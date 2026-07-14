#!/system/bin/sh
# Ternak v4.15 - GAID (Google Advertising ID) with per-user backup + granular revert.
# Backup approach adopted from DSL SSAID pattern.

gaid_valid_uuid() {
    printf '%s' "$1" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
}

gaid_path() {
    printf '/data/user/%s/com.google.android.gms/shared_prefs/adid_settings.xml' "$1"
}

gaid_backup() {
    local U="$1" F="$2" DST
    DST="${GAID_BACKUP_DIR}/user${U}_adid_settings.xml.orig"
    [ -f "$DST" ] && return 0
    mkdir -p "$GAID_BACKUP_DIR" 2>/dev/null
    chmod 700 "$GAID_BACKUP_DIR" 2>/dev/null
    cp "$F" "$DST" 2>/dev/null && chmod 600 "$DST" 2>/dev/null && \
        log "[gaid] backed up original for user ${U}"
}

set_gaid_value() {
    local U="$1" NEW="$2" F TMP
    gaid_valid_uuid "$NEW" || { log "[gaid] invalid uuid: $NEW"; return 1; }
    F=$(gaid_path "$U")
    [ -f "$F" ] || { log "[gaid] no adid_settings for user $U"; return 1; }

    gaid_backup "$U" "$F"

    TMP="${F}.tmp.$$"
    if sed 's|<string name="adid_key">[^<]*</string>|<string name="adid_key">'"${NEW}"'</string>|' \
           "$F" > "$TMP" 2>/dev/null; then
        # Preserve ownership + SELinux context
        local OWNER GROUP
        OWNER=$(stat -c '%u' "$F" 2>/dev/null)
        GROUP=$(stat -c '%g' "$F" 2>/dev/null)
        mv -f "$TMP" "$F"
        [ -n "$OWNER" ] && [ -n "$GROUP" ] && chown "${OWNER}:${GROUP}" "$F" 2>/dev/null
        chmod 660 "$F" 2>/dev/null
        restorecon "$F" 2>/dev/null
        log "[gaid] user ${U}: set to ${NEW}"

        # Record for revert
        {
            echo "USER=${U}"
            echo "TIMESTAMP=$(date +%s)"
            echo "VALUE=${NEW}"
        } > "$GAID_APPLIED_STATE" 2>/dev/null
        chmod 600 "$GAID_APPLIED_STATE" 2>/dev/null
        return 0
    fi
    rm -f "$TMP"
    return 1
}

gaid_revert() {
    [ -f "$GAID_APPLIED_STATE" ] || return 0
    local U DST F
    U=$(grep -m1 '^USER=' "$GAID_APPLIED_STATE" | sed 's/^USER=//')
    DST="${GAID_BACKUP_DIR}/user${U}_adid_settings.xml.orig"
    F=$(gaid_path "$U")
    [ -f "$DST" ] && [ -f "$F" ] || return 0
    cp "$DST" "$F" 2>/dev/null && chmod 660 "$F" 2>/dev/null && restorecon "$F" 2>/dev/null
    rm -f "$GAID_APPLIED_STATE" 2>/dev/null
    log "[gaid] reverted user ${U}"
}
