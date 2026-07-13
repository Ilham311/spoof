#!/system/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC3043,SC2155,SC2086,SC2034,SC2046,SC2015,SC2317
# ============================================================
# Ternak Device Changer - Core Engine v4.12.3 (Android 15)
# HOTFIX #3 atas v4.12.2 (device log Fri 10 Jul 2026 02:38):
#   #9  `--force` CLI flag di persona/fresh: session-scoped bypass
#       PIF filter, tulis semua 17 key termasuk PIF-managed.
#   #10 STATE VERIFY split view: PIF-managed vs Ternak-managed
#       biar user liat perubahan real yang Ternak apply.
#   #11 Warning eksplisit di force mode: PI risk + zygote re-inject.
#
# Fixes retained:
#   v4.12.2 #5-8: readback verify, plain -n flag, debug logging, rp_test
#   v4.12.1 #1-4: BOM strip, PIF selective skip, argv detect, cosmetic
# ============================================================

VERSION="4.12.3-a15-rs"

MODDIR="${MODDIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
[ -z "$MODDIR" ] && MODDIR="/data/adb/modules/ternak_device_changer"

PERSONA_DIR="$MODDIR/personas"
LOG_DIR="$MODDIR/logs"
BACKUP_DIR_ROOT="$MODDIR/backups"
STATE_DIR="$MODDIR/state"
ACTIVE_PERSONA_FILE="$STATE_DIR/active_persona.txt"
SYSPROP_FILE="$MODDIR/system.prop"
SETTINGS_FILE="$MODDIR/sett.txt"

# v4.12.1: kunci-kunci yang PIF/Zygisk-based modules urus (skip di kita)
_PIF_MANAGED_KEYS_RE='^(ro\.product\.(brand|manufacturer|model|name|device)|ro\.build\.(fingerprint|id|tags|type|display\.id))$'

# === Load sett.txt (default semua true jika file tidak ada) ===
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
        key=$(echo "$key" | sed 's/#.*//' | tr -d ' \t')
        val=$(echo "$val" | sed 's/#.*//' | tr -d ' \t')
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

# v4.12.3 FIX #9: cek --force flag di argv (posisi bebas)
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
se_permissive() { SE_PREV=$(getenforce 2>/dev/null); setenforce 0 2>/dev/null || true; }
se_restore()    { [ "$SE_PREV" = "Enforcing" ] && setenforce 1 2>/dev/null; SE_PREV=""; }

# === Settings/cmd wrappers (A15) ===
get_users() {
    pm list users 2>/dev/null | grep -o 'UserInfo{[0-9]\+' | grep -o '[0-9]\+' || echo "0"
}

settings_get() {
    local val
    val=$(cmd settings get "$1" "$2" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ]; then val=$(settings get "$1" "$2" 2>/dev/null); fi
    echo "$val" | tr -d '"\r\n\t'
}
settings_put() { cmd settings put "$1" "$2" "$3" 2>/dev/null || settings put "$1" "$2" "$3" 2>/dev/null; }
settings_del() { cmd settings delete "$1" "$2" 2>/dev/null || settings delete "$1" "$2" 2>/dev/null; }
force_stop()   { cmd activity force-stop "$1" 2>/dev/null || am force-stop "$1" 2>/dev/null; }

# === resetprop wrapper — prefer resetprop-rs (stealth) ===
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
        log_info "resetprop: $RP_MODE → $RESETPROP_BIN"
        return 0
    fi
}

# v4.12.2 FIX #6: RS pake plain `-n` (standard flag)
rprop_set() {
    [ -z "$RESETPROP_BIN" ] && return 1
    "$RESETPROP_BIN" -n "$1" "$2" 2>/dev/null
}

rprop_get() {
    [ -z "$RESETPROP_BIN" ] && return
    "$RESETPROP_BIN" "$1" 2>/dev/null
}

trim_ws() { echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# v4.12.1 FIX #1: BOM strip via head/tail byte-based (toybox sed no \xNN)
_strip_bom() {
    local f="$1"
    [ -f "$f" ] || return 0
    local bom
    bom=$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$bom" = "efbbbf" ]; then
        tail -c +4 "$f" > "$f.nobom" 2>/dev/null && mv "$f.nobom" "$f"
        log_info "Stripped UTF-8 BOM from $(basename "$f")"
    fi
}

_snapshot_build_extended() {
    local snap_file="$STATE_DIR/build_spoof_extended.txt"
    local props="ro.build.fingerprint ro.build.description ro.build.display.id ro.build.id ro.build.tags ro.build.type ro.build.version.incremental ro.build.version.release ro.build.version.security_patch ro.product.brand ro.product.manufacturer ro.product.model ro.product.name ro.boot.verifiedbootstate ro.boot.veritymode ro.boot.flash.locked ro.boot.warranty_bit ro.warranty_bit ro.debuggable ro.secure ro.vendor.build.fingerprint ro.vendor.build.type ro.vendor.build.tags ro.vendor.product.brand ro.vendor.product.manufacturer ro.vendor.product.model"

    [ -f "$snap_file" ] && return 0

    if [ -f "$STATE_DIR/build_spoof_before.txt" ]; then
       log_info "Migrating v4.11 snapshot → extended (augmenting with missing props)"
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

# === Random generators ===
generate_hex()    { dd if=/dev/urandom bs=1 count=$(($1 * 2)) 2>/dev/null | od -An -tx1 | tr -d ' \n' | cut -c1-"$1"; }
generate_uuid()   {
    local u=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    [ -n "$u" ] && echo "$u" || echo "$(generate_hex 8)-$(generate_hex 4)-4$(generate_hex 3)-$(generate_hex 4)-$(generate_hex 12)"
}
generate_serial_samsung() {
    local raw=$(dd if=/dev/urandom bs=1 count=64 2>/dev/null | tr -dc 'A-Z0-9' | cut -c1-14)
    echo "R${raw}"
}
generate_serial_generic() { generate_hex 16 | tr 'a-f' 'A-F'; }
generate_mac() {
    local b1_raw=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    local b1_dec=$(( (0x${b1_raw} & 0xFE) | 0x02 ))
    local b1=$(printf "%02x" $b1_dec)
    local rest=$(dd if=/dev/urandom bs=1 count=5 2>/dev/null | od -An -tx1 | tr -d ' \n')
    echo "${b1}:$(echo $rest | cut -c1-2):$(echo $rest | cut -c3-4):$(echo $rest | cut -c5-6):$(echo $rest | cut -c7-8):$(echo $rest | cut -c9-10)"
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

        if is_on "$DRY_RUN"; then
            log_info "[dry] restore $key -> $val"
            continue
        fi

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
    log_ok "Restore completed: applied=$applied skipped_nodiff=$skipped errs=$errs"
    rm -f "$ACTIVE_PERSONA_FILE"
}

# ============================================================
# PERSONA SYSTEM (v4.12.3)
# ============================================================

_load_real_sdk() {
    REAL_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
    REAL_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
    [ -n "$REAL_SDK" ] || { log_err "Failed to get real SDK version"; return 1; }
    log_info "Real device: SDK=$REAL_SDK release=$REAL_RELEASE"
    return 0
}

# v4.12.3 FIX #9: accept `--force` flag di 2nd arg
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
    local first_line
    first_line="$(head -n 1 "$pfile")"
    if echo "$first_line" | grep -q "^# TARGET_SDK="; then
        target_sdk="$(echo "$first_line" | cut -d'=' -f2 | tr -d ' \r\n')"
    fi

    if [ -n "$target_sdk" ] && [ "$target_sdk" != "$real_sdk" ]; then
        log_err "persona: TARGET_SDK=$target_sdk override rejected (locked to real device SDK=$real_sdk)"
        return 1
    fi

    # v4.12.3 FIX #9: force mode = bypass PIF filter (CLI flag ATAU global setting)
    local pif_active=0
    if [ "$HAS_PIF" = "1" ] && ! is_on "$FORCE_APPLY" && [ "$force_arg" = "0" ]; then
        pif_active=1
        log_info "PIF active — akan skip key yang PIF handle (ro.product.*, ro.build.fingerprint/id/tags/type/display.id), sisanya tetap apply"
    fi

    # v4.12.3 FIX #11: warning eksplisit di force mode
    if [ "$force_arg" = "1" ] || is_on "$FORCE_APPLY"; then
        log_warn "FORCE mode aktif: bypass PIF filter, tulis semua persona keys termasuk PIF-managed"
        log_warn "Risk: PIF module bisa re-inject di zygote spawn; Play Integrity DEVICE verdict bisa flag mismatch"
    fi

    local applied=0 skipped=0 skipped_pif=0 errs=0 line key val malformed=0
    local dbg_count=0
    local before after

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

        if is_on "$DRY_RUN"; then
            log_info "[dry] persona set $key"
            continue
        fi

        before="$(rprop_get "$key")"
        if [ "$before" = "$val" ]; then
            skipped=$((skipped+1))
            [ $dbg_count -lt 3 ] && { log_dbg "$key: already=$val (nodiff)"; dbg_count=$((dbg_count+1)); }
            continue
        fi

        rprop_set "$key" "$val"
        after="$(rprop_get "$key")"

        if [ $dbg_count -lt 3 ]; then
            log_dbg "$key: before='$before' target='$val' after='$after'"
            dbg_count=$((dbg_count+1))
        fi

        if [ "$after" = "$val" ]; then
            applied=$((applied+1))
        else
            errs=$((errs+1))
        fi
    done < "$pfile"

    log_ok "Persona '$persona' applied=$applied skipped_nodiff=$skipped skipped_pif=$skipped_pif errs=$errs (SDK locked to $real_sdk)"
    echo "$persona" > "$ACTIVE_PERSONA_FILE"
}

# === Identifier setters ===
set_android_id_global() {
    local newid="$1"
    [ -z "$newid" ] && newid=$(generate_hex 16)
    settings_put secure android_id "$newid"
    log_ok "Global ANDROID_ID: $newid"
}
wipe_ssaid() {
    log_step "Wipe SSAID per-app..."
    force_stop com.android.settings; sleep 1
    se_permissive
    for u in $(get_users); do
        rm -f "/data/system/users/$u/settings_ssaid.xml" 2>/dev/null
        rm -f "/data/system/users/$u/settings_ssaid.xml.bak" 2>/dev/null
        rm -f "/data/system/users/$u/settings_ssaid.xml.tmp" 2>/dev/null
    done
    se_restore
    log_ok "SSAID wiped (regenerate saat app launch)"
}
set_gaid_value() {
    local newgaid="$1"
    [ -z "$newgaid" ] && newgaid=$(generate_uuid)
    log_step "Set GAID: $newgaid"
    force_stop com.google.android.gms
    am kill com.google.android.gms 2>/dev/null; sleep 1
    se_permissive
    rm -f /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    rm -f /data/data/com.google.android.gms/shared_prefs/adsidentity*.xml 2>/dev/null
    rm -f /data/data/com.google.android.gms/files/adid_cache.dat 2>/dev/null
    rm -rf /data/data/com.google.android.gms/no_backup/adid* 2>/dev/null
    mkdir -p /data/data/com.google.android.gms/shared_prefs 2>/dev/null
    cat > /data/data/com.google.android.gms/shared_prefs/adid_settings.xml <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="adid_key">$newgaid</string>
    <boolean name="enable_limit_ad_tracking" value="false" />
    <long name="last_reset_time" value="$(date +%s)000" />
</map>
EOF
    local gms_uid=$(stat -c '%u' /data/data/com.google.android.gms 2>/dev/null)
    [ -n "$gms_uid" ] && chown $gms_uid:$gms_uid /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    chmod 660 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    settings_put global advertising_id "$newgaid"
    se_restore
    log_ok "GAID set: $newgaid"
}
randomize_wlan_mac() {
    local newmac="$1"
    [ -z "$newmac" ] && newmac=$(generate_mac)
    log_step "Randomize wlan0 MAC: $newmac"
    se_permissive
    ip link set wlan0 down 2>/dev/null; sleep 1
    ip link set dev wlan0 address "$newmac" 2>/dev/null && log_ok "MAC: $newmac" || log_warn "MAC change rejected by driver"
    ip link set wlan0 up 2>/dev/null
    rm -f /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml 2>/dev/null
    rm -f /data/misc/apexdata/com.android.wifi/WifiConfigStore.xml.encrypted-checkpoint 2>/dev/null
    se_restore
}
randomize_device_name() {
    log_step "Randomize device/BT name..."
    local BRANDS="Galaxy Pixel Redmi Mi Poco Realme OnePlus Nothing Honor Oppo Vivo Asus"
    local MODELS="S24 S25 Note13 9Pro 14Ultra F6 12R 11R X100 FindX7 Magic6 Zero2 ROG8 K70 Edge"
    local nb=$(echo $BRANDS | wc -w)
    local nm=$(echo $MODELS | wc -w)
    local r1=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % nb + 1 ))
    local r2=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % nm + 1 ))
    local nonce=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 900 + 100 ))
    local b=$(echo $BRANDS | cut -d' ' -f$r1)
    local m=$(echo $MODELS | cut -d' ' -f$r2)
    local NEW_NAME="$b $m-$nonce"

    log_info "New BT name target: $NEW_NAME"

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
    [ $updated -eq 0 ] && log_warn "bt_config.conf belum ada / not writable — BT akan generate file fresh next start"
    se_restore

    log_step "Restart bluetooth process..."
    force_stop com.android.bluetooth
    pkill -f 'com\.(android|google\.android)\.bluetooth' 2>/dev/null
    sleep 1

    log_ok "Name: $NEW_NAME (com.android.bluetooth restarted — buka Settings→Bluetooth)"
}
randomize_hostname() {
    local nonce=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 9000 + 1000 ))
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
    log_info "Root: $ROOT_MGR"
}
detect_modules() {
    HAS_PIF=0; HAS_SPECTER=0; HAS_ZYGISK_NEXT=0
    [ -d /data/adb/modules/playintegrityfix ] && HAS_PIF=1
    [ -d /data/adb/modules/specter ] && HAS_SPECTER=1
    if [ -d /data/adb/modules/zygisksu ] || [ -d /data/adb/modules/zygisknext ]; then HAS_ZYGISK_NEXT=1; fi
    SDK=$(getprop ro.build.version.sdk 2>/dev/null)
    local rp_str="no"
    [ -n "$RESETPROP_BIN" ] && rp_str="yes $RESETPROP_BIN"
    log_info "SDK=$SDK PIF=$HAS_PIF Specter=$HAS_SPECTER ZygiskNext=$HAS_ZYGISK_NEXT RP=$rp_str"
}
check_root() { [ "$(id -u)" -eq 0 ] || { log_err "Need root"; exit 1; }; }
preflight() {
    check_root
    detect_resetprop
    detect_root_manager
    detect_modules
    [ $HAS_PIF -eq 1 ] && log_info "PIF detected — persona akan skip 10 key yang PIF handle, sisanya (vendor.*, boot.*, security_patch, dll) tetap apply. Pake --force buat bypass."
    [ $HAS_SPECTER -eq 0 ] && log_warn "Specter tidak terinstall — root bisa terdeteksi"
}

# === Backup ===
backup_state() {
    local bdir="$BACKUP_DIR_ROOT/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bdir"
    settings_get secure android_id     > "$bdir/android_id"
    settings_get global bluetooth_name > "$bdir/bluetooth_name"
    settings_get global advertising_id > "$bdir/advertising_id"
    getprop net.hostname               > "$bdir/hostname"
    getprop ro.serialno                > "$bdir/serialno"
    getprop ro.product.model           > "$bdir/model"
    getprop ro.build.fingerprint       > "$bdir/fingerprint"
    chmod 600 "$bdir"/* 2>/dev/null
    log_ok "Backup: $bdir"
}

# === App ops + wipes ===
freeze_targets() {
    log_step "Force-stop targets + GMS/GSF..."
    for pkg in $FID_TARGETS; do force_stop "$pkg"; done
    sleep 2; log_ok "Frozen"
}
clear_target_apps() {
    log_step "pm clear targets..."
    for pkg in $TARGET_APPS; do
        if pm list packages 2>/dev/null | grep -q "package:$pkg"; then
            for u in $(get_users); do
                pm clear --user "$u" "$pkg" >/dev/null 2>&1 && log_ok "Cleared: $pkg (user $u)" || log_err "Failed: $pkg (user $u)"
            done
        else log_warn "$pkg not installed"; fi
    done
}
clear_sdcard_residue() {
    log_step "Wipe SDcard residue..."
    se_permissive
    for pkg in $TARGET_APPS; do
        rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null
    done
    se_restore; log_ok "SDcard cleared"
}
wipe_firebase_iid() {
    log_step "Wipe Firebase IID..."
    se_permissive
    for pkg in $FID_TARGETS; do
        rm -f /data/data/$pkg/shared_prefs/PersistedInstallation.*.json 2>/dev/null
        rm -f /data/data/$pkg/files/PersistedInstallation.* 2>/dev/null
        rm -f /data/data/$pkg/shared_prefs/com.google.firebase.*.xml 2>/dev/null
        rm -f /data/data/$pkg/shared_prefs/com.google.android.gms.*.xml 2>/dev/null
        rm -rf /data/data/$pkg/databases/google_app_measurement_local.db* 2>/dev/null
        rm -rf /data/data/$pkg/databases/firebase-* 2>/dev/null
    done
    se_restore; log_ok "Firebase IID wiped"
}
reset_gsf_id() {
    log_step "Reset GSF ID..."
    force_stop com.google.android.gsf
    se_permissive
    rm -f /data/data/com.google.android.gsf/databases/gservices.db* 2>/dev/null
    rm -f /data/data/com.google.android.gsf/databases/Checkin.db* 2>/dev/null
    se_restore; log_ok "GSF ID regenerated next boot"
}
wipe_mediadrm() {
    log_step "Wipe MediaDrm L3..."
    se_permissive
    rm -rf /data/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/ 2>/dev/null
    for u in $(get_users); do
        rm -rf "/data/system/users/$u/drm/" 2>/dev/null
    done
    rm -rf /data/misc/mediadrm/ 2>/dev/null
    se_restore
    pkill -f mediadrmserver 2>/dev/null; pkill -f android.hardware.drm 2>/dev/null
    log_ok "MediaDrm L3 wiped"
}
clear_network_caches() {
    log_step "Wipe network caches..."
    se_permissive
    rm -rf /data/misc/net/* /data/misc/connectivity/* 2>/dev/null
    rm -f /data/misc/dhcp/*.lease /data/misc/dhcp-6.8/*.lease 2>/dev/null
    rm -rf /data/misc/netstats/* /data/system/netstats/* 2>/dev/null
    se_restore
    ndc resolver clearnetdns 0 2>/dev/null
    log_ok "Network caches cleared"
}
wipe_forensic_traces() {
    log_step "Wipe forensic traces..."
    logcat -c 2>/dev/null; logcat -b all -c 2>/dev/null
    se_permissive
    rm -rf /data/anr/* /data/tombstones/* /data/system/dropbox/* 2>/dev/null
    for u in $(get_users); do
        rm -rf "/data/system/usagestats/$u/"* 2>/dev/null
        rm -rf "/data/system/users/$u/recent_tasks/"* "/data/system/users/$u/recent_images/"* 2>/dev/null
    done
    rm -rf /data/system/procstats/* 2>/dev/null
    rm -rf /data/system/heapdump/* 2>/dev/null
    se_restore; log_ok "Forensics cleared"
}
wipe_clipboard() { cmd clipboard set-text "" 2>/dev/null; log_ok "Clipboard cleared"; }

# === Persona snapshot (display saja) ===
save_persona_snapshot() {
    local pkg="$1"
    local f="$PERSONA_DIR/${pkg}.json"
    local aid=$(settings_get secure android_id); [ -z "$aid" ] && aid=$(generate_hex 16)
    local gaid_val=$(settings_get global advertising_id); [ -z "$gaid_val" ] && gaid_val=$(generate_uuid)
    local pname="unknown"
    [ -f "$ACTIVE_PERSONA_FILE" ] && pname=$(cat "$ACTIVE_PERSONA_FILE")
    local now=$(date +%s)000
    local age=$(( ($(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 30) + 1 ))
    cat > "$f" <<EOF
{
  "package": "$pkg",
  "profile": "$pname",
  "androidId": "$aid",
  "gaid": "$gaid_val",
  "createdAt": $now,
  "ageDays": $age
}
EOF
    chmod 644 "$f"
    log_ok "Snapshot: $pkg → $pname"
}

burn_persona() {
    local pkg="$1"
    log_step "Burn: $pkg"
    rm -f "$PERSONA_DIR/${pkg}.json"
    force_stop "$pkg"
    for u in $(get_users); do
        pm clear --user "$u" "$pkg" >/dev/null 2>&1 && log_ok "App data cleared (user $u)"
    done
    se_permissive
    rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null
    rm -f /data/data/$pkg/shared_prefs/PersistedInstallation.*.json 2>/dev/null
    rm -f /data/data/$pkg/files/PersistedInstallation.* 2>/dev/null
    se_restore
    set_gaid_value
    wipe_ssaid
    restore_build
    save_persona_snapshot "$pkg"
    log_ok "$pkg ready for new account"
}

# === FRESH IDENTITY pipeline ===
do_fresh() {
    preflight
    log_info "=== TERNAK FRESH IDENTITY v$VERSION ==="
    is_on "$ENABLE_BACKUP" && backup_state

    # v4.12.3: argv parsing — persona bisa di $1, force flag bisa di $1/$2/$3
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
            log_err "Persona '$persona_arg' not found — aborting"
            log_info "Available: $(list_personas_available)"
            return 1
        fi
        ENABLE_SPOOF_PERSONA=true
        log_info "Persona argv detected: $persona_arg — ENABLE_SPOOF_PERSONA=true (session override)"
    elif [ -f "$ACTIVE_PERSONA_FILE" ]; then
        persona_arg="$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null)"
        if [ -n "$persona_arg" ]; then
            ENABLE_SPOOF_PERSONA=true
            log_info "Active persona from state: $persona_arg — auto-apply enabled"
        fi
    fi

    if is_on "$ENABLE_SPOOF_PERSONA" && [ -n "$persona_arg" ]; then
        if [ "$force_arg" = "1" ]; then
            spoof_build_persona "$persona_arg" --force || log_warn "Persona apply had errors, continuing pipeline"
        else
            spoof_build_persona "$persona_arg" || log_warn "Persona apply had errors, continuing pipeline"
        fi
    else
        log_info "ENABLE_SPOOF_PERSONA=false atau persona kosong — skip profile"
    fi

    local new_gaid=$(generate_uuid)
    local new_aid=$(generate_hex 16)

    freeze_targets
    if is_on "$ENABLE_CLEAR_APPS";    then clear_target_apps;    else log_info "ENABLE_CLEAR_APPS=false — skip";    fi
    if is_on "$ENABLE_WIPE_SDCARD";   then clear_sdcard_residue; else log_info "ENABLE_WIPE_SDCARD=false — skip";   fi
    if is_on "$ENABLE_WIPE_FIREBASE"; then wipe_firebase_iid;    else log_info "ENABLE_WIPE_FIREBASE=false — skip"; fi
    if is_on "$ENABLE_WIPE_MEDIADRM"; then wipe_mediadrm;        else log_info "ENABLE_WIPE_MEDIADRM=false — skip"; fi
    if is_on "$ENABLE_RESET_GSF";     then reset_gsf_id;         else log_info "ENABLE_RESET_GSF=false — skip";     fi

    if is_on "$ENABLE_ANDROID_ID"; then
        wipe_ssaid
        set_android_id_global "$new_aid"
    else
        log_info "ENABLE_ANDROID_ID=false — skip"
    fi
    if is_on "$ENABLE_GAID";          then set_gaid_value "$new_gaid"; else log_info "ENABLE_GAID=false — skip";          fi
    if is_on "$ENABLE_BT_NAME";       then randomize_device_name;      else log_info "ENABLE_BT_NAME=false — skip";       fi
    if is_on "$ENABLE_HOSTNAME";      then randomize_hostname;          else log_info "ENABLE_HOSTNAME=false — skip";      fi
    if is_on "$ENABLE_MAC_RANDOM";    then randomize_wlan_mac;          else log_info "ENABLE_MAC_RANDOM=false — skip";    fi
    if is_on "$ENABLE_CLEAR_NETWORK"; then clear_network_caches;        else log_info "ENABLE_CLEAR_NETWORK=false — skip"; fi

    if is_on "$ENABLE_PERSONAS"; then
        rm -f "$PERSONA_DIR"/*.json 2>/dev/null
        for pkg in $TARGET_APPS; do save_persona_snapshot "$pkg"; done
    else
        log_info "ENABLE_PERSONAS=false — skip"
    fi

    if is_on "$ENABLE_WIPE_CLIPBOARD"; then wipe_clipboard;       else log_info "ENABLE_WIPE_CLIPBOARD=false — skip"; fi
    if is_on "$ENABLE_WIPE_FORENSIC";  then wipe_forensic_traces; else log_info "ENABLE_WIPE_FORENSIC=false — skip";  fi
    echo ""; verify_changes; echo ""
    log_ok "FRESH IDENTITY READY"
    log_info "Recommend reboot supaya semua Build.* props fully propagated."
}

# === Info / verify (JSON for WebUI) ===
get_info() {
    local android_id=$(settings_get secure android_id)
    local bt_name=$(settings_get global bluetooth_name)
    local hostname_val=$(getprop net.hostname | tr -d '"\r\n\t')
    [ -z "$hostname_val" ] && hostname_val=$(hostname 2>/dev/null | tr -d '"\r\n\t')
    local gaid=$(settings_get global advertising_id)
    local model=$(getprop ro.product.model | tr -d '"\r\n\t')
    local brand=$(getprop ro.product.brand | tr -d '"\r\n\t')
    local serial=$(getprop ro.serialno | tr -d '"\r\n\t')
    local fingerprint=$(getprop ro.build.fingerprint | tr -d '"\r\n\t')
    local sdk=$(getprop ro.build.version.sdk | tr -d '"\r\n\t')
    local profile_name="-"
    [ -f "$ACTIVE_PERSONA_FILE" ] && profile_name=$(cat "$ACTIVE_PERSONA_FILE")
    [ -z "$android_id" ] || [ "$android_id" = "null" ] && android_id="—"
    [ -z "$gaid" ] || [ "$gaid" = "null" ] && gaid="—"
    [ -z "$bt_name" ] || [ "$bt_name" = "null" ] && bt_name="—"
    local persona_count=$(ls "$PERSONA_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    local pif=$([ $HAS_PIF -eq 1 ] && echo true || echo false)
    local specter=$([ $HAS_SPECTER -eq 1 ] && echo true || echo false)
    local zygnext=$([ $HAS_ZYGISK_NEXT -eq 1 ] && echo true || echo false)
    local rp_ok="$([ -n "$RESETPROP_BIN" ] && echo true || echo false)"
    local rp_mode_out="${RP_MODE:-none}"
    printf '{"android_id":"%s","bt_name":"%s","hostname":"%s","gaid":"%s","model":"%s","brand":"%s","serial":"%s","fingerprint":"%s","sdk":"%s","profile":"%s","root_manager":"%s","persona_count":%s,"modules":{"pif":%s,"specter":%s,"zygisk_next":%s,"resetprop":%s,"resetprop_mode":"%s"}}' \
        "$android_id" "$bt_name" "$hostname_val" "$gaid" "$model" "$brand" "$serial" "$fingerprint" "$sdk" \
        "$profile_name" "$ROOT_MGR" "$persona_count" "$pif" "$specter" "$zygnext" "$rp_ok" "$rp_mode_out"
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
        printf '"%s"' "$(basename "$p" .txt)"
        first_val=0
    done
    printf '],"custom":['
    local first_cust=1
    for p in "$PERSONA_DIR/custom/"*.txt; do
        [ -f "$p" ] || continue
        [ $first_cust -eq 0 ] && printf ','
        printf '"%s"' "$(basename "$p" .txt)"
        first_cust=0
    done
    printf ']}'
}

# v4.12.3 FIX #10: split view PIF-managed vs Ternak-managed
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

# === Router ===
case "$1" in
    info)        detect_resetprop >/dev/null 2>&1; detect_root_manager >/dev/null 2>&1; detect_modules >/dev/null 2>&1; get_info ;;
    fresh|full)  shift; do_fresh "$@" ;;
    persona)     preflight; shift; spoof_build_persona "$@" ;;
    personas_list) list_personas_available ;;
    personas_active) list_personas ;;
    restore_build) preflight; restore_build ;;
    preflight)   preflight ;;
    burn)        preflight; [ -z "$2" ] && { log_err "Usage: $0 burn <pkg>"; exit 1; }; burn_persona "$2" ;;
    burn_all)    preflight; for pkg in $TARGET_APPS; do burn_persona "$pkg"; done ;;
    aid)         preflight; wipe_ssaid; set_android_id_global "$2" ;;
    gaid)        preflight; set_gaid_value "$2" ;;
    mac)         preflight; randomize_wlan_mac "$2" ;;
    deep_wipe)   preflight; freeze_targets; wipe_mediadrm; reset_gsf_id; wipe_firebase_iid; clear_network_caches; wipe_forensic_traces ;;
    backup)      check_root; backup_state ;;
    verify)      detect_resetprop >/dev/null 2>&1; detect_modules >/dev/null 2>&1; verify_changes ;;
    diag)        sh "$MODDIR/bootloop_diag.sh" ;;
    rp_test)
        detect_resetprop || { log_err "resetprop not found"; exit 1; }
        TEST_KEY="debug.ternak.rptest"
        TEST_VAL="ok_$(date +%s)"
        log_info "rp_test: setting $TEST_KEY=$TEST_VAL via $RP_MODE mode"
        before="$(rprop_get "$TEST_KEY")"
        rprop_set "$TEST_KEY" "$TEST_VAL"
        after="$(rprop_get "$TEST_KEY")"
        log_info "before='$before' after='$after' target='$TEST_VAL'"
        if [ "$after" = "$TEST_VAL" ]; then
            log_ok "rp_test PASSED — resetprop-rs writes work"
        else
            log_err "rp_test FAILED — resetprop-rs ga bisa nulis, coba pake legacy resetprop"
            exit 1
        fi
        ;;
    settings_get)
        printf '{'
        first=1
        while IFS='=' read -r key val; do
            key=$(echo "$key" | sed 's/#.*//' | tr -d ' \t')
            val=$(echo "$val" | sed 's/#.*//' | tr -d ' \t')
            [ -z "$key" ] && continue
            [ $first -eq 0 ] && printf ','
            val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
            printf '"%s":"%s"' "$key" "$val"
            first=0
        done < "$SETTINGS_FILE"
        printf '}'
        ;;
    settings_set)
        check_root
        skey="$2"; sval="$3"
        [ -z "$skey" ] || [ -z "$sval" ] && { log_err "Usage: $0 settings_set KEY true|false"; exit 1; }
        case "$sval" in true|false) ;; *) log_err "Nilai harus 'true' atau 'false'"; exit 1 ;; esac
        [ -f "$SETTINGS_FILE" ] || { log_err "sett.txt tidak ditemukan: $SETTINGS_FILE"; exit 1; }
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
        load_settings
        log_ok "Settings: $skey=$sval"
        ;;
    unfresh)
        check_root
        rm -f "$SYSPROP_FILE" 2>/dev/null && log_ok "system.prop removed"
        rm -f "$MODDIR/post-fs-data.sh" 2>/dev/null && log_ok "post-fs-data.sh removed"
        rm -f "$ACTIVE_PERSONA_FILE" 2>/dev/null && log_ok "persona state cleared"
        rm -f "$PERSONA_DIR"/*.json 2>/dev/null && log_ok "personas wiped"
        log_warn "Reboot untuk back ke build asli." ;;
    reboot)      sync && reboot ;;
    *)
        cat <<EOF
Ternak Device Changer v$VERSION (Android 15)
Usage: $0 <command> [args] [--force]

Main:
  fresh [persona] [--force]   FRESH identity pipeline (persona + AID + GAID + MAC + clear)
  full                        Alias 'fresh'
  persona <name> [--force]    Apply persona only (e.g. pixel8pro_a15)
                              --force = bypass PIF filter, tulis semua 17 key
  personas_list     List validated and custom personas (JSON)
  personas_active   List burnable snapshot personas (JSON)
  restore_build     Restore build properties from extended snapshot
  preflight         Run health checks
  rp_test           Sanity check: verify resetprop actually writes props
  unfresh           RECOVERY: wipe system.prop + persona (rollback ke build asli)
  diag              Diagnosa penyebab bootloop, simpan log ke logs/

Targeted:
  burn <pkg>        Burn 1 app + new identifier
  burn_all          Burn semua
  aid [hex16]       Set ANDROID_ID + wipe SSAID
  gaid [uuid]       Set GAID via adid_settings.xml
  mac [aa:..:ff]    Randomize wlan0 MAC

Settings:
  settings_get      Tampilkan semua setting sebagai JSON
  settings_set KEY true|false   Ubah nilai setting (update sett.txt)

Maintenance:
  info | personas_list | personas_active | deep_wipe | backup | verify | reboot
EOF
        ;;
esac