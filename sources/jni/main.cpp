// main.cpp — Ternak Zygisk Companion (v1.1.0)
// Hook android.os.Build.* untuk paket di hook_targets.txt
// v1.1.0: derive_from_fingerprint() safety net + skip-log verbose

#include <jni.h>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <sstream>
#include <android/log.h>

#include "zygisk.hpp"

#define LOG_TAG "TernakZygisk"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

using zygisk::Api;
using zygisk::AppSpecializeArgs;
using zygisk::ServerSpecializeArgs;

static constexpr const char *TARGETS_FILE = "/data/adb/modules/ternak_device_changer/hook_targets.txt";
static constexpr const char *SPOOF_FILE   = "/data/adb/modules/ternak_device_changer/spoof.prop";
static constexpr const char *PIF_FILE     = "/data/adb/modules/playintegrityfix/pif.prop";

static inline void trim(std::string &s) {
    while (!s.empty() && (s.back()==' '||s.back()=='\t'||s.back()=='\r'||s.back()=='\n')) s.pop_back();
    size_t p = 0; while (p < s.size() && (s[p]==' '||s[p]=='\t')) ++p;
    s.erase(0, p);
    if (s.size() >= 2 && s.front()=='"' && s.back()=='"') s = s.substr(1, s.size()-2);
}

class TernakModule : public zygisk::ModuleBase {
public:
    void onLoad(Api *api, JNIEnv *env) override {
        this->api = api;
        this->env = env;
    }

    void preAppSpecialize(AppSpecializeArgs *args) override {
        if (!args || !args->nice_name) { unload(); return; }
        const char *raw = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!raw) { unload(); return; }
        proc_name.assign(raw);
        env->ReleaseStringUTFChars(args->nice_name, raw);

        if (!is_target(proc_name)) {
            unload();
            return;
        }

        load_spoof_props();
        if (spoof.empty()) {
            LOGW("Target %s matched tapi spoof.prop kosong — nothing to apply", proc_name.c_str());
        } else {
            LOGI("Target %s: %zu spoof keys loaded", proc_name.c_str(), spoof.size());
        }
    }

    void postAppSpecialize(const AppSpecializeArgs * /*args*/) override {
        if (spoof.empty()) return;
        apply_build_spoof();
    }

    void preServerSpecialize(ServerSpecializeArgs * /*args*/) override {
        unload();
    }

private:
    Api *api = nullptr;
    JNIEnv *env = nullptr;
    std::string proc_name;
    std::map<std::string, std::string> spoof;

    void unload() {
        if (api) api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

    // -------- whitelist --------
    bool is_target(const std::string &pkg) {
        std::ifstream f(TARGETS_FILE);
        std::string line;
        bool any = false;
        if (f) {
            while (std::getline(f, line)) {
                auto h = line.find('#'); if (h != std::string::npos) line.erase(h);
                trim(line);
                if (line.empty()) continue;
                any = true;
                if (line == pkg) return true;
                if (!line.empty() && line.back() == '*') {
                    std::string prefix = line.substr(0, line.size() - 1);
                    if (pkg.compare(0, prefix.size(), prefix) == 0) return true;
                }
            }
        }
        if (any) return false;

        static const char *defaults[] = {
            "com.shopee.id",
            "com.tokopedia.tkpd",
            "com.ss.android.ugc.trill",
            "com.zhiliaoapp.musically",
            "com.liuzh.deviceinfo",
            "com.cwsl.mydevice",
            nullptr
        };
        for (int i = 0; defaults[i]; ++i)
            if (pkg == defaults[i]) return true;
        return false;
    }

    // -------- prop parser --------
    bool parse_prop_file(const char *path) {
        std::ifstream f(path);
        if (!f) return false;
        std::string line;
        size_t before = spoof.size();
        while (std::getline(f, line)) {
            auto h = line.find('#'); if (h != std::string::npos) line.erase(h);
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string k = line.substr(0, eq);
            std::string v = line.substr(eq + 1);
            trim(k); trim(v);
            if (k.empty()) continue;
            if (k == "DEBUG" || k.rfind("spoof", 0) == 0 || k == "verboseLogs") continue;
            spoof[k] = v;
        }
        return spoof.size() > before;
    }

    // -------- v1.1.0: derive missing keys dari FINGERPRINT --------
    // format kanonik: brand/product/device:release/id/incremental:type/tags
    void derive_from_fingerprint() {
        auto fp = spoof.find("FINGERPRINT");
        if (fp == spoof.end()) return;
        const std::string &s = fp->second;

        auto s1 = s.find('/');                       if (s1 == std::string::npos) return;
        auto s2 = s.find('/', s1 + 1);               if (s2 == std::string::npos) return;
        auto c1 = s.find(':', s2 + 1);               if (c1 == std::string::npos) return;
        auto s3 = s.find('/', c1 + 1);               if (s3 == std::string::npos) return;
        auto s4 = s.find('/', s3 + 1);               if (s4 == std::string::npos) return;
        auto c2 = s.find(':', s4 + 1);               if (c2 == std::string::npos) return;

        std::string brand   = s.substr(0, s1);
        std::string product = s.substr(s1 + 1, s2 - s1 - 1);
        std::string device  = s.substr(s2 + 1, c1 - s2 - 1);
        std::string release = s.substr(c1 + 1, s3 - c1 - 1);
        std::string bid     = s.substr(s3 + 1, s4 - s3 - 1);
        std::string incr    = s.substr(s4 + 1, c2 - s4 - 1);
        std::string rest    = s.substr(c2 + 1);
        auto s5 = rest.find('/');
        std::string type    = (s5 == std::string::npos) ? rest : rest.substr(0, s5);
        std::string tags    = (s5 == std::string::npos) ? std::string() : rest.substr(s5 + 1);

        auto fill = [&](const char *k, const std::string &v) {
            if (!v.empty() && spoof.find(k) == spoof.end()) {
                spoof[k] = v;
                LOGD("derived %s = %s (from FINGERPRINT)", k, v.c_str());
            }
        };
        fill("BRAND",       brand);
        fill("PRODUCT",     product);
        fill("DEVICE",      device);
        fill("BOARD",       device);
        fill("HARDWARE",    device);
        fill("RELEASE",     release);
        fill("ID",          bid);
        fill("INCREMENTAL", incr);
        fill("TYPE",        type);
        fill("TAGS",        tags);
    }

    void load_spoof_props() {
        spoof.clear();
        if (!parse_prop_file(SPOOF_FILE)) {
            parse_prop_file(PIF_FILE);
        }
        derive_from_fingerprint();   // v1.1.0: safety net
    }

    // -------- JNI helpers --------
    void set_static_string(jclass clazz, const char *field, const std::string &val) {
        if (!clazz) return;
        jfieldID fid = env->GetStaticFieldID(clazz, field, "Ljava/lang/String;");
        if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
        if (!fid) return;
        jstring js = env->NewStringUTF(val.c_str());
        env->SetStaticObjectField(clazz, fid, js);
        env->DeleteLocalRef(js);
        if (env->ExceptionCheck()) env->ExceptionClear();
    }

    void set_static_int(jclass clazz, const char *field, int val) {
        if (!clazz) return;
        jfieldID fid = env->GetStaticFieldID(clazz, field, "I");
        if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
        if (!fid) return;
        env->SetStaticIntField(clazz, fid, val);
        if (env->ExceptionCheck()) env->ExceptionClear();
    }

    void set_static_long(jclass clazz, const char *field, long long val) {
        if (!clazz) return;
        jfieldID fid = env->GetStaticFieldID(clazz, field, "J");
        if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
        if (!fid) return;
        env->SetStaticLongField(clazz, fid, (jlong)val);
        if (env->ExceptionCheck()) env->ExceptionClear();
    }

    // -------- inti spoof --------
    void apply_build_spoof() {
        jclass build = env->FindClass("android/os/Build");
        if (env->ExceptionCheck()) env->ExceptionClear();
        jclass ver   = env->FindClass("android/os/Build$VERSION");
        if (env->ExceptionCheck()) env->ExceptionClear();

        if (!build && !ver) {
            LOGW("android.os.Build tidak ditemukan — spoof di-skip");
            return;
        }

        struct StrEntry { const char *key; const char *field; jclass clazz; };
        StrEntry str_map[] = {
            { "BRAND",          "BRAND",          build },
            { "MANUFACTURER",   "MANUFACTURER",   build },
            { "MODEL",          "MODEL",          build },
            { "DEVICE",         "DEVICE",         build },
            { "PRODUCT",        "PRODUCT",        build },
            { "FINGERPRINT",    "FINGERPRINT",    build },
            { "ID",             "ID",             build },
            { "BOARD",          "BOARD",          build },
            { "HARDWARE",       "HARDWARE",       build },
            { "TAGS",           "TAGS",           build },
            { "TYPE",           "TYPE",           build },
            { "BOOTLOADER",     "BOOTLOADER",     build },
            { "HOST",           "HOST",           build },
            { "USER",           "USER",           build },
            { "RELEASE",        "RELEASE",        ver   },
            { "INCREMENTAL",    "INCREMENTAL",    ver   },
            { "SECURITY_PATCH", "SECURITY_PATCH", ver   },
            { "CODENAME",       "CODENAME",       ver   },
        };
        int applied = 0, skipped = 0;
        for (auto &e : str_map) {
            auto it = spoof.find(e.key);
            if (it == spoof.end() || !e.clazz) {
                if (e.clazz) { ++skipped; LOGD("skip Build.%s — key %s tidak ada di spoof map", e.field, e.key); }
                continue;
            }
            set_static_string(e.clazz, e.field, it->second);
            ++applied;
            LOGD("%s.%s = %s",
                 (e.clazz == ver ? "Build.VERSION" : "Build"),
                 e.field, it->second.c_str());
        }

        auto sdk = spoof.find("SDK_INT");
        if (sdk != spoof.end() && ver) { int v = std::atoi(sdk->second.c_str()); if (v > 0) { set_static_int(ver, "SDK_INT", v); ++applied; } }
        auto first = spoof.find("DEVICE_INITIAL_SDK_INT");
        if (first != spoof.end() && ver) { int v = std::atoi(first->second.c_str()); if (v > 0) { set_static_int(ver, "DEVICE_INITIAL_SDK_INT", v); ++applied; } }
        auto tms = spoof.find("TIME");
        if (tms != spoof.end() && build) { long long v = std::atoll(tms->second.c_str()); if (v > 0) { set_static_long(build, "TIME", v); ++applied; } }

        if (build) env->DeleteLocalRef(build);
        if (ver)   env->DeleteLocalRef(ver);

        LOGI("%s: %d Build fields spoofed, %d skipped", proc_name.c_str(), applied, skipped);
    }
};

REGISTER_ZYGISK_MODULE(TernakModule)
