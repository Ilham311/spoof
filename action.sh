#!/system/bin/sh

# ============================================================
# Ternak Device Changer - Action Script
# Mendeteksi WebUI manager yang terinstall dan membukanya.
# Jika tidak ada, jalankan Full Proses via terminal.
# ============================================================

MODDIR="${0%/*}"
MODULE_ID="ternak_device_changer"

# --- Coba buka WebUI lewat manager yang tersedia ---

# Fungsi helper untuk cek package dan start activity
check_and_start() {
    local pkg="$1"
    local cmp="$2"
    local ext_key="$3"

    if pm list packages 2>/dev/null | grep -q "^package:${pkg}\$"; then
        echo "- Membuka WebUI di ${pkg}..."
        # Menggunakan --user 0 atau current untuk kompatibilitas multi-user
        am start --user 0 -n "${cmp}" -e "${ext_key}" "$MODULE_ID" >/dev/null 2>&1
        exit 0
    fi
}

# 1. KSUWebUIStandalone
check_and_start "io.github.a13e300.ksuwebui" "io.github.a13e300.ksuwebui/.WebUIActivity" "id"

# 2. MMRL (Magisk Module Repo Loader)
check_and_start "com.dergoogler.mmrl" "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" "MOD_ID"

# 3. WebUI-X Portable
check_and_start "com.wxportal" "com.wxportal/.WebUIActivity" "id"

# --- Tidak ada WebUI manager: jalankan Full Proses via terminal ---
cat <<EOF

⚠️  Tidak ada WebUI Manager terdeteksi!
   Install salah satu aplikasi berikut untuk
   mendapatkan tampilan antarmuka grafis (WebUI):

   • KSUWebUIStandalone
   • MMRL (Magisk Module Repo Loader)
   • WebUI-X Portable

   Sementara itu, menjalankan Quick Action...
================================================

EOF

# FIX: Script yang dipanggil sebelumnya salah nama (ternak_core.sh vs ternak_core_v4.sh)
if [ -f "$MODDIR/ternak_core_v4.sh" ]; then
    sh "$MODDIR/ternak_core_v4.sh" full
else
    echo "[-] Error: Core script tidak ditemukan!"
fi

echo ""
echo "[✓] Selesai!"
