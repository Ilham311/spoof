#!/system/bin/sh
# Surgical SSAID rewrite - callable from ternak_core CLI
# Requires: DATA_DIR, STATE_DIR, log_* functions from ternak_core

SSAID_TARGETS_FILE="${SSAID_TARGETS_FILE:-$STATE_DIR/ssaid_targets.conf}"
SSAID_VALUE_FILE="${SSAID_VALUE_FILE:-$STATE_DIR/ssaid_value.txt}"
SSAID_BACKUP_DIR="${SSAID_BACKUP_DIR:-$DATA_DIR/ssaid_backup}"

# Write SSAID config: value + target packages
ssaid_write_config() {
    local value="$1"; shift
    case "$value" in ''|*[!0-9a-f]*) log_err "Invalid SSAID (need 16 hex)"; return 1 ;; esac
    [ "${#value}" -ne 16 ] && { log_err "SSAID must be 16 hex chars"; return 1; }

    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s' "$value" > "$SSAID_VALUE_FILE"
    chmod 600 "$SSAID_VALUE_FILE" 2>/dev/null

    : > "$SSAID_TARGETS_FILE"
    for pkg in "$@"; do
        case "$pkg" in ''|*[!A-Za-z0-9._]*) continue ;; esac
        echo "$pkg" >> "$SSAID_TARGETS_FILE"
    done
    chmod 600 "$SSAID_TARGETS_FILE" 2>/dev/null
    log_ok "SSAID config: value=$value targets=$#"
}

# Apply surgical SSAID rewrite immediately (CLI mode).
# Note: system_server holds cache; for guaranteed effect,
# either reboot OR force-stop target apps + kill system_server
# (aggressive, may need reboot anyway).
ssaid_apply_now() {
    [ -f "$SSAID_VALUE_FILE" ] || { log_err "SSAID: no value configured"; return 1; }
    [ -f "$SSAID_TARGETS_FILE" ] || { log_err "SSAID: no targets configured"; return 1; }

    local new_ssaid users u abx2xml="" xml2abx=""
    new_ssaid="$(cat "$SSAID_VALUE_FILE")"
    users="$(ls /data/system/users/ 2>/dev/null | grep -E '^[0-9]+$')"
    [ -z "$users" ] && users="0"
    [ -x /system/bin/abx2xml ] && abx2xml=/system/bin/abx2xml
    [ -x /system/bin/xml2abx ] && xml2abx=/system/bin/xml2abx

    mkdir -p "$SSAID_BACKUP_DIR" 2>/dev/null
    chmod 700 "$SSAID_BACKUP_DIR" 2>/dev/null

    local total_changed=0
    for u in $users; do
        local ssaid_file="/data/system/users/$u/settings_ssaid.xml"
        [ -f "$ssaid_file" ] || continue

        local backup="$SSAID_BACKUP_DIR/user${u}_settings_ssaid.xml.orig"
        [ ! -f "$backup" ] && cp "$ssaid_file" "$backup" 2>/dev/null && chmod 600 "$backup" 2>/dev/null

        local magic is_abx=0
        magic="$(dd if="$ssaid_file" bs=1 count=3 2>/dev/null)"
        [ "$magic" = "ABX" ] && is_abx=1

        local plain="$DATA_DIR/.ssaid_${u}.$$.xml"
        if [ "$is_abx" = "1" ]; then
            [ -z "$abx2xml" ] && { log_warn "user=$u ABX but no abx2xml, skip"; continue; }
            $abx2xml "$ssaid_file" "$plain" 2>/dev/null || { rm -f "$plain"; continue; }
        else
            cp "$ssaid_file" "$plain" 2>/dev/null || continue
        fi

        local changed=0 pkg esc
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            case "$pkg" in \#*) continue ;; esac
            if grep -qF "package=\"${pkg}\"" "$plain" 2>/dev/null; then
                esc="$(printf '%s' "$pkg" | sed 's/\./\\./g')"
                sed -i "/package=\"${esc}\"/ s/ value=\"[^\"]*\"/ value=\"${new_ssaid}\"/" "$plain"
                changed=$((changed+1))
            fi
        done < "$SSAID_TARGETS_FILE"

        if [ "$changed" -eq 0 ]; then rm -f "$plain"; continue; fi

        if [ "$is_abx" = "1" ]; then
            local abx_out="$DATA_DIR/.ssaid_${u}.$$.abx"
            if $xml2abx "$plain" "$abx_out" 2>/dev/null && [ -s "$abx_out" ]; then
                cat "$abx_out" > "$ssaid_file"
                rm -f "$abx_out"
            else
                rm -f "$plain" "$abx_out"; log_err "xml2abx failed user=$u"; continue
            fi
        else
            cat "$plain" > "$ssaid_file"
        fi
        rm -f "$plain"

        chmod 600 "$ssaid_file"
        chown 1000:1000 "$ssaid_file" 2>/dev/null
        restorecon "$ssaid_file" 2>/dev/null

        total_changed=$((total_changed + changed))
        log_ok "SSAID user=$u: rewrote $changed pkg (abx=$is_abx)"
    done

    if [ "$total_changed" -gt 0 ]; then
        log_warn "CLI apply: system_server may cache old SSAID. Force-stop target apps NOW, or reboot for guaranteed effect."
    fi
}

# Restore original SSAID values for target packages
ssaid_revert() {
    local users u
    users="$(ls /data/system/users/ 2>/dev/null | grep -E '^[0-9]+$')"
    [ -z "$users" ] && users="0"
    for u in $users; do
        local backup="$SSAID_BACKUP_DIR/user${u}_settings_ssaid.xml.orig"
        [ -f "$backup" ] || continue
        cp "$backup" "/data/system/users/$u/settings_ssaid.xml"
        chmod 600 "/data/system/users/$u/settings_ssaid.xml"
        chown 1000:1000 "/data/system/users/$u/settings_ssaid.xml" 2>/dev/null
        restorecon "/data/system/users/$u/settings_ssaid.xml" 2>/dev/null
        log_ok "SSAID user=$u: restored from backup"
    done
}
