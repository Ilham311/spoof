#!/system/bin/sh
MODDIR="${0%/*}"
exec "$MODDIR/bin/envctl" regenerate
