// ============================================================
// Dynamic Environment v5.1 — Root companion (production fix)
// Runs in dedicated root process (spawned by Zygisk framework).
// Handles Zygisk-hook IPC + UDS listener for envctl CLI.
//
// v5.1 changes vs v1-FIX-release:
//   [P1] hook_targets.txt hot-reload via stat().st_mtime
//   [P1] FINGERPRINT fallback uses real BRAND (not hardcoded "google/")
//   [P1] RADIO fallback per-brand (google/samsung/qcom-vendor)
// ============================================================
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>       // + P1: for stat/st_mtime
#include <sys/wait.h>
#include <sys/types.h>
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
#include <cstdlib>
#include <cctype>            // + P1: for tolower
#include <algorithm>         // + P1: for transform

#define LOG_TAG "EnvCompanion"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ============================================================
// Protocols
// ============================================================
enum : uint8_t { CMD_CHECK_TARGET = 1, CMD_GET_IDENTITY = 2, };
enum : uint8_t {
    CLI_REGENERATE = 10, CLI_STATUS = 11, CLI_APPLY_BOOT = 12,
    CLI_SET_MODE   = 13, CLI_SNAPSHOT = 14, CLI_ROLLBACK   = 15,
    CLI_KEEP_ID    = 16,
};

// ============================================================
// Paths
// ============================================================
static const char* MODDIR         = "/data/adb/modules/dynamic_env_module";
static const char* IDENTITY_FILE  = "/data/adb/modules/dynamic_env_module/identity.prop";
static const char* IDENTITY_BAK   = "/data/adb/modules/dynamic_env_module/identity.prop.bak";
static const char* MODE_FILE      = "/data/adb/modules/dynamic_env_module/identity.mode";
static const char* PERSISTENT_BIN = "/data/adb/modules/dynamic_env_module/persistent_id.bin";
static const char* HOOK_TARGETS   = "/data/adb/modules/dynamic_env_module/hook_targets.txt";
static const char* RESETPROP      = "/data/adb/modules/dynamic_env_module/bin/resetprop-rs";
static const char* POOL_FILE      = "/data/adb/modules/dynamic_env_module/pool.json";
static const char* UDS_NAME       = "env.ctrl";

// ============================================================
// Embedded Pixel device pool (fallback kalau pool.json absent)
// ============================================================
struct PixelEntry {
    const char* model; const char* device; const char* product;
    const char* board; const char* hardware; int sdk;
    const char* release; const char* id; const char* incremental;
    const char* security_patch;
};

static const std::vector<PixelEntry> PIXEL_POOL = {
    {"Pixel 6",         "oriole",    "oriole_beta",    "oriole",    "oriole",    36, "16", "BP1A.250705.006", "13051201", "2026-07-05"},
    {"Pixel 6 Pro",     "raven",     "raven_beta",     "raven",     "raven",     36, "16", "BP1A.250705.006", "13051202", "2026-07-05"},
    {"Pixel 6a",        "bluejay",   "bluejay_beta",   "bluejay",   "bluejay",   36, "16", "BP1A.250705.006", "13051203", "2026-07-05"},
    {"Pixel 7",         "panther",   "panther_beta",   "panther",   "panther",   36, "16", "BP1A.250705.006", "13051204", "2026-07-05"},
    {"Pixel 7 Pro",     "cheetah",   "cheetah_beta",   "cheetah",   "cheetah",   36, "16", "BP1A.250705.006", "13051205", "2026-07-05"},
    {"Pixel 7a",        "lynx",      "lynx_beta",      "lynx",      "lynx",      36, "16", "BP1A.250705.006", "13051206", "2026-07-05"},
    {"Pixel 8",         "shiba",     "shiba_beta",     "shiba",     "shiba",     36, "16", "BP1A.250705.006", "13051207", "2026-07-05"},
    {"Pixel 8 Pro",     "husky",     "husky_beta",     "husky",     "husky",     36, "16", "BP1A.250705.006", "13051208", "2026-07-05"},
    {"Pixel 8a",        "akita",     "akita_beta",     "akita",     "akita",     36, "16", "BP1A.250705.006", "13051209", "2026-07-05"},
    {"Pixel 9",         "tokay",     "tokay_beta",     "tokay",     "tokay",     36, "16", "BP1A.250705.006", "13051210", "2026-07-05"},
    {"Pixel 9 Pro",     "caiman",    "caiman_beta",    "caiman",    "caiman",    36, "16", "BP1A.250705.006", "13051211", "2026-07-05"},
    {"Pixel 9 Pro XL",  "komodo",    "komodo_beta",    "komodo",    "komodo",    36, "16", "BP1A.250705.006", "13051212", "2026-07-05"},
    {"Pixel 9 Pro Fold","comet",     "comet_beta",     "comet",     "comet",     36, "16", "BP1A.250705.006", "13051213", "2026-07-05"},
    {"Pixel 9a",        "tegu",      "tegu_beta",      "tegu",      "tegu",      36, "16", "BP1A.250705.006", "13051214", "2026-07-05"},
    {"Pixel 10",        "frankel",   "frankel_beta",   "frankel",   "frankel",   36, "16", "ZP11.260618.005", "15760424", "2026-07-05"},
    {"Pixel 10 Pro",    "blazer",    "blazer_beta",    "blazer",    "blazer",    36, "16", "ZP11.260618.005", "15760425", "2026-07-05"},
    {"Pixel 10 Pro XL", "mustang",   "mustang_beta",   "mustang",   "mustang",   36, "16", "ZP11.260618.005", "15760426", "2026-07-05"},
    {"Pixel 10 Pro Fold","rango",    "rango_beta",     "rango",     "rango",     36, "16", "ZP11.260618.005", "15760427", "2026-07-05"},
    {"Pixel Fold",      "felix",     "felix_beta",     "felix",     "felix",     36, "16", "BP1A.250705.006", "13051215", "2026-07-05"},
    {"Pixel Tablet",    "tangorpro", "tangorpro_beta", "tangorpro", "tangorpro", 36, "16", "BP1A.250705.006", "13051216", "2026-07-05"},
};

// ============================================================
// Helpers
// ============================================================
static std::string to_lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    return s;
}

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

static std::string random_uuid() {
    std::string s = random_hex(16, false);
    std::string out = s.substr(0, 8) + "-" + s.substr(8, 4) + "-4" + s.substr(12, 3) + "-";
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<int> dist(0, 3);
    const char* y_chars = "89ab";
    out += y_chars[dist(gen)];
    out += s.substr(15, 3) + "-" + random_hex(6, false);
    return out;
}

static bool atomic_write(const std::string& path, const std::string& data) {
    std::string tmp = path + ".tmp";
    int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return false;
    ssize_t w = ::write(fd, data.data(), data.size());
    ::fsync(fd); ::close(fd);
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
// [P1] hook_targets.txt hot-reload with mtime-based cache
// ============================================================
static std::set<std::string> load_targets_from_disk() {
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

static pthread_mutex_t g_targets_mu = PTHREAD_MUTEX_INITIALIZER;
static std::set<std::string> g_targets_cache;
static time_t g_targets_mtime = 0;

static std::set<std::string> get_targets_cached() {
    struct stat st;
    if (::stat(HOOK_TARGETS, &st) != 0) {
        pthread_mutex_lock(&g_targets_mu);
        auto snapshot = g_targets_cache;
        pthread_mutex_unlock(&g_targets_mu);
        return snapshot;
    }
    pthread_mutex_lock(&g_targets_mu);
    if (st.st_mtime != g_targets_mtime) {
        g_targets_mtime = st.st_mtime;
        g_targets_cache = load_targets_from_disk();
        LOGI("Reloaded hook_targets (%zu entries)", g_targets_cache.size());
    }
    auto snapshot = g_targets_cache;
    pthread_mutex_unlock(&g_targets_mu);
    return snapshot;
}

// ============================================================
// [P1] Per-brand RADIO builder
// ============================================================
static std::string build_radio_for(const std::string& brand,
                                    const std::string& incremental) {
    std::string b = to_lower(brand);
    std::time_t now = std::time(nullptr);
    struct tm lt;
    localtime_r(&now, &lt);
    char datebuf[16];
    strftime(datebuf, sizeof(datebuf), "%y%m%d", &lt);
    char rad[128] = {0};

    if (b == "google") {
        snprintf(rad, sizeof(rad), "g5300q-%s-%s-B-%s",
                 datebuf, datebuf, incremental.c_str());
    } else if (b == "samsung") {
        // Samsung uses INCREMENTAL as radio version
        snprintf(rad, sizeof(rad), "%s", incremental.c_str());
    } else if (b == "xiaomi" || b == "poco"   || b == "redmi" ||
               b == "oppo"   || b == "realme" || b == "oneplus" ||
               b == "vivo"   || b == "iqoo") {
        // Qualcomm MPSS-style (Snapdragon 8-series baseband)
        snprintf(rad, sizeof(rad),
                 "MPSS.HI.4.0.c1-00104-SUNXFAAAAAAAZOZM-1.%s",
                 datebuf);
    }
    // else: unknown brand → return "" (caller should skip, don't write "unknown")
    return std::string(rad);
}

// ============================================================
// Identity struct + serializer
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
            "GAID", "GSF_ID",
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

// ============================================================
// Identity generation
// ============================================================
static Identity generate_identity(bool keep_id) {
    std::random_device rd;
    std::mt19937 gen(rd());
    Identity id;
    id.kv["BOOTLOADER"] = "unknown";
    id.kv["HOST"]       = "abfarm-release";
    id.kv["USER"]       = "android-build";
    id.kv["TYPE"]       = "user";
    id.kv["TAGS"]       = "release-keys";
    id.kv["CODENAME"]   = "REL";
    id.kv["TIME"] = std::to_string(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());

    auto json_pool = load_json_pool();
    if (!json_pool.empty()) {
        std::uniform_int_distribution<size_t> pick(0, json_pool.size() - 1);
        auto& p = json_pool[pick(gen)];
        for (const auto& [k, v] : p) id.kv[k] = v;

        if (id.kv.find("DEVICE_INITIAL_SDK_INT") == id.kv.end() &&
            id.kv.find("SDK_INT") != id.kv.end())
            id.kv["DEVICE_INITIAL_SDK_INT"] = id.kv["SDK_INT"];
        if (id.kv.find("DISPLAY") == id.kv.end())
            id.kv["DISPLAY"] = id.kv["ID"];
        if (id.kv.find("DESCRIPTION") == id.kv.end()) {
            char desc[512];
            snprintf(desc, sizeof(desc), "%s-user %s %s %s release-keys",
                     id.kv["PRODUCT"].c_str(), id.kv["RELEASE"].c_str(),
                     id.kv["ID"].c_str(), id.kv["INCREMENTAL"].c_str());
            id.kv["DESCRIPTION"] = desc;
        }
        // [P1 FIX] FINGERPRINT fallback uses real BRAND (not hardcoded "google/")
        if (id.kv.find("FINGERPRINT") == id.kv.end()) {
            std::string brand_lc = to_lower(id.kv.count("BRAND") ? id.kv["BRAND"] : "unknown");
            std::string channel  = id.kv["PRODUCT"].find("_beta") != std::string::npos ? "CANARY" : "REL";
            char fp[512];
            snprintf(fp, sizeof(fp), "%s/%s/%s:%s/%s/%s:user/release-keys",
                     brand_lc.c_str(),
                     id.kv["PRODUCT"].c_str(), id.kv["DEVICE"].c_str(),
                     channel.c_str(),
                     id.kv["ID"].c_str(), id.kv["INCREMENTAL"].c_str());
            id.kv["FINGERPRINT"] = fp;
        }
        // [P1 FIX] RADIO fallback per-brand (don't write "unknown")
        if (id.kv.find("RADIO") == id.kv.end()) {
            std::string rad = build_radio_for(
                id.kv.count("BRAND") ? id.kv["BRAND"] : "",
                id.kv.count("INCREMENTAL") ? id.kv["INCREMENTAL"] : "");
            if (!rad.empty()) id.kv["RADIO"] = rad;
        }
    } else {
        // Fallback to embedded PIXEL_POOL
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

        id.kv["RADIO"] = build_radio_for("google", p.incremental);
    }

    if (keep_id) {
        std::istringstream iss(read_file(PERSISTENT_BIN));
        std::string line;
        while (std::getline(iss, line)) {
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string k = line.substr(0, eq), v = line.substr(eq + 1);
            if (k == "SERIAL" || k == "ANDROID_ID" || k == "GAID" || k == "GSF_ID")
                id.kv[k] = trim(v);
        }
    }
    if (id.kv.find("SERIAL")     == id.kv.end()) id.kv["SERIAL"]     = random_hex(8, true);
    if (id.kv.find("ANDROID_ID") == id.kv.end()) id.kv["ANDROID_ID"] = random_hex(8, false);
    if (id.kv.find("GAID")       == id.kv.end()) id.kv["GAID"]       = random_uuid();
    if (id.kv.find("GSF_ID")     == id.kv.end()) id.kv["GSF_ID"]     = random_hex(8, false);

    std::string snap = "SERIAL="     + id.kv["SERIAL"] +
                       "\nANDROID_ID=" + id.kv["ANDROID_ID"] +
                       "\nGAID="       + id.kv["GAID"] +
                       "\nGSF_ID="     + id.kv["GSF_ID"] + "\n";
    atomic_write(PERSISTENT_BIN, snap);
    return id;
}

// ============================================================
// Apply native prop + settings + kill target apps
// ============================================================
static void apply_native(const Identity& id, bool clear_targets = true) {
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

    std::string model = get("MODEL");
    if (!model.empty()) {
        run_bin("/system/bin/settings",
                {"settings", "put", "global", "device_name", model.c_str()});
        run_bin("/system/bin/settings",
                {"settings", "put", "system", "device_name", model.c_str()});
    }
    std::string aid = get("ANDROID_ID");
    if (!aid.empty()) {
        run_bin("/system/bin/settings",
                {"settings", "put", "secure", "android_id", aid.c_str()});
    }

    // [P1 FIX] Use hot-reload cache instead of loading disk every time
    auto targets = get_targets_cached();
    for (const std::string& pkg : targets) {
        run_bin("/system/bin/am", {"am", "force-stop", pkg.c_str()});
        if (clear_targets) run_bin("/system/bin/pm", {"pm", "clear", pkg.c_str()});
    }
}

// ============================================================
// CLI command handlers
// ============================================================
static std::string do_regenerate(bool keep_id) {
    std::string mode = trim(read_file(MODE_FILE));
    if (mode == "locked")
        return "LOCKED: identity locked. Run `envctl set-mode fresh` to unlock.\n";
    if (mode == "persistent") keep_id = true;
    std::string old = read_file(IDENTITY_FILE);
    if (!old.empty()) atomic_write(IDENTITY_BAK, old);
    Identity id = generate_identity(keep_id);
    if (!atomic_write(IDENTITY_FILE, id.serialize()))
        return "ERROR: failed to write identity.prop\n";
    apply_native(id);
    std::string out = "OK\n";
    out += "  BRAND       : " + id.kv["BRAND"]         + "\n";
    out += "  MODEL       : " + id.kv["MODEL"]         + "\n";
    out += "  DEVICE      : " + id.kv["DEVICE"]        + "\n";
    out += "  FINGERPRINT : " + id.kv["FINGERPRINT"]   + "\n";
    out += "  RADIO       : " + id.kv["RADIO"]         + "\n";
    out += "  SERIAL      : " + id.kv["SERIAL"]        + "\n";
    out += "  ANDROID_ID  : " + id.kv["ANDROID_ID"]    + "\n";
    out += "  GAID        : " + id.kv["GAID"]          + "\n";
    out += "  GSF_ID      : " + id.kv["GSF_ID"]        + "\n";
    out += "  SEC PATCH   : " + id.kv["SECURITY_PATCH"]+ "\n";
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

static bool is_safe_name(const std::string& name) {
    if (name.empty()) return false;
    for (char c : name) {
        if (!std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '-') return false;
    }
    return true;
}

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
            apply_native(id, false);
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
            if (::read(client, m.data(), len) != (ssize_t)len) {
                reply = "bad mode\n"; break;
            }
            atomic_write(MODE_FILE, m + "\n");
            reply = "OK: mode=" + m + "\n";
            break;
        }
        case CLI_SNAPSHOT: {
            uint32_t len = 0;
            if (::read(client, &len, sizeof(len)) != sizeof(len) || len > 64) {
                reply = "bad len\n"; break;
            }
            std::string name(len, 0);
            if (len && ::read(client, name.data(), len) != (ssize_t)len) {
                reply = "bad name\n"; break;
            }
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
            if (::read(client, &len, sizeof(len)) != sizeof(len) || len > 64) {
                reply = "bad len\n"; break;
            }
            std::string name(len, 0);
            if (len && ::read(client, name.data(), len) != (ssize_t)len) {
                reply = "bad name\n"; break;
            }
            std::string src = IDENTITY_BAK;
            if (!name.empty()) {
                if (!is_safe_name(name)) { reply = "ERROR: invalid snapshot name\n"; break; }
                src = std::string(MODDIR) + "/identity.snap." + name;
            }
            std::string data = read_file(src);
            if (data.empty()) { reply = "no such snapshot\n"; break; }
            atomic_write(IDENTITY_FILE, data);
            apply_native(load_identity(), false);
            reply = "OK: rollback from " + src + "\n";
            break;
        }
        default: reply = "unknown cmd\n";
    }
    uint32_t rlen = (uint32_t)reply.size();
    ::write(client, &rlen, sizeof(rlen));
    ::write(client, reply.data(), rlen);
    ::close(client);
}

// ============================================================
// UDS listener with peer credential check
// ============================================================
static void* uds_listener(void*) {
    int sock = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) { LOGE("socket() failed"); return nullptr; }
    struct sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    addr.sun_path[0] = '\0';
    strncpy(addr.sun_path + 1, UDS_NAME, sizeof(addr.sun_path) - 2);
    socklen_t alen = sizeof(sa_family_t) + 1 + strlen(UDS_NAME);
    if (::bind(sock, (struct sockaddr*)&addr, alen) < 0) {
        LOGE("bind @%s failed: %s", UDS_NAME, strerror(errno));
        ::close(sock); return nullptr;
    }
    if (::listen(sock, 8) < 0) {
        LOGE("listen failed: %s", strerror(errno));
        ::close(sock); return nullptr;
    }
    LOGI("UDS listener started @%s", UDS_NAME);

    while (true) {
        int client = ::accept(sock, nullptr, nullptr);
        if (client < 0) { if (errno == EINTR) continue; break; }
        struct ucred cred;
        socklen_t cr_len = sizeof(cred);
        if (::getsockopt(client, SOL_SOCKET, SO_PEERCRED, &cred, &cr_len) < 0) {
            ::close(client); continue;
        }
        if (cred.uid != 0 && cred.uid != 2000) {
            LOGE("Unauthorized UDS connection from UID %d", cred.uid);
            ::close(client); continue;
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
// Zygisk companion entry
// ============================================================
extern "C" __attribute__((visibility("default")))
void env_companion_entry(int client) {
    pthread_once(&g_once, start_uds_thread_once);
    while (true) {
        uint8_t cmd = 0;
        if (::read(client, &cmd, 1) != 1) break;
        if (cmd == CMD_CHECK_TARGET) {
            uint32_t len = 0;
            if (::read(client, &len, sizeof(len)) != sizeof(len) || len > 512) break;
            std::string pkg(len, 0);
            if (::read(client, pkg.data(), len) != (ssize_t)len) break;
            // [P1 FIX] hot-reload cache instead of static-once
            auto targets = get_targets_cached();
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
