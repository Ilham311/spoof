// ============================================================
// ternakctl.c — Ternak Device Changer v5.0 CLI trigger
// Connects to abstract UDS @ternak.ctrl (companion), sends command,
// prints reply.
// ============================================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>

#define UDS_NAME "ternak.ctrl"

enum {
    CLI_REGENERATE = 10,
    CLI_STATUS     = 11,
    CLI_APPLY_BOOT = 12,
    CLI_SET_MODE   = 13,
    CLI_SNAPSHOT   = 14,
    CLI_ROLLBACK   = 15,
    CLI_KEEP_ID    = 16,
};

static int connect_companion(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';   // abstract namespace
    strncpy(addr.sun_path + 1, UDS_NAME, sizeof(addr.sun_path) - 2);
    socklen_t alen = sizeof(sa_family_t) + 1 + strlen(UDS_NAME);

    if (connect(fd, (struct sockaddr*)&addr, alen) < 0) {
        fprintf(stderr, "! Cannot connect to @%s: %s\n", UDS_NAME, strerror(errno));
        fprintf(stderr, "! Is Zygisk enabled and module loaded? Try reboot.\n");
        close(fd);
        return -1;
    }
    return fd;
}

static int read_and_print_reply(int fd) {
    uint32_t rlen = 0;
    if (read(fd, &rlen, sizeof(rlen)) != sizeof(rlen)) {
        fprintf(stderr, "! No reply\n");
        return 1;
    }
    if (rlen > 65536) rlen = 65536;
    char* buf = (char*)malloc(rlen + 1);
    if (!buf) return 1;
    ssize_t got = 0;
    while ((size_t)got < rlen) {
        ssize_t n = read(fd, buf + got, rlen - got);
        if (n <= 0) break;
        got += n;
    }
    buf[got] = 0;
    fwrite(buf, 1, got, stdout);
    free(buf);
    return 0;
}

static int send_simple(uint8_t cmd) {
    int fd = connect_companion();
    if (fd < 0) return 1;
    write(fd, &cmd, 1);
    int r = read_and_print_reply(fd);
    close(fd);
    return r;
}

static int send_with_arg(uint8_t cmd, const char* arg) {
    int fd = connect_companion();
    if (fd < 0) return 1;
    write(fd, &cmd, 1);
    uint32_t len = arg ? (uint32_t)strlen(arg) : 0;
    write(fd, &len, sizeof(len));
    if (len) write(fd, arg, len);
    int r = read_and_print_reply(fd);
    close(fd);
    return r;
}

static void usage(const char* prog) {
    fprintf(stderr,
        "Usage: %s <command> [args]\n\n"
        "Commands:\n"
        "  regenerate               Generate fresh identity dari embedded pool\n"
        "  regenerate --keep-id     Rotate device, keep SERIAL + ANDROID_ID\n"
        "  status                   Print current identity.prop\n"
        "  apply-boot               Re-apply native prop (called by service.sh)\n"
        "  set-mode <mode>          Set mode: fresh | persistent | locked\n"
        "  snapshot [name]          Save current identity to identity.snap.<name>\n"
        "  rollback [name]          Restore from snapshot (default: identity.prop.bak)\n",
        prog);
}

int main(int argc, char** argv) {
    if (argc < 2) { usage(argv[0]); return 1; }
    const char* cmd = argv[1];

    if (!strcmp(cmd, "regenerate")) {
        if (argc >= 3 && !strcmp(argv[2], "--keep-id")) return send_simple(CLI_KEEP_ID);
        return send_simple(CLI_REGENERATE);
    }
    if (!strcmp(cmd, "status"))     return send_simple(CLI_STATUS);
    if (!strcmp(cmd, "apply-boot")) return send_simple(CLI_APPLY_BOOT);
    if (!strcmp(cmd, "set-mode")) {
        if (argc < 3) { fprintf(stderr, "! set-mode needs argument\n"); return 1; }
        return send_with_arg(CLI_SET_MODE, argv[2]);
    }
    if (!strcmp(cmd, "snapshot")) return send_with_arg(CLI_SNAPSHOT, argc >= 3 ? argv[2] : "");
    if (!strcmp(cmd, "rollback")) return send_with_arg(CLI_ROLLBACK, argc >= 3 ? argv[2] : "");

    usage(argv[0]);
    return 1;
}
