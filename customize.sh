#!/system/bin/sh
SKIPUNZIP=0

ui_print() { echo "$1"; }

set_permissions() {
    ui_print "- Setting permissions for Ternak v4.15"
    set_perm_recursive "$MODPATH/common" 0 0 0755 0755
    set_perm "$MODPATH/system/bin/ternak" 0 2000 0755
    set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
    set_perm "$MODPATH/service.sh" 0 0 0755
    ui_print "- Permissions set"
}

ui_print " "
ui_print "************************************"
ui_print "  Ternak Device Changer v4.15.0     "
ui_print "  DSL-Integrated + Pixel 7 Pro      "
ui_print "************************************"
ui_print " "
ui_print "- Installing module files..."
ui_print "- Persistent state at /data/adb/ternak/"
ui_print "- Reboot required to activate persona"
