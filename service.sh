#!/system/bin/sh
# Ternak v5.0 — boot-time apply native prop
MODDIR="${0%/*}"

# Wait system fully booted
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 5

# Apply identity.prop tersimpan → native prop
if [ -f "$MODDIR/identity.prop" ] && [ -x "$MODDIR/bin/ternakctl" ]; then
    "$MODDIR/bin/ternakctl" apply-boot >> /cache/ternak-boot.log 2>&1
fi
