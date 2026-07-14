#!/system/bin/sh
# Ternak v4.15 - freeze-on-activate token resolver.
# Tokens: ${RANDOM_HEX:N}, ${RANDOM_SERIAL}, ${RANDOM_UUID},
#         ${RANDOM_MAC:OUI_HEX6}, ${RANDOM_BT_MAC:OUI_HEX6}, ${RANDOM_IMEI:TAC}

generate_hex() {
    local N=${1:-16}
    case "$N" in ''|*[!0-9]*) N=16 ;; esac
    [ "$N" -lt 1 ] && N=16
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c "$N"
}

generate_serial() {
    # 12-char alphanumeric uppercase (Google format)
    LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 12
}

generate_uuid() {
    # RFC4122 v4 UUID with correct variant bits (fixes v4.13 bug #2)
    local A B C D E
    A=$(generate_hex 8)
    B=$(generate_hex 4)
    C="4$(generate_hex 3)"                          # version 4
    local Y=$(LC_ALL=C tr -dc '89ab' < /dev/urandom | head -c 1)
    D="${Y}$(generate_hex 3)"                       # variant 10
    E=$(generate_hex 12)
    printf '%s-%s-%s-%s-%s' "$A" "$B" "$C" "$D" "$E"
}

generate_mac() {
    # OUI-anchored MAC. OUI arg is 6 hex chars without separator, e.g. "3c5ab4"
    local OUI="$1"
    case "$OUI" in
        '' | *[!0-9a-fA-F]* ) OUI="3c5ab4" ;;  # Google default OUI
    esac
    [ "${#OUI}" -ne 6 ] && OUI="3c5ab4"
    local NIC=$(generate_hex 6)
    printf '%s:%s:%s:%s:%s:%s' \
        "${OUI:0:2}" "${OUI:2:2}" "${OUI:4:2}" \
        "${NIC:0:2}" "${NIC:2:2}" "${NIC:4:2}"
}

generate_imei() {
    # 15-digit IMEI: 8-digit TAC + 6-digit serial + Luhn check digit
    local TAC="$1"
    case "$TAC" in ''|*[!0-9]*) TAC="35892611" ;; esac  # Pixel 7 Pro TAC
    [ "${#TAC}" -ne 8 ] && TAC="35892611"
    local SN=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 6)
    local BASE="${TAC}${SN}"
    # Luhn checksum
    local I=0 SUM=0 D DBL
    while [ "$I" -lt 14 ]; do
        D=$(printf '%s' "$BASE" | cut -c$((14 - I)))
        if [ $((I % 2)) -eq 0 ]; then
            DBL=$((D * 2))
            [ "$DBL" -ge 10 ] && DBL=$((DBL - 9))
            SUM=$((SUM + DBL))
        else
            SUM=$((SUM + D))
        fi
        I=$((I + 1))
    done
    local CHK=$(( (10 - SUM % 10) % 10 ))
    printf '%s%s' "$BASE" "$CHK"
}

replace_first() {
    local TEXT="$1" NEEDLE="$2" REPL="$3" PREFIX SUFFIX
    PREFIX=${TEXT%%"$NEEDLE"*}
    SUFFIX=${TEXT#*"$NEEDLE"}
    printf '%s%s%s' "$PREFIX" "$REPL" "$SUFFIX"
}

resolve_value() {
    local V="$1" TOKEN ARG REPL GUARD=0
    while [ "$GUARD" -lt 20 ]; do
        GUARD=$((GUARD + 1))
        case "$V" in
            *'${RANDOM_HEX:'*'}'*)
                TOKEN=$(printf '%s' "$V" | sed -n 's/.*\(\${RANDOM_HEX:[0-9][0-9]*}\).*/\1/p')
                [ -z "$TOKEN" ] && break
                ARG=$(printf '%s' "$TOKEN" | sed 's/.*:\([0-9][0-9]*\)}/\1/')
                REPL=$(generate_hex "$ARG")
                V=$(replace_first "$V" "$TOKEN" "$REPL") ;;
            *'${RANDOM_SERIAL}'*)
                REPL=$(generate_serial)
                V=$(replace_first "$V" '${RANDOM_SERIAL}' "$REPL") ;;
            *'${RANDOM_UUID}'*)
                REPL=$(generate_uuid)
                V=$(replace_first "$V" '${RANDOM_UUID}' "$REPL") ;;
            *'${RANDOM_MAC:'*'}'*)
                TOKEN=$(printf '%s' "$V" | sed -n 's/.*\(\${RANDOM_MAC:[0-9a-fA-F][0-9a-fA-F]*}\).*/\1/p')
                [ -z "$TOKEN" ] && break
                ARG=$(printf '%s' "$TOKEN" | sed 's/.*:\([0-9a-fA-F]*\)}/\1/')
                REPL=$(generate_mac "$ARG")
                V=$(replace_first "$V" "$TOKEN" "$REPL") ;;
            *'${RANDOM_BT_MAC:'*'}'*)
                TOKEN=$(printf '%s' "$V" | sed -n 's/.*\(\${RANDOM_BT_MAC:[0-9a-fA-F][0-9a-fA-F]*}\).*/\1/p')
                [ -z "$TOKEN" ] && break
                ARG=$(printf '%s' "$TOKEN" | sed 's/.*:\([0-9a-fA-F]*\)}/\1/')
                REPL=$(generate_mac "$ARG")
                V=$(replace_first "$V" "$TOKEN" "$REPL") ;;
            *'${RANDOM_IMEI:'*'}'*)
                TOKEN=$(printf '%s' "$V" | sed -n 's/.*\(\${RANDOM_IMEI:[0-9][0-9]*}\).*/\1/p')
                [ -z "$TOKEN" ] && break
                ARG=$(printf '%s' "$TOKEN" | sed 's/.*:\([0-9]*\)}/\1/')
                REPL=$(generate_imei "$ARG")
                V=$(replace_first "$V" "$TOKEN" "$REPL") ;;
            *) break ;;
        esac
    done
    case "$V" in
        *'${RANDOM_'*) log "persona_freeze: unresolved token in: $V"; return 1 ;;
    esac
    printf '%s' "$V"
}

has_generator_token() {
    case "$1" in *'${RANDOM_'*) return 0 ;; *) return 1 ;; esac
}

freeze_config_file() {
    # Freeze all ${RANDOM_*} tokens in a conf file. Format: STATUS,PROP,VALUE
    local FILE="$1" TMP="${1}.tmp.$$"
    local LINE STATUS REST PROP RAW VALUE CHANGED=0
    [ -f "$FILE" ] || return 0
    grep -qF '${RANDOM_' "$FILE" 2>/dev/null || return 0
    : > "$TMP" || return 1
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        case "$LINE" in
            ''|'#'*)
                printf '%s\n' "$LINE" >> "$TMP" ; continue ;;
            *'${RANDOM_'*) ;;
            *)
                printf '%s\n' "$LINE" >> "$TMP" ; continue ;;
        esac
        STATUS=${LINE%%,*}
        REST=${LINE#*,}
        PROP=${REST%%,*}
        RAW=${REST#*,}
        if [ -n "$PROP" ] && has_generator_token "$RAW"; then
            VALUE=$(resolve_value "$RAW") || { rm -f "$TMP"; return 1; }
            printf '%s,%s,%s\n' "$STATUS" "$PROP" "$VALUE" >> "$TMP"
            CHANGED=1
        else
            printf '%s\n' "$LINE" >> "$TMP"
        fi
    done < "$FILE"
    if [ "$CHANGED" -eq 1 ]; then
        chmod 600 "$TMP" 2>/dev/null
        mv -f "$TMP" "$FILE"
    else
        rm -f "$TMP"
    fi
}

freeze_persona() {
    local PDIR="$1" CONF
    for CONF in build.conf identifiers.conf mac_pool.conf android_id.conf; do
        [ -f "${PDIR}/${CONF}" ] && freeze_config_file "${PDIR}/${CONF}"
    done
    log "Persona frozen: ${PDIR##*/}"
}
