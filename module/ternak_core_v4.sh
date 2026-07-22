#!/system/bin/sh
# ============================================================
# Ternak Device Changer — core.sh
# v4.13-a15-rs (spoof.prop always written; Zygisk full-field fix)
# ============================================================
VERSION="4.13-a15-rs"

MODDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -z "$MODDIR" ] && MODDIR="/data/adb/modules/ternak_device_changer"

PERSONA_DIR="$MODDIR/personas"
LOG_DIR="$MODDIR/logs"
BACKUP_DIR_ROOT="$MODDIR/backups"
PROFILE_FILE="$MODDIR/current_profile.txt"
SYSPROP_FILE="$MODDIR/system.prop"
REBOOT_NEEDED=0

TARGET_APPS="com.shopee.id com.tokopedia.tkpd com.ss.android.ugc.trill com.liuzh.deviceinfo com.zhiliaoapp.musically"
FID_TARGETS="$TARGET_APPS com.google.android.gms com.google.android.gsf"

mkdir -p "$PERSONA_DIR" "$LOG_DIR" "$BACKUP_DIR_ROOT" 2>/dev/null
chmod 0755 "$PERSONA_DIR" 2>/dev/null
chmod 0700 "$LOG_DIR" "$BACKUP_DIR_ROOT" 2>/dev/null
LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"

# === Logging ===
log()      { m="[$(date '+%H:%M:%S')] $1"; echo "$m"; echo "$m" >> "$LOG_FILE" 2>/dev/null; }
log_ok()   { log "[+] $1"; }
log_info() { log "[i] $1"; }
log_warn() { log "[!] $1"; }
log_err()  { log "[-] $1"; }
log_step() { log "[...] $1"; }

# === SELinux helper (depth-counter) ===
SE_DEPTH=0
SE_ORIG=""
se_permissive() {
    [ "$SE_DEPTH" -eq 0 ] && SE_ORIG=$(getenforce 2>/dev/null)
    SE_DEPTH=$((SE_DEPTH+1))
    setenforce 0 2>/dev/null || true
}
se_restore() {
    [ "$SE_DEPTH" -gt 0 ] && SE_DEPTH=$((SE_DEPTH-1))
    if [ "$SE_DEPTH" -eq 0 ] && [ "$SE_ORIG" = "Enforcing" ]; then setenforce 1 2>/dev/null; fi
}

# === settings/cmd wrappers (A15) ===
get_users() {
    pm list users 2>/dev/null | grep -o 'UserInfo{[0-9]\+' | grep -o '[0-9]\+' || echo "0"
}
settings_get() {
    val=$(cmd settings get "$1" "$2" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ]; then val=$(settings get "$1" "$2" 2>/dev/null); fi
    echo "$val" | tr -d '"\r\n\t'
}
settings_put() { cmd settings put "$1" "$2" "$3" 2>/dev/null || settings put "$1" "$2" "$3" 2>/dev/null; }
settings_del() { cmd settings delete "$1" "$2" 2>/dev/null || settings delete "$1" "$2" 2>/dev/null; }
force_stop()   { cmd activity force-stop "$1" 2>/dev/null || am force-stop "$1" 2>/dev/null; }

# ============================================================
# resetprop-rs — WAJIB
# ============================================================
RP=""
RP_RS="$MODDIR/bin/resetprop-rs"
RP_STEALTH_OK=0

rp_stealth_selftest() {
    k="ternak.st.$$"; v="ok$(date +%s)"
    "$RP" -st "$k" "$v" 2>/dev/null
    got=$(getprop "$k" 2>/dev/null)
    "$RP" -nk "$k" 2>/dev/null
    [ "$got" = "$v" ]
}
detect_resetprop() {
    [ -f "$RP_RS" ] && chmod +x "$RP_RS" 2>/dev/null
    if   [ -x "$RP_RS" ];                         then RP="$RP_RS"
    elif command -v resetprop-rs >/dev/null 2>&1; then RP="resetprop-rs"
    fi
    if [ -z "$RP" ]; then
        log_err "resetprop-rs WAJIB tapi tidak ditemukan di $RP_RS atau PATH."
        return 1
    fi
    log_info "resetprop-rs: $RP"
    if rp_stealth_selftest; then
        RP_STEALTH_OK=1; log_info "stealth (-st) OK"
    else
        RP_STEALTH_OK=0; log_warn "stealth (-st) gagal selftest — pakai resetprop-rs mode -n"
    fi
    return 0
}
_rp_put() {
    case "$1" in persist.*) _P="-p" ;; *) _P="" ;; esac
    if [ "$RP_STEALTH_OK" = "1" ]; then "$RP" -st $_P "$1" "$2" 2>/dev/null
    else "$RP" -n $_P "$1" "$2" 2>/dev/null; fi
}
rp_set() {
    k="$1"; v="$2"
    [ -z "$RP" ] && return 1
    _rp_put "$k" "$v"
    got=$(getprop "$k" 2>/dev/null)
    if [ "$got" != "$v" ]; then
        _rp_put "$k" "$v"
        got=$(getprop "$k" 2>/dev/null)
    fi
    if [ "$got" != "$v" ] && [ "$RP_STEALTH_OK" = "1" ]; then
        case "$k" in persist.*) "$RP" -n -p "$k" "$v" 2>/dev/null ;; *) "$RP" -n "$k" "$v" 2>/dev/null ;; esac
        got=$(getprop "$k" 2>/dev/null)
    fi
    [ "$got" != "$v" ] && log_warn "prop $k gagal (want=$v got=$got)"
}
rp_del() {
    [ -z "$RP" ] && return 1
    if [ "$RP_STEALTH_OK" = "1" ]; then "$RP" -nk "$1" 2>/dev/null; else "$RP" -d "$1" 2>/dev/null; fi
}
rp_seal() {
    [ "$RP_STEALTH_OK" = "1" ] || return 1
    "$RP" --seal "$1" "$2" 2>/dev/null || "$RP" --seal-arena "$1" "$2" 2>/dev/null
}
rp() { rp_set "$1" "$2"; }

rp_bulk() {
    [ -z "$RP" ] && return 1
    bf="$MODDIR/.ternak_bulk.$$"
    : > "$bf"
    while IFS=' ' read -r bk bv; do
        [ -z "$bk" ] && continue
        printf '%s=%s\n' "$bk" "$bv" >> "$bf"
    done
    if [ "$RP_STEALTH_OK" = "1" ]; then "$RP" -st -f "$bf" 2>/dev/null; else "$RP" -n -f "$bf" 2>/dev/null; fi
    while IFS='=' read -r bk bv; do
        [ -z "$bk" ] && continue
        [ "$(getprop "$bk" 2>/dev/null)" = "$bv" ] || rp_set "$bk" "$bv"
    done < "$bf"
    rm -f "$bf" 2>/dev/null
}

seal_all() {
    [ "$RP_STEALTH_OK" = "1" ] || { log_warn "seal butuh stealth resetprop-rs yang berfungsi"; return 1; }
    [ -f "$PROFILE_FILE" ] || { log_warn "no active profile to seal"; return 1; }
    pname=$(cut -d'|' -f1 "$PROFILE_FILE")
    load_profile "$pname" >/dev/null 2>&1 || return 1
    log_step "Sealing display props (Tier B batch)..."
    if "$RP" --seal ro.product.model --check >/dev/null 2>&1; then log_info "seal --check OK"; else log_warn "seal --check gagal"; fi
    set -- --seal ro.product.brand "$P_BRAND" \
           --seal ro.product.manufacturer "$P_MANUFACTURER" \
           --seal ro.product.model "$P_MODEL" \
           --seal ro.product.device "$P_DEVICE" \
           --seal ro.product.name "$P_PRODUCT" \
           --seal ro.build.fingerprint "$P_FINGERPRINT" \
           --seal ro.build.id "$P_BUILD_ID"
    if "$RP" "$@" 2>/dev/null; then
        log_ok "Sealed (Tier B batch)."
    else
        log_warn "Tier B batch gagal — fallback Tier A per-prop."
        rp_seal ro.product.brand "$P_BRAND"; rp_seal ro.product.model "$P_MODEL"; rp_seal ro.build.fingerprint "$P_FINGERPRINT"
    fi
    log_info "Seal in-session; RE-SEAL tiap boot via post-fs-data.sh."
}

# === Random generators ===
generate_hex()  { dd if=/dev/urandom bs=1 count=$(( ($1 + 1) / 2 )) 2>/dev/null | od -An -tx1 | tr -d ' \n' | cut -c1-"$1"; }
generate_uuid() {
    u=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    if [ -n "$u" ]; then echo "$u"; return; fi
    var=$(printf '%x' $(( ( 0x$(generate_hex 1) & 0x3 ) | 0x8 )))
    echo "$(generate_hex 8)-$(generate_hex 4)-4$(generate_hex 3)-${var}$(generate_hex 3)-$(generate_hex 12)"
}
generate_serial_samsung() { raw=$(dd if=/dev/urandom bs=1 count=64 2>/dev/null | tr -dc 'A-Z0-9' | cut -c1-10); echo "R${raw}"; }
generate_serial_generic() { generate_hex 16 | tr 'a-f' 'A-F'; }
generate_mac() {
    b1_raw=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    b1_dec=$(( (0x${b1_raw} & 0xFE) | 0x02 ))
    b1=$(printf "%02x" $b1_dec)
    rest=$(dd if=/dev/urandom bs=1 count=5 2>/dev/null | od -An -tx1 | tr -d ' \n')
    echo "${b1}:$(echo $rest | cut -c1-2):$(echo $rest | cut -c3-4):$(echo $rest | cut -c5-6):$(echo $rest | cut -c7-8):$(echo $rest | cut -c9-10)"
}

# === Device profile pool (v4.13: +BOOTLOADER/HOST/USER/CODENAME/INITIAL_SDK) ===
profile_pixel9pro() { PROFILE_NAME="Pixel 9 Pro XL"; P_BRAND="google"; P_MANUFACTURER="Google"; P_MODEL="Pixel 9 Pro XL"; P_DEVICE="komodo"; P_PRODUCT="komodo"; P_BOARD="komodo"; P_HARDWARE="komodo"; P_PLATFORM="zuma_pro"; P_FINGERPRINT="google/komodo/komodo:15/AP3A.241105.007/12686056:user/release-keys"; P_DESCRIPTION="komodo-user 15 AP3A.241105.007 12686056 release-keys"; P_BUILD_ID="AP3A.241105.007"; P_INCREMENTAL="12686056"; P_RELEASE="15"; P_SDK="35"; P_INITIAL_SDK="33"; P_SECURITY_PATCH="2024-11-05"; P_TAGS="release-keys"; P_TYPE="user"; P_BOOTLOADER="komodo-1.0-12345678"; P_HOST="abfarm-release"; P_USER="android-build"; P_CODENAME="REL"; }
profile_s24ultra()  { PROFILE_NAME="Galaxy S24 Ultra"; P_BRAND="samsung"; P_MANUFACTURER="samsung"; P_MODEL="SM-S928B"; P_DEVICE="e3q"; P_PRODUCT="e3qxxx"; P_BOARD="e3q"; P_HARDWARE="qcom"; P_PLATFORM="pineapple"; P_FINGERPRINT="samsung/e3qxxx/e3q:14/UP1A.231005.007/S928BXXU3BXIB:user/release-keys"; P_DESCRIPTION="e3qxxx-user 14 UP1A.231005.007 S928BXXU3BXIB release-keys"; P_BUILD_ID="UP1A.231005.007"; P_INCREMENTAL="S928BXXU3BXIB"; P_RELEASE="14"; P_SDK="34"; P_INITIAL_SDK="33"; P_SECURITY_PATCH="2024-09-01"; P_TAGS="release-keys"; P_TYPE="user"; P_BOOTLOADER="S928BXXU3BXIB"; P_HOST="21DKC518"; P_USER="dpi"; P_CODENAME="REL"; }
profile_xiaomi14()  { PROFILE_NAME="Xiaomi 14"; P_BRAND="Xiaomi"; P_MANUFACTURER="Xiaomi"; P_MODEL="23127PN0CG"; P_DEVICE="houji"; P_PRODUCT="houji"; P_BOARD="houji"; P_HARDWARE="qcom"; P_PLATFORM="pineapple"; P_FINGERPRINT="Xiaomi/houji/houji:14/UKQ1.231003.002/V816.0.4.0.UNCMIXM:user/release-keys"; P_DESCRIPTION="houji-user 14 UKQ1.231003.002 V816.0.4.0.UNCMIXM release-keys"; P_BUILD_ID="UKQ1.231003.002"; P_INCREMENTAL="V816.0.4.0.UNCMIXM"; P_RELEASE="14"; P_SDK="34"; P_INITIAL_SDK="33"; P_SECURITY_PATCH="2024-07-01"; P_TAGS="release-keys"; P_TYPE="user"; P_BOOTLOADER="unknown"; P_HOST="pangu-build"; P_USER="builder"; P_CODENAME="REL"; }
profile_oneplus12() { PROFILE_NAME="OnePlus 12"; P_BRAND="OnePlus"; P_MANUFACTURER="OnePlus"; P_MODEL="CPH2583"; P_DEVICE="OP595DL1"; P_PRODUCT="CPH2583EEA"; P_BOARD="kalama"; P_HARDWARE="qcom"; P_PLATFORM="kalama"; P_FINGERPRINT="OnePlus/CPH2583EEA/OP595DL1:14/UP1A.231005.007/U.5e7ab59_3_4f9e0d0:user/release-keys"; P_DESCRIPTION="OP595DL1-user 14 UP1A.231005.007 release-keys"; P_BUILD_ID="UP1A.231005.007"; P_INCREMENTAL="U.5e7ab59_3_4f9e0d0"; P_RELEASE="14"; P_SDK="34"; P_INITIAL_SDK="33"; P_SECURITY_PATCH="2024-08-01"; P_TAGS="release-keys"; P_TYPE="user"; P_BOOTLOADER="unknown"; P_HOST="ubuntu"; P_USER="jenkins"; P_CODENAME="REL"; }
profile_pixel8pro() { PROFILE_NAME="Pixel 8 Pro"; P_BRAND="google"; P_MANUFACTURER="Google"; P_MODEL="Pixel 8 Pro"; P_DEVICE="husky"; P_PRODUCT="husky"; P_BOARD="husky"; P_HARDWARE="husky"; P_PLATFORM="zuma"; P_FINGERPRINT="google/husky/husky:14/AP2A.240805.005/12025142:user/release-keys"; P_DESCRIPTION="husky-user 14 AP2A.240805.005 12025142 release-keys"; P_BUILD_ID="AP2A.240805.005"; P_INCREMENTAL="12025142"; P_RELEASE="14"; P_SDK="34"; P_INITIAL_SDK="33"; P_SECURITY_PATCH="2024-08-05"; P_TAGS="release-keys"; P_TYPE="user"; P_BOOTLOADER="husky-1.2-12025142"; P_HOST="abfarm-release"; P_USER="android-build"; P_CODENAME="REL"; }

PROFILES_LIST="pixel9pro s24ultra xiaomi14 oneplus12 pixel8pro"
pick_random_profile() {
    count=$(echo $PROFILES_LIST | wc -w)
    rand=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % count ))
    i=0
    for p in $PROFILES_LIST; do [ $i -eq $rand ] && { echo "$p"; return; }; i=$((i+1)); done
    echo "pixel8pro"
}
load_profile() {
    case "$1" in
        pixel9pro) profile_pixel9pro ;;
        s24ultra)  profile_s24ultra ;;
        xiaomi14)  profile_xiaomi14 ;;
        oneplus12) profile_oneplus12 ;;
        pixel8pro) profile_pixel8pro ;;
        *)         log_err "Unknown profile: $1"; return 1 ;;
    esac
}

# ============================================================
# NEW v4.13: write_spoof_prop — SELALU dipanggil (PIF-aware).
# Tulis 21 key lengkap yang di-consume main.cpp.
# ============================================================
write_spoof_prop() {
    [ -z "$P_MODEL" ] && { log_warn "write_spoof_prop: profil belum di-load"; return 1; }
    _BL="${P_BOOTLOADER:-unknown}"
    _HOST="${P_HOST:-abfarm-release}"
    _USER="${P_USER:-android-build}"
    _CODENAME="${P_CODENAME:-REL}"
    _INITSDK="${P_INITIAL_SDK:-$P_SDK}"
    _TIME_MS="$(date +%s)000"

    rm -f "$MODDIR/spoof.prop"
    cat > "$MODDIR/spoof.prop" <<EOF
# Auto-generated ternak v${VERSION} — ${PROFILE_NAME} | $(date '+%Y-%m-%d %H:%M:%S')
BRAND=$P_BRAND
MANUFACTURER=$P_MANUFACTURER
MODEL=$P_MODEL
DEVICE=$P_DEVICE
PRODUCT=$P_PRODUCT
BOARD=$P_BOARD
HARDWARE=$P_HARDWARE
FINGERPRINT=$P_FINGERPRINT
ID=$P_BUILD_ID
BOOTLOADER=$_BL
HOST=$_HOST
USER=$_USER
TYPE=$P_TYPE
TAGS=$P_TAGS
TIME=$_TIME_MS
INCREMENTAL=$P_INCREMENTAL
RELEASE=$P_RELEASE
SDK_INT=$P_SDK
DEVICE_INITIAL_SDK_INT=$_INITSDK
SECURITY_PATCH=$P_SECURITY_PATCH
CODENAME=$_CODENAME
EOF
    chmod 644 "$MODDIR/spoof.prop"
    log_ok "spoof.prop written (${PROFILE_NAME}, 21 keys)"
}

apply_profile() {
    pname="$1"
    [ -z "$pname" ] && pname=$(pick_random_profile)
    load_profile "$pname" || return 1
    log_step "Apply device profile: $PROFILE_NAME ($pname)"

    if echo "$P_BRAND" | grep -qi samsung; then serial=$(generate_serial_samsung); else serial=$(generate_serial_generic); fi

    rp_bulk <<EOF
ro.product.brand $P_BRAND
ro.product.manufacturer $P_MANUFACTURER
ro.product.model $P_MODEL
ro.product.name $P_PRODUCT
ro.product.device $P_DEVICE
ro.product.board $P_BOARD
ro.product.system.brand $P_BRAND
ro.product.system.manufacturer $P_MANUFACTURER
ro.product.system.model $P_MODEL
ro.product.system.name $P_PRODUCT
ro.product.system.device $P_DEVICE
ro.board.platform $P_PLATFORM
ro.hardware $P_HARDWARE
ro.build.product $P_PRODUCT
ro.build.id $P_BUILD_ID
ro.build.version.incremental $P_INCREMENTAL
ro.build.version.release $P_RELEASE
ro.build.version.security_patch $P_SECURITY_PATCH
ro.build.fingerprint $P_FINGERPRINT
ro.build.description $P_DESCRIPTION
ro.build.tags $P_TAGS
ro.build.type $P_TYPE
ro.bootimage.build.fingerprint $P_FINGERPRINT
ro.system.build.fingerprint $P_FINGERPRINT
ro.product.build.fingerprint $P_FINGERPRINT
EOF
    rp ro.serialno "$serial"

    cat > "$SYSPROP_FILE" <<EOF
# Auto-generated ternak v${VERSION} — $PROFILE_NAME ($pname) | $(date '+%Y-%m-%d %H:%M:%S')
ro.product.brand=$P_BRAND
ro.product.manufacturer=$P_MANUFACTURER
ro.product.model=$P_MODEL
ro.product.name=$P_PRODUCT
ro.product.device=$P_DEVICE
ro.product.board=$P_BOARD
ro.product.system.brand=$P_BRAND
ro.product.system.manufacturer=$P_MANUFACTURER
ro.product.system.model=$P_MODEL
ro.product.system.name=$P_PRODUCT
ro.product.system.device=$P_DEVICE
ro.board.platform=$P_PLATFORM
ro.hardware=$P_HARDWARE
ro.build.product=$P_PRODUCT
ro.build.id=$P_BUILD_ID
ro.build.version.incremental=$P_INCREMENTAL
ro.build.version.release=$P_RELEASE
ro.build.version.security_patch=$P_SECURITY_PATCH
ro.build.fingerprint=$P_FINGERPRINT
ro.build.description=$P_DESCRIPTION
ro.build.tags=$P_TAGS
ro.build.type=$P_TYPE
ro.bootimage.build.fingerprint=$P_FINGERPRINT
ro.system.build.fingerprint=$P_FINGERPRINT
ro.product.build.fingerprint=$P_FINGERPRINT
EOF
    chmod 644 "$SYSPROP_FILE"

    echo "$pname|$PROFILE_NAME|$P_FINGERPRINT|$serial|$(date +%s)" > "$PROFILE_FILE"
    chmod 644 "$PROFILE_FILE"
    REBOOT_NEEDED=1
    log_ok "Profile applied: $PROFILE_NAME"
    log_info "Fingerprint: $P_FINGERPRINT"
    log_info "Serial: $serial"

    # NEW v4.13: write spoof.prop (21 keys)
    write_spoof_prop
}

# === Identifier setters ===
set_android_id_global() { newid="$1"; [ -z "$newid" ] && newid=$(generate_hex 16); settings_put secure android_id "$newid"; log_ok "Global ANDROID_ID: $newid"; }

wipe_ssaid() {
    log_step "Wipe SSAID (backup + surgical)..."
    se_permissive
    changed=0
    for u in $(get_users); do
        f="/data/system/users/$u/settings_ssaid.xml"
        [ -f "$f" ] || continue
        cp -f "$f" "$BACKUP_DIR_ROOT/settings_ssaid.$u.$(date +%s).bak" 2>/dev/null
        rm -f "$f" "$f.bak" "$f.tmp" 2>/dev/null
        changed=1
    done
    se_restore
    if [ "$changed" = "1" ]; then
        REBOOT_NEEDED=1
        log_ok "SSAID dihapus (backup di $BACKUP_DIR_ROOT)."
        log_warn "WAJIB reboot: system_server regen SSAID bersih saat boot."
    else
        log_info "Tidak ada settings_ssaid.xml."
    fi
}

set_gaid_value() {
    newgaid="$1"; [ -z "$newgaid" ] && newgaid=$(generate_uuid)
    log_step "Set GAID: $newgaid"
    settings_put global advertising_id "$newgaid"
    settings_put global limit_ad_tracking 0
    force_stop com.google.android.gms; am kill com.google.android.gms 2>/dev/null; sleep 1
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
    gms_uid=$(stat -c '%u' /data/data/com.google.android.gms 2>/dev/null)
    [ -n "$gms_uid" ] && chown $gms_uid:$gms_uid /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    chmod 660 /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null
    se_restore
    log_ok "GAID set: $newgaid"
}

randomize_wlan_mac() {
    newmac="$1"; [ -z "$newmac" ] && newmac=$(generate_mac)
    log_step "Randomize wlan0 MAC: $newmac"
    se_permissive
    ip link set wlan0 down 2>/dev/null; sleep 1
    ip link set dev wlan0 address "$newmac" 2>/dev/null && log_ok "MAC: $newmac" || log_warn "MAC ditolak driver"
    ip link set wlan0 up 2>/dev/null
    WCS=/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml
    if [ -f "$WCS" ]; then
        cp -f "$WCS" "$BACKUP_DIR_ROOT/WifiConfigStore.$(date +%s).xml" 2>/dev/null
        log_info "Backup WifiConfigStore -> $BACKUP_DIR_ROOT"
        rm -f "$WCS" "$WCS.encrypted-checkpoint" 2>/dev/null
    fi
    se_restore
}

randomize_device_name() {
    log_step "Randomize device/BT name..."
    BRANDS="Galaxy Pixel Redmi Mi Poco Realme OnePlus Nothing Honor Oppo Vivo Asus"
    MODELS="S24 S25 Note13 9Pro 14Ultra F6 12R 11R X100 FindX7 Magic6 Zero2 ROG8 K70 Edge"
    nb=$(echo $BRANDS | wc -w); nm=$(echo $MODELS | wc -w)
    r1=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % nb + 1 ))
    r2=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % nm + 1 ))
    nonce=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 900 + 100 ))
    b=$(echo $BRANDS | cut -d' ' -f$r1); m=$(echo $MODELS | cut -d' ' -f$r2)
    NEW_NAME="$b $m-$nonce"
    log_info "New BT name: $NEW_NAME"
    settings_put global bluetooth_name "$NEW_NAME"
    settings_put global device_name "$NEW_NAME"
    settings_put system device_name "$NEW_NAME"
    rp_set persist.bluetooth.adaptername "$NEW_NAME"
    se_permissive
    updated=0
    for btcfg in /data/misc/bluedroid/bt_config.conf /data/misc/bluetooth/bt_config.conf /data/vendor/bluetooth/bt_config.conf; do
        [ -f "$btcfg" ] || continue
        if grep -q '^Name = ' "$btcfg" 2>/dev/null; then
            owner=$(stat -c '%U:%G' "$btcfg" 2>/dev/null); mode=$(stat -c '%a' "$btcfg" 2>/dev/null)
            awk -v n="$NEW_NAME" '/^Name = / { print "Name = " n; next } { print }' "$btcfg" > "${btcfg}.tmp" 2>/dev/null
            if [ -s "${btcfg}.tmp" ]; then
                mv "${btcfg}.tmp" "$btcfg" 2>/dev/null && {
                    [ -n "$owner" ] && chown "$owner" "$btcfg" 2>/dev/null
                    [ -n "$mode" ]  && chmod "$mode"  "$btcfg" 2>/dev/null
                    log_ok "Rewrote: $btcfg"; updated=1
                }
            fi
            rm -f "${btcfg}.tmp" 2>/dev/null
        fi
    done
    [ $updated -eq 0 ] && log_warn "bt_config.conf belum ada / not writable"
    se_restore
    force_stop com.android.bluetooth
    pkill -f 'com\.(android|google\.android)\.bluetooth' 2>/dev/null
    sleep 1
    log_ok "Name: $NEW_NAME"
}

randomize_hostname() {
    nonce=$(( $(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 9000 + 1000 ))
    hn="android-$nonce"
    rp_set net.hostname "$hn"
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
    { [ -d /data/adb/modules/zygisksu ] || [ -d /data/adb/modules/zygisknext ]; } && HAS_ZYGISK_NEXT=1
    SDK=$(getprop ro.build.version.sdk 2>/dev/null)
    log_info "SDK=$SDK PIF=$HAS_PIF Specter=$HAS_SPECTER ZygiskNext=$HAS_ZYGISK_NEXT RP=$([ -n "$RP" ] && echo yes || echo no)"
}
check_root() { [ "$(id -u)" -eq 0 ] || { log_err "Need root"; exit 1; }; }
preflight() {
    check_root
    detect_resetprop || { log_err "resetprop-rs WAJIB. Bundle bin/resetprop-rs di module. Abort."; exit 1; }
    detect_root_manager
    detect_modules
    [ $HAS_PIF -eq 1 ] && log_warn "PIF aktif — apply_profile native SKIP tapi spoof.prop TETAP ditulis utk Zygisk"
    [ $HAS_SPECTER -eq 0 ] && log_warn "Specter tidak terinstall — root bisa terdeteksi"
}

# === Backup ===
backup_state() {
    bdir="$BACKUP_DIR_ROOT/$(date +%Y%m%d_%H%M%S)"
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
freeze_targets() { log_step "Force-stop targets + GMS/GSF..."; for pkg in $FID_TARGETS; do force_stop "$pkg"; done; sleep 2; log_ok "Frozen"; }
deep_clear() {
    pkg="$1"
    log_step "Deep-clear: $pkg"
    pkg_uid=$(pm list packages -U 2>/dev/null | grep "^package:$pkg " | sed 's/.*uid://' | head -n1)
    [ -z "$pkg_uid" ] && pkg_uid=$(stat -c '%u' "/data/data/$pkg" 2>/dev/null)
    force_stop "$pkg"; pkill -9 -f "$pkg" 2>/dev/null; sleep 1
    for u in $(get_users); do
        r=$(pm clear --user "$u" "$pkg" 2>&1)
        [ "$r" = "Success" ] && log_ok "pm clear: $pkg (user $u)" || log_warn "pm clear FAIL: $pkg -> $r"
    done
    se_permissive
    for u in $(get_users); do
        rm -rf "/data/user/$u/$pkg"                2>/dev/null
        rm -rf "/data/user_de/$u/$pkg"             2>/dev/null
        rm -rf "/data/media/$u/Android/data/$pkg"  2>/dev/null
        rm -rf "/data/media/$u/Android/media/$pkg" 2>/dev/null
        rm -rf "/data/media/$u/Android/obb/$pkg"   2>/dev/null
    done
    bmgr wipe   "$pkg" >/dev/null 2>&1
    bmgr backup "$pkg" >/dev/null 2>&1
    for u in $(get_users); do
        db="/data/system_ce/$u/accounts_ce.db"
        [ -f "$db" ] || continue
        sqlite3 "$db" "DELETE FROM authtokens WHERE type LIKE '%$pkg%';" 2>/dev/null
        [ -n "$pkg_uid" ] && sqlite3 "$db" "DELETE FROM grants WHERE uid = $pkg_uid;" 2>/dev/null
    done
    rm -f /data/data/com.google.android.gms/shared_prefs/oauth_*"$pkg"*.xml       2>/dev/null
    rm -f /data/data/com.google.android.gms/shared_prefs/googlesignin*"$pkg"*.xml 2>/dev/null
    rm -f /data/data/com.google.android.gms/shared_prefs/AppAuth*"$pkg"*.xml      2>/dev/null
    se_restore
    verify_clear "$pkg" quiet
    log_ok "deep-clear done: $pkg"
}
verify_clear() {
    pkg="$1"; mode="$2"
    residue=0
    for u in $(get_users); do
        d="/data/user/$u/$pkg"
        [ -d "$d" ] || continue
        if [ -d "$d/shared_prefs" ] && [ -n "$(ls -A "$d/shared_prefs" 2>/dev/null)" ]; then
            residue=1
            log_warn "RESIDUE $pkg (user $u): $d/shared_prefs masih berisi:"
            ls -1 "$d/shared_prefs/" 2>/dev/null | head -5 | while read x; do log_warn "    -> $x"; done
        fi
        if [ -d "$d/databases" ] && [ -n "$(ls -A "$d/databases" 2>/dev/null)" ]; then
            residue=1
            log_warn "RESIDUE $pkg (user $u): $d/databases masih ada file"
        fi
    done
    if [ "$residue" = "0" ]; then
        [ "$mode" != "quiet" ] && log_ok "verify_clear $pkg: BERSIH"
        return 0
    fi
    return 1
}
clear_target_apps() {
    log_step "Deep-clear targets..."
    for pkg in $TARGET_APPS; do
        if pm list packages 2>/dev/null | grep -q "package:$pkg"; then
            deep_clear "$pkg"
        else
            log_warn "$pkg not installed"
        fi
    done
    force_stop com.google.android.gms
    force_stop com.google.android.gsf
    am kill    com.google.android.gms 2>/dev/null
    am kill    com.google.android.gsf 2>/dev/null
    sleep 2
    log_ok "GMS restarted post-clear"
}
clear_sdcard_residue() { log_step "Wipe SDcard residue..."; se_permissive; for pkg in $TARGET_APPS; do rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null; done; se_restore; log_ok "SDcard cleared"; }
wipe_firebase_iid() {
    log_step "Wipe Firebase IID..."; se_permissive
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
reset_gsf_id() { log_step "Reset GSF ID..."; force_stop com.google.android.gsf; se_permissive; rm -f /data/data/com.google.android.gsf/databases/gservices.db* 2>/dev/null; rm -f /data/data/com.google.android.gsf/databases/Checkin.db* 2>/dev/null; se_restore; log_ok "GSF ID regenerated next boot"; }
wipe_mediadrm() {
    log_step "Wipe MediaDrm L3..."; se_permissive
    rm -rf /data/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/IDM1013/L3/ /data/vendor/mediadrm/ 2>/dev/null
    for u in $(get_users); do rm -rf "/data/system/users/$u/drm/" 2>/dev/null; done
    rm -rf /data/misc/mediadrm/ 2>/dev/null; se_restore
    pkill -f mediadrmserver 2>/dev/null; pkill -f android.hardware.drm 2>/dev/null
    log_ok "MediaDrm L3 wiped"
}
clear_network_caches() {
    log_step "Wipe network caches..."; se_permissive
    rm -rf /data/misc/net/* /data/misc/connectivity/* 2>/dev/null
    rm -f /data/misc/dhcp/*.lease /data/misc/dhcp-6.8/*.lease 2>/dev/null
    rm -rf /data/misc/netstats/* /data/system/netstats/* 2>/dev/null
    se_restore
    for _nid in $(cmd connectivity networks 2>/dev/null | awk '/netId/{print $2}' | tr -d ','); do
        ndc resolver flushnet "$_nid" >/dev/null 2>&1
    done
    ndc resolver flushnet 0 >/dev/null 2>&1 || true
    log_ok "Network caches cleared"
}
wipe_forensic_traces() {
    log_step "Wipe forensic traces..."; logcat -c 2>/dev/null; logcat -b all -c 2>/dev/null; se_permissive
    rm -rf /data/anr/* /data/tombstones/* /data/system/dropbox/* 2>/dev/null
    for u in $(get_users); do rm -rf "/data/system/usagestats/$u/"* 2>/dev/null; rm -rf "/data/system/users/$u/recent_tasks/"* "/data/system/users/$u/recent_images/"* 2>/dev/null; done
    rm -rf /data/system/procstats/* /data/system/heapdump/* 2>/dev/null; se_restore; log_ok "Forensics cleared"
}
wipe_clipboard() { cmd clipboard set-text "" 2>/dev/null; log_ok "Clipboard cleared"; }

save_persona_snapshot() {
    pkg="$1"; f="$PERSONA_DIR/${pkg}.json"
    aid=$(settings_get secure android_id); [ -z "$aid" ] && aid=$(generate_hex 16)
    gaid_val=$(settings_get global advertising_id); [ -z "$gaid_val" ] && gaid_val=$(generate_uuid)
    pname="unknown"
    if [ -f "$PROFILE_FILE" ]; then
        pname=$(cut -d'|' -f2 "$PROFILE_FILE")
    else
        for _pif in /data/adb/modules/playintegrityfix/pif.prop /data/adb/pif.prop /data/adb/modules/playintegrityfix/custom.pif.prop; do
            [ -f "$_pif" ] || continue
            _m=$(grep -E '^MODEL=' "$_pif" | head -n1 | cut -d= -f2- | tr -d '"\r\n')
            _b=$(grep -E '^MANUFACTURER=' "$_pif" | head -n1 | cut -d= -f2- | tr -d '"\r\n')
            [ -n "$_m" ] && { pname="${_b:+$_b }$_m (pif)"; break; }
        done
        [ "$pname" = "unknown" ] && [ "$HAS_PIF" = "1" ] && pname="pif-managed"
    fi
    now=$(date +%s)000; age=$(( ($(od -An -N2 -tu2 /dev/urandom 2>/dev/null) % 30) + 1 ))
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
    chmod 644 "$f"; log_ok "Snapshot: $pkg -> $pname"
}
burn_persona() {
    pkg="$1"; log_step "Burn: $pkg"
    rm -f "$PERSONA_DIR/${pkg}.json"; force_stop "$pkg"
    for u in $(get_users); do pm clear --user "$u" "$pkg" >/dev/null 2>&1 && log_ok "App data cleared (user $u)"; done
    se_permissive
    rm -rf "/sdcard/Android/data/$pkg" "/sdcard/Android/media/$pkg" "/sdcard/Android/obb/$pkg" 2>/dev/null
    rm -f /data/data/$pkg/shared_prefs/PersistedInstallation.*.json 2>/dev/null
    rm -f /data/data/$pkg/files/PersistedInstallation.* 2>/dev/null
    se_restore
    set_gaid_value; wipe_ssaid; save_persona_snapshot "$pkg"
    log_ok "$pkg ready for new account"
}

do_fresh() {
    preflight
    log_info "=== TERNAK FRESH IDENTITY v$VERSION ==="
    backup_state

    # v4.13: SELALU tulis spoof.prop utk Zygisk, apapun kondisi PIF.
    if [ "$HAS_PIF" -eq 0 ]; then
        apply_profile "$1"
    else
        log_warn "PIF active — SKIP native prop writing, tapi TETAP tulis spoof.prop utk Zygisk"
        pname="${1:-$(pick_random_profile)}"
        load_profile "$pname" >/dev/null 2>&1
        if echo "$P_BRAND" | grep -qi samsung; then serial=$(generate_serial_samsung); else serial=$(generate_serial_generic); fi
        rp ro.serialno "$serial"
        write_spoof_prop
        echo "$pname|$PROFILE_NAME|$P_FINGERPRINT|$serial|$(date +%s)" > "$PROFILE_FILE"
        chmod 644 "$PROFILE_FILE"
        REBOOT_NEEDED=1
        log_ok "Profile registered (PIF mode): $PROFILE_NAME"
        log_info "Fingerprint: $P_FINGERPRINT"
        log_info "Serial: $serial"
    fi

    new_gaid=$(generate_uuid); new_aid=$(generate_hex 16)
    freeze_targets
    clear_target_apps
    clear_sdcard_residue
    wipe_firebase_iid
    wipe_mediadrm
    reset_gsf_id
    wipe_ssaid; set_android_id_global "$new_aid"
    set_gaid_value "$new_gaid"
    randomize_device_name
    randomize_hostname
    randomize_wlan_mac
    clear_network_caches
    rm -f "$PERSONA_DIR"/*.json 2>/dev/null; for pkg in $TARGET_APPS; do save_persona_snapshot "$pkg"; done
    wipe_clipboard
    wipe_forensic_traces
    if [ "$HAS_PIF" = "1" ]; then
        log_info "PIF active — skip seal_all (native prop handled by PIF)"
    else
        seal_all
    fi
    [ -n "$RP" ] && "$RP" --compact 2>/dev/null && log_ok "Property arenas compacted"

    echo ""; verify_changes; echo ""
    log_ok "FRESH IDENTITY READY"
    [ "$REBOOT_NEEDED" = "1" ] && log_warn "WAJIB REBOOT: SSAID/Build.* baru propagate penuh setelah reboot."
}

get_info() {
    android_id=$(settings_get secure android_id); bt_name=$(settings_get global bluetooth_name)
    hostname=$(getprop net.hostname | tr -d '"\r\n\t'); gaid=$(settings_get global advertising_id)
    model=$(getprop ro.product.model | tr -d '"\r\n\t'); brand=$(getprop ro.product.brand | tr -d '"\r\n\t')
    serial=$(getprop ro.serialno | tr -d '"\r\n\t'); fingerprint=$(getprop ro.build.fingerprint | tr -d '"\r\n\t')
    sdk=$(getprop ro.build.version.sdk | tr -d '"\r\n\t'); profile_name="-"
    [ -f "$PROFILE_FILE" ] && profile_name=$(cut -d'|' -f2 "$PROFILE_FILE")
    [ -z "$android_id" ] || [ "$android_id" = "null" ] && android_id="-"
    [ -z "$gaid" ] || [ "$gaid" = "null" ] && gaid="-"
    [ -z "$bt_name" ] || [ "$bt_name" = "null" ] && bt_name="-"
    persona_count=$(ls "$PERSONA_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
    pif=$([ $HAS_PIF -eq 1 ] && echo true || echo false)
    specter=$([ $HAS_SPECTER -eq 1 ] && echo true || echo false)
    zygnext=$([ $HAS_ZYGISK_NEXT -eq 1 ] && echo true || echo false)
    rp_ok=$([ -n "$RP" ] && echo true || echo false)
    stealth=$([ "$RP_STEALTH_OK" = "1" ] && echo true || echo false)
    printf '{"android_id":"%s","bt_name":"%s","hostname":"%s","gaid":"%s","model":"%s","brand":"%s","serial":"%s","fingerprint":"%s","sdk":"%s","profile":"%s","root_manager":"%s","persona_count":%s,"modules":{"pif":%s,"specter":%s,"zygisk_next":%s,"resetprop_rs":%s,"stealth":%s}}' \
        "$android_id" "$bt_name" "$hostname" "$gaid" "$model" "$brand" "$serial" "$fingerprint" "$sdk" "$profile_name" "$ROOT_MGR" "$persona_count" "$pif" "$specter" "$zygnext" "$rp_ok" "$stealth"
}
list_personas() { printf '['; first=1; for f in "$PERSONA_DIR"/*.json; do [ -f "$f" ] || continue; [ $first -eq 0 ] && printf ','; cat "$f" | tr -d '\n'; first=0; done; printf ']'; }
list_profiles() { printf '['; first=1; for p in $PROFILES_LIST; do load_profile "$p" >/dev/null 2>&1; [ $first -eq 0 ] && printf ','; printf '{"id":"%s","name":"%s","model":"%s","brand":"%s"}' "$p" "$PROFILE_NAME" "$P_MODEL" "$P_BRAND"; first=0; done; printf ']'; }
verify_changes() {
    echo "================ STATE VERIFY ================"
    [ -f "$PROFILE_FILE" ] && echo "Profile     : $(cut -d'|' -f2 $PROFILE_FILE)"
    echo "SDK         : $(getprop ro.build.version.sdk)"
    echo "Brand/Model : $(getprop ro.product.brand) / $(getprop ro.product.model)"
    echo "Fingerprint : $(getprop ro.build.fingerprint)"
    echo "Serial      : $(getprop ro.serialno)"
    echo "Android ID  : $(settings_get secure android_id)"
    echo "GAID        : $(settings_get global advertising_id)"
    echo "BT Name     : $(settings_get global bluetooth_name)"
    echo "Hostname    : $(getprop net.hostname)"
    echo "spoof.prop  : $([ -f "$MODDIR/spoof.prop" ] && wc -l < "$MODDIR/spoof.prop" | tr -d ' ' || echo 0) keys"
    echo "resetprop-rs: ${RP:-none} (stealth=$RP_STEALTH_OK)"
    echo "============================================="
}

case "$1" in
    info)        detect_resetprop >/dev/null 2>&1; detect_root_manager >/dev/null 2>&1; detect_modules >/dev/null 2>&1; get_info ;;
    fresh|full)  do_fresh "$2" ;;
    profile)     preflight; apply_profile "$2" ;;
    profiles)    list_profiles ;;
    pick)        pick_random_profile ;;
    burn)        preflight; [ -z "$2" ] && { log_err "Usage: $0 burn <pkg>"; exit 1; }; burn_persona "$2" ;;
    burn_all)    preflight; for pkg in $TARGET_APPS; do burn_persona "$pkg"; done ;;
    aid)         preflight; wipe_ssaid; set_android_id_global "$2" ;;
    gaid)        preflight; set_gaid_value "$2" ;;
    mac)         preflight; randomize_wlan_mac "$2" ;;
    personas)    list_personas ;;
    deep_wipe)   preflight; freeze_targets; wipe_mediadrm; reset_gsf_id; wipe_firebase_iid; clear_network_caches; wipe_forensic_traces ;;
    backup)      check_root; backup_state ;;
    verify)      detect_resetprop >/dev/null 2>&1; detect_modules >/dev/null 2>&1; verify_changes ;;
    deep_clear)  preflight; [ -z "$2" ] && { log_err "Usage: $0 deep_clear <pkg>"; exit 1; }; deep_clear "$2" ;;
    verify_clear) [ -z "$2" ] && { log_err "Usage: $0 verify_clear <pkg>"; exit 1; }; verify_clear "$2" ;;
    seal_all)    preflight; seal_all ;;
    seals)       detect_resetprop >/dev/null 2>&1; [ -n "$RP" ] && "$RP" --seals || log_err "resetprop-rs tidak ada" ;;
    unseal)      preflight; [ -z "$2" ] && { log_err "Usage: $0 unseal <prop>"; exit 1; }; "$RP" --unseal "$2" 2>/dev/null || "$RP" --unseal-arena "$2" 2>/dev/null; log_ok "Unsealed: $2" ;;
    compact)     detect_resetprop >/dev/null 2>&1; [ -n "$RP" ] && "$RP" --compact && log_ok "Compacted" || log_err "resetprop-rs tidak ada" ;;
    diag)        [ -f "$MODDIR/bootloop_diag.sh" ] && sh "$MODDIR/bootloop_diag.sh" || log_err "bootloop_diag.sh tidak ditemukan" ;;
    write_spoof) preflight; pname="${2:-$(pick_random_profile)}"; load_profile "$pname" >/dev/null 2>&1 && write_spoof_prop || log_err "Gagal load profil $pname" ;;
    unfresh)
        check_root
        rm -f "$SYSPROP_FILE" 2>/dev/null && log_ok "system.prop removed"
        rm -f "$PROFILE_FILE" 2>/dev/null && log_ok "profile cleared"
        rm -f "$PERSONA_DIR"/*.json 2>/dev/null && log_ok "personas wiped"
        rm -f "$MODDIR/spoof.prop" 2>/dev/null && log_ok "spoof.prop removed"
        log_warn "Reboot untuk balik ke build asli." ;;
    reboot)      sync && reboot ;;
    *)
        cat <<EOF
Ternak Device Changer v$VERSION (Android 15) — resetprop-rs WAJIB
Usage: $0 <command> [args]

Main:
  fresh [profile]   FRESH identity: profile + AID + GAID + MAC + clear
  profile <name>    pixel9pro|s24ultra|xiaomi14|oneplus12|pixel8pro
  write_spoof [pf]  hanya tulis spoof.prop utk Zygisk (tanpa apply native)
  profiles | pick | unfresh | diag
Targeted:
  burn <pkg> | burn_all | aid [hex16] | gaid [uuid] | mac [aa:..:ff]
  deep_clear <pkg> | verify_clear <pkg>
Stealth (resetprop-rs --seal):
  seal_all | seals | unseal <prop> | compact
Maintenance:
  info | personas | deep_wipe | backup | verify | reboot
EOF
        ;;
esac
