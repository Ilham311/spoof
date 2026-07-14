#!/system/bin/sh
# Clean uninstall: revert everything, keep state for potential reinstall.

MODDIR=/data/adb/modules/ternak_device_changer
[ -x "${MODDIR}/common/ternak_core.sh" ] && \
    "${MODDIR}/common/ternak_core.sh" unfresh --force 2>/dev/null

# Optionally purge state (comment out to keep for reinstall)
# rm -rf /data/adb/ternak 2>/dev/null

rm -f /system/bin/ternak /data/adb/ksu/bin/ternak /data/adb/ap/bin/ternak 2>/dev/null
