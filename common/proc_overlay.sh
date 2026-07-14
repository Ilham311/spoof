#!/system/bin/sh
# common/proc_overlay.sh — /proc mount-bind (opt-in only)

PROC_OVERLAY_FLAG="${STATE_DIR}/proc_overlay_enabled"

proc_overlay_enabled() {
    [ -f "$PROC_OVERLAY_FLAG" ]
}

apply_proc_overlay() {
    proc_overlay_enabled || { log "[proc] overlay disabled (opt-in required)"; return 0; }
    local SIG="$1" TMPFS="${DATA_DIR}/proc_overlay"
    [ -n "$SIG" ] || SIG="gs201"

    mkdir -p "$TMPFS" 2>/dev/null
    chmod 700 "$TMPFS" 2>/dev/null

    # Build fake /proc/cpuinfo matching persona
    cat > "${TMPFS}/cpuinfo" <<EOF
processor       : 0
BogoMIPS        : 52.00
Features        : fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 asimdfhm dit uscat ilrcpc flagm ssbs sb paca pacg dcpodp flagm2 frint
CPU implementer : 0x41
CPU architecture: 8
CPU variant     : 0x2
CPU part        : 0xd47
CPU revision    : 0

Hardware        : ${SIG}
EOF
    chmod 644 "${TMPFS}/cpuinfo" 2>/dev/null

    mount --bind "${TMPFS}/cpuinfo" /proc/cpuinfo 2>/dev/null && \
        log "[proc] /proc/cpuinfo bind-mounted (sig=${SIG})" || \
        log "[proc] bind-mount failed (need mount ns support)"
}

unapply_proc_overlay() {
    umount /proc/cpuinfo 2>/dev/null && log "[proc] /proc/cpuinfo unmounted"
}
