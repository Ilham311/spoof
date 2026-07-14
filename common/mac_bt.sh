#!/system/bin/sh
# Ternak v4.15 - MAC + Bluetooth randomization with persona OUI pool.

get_wlan_iface() {
    # Fix v4.13 bug #5: don't hardcode wlan0. Enumerate real interfaces.
    local IF
    for IF in $(ls /sys/class/net 2>/dev/null); do
        case "$IF" in
            wlan*|wifi*)
                [ -f "/sys/class/net/${IF}/address" ] && { printf '%s' "$IF"; return 0; } ;;
        esac
    done
    printf 'wlan0'
}

randomize_wlan_mac() {
    local NEW="$1" IF
    IF=$(get_wlan_iface)
    [ -n "$NEW" ] || NEW=$(generate_mac "$(persona_get_mac_oui)")

    # 1. Runtime change
    ip link set "$IF" down 2>/dev/null
    ip link set "$IF" address "$NEW" 2>/dev/null || \
        ifconfig "$IF" hw ether "$NEW" 2>/dev/null
    ip link set "$IF" up 2>/dev/null

    # 2. Persist across reboot via WifiConfigStore.xml (safer than deleting wifi passwords)
    # We DON'T touch /data/misc/wifi/WifiConfigStore.xml directly (would nuke saved APs).
    # Instead we set the persistent random-mac setting.
    settings put global wifi_scan_always_enabled 1 2>/dev/null
    settings put secure wifi_privacy_random_mac_setting 1 2>/dev/null

    log "[mac] WLAN(${IF}) → ${NEW}"
    printf '%s' "$NEW"
}

randomize_bt_mac() {
    local NEW="$1"
    [ -n "$NEW" ] || NEW=$(generate_mac "$(persona_get_bt_oui)")

    # Runtime: turn BT off, set factory addr, back on
    settings put global bluetooth_on 0 2>/dev/null
    sleep 1
    if [ -f /data/misc/bluedroid/bt_config.conf ]; then
        local F=/data/misc/bluedroid/bt_config.conf
        sed -i "s|^Address = .*|Address = ${NEW}|" "$F" 2>/dev/null
        chown bluetooth:bluetooth "$F" 2>/dev/null
        restorecon "$F" 2>/dev/null
    fi
    if [ -f /data/misc/bluetooth/bt_config.conf ]; then
        sed -i "s|^Address = .*|Address = ${NEW}|" /data/misc/bluetooth/bt_config.conf 2>/dev/null
    fi
    settings put global bluetooth_on 1 2>/dev/null

    log "[bt] adapter → ${NEW}"
    printf '%s' "$NEW"
}

randomize_device_name() {
    local NEW="$1"
    [ -n "$NEW" ] || NEW="Pixel 7 Pro"
    settings put global device_name "$NEW" 2>/dev/null
    settings put secure bluetooth_name "$NEW" 2>/dev/null
    settings put global bluetooth_name "$NEW" 2>/dev/null
    log "[name] device+bt → ${NEW}"
}
