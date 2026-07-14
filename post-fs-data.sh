#!/system/bin/sh
# shellcheck shell=sh
# ============================================================
# Ternak v4.14.0 - Pre-Zygote Stage
# Applies persona props, SSAID, and GAID BEFORE zygote starts.
# Eliminates GAID drift, SSAID reboot requirement, and
# cross-partition FP race conditions.
# ============================================================

MODDIR="${0%/*}"
DATA_DIR="/data/adb/ternak_device_changer"
STATE_DIR="$DATA_DIR/state"
LOG_FILE="$DATA_DIR/logs/post-fs-data.log"
ACTIVE_PERSONA_FILE="$STATE_DIR/active_persona.txt"
SSAID_TARGETS_FILE="$STATE_DIR/ssaid_targets.conf"
SSAID_VALUE_FILE="$STATE_DIR/ssaid_value.txt"
GAID_VALUE_FILE="$STATE_DIR/gaid_value.txt"

mkdir -p "$STATE_DIR" "$DATA_DIR/logs" 2>/dev/null
chmod 700 "$DATA_DIR" "$STATE_DIR" "$DATA_DIR/logs" 2>/dev/null

log() {
    local m="[$(date '+%Y-%m-%d %H:%M:%S')] [pfd] $1"
    echo "$m" >> "$LOG_FILE" 2>/dev/null
}

# Skip if module disabled or no persona active
[ -f "$MODDIR/disable" ] && { log "Module disabled, skip"; exit 0; }
[ -f "$ACTIVE_PERSONA_FILE" ] || { log "No active persona, skip"; exit 0; }

ACTIVE_PERSONA="$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \t\n\r')"
[ -z "$ACTIVE_PERSONA" ] && { log "Persona file empty, skip"; exit 0; }

log "=== Pre-zygote stage start (persona=$ACTIVE_PERSONA) ==="

# ---- Resolve resetprop ----
RESETPROP=""
for CAND in "$MODDIR/bin/resetprop-rs" \
            /data/adb/ksu/bin/resetprop \
            /data/adb/ap/bin/resetprop \
            /data/adb/magisk/magisk \
            /data/adb/magisk/resetprop; do
    if [ -x "$CAND" ]; then
        case "$CAND" in
            */magisk) RESETPROP="$CAND resetprop" ;;
            *) RESETPROP="$CAND" ;;
        esac
        break
    fi
done
[ -z "$RESETPROP" ] && { log "ERROR: no resetprop"; exit 0; }
log "resetprop=$RESETPROP"

# ---- Safety allowlist (fail-closed) ----
is_safe_identity_prop() {
    case "$1" in
        ro.product.brand|ro.product.manufacturer|ro.product.model|\
        ro.product.name|ro.product.device|ro.product.board|\
        ro.product.system.*|ro.product.system_ext.*|ro.product.product.*|\
        ro.product.vendor.*|ro.product.odm.*)
            return 0 ;;
        ro.build.fingerprint|ro.build.id|ro.build.display.id|\
        ro.build.version.incremental|ro.build.version.security_patch|\
        ro.build.version.release|ro.build.version.codename|\
        ro.build.type|ro.build.tags|ro.build.description|\
        ro.build.flavor|ro.build.product|ro.build.characteristics)
            return 0 ;;
        ro.product.build.*|ro.system.build.*|ro.system_ext.build.*|\
        ro.vendor.build.*|ro.odm.build.*|ro.bootimage.build.*)
            return 0 ;;
        ro.vendor.product.*|ro.vendor.build.security_patch)
            return 0 ;;
        ro.serialno|ro.boot.serialno|ro.bootloader|\
        ro.boot.hwname|ro.boot.hwdevice|ro.product.hardware.sku|\
        ro.boot.product.hardware.sku|ro.build.device_family|\
        vendor.usb.product_string)
            return 0 ;;
        ro.soc.model|ro.soc.manufacturer|ro.product.first_api_level)
            return 0 ;;
    esac
    return 1
}

# ---- Token resolver ----
resolve_value() {
    local v="$1" tok len rep
    while :; do
        case "$v" in
            *'${RANDOM_HEX:'*'}'*)
                tok=$(printf '%s' "$v" | sed -n 's/.*\(\${RANDOM_HEX:[0-9]*}\).*/\1/p')
                [ -z "$tok" ] && break
                len=$(printf '%s' "$tok" | sed 's/${RANDOM_HEX:\([0-9]*\)}/\1/')
                rep=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c "$len")
                v="${v%%"$tok"*}${rep}${v#*"$tok"}"
                ;;
            *'${RANDOM_SERIAL}'*)
                rep=$(LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 12)
                v="${v%%'${RANDOM_SERIAL}'*}${rep}${v#*'${RANDOM_SERIAL}'}"
                ;;
            *) break ;;
        esac
    done
    printf '%s' "$v"
}

# ---- 1. Apply persona props ----
apply_persona_props() {
    local persona_file=""
    if [ -f "$STATE_DIR/resolved_persona.txt" ]; then
        persona_file="$STATE_DIR/resolved_persona.txt"
        log "Using frozen resolved persona snapshot"
    else
        for base in "$MODDIR/personas" "$MODDIR/personas/custom"; do
            [ -f "$base/${ACTIVE_PERSONA}.txt" ] && { persona_file="$base/${ACTIVE_PERSONA}.txt"; break; }
        done
    fi
    [ -z "$persona_file" ] && { log "ERROR: persona '$ACTIVE_PERSONA' file missing"; return 1; }

    log "Applying persona: $persona_file"
    local applied=0 skipped=0 unsafe=0 line key val
    while IFS= read -r line || [ -n "$line" ]; do
        # strip inline comment
        line="$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//')"
        case "$line" in ''|\#*) continue ;; esac
        key="$(printf '%s' "${line%%=*}" | awk '{gsub(/^[ \t]+|[ \t]+$/,""); print}')"
        val="$(printf '%s' "${line#*=}" | awk '{gsub(/^[ \t]+|[ \t]+$/,""); print}')"
        [ -z "$key" ] || [ -z "$val" ] && continue

        # Safety: reject non-identity props
        if ! is_safe_identity_prop "$key"; then
            log "SAFETY skip: $key (not in allowlist)"
            unsafe=$((unsafe+1))
            continue
        fi

        # Skip SDK override (never spoof, always breaks something)
        [ "$key" = "ro.build.version.sdk" ] && { skipped=$((skipped+1)); continue; }

        # Resolve tokens
        val="$(resolve_value "$val")"

        if $RESETPROP -n "$key" "$val" 2>/dev/null; then
            applied=$((applied+1))
        else
            skipped=$((skipped+1))
        fi
    done < "$persona_file"
    log "Persona apply: applied=$applied skipped=$skipped unsafe_rejected=$unsafe"
}

# ---- 2. Surgical SSAID rewrite ----
apply_ssaid_surgical() {
    [ -f "$SSAID_TARGETS_FILE" ] || { log "SSAID: no targets"; return 0; }
    [ -f "$SSAID_VALUE_FILE" ] || { log "SSAID: no value stored"; return 0; }

    local new_ssaid users u
    new_ssaid="$(cat "$SSAID_VALUE_FILE" 2>/dev/null | tr -d ' \t\n\r')"
    case "$new_ssaid" in ''|*[!0-9a-f]*) log "SSAID: invalid value"; return 1 ;; esac
    [ "${#new_ssaid}" -ne 16 ] && { log "SSAID: value must be 16 hex"; return 1; }

    users="$(ls /data/system/users/ 2>/dev/null | grep -E '^[0-9]+$')"
    [ -z "$users" ] && users="0"

    local abx2xml="" xml2abx=""
    [ -x /system/bin/abx2xml ] && abx2xml=/system/bin/abx2xml
    [ -x /system/bin/xml2abx ] && xml2abx=/system/bin/xml2abx

    for u in $users; do
        local ssaid_file="/data/system/users/$u/settings_ssaid.xml"
        [ -f "$ssaid_file" ] || continue

        # Backup once
        local backup="$DATA_DIR/ssaid_backup/user${u}_settings_ssaid.xml.orig"
        mkdir -p "$DATA_DIR/ssaid_backup" 2>/dev/null
        chmod 700 "$DATA_DIR/ssaid_backup" 2>/dev/null
        [ ! -f "$backup" ] && cp "$ssaid_file" "$backup" 2>/dev/null && chmod 600 "$backup" 2>/dev/null

        # Detect ABX (binary XML on Android 13+)
        local magic is_abx=0
        magic="$(dd if="$ssaid_file" bs=1 count=3 2>/dev/null)"
        [ "$magic" = "ABX" ] && is_abx=1

        local plain="$DATA_DIR/.ssaid_${u}.$$.xml"
        if [ "$is_abx" = "1" ]; then
            [ -z "$abx2xml" ] && { log "SSAID user=$u: ABX detected but abx2xml missing"; continue; }
            $abx2xml "$ssaid_file" "$plain" 2>/dev/null || { log "SSAID user=$u: abx2xml failed"; rm -f "$plain"; continue; }
        else
            cp "$ssaid_file" "$plain" 2>/dev/null || continue
        fi
        chmod 600 "$plain" 2>/dev/null

        # Rewrite value for each target package
        local changed=0 pkg esc
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            case "$pkg" in \#*) continue ;; esac
            if grep -qF "package=\"${pkg}\"" "$plain" 2>/dev/null; then
                esc="$(printf '%s' "$pkg" | sed 's/\./\\./g')"
                sed -i "/package=\"${esc}\"/ s/ value=\"[^\"]*\"/ value=\"${new_ssaid}\"/" "$plain" 2>/dev/null
                changed=$((changed+1))
            fi
        done < "$SSAID_TARGETS_FILE"

        if [ "$changed" -eq 0 ]; then
            rm -f "$plain"
            log "SSAID user=$u: no target packages have entries yet (open app once)"
            continue
        fi

        # Write back
        if [ "$is_abx" = "1" ]; then
            local abx_out="$DATA_DIR/.ssaid_${u}.$$.abx"
            if ! $xml2abx "$plain" "$abx_out" 2>/dev/null || [ ! -s "$abx_out" ]; then
                log "SSAID user=$u: xml2abx failed"
                rm -f "$plain" "$abx_out"; continue
            fi
            cat "$abx_out" > "$ssaid_file" 2>/dev/null
            rm -f "$abx_out"
        else
            [ -s "$plain" ] && cat "$plain" > "$ssaid_file" 2>/dev/null
        fi
        rm -f "$plain"

        chmod 600 "$ssaid_file" 2>/dev/null
        chown 1000:1000 "$ssaid_file" 2>/dev/null
        restorecon "$ssaid_file" 2>/dev/null || chcon u:object_r:system_data_file:s0 "$ssaid_file" 2>/dev/null
        log "SSAID user=$u: rewrote $changed package(s) to $new_ssaid (abx=$is_abx)"
    done
}

# ---- 3. Pre-zygote GAID (before GMS starts) ----
apply_gaid_prezygote() {
    [ -f "$GAID_VALUE_FILE" ] || return 0
    local gaid now_ms
    gaid="$(cat "$GAID_VALUE_FILE" 2>/dev/null | tr -d ' \t\n\r')"
    case "$gaid" in
        [0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*) : ;;
        *) log "GAID: invalid uuid format"; return 1 ;;
    esac
    now_ms="$(date +%s)000"

    mkdir -p /data/data/com.google.android.gms/shared_prefs 2>/dev/null
    cat > /data/data/com.google.android.gms/shared_prefs/adid_settings.xml <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <int name="version" value="1" />
    <string name="adid_key">$gaid</string>
    <boolean name="enable_limit_ad_tracking" value="false" />
    <long name="last_reset_time" value="$now_ms" />
    <long name="last_generated_at" value="$now_ms" />
</map>
EOF
    local gms_owner
    gms_owner="$(stat -c '%u:%g' /data/data/com.google.android.gms 2>/dev/null)"
    [ -n "$gms_owner" ] && chown "$gms_owner" /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    chmod 660 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    restorecon /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    log "GAID set pre-zygote: $gaid"
}

# ---- Main sequence ----
apply_persona_props
apply_ssaid_surgical
apply_gaid_prezygote

log "=== Pre-zygote stage complete ==="
