#!/system/bin/sh
# ===================================================================
# Ternak Device Changer — Core v4.15.0 (DSL-Integrated)
# Persona: Pixel 7 Pro (cheetah, gs201, Android 15 QPR2)
# Targets: com.shopee.id com.tokopedia.tkpd com.ss.android.ugc.trill
# ===================================================================

VERSION="4.15.0-dsl-integrated"
MODDIR="${MODDIR:-/data/adb/modules/ternak_device_changer}"
COMMON="${MODDIR}/common"

. "${COMMON}/state.sh"           || { echo "FATAL: state.sh"; exit 2; }
ensure_persistent_state
with_lock

. "${COMMON}/prop_safety.sh"     || { log "FATAL: prop_safety"; exit 2; }
. "${COMMON}/persona_freeze.sh"  || { log "FATAL: persona_freeze"; exit 2; }
. "${COMMON}/ssaid_abx.sh"       || { log "FATAL: ssaid_abx"; exit 2; }
. "${COMMON}/gaid.sh"            || { log "FATAL: gaid"; exit 2; }
. "${COMMON}/mac_bt.sh"          || { log "FATAL: mac_bt"; exit 2; }
. "${COMMON}/proc_overlay.sh"    || { log "FATAL: proc_overlay"; exit 2; }
. "${COMMON}/widevine.sh"        || { log "FATAL: widevine"; exit 2; }

TARGET_APPS="com.shopee.id com.tokopedia.tkpd com.ss.android.ugc.trill"

# -------- helpers --------
jitter() {
    local MAX=${1:-3}
    local N=$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % MAX + 1 ))
    sleep "$N"
}

get_users() {
    # Fix v4.13 bug #11: robust regex compat
    if command -v pm >/dev/null 2>&1; then
        pm list users 2>/dev/null | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p'
    else
        ls -1 /data/system/users 2>/dev/null | grep -E '^[0-9]+$'
    fi
}

escape_json() {
    # Fix v4.13 bug #10: newline-safe
    printf '%s' "$1" | awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t");
        gsub(/\r/,"\\r"); print; if (NR>0) print "\\n"
    }' | sed 's/\\n$//'
}

# -------- persona --------
persona_new_id() { printf 'p%s_%s' "$(date +%s)" "$(generate_hex 4)"; }

persona_get_mac_oui() {
    local ID DIR OUI
    ID=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    [ -n "$ID" ] || { echo "3c5ab4"; return; }
    DIR="${PERSONAS_DIR}/${ID}"
    OUI=$(grep -m1 '^WLAN_OUI=' "${DIR}/mac_pool.conf" 2>/dev/null | sed 's/^WLAN_OUI=//')
    printf '%s' "${OUI:-3c5ab4}"
}

persona_get_bt_oui() {
    local ID DIR OUI
    ID=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    DIR="${PERSONAS_DIR}/${ID}"
    OUI=$(grep -m1 '^BT_OUI=' "${DIR}/mac_pool.conf" 2>/dev/null | sed 's/^BT_OUI=//')
    printf '%s' "${OUI:-a4c361}"
}

persona_seed_pixel7pro() {
    local DIR="$1"
    mkdir -p "$DIR" 2>/dev/null
    chmod 700 "$DIR" 2>/dev/null

    # Frozen persona uses ${RANDOM_*} tokens; frozen at activate time.
    cat > "${DIR}/build.conf" <<'EOF'
FILE_ENABLED
# Pixel 7 Pro (cheetah, gs201) — Android 15 QPR2 / January 2026
ENABLED,ro.product.brand,google
ENABLED,ro.product.manufacturer,Google
ENABLED,ro.product.model,Pixel 7 Pro
ENABLED,ro.product.name,cheetah
ENABLED,ro.product.device,cheetah
ENABLED,ro.product.board,gs201
ENABLED,ro.product.system.brand,google
ENABLED,ro.product.system.manufacturer,Google
ENABLED,ro.product.system.model,Pixel 7 Pro
ENABLED,ro.product.system.name,cheetah
ENABLED,ro.product.system.device,cheetah
ENABLED,ro.product.system_ext.brand,google
ENABLED,ro.product.system_ext.manufacturer,Google
ENABLED,ro.product.system_ext.model,Pixel 7 Pro
ENABLED,ro.product.system_ext.name,cheetah
ENABLED,ro.product.system_ext.device,cheetah
ENABLED,ro.product.product.brand,google
ENABLED,ro.product.product.manufacturer,Google
ENABLED,ro.product.product.model,Pixel 7 Pro
ENABLED,ro.product.product.name,cheetah
ENABLED,ro.product.product.device,cheetah
ENABLED,ro.product.vendor.brand,google
ENABLED,ro.product.vendor.manufacturer,Google
ENABLED,ro.product.vendor.model,Pixel 7 Pro
ENABLED,ro.product.vendor.name,cheetah
ENABLED,ro.product.vendor.device,cheetah
ENABLED,ro.product.odm.brand,google
ENABLED,ro.product.odm.manufacturer,Google
ENABLED,ro.product.odm.model,Pixel 7 Pro
ENABLED,ro.product.odm.name,cheetah
ENABLED,ro.product.odm.device,cheetah
ENABLED,ro.product.cpu.abi,arm64-v8a
ENABLED,ro.product.cpu.abilist,arm64-v8a,armeabi-v7a,armeabi
ENABLED,ro.product.cpu.abilist32,armeabi-v7a,armeabi
ENABLED,ro.product.cpu.abilist64,arm64-v8a
ENABLED,ro.product.first_api_level,33
ENABLED,ro.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.build.id,AP4A.250105.002
ENABLED,ro.build.display.id,AP4A.250105.002
ENABLED,ro.build.version.incremental,13100829
ENABLED,ro.build.version.release,15
ENABLED,ro.build.version.release_or_codename,15
ENABLED,ro.build.version.sdk,35
ENABLED,ro.build.version.security_patch,2026-01-05
ENABLED,ro.build.type,user
ENABLED,ro.build.tags,release-keys
ENABLED,ro.build.description,cheetah-user 15 AP4A.250105.002 13100829 release-keys
ENABLED,ro.build.product,cheetah
ENABLED,ro.build.device,cheetah
ENABLED,ro.build.characteristics,nosdcard
ENABLED,ro.build.flavor,cheetah-user
ENABLED,ro.system.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.system_ext.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.product.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.vendor.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.vendor.build.id,AP4A.250105.002
ENABLED,ro.vendor.build.security_patch,2026-01-05
ENABLED,ro.odm.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.bootimage.build.fingerprint,google/cheetah/cheetah:15/AP4A.250105.002/13100829:user/release-keys
ENABLED,ro.boot.verifiedbootstate,green
ENABLED,ro.boot.veritymode,enforcing
ENABLED,ro.boot.flash.locked,1
ENABLED,ro.boot.warranty_bit,0
ENABLED,ro.warranty_bit,0
ENABLED,ro.debuggable,0
ENABLED,ro.secure,1
ENABLED,ro.build.selinux,1
ENABLED,ro.hardware,gs201
ENABLED,ro.hardware.chipname,gs201
EOF

    cat > "${DIR}/identifiers.conf" <<EOF
FILE_ENABLED
ENABLED,ro.serialno,\${RANDOM_SERIAL}
ENABLED,ro.boot.serialno,\${RANDOM_SERIAL}
ENABLED,ro.bootloader,cloudripper-1.4-\${RANDOM_HEX:8}
EOF

    cat > "${DIR}/mac_pool.conf" <<EOF
FILE_ENABLED
# Google/Pixel WLAN OUIs (verified public)
WLAN_OUI=3c5ab4
BT_OUI=a4c361
EOF

    cat > "${DIR}/android_id.conf" <<EOF
# Ternak Android ID (SSAID) config
DISABLED
VALUE=\${RANDOM_HEX:16}
USER=0
PKG=com.shopee.id
PKG=com.tokopedia.tkpd
PKG=com.ss.android.ugc.trill
EOF

    chmod 600 "${DIR}"/*.conf 2>/dev/null
}

persona_write_meta() {
    local ID="$1" NAME="$2" DIR="${PERSONAS_DIR}/${ID}"
    {
        echo "NAME=${NAME}"
        echo "CREATED=$(date +%s)"
        echo "TEMPLATE=pixel7pro_cheetah"
    } > "${DIR}/meta"
    chmod 600 "${DIR}/meta" 2>/dev/null
}

cmd_persona_create() {
    local NAME="${1:-Pixel7Pro-$(date +%m%d-%H%M)}"
    local ID DIR
    ID=$(persona_new_id)
    DIR="${PERSONAS_DIR}/${ID}"
    persona_seed_pixel7pro "$DIR"
    persona_write_meta "$ID" "$NAME"
    freeze_persona "$DIR"
    log "persona created: $ID ($NAME)"
    echo "$ID"
}

cmd_persona_activate() {
    local ID="$1" DIR
    [ -n "$ID" ] || { echo "usage: ternak persona activate <id>" >&2; return 1; }
    DIR="${PERSONAS_DIR}/${ID}"
    [ -d "$DIR" ] || { echo "no such persona: $ID" >&2; return 1; }

    backup_state
    freeze_persona "$DIR"

    printf '%s' "$ID" > "$ACTIVE_PERSONA_FILE"
    chmod 600 "$ACTIVE_PERSONA_FILE" 2>/dev/null
    touch "$PERSONA_FLAG"
    mark_reboot
    log "persona activated: $ID"
    echo "✓ persona activated. Reboot to apply build props."
}

cmd_persona_list() {
    local ID N C ACTIVE
    ACTIVE=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    for D in "$PERSONAS_DIR"/*/; do
        [ -d "$D" ] || continue
        ID=$(basename "$D")
        N=$(grep -m1 '^NAME=' "${D}meta" 2>/dev/null | sed 's/^NAME=//')
        C=$(grep -m1 '^CREATED=' "${D}meta" 2>/dev/null | sed 's/^CREATED=//')
        [ "$ID" = "$ACTIVE" ] && printf '* ' || printf '  '
        printf '%s  %s  (created %s)\n' "$ID" "${N:-?}" "$(date -d @${C} 2>/dev/null || echo $C)"
    done
}

# -------- backup / restore --------
_snapshot_build_extended() {
    # Fix v4.13 bug #9: cover all partitions + version keys
    local KEYS="
        ro.product.brand ro.product.manufacturer ro.product.model ro.product.name
        ro.product.device ro.product.board ro.product.first_api_level
        ro.product.system.brand ro.product.system.model ro.product.system.name
        ro.product.system_ext.brand ro.product.system_ext.model
        ro.product.product.brand ro.product.product.model
        ro.product.vendor.brand ro.product.vendor.model
        ro.product.odm.brand ro.product.odm.model
        ro.build.fingerprint ro.build.id ro.build.display.id
        ro.build.version.incremental ro.build.version.release
        ro.build.version.sdk ro.build.version.security_patch
        ro.build.type ro.build.tags ro.build.description
        ro.build.product ro.build.device ro.build.flavor
        ro.system.build.fingerprint ro.system_ext.build.fingerprint
        ro.product.build.fingerprint ro.vendor.build.fingerprint
        ro.odm.build.fingerprint ro.bootimage.build.fingerprint
        ro.vendor.build.id ro.vendor.build.security_patch
        ro.serialno ro.boot.serialno ro.bootloader ro.hardware
        ro.boot.verifiedbootstate ro.boot.veritymode ro.boot.flash.locked
        ro.boot.warranty_bit ro.warranty_bit ro.debuggable ro.secure
    "
    local K V FIRST=1
    printf '{'
    for K in $KEYS; do
        V=$(getprop "$K" 2>/dev/null)
        [ "$FIRST" -eq 1 ] && FIRST=0 || printf ','
        printf '"%s":"%s"' "$K" "$(escape_json "$V")"
    done
    printf '}'
}

backup_state() {
    mkdir -p "$BACKUP_DIR_ROOT" 2>/dev/null
    local TS=$(date +%Y%m%d_%H%M%S)
    local F="${BACKUP_DIR_ROOT}/build_${TS}.snap.json"
    _snapshot_build_extended > "$F" 2>/dev/null
    chmod 600 "$F" 2>/dev/null
    log "backup: $F"

    # Rotate
    local COUNT=$(ls -1 "$BACKUP_DIR_ROOT"/build_*.snap.json 2>/dev/null | wc -l)
    if [ "$COUNT" -gt "$BACKUP_KEEP" ]; then
        ls -1t "$BACKUP_DIR_ROOT"/build_*.snap.json 2>/dev/null | \
            tail -n +$((BACKUP_KEEP + 1)) | xargs rm -f 2>/dev/null
        log "backup rotated (keep $BACKUP_KEEP)"
    fi
    echo "$F"
}

restore_build() {
    local F="$1"
    [ -z "$F" ] && F=$(ls -1t "$BACKUP_DIR_ROOT"/build_*.snap.json 2>/dev/null | head -1)
    [ -f "$F" ] || { echo "no backup found" >&2; return 1; }
    log "restoring from: $F"

    local RESETPROP="$(command -v resetprop-rs 2>/dev/null)"
    [ -n "$RESETPROP" ] || RESETPROP="$MODDIR/bin/resetprop-rs"
    [ -x "$RESETPROP" ] || RESETPROP=/data/adb/magisk/resetprop
    [ -x "$RESETPROP" ] || { echo "resetprop not found" >&2; return 1; }

    # Parse JSON with awk (no jq guaranteed)
    tr ',' '\n' < "$F" | tr -d '{}' | while IFS= read -r KV; do
        KV=${KV#\"}
        local K=${KV%%\":\"*}
        local V=${KV#*\":\"}
        V=${V%\"}
        [ -n "$K" ] && "$RESETPROP" -n "$K" "$V" 2>/dev/null
    done
    log "restore complete"
    mark_reboot
}

# -------- verify --------
verify_changes() {
    local ACTIVE PDIR EXPECTED ACTUAL MISMATCH=0
    ACTIVE=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    [ -n "$ACTIVE" ] || { echo "no active persona"; return 1; }
    PDIR="${PERSONAS_DIR}/${ACTIVE}"

    echo "=== Persona: $ACTIVE ==="
    grep '^ENABLED,' "${PDIR}/build.conf" 2>/dev/null | while IFS=',' read -r _ K V; do
        ACTUAL=$(getprop "$K" 2>/dev/null)
        if [ "$ACTUAL" != "$V" ]; then
            printf '✗ %s\n    expected: %s\n    actual:   %s\n' "$K" "$V" "$ACTUAL"
        else
            printf '✓ %s\n' "$K"
        fi
    done

    echo ""
    echo "=== Hardware consistency ==="
    local HW=$(getprop ro.hardware)
    local BOARD=$(getprop ro.product.board)
    local FP=$(getprop ro.build.fingerprint)
    printf 'ro.hardware       : %s\n' "$HW"
    printf 'ro.product.board  : %s\n' "$BOARD"
    printf 'ro.build.fingerprint: %s\n' "$FP"
    case "$FP" in
        */cheetah/*) [ "$BOARD" = "gs201" ] || echo "⚠ board mismatch" ;;
    esac

    echo ""
    echo "=== MAC ==="
    local IF=$(get_wlan_iface)
    printf 'wlan(%s): %s\n' "$IF" "$(cat /sys/class/net/${IF}/address 2>/dev/null)"

    echo ""
    echo "=== Widevine ==="
    cat "$WIDEVINE_LVL_FILE" 2>/dev/null || echo "default"
}

# -------- preflight --------
preflight() {
    local ISSUES=0
    echo "=== ternak v${VERSION} preflight ==="

    # Root manager
    for R in ksu ap magisk; do
        [ -d "/data/adb/${R}" ] && { echo "✓ root manager: ${R}"; break; }
    done

    # resetprop
    command -v resetprop-rs >/dev/null 2>&1 || \
        [ -x "$MODDIR/bin/resetprop-rs" ] || \
        [ -x /data/adb/magisk/resetprop ] || \
        [ -x /data/adb/ksu/bin/resetprop ] || \
        [ -x /data/adb/ap/bin/resetprop ] || \
        { echo "✗ resetprop missing"; ISSUES=$((ISSUES + 1)); }
    [ "$ISSUES" -eq 0 ] && echo "✓ resetprop available"

    # ABX tools
    if command -v abx2xml >/dev/null 2>&1 || [ -x /system/bin/abx2xml ]; then
        echo "✓ abx tools (SSAID rewrite supported)"
    else
        echo "⚠ abx2xml not found — SSAID rewrite will fail on Android 12+"
    fi

    # State dir writable
    if touch "${DATA_DIR}/.test" 2>/dev/null; then
        rm -f "${DATA_DIR}/.test"
        echo "✓ DATA_DIR writable: ${DATA_DIR}"
    else
        echo "✗ DATA_DIR not writable"; ISSUES=$((ISSUES + 1))
    fi

    # SELinux
    local SE=$(getenforce 2>/dev/null)
    echo "  SELinux: ${SE:-unknown}"

    # Users
    echo "  Users: $(get_users | tr '\n' ' ')"

    if [ "$ISSUES" -eq 0 ]; then
        echo ""
        echo "✅ preflight OK"
        return 0
    fi
    echo ""
    echo "❌ preflight has ${ISSUES} issue(s)"
    return 1
}

# -------- do_fresh --------
do_fresh() {
    local ACTIVE PDIR
    ACTIVE=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    [ -n "$ACTIVE" ] || { echo "no active persona; run: ternak persona create + activate" >&2; return 1; }
    PDIR="${PERSONAS_DIR}/${ACTIVE}"

    log "===== FRESH START ($ACTIVE) ====="
    backup_state >/dev/null

    # SSAID revert last, then apply new
    ai_revert_last_applied

    local SSAID_VAL=$(grep -m1 '^VALUE=' "${PDIR}/android_id.conf" 2>/dev/null | sed 's/^VALUE=//')
    local USER=$(grep -m1 '^USER=' "${PDIR}/android_id.conf" 2>/dev/null | sed 's/^USER=//')
    local TARGETS=$(grep '^PKG=' "${PDIR}/android_id.conf" 2>/dev/null | sed 's/^PKG=//')

    if [ -n "$SSAID_VAL" ] && [ -n "$TARGETS" ] && grep -q '^ENABLED$' "${PDIR}/android_id.conf"; then
        ai_apply_user "${USER:-0}" "$SSAID_VAL" $TARGETS
        [ "$AI_APPLIED_COUNT" -gt 0 ] && ai_record_applied "${USER:-0}" $TARGETS
    fi

    # GAID
    set_gaid_value "${USER:-0}" "$(generate_uuid)"

    # MAC / BT
    jitter 3
    randomize_wlan_mac >/dev/null
    jitter 2
    randomize_bt_mac >/dev/null
    randomize_device_name "Pixel 7 Pro"

    # /proc overlay (opt-in only)
    apply_proc_overlay "gs201"

    echo "✓ fresh complete for persona $ACTIVE"
    echo "  Reboot required for build props to apply"
    mark_reboot
}

# -------- unfresh (with --force guard) --------
unfresh() {
    local FORCE=0
    [ "$1" = "--force" ] && FORCE=1
    if [ "$FORCE" -eq 0 ]; then
        printf 'This will revert all spoofing. Type YES to confirm: '
        read ANS
        [ "$ANS" = "YES" ] || { echo "aborted"; return 1; }
    fi
    log "===== UNFRESH ====="
    ai_revert_last_applied
    gaid_revert
    unapply_proc_overlay
    restore_build
    rm -f "$PERSONA_FLAG" 2>/dev/null
    rm -f "$ACTIVE_PERSONA_FILE" 2>/dev/null
    echo "✓ unfresh complete. Reboot recommended."
}

# -------- router --------
main() {

# ======== WEBUI COMPATIBILITY COMMANDS ========

list_personas() {
    printf '['
    local first=1
    for d in "$PERSONAS_DIR"/*/; do
        [ -d "$d" ] || continue
        [ $first -eq 0 ] && printf ','
        local id=$(basename "$d")
        local name=$(grep -m1 '^NAME=' "${d}meta" 2>/dev/null | sed 's/^NAME=//')
        local aid=$(grep -m1 '^VALUE=' "${d}android_id.conf" 2>/dev/null | sed 's/^VALUE=//')
        printf '{"profile":"%s","package":"%s","androidId":"%s"}' "$(escape_json "$id ($name)")" "ALL" "$(escape_json "$aid")"
        first=0
    done
    printf ']'
}

get_info() {
    local android_id="$(settings get secure android_id 2>/dev/null)"
    local bt_name="$(settings get global bluetooth_name 2>/dev/null)"
    local hostname_val="$(getprop net.hostname 2>/dev/null)"
    [ -z "$hostname_val" ] && hostname_val="$(hostname 2>/dev/null)"
    local gaid="$(settings get global advertising_id 2>/dev/null)"
    local model="$(getprop ro.product.model 2>/dev/null)"
    local brand="$(getprop ro.product.brand 2>/dev/null)"
    local serial="$(getprop ro.serialno 2>/dev/null)"
    local fingerprint="$(getprop ro.build.fingerprint 2>/dev/null)"
    local sdk="$(getprop ro.build.version.sdk 2>/dev/null)"
    local profile_name="-"
    local active_id=$(cat "$ACTIVE_PERSONA_FILE" 2>/dev/null | tr -d ' \n\r')
    if [ -n "$active_id" ]; then
        local p_name=$(grep -m1 '^NAME=' "${PERSONAS_DIR}/${active_id}/meta" 2>/dev/null | sed 's/^NAME=//')
        profile_name="${active_id} (${p_name})"
    fi

    [ -z "$android_id" ] || [ "$android_id" = "null" ] && android_id="—"
    [ -z "$gaid" ] || [ "$gaid" = "null" ] && gaid="—"
    [ -z "$bt_name" ] || [ "$bt_name" = "null" ] && bt_name="—"

    local persona_count=$(ls -1d "$PERSONAS_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
    local rp_ok="$([ -n "$RESETPROP" ] && echo true || echo false)"

    printf '{"android_id":"%s","bt_name":"%s","hostname":"%s","gaid":"%s","model":"%s","brand":"%s","serial":"%s","fingerprint":"%s","sdk":"%s","profile":"%s","root_manager":"ksu/magisk","persona_count":%s,"modules":{"pif":false,"specter":false,"zygisk_next":false,"resetprop":%s,"resetprop_mode":"v4.15"}}' \
        "$(escape_json "$android_id")" "$(escape_json "$bt_name")" "$(escape_json "$hostname_val")" \
        "$(escape_json "$gaid")" "$(escape_json "$model")" "$(escape_json "$brand")" "$(escape_json "$serial")" \
        "$(escape_json "$fingerprint")" "$(escape_json "$sdk")" "$(escape_json "$profile_name")" \
        "$persona_count" "$rp_ok"
}

burn_persona() {
    local pkg="$1"
    for u in $(get_users); do
        pm clear --user "$u" "$pkg" >/dev/null 2>&1
        rm -rf "/data/media/$u/Android/data/$pkg" "/data/media/$u/Android/media/$pkg" "/data/media/$u/Android/obb/$pkg" 2>/dev/null
    done
}

webui_settings_get() {
    printf '{'
    printf '"ENABLE_SEAL":"true"'
    printf '}'
}
    local CMD="${1:-info}"
    shift 2>/dev/null || true
    case "$CMD" in
        info|version) get_info ;;
        personas_active) list_personas ;;
        settings_get) webui_settings_get ;;
        settings_set) echo "OK" ;;
        burn) burn_persona "$2" ;;
        personas_active) list_personas ;;
        settings_get) webui_settings_get ;;
        settings_set) echo "OK" ;;
        burn) burn_persona "$1" ;;
        preflight)     preflight ;;
        fresh)         do_fresh ;;
        unfresh)       unfresh "$@" ;;
        persona)
            case "$1" in
                create)   shift; cmd_persona_create "$@" ;;
                activate) shift; cmd_persona_activate "$@" ;;
                list)     cmd_persona_list ;;
                *) echo "usage: ternak persona {create|activate <id>|list}" >&2; exit 2 ;;
            esac ;;
        backup)        backup_state ;;
        restore)       restore_build "$@" ;;
        verify)        verify_changes ;;
        mac)           randomize_wlan_mac "$@" ;;
        bt)            randomize_bt_mac "$@" ;;
        name)          randomize_device_name "$@" ;;
        ssaid)
            case "$1" in
                apply)   shift; ai_apply_user "$@" ;;
                revert)  ai_revert_last_applied ;;
                *) echo "usage: ternak ssaid {apply <user> <val> <pkg...>|revert}" >&2; exit 2 ;;
            esac ;;
        gaid)
            case "$1" in
                set)    shift; set_gaid_value "$@" ;;
                revert) gaid_revert ;;
                *) echo "usage: ternak gaid {set <user> <uuid>|revert}" >&2; exit 2 ;;
            esac ;;
        widevine)      enforce_widevine_level "$@" ;;
        proc_overlay)
            case "$1" in
                enable)  touch "$PROC_OVERLAY_FLAG"; chmod 600 "$PROC_OVERLAY_FLAG"; echo "enabled (next boot)" ;;
                disable) rm -f "$PROC_OVERLAY_FLAG"; echo "disabled" ;;
                apply)   apply_proc_overlay "$2" ;;
                *) echo "usage: ternak proc_overlay {enable|disable|apply <sig>}" >&2; exit 2 ;;
            esac ;;
        log)           tail -n 100 "$LOG_FILE" ;;
        diag)          preflight; echo; verify_changes ;;
        reboot)        mark_reboot; svc power reboot 2>/dev/null || reboot ;;
        *)
            cat <<HELP
ternak v${VERSION}

Commands:
  info | preflight | diag | log
  persona {create [name]|activate <id>|list}
  fresh | unfresh [--force]
  backup | restore [file]
  verify
  ssaid {apply <user> <val> <pkg...>|revert}
  gaid {set <user> <uuid>|revert}
  mac [addr] | bt [addr] | name [str]
  widevine {L1|L2|L3}
  proc_overlay {enable|disable|apply <sig>}
  re"b"o"o"t
HELP
            ;;
    esac
}

main "$@"
