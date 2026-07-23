// envctl - Tiny CLI for Dynamic Environment
// Connects to abstract UDS @env.ctrl, sends command, prints reply.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <errno.h>

enum {
    CLI_REGENERATE = 10,
    CLI_STATUS     = 11,
    CLI_APPLY_BOOT = 12,
    CLI_SET_MODE   = 13,
    CLI_SNAPSHOT   = 14,
    CLI_ROLLBACK   = 15,
    CLI_KEEP_ID    = 16,
};

static const char* UDS_NAME = "env.ctrl";

static int connect_uds(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';
    strncpy(addr.sun_path + 1, UDS_NAME, sizeof(addr.sun_path) - 2);
    socklen_t alen = sizeof(sa_family_t) + 1 + strlen(UDS_NAME);
    if (connect(fd, (struct sockaddr*)&addr, alen) < 0) {
        fprintf(stderr, "envctl: connect @%s failed: %s\n",
                UDS_NAME, strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

static int send_all(int fd, const void* buf, size_t len) {
    const char* p = (const char*)buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return -1;
        p += n; len -= (size_t)n;
    }
    return 0;
}

static int recv_all(int fd, void* buf, size_t len) {
    char* p = (char*)buf;
    while (len > 0) {
        ssize_t n = read(fd, p, len);
        if (n <= 0) return -1;
        p += n; len -= (size_t)n;
    }
    return 0;
}

static int send_cmd(uint8_t cmd, const char* arg) {
    int fd = connect_uds();
    if (fd < 0) return 1;
    if (send_all(fd, &cmd, 1) < 0) { close(fd); return 1; }
    if (arg) {
        uint32_t len = (uint32_t)strlen(arg);
        if (send_all(fd, &len, sizeof(len)) < 0) { close(fd); return 1; }
        if (len > 0 && send_all(fd, arg, len) < 0) { close(fd); return 1; }
    }
    uint32_t rlen = 0;
    if (recv_all(fd, &rlen, sizeof(rlen)) < 0 || rlen > 65536) {
        close(fd); return 1;
    }
    char* buf = (char*)malloc(rlen + 1);
    if (!buf) { close(fd); return 1; }
    if (rlen > 0 && recv_all(fd, buf, rlen) < 0) {
        free(buf); close(fd); return 1;
    }
    buf[rlen] = '\0';
    fputs(buf, stdout);
    free(buf); close(fd);
    return 0;
}

static void usage(void) {
    fprintf(stderr,
        "Usage: envctl <command> [args]\n"
        "Commands:\n"
        "  regenerate [--keep-id]     Generate fresh identity (or keep SERIAL/ANDROID_ID/GAID/GSF_ID)\n"
        "  status                     Show current identity.prop\n"
        "  apply-boot                 Re-apply native prop (called by service.sh at boot)\n"
        "  set-mode <fresh|persistent|locked>\n"
        "  snapshot [name]            Save current identity as named snapshot\n"
        "  rollback [name]            Restore from snapshot (default: .bak)\n");
}

int main(int argc, char** argv) {
    if (argc < 2) { usage(); return 1; }
    const char* cmd = argv[1];

    if (strcmp(cmd, "regenerate") == 0) {
        int keep = (argc > 2 && strcmp(argv[2], "--keep-id") == 0);
        return send_cmd(keep ? CLI_KEEP_ID : CLI_REGENERATE, NULL);
    } else if (strcmp(cmd, "status") == 0) {
        return send_cmd(CLI_STATUS, NULL);
    } else if (strcmp(cmd, "apply-boot") == 0) {
        return send_cmd(CLI_APPLY_BOOT, NULL);
    } else if (strcmp(cmd, "set-mode") == 0) {
        if (argc < 3) { usage(); return 1; }
        return send_cmd(CLI_SET_MODE, argv[2]);
    } else if (strcmp(cmd, "snapshot") == 0) {
        return send_cmd(CLI_SNAPSHOT, argc > 2 ? argv[2] : "");
    } else if (strcmp(cmd, "rollback") == 0) {
        return send_cmd(CLI_ROLLBACK, argc > 2 ? argv[2] : "");
    }
    usage();
    return 1;
}
