#!/system/bin/sh
# Ternak v4.15 - ABX-aware SSAID rewriter with per-package precision + revert.
# Ported and extended from DSL (yubunus/DeviceSpoofLab-Magisk).

AI_APPLIED_COUNT=0
AI_SKIPPED_PKGS=""
AI_TARGET_COUNT=0
AI_ERROR=""
AI_ABX2XML=""
AI_XML2ABX=""

ai_valid_value() {
    case "$1" in
        '' | *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 16 ]
}

ai_valid_pkg() {
    case "$1" in
        '' | *[!A-Za-z0-9._]*) return 1 ;;
        *) return 0 ;;
    esac
}

ai_valid_user() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

ai_ssaid_path() {
    printf '/data/system/users/%s/settings_ssaid.xml' "$1"
}

ai_is_abx() {
    local FILE="$1" MAGIC
    MAGIC=$(dd if="$FILE" bs=1 count=3 2>/dev/null)
    [ "$MAGIC" = "ABX" ]
}

ai_resolve_abx_tools() {
    AI_ABX2XML="$(command -v abx2xml 2>/dev/null)"
    AI_XML2ABX="$(command -v xml2abx 2>/dev/null)"
    [ -n "$AI_ABX2XML" ] || { [ -x /system/bin/abx2xml ] && AI_ABX2XML=/system/bin/abx2xml; }
    [ -n "$AI_XML2ABX" ] || { [ -x /system/bin/xml2abx ] && AI_XML2ABX=/system/bin/xml2abx; }
    [ -n "$AI_ABX2XML" ] && [ -n "$AI_XML2ABX" ]
}

ai_backup_ssaid() {
    local AUSER="$1" FILE="$2" DEST
    DEST="${SSAID_BACKUP_DIR}/user${AUSER}_settings_ssaid.xml.orig"
    [ -f "$DEST" ] && return 0
    mkdir -p "$SSAID_BACKUP_DIR" 2>/dev/null
    chmod 700 "$SSAID_BACKUP_DIR" 2>/dev/null
    if cp "$FILE" "$DEST" 2>/dev/null; then
        chmod 600 "$DEST" 2>/dev/null
        log "[ssaid] backed up original for user ${AUSER}"
    fi
}

ai_rewrite_plain() {
    # Rewrite plaintext XML: replace value="..." for each target package.
    local XML="$1" NEW="$2" PKG ESC TMP
    TMP="${XML}.r.$$"
    AI_APPLIED_COUNT=0
    AI_SKIPPED_PKGS=""
    while IFS= read -r PKG; do
        [ -n "$PKG" ] || continue
        if grep -qF "package=\"${PKG}\"" "$XML" 2>/dev/null; then
            ESC=$(printf '%s' "$PKG" | sed 's/\./\\./g')
            if sed "/package=\"${ESC}\"/ s/ value=\"[^\"]*\"/ value=\"${NEW}\"/" \
                   "$XML" > "$TMP" 2>/dev/null; then
                mv -f "$TMP" "$XML" 2>/dev/null
                AI_APPLIED_COUNT=$((AI_APPLIED_COUNT + 1))
            else
                rm -f "$TMP"
                AI_SKIPPED_PKGS="${AI_SKIPPED_PKGS} ${PKG}"
            fi
        else
            AI_SKIPPED_PKGS="${AI_SKIPPED_PKGS} ${PKG}"
        fi
    done
    AI_SKIPPED_PKGS="${AI_SKIPPED_PKGS# }"
}

ai_apply_user() {
    # Apply NEW ssaid value to all TARGET packages in $3+ for user $1.
    local AUSER="$1" VALUE="$2"
    shift 2
    local FILE PLAIN ABX_OUT IS_ABX=0 TGT_FILE
    AI_APPLIED_COUNT=0
    AI_SKIPPED_PKGS=""
    AI_ERROR=""

    ai_valid_value "$VALUE" || { AI_ERROR="Invalid SSAID value (need 16 hex)"; return 1; }
    ai_valid_user "$AUSER" || { AI_ERROR="Invalid user id"; return 1; }

    FILE=$(ai_ssaid_path "$AUSER")
    [ -f "$FILE" ] || { AI_ERROR="No SSAID store: $FILE"; return 1; }

    ai_backup_ssaid "$AUSER" "$FILE"

    mkdir -p "$DATA_DIR" 2>/dev/null
    PLAIN="${DATA_DIR}/.ssaid_${AUSER}.$$.xml"

    if ai_is_abx "$FILE"; then
        IS_ABX=1
        ai_resolve_abx_tools || { AI_ERROR="ABX tools unavailable"; return 1; }
        if ! "$AI_ABX2XML" "$FILE" "$PLAIN" 2>/dev/null; then
            rm -f "$PLAIN"; AI_ERROR="abx2xml failed"; return 1
        fi
    else
        cp "$FILE" "$PLAIN" 2>/dev/null || { rm -f "$PLAIN"; AI_ERROR="read fail"; return 1; }
    fi
    chmod 600 "$PLAIN" 2>/dev/null

    TGT_FILE="${DATA_DIR}/.ssaid_tgt.$$"
    : > "$TGT_FILE"
    local P
    for P in "$@"; do
        ai_valid_pkg "$P" && printf '%s\n' "$P" >> "$TGT_FILE"
    done
    ai_rewrite_plain "$PLAIN" "$VALUE" < "$TGT_FILE"
    rm -f "$TGT_FILE"

    if [ "$AI_APPLIED_COUNT" -eq 0 ]; then
        rm -f "$PLAIN"
        log "[ssaid] user ${AUSER}: no matching packages (open app once first!)"
        return 0
    fi

    if [ "$IS_ABX" -eq 1 ]; then
        ABX_OUT="${DATA_DIR}/.ssaid_${AUSER}.$$.abx"
        if ! "$AI_XML2ABX" "$PLAIN" "$ABX_OUT" 2>/dev/null || [ ! -s "$ABX_OUT" ]; then
            rm -f "$PLAIN" "$ABX_OUT"; AI_ERROR="xml2abx failed"; return 1
        fi
        if ! cat "$ABX_OUT" > "$FILE" 2>/dev/null; then
            rm -f "$PLAIN" "$ABX_OUT"; AI_ERROR="write fail"; return 1
        fi
        rm -f "$ABX_OUT"
    else
        [ -s "$PLAIN" ] || { rm -f "$PLAIN"; AI_ERROR="empty plain"; return 1; }
        if ! cat "$PLAIN" > "$FILE" 2>/dev/null; then
            rm -f "$PLAIN"; AI_ERROR="write fail"; return 1
        fi
    fi
    rm -f "$PLAIN"

    chmod 600 "$FILE" 2>/dev/null
    chown 1000:1000 "$FILE" 2>/dev/null
    restorecon "$FILE" 2>/dev/null || chcon u:object_r:system_data_file:s0 "$FILE" 2>/dev/null

    log "[ssaid] user ${AUSER}: set ${AI_APPLIED_COUNT} pkg(s) to ${VALUE}${IS_ABX:+ (ABX)}${AI_SKIPPED_PKGS:+ skip:${AI_SKIPPED_PKGS}}"
    return 0
}

ai_record_applied() {
    local USER="$1"
    shift
    {
        echo "USER=${USER}"
        echo "TIMESTAMP=$(date +%s)"
        local P
        for P in "$@"; do
            ai_valid_pkg "$P" && echo "PKG=${P}"
        done
    } > "$SSAID_APPLIED_STATE" 2>/dev/null
    chmod 600 "$SSAID_APPLIED_STATE" 2>/dev/null
}

ai_value_for_pkg() {
    local F="$1" PKG="$2" LINE
    LINE=$(grep -m1 "package=\"${PKG}\"" "$F" 2>/dev/null) || return 1
    printf '%s' "$LINE" | sed -n 's/.* value="\([^"]*\)".*/\1/p'
}

ai_set_pkg_value() {
    local XML="$1" PKG="$2" VAL="$3" ESC TMP
    TMP="${XML}.s.$$"
    ESC=$(printf '%s' "$PKG" | sed 's/\./\\./g')
    if sed "/package=\"${ESC}\"/ s/ value=\"[^\"]*\"/ value=\"${VAL}\"/" \
           "$XML" > "$TMP" 2>/dev/null; then
        mv -f "$TMP" "$XML" 2>/dev/null
    else
        rm -f "$TMP"
    fi
}

ai_restore_targets() {
    # Precise per-package revert: restore original SSAID for listed packages only.
    local AUSER="$1"
    shift
    ai_valid_user "$AUSER" || return 1
    [ "$#" -gt 0 ] || return 0

    local FILE DEST PLAIN BPLAIN ABX_OUT IS_ABX=0 PKG ORIG CHANGED=0
    FILE=$(ai_ssaid_path "$AUSER")
    DEST="${SSAID_BACKUP_DIR}/user${AUSER}_settings_ssaid.xml.orig"
    [ -f "$DEST" ] && [ -f "$FILE" ] || return 0

    PLAIN="${DATA_DIR}/.ssaid_rv_${AUSER}.$$.xml"
    BPLAIN="${DATA_DIR}/.ssaid_bk_${AUSER}.$$.xml"

    if ai_is_abx "$FILE"; then
        IS_ABX=1
        ai_resolve_abx_tools || { AI_ERROR="abx tools"; return 1; }
        "$AI_ABX2XML" "$FILE" "$PLAIN" 2>/dev/null || return 1
    else
        cp "$FILE" "$PLAIN" 2>/dev/null || return 1
    fi
    if ai_is_abx "$DEST"; then
        ai_resolve_abx_tools || return 1
        "$AI_ABX2XML" "$DEST" "$BPLAIN" 2>/dev/null || return 1
    else
        cp "$DEST" "$BPLAIN" 2>/dev/null || return 1
    fi

    for PKG in "$@"; do
        ai_valid_pkg "$PKG" || continue
        ORIG=$(ai_value_for_pkg "$BPLAIN" "$PKG") || continue
        ai_valid_value "$ORIG" || continue
        if grep -qF "package=\"${PKG}\"" "$PLAIN" 2>/dev/null; then
            ai_set_pkg_value "$PLAIN" "$PKG" "$ORIG"
            CHANGED=1
        fi
    done

    [ "$CHANGED" -eq 0 ] && { rm -f "$PLAIN" "$BPLAIN"; return 0; }

    if [ "$IS_ABX" -eq 1 ]; then
        ABX_OUT="${DATA_DIR}/.ssaid_rv_${AUSER}.$$.abx"
        "$AI_XML2ABX" "$PLAIN" "$ABX_OUT" 2>/dev/null || { rm -f "$PLAIN" "$BPLAIN" "$ABX_OUT"; return 1; }
        [ -s "$ABX_OUT" ] || { rm -f "$PLAIN" "$BPLAIN" "$ABX_OUT"; return 1; }
        cat "$ABX_OUT" > "$FILE" 2>/dev/null
        rm -f "$ABX_OUT"
    else
        cat "$PLAIN" > "$FILE" 2>/dev/null
    fi
    rm -f "$PLAIN" "$BPLAIN"

    chmod 600 "$FILE" 2>/dev/null
    chown 1000:1000 "$FILE" 2>/dev/null
    restorecon "$FILE" 2>/dev/null
    log "[ssaid] reverted user ${AUSER} for listed package(s)"
    return 0
}

ai_revert_last_applied() {
    [ -f "$SSAID_APPLIED_STATE" ] || return 0
    local U T
    U=$(grep -m1 '^USER=' "$SSAID_APPLIED_STATE" 2>/dev/null | sed 's/^USER=//')
    T=$(grep '^PKG=' "$SSAID_APPLIED_STATE" 2>/dev/null | sed 's/^PKG=//')
    if [ -n "$T" ]; then
        ai_restore_targets "$U" $T || return 1
    fi
    rm -f "$SSAID_APPLIED_STATE" 2>/dev/null
    return 0
}
