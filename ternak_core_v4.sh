#!/system/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC3043,SC2155,SC2086,SC2034,SC2046,SC2015,SC2317
# ============================================================
# Ternak Device Changer - Core Engine v4.12.4 (Android 15)
# REWRITTEN FOR SECURITY, PERFORMANCE & STABILITY
# ============================================================

VERSION="4.14.0-a15-rs"

MODDIR="${MODDIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
[ -z "$MODDIR" ] && MODDIR="/data/adb/modules/ternak_device_changer"

# NEW: persistent state outside module dir (survives reinstall)
DATA_DIR="/data/adb/ternak_device_changer"
STATE_DIR="$DATA_DIR/state"
SSAID_STATE_DIR="$DATA_DIR/ssaid_backup"
SSAID_TARGETS_FILE="$STATE_DIR/ssaid_targets.conf"
SSAID_VALUE_FILE="$STATE_DIR/ssaid_value.txt"
GAID_VALUE_FILE="$STATE_DIR/gaid_value.txt"

# Keep MODDIR-based paths for persona files & logs (read-only, shipped in module)
PERSONA_DIR="$MODDIR/personas"
LOG_DIR="$DATA_DIR/logs"       # moved to DATA_DIR
BACKUP_DIR_ROOT="$DATA_DIR/backups"  # moved to DATA_DIR
ACTIVE_PERSONA_FILE="$STATE_DIR/active_persona.txt"  # moved to DATA_DIR
LOCKFILE="$STATE_DIR/.lock"
SYSPROP_FILE="$MODDIR/system.prop"
SETTINGS_FILE="$MODDIR/sett.txt"

mkdir -p "$DATA_DIR" "$STATE_DIR" "$LOG_DIR" "$BACKUP_DIR_ROOT" "$SSAID_STATE_DIR" 2>/dev/null
chmod 700 "$DATA_DIR" "$STATE_DIR" "$LOG_DIR" "$BACKUP_DIR_ROOT" "$SSAID_STATE_DIR" 2>/dev/null

# Migrate from v4.13.0 paths if legacy state exists
LEGACY_STATE="$MODDIR/state"
if [ -d "$LEGACY_STATE" ] && [ ! -f "$STATE_DIR/.migrated" ]; then
    cp -a "$LEGACY_STATE/." "$STATE_DIR/" 2>/dev/null
    touch "$STATE_DIR/.migrated"
    log_ok "Migrated v4.13.0 state → $STATE_DIR"
fi

# Source surgical SSAID helper
[ -f "$MODDIR/common/ssaid_surgical.sh" ] && . "$MODDIR/common/ssaid_surgical.sh"

_PIF_MANAGED_KEYS_RE='^(ro\.product\.(brand|manufacturer|model|name|device)|ro\.build\.(fingerprint|id|tags|type|display\.id))$'

# === Default Settings ===
ENABLE_SPOOF_PERSONA=false
ENABLE_ANDROID_ID=true
ENABLE_GAID=true
ENABLE_MAC_RANDOM=true
ENABLE_BT_NAME=true
ENABLE_HOSTNAME=true
ENABLE_CLEAR_APPS=true
ENABLE_WIPE_SDCARD=true
ENABLE_WIPE_FIREBASE=true
ENABLE_WIPE_MEDIADRM=true
ENABLE_RESET_GSF=true
ENABLE_CLEAR_NETWORK=true
ENABLE_WIPE_FORENSIC=true
ENABLE_WIPE_CLIPBOARD=true
ENABLE_BACKUP=true
ENABLE_PERSONAS=true
FORCE_APPLY=false

load_settings() {
    [ -f "$SETTINGS_FILE" ] || return
    while IFS='=' read -r key val; do
        key="$(echo "$key" | sed 's/#.*//' | tr -d ' \t')"
        val="$(echo "$val" | sed 's/#.*//' | tr -d ' \t')"
        [ -z "$key" ] && continue
        case "$key" in
            ENABLE_SPOOF_PERSONA)  ENABLE_SPOOF_PERSONA="$val"  ;;
            ENABLE_ANDROID_ID)     ENABLE_ANDROID_ID="$val"     ;;
            ENABLE_GAID)           ENABLE_GAID="$val"           ;;
            ENABLE_MAC_RANDOM)     ENABLE_MAC_RANDOM="$val"     ;;
            ENABLE_BT_NAME)        ENABLE_BT_NAME="$val"        ;;
            ENABLE_HOSTNAME)       ENABLE_HOSTNAME="$val"       ;;
            ENABLE_CLEAR_APPS)     ENABLE_CLEAR_APPS="$val"     ;;
            ENABLE_WIPE_SDCARD)    ENABLE_WIPE_SDCARD="$val"    ;;
            ENABLE_WIPE_FIREBASE)  ENABLE_WIPE_FIREBASE="$val"  ;;
            ENABLE_WIPE_MEDIADRM)  ENABLE_WIPE_MEDIADRM="$val"  ;;
            ENABLE_RESET_GSF)      ENABLE_RESET_GSF="$val"      ;;
            ENABLE_CLEAR_NETWORK)  ENABLE_CLEAR_NETWORK="$val"  ;;
            ENABLE_WIPE_FORENSIC)  ENABLE_WIPE_FORENSIC="$val"  ;;
            ENABLE_WIPE_CLIPBOARD) ENABLE_WIPE_CLIPBOARD="$val" ;;
            ENABLE_BACKUP)         ENABLE_BACKUP="$val"         ;;
            ENABLE_PERSONAS)       ENABLE_PERSONAS="$val"       ;;
            FORCE_APPLY)           FORCE_APPLY="$val"           ;;
        esac
    done < "$SETTINGS_FILE"
}
load_settings
is_on() { [ "$(echo "$1" | tr '[:upper:]' '[:lower:]')" = "true" ]; }

_has_force_flag() {
    for arg in "$@"; do
        case "$arg" in
            force|--force|-f) return 0 ;;
        esac
    done
    return 1
}

TARGET_APPS="com.shopee.id com.tokopedia.tkpd com.ss.android.ugc.trill"
FID_TARGETS="$TARGET_APPS com.google.android.gms com.google.android.gsf"

# Secure directory creation
umask 022
mkdir -p "$PERSONA_DIR" "$PERSONA_DIR/custom" "$LOG_DIR" "$BACKUP_DIR_ROOT" "$STATE_DIR" 2>/dev/null
chmod 0755 "$PERSONA_DIR" "$PERSONA_DIR/custom" 2>/dev/null
chmod 0700 "$LOG_DIR" "$BACKUP_DIR_ROOT" "$STATE_DIR" 2>/dev/null

LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"

# === Logging ===
log()       { local m="[$(date '+%H:%M:%S')] $1"; echo "$m"; echo "$m" >> "$LOG_FILE" 2>/dev/null; }
log_ok()    { log "[+] $1"; }
log_info()  { log "[i] $1"; }
log_warn()  { log "[!] $1"; }
log_err()   { log "[-] $1"; }
log_step()  { log "[...] $1"; }
log_dbg()   { log "[dbg] $1"; }

# === SELinux helper ===
SE_PREV=""
se_permissive() { SE_PREV="$(getenforce 2>/dev/null)"; setenforce 0 2>/dev/null || true; }
se_restore()    { [ "$SE_PREV" = "Enforcing" ] && setenforce 1 2>/dev/null; SE_PREV=""; }

# === Settings/cmd wrappers ===
get_users() {
    pm list users 2>/dev/null | grep -o 'UserInfo{[0-9]\+' | grep -o '[0-9]\+' || echo "0"
}

settings_get() {
    local val
    val="$(cmd settings get "$1" "$2" 2>/dev/null)"
    if [ -z "$val" ] || [ "$val" = "null" ]; then val="$(settings get "$1" "$2" 2>/dev/null)"; fi
    echo "$val" | tr -d '"\r\n\t'
}
settings_put() { cmd settings put "$1" "$2" "$3" 2>/dev/null || settings put "$1" "$2" "$3" 2>/dev/null; }
settings_del() { cmd settings delete "$1" "$2" 2>/dev/null || settings delete "$1" "$2" 2>/dev/null; }
force_stop()   { cmd activity force-stop "$1" 2>/dev/null || am force-stop "$1" 2>/dev/null; }

escape_json() {
    printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r//g' -e 's/\t/\\t/g'
}

# === resetprop wrapper ===
RESETPROP_BIN=""
RP_MODE=""
detect_resetprop() {
    local RP_RS="$MODDIR/bin/resetprop-rs"
    [ -f "$RP_RS" ] && chmod +x "$RP_RS" 2>/dev/null
    local RP=""
    if   [ -x "$RP_RS" ];                          then RP="$RP_RS";                            RP_MODE="rs"
    elif command -v resetprop-rs >/dev/null 2>&1;  then RP="resetprop-rs";                      RP_MODE="rs"
    elif command -v resetprop >/dev/null 2>&1;     then RP="resetprop";                         RP_MODE="legacy"
    elif [ -x /data/adb/magisk/magisk ];           then RP="/data/adb/magisk/magisk resetprop"; RP_MODE="legacy"
    elif [ -x /data/adb/ksu/bin/resetprop ];       then RP="/data/adb/ksu/bin/resetprop";       RP_MODE="legacy"
    elif [ -x /data/adb/ap/bin/resetprop ];        then RP="/data/adb/ap/bin/resetprop";        RP_MODE="legacy"
    fi

    if [ -z "$RP" ]; then
        RESETPROP_BIN=""
        log_warn "resetprop tidak ada — live spoof skip, hanya system.prop persist (butuh reboot)"
        return 1
    else
        RESETPROP_BIN="$RP"
        return 0
    fi
}

rprop_set() {
    [ -z "$RESETPROP_BIN" ] && return 1
    "$RESETPROP_BIN" -n "$1" "$2" 2>/dev/null
}

rprop_get() {
    [ -z "$RESETPROP_BIN" ] && return
    "$RESETPROP_BIN" -v "$1" 2>/dev/null
}

trim_ws() { echo "$1" | awk '{gsub(/^[ \t]+|[ \t]+$/,""); print}'; }

_strip_bom() {
    local f="$1"
    [ -f "$f" ] || return 0
    local bom="$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    if [ "$bom" = "efbbbf" ]; then
        tail -c +4 "$f" > "$f.nobom" 2>/dev/null && mv "$f.nobom" "$f"
    fi
}

_snapshot_build_extended() {
    local snap_file="$STATE_DIR/build_spoof_extended.txt"
    local props="ro.build.fingerprint ro.build.description ro.build.display.id ro.build.id ro.build.tags ro.build.type ro.build.version.incremental ro.build.version.release ro.build.version.security_patch ro.product.brand ro.product.manufacturer ro.product.model ro.product.name ro.boot.verifiedbootstate ro.boot.veritymode ro.boot.flash.locked ro.boot.warranty_bit ro.warranty_bit ro.debuggable ro.secure ro.vendor.build.fingerprint ro.vendor.build.type ro.vendor.build.tags ro.vendor.product.brand ro.vendor.product.manufacturer ro.vendor.product.model"

    [ -f "$snap_file" ] && return 0

    if [ -f "$STATE_DIR/build_spoof_before.txt" ]; then
       cp "$STATE_DIR/build_spoof_before.txt" "$snap_file" 2>/dev/null
       for p in $props; do
           grep -q "^$p=" "$snap_file" 2>/dev/null && continue
           local v="$(rprop_get "$p")"
           [ -n "$v" ] && echo "$p=$v" >> "$snap_file"
       done
       rm -f "$STATE_DIR/build_spoof_before.txt"
       return 0
    fi

    log_step "Creating extended property snapshot (20+ props)"
    for p in $props; do
        local v="$(rprop_get "$p")"
        [ -n "$v" ] && echo "$p=$v" >> "$snap_file"
    done
}

# === Random generators (Optimized) ===
generate_hex() {
    local bytes=$(( $1 / 2 ))
    [ $(( $1 % 2 )) -ne 0 ] && bytes=$(( bytes + 1 ))
    od -An -tx1 -N "$bytes" /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-"$1"
}

generate_uuid() {
    local u="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
    [ -n "$u" ] && echo "$u" || echo "$(generate_hex 8)-$(generate_hex 4)-4$(generate_hex 3)-$(generate_hex 4)-$(generate_hex 12)"
}

generate_mac() {
    local bytes="$(od -An -tx1 -N 6 /dev/urandom 2>/dev/null | tr -d ' \n')"
    local b1_dec=$((0x$(echo "$bytes" | cut -c1-2) & 0xFC))
    local b1="$(printf "%02x" $b1_dec)"
    echo "${b1}:$(echo $bytes | cut -c3-4):$(echo $bytes | cut -c5-6):$(echo $bytes | cut -c7-8):$(echo $bytes | cut -c9-10):$(echo $bytes | cut -c11-12)"
}

# === Restore Build (readback verify) ===
restore_build() {
    local snap_file="$STATE_DIR/build_spoof_extended.txt"
    [ -f "$snap_file" ] || { log_warn "No snapshot to restore"; return 1; }

    detect_resetprop || return 1
    log_step "Restoring properties from extended snapshot..."

    local applied=0 skipped=0 errs=0 line key val before after
    while IFS= read -r line || [ -n "$line" ]; do
        case "$(trim_ws "$line")" in ""|\#*) continue ;; esac
        key="$(trim_ws "${line%%=*}")"
        val="$(trim_ws "${line#*=}")"
        [ -z "$key" ] && continue

        before="$(rprop_get "$key")"
        if [ "$before" = "$val" ]; then
            skipped=$((skipped+1))
            continue
        fi

        rprop_set "$key" "$val"
        after="$(rprop_get "$key")"
        if [ "$after" = "$val" ]; then
            applied=$((applied+1))
        else
            errs=$((errs+1))
        fi
    done < "$snap_file"
    log_ok "Restore completed: applied=$applied skipped=$skipped errs=$errs"
    rm -f "$ACTIVE_PERSONA_FILE"
}

# ============================================================
# PERSONA SYSTEM
# ============================================================

_load_real_sdk() {
    REAL_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
    REAL_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
    [ -n "$REAL_SDK" ] || { log_err "Failed to get real SDK version"; return 1; }
    return 0
}

# Fix v4.14 - fail-closed safety allowlist
is_safe_identity_prop() {
    case "$1" in
        ro.product.brand|ro.product.manufacturer|ro.product.model|\
        ro.product.name|ro.product.device|ro.product.board|\
        ro.product.system.*|ro.product.system_ext.*|ro.product.product.*|\
        ro.product.vendor.*|ro.product.odm.*) return 0 ;;
        ro.build.fingerprint|ro.build.id|ro.build.display.id|\
        ro.build.version.incremental|ro.build.version.security_patch|\
        ro.build.version.release|ro.build.version.codename|\
        ro.build.type|ro.build.tags|ro.build.description|\
        ro.build.flavor|ro.build.product|ro.build.characteristics) return 0 ;;
        ro.product.build.*|ro.system.build.*|ro.system_ext.build.*|\
        ro.vendor.build.*|ro.odm.build.*|ro.bootimage.build.*) return 0 ;;
        ro.vendor.product.*|ro.vendor.build.security_patch) return 0 ;;
        ro.serialno|ro.boot.serialno|ro.bootloader|\
        ro.boot.hwname|ro.boot.hwdevice|ro.product.hardware.sku|\
        ro.boot.product.hardware.sku|ro.build.device_family|\
        vendor.usb.product_string) return 0 ;;
        ro.soc.model|ro.soc.manufacturer|ro.product.first_api_level) return 0 ;;
    esac
    return 1
}

# Fix v4.14 - resolve ${RANDOM_HEX:N} and ${RANDOM_SERIAL} in persona values
resolve_persona_value() {
    local v="$1" tok len rep
    while :; do
        case "$v" in
            *'${RANDOM_HEX:'*'}'*)
                tok=$(printf '%s' "$v" | sed -n 's/.*\(\${RANDOM_HEX:[0-9]*}\).*/\1/p')
                [ -z "$tok" ] && break
                len=$(printf '%s' "$tok" | sed 's/${RANDOM_HEX:\([0-9]*\)}/\1/')
                rep=$(generate_hex "$len")
                v="${v%%"$tok"*}${rep}${v#*"$tok"}"
                ;;
            *'${RANDOM_SERIAL}'*)
                rep=$(generate_serial)
                v="${v%%'${RANDOM_SERIAL}'*}${rep}${v#*'${RANDOM_SERIAL}'}"
                ;;
            *) break ;;
        esac
    done
    printf '%s' "$v"
}

spoof_build_persona() {
    local persona="$1"
    shift
    local force_arg=0
    _has_force_flag "$@" && force_arg=1

    [ -z "$persona" ] && { log_err "spoof_build_persona requires a name"; return 1; }

    local pfile=""
    if [ -f "$PERSONA_DIR/${persona}.txt" ]; then
        pfile="$PERSONA_DIR/${persona}.txt"
    elif [ -f "$PERSONA_DIR/custom/${persona}.txt" ]; then
        pfile="$PERSONA_DIR/custom/${persona}.txt"
        log_warn "Using unvalidated persona - Play Integrity risk"
    else
        log_err "Persona missing: $persona"
        return 1
    fi

    detect_resetprop || return 1
    _strip_bom "$pfile"
    log_step "Loading persona: $persona"
    _snapshot_build_extended
    _load_real_sdk || return 1
    local real_sdk="$REAL_SDK"

    local target_sdk=""
    local first_line="$(head -n 1 "$pfile")"
    if echo "$first_line" | grep -q "^# TARGET_SDK="; then
        target_sdk="$(echo "$first_line" | cut -d'=' -f2 | tr -d ' \r\n')"
    fi

    if [ -n "$target_sdk" ] && [ "$target_sdk" != "$real_sdk" ]; then
        log_err "persona: TARGET_SDK=$target_sdk override rejected (locked to real device SDK=$real_sdk)"
        return 1
    fi

    local pif_active=0
    if [ "$HAS_PIF" = "1" ] && ! is_on "$FORCE_APPLY" && [ "$force_arg" = "0" ]; then
        pif_active=1
    fi

    local applied=0 skipped=0 skipped_pif=0 errs=0 line key val malformed=0 before after dbg_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$(trim_ws "$line")" in ""|\#*) continue ;; esac
        key="$(trim_ws "${line%%=*}")"
        val="$(trim_ws "${line#*=}")"

        if [ -z "$key" ] || [ -z "$val" ]; then
            log_warn "persona '$persona': skipping malformed line: '$line'"
            malformed=$((malformed+1))
            if [ $malformed -gt 5 ]; then
                log_err "Aborting: Persona file is corrupted (>5 malformed lines)"
                return 1
            fi
            continue
        fi

        if [ "$key" = "ro.build.version.sdk" ]; then
            log_warn "persona: ro.build.version.sdk override rejected (locked to real device SDK=$real_sdk)"
            skipped=$((skipped+1))
            continue
        fi

        if [ "$pif_active" = "1" ] && echo "$key" | grep -qE "$_PIF_MANAGED_KEYS_RE"; then
            skipped_pif=$((skipped_pif+1))
            continue
        fi

        # v4.14 - safety allowlist (fail-closed)
        if ! is_safe_identity_prop "$key"; then
            log_warn "persona '$persona': $key rejected (not in identity allowlist)"
            skipped=$((skipped+1))
            continue
        fi

        # v4.14 - resolve tokens
        val="$(resolve_persona_value "$val")"

        before="$(rprop_get "$key")"
        if [ "$before" = "$val" ]; then
            skipped=$((skipped+1))
            continue
        fi

        rprop_set "$key" "$val"
        after="$(rprop_get "$key")"

        if [ "$after" = "$val" ]; then
            applied=$((applied+1))
        else
            errs=$((errs+1))
        fi
    done < "$pfile"

    log_ok "Persona applied=$applied skipped=$skipped skipped_pif=$skipped_pif errs=$errs"
    echo "$persona" > "$ACTIVE_PERSONA_FILE"
    _freeze_persona_snapshot "$pfile"
}

# v4.14 - freeze resolved values for next-boot pre-zygote apply
_freeze_persona_snapshot() {
    local pfile="$1" out="$STATE_DIR/resolved_persona.txt"
    : > "$out"
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(strip_inline_comment "$line")"
        case "$(trim_ws "$line")" in ''|\#*) continue ;; esac
        local k v
        k="$(trim_ws "${line%%=*}")"; v="$(trim_ws "${line#*=}")"
        [ -z "$k" ] || [ -z "$v" ] && continue
        is_safe_identity_prop "$k" || continue
        v="$(resolve_persona_value "$v")"
        echo "$k=$v" >> "$out"
    done < "$pfile"
    chmod 600 "$out" 2>/dev/null
}

# === Identifiers ===
set_android_id_global() {
    local newid="$1"
    [ -z "$newid" ] && newid="$(generate_hex 16)"
    settings_put secure android_id "$newid"
    log_ok "Global ANDROID_ID: $newid"
}

# v4.14 - surgical SSAID replacing nuclear wipe
apply_ssaid_new() {
    local new_ssaid="${1:-$(generate_hex 16)}"
    local targets="${2:-$TARGET_APPS}"

    # Write config for post-fs-data next boot AND CLI immediate apply
    ssaid_write_config "$new_ssaid" $targets
    ssaid_apply_now
    log_ok "SSAID configured: $new_ssaid (targets: $targets)"
    log_info "Full effect on next boot (or force-stop target apps now)"
}

set_gaid_value() {
    local newgaid="$1"
    [ -z "$newgaid" ] && newgaid="$(generate_uuid)"
    log_step "Set GAID: $newgaid"
    force_stop com.google.android.gms
    am kill com.google.android.gms 2>/dev/null
    se_permissive
    rm -rf /data/data/com.google.android.gms/shared_prefs/adid_settings.xml* \
           /data/data/com.google.android.gms/shared_prefs/adsidentity*.xml \
           /data/data/com.google.android.gms/files/adid_cache.dat \
           /data/data/com.google.android.gms/no_backup/adid* 2>/dev/null
    mkdir -p /data/data/com.google.android.gms/shared_prefs 2>/dev/null

    cat > /data/data/com.google.android.gms/shared_prefs/adid_settings.xml <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="adid_key">$newgaid</string>
    <boolean name="enable_limit_ad_tracking" value="false" />
    <long name="last_reset_time" value="$(date +%s)000" />
</map>
EOF
    local gms_uid="$(stat -c '%u' /data/data/com.google.android.gms 2>/dev/null)"
    if [ -n "$gms_uid" ]; then
        chown $gms_uid:$gms_uid /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    fi
    chmod 660 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    settings_put global advertising_id "$newgaid"
    se_restore
    log_ok "GAID set: $newgaid"

    # v4.14 - freeze GAID for next-boot pre-zygote apply
    printf '%s' "$newgaid" > "$GAID_VALUE_FILE"
    chmod 600 "$GAID_VALUE_FILE" 2>/dev/null
}

randomize_wlan_mac() {
    local newmac="$1"
    [ -z "$newmac" ] && newmac="$(generate_mac)"
    log_step "Randomize wlan0 MAC: $newmac"
    se_permissive
    ip link set wlan0 down 2>/dev/null
    ip link set dev wlan0 address "$newmac" 2>/dev/null && log_ok "MAC: $newmac" || log_warn "MAC change rejected"
    ip link set wlan0 up 2>/dev/null
    rm -f /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml* 2>/dev/null
    se_restore
}

randomize_device_name() {
    log_step "Randomize device/BT name..."
    local BRANDS="Galaxy Pixel Redmi Mi Poco Realme OnePlus Honor Oppo Vivo Asus"
    local MODELS="S24 S25 Note13 9Pro 14Ultra F6 12R 11R X100 FindX7 Magic6 ROG8 Edge"
    local b="$(echo "$BRANDS" | awk -v r=$(( $(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 11 + 1 )) '{print $r}')"
    local m="$(echo "$MODELS" | awk -v r=$(( $(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 13 + 1 )) '{print $r}')"
    local nonce=$(( $(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 900 + 100 ))
    local NEW_NAME="$b $m-$nonce"

    settings_put global bluetooth_name "$NEW_NAME"
    settings_put global device_name "$NEW_NAME"
    rprop_set persist.bluetooth.adaptername "$NEW_NAME"

    se_permissive
    local updated=0
    for btcfg in /data/misc/bluedroid/bt_config.conf /data/misc/bluetooth/bt_config.conf /data/vendor/bluetooth/bt_config.conf; do
        [ -f "$btcfg" ] || continue
        if grep -q "^Name = " "$btcfg" 2>/dev/null; then
            local owner=$(stat -c '%U:%G' "$btcfg" 2>/dev/null)
            local mode=$(stat -c '%a' "$btcfg" 2>/dev/null)
            awk -v n="$NEW_NAME" '/^Name = / { print "Name = " n; next } { print }' "$btcfg" > "${btcfg}.tmp" 2>/dev/null
            if [ -s "${btcfg}.tmp" ]; then
                mv "${btcfg}.tmp" "$btcfg" 2>/dev/null && {
                    [ -n "$owner" ] && chown "$owner" "$btcfg" 2>/dev/null
                    [ -n "$mode" ]  && chmod "$mode"  "$btcfg" 2>/dev/null
                    log_ok "Rewrote: $btcfg"
                    updated=1
                }
            fi
            rm -f "${btcfg}.tmp" 2>/dev/null
        fi
    done
    [ $updated -eq 0 ] && log_warn "bt_config.conf belum ada / not writable"
    se_restore

    force_stop com.android.bluetooth
    pkill -f 'com\.(android|google\.android)\.bluetooth' 2>/dev/null
    log_ok "Name: $NEW_NAME"
}

randomize_hostname() {
    local nonce=$(( $(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 9000 + 1000 ))
    local hn="android-$nonce"
    if [ -n "$RESETPROP_BIN" ]; then rprop_set net.hostname "$hn"
    else setprop net.hostname "$hn" 2>/dev/null; fi
    hostname "$hn" 2>/dev/null
    log_ok "Hostname: $hn"
}

# === Detection ===
detect_root_manager() {
    if   [ -d /data/adb/ksu ];    then ROOT_MGR="KernelSU"
    elif [ -d /data/adb/ap ];     then ROOT_MGR="APatch"
    elif [ -d /data/adb/magisk ]; then ROOT_MGR="Magisk"
    else ROOT_MGR="Unknown"; fi
}
detect_modules() {
    HAS_PIF=0; HAS_SPECTER=0; HAS_ZYGISK_NEXT=0
    [ -d /data/adb/modules/playintegrityfix ] && HAS_PIF=1
    [ -d /data/adb/modules/specter ] && HAS_SPECTER=1
    if [ -d /data/adb/modules/zygisksu ] || [ -d /data/adb/modules/zygisknext ]; then HAS_ZYGISK_NEXT=1; fi
    SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
}
preflight() {
    [ "$(id -u)" -eq 0 ] || { log_err "Need root"; exit 1; }
    detect_resetprop
    detect_root_manager
    detect_modules
}

# === Wipes (Fixed to support root mount namespace bypassing /sdcard) ===
freeze_targets() {
    log_step "Force-stop targets..."
    for pkg in $FID_TARGETS; do force_stop "$pkg"; done
}
clear_target_apps() {
    log_step "pm clear targets..."
    for pkg in $TARGET_APPS; do
        if pm list packages 2>/dev/null | grep -q "package:$pkg"; then
            for u in $(get_users); do
                pm clear --user "$u" "$pkg" >/dev/null 2>&1
            done
        fi
    done
    log_ok "Apps cleared"
}
clear_sdcard_residue() {
    log_step "Wipe Media/SDcard residue..."
    se_permissive
    for u in $(get_users); do
        for pkg in $TARGET_APPS; do
            rm -rf "/data/media/$u/Android/data/$pkg" "/data/media/$u/Android/media/$pkg" "/data/media/$u/Android/obb/$pkg" 2>/dev/null
        done
    done
    # Fallback to general sdcard path for older Androids without namespace isolation issues
    for pkg in $TARGET_APPS; do
        rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null
    done
    se_restore; log_ok "Media cleared"
}
wipe_firebase_iid() {
    log_step "Wipe Firebase..."
    se_permissive
    for pkg in $FID_TARGETS; do
        rm -f /data/data/$pkg/shared_prefs/PersistedInstallation.* \
              /data/data/$pkg/files/PersistedInstallation.* \
              /data/data/$pkg/shared_prefs/com.google.firebase.*.xml \
              /data/data/$pkg/shared_prefs/com.google.android.gms.*.xml 2>/dev/null
        rm -rf /data/data/$pkg/databases/google_app_measurement_local.db* \
               /data/data/$pkg/databases/firebase-* 2>/dev/null
    done
    se_restore; log_ok "Firebase wiped"
}
reset_gsf_id() {
    log_step "Reset GSF..."
    force_stop com.google.android.gsf
    se_permissive
    rm -f /data/data/com.google.android.gsf/databases/gservices.db* \
          /data/data/com.google.android.gsf/databases/Checkin.db* 2>/dev/null
    se_restore; log_ok "GSF reset"
}
wipe_mediadrm() {
    log_step "Wipe MediaDrm..."
    se_permissive
    rm -rf /data/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/ 2>/dev/null
    for u in $(get_users); do rm -rf "/data/system/users/$u/drm/" 2>/dev/null; done
    rm -rf /data/misc/mediadrm/ 2>/dev/null
    se_restore
    pkill -f mediadrmserver 2>/dev/null; pkill -f android.hardware.drm 2>/dev/null
    log_ok "MediaDrm wiped"
}
clear_network_caches() {
    log_step "Wipe network..."
    se_permissive
    rm -rf /data/misc/net/* /data/misc/connectivity/* \
           /data/misc/dhcp/*.lease /data/misc/dhcp-6.8/*.lease \
           /data/misc/netstats/* /data/system/netstats/* 2>/dev/null
    se_restore
    ndc resolver clearnetdns 0 2>/dev/null
    log_ok "Network wiped"
}
wipe_forensic_traces() {
    log_step "Wipe forensics..."
    logcat -c 2>/dev/null; logcat -b all -c 2>/dev/null
    se_permissive
    rm -rf /data/anr/* /data/tombstones/* /data/system/dropbox/* /data/system/procstats/* /data/system/heapdump/* 2>/dev/null
    for u in $(get_users); do
        rm -rf "/data/system/usagestats/$u/"* "/data/system/users/$u/recent_tasks/"* "/data/system/users/$u/recent_images/"* 2>/dev/null
    done
    se_restore; log_ok "Forensics cleared"
}
wipe_clipboard() { cmd clipboard set-text "" 2>/dev/null; log_ok "Clipboard cleared"; }

backup_state() {
    local bdir="$BACKUP_DIR_ROOT/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bdir"
    settings_get secure android_id     > "$bdir/android_id"
    settings_get global bluetooth_name > "$bdir/bluetooth_name"
    settings_get global advertising_id > "$bdir/advertising_id"
    getprop net.hostname               > "$bdir/hostname"
    getprop ro.serialno                > "$bdir/serialno"
    getprop ro.build.fingerprint       > "$bdir/fingerprint"
    chmod 600 "$bdir"/* 2>/dev/null
    log_ok "Backup saved"
}

save_persona_snapshot() {
    local pkg="$1"
    local f="$PERSONA_DIR/${pkg}.json"
    local aid="$(settings_get secure android_id)"; [ -z "$aid" ] && aid="$(generate_hex 16)"
    local gaid_val="$(settings_get global advertising_id)"; [ -z "$gaid_val" ] && gaid_val="$(generate_uuid)"
    local pname="unknown"
    [ -f "$ACTIVE_PERSONA_FILE" ] && pname="$(cat "$ACTIVE_PERSONA_FILE")"
    local now="$(date +%s)000"
    local age=$(( ($(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 30) + 1 ))

    # Safe JSON writing
    cat > "$f" <<EOF
{
  "package": "$(escape_json "$pkg")",
  "profile": "$(escape_json "$pname")",
  "androidId": "$(escape_json "$aid")",
  "gaid": "$(escape_json "$gaid_val")",
  "createdAt": $now,
  "ageDays": $age
}
EOF
    chmod 644 "$f"
}

burn_persona() {
    local pkg="$1"
    log_step "Burn: $pkg"
    rm -f "$PERSONA_DIR/${pkg}.json"
    force_stop "$pkg"
    for u in $(get_users); do
        pm clear --user "$u" "$pkg" >/dev/null 2>&1
    done
    se_permissive
    for u in $(get_users); do
        rm -rf "/data/media/$u/Android/data/$pkg" "/data/media/$u/Android/media/$pkg" "/data/media/$u/Android/obb/$pkg" 2>/dev/null
    done
    rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null
    rm -f /data/data/$pkg/shared_prefs/PersistedInstallation.* /data/data/$pkg/files/PersistedInstallation.* 2>/dev/null
    se_restore
    set_gaid_value
    apply_ssaid_new "$(generate_hex 16)" "$TARGET_APPS"
    restore_build
    save_persona_snapshot "$pkg"
    log_ok "$pkg burnt"
}

# === Pipeline ===
do_fresh() {
    preflight
    is_on "$ENABLE_BACKUP" && backup_state

    local persona_arg=""
    local force_arg=0
    for arg in "$@"; do
        case "$arg" in
            force|--force|-f) force_arg=1 ;;
            "") ;;
            *) [ -z "$persona_arg" ] && persona_arg="$arg" ;;
        esac
    done

    if [ -n "$persona_arg" ]; then
        if [ ! -f "$PERSONA_DIR/${persona_arg}.txt" ] && [ ! -f "$PERSONA_DIR/custom/${persona_arg}.txt" ]; then
            log_err "Persona '$persona_arg' not found"
            return 1
        fi
        ENABLE_SPOOF_PERSONA=true
    elif [ -f "$ACTIVE_PERSONA_FILE" ]; then
        persona_arg="$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null)"
        [ -n "$persona_arg" ] && ENABLE_SPOOF_PERSONA=true
    fi

    if is_on "$ENABLE_SPOOF_PERSONA" && [ -n "$persona_arg" ]; then
        if [ "$force_arg" = "1" ]; then spoof_build_persona "$persona_arg" --force
        else spoof_build_persona "$persona_arg"; fi
    fi

    freeze_targets
    is_on "$ENABLE_CLEAR_APPS"    && clear_target_apps
    is_on "$ENABLE_WIPE_SDCARD"   && clear_sdcard_residue
    is_on "$ENABLE_WIPE_FIREBASE" && wipe_firebase_iid
    is_on "$ENABLE_WIPE_MEDIADRM" && wipe_mediadrm
    is_on "$ENABLE_RESET_GSF"     && reset_gsf_id

    if is_on "$ENABLE_ANDROID_ID"; then
        apply_ssaid_new "$(generate_hex 16)" "$TARGET_APPS"
        set_android_id_global "$(generate_hex 16)"
    fi
    is_on "$ENABLE_GAID"          && set_gaid_value "$(generate_uuid)"
    is_on "$ENABLE_BT_NAME"       && randomize_device_name
    is_on "$ENABLE_HOSTNAME"      && randomize_hostname
    is_on "$ENABLE_MAC_RANDOM"    && randomize_wlan_mac
    is_on "$ENABLE_CLEAR_NETWORK" && clear_network_caches

    if is_on "$ENABLE_PERSONAS"; then
        rm -f "$PERSONA_DIR"/*.json 2>/dev/null
        for pkg in $TARGET_APPS; do save_persona_snapshot "$pkg"; done
    fi

    is_on "$ENABLE_WIPE_CLIPBOARD" && wipe_clipboard
    is_on "$ENABLE_WIPE_FORENSIC"  && wipe_forensic_traces
    echo ""; verify_changes; echo ""
    log_ok "FRESH IDENTITY READY"
}

# === Verify (Display differences) ===
verify_changes() {
    local hn
    hn="$(getprop net.hostname 2>/dev/null)"
    [ -z "$hn" ] && hn="$(hostname 2>/dev/null)"
    [ -z "$hn" ] && hn="<unset>"

    echo "================ STATE VERIFY ================"
    [ -f "$ACTIVE_PERSONA_FILE" ] && echo "Persona          : $(cat "$ACTIVE_PERSONA_FILE")"
    echo "SDK              : $(getprop ro.build.version.sdk)"
    echo ""
    echo "--- [PIF-managed] handled by PlayIntegrityFix at GMS query time ---"
    echo "Brand/Model      : $(getprop ro.product.brand) / $(getprop ro.product.model)"
    echo "Manufacturer     : $(getprop ro.product.manufacturer)"
    echo "Device           : $(getprop ro.product.device)"
    echo "Fingerprint      : $(getprop ro.build.fingerprint)"
    echo "Build ID         : $(getprop ro.build.id)"
    echo "Build Type/Tags  : $(getprop ro.build.type) / $(getprop ro.build.tags)"
    echo ""
    echo "--- [Ternak-managed] via resetprop live-write (persona) ---"
    echo "Description      : $(getprop ro.build.description)"
    echo "Security patch   : $(getprop ro.build.version.security_patch)"
    echo "Vendor brand     : $(getprop ro.vendor.product.brand)"
    echo "Vendor model     : $(getprop ro.vendor.product.model)"
    echo "Vendor fingerprint: $(getprop ro.vendor.build.fingerprint)"
    echo ""
    echo "--- [Ternak-managed] identifiers ---"
    echo "Serial           : $(getprop ro.serialno)"
    echo "Android ID       : $(settings_get secure android_id)"
    echo "GAID             : $(settings_get global advertising_id)"
    echo "BT Name          : $(settings_get global bluetooth_name)"
    echo "Hostname         : $hn"
    echo "=============================================="
}

# === JSON Info Generator ===
get_info() {
    local android_id="$(settings_get secure android_id)"
    local bt_name="$(settings_get global bluetooth_name)"
    local hostname_val="$(getprop net.hostname)"
    [ -z "$hostname_val" ] && hostname_val="$(hostname 2>/dev/null)"
    local gaid="$(settings_get global advertising_id)"
    local model="$(getprop ro.product.model)"
    local brand="$(getprop ro.product.brand)"
    local serial="$(getprop ro.serialno)"
    local fingerprint="$(getprop ro.build.fingerprint)"
    local sdk="$(getprop ro.build.version.sdk)"
    local profile_name="-"
    [ -f "$ACTIVE_PERSONA_FILE" ] && profile_name="$(cat "$ACTIVE_PERSONA_FILE")"

    [ -z "$android_id" ] || [ "$android_id" = "null" ] && android_id="—"
    [ -z "$gaid" ] || [ "$gaid" = "null" ] && gaid="—"
    [ -z "$bt_name" ] || [ "$bt_name" = "null" ] && bt_name="—"

    local persona_count=$(ls "$PERSONA_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    local pif=$([ "$HAS_PIF" = "1" ] && echo true || echo false)
    local specter=$([ "$HAS_SPECTER" = "1" ] && echo true || echo false)
    local zygnext=$([ "$HAS_ZYGISK_NEXT" = "1" ] && echo true || echo false)
    local rp_ok="$([ -n "$RESETPROP_BIN" ] && echo true || echo false)"
    local rp_mode_out="${RP_MODE:-none}"

    printf '{"android_id":"%s","bt_name":"%s","hostname":"%s","gaid":"%s","model":"%s","brand":"%s","serial":"%s","fingerprint":"%s","sdk":"%s","profile":"%s","root_manager":"%s","persona_count":%s,"modules":{"pif":%s,"specter":%s,"zygisk_next":%s,"resetprop":%s,"resetprop_mode":"%s"}}' \
        "$(escape_json "$android_id")" "$(escape_json "$bt_name")" "$(escape_json "$hostname_val")" \
        "$(escape_json "$gaid")" "$(escape_json "$model")" "$(escape_json "$brand")" "$(escape_json "$serial")" \
        "$(escape_json "$fingerprint")" "$(escape_json "$sdk")" "$(escape_json "$profile_name")" \
        "$(escape_json "$ROOT_MGR")" "$persona_count" "$pif" "$specter" "$zygnext" "$rp_ok" "$(escape_json "$rp_mode_out")"
}

list_personas() {
    printf '['
    local first=1
    for f in "$PERSONA_DIR"/*.json; do
        [ -f "$f" ] || continue
        [ $first -eq 0 ] && printf ','
        cat "$f" | tr -d '\n'
        first=0
    done
    printf ']'
}

list_personas_available() {
    printf '{"validated":['
    local first_val=1
    for p in "$PERSONA_DIR"/*.txt; do
        [ -f "$p" ] || continue
        [ $first_val -eq 0 ] && printf ','
        printf '"%s"' "$(escape_json "$(basename "$p" .txt)")"
        first_val=0
    done
    printf '],"custom":['
    local first_cust=1
    for p in "$PERSONA_DIR/custom/"*.txt; do
        [ -f "$p" ] || continue
        [ $first_cust -eq 0 ] && printf ','
        printf '"%s"' "$(escape_json "$(basename "$p" .txt)")"
        first_cust=0
    done
    printf ']}'
}

# === Router ===
case "$1" in
    info)        detect_resetprop >/dev/null 2>&1; detect_root_manager >/dev/null 2>&1; detect_modules >/dev/null 2>&1; get_info ;;
    fresh|full)  shift; do_fresh "$@" ;;
    persona)     preflight; shift; spoof_build_persona "$@" ;;
    personas_list) list_personas_available ;;
    personas_active) list_personas ;;
    restore_build) preflight; restore_build ;;
    preflight)   preflight ;;
    burn)        preflight; [ -z "$2" ] && { log_err "Usage: burn <pkg>"; exit 1; }; burn_persona "$2" ;;
    burn_all)    preflight; for pkg in $TARGET_APPS; do burn_persona "$pkg"; done ;;
    aid)         preflight; apply_ssaid_new "$(generate_hex 16)" "$TARGET_APPS"; set_android_id_global "$2" ;;
    ssaid)
        preflight
        shift
        local v="$1"; shift
        [ "$v" = "new" ] && v="$(generate_hex 16)"
        apply_ssaid_new "$v" "${*:-$TARGET_APPS}"
        ;;
    ssaid_revert)
        preflight; ssaid_revert
        ;;
    gaid)        preflight; set_gaid_value "$2" ;;
    mac)         preflight; randomize_wlan_mac "$2" ;;
    deep_wipe)   preflight; freeze_targets; wipe_mediadrm; reset_gsf_id; wipe_firebase_iid; clear_network_caches; wipe_forensic_traces ;;
    backup)      [ "$(id -u)" -eq 0 ] || exit 1; backup_state ;;
    verify)      detect_resetprop >/dev/null 2>&1; detect_modules >/dev/null 2>&1; verify_changes ;;
    diag)        sh "$MODDIR/bootloop_diag.sh" ;;
    rp_test)
        detect_resetprop || exit 1
        TEST_KEY="debug.ternak.rptest"
        TEST_VAL="ok_$(date +%s)"
        rprop_set "$TEST_KEY" "$TEST_VAL"
        if [ "$(rprop_get "$TEST_KEY")" = "$TEST_VAL" ]; then log_ok "rp_test PASSED"; else log_err "rp_test FAILED"; exit 1; fi
        ;;
    settings_get)
        printf '{'
        first=1
        while IFS='=' read -r key val; do
            key="$(echo "$key" | sed 's/#.*//' | tr -d ' \t')"
            val="$(echo "$val" | sed 's/#.*//' | tr -d ' \t')"
            [ -z "$key" ] && continue
            [ $first -eq 0 ] && printf ','
            printf '"%s":"%s"' "$key" "$(escape_json "$val")"
            first=0
        done < "$SETTINGS_FILE"
        printf '}'
        ;;
    settings_set)
        [ "$(id -u)" -eq 0 ] || exit 1
        skey="$2"; sval="$3"
        [ -z "$skey" ] || [ -z "$sval" ] && exit 1
        awk -v k="$skey" -v v="$sval" '
            /^[[:space:]]*#/ { print; next }
            {
                split($0, a, "#"); entry=a[1]; comment=a[2]
                n = split(entry, p, "=")
                key = p[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (key == k) {
                    printf "%s=%s", key, v
                    if (comment != "") printf "       #%s", comment
                    printf "\n"
                } else { print }
            }
        ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        ;;
    unfresh)
        [ "$(id -u)" -eq 0 ] || exit 1
        preflight
        restore_build
        ssaid_revert
        rm -f "$SYSPROP_FILE" "$MODDIR/post-fs-data.sh" "$ACTIVE_PERSONA_FILE" 2>/dev/null
        rm -f "$STATE_DIR/resolved_persona.txt" \
              "$GAID_VALUE_FILE" \
              "$SSAID_TARGETS_FILE" "$SSAID_VALUE_FILE" 2>/dev/null
        rm -f "$PERSONA_DIR"/*.json 2>/dev/null
        log_ok "Unfresh done - reboot recommended"
        ;;
    reboot)      sync && reboot ;;
    *)
        echo "Ternak Device Changer Core Engine v$VERSION"
        ;;
esac
