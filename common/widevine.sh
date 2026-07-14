#!/system/bin/sh
# common/widevine.sh — L1 → L3 controlled downgrade

WIDEVINE_LVL_FILE="${STATE_DIR}/widevine_level"

enforce_widevine_level() {
    local LVL="$1"
    case "$LVL" in
        L1|L2|L3) ;;
        *) log "[widevine] invalid level: $LVL"; return 1 ;;
    esac
    echo "$LVL" > "$WIDEVINE_LVL_FILE"
    chmod 600 "$WIDEVINE_LVL_FILE" 2>/dev/null

    if [ "$LVL" = "L3" ]; then
        # Force L3 by clearing OEMCrypto state (app must reboot)
        rm -rf /data/vendor/mediadrm/IDM*.dat 2>/dev/null
        rm -rf /data/mediadrm/IDM*.dat 2>/dev/null
        rm -rf /data/vendor/mediadrm/*.bin 2>/dev/null
        log "[widevine] cleared L1 state → next boot will be L3"
    fi
    log "[widevine] level set: ${LVL}"
}
