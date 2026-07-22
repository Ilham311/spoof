#!/system/bin/sh

# ============================================================
# Ternak Device Changer - Action Script
# Mendeteksi WebUI manager yang terinstall dan membukanya.
# Jika tidak ada, jalankan Full Proses via terminal.
# ============================================================

MODDIR=${0%/*}
MODULE_ID="ternak_device_changer"

# --- Coba buka WebUI lewat manager yang tersedia ---

# 1. KSUWebUIStandalone
if pm list packages 2>/dev/null | grep -q "io.github.a13e300.ksuwebui"; then
    echo "- Membuka WebUI di KSUWebUIStandalone..."
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODULE_ID" >/dev/null 2>&1
    exit 0
fi

# 2. MMRL (Magisk Module Repo Loader)
if pm list packages 2>/dev/null | grep -q "com.dergoogler.mmrl"; then
    echo "- Membuka WebUI di MMRL..."
    am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" -e MOD_ID "$MODULE_ID" >/dev/null 2>&1
    exit 0
fi

# 3. WebUI-X Portable
if pm list packages 2>/dev/null | grep -q "com.wxportal"; then
    echo "- Membuka WebUI di WebUI-X..."
    am start -n "com.wxportal/.WebUIActivity" -e id "$MODULE_ID" >/dev/null 2>&1
    exit 0
fi

# --- Tidak ada WebUI manager: jalankan Full Proses via terminal ---
echo ""
echo "⚠️  Tidak ada WebUI Manager terdeteksi!"
echo "   Install salah satu aplikasi berikut untuk"
echo "   mendapatkan tampilan antarmuka grafis (WebUI):"
echo ""
echo "   • KSUWebUIStandalone"
echo "   • MMRL (Magisk Module Repo Loader)"
echo "   • WebUI-X Portable"
echo ""
echo "   Sementara itu, menjalankan Quick Action..."
echo "================================================"
echo ""

sh "$MODDIR/ternak_core_v4.sh" full

echo ""
echo "[✓] Selesai!"
