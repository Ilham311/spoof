#include <jni.h>
#include <unistd.h>
#include <sys/system_properties.h>
#include <android/log.h>
#include <string>
#include <map>
#include <vector>
#include <utility>
#include <sstream>
#include <cstdlib>
#include "zygisk.hpp"

#define LOG_TAG "EnvZygisk"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

using zygisk::Api;
using zygisk::AppSpecializeArgs;
using zygisk::ServerSpecializeArgs;

enum : uint8_t {
    CMD_CHECK_TARGET = 1,
    CMD_GET_IDENTITY = 2,
};

static std::map<std::string, std::string> g_identity;

static const std::string& lookup(const std::string& k) {
    static const std::string empty;
    auto it = g_identity.find(k);
    return it != g_identity.end() ? it->second : empty;
}

static jstring hook_native_get(JNIEnv* env, jclass, jstring j_key, jstring j_def) {
    if (!j_key) return j_def;
    const char* raw = env->GetStringUTFChars(j_key, nullptr);
    std::string k(raw ? raw : "");
    env->ReleaseStringUTFChars(j_key, raw);

    static const std::map<std::string, std::string> prop_to_id = {
        {"ro.serialno",                    "SERIAL"},
        {"ro.boot.serialno",               "SERIAL"},
        {"ro.build.display.id",            "DISPLAY"},
        {"ro.build.description",           "DESCRIPTION"},
        {"gsm.version.baseband",           "RADIO"},
        {"ro.build.expect.baseband",       "RADIO"},
        {"ro.build.fingerprint",           "FINGERPRINT"},
        {"ro.bootimage.build.fingerprint", "FINGERPRINT"},
        {"ro.system.build.fingerprint",    "FINGERPRINT"},
        {"ro.vendor.build.fingerprint",    "FINGERPRINT"},
        {"ro.product.build.fingerprint",   "FINGERPRINT"},
        {"ro.product.model",               "MODEL"},
        {"ro.product.system.model",        "MODEL"},
        {"ro.product.vendor.model",        "MODEL"},
        {"ro.product.brand",               "BRAND"},
        {"ro.product.system.brand",        "BRAND"},
        {"ro.product.vendor.brand",        "BRAND"},
        {"ro.product.manufacturer",        "MANUFACTURER"},
        {"ro.product.system.manufacturer", "MANUFACTURER"},
        {"ro.product.vendor.manufacturer", "MANUFACTURER"},
        {"ro.product.device",              "DEVICE"},
        {"ro.product.system.device",       "DEVICE"},
        {"ro.product.vendor.device",       "DEVICE"},
        {"ro.product.name",                "PRODUCT"},
        {"ro.product.system.name",         "PRODUCT"},
        {"ro.product.board",               "BOARD"},
        {"ro.board.platform",              "HARDWARE"},
        {"ro.hardware",                    "HARDWARE"},
        {"ro.build.id",                    "ID"},
        {"ro.build.type",                  "TYPE"},
        {"ro.build.tags",                  "TAGS"},
        {"ro.build.user",                  "USER"},
        {"ro.build.host",                  "HOST"},
        {"ro.build.version.incremental",   "INCREMENTAL"},
        {"ro.build.version.release",       "RELEASE"},
        {"ro.build.version.sdk",           "SDK_INT"},
        {"ro.build.version.security_patch","SECURITY_PATCH"},
        {"ro.build.version.codename",      "CODENAME"},
        {"ro.bootloader",                  "BOOTLOADER"},
    };

    auto it = prop_to_id.find(k);
    if (it != prop_to_id.end()) {
        const std::string& val = lookup(it->second);
        if (!val.empty()) return env->NewStringUTF(val.c_str());
    }
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get(k.c_str(), buf) > 0) {
        return env->NewStringUTF(buf);
    }
    return j_def;
}

static void install_native_get_hook(JNIEnv* env) {
    jclass sp = env->FindClass("android/os/SystemProperties");
    if (!sp) { env->ExceptionClear(); return; }
    JNINativeMethod m = {
        const_cast<char*>("native_get"),
        const_cast<char*>("(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"),
        reinterpret_cast<void*>(hook_native_get)
    };
    env->RegisterNatives(sp, &m, 1);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        LOGE("RegisterNatives SystemProperties.native_get FAILED");
    } else {
        LOGD("Hooked SystemProperties.native_get");
    }
    env->DeleteLocalRef(sp);
}

static void set_str(JNIEnv* env, jclass c, const char* f, const std::string& v) {
    if (v.empty()) return;
    jfieldID id = env->GetStaticFieldID(c, f, "Ljava/lang/String;");
    if (!id) { env->ExceptionClear(); return; }
    jstring j = env->NewStringUTF(v.c_str());
    env->SetStaticObjectField(c, id, j);
    env->DeleteLocalRef(j);
}

static void set_int(JNIEnv* env, jclass c, const char* f, int v) {
    jfieldID id = env->GetStaticFieldID(c, f, "I");
    if (!id) { env->ExceptionClear(); return; }
    env->SetStaticIntField(c, id, v);
}

static void set_long(JNIEnv* env, jclass c, const char* f, jlong v) {
    jfieldID id = env->GetStaticFieldID(c, f, "J");
    if (!id) { env->ExceptionClear(); return; }
    env->SetStaticLongField(c, id, v);
}

static void apply_build_hooks(JNIEnv* env) {
    jclass build = env->FindClass("android/os/Build");
    if (build) {
        static const std::vector<std::pair<const char*, const char*>> str_fields = {
            {"BRAND",        "BRAND"},
            {"MANUFACTURER", "MANUFACTURER"},
            {"MODEL",        "MODEL"},
            {"DEVICE",       "DEVICE"},
            {"PRODUCT",      "PRODUCT"},
            {"BOARD",        "BOARD"},
            {"HARDWARE",     "HARDWARE"},
            {"FINGERPRINT",  "FINGERPRINT"},
            {"ID",           "ID"},
            {"DISPLAY",      "DISPLAY"},
            {"BOOTLOADER",   "BOOTLOADER"},
            {"HOST",         "HOST"},
            {"USER",         "USER"},
            {"TYPE",         "TYPE"},
            {"TAGS",         "TAGS"},
            {"SERIAL",       "SERIAL"},
            {"RADIO",        "RADIO"},
        };
        for (const auto& [f, k] : str_fields) set_str(env, build, f, lookup(k));

        const std::string& t = lookup("TIME");
        if (!t.empty()) {
            char* end = nullptr;
            long long val = std::strtoll(t.c_str(), &end, 10);
            if (end && *end == '\0') {
                set_long(env, build, "TIME", (jlong)val);
            }
        }
        env->DeleteLocalRef(build);
    } else env->ExceptionClear();

    jclass ver = env->FindClass("android/os/Build$VERSION");
    if (ver) {
        static const std::vector<std::pair<const char*, const char*>> vstr = {
            {"RELEASE",        "RELEASE"},
            {"INCREMENTAL",    "INCREMENTAL"},
            {"CODENAME",       "CODENAME"},
            {"SECURITY_PATCH", "SECURITY_PATCH"},
        };
        for (const auto& [f, k] : vstr) set_str(env, ver, f, lookup(k));

        const std::string& s = lookup("SDK_INT");
        if (!s.empty()) {
            char* end = nullptr;
            long val = std::strtol(s.c_str(), &end, 10);
            if (end && *end == '\0') set_int(env, ver, "SDK_INT", (int)val);
        }
        const std::string& si = lookup("DEVICE_INITIAL_SDK_INT");
        if (!si.empty()) {
            char* end = nullptr;
            long val = std::strtol(si.c_str(), &end, 10);
            if (end && *end == '\0') set_int(env, ver, "DEVICE_INITIAL_SDK_INT", (int)val);
        }
        env->DeleteLocalRef(ver);
    } else env->ExceptionClear();
}

class EnvModule : public zygisk::ModuleBase {
public:
    void onLoad(Api* api, JNIEnv* env) override { api_ = api; env_ = env; }

    void preAppSpecialize(AppSpecializeArgs* args) override {
        std::string pkg;
        if (args && args->nice_name) {
            const char* raw = env_->GetStringUTFChars(args->nice_name, nullptr);
            pkg = raw ? raw : "";
            env_->ReleaseStringUTFChars(args->nice_name, raw);
        }
        if (pkg.empty()) { unload(); return; }

        int fd = api_->connectCompanion();
        if (fd < 0) { unload(); return; }

        uint8_t cmd = CMD_CHECK_TARGET;
        uint32_t len = (uint32_t)pkg.size();
        write(fd, &cmd, 1);
        write(fd, &len, sizeof(len));
        write(fd, pkg.data(), len);

        uint8_t reply = 0;
        if (read(fd, &reply, 1) != 1 || reply != 1) {
            close(fd); unload(); return;
        }

        cmd = CMD_GET_IDENTITY;
        write(fd, &cmd, 1);
        uint32_t blen = 0;
        if (read(fd, &blen, sizeof(blen)) != (ssize_t)sizeof(blen)
            || blen == 0 || blen > 65536) {
            close(fd); unload(); return;
        }
        identity_blob_.resize(blen);
        size_t got = 0;
        while (got < blen) {
            ssize_t n = read(fd, identity_blob_.data() + got, blen - got);
            if (n <= 0) break;
            got += (size_t)n;
        }
        close(fd);
        if (got != blen) { unload(); return; }

        should_hook_ = true;
        LOGI("Target hooked: %s (%u B)", pkg.c_str(), blen);
    }

    void postAppSpecialize(const AppSpecializeArgs*) override {
        if (!should_hook_) return;
        parse_blob();
        install_native_get_hook(env_);
        apply_build_hooks(env_);
    }

    void preServerSpecialize(ServerSpecializeArgs*) override { unload(); }

private:
    Api* api_ = nullptr;
    JNIEnv* env_ = nullptr;
    bool should_hook_ = false;
    std::vector<uint8_t> identity_blob_;

    void unload() {
        if (api_) api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

    void parse_blob() {
        std::string s(identity_blob_.begin(), identity_blob_.end());
        std::istringstream iss(s);
        std::string line;
        while (std::getline(iss, line)) {
            if (line.empty() || line[0] == '#') continue;
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            g_identity[line.substr(0, eq)] = line.substr(eq + 1);
        }
    }
};

REGISTER_ZYGISK_MODULE(EnvModule)

extern "C" __attribute__((visibility("default"))) void env_companion_entry(int client);
REGISTER_ZYGISK_COMPANION(env_companion_entry)
