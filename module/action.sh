#!/bin/sh
# ============================================================
# action.sh — Ternak Device Changer
# All-in-one: fetch Pixel Canary dari Google OTA → spoof.prop.
# Adapted from: PlayIntegrityFix / action/pixel_canary.sh
#
# Cukup tap Action di KSU/APatch/Magisk manager — tanpa input.
# ============================================================

PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR="${0%/*}"
[ -z "$MODDIR" ] || [ "$MODDIR" = "." ] && MODDIR=/data/adb/modules/ternak_device_changer
SPOOF="$MODDIR/spoof.prop"
BACKUP="$MODDIR/spoof.prop.bak"
VERSION="1.3-ota-fixed"    # v1.3: fix DevInfo "Nama perangkat", "Membangun nomor", "Pita dasar"

# ---------- inline helpers (menggantikan common_func.sh PIF) ----------
download() {
    url="$1"; output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 -sfL -A 'Mozilla/5.0' "$url" -o "$output" || download_fail "$url"
    else
        busybox wget -T 10 --header 'User-Agent: Mozilla/5.0' -qO "$output" "$url" || download_fail "$url"
    fi
}
download_fail() {
    echo "! Failed to download: $1"
    rm -rf "$TEMPDIR"
    exit 1
}

# ---------- tmpfs preference ----------
TEMPDIR="$MODDIR/temp"
[ -w /sbin ]           && TEMPDIR="/sbin/ternak_fetch"
[ -w /debug_ramdisk ]  && TEMPDIR="/debug_ramdisk/ternak_fetch"
[ -w /dev ]            && TEMPDIR="/dev/ternak_fetch"
mkdir -p "$TEMPDIR"
cd "$TEMPDIR" || exit 1

echo "[+] Ternak Device Changer — Fetch Pixel Canary $VERSION"
echo "[+] $(date '+%Y-%m-%d %H:%M:%S')"
printf '\n'

set_random_beta() {
    if [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$(echo "$PRODUCT_LIST" | wc -l)" ]; then
        echo "! MODEL/PRODUCT list mismatch — fallback ke Pixel 6"
        MODEL="Pixel 6"
        PRODUCT="oriole_beta"
    else
        count=$(echo "$MODEL_LIST" | wc -l)
        rand_index=$(( $$ % count ))
        MODEL=$(echo "$MODEL_LIST"   | sed -n "$((rand_index + 1))p")
        PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
    fi
}

# ============================================================
# 1. Cari halaman Android Canary terbaru
# ============================================================
echo "- Fetching Android versions index ..."
download https://developer.android.com/about/versions PIXEL_VERSIONS_HTML
LATEST_URL=$(grep -o 'https://developer.android.com/about/versions/.*[0-9]"' PIXEL_VERSIONS_HTML \
             | sort -ru | cut -d\" -f1 | head -n1)
download "$LATEST_URL" PIXEL_LATEST_HTML

FI_URL="https://developer.android.com$(grep -o 'href=".*download.*"' PIXEL_LATEST_HTML \
         | grep 'qpr' | cut -d\" -f2 | head -n1)"
download "$FI_URL" PIXEL_FI_HTML

OTA_URL="https://developer.android.com$(grep -o 'href=".*download-ota.*"' PIXEL_LATEST_HTML \
          | grep 'qpr' | cut -d\" -f2 | head -n1)"
download "$OTA_URL" PIXEL_OTA_HTML

SRC=FI
FI_COUNT=$(grep 'tr id=' PIXEL_FI_HTML  | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)
OTA_COUNT=$(grep 'tr id=' PIXEL_OTA_HTML | sed 's;.*<tr id="\(.*\)">.*;\1;' | wc -w)
[ "$FI_COUNT" -lt "$OTA_COUNT" ] && SRC=OTA

MODEL_LIST="$(grep -A1 'tr id=' PIXEL_${SRC}_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>.*;\1;')"
PRODUCT_LIST="$(grep 'tr id=' PIXEL_${SRC}_HTML | sed 's;.*<tr id="\(.*\)">.*;\1_beta;')"

# ============================================================
# 2. Random pick device Pixel Canary
# ============================================================
echo "- Selecting random Pixel Canary device ..."
set_random_beta
echo "  → $MODEL ($PRODUCT)"

# ============================================================
# 3. Ambil ID + INCREMENTAL dari Flash Station API
# ============================================================
DEVICE="$(echo "$PRODUCT" | sed 's/_beta//')"
echo "- Fetching Flash Station API key ..."
download https://flash.android.com PIXEL_FLASH_HTML
FLASH_KEY=$(grep -o '<body data-client-config=.*' PIXEL_FLASH_HTML | cut -d\; -f2 | cut -d\& -f1)

echo "- Querying build info untuk $PRODUCT ..."
if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout 10 -H "Referer: https://flash.android.com" -s \
        "https://content-flashstation-pa.googleapis.com/v1/builds?product=$PRODUCT&key=$FLASH_KEY" \
        > PIXEL_STATION_JSON || download_fail "flash.android.com"
else
    busybox wget -T 10 --header "Referer: https://flash.android.com" -qO - \
        "https://content-flashstation-pa.googleapis.com/v1/builds?product=$PRODUCT&key=$FLASH_KEY" \
        > PIXEL_STATION_JSON || download_fail "flash.android.com"
fi

busybox tac PIXEL_STATION_JSON | busybox grep -m1 -A13 '"canary": true' > PIXEL_CANARY_JSON

ID="$(grep 'releaseCandidateName' PIXEL_CANARY_JSON | cut -d\" -f4)"
INCREMENTAL="$(grep 'buildId' PIXEL_CANARY_JSON | cut -d\" -f4)"
FINGERPRINT="google/$PRODUCT/$DEVICE:CANARY/$ID/$INCREMENTAL:user/release-keys"

# ============================================================
# 4. SECURITY_PATCH dari Android Security Bulletin
# ============================================================
echo "- Fetching security bulletin ..."
download https://source.android.com/docs/security/bulletin/pixel PIXEL_SECBULL_HTML
CANARY_ID="$(grep '"id"' PIXEL_CANARY_JSON | sed -e 's;.*canary-\(.*\)".*;\1;' -e 's;^\(.\{4\}\);\1-;')"
SECURITY_PATCH="$(grep "<td>$CANARY_ID" PIXEL_SECBULL_HTML | sed 's;.*<td>\(.*\)</td>;\1;')"

if [ -z "$ID" ] || [ -z "$INCREMENTAL" ]; then
    echo "! Failed to fetch Canary build info dari Google (ID/INCREMENTAL kosong)"
    rm -rf "$TEMPDIR"
    exit 1
fi
if [ -z "$SECURITY_PATCH" ]; then
    echo "- Bulletin belum publish. Assuming security patch from Canary ID"
    SECURITY_PATCH="${CANARY_ID}-05"
fi

# ============================================================
# 5. Compose 21 field spoof.prop
# ============================================================
BRAND=google
MANUFACTURER=Google
BOARD="$DEVICE"
HARDWARE="$DEVICE"
TYPE=user
TAGS=release-keys
BOOTLOADER=unknown
HOST=abfarm-release
BUSER=android-build
CODENAME=REL

API_VER=$(echo "$LATEST_URL" | grep -oE '[0-9]+' | tail -n1)
case "$API_VER" in
    17) SDK=37 ;;
    16) SDK=36 ;;
    15) SDK=35 ;;
    14) SDK=34 ;;
    13) SDK=33 ;;
    12) SDK=32 ;;
    *)  SDK=35 ;;
esac
INITSDK="$SDK"
RELEASE="$API_VER"
TIME_MS="$(date +%s)000"

# v1.3: tambahan field untuk fix DevInfo "Membangun nomor" & "Pita dasar"
DISPLAY="$ID"
DESCRIPTION="$PRODUCT-$TYPE $RELEASE $ID $INCREMENTAL $TAGS"
BASEBAND="g5300q-$(date +%y%m%d)-$(date +%y%m%d)-B-$INCREMENTAL"

# ============================================================
# 6. Backup + tulis spoof.prop (23 field: +DISPLAY +DESCRIPTION)
# ============================================================
if [ -f "$SPOOF" ]; then
    cp "$SPOOF" "$BACKUP"
    echo "- Backup lama → $BACKUP"
fi

echo "- Writing spoof.prop ..."
echo ""
cat <<EOF | tee "$SPOOF"
BRAND=$BRAND
MANUFACTURER=$MANUFACTURER
MODEL=$MODEL
DEVICE=$DEVICE
PRODUCT=$PRODUCT
BOARD=$BOARD
HARDWARE=$HARDWARE
FINGERPRINT=$FINGERPRINT
ID=$ID
DISPLAY=$DISPLAY
DESCRIPTION=$DESCRIPTION
BOOTLOADER=$BOOTLOADER
HOST=$HOST
USER=$BUSER
TYPE=$TYPE
TAGS=$TAGS
TIME=$TIME_MS
INCREMENTAL=$INCREMENTAL
RELEASE=$RELEASE
SDK_INT=$SDK
DEVICE_INITIAL_SDK_INT=$INITSDK
SECURITY_PATCH=$SECURITY_PATCH
CODENAME=$CODENAME
EOF
chmod 644 "$SPOOF"
echo ""
echo "- spoof.prop saved to $SPOOF"

# ============================================================
# 7. Native prop overrides via resetprop-rs
#    Fix: "Membangun nomor" (ro.build.display.id + description)
#    Fix: "Pita dasar"     (gsm.version.baseband + ro.build.expect.baseband)
# ============================================================
RP="$MODDIR/bin/resetprop-rs"
if [ -x "$RP" ]; then
    echo "- Native resetprop: display.id / description / baseband ..."
    "$RP" -n ro.build.display.id      "$DISPLAY"     2>/dev/null
    "$RP" -n ro.build.description     "$DESCRIPTION" 2>/dev/null
    "$RP" -n gsm.version.baseband     "$BASEBAND"    2>/dev/null
    "$RP" -n ro.build.expect.baseband "$BASEBAND"    2>/dev/null
else
    echo "! resetprop-rs tidak ada — skip native override"
fi

# ============================================================
# 8. Update device_name (fix DevInfo "Nama perangkat" = POCO F3)
# ============================================================
echo "- Setting device_name = $MODEL ..."
settings put global device_name "$MODEL" 2>/dev/null
settings put system device_name "$MODEL" 2>/dev/null

# ============================================================
# 9. Cleanup + live reseal + kill gms/vending
# ============================================================
echo "- Cleaning up ..."
rm -rf "$TEMPDIR"

if [ -x "$MODDIR/ternak_core_v4.sh" ]; then
    echo "- Running reseal via ternak_core_v4 ..."
    sh "$MODDIR/ternak_core_v4.sh" reseal 2>/dev/null
fi

for i in $(busybox pidof com.google.android.gms.unstable com.android.vending 2>/dev/null); do
    echo "- Killing pid $i"
    kill -9 "$i" 2>/dev/null
done

echo ""
echo "[✓] Done!"
echo "    MODEL       : $MODEL"
echo "    DISPLAY     : $DISPLAY"
echo "    FINGERPRINT : $FINGERPRINT"
echo "    BASEBAND    : $BASEBAND"
echo "    SEC PATCH   : $SECURITY_PATCH"
sleep 3
