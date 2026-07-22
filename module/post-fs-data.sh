#!/system/bin/sh
# ============================================================
# post-fs-data.sh — Ternak Device Changer (v4.10-a15-rs)
# Dijalankan OTOMATIS oleh KSU/Magisk/APatch tiap boot (early boot).
# Bootloop-safe + resetprop-rs WAJIB. Data-driven: baca system.prop.
# ============================================================
MODDIR="${0%/*}"
RP="$MODDIR/bin/resetprop-rs"
PROP="$MODDIR/system.prop"
LOG="$MODDIR/logs/postfsdata.log"
mkdir -p "$MODDIR/logs" 2>/dev/null
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

# --- Guard 1: resetprop-rs WAJIB. Tanpa itu JANGAN tulis apa pun (anti-bootloop) ---
[ -x "$RP" ] || chmod +x "$RP" 2>/dev/null
[ -x "$RP" ] || { log "resetprop-rs tidak ada -> skip total"; exit 0; }

# --- Guard 2: belum pernah 'fresh' (system.prop tidak ada) -> no-op ---
[ -f "$PROP" ] || { log "system.prop tidak ada -> no-op"; exit 0; }

# --- Pilih mode tulis: stealth (-st) kalau device support, else -n (tetap rs) ---
ST="-st"
"$RP" -st ternak.pfd.probe 1 2>/dev/null
[ "$(getprop ternak.pfd.probe)" = "1" ] || ST="-n"
"$RP" -nk ternak.pfd.probe 2>/dev/null || "$RP" -d ternak.pfd.probe 2>/dev/null
log "write-mode=$ST"

# --- Terapkan SEMUA prop dari system.prop (SAFE display subset saja) ---
# 1 proses via -f, lalu rekonsiliasi per-key (verify + retry yang belum nempel).
"$RP" $ST -f "$PROP" 2>/dev/null
while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    [ "$(getprop "$k")" = "$v" ] || "$RP" $ST "$k" "$v" 2>/dev/null
done < "$PROP"
log "props applied dari system.prop"

# --- RE-SEAL display props tiap boot (seal resetprop-rs TIDAK persist across reboot) ---
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
        log "seal --check gagal -> skip seal (hindari init tak stabil)"
    fi
fi

# --- Compact arena (buang gap forensik) ---
"$RP" --compact 2>/dev/null
log "post-fs-data selesai"

# ---- Zygisk bootstrap (merged edition) ----
TERNAK="$MODDIR"
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
fi
if [ ! -e "$TERNAK/spoof.prop" ] && [ -f /data/adb/modules/playintegrityfix/pif.prop ]; then
    cat /data/adb/modules/playintegrityfix/pif.prop > "$TERNAK/spoof.prop" 2>/dev/null
fi
# --------------------------------------------

exit 0