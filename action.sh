#!/system/bin/sh
# Ternak v5.0 — action trigger
# Semua logic ada di companion.cpp; shell cuma exec CLI trigger.
MODDIR="${0%/*}"
"$MODDIR/bin/ternakctl" regenerate --keep-id
reboot
