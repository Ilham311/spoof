#!/system/bin/sh
# Ternak v4.15 - pre-zygote stage: apply BUILD PROPS ONLY.
# All identifier work (MAC, BT, SSAID, GAID) happens at runtime via CLI.

MODDIR=${0%/*}
DATA_DIR="${DATA_DIR:-/data/adb/ternak}"

. "${MODDIR}/common/state.sh" 2>/dev/null || {
    echo "[ternak] FATAL: state.sh missing" >&2
    exit 0
}
ensure_persistent_state

clear_reboot
log "===== ternak post-fs-data ====="

if [ -f "${MODDIR}/disable" ]; then
    log "module disabled - skip"
    exit 0
fi
[ -f "$PERSONA_FLAG" ] || { log "no active persona - skip"; exit 0; }

# Fail-closed: refuse everything if prop_safety.sh missing.
fail_closed_should_apply() {
    log "ERROR: prop_safety unavailable ($1/$2) - refuse prop: $3"
    return 1
}
should_apply_prop() { fail_closed_should_apply "$3" "$4" "$1"; }

if [ -f "${MODDIR}/common/prop_safety.sh" ]; then
    . "${MODDIR}/common/prop_safety.sh" || \
        should_apply_prop() { fail_closed_should_apply "$3" "$4" "$1"; }
else
    log "ERROR: prop_safety.sh missing - refusing all props"
fi

. "${MODDIR}/common/persona_freeze.sh"

# Resolve resetprop
RESETPROP="$(command -v resetprop 2>/dev/null)"
for C in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
    [ -n "$RESETPROP" ] && break
    [ -x "$C" ] && RESETPROP="$C"
done
[ -n "$RESETPROP" ] || { log "ERROR: resetprop not found"; exit 0; }
log "resetprop: $RESETPROP"

apply_prop() {
    local PROP="$1" VAL="$2"
    [ -z "$VAL" ] && return 1
    if "$RESETPROP" -n "$PROP" "$VAL" 2>/dev/null; then
        log "prop set: $PROP"
        return 0
    fi
    log "ERROR set prop: $PROP"
    return 1
}

ACTIVE=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
[ -n "$ACTIVE" ] || { log "no active persona id"; exit 0; }
PDIR="${PERSONAS_DIR}/${ACTIVE}"
[ -d "$PDIR" ] || { log "persona dir missing: $PDIR"; exit 0; }

apply_conf() {
    local FILE="$1" NAME=$(basename "$1")
    [ -f "$FILE" ] || return
    grep -q '^FILE_DISABLED' "$FILE" && { log "skip disabled: $NAME"; return; }
    log "applying: $NAME"
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        case "$LINE" in ''|'#'*|FILE_ENABLED) continue ;; esac
        local STATUS=$(echo "$LINE" | cut -d',' -f1)
        local PROP=$(echo "$LINE" | cut -d',' -f2)
        local VAL=$(echo "$LINE" | cut -d',' -f3-)
        [ "$STATUS" = "ENABLED" ] || continue
        if has_generator_token "$VAL"; then
            log "ERROR: unresolved token in $NAME → $PROP (persona not frozen?)"
            continue
        fi
        should_apply_prop "$PROP" "$VAL" "post-fs-data" "$NAME" || continue
        apply_prop "$PROP" "$VAL"
    done < "$FILE"
}

apply_conf "${PDIR}/build.conf"
apply_conf "${PDIR}/identifiers.conf"

log "pre-zygote spoof complete"
