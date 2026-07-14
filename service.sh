#!/system/bin/sh
# Ternak v4.15 - post-boot: ensure CLI symlink.

MODDIR=${0%/*}
. "${MODDIR}/common/state.sh" 2>/dev/null || exit 0
ensure_persistent_state

log "===== ternak service ====="

[ -f "${MODDIR}/disable" ] && { log "disabled"; exit 0; }

LAUNCHER="${MODDIR}/system/bin/ternak"
[ -f "$LAUNCHER" ] || exit 0
[ -x /system/bin/ternak ] && { log "CLI in system path"; exit 0; }

for B in /data/adb/ksu/bin /data/adb/ap/bin; do
    if [ -d "$B" ]; then
        ln -sf "$LAUNCHER" "$B/ternak" 2>/dev/null && log "CLI symlink: $B/ternak"
        break
    fi
done

log "service ready"
