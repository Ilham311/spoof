// ============================================================
// Ternak Device Changer v5.0 — Root companion
// Runs in dedicated root process (spawned by Zygisk framework).
// Handles Zygisk-hook IPC + UDS listener for ternakctl CLI.
// ============================================================
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <pthread.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <fstream>
#include <sstream>
#include <random>
#include <chrono>
#include <ctime>
#include <cstring>
#include <cstdio>

#define LOG_TAG "TernakCompanion"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ============================================================
// Protocols
// ============================================================
// Zygisk-hook ↔ companion
enum : uint8_t {
    CMD_CHECK_TARGET = 1,
    CMD_GET_IDENTITY = 2,
};
// ternakctl CLI ↔ companion (over @ternak.ctrl UDS)
enum : uint8_t {
    CLI_REGENERATE   = 10,
    CLI_STATUS       = 11,
    CLI_APPLY_BOOT   = 12,
    CLI_SET_MODE     = 13,
    CLI_SNAPSHOT     = 14,
    CLI_ROLLBACK     = 15,
    CLI_KEEP_ID      = 16,   // regenerate --keep-id
};

// ============================================================
// Paths
// ============================================================
static const char* MODDIR         = "/data/adb/modules/ternak_device_changer";
static const char* IDENTITY_FILE  = "/data/adb/modules/ternak_device_changer/identity.prop";
static const char* IDENTITY_BAK   = "/data/adb/modules/ternak_device_changer/identity.prop.bak";
static const char* MODE_FILE      = "/data/adb/modules/ternak_device_changer/identity.mode";
static const char* PERSISTENT_BIN = "/data/adb/modules/ternak_device_changer/persistent_id.bin";
static const char* HOOK_TARGETS   = "/data/adb/modules/ternak_device_changer/hook_targets.txt";
static const char* RESETPROP      = "/data/adb/modules/ternak_device_changer/bin/resetprop-rs";
static const char* POOL_FILE      = "/data/adb/modules/ternak_device_changer/pool.json";
static const char* UDS_NAME       = "ternak.ctrl";   // abstract UDS namespace

// ============================================================
// Embedded Pixel device pool
// ============================================================
struct PixelEntry {
    const char* model;
    const char* device;
    const char* product;         // ends with _beta if Canary channel
    const char* board;
    const char* hardware;
    int         sdk;
    const char* release;
    const char* id;              // build ID (e.g. BP1A.250705.006)
    const char* incremental;
    const char* security_patch;  // yyyy-mm-dd
};

static const std::vector<PixelEntry> PIXEL_POOL = {
    // Pixel 6 series
    {"Pixel 6",         "oriole",    "oriole_beta",    "oriole",    "oriole",    36, "16", "BP1A.250705.006", "13051201", "2026-07-05"},
    {"Pixel 6 Pro",     "raven",     "raven_beta",     "raven",     "raven",     36, "16", "BP1A.250705.006", "13051202", "2026-07-05"},
    {"Pixel 6a",        "bluejay",   "bluejay_beta",   "bluejay",   "bluejay",   36, "16", "BP1A.250705.006", "13051203", "2026-07-05"},
    // Pixel 7 series
    {"Pixel 7",         "panther",   "panther_beta",   "panther",   "panther",   36, "16", "BP1A.250705.006", "13051204", "2026-07-05"},
    {"Pixel 7 Pro",     "cheetah",   "cheetah_beta",   "cheetah",   "cheetah",   36, "16", "BP1A.250705.006", "13051205", "2026-07-05"},
    {"Pixel 7a",        "lynx",      "lynx_beta",      "lynx",      "lynx",      36, "16", "BP1A.250705.006", "13051206", "2026-07-05"},
    // Pixel 8 series
    {"Pixel 8",         "shiba",     "shiba_beta",     "shiba",     "shiba",     36, "16", "BP1A.250705.006", "13051207", "2026-07-05"},
    {"Pixel 8 Pro",     "husky",     "husky_beta",     "husky",     "husky",     36, "16", "BP1A.250705.006", "13051208", "2026-07-05"},
    {"Pixel 8a",        "akita",     "akita_beta",     "akita",     "akita",     36, "16", "BP1A.250705.006", "13051209", "2026-07-05"},
    // Pixel 9 series
    {"Pixel 9",         "tokay",     "tokay_beta",     "tokay",     "tokay",     36, "16", "BP1A.250705.006", "13051210", "2026-07-05"},
    {"Pixel 9 Pro",     "caiman",    "caiman_beta",    "caiman",    "caiman",    36, "16", "BP1A.250705.006", "13051211", "2026-07-05"},
    {"Pixel 9 Pro XL",  "komodo",    "komodo_beta",    "komodo",    "komodo",    36, "16", "BP1A.250705.006", "13051212", "2026-07-05"},
    {"Pixel 9 Pro Fold","comet",     "comet_beta",     "comet",     "comet",     36, "16", "BP1A.250705.006", "13051213", "2026-07-05"},
    {"Pixel 9a",        "tegu",      "tegu_beta",      "tegu",      "tegu",      36, "16", "BP1A.250705.006", "13051214", "2026-07-05"},
    // Pixel 10 series (Canary)
    {"Pixel 10",        "frankel",   "frankel_beta",   "frankel",   "frankel",   36, "16", "ZP11.260618.005", "15760424", "2026-07-05"},
    {"Pixel 10 Pro",    "blazer",    "blazer_beta",    "blazer",    "blazer",    36, "16", "ZP11.260618.005", "15760425", "2026-07-05"},
    {"Pixel 10 Pro XL", "mustang",   "mustang_beta",   "mustang",   "mustang",   36, "16", "ZP11.260618.005", "15760426", "2026-07-05"},
    {"Pixel 10 Pro Fold","rango",    "rango_beta",     "rango",     "rango",     36, "16", "ZP11.260618.005", "15760427", "2026-07-05"},
    // Fold + Tablet
    {"Pixel Fold",      "felix",     "felix_beta",     "felix",     "felix",     36, "16", "BP1A.250705.006", "13051215", "2026-07-05"},
    {"Pixel Tablet",    "tangorpro", "tangorpro_beta", "tangorpro", "tangorpro", 36, "16", "BP1A.250705.006", "13051216", "2026-07-05"},
};

// ============================================================
// Helpers
// ============================================================
static std::string random_hex(int bytes, bool upper = true) {
    std::random_device rd;
    std::mt19937_64 gen(rd() ^ (uint64_t)std::chrono::steady_clock::now()
                                    .time_since_epoch().count());
    std::uniform_int_distribution<int> dist(0, 15);
    const char* alph = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    std::string s;
    s.reserve(bytes * 2);
    for (int i = 0; i < bytes * 2; ++i) s.push_back(alph[dist(gen)]);
    return s;
}

static bool atomic_write(const std::string& path, const std::string& data) {
    std::string tmp = path + ".tmp";
    int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return false;
    ssize_t w = ::write(fd, data.data(), data.size());
    ::fsync(fd);
    ::close(fd);
    if (w != (ssize_t)data.size()) { ::unlink(tmp.c_str()); return false; }
    return ::rename(tmp.c_str(), path.c_str()) == 0;
}

static std::string read_file(const std::string& path) {
    std::ifstream f(path);
    if (!f) return "";
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static std::string trim(std::string s) {
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' ||
                          s.back() == ' '  || s.back() == '\t'))
        s.pop_back();
    size_t st = s.find_first_not_of(" \t");
    if (st != std::string::npos) s = s.substr(st);
    return s;
}

static void run_bin(const char* path, std::vector<const char*> argv) {
    pid_t pid = fork();
    if (pid == 0) {
        argv.push_back(nullptr);
        execv(path, const_cast<char* const*>(argv.data()));
        _exit(127);
    } else if (pid > 0) waitpid(pid, nullptr, 0);
}

// ============================================================
// Identity generation
// ============================================================
struct Identity {
    std::map<std::string, std::string> kv;

    std::string serialize() const {
        static const std::vector<std::string> order = {
            "BRAND", "MANUFACTURER", "MODEL", "DEVICE", "PRODUCT",
            "BOARD", "HARDWARE", "FINGERPRINT", "ID", "DISPLAY", "DESCRIPTION",
            "BOOTLOADER", "HOST", "USER", "TYPE", "TAGS",
            "TIME", "INCREMENTAL", "RELEASE", "SDK_INT", "DEVICE_INITIAL_SDK_INT",
            "SECURITY_PATCH", "CODENAME", "SERIAL", "RADIO", "ANDROID_ID",
        };
        std::string out;
        for (const auto& k : order) {
            auto it = kv.find(k);
            if (it != kv.end()) out += k + "=" + it->second + "\n";
        }
        return out;
    }
};

static std::vector<std::map<std::string, std::string>> load_json_pool() {
    std::vector<std::map<std::string, std::string>> pool;
    std::string content = read_file(POOL_FILE);
    if (content.empty()) return pool;

    // Extremely lightweight, non-validating JSON parsing intended for simple array of objects
    // Format expected: [{ "KEY": "VALUE", ... }, { ... }]
    size_t pos = 0;
    while ((pos = content.find('{', pos)) != std::string::npos) {
        size_t end_obj = content.find('}', pos);
        if (end_obj == std::string::npos) break;

        std::map<std::string, std::string> entry;
        size_t key_pos = pos;
        while ((key_pos = content.find('"', key_pos)) != std::string::npos && key_pos < end_obj) {
            size_t key_end = content.find('"', key_pos + 1);
            if (key_end == std::string::npos || key_end > end_obj) break;
            std::string key = content.substr(key_pos + 1, key_end - key_pos - 1);

            size_t colon_pos = content.find(':', key_end);
            if (colon_pos == std::string::npos || colon_pos > end_obj) break;

            size_t val_pos = content.find('"', colon_pos);
            if (val_pos == std::string::npos || val_pos > end_obj) break;
            size_t val_end = content.find('"', val_pos + 1);
            if (val_end == std::string::npos || val_end > end_obj) break;
            std::string val = content.substr(val_pos + 1, val_end - val_pos - 1);

            entry[key] = val;
            key_pos = val_end + 1;
        }
        if (!entry.empty()) pool.push_back(entry);
        pos = end_obj + 1;
    }
    return pool;
}

static Identity generate_identity(bool keep_id) {
    std::random_device rd;
    std::mt19937 gen(rd());
    Identity id;

    // Default static fields
    id.kv["BOOTLOADER"]             = "unknown";
    id.kv["HOST"]                   = "abfarm-release";
    id.kv["USER"]                   = "android-build";
    id.kv["TYPE"]                   = "user";
    id.kv["TAGS"]                   = "release-keys";
    id.kv["CODENAME"]               = "REL";
    id.kv["TIME"] = std::to_string(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    // 1. Try to load from pool.json
    auto json_pool = load_json_pool();
    if (!json_pool.empty()) {
        std::uniform_int_distribution<size_t> pick(0, json_pool.size() - 1);
        auto& p = json_pool[pick(gen)];
        for (const auto& [k, v] : p) {
            id.kv[k] = v;
        }

        // Fill missing essentials if JSON didn't provide them
        if (id.kv.find("DEVICE_INITIAL_SDK_INT") == id.kv.end() && id.kv.find("SDK_INT") != id.kv.end())
            id.kv["DEVICE_INITIAL_SDK_INT"] = id.kv["SDK_INT"];
        if (id.kv.find("DISPLAY") == id.kv.end()) id.kv["DISPLAY"] = id.kv["ID"];
        if (id.kv.find("DESCRIPTION") == id.kv.end()) {
            char desc[512];
            snprintf(desc, sizeof(desc), "%s-user %s %s %s release-keys",
                     id.kv["PRODUCT"].c_str(), id.kv["RELEASE"].c_str(),
                     id.kv["ID"].c_str(), id.kv["INCREMENTAL"].c_str());
            id.kv["DESCRIPTION"] = desc;
        }
    } else {
        // 2. Fallback to embedded Pixel pool
        std::uniform_int_distribution<size_t> pick(0, PIXEL_POOL.size() - 1);
        const PixelEntry& p = PIXEL_POOL[pick(gen)];

        id.kv["BRAND"]                  = "google";
        id.kv["MANUFACTURER"]           = "Google";
        id.kv["MODEL"]                  = p.model;
        id.kv["DEVICE"]                 = p.device;
        id.kv["PRODUCT"]                = p.product;
        id.kv["BOARD"]                  = p.board;
        id.kv["HARDWARE"]               = p.hardware;
        id.kv["ID"]                     = p.id;
        id.kv["INCREMENTAL"]            = p.incremental;
        id.kv["RELEASE"]                = p.release;
        id.kv["SDK_INT"]                = std::to_string(p.sdk);
        id.kv["DEVICE_INITIAL_SDK_INT"] = std::to_string(p.sdk);
        id.kv["SECURITY_PATCH"]         = p.security_patch;

        std::string channel = std::string(p.product).find("_beta") != std::string::npos ? "CANARY" : "REL";
        char fp[512];
        snprintf(fp, sizeof(fp), "google/%s/%s:%s/%s/%s:user/release-keys",
                 p.product, p.device, channel.c_str(), p.id, p.incremental);
        id.kv["FINGERPRINT"] = fp;

        id.kv["DISPLAY"] = p.id;
        char desc[512];
        snprintf(desc, sizeof(desc), "%s-user %s %s %s release-keys",
                 p.product, p.release, p.id, p.incremental);
        id.kv["DESCRIPTION"] = desc;

        std::time_t now = std::time(nullptr);
        struct tm lt;
        localtime_r(&now, &lt);
        char datebuf[16];
        strftime(datebuf, sizeof(datebuf), "%y%m%d", &lt);
        char rad[128];
        snprintf(rad, sizeof(rad), "g5300q-%s-%s-B-%s", datebuf, datebuf, p.incremental);
        id.kv["RADIO"] = rad;
    }

    // SERIAL & ANDROID_ID (Persistent logic remains the same)
    if (keep_id) {
        std::istringstream iss(read_file(PERSISTENT_BIN));
        std::string line;
        while (std::getline(iss, line)) {
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string k = line.substr(0, eq), v = line.substr(eq + 1);
            if (k == "SERIAL" || k == "ANDROID_ID") id.kv[k] = trim(v);
        }
    }
    if (id.kv.find("SERIAL")     == id.kv.end()) id.kv["SERIAL"]     = random_hex(8, true);
    if (id.kv.find("ANDROID_ID") == id.kv.end()) id.kv["ANDROID_ID"] = random_hex(8, false);

    // Update persistent snapshot
    std::string snap = "SERIAL=" + id.kv["SERIAL"] + "\nANDROID_ID=" + id.kv["ANDROID_ID"] + "\n";
    atomic_write(PERSISTENT_BIN, snap);

    return id;
}

// ============================================================
// Hook target check forward declaration
// ============================================================
static std::set<std::string> load_targets();

// ============================================================
// Apply native prop + settings + kill gms/vending
// ============================================================
static void apply_native(const Identity& id) {
    auto get = [&](const std::string& k) -> std::string {
        auto it = id.kv.find(k);
        return it != id.kv.end() ? it->second : "";
    };

    struct Rp { const char* key; std::string val; };
    std::vector<Rp> rp = {
        {"ro.serialno",              get("SERIAL")},
        {"ro.boot.serialno",         get("SERIAL")},
        {"ro.build.display.id",      get("DISPLAY")},
        {"ro.build.description",     get("DESCRIPTION")},
        {"gsm.version.baseband",     get("RADIO")},
        {"ro.build.expect.baseband", get("RADIO")},
    };

    if (::access(RESETPROP, X_OK) == 0) {
        for (const auto& r : rp) {
            if (r.val.empty()) continue;
            run_bin(RESETPROP, {"resetprop-rs", "-n", r.key, r.val.c_str()});
        }
    } else {
        LOGE("resetprop-rs missing at %s", RESETPROP);
    }

    // settings put device_name (global + system)
    std::string model = get("MODEL");
    if (!model.empty()) {
        run_bin("/system/bin/settings",
                {"settings", "put", "global", "device_name", model.c_str()});
        run_bin("/system/bin/settings",
                {"settings", "put", "system", "device_name", model.c_str()});
    }

    // settings put secure android_id
    std::string aid = get("ANDROID_ID");
    if (!aid.empty()) {
        run_bin("/system/bin/settings",
                {"settings", "put", "secure", "android_id", aid.c_str()});
    }

    // am force-stop and pm clear for all targets in hook_targets.txt
    std::set<std::string> targets = load_targets();
    for (const std::string& pkg : targets) {
        run_bin("/system/bin/am", {"am", "force-stop", pkg.c_str()});
        run_bin("/system/bin/pm", {"pm", "clear", pkg.c_str()});
    }
}

// ============================================================
// REGENERATE flow
// ============================================================
static std::string do_regenerate(bool keep_id) {
    std::string mode = trim(read_file(MODE_FILE));
    if (mode == "locked") {
        return "LOCKED: identity locked. Run `ternakctl set-mode fresh` to unlock.\n";
    }
    if (mode == "persistent") keep_id = true;

    // Backup existing
    std::string old = read_file(IDENTITY_FILE);
    if (!old.empty()) atomic_write(IDENTITY_BAK, old);

    Identity id = generate_identity(keep_id);
    if (!atomic_write(IDENTITY_FILE, id.serialize())) {
        return "ERROR: failed to write identity.prop\n";
    }

    apply_native(id);

    std::string out = "OK\n";
    out += "  MODEL       : " + id.kv["MODEL"]       + "\n";
    out += "  DEVICE      : " + id.kv["DEVICE"]      + "\n";
    out += "  FINGERPRINT : " + id.kv["FINGERPRINT"] + "\n";
    out += "  SERIAL      : " + id.kv["SERIAL"]     + "\n";
    out += "  ANDROID_ID  : " + id.kv["ANDROID_ID"]  + "\n";
    out += "  SEC PATCH   : " + id.kv["SECURITY_PATCH"] + "\n";
    return out;
}

static Identity load_identity() {
    Identity id;
    std::istringstream iss(read_file(IDENTITY_FILE));
    std::string line;
    while (std::getline(iss, line)) {
        if (line.empty() || line[0] == '#') continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        id.kv[line.substr(0, eq)] = line.substr(eq + 1);
    }
    return id;
}

// ============================================================
// Hook target check (called by Zygisk-side CMD_CHECK_TARGET)
// ============================================================
static std::set<std::string> load_targets() {
    std::set<std::string> s;
    std::ifstream f(HOOK_TARGETS);
    std::string line;
    while (std::getline(f, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        s.insert(line);
    }
    return s;
}

static bool is_safe_name(const std::string& name) {
    if (name.empty()) return false;
    for (char c : name) {
        if (!isalnum(c) && c != '_' && c != '-') return false;
    }
    return true;
}

// ============================================================
// UDS listener thread (for ternakctl CLI)
// ============================================================
static void handle_cli(int client) {
    uint8_t cmd = 0;
    if (::read(client, &cmd, 1) != 1) { ::close(client); return; }

    std::string reply;
    switch (cmd) {
        case CLI_REGENERATE: reply = do_regenerate(false); break;
        case CLI_KEEP_ID:    reply = do_regenerate(true);  break;

        case CLI_APPLY_BOOT: {
            Identity id = load_identity();
            if (id.kv.empty()) { reply = "ERROR: no identity.prop\n"; break; }
            apply_native(id);
            reply = "OK: native prop re-applied at boot\n";
            break;
        }

        case CLI_STATUS: {
            std::string data = read_file(IDENTITY_FILE);
            reply = data.empty() ? "no identity yet\n" : data;
            break;
        }

        case CLI_SET_MODE: {
            uint32_t len = 0;
            if (::read(client, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 32) {
                reply = "bad len\n"; break;
            }
            std::string m(len, 0);
            ::read(client, m.data(), len);
            atomic_write(MODE_FILE, m + "\n");
            reply = "OK: mode=" + m + "\n";
            break;
        }

        case CLI_SNAPSHOT: {
            uint32_t len = 0;
            ::read(client, &len, sizeof(len));
            std::string name(len, 0);
            if (len) ::read(client, name.data(), len);
            if (name.empty()) name = "default";
            if (!is_safe_name(name)) { reply = "ERROR: invalid snapshot name\n"; break; }
            std::string dst = std::string(MODDIR) + "/identity.snap." + name;
            std::string cur = read_file(IDENTITY_FILE);
            if (cur.empty()) reply = "no identity to snapshot\n";
            else { atomic_write(dst, cur); reply = "OK: snapshot -> " + dst + "\n"; }
            break;
        }

        case CLI_ROLLBACK: {
            uint32_t len = 0;
            ::read(client, &len, sizeof(len));
            std::string name(len, 0);
            if (len) ::read(client, name.data(), len);
            std::string src = IDENTITY_BAK;
            if (!name.empty()) {
                if (!is_safe_name(name)) { reply = "ERROR: invalid snapshot name\n"; break; }
                src = std::string(MODDIR) + "/identity.snap." + name;
            }
            std::string data = read_file(src);
            if (data.empty()) { reply = "no such snapshot\n"; break; }
            atomic_write(IDENTITY_FILE, data);
            apply_native(load_identity());
            reply = "OK: rollback from " + src + "\n";
            break;
        }

        default:
            reply = "unknown cmd\n";
    }

    uint32_t rlen = (uint32_t)reply.size();
    ::write(client, &rlen, sizeof(rlen));
    ::write(client, reply.data(), rlen);
    ::close(client);
}

static void* uds_listener(void*) {
    int sock = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) { LOGE("socket() failed"); return nullptr; }

    struct sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';   // abstract namespace
    strncpy(addr.sun_path + 1, UDS_NAME, sizeof(addr.sun_path) - 2);
    socklen_t alen = sizeof(sa_family_t) + 1 + strlen(UDS_NAME);

    if (::bind(sock, (struct sockaddr*)&addr, alen) < 0) {
        LOGE("bind @%s failed: %s", UDS_NAME, strerror(errno));
        ::close(sock);
        return nullptr;
    }
    if (::listen(sock, 8) < 0) {
        LOGE("listen failed: %s", strerror(errno));
        ::close(sock);
        return nullptr;
    }
    LOGI("UDS listener started @%s", UDS_NAME);

    while (true) {
        int client = ::accept(sock, nullptr, nullptr);
        if (client < 0) { if (errno == EINTR) continue; break; }

        struct ucred cred;
        socklen_t cr_len = sizeof(cred);
        if (::getsockopt(client, SOL_SOCKET, SO_PEERCRED, &cred, &cr_len) < 0) {
            ::close(client);
            continue;
        }
        if (cred.uid != 0 && cred.uid != 2000) {
            LOGE("Unauthorized UDS connection from UID %d", cred.uid);
            ::close(client);
            continue;
        }

        handle_cli(client);
    }
    ::close(sock);
    return nullptr;
}

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static void start_uds_thread_once() {
    pthread_t th;
    if (pthread_create(&th, nullptr, uds_listener, nullptr) == 0) {
        pthread_detach(th);
    }
}

// ============================================================
// Zygisk companion entry (framework calls for each hook client)
// ============================================================
extern "C" __attribute__((visibility("default"))) void ternak_companion_entry(int client) {
    // Lazy-start UDS listener on first companion request
    pthread_once(&g_once, start_uds_thread_once);

    while (true) {
        uint8_t cmd = 0;
        if (::read(client, &cmd, 1) != 1) break;

        if (cmd == CMD_CHECK_TARGET) {
            uint32_t len = 0;
            if (::read(client, &len, sizeof(len)) != sizeof(len) || len > 512) break;
            std::string pkg(len, 0);
            if (::read(client, pkg.data(), len) != (ssize_t)len) break;

            static std::set<std::string> targets = load_targets();
            uint8_t r = targets.count(pkg) ? 1 : 0;
            ::write(client, &r, 1);
        } else if (cmd == CMD_GET_IDENTITY) {
            std::string data = read_file(IDENTITY_FILE);
            uint32_t len = (uint32_t)data.size();
            ::write(client, &len, sizeof(len));
            if (len) ::write(client, data.data(), len);
        } else {
            break;
        }
    }
    ::close(client);
}
