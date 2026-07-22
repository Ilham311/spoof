#!/system/bin/sh
# ============================================================
# post-fs-data.sh — Ternak Device Changer (v4.13-a15-rs)
# Bootloop-safe + resetprop-rs WAJIB. Data-driven: baca system.prop.
# Smart fallback: derive missing spoof.prop keys dari FINGERPRINT.
# ============================================================
MODDIR="${0%/*}"
RP="$MODDIR/bin/resetprop-rs"
PROP="$MODDIR/system.prop"
LOG="$MODDIR/logs/postfsdata.log"
mkdir -p "$MODDIR/logs" 2>/dev/null
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

# --- Guard 1: resetprop-rs WAJIB ---
[ -x "$RP" ] || chmod +x "$RP" 2>/dev/null
[ -x "$RP" ] || { log "resetprop-rs tidak ada -> skip total"; RP=""; }

# --- Guard 2: kalau ada system.prop, terapkan (butuh RP) ---
if [ -n "$RP" ] && [ -f "$PROP" ]; then
    ST="-st"
    "$RP" -st ternak.pfd.probe 1 2>/dev/null
    [ "$(getprop ternak.pfd.probe)" = "1" ] || ST="-n"
    "$RP" -nk ternak.pfd.probe 2>/dev/null || "$RP" -d ternak.pfd.probe 2>/dev/null
    log "write-mode=$ST"

    "$RP" $ST -f "$PROP" 2>/dev/null
    while IFS='=' read -r k v; do
        case "$k" in ''|\#*) continue ;; esac
        [ "$(getprop "$k")" = "$v" ] || "$RP" $ST "$k" "$v" 2>/dev/null
    done < "$PROP"
    log "props applied dari system.prop"

    # RE-SEAL display props tiap boot
    if [ "$ST" = "-st" ]; then
        B=$(getprop ro.product.brand);  MF=$(getprop ro.product.manufacturer)
        MD=$(getprop ro.product.model); DV=$(getprop ro.product.device)
        NM=$(getprop ro.product.name);  FP=$(getprop ro.build.fingerprint)
        BID=$(getprop ro.build.id)
        if "$RP" --seal ro.product.model --check >/dev/null 2>&1; then
            "$RP" --seal ro.product.brand "$B" \
                  --seal ro.product.manufacturer "$MF" \
                  --seal ro.product.model "$MD" \
                  --seal ro.product.device "$DV" \
                  --seal ro.product.name "$NM" \
                  --seal ro.build.fingerprint "$FP" \
                  --seal ro.build.id "$BID" 2>/dev/null \
                && log "sealed (Tier B batch)" \
                || { "$RP" --seal-arena ro.build.fingerprint "$FP" 2>/dev/null; log "seal fallback Tier A (arena)"; }
        else
            log "seal --check gagal -> skip seal"
        fi
    fi
    "$RP" --compact 2>/dev/null
    log "post-fs-data apply-native selesai"
fi

# ============================================================
# Zygisk bootstrap (v4.13 smart fallback)
# ============================================================
TERNAK="$MODDIR"

# hook_targets.txt default
if [ ! -f "$TERNAK/hook_targets.txt" ]; then
    cat > "$TERNAK/hook_targets.txt" <<'ZEOF'
# 1 baris = 1 package. Suffix "*" = prefix match.
com.shopee.id
com.tokopedia.tkpd
com.ss.android.ugc.trill
com.zhiliaoapp.musically
com.liuzh.deviceinfo
com.cwsl.mydevice
ZEOF
    chmod 644 "$TERNAK/hook_targets.txt"
    log "hook_targets.txt bootstrap default"
fi

# spoof.prop smart fallback: kalau ternak belum pernah tulis, copy pif.prop
# LALU augment key yang di-derive dari FINGERPRINT (BRAND/DEVICE/BOARD/HARDWARE/PRODUCT/TYPE/TAGS/dll).
if [ ! -f "$TERNAK/spoof.prop" ] && [ -f /data/adb/modules/playintegrityfix/pif.prop ]; then
    cp /data/adb/modules/playintegrityfix/pif.prop "$TERNAK/spoof.prop"
    log "spoof.prop: fallback copy dari pif.prop"

    FP=$(grep -E '^FINGERPRINT=' "$TERNAK/spoof.prop" | head -n1 | cut -d= -f2- | tr -d '"\r')
    if [ -n "$FP" ]; then
        # google/oriole_beta/oriole:CANARY/ZP11.260618.005/15760424:user/release-keys
        # brand   /product     /device :release/id           /incremental:type/tags
        _BR=$(echo "$FP" | cut -d/ -f1)
        _PR=$(echo "$FP" | cut -d/ -f2)
        _DVR=$(echo "$FP" | cut -d/ -f3)
        _DV=$(echo "$_DVR" | cut -d: -f1)
        _RL=$(echo "$_DVR" | cut -d: -f2)
        _BID=$(echo "$FP" | cut -d/ -f4)
        _INTP=$(echo "$FP" | cut -d/ -f5)
        _INC=$(echo "$_INTP" | cut -d: -f1)
        _TY=$(echo "$_INTP" | cut -d: -f2)
        _TG=$(echo "$FP" | cut -d/ -f6)
        {
            grep -q '^BRAND='       "$TERNAK/spoof.prop" || echo "BRAND=$_BR"
            grep -q '^PRODUCT='     "$TERNAK/spoof.prop" || echo "PRODUCT=$_PR"
            grep -q '^DEVICE='      "$TERNAK/spoof.prop" || echo "DEVICE=$_DV"
            grep -q '^BOARD='       "$TERNAK/spoof.prop" || echo "BOARD=$_DV"
            grep -q '^HARDWARE='    "$TERNAK/spoof.prop" || echo "HARDWARE=$_DV"
            grep -q '^RELEASE='     "$TERNAK/spoof.prop" || echo "RELEASE=$_RL"
            grep -q '^ID='          "$TERNAK/spoof.prop" || echo "ID=$_BID"
            grep -q '^INCREMENTAL=' "$TERNAK/spoof.prop" || echo "INCREMENTAL=$_INC"
            grep -q '^TYPE='        "$TERNAK/spoof.prop" || echo "TYPE=$_TY"
            grep -q '^TAGS='        "$TERNAK/spoof.prop" || echo "TAGS=$_TG"
            grep -q '^BOOTLOADER='  "$TERNAK/spoof.prop" || echo "BOOTLOADER=unknown"
            grep -q '^HOST='        "$TERNAK/spoof.prop" || echo "HOST=abfarm-release"
            grep -q '^USER='        "$TERNAK/spoof.prop" || echo "USER=android-build"
        } >> "$TERNAK/spoof.prop"
        log "spoof.prop: augmented dari FINGERPRINT ($_BR/$_PR/$_DV)"
    fi
    chmod 644 "$TERNAK/spoof.prop"
fi

log "post-fs-data.sh selesai"
exit 0
