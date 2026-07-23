#!/system/bin/sh
# Dynamic Environment v5.1 — action trigger
# Tap Action → generate FRESH identity (rotate device + rotate SERIAL/ANDROID_ID/GAID/GSF_ID)
# Kalau mau rotate device TAPI keep identity id, jalankan manual:
#   su -c /data/adb/modules/dynamic_env_module/bin/envctl regenerate --keep-id
MODDIR="${0%/*}"
exec "$MODDIR/bin/envctl" regenerate
