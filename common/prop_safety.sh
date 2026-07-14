#!/system/bin/sh
# Ternak v4.15 - fail-closed prop allowlist (adopted from DSL).
# Default DENY. Only explicitly-listed identity props may be spoofed.

ALLOW_UNSAFE_PROPS_FILE="${STATE_DIR}/allow_unsafe_props"

safety_log() {
    case "$(type log 2>/dev/null)" in
        *function*) log "$1" ;;
    esac
}

unsafe_props_allowed() {
    [ -f "$ALLOW_UNSAFE_PROPS_FILE" ] && return 0
    [ "$(getprop persist.ternak.allow_unsafe 2>/dev/null)" = "1" ] && return 0
    return 1
}

is_safe_identity_prop() {
    case "$1" in
        # Product identity
        ro.product.brand|ro.product.manufacturer|ro.product.model|\
        ro.product.name|ro.product.device|ro.product.board|\
        ro.product.system.*|ro.product.system_ext.*|\
        ro.product.product.*|ro.product.vendor.*|ro.product.odm.*|\
        ro.product.bootimage.*|ro.product.odm_dlkm.*|\
        ro.product.vendor_dlkm.*|ro.product.system_dlkm.*|\
        ro.product.cpu.abi|ro.product.cpu.abilist*|\
        ro.product.first_api_level|ro.product.locale)
            return 0 ;;
        # Build info
        ro.build.fingerprint|ro.build.id|ro.build.display.id|\
        ro.build.version.incremental|ro.build.version.release|\
        ro.build.version.release_or_codename|ro.build.version.sdk|\
        ro.build.version.security_patch|ro.build.type|ro.build.tags|\
        ro.build.description|ro.build.product|ro.build.device|\
        ro.build.characteristics|ro.build.flavor|ro.build.host|ro.build.user|\
        ro.build.date|ro.build.date.utc)
            return 0 ;;
        # Partition build fingerprints
        ro.product.build.*|ro.system.build.*|ro.system_ext.build.*|\
        ro.vendor.build.*|ro.odm.build.*|ro.bootimage.build.*|\
        ro.odm_dlkm.build.*|ro.vendor_dlkm.build.*|ro.system_dlkm.build.*)
            return 0 ;;
        # Serial + bootloader
        ro.serialno|ro.boot.serialno|ro.boot.hardware.sku|\
        ro.bootloader|ro.hardware|ro.hardware.chipname|\
        ro.revision|ro.boot.revision)
            return 0 ;;
        # Boot state (managed carefully via widevine.sh / prop_safety opt-in)
        ro.boot.verifiedbootstate|ro.boot.veritymode|\
        ro.boot.flash.locked|ro.boot.warranty_bit|\
        ro.warranty_bit|ro.debuggable|ro.secure|\
        ro.build.selinux)
            return 0 ;;
    esac
    return 1
}

should_apply_prop() {
    local PROP="$1" VALUE="$2" STAGE="$3" SOURCE="$4"
    unsafe_props_allowed && return 0
    if is_safe_identity_prop "$PROP"; then
        return 0
    fi
    safety_log "prop_safety DENY (${STAGE}/${SOURCE}): $PROP=$VALUE"
    return 1
}

# Fail-closed fallback: if this file failed to source, callers should use this stub
# and refuse everything. See post-fs-data.sh for the fail-closed pattern.
