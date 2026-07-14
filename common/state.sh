#!/system/bin/sh
# Ternak v4.15 - persistent state paths + legacy migration.
# Adopts DSL pattern: state lives OUTSIDE MODDIR so it survives module reinstall.

MODDIR="${MODDIR:-/data/adb/modules/ternak_device_changer}"
DATA_DIR="${DATA_DIR:-/data/adb/ternak}"
STATE_DIR="${STATE_DIR:-${DATA_DIR}/state}"
BACKUP_DIR_ROOT="${BACKUP_DIR_ROOT:-${DATA_DIR}/backups}"
PERSONAS_DIR="${PERSONAS_DIR:-${DATA_DIR}/personas}"
SSAID_BACKUP_DIR="${SSAID_BACKUP_DIR:-${DATA_DIR}/ssaid_backup}"
GAID_BACKUP_DIR="${GAID_BACKUP_DIR:-${DATA_DIR}/gaid_backup}"

ACTIVE_PERSONA_FILE="${ACTIVE_PERSONA_FILE:-${STATE_DIR}/active_persona}"
PERSONA_FLAG="${PERSONA_FLAG:-${STATE_DIR}/persona_active}"
REBOOT_PENDING="${REBOOT_PENDING:-${STATE_DIR}/reboot_pending}"
LAST_RUN_FILE="${LAST_RUN_FILE:-${STATE_DIR}/last_run}"
SSAID_APPLIED_STATE="${SSAID_APPLIED_STATE:-${DATA_DIR}/ssaid_applied.conf}"
GAID_APPLIED_STATE="${GAID_APPLIED_STATE:-${DATA_DIR}/gaid_applied.conf}"

LOG_FILE="${LOG_FILE:-${DATA_DIR}/ternak.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-131072}"
LOCK_FILE="${LOCK_FILE:-${STATE_DIR}/ternak.lock}"
BACKUP_KEEP="${BACKUP_KEEP:-10}"

# Legacy paths (v4.13 and earlier)
LEGACY_STATE_DIR="${MODDIR}/state"
LEGACY_BACKUP_ROOT="${MODDIR}/backups"
LEGACY_PERSONAS_DIR="${MODDIR}/personas"

_TERNAK_LOG_READY=""

prepare_log() {
    [ "$_TERNAK_LOG_READY" = "$LOG_FILE" ] && return 0
    mkdir -p "${LOG_FILE%/*}" 2>/dev/null
    chmod 700 "${LOG_FILE%/*}" 2>/dev/null
    if [ -f "$LOG_FILE" ]; then
        local SZ=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
        if [ "${SZ:-0}" -gt "$LOG_MAX_BYTES" ]; then
            mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null
            chmod 600 "${LOG_FILE}.1" 2>/dev/null
        fi
    fi
    touch "$LOG_FILE" 2>/dev/null
    chmod 600 "$LOG_FILE" 2>/dev/null
    _TERNAK_LOG_READY="$LOG_FILE"
}

append_log_line() {
    prepare_log
    echo "$1" >> "$LOG_FILE"
}

log() {
    append_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

migrate_legacy_state() {
    # v4.13 → v4.15: move state from MODDIR to DATA_DIR (survives reinstall)
    [ -d "$LEGACY_STATE_DIR" ] || return 0
    [ -f "${STATE_DIR}/.migrated_from_v413" ] && return 0

    log "Migrating legacy state from ${LEGACY_STATE_DIR} → ${STATE_DIR}"

    if [ -f "${LEGACY_STATE_DIR}/active_persona" ] && [ ! -f "$ACTIVE_PERSONA_FILE" ]; then
        cp -p "${LEGACY_STATE_DIR}/active_persona" "$ACTIVE_PERSONA_FILE" 2>/dev/null
    fi
    if [ -f "${LEGACY_STATE_DIR}/persona_active" ] && [ ! -f "$PERSONA_FLAG" ]; then
        touch "$PERSONA_FLAG" 2>/dev/null
    fi
    if [ -d "$LEGACY_BACKUP_ROOT" ]; then
        cp -rp "${LEGACY_BACKUP_ROOT}/." "$BACKUP_DIR_ROOT/" 2>/dev/null
    fi
    if [ -d "$LEGACY_PERSONAS_DIR" ]; then
        cp -rp "${LEGACY_PERSONAS_DIR}/." "$PERSONAS_DIR/" 2>/dev/null
    fi

    touch "${STATE_DIR}/.migrated_from_v413" 2>/dev/null
    chmod 600 "${STATE_DIR}/.migrated_from_v413" 2>/dev/null
    log "Legacy migration complete"
}

ensure_persistent_state() {
    mkdir -p "$DATA_DIR" "$STATE_DIR" "$BACKUP_DIR_ROOT" "$PERSONAS_DIR" \
             "$SSAID_BACKUP_DIR" "$GAID_BACKUP_DIR" 2>/dev/null
    chmod 700 "$DATA_DIR" "$STATE_DIR" "$BACKUP_DIR_ROOT" "$PERSONAS_DIR" \
              "$SSAID_BACKUP_DIR" "$GAID_BACKUP_DIR" 2>/dev/null
    prepare_log
    migrate_legacy_state
}

mark_reboot() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    touch "$REBOOT_PENDING" 2>/dev/null
    chmod 600 "$REBOOT_PENDING" 2>/dev/null
}

clear_reboot() {
    rm -f "$REBOOT_PENDING" 2>/dev/null
}

with_lock() {
    # Serialize concurrent invocations. Requires util-linux flock OR toybox flock.
    local FLOCK="$(command -v flock 2>/dev/null)"
    if [ -n "$FLOCK" ]; then
        exec 9>"$LOCK_FILE"
        "$FLOCK" -n 9 || { log "Another ternak instance is running; aborting"; exit 1; }
    fi
}
