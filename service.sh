#!/system/bin/sh
MODDIR="${0%/*}"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 5

if [ -f "$MODDIR/identity.prop" ] && [ -x "$MODDIR/bin/envctl" ]; then
    "$MODDIR/bin/envctl" apply-boot >> /cache/env-boot.log 2>&1
fi
