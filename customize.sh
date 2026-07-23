#!/system/bin/sh
SKIPUNZIP=0

ui_print "- Dynamic Environment Device Changer v5.1"
ui_print "- Pure-Zygisk architecture (production fix)"
ui_print ""

ABI=$(getprop ro.product.cpu.abi)
ui_print "- Device ABI: $ABI"

if [ ! -d /data/adb/modules ]; then
    abort "! /data/adb/modules not found — root not detected"
fi

ZYGISK_OK=0
[ -d /data/adb/modules/zygisksu ] && ZYGISK_OK=1
[ -d /data/adb/modules/ReZygisk ] && ZYGISK_OK=1
[ "${MAGISK_VER_CODE:-0}" -ge 26100 ] && ZYGISK_OK=1

if [ "$ZYGISK_OK" = "0" ]; then
    ui_print "! WARNING: Zygisk tidak terdeteksi. Install ZygiskNext / ReZygisk dulu."
    ui_print "! Module tetap ter-install tapi hook tidak akan aktif."
fi

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/action.sh              0 0 0755
set_perm $MODPATH/service.sh             0 0 0755
set_perm $MODPATH/bin/envctl-arm64       0 0 0755
set_perm $MODPATH/bin/envctl-arm         0 0 0755
set_perm $MODPATH/bin/envctl-x86_64      0 0 0755
set_perm $MODPATH/bin/envctl-x86         0 0 0755

if [ -f "$MODPATH/pool.json" ]; then
    set_perm $MODPATH/pool.json 0 0 0644
fi

if [ -f "$MODPATH/bin/resetprop-rs" ]; then
    set_perm $MODPATH/bin/resetprop-rs 0 0 0755
else
    ui_print "! WARNING: resetprop-rs binary is missing."
    ui_print "! Native props will NOT be emulated automatically."
    ui_print "! See README.md on how to manually drop it into prebuilt/ before build."
fi

for abi_dir in $MODPATH/zygisk/*.so; do
    [ -f "$abi_dir" ] && set_perm "$abi_dir" 0 0 0644
done

case "$ABI" in
    arm64-v8a)   ln -sf envctl-arm64  $MODPATH/bin/envctl ;;
    armeabi-v7a) ln -sf envctl-arm    $MODPATH/bin/envctl ;;
    x86_64)      ln -sf envctl-x86_64 $MODPATH/bin/envctl ;;
    x86)         ln -sf envctl-x86    $MODPATH/bin/envctl ;;
    *)           ui_print "! Unknown ABI: $ABI" ;;
esac

if [ ! -f $MODPATH/identity.mode ]; then
    echo "fresh" > $MODPATH/identity.mode
    set_perm $MODPATH/identity.mode 0 0 0644
fi

if [ ! -f $MODPATH/hook_targets.txt ]; then
    cat > $MODPATH/hook_targets.txt <<'EOF'
# Dynamic Environment hook targets — satu package per baris, # untuk comment.
# File ini di-HOT-RELOAD oleh companion: edit → langsung apply tanpa reboot.
com.google.android.gms.unstable
com.android.vending
com.google.android.gms
# Attestation checkers
com.liuzh.deviceinfo
com.cwsl.mydevice
gr.nikolasspyr.integritycheck
# --- JANGAN masukin Shopee/Tokopedia/banking di sini ---
# Mereka anti-fraud tier-1, mock malah trigger flag.
EOF
    set_perm $MODPATH/hook_targets.txt 0 0 0644
fi

ui_print ""
ui_print "- Install complete."
ui_print "- Reboot untuk aktifkan Zygisk module."
ui_print "- Setelah reboot: tap Action untuk generate identity pertama."
