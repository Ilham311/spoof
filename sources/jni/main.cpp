#include <jni.h>
#include <android/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include "zygisk.hpp"

#define LOG_TAG "TernakZygisk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

constexpr const char* TARGETS_FILE = "/data/adb/modules/ternak_device_changer/hook_targets.txt";
constexpr const char* SPOOF_FILE = "/data/adb/modules/ternak_device_changer/spoof.prop";
constexpr const char* PIF_FILE = "/data/adb/modules/playintegrityfix/pif.prop";

#define MAX_SPOOF_PROPS 64
#define MAX_PROP_LEN 256

struct SpoofProp {
    char key[MAX_PROP_LEN];
    char value[MAX_PROP_LEN];
};

void* operator new(size_t size) {
    return malloc(size);
}

void operator delete(void* p) noexcept {
    free(p);
}

void operator delete(void* p, size_t size) noexcept {
    free(p);
}

class TernakModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        api_ = api;
        env_ = env;
        memset(process_name_, 0, sizeof(process_name_));
        memset(spoof_props_, 0, sizeof(spoof_props_));
        spoof_props_count_ = 0;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        jstring nice_name = args->nice_name;
        if (!nice_name) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        const char *process_name = env_->GetStringUTFChars(nice_name, nullptr);
        if (!process_name) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }
        strncpy(process_name_, process_name, sizeof(process_name_) - 1);
        process_name_[sizeof(process_name_) - 1] = '\0';
        env_->ReleaseStringUTFChars(nice_name, process_name);

        if (!is_target_process()) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        load_spoof_props();
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
        if (spoof_props_count_ > 0) {
            apply_build_spoof();
        }
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs *args) override {
        api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api_;
    JNIEnv *env_;
    char process_name_[256];
    SpoofProp spoof_props_[MAX_SPOOF_PROPS];
    int spoof_props_count_;

    void clear_exceptions() {
        if (env_->ExceptionCheck()) {
            env_->ExceptionClear();
        }
    }

    char* trim(char* str) {
        if (!str) return nullptr;
        while (isspace((unsigned char)*str)) str++;
        if (*str == 0) return str;
        char* end = str + strlen(str) - 1;
        while (end > str && isspace((unsigned char)*end)) end--;
        end[1] = '\0';
        return str;
    }

    bool is_target_process() {
        FILE* fp = fopen(TARGETS_FILE, "r");
        bool match = false;
        if (fp) {
            char line[512];
            while (fgets(line, sizeof(line), fp)) {
                char* t = trim(line);
                if (t[0] == '\0' || t[0] == '#') continue;

                size_t len = strlen(t);
                if (len > 0 && t[len - 1] == '*') {
                    if (strncmp(process_name_, t, len - 1) == 0) {
                        match = true;
                        break;
                    }
                } else {
                    if (strcmp(process_name_, t) == 0) {
                        match = true;
                        break;
                    }
                }
            }
            fclose(fp);
            return match;
        } else {
            const char* defaults[] = {
                "com.shopee.id",
                "com.tokopedia.tkpd",
                "com.ss.android.ugc.trill",
                "com.zhiliaoapp.musically",
                "com.liuzh.deviceinfo",
                "com.cwsl.mydevice"
            };
            for (size_t i = 0; i < sizeof(defaults) / sizeof(defaults[0]); i++) {
                if (strcmp(process_name_, defaults[i]) == 0) {
                    return true;
                }
            }
            return false;
        }
    }

    void load_spoof_props() {
        FILE* fp = fopen(SPOOF_FILE, "r");
        if (!fp) {
            fp = fopen(PIF_FILE, "r");
            if (!fp) return;
        }

        char line[1024];
        while (fgets(line, sizeof(line), fp)) {
            if (spoof_props_count_ >= MAX_SPOOF_PROPS) break;

            char* t = trim(line);
            if (t[0] == '\0' || t[0] == '#') continue;

            char* eq = strchr(t, '=');
            if (eq) {
                *eq = '\0';
                char* key = trim(t);
                char* val = trim(eq + 1);

                if (strncmp(key, "spoof", 5) == 0 || strcmp(key, "DEBUG") == 0 || strcmp(key, "verboseLogs") == 0) {
                    continue;
                }

                strncpy(spoof_props_[spoof_props_count_].key, key, MAX_PROP_LEN - 1);
                spoof_props_[spoof_props_count_].key[MAX_PROP_LEN - 1] = '\0';
                strncpy(spoof_props_[spoof_props_count_].value, val, MAX_PROP_LEN - 1);
                spoof_props_[spoof_props_count_].value[MAX_PROP_LEN - 1] = '\0';
                spoof_props_count_++;
            }
        }
        fclose(fp);
    }

    const char* get_prop(const char* key) {
        for (int i = 0; i < spoof_props_count_; i++) {
            if (strcmp(spoof_props_[i].key, key) == 0) {
                return spoof_props_[i].value;
            }
        }
        return nullptr;
    }

    void set_static_string_field(jclass clazz, const char* field_name, const char* value) {
        jfieldID field = env_->GetStaticFieldID(clazz, field_name, "Ljava/lang/String;");
        clear_exceptions();
        if (field) {
            jstring jval = env_->NewStringUTF(value);
            env_->SetStaticObjectField(clazz, field, jval);
            env_->DeleteLocalRef(jval);
            clear_exceptions();
        }
    }

    void set_static_int_field(jclass clazz, const char* field_name, int value) {
        jfieldID field = env_->GetStaticFieldID(clazz, field_name, "I");
        clear_exceptions();
        if (field) {
            env_->SetStaticIntField(clazz, field, value);
            clear_exceptions();
        }
    }

    void set_static_long_field(jclass clazz, const char* field_name, long long value) {
        jfieldID field = env_->GetStaticFieldID(clazz, field_name, "J");
        clear_exceptions();
        if (field) {
            env_->SetStaticLongField(clazz, field, value);
            clear_exceptions();
        }
    }

    void apply_build_spoof() {
        int fields_spoofed = 0;

        jclass build_class = env_->FindClass("android/os/Build");
        clear_exceptions();

        if (build_class) {
            const char* string_fields[] = {
                "BRAND", "MANUFACTURER", "MODEL", "DEVICE", "PRODUCT",
                "FINGERPRINT", "ID", "BOARD", "HARDWARE", "TAGS",
                "TYPE", "BOOTLOADER", "HOST", "USER"
            };

            for (size_t i = 0; i < sizeof(string_fields) / sizeof(string_fields[0]); i++) {
                const char* val = get_prop(string_fields[i]);
                if (val) {
                    set_static_string_field(build_class, string_fields[i], val);
                    fields_spoofed++;
                }
            }
            env_->DeleteLocalRef(build_class);
        }

        jclass version_class = env_->FindClass("android/os/Build$VERSION");
        clear_exceptions();

        if (version_class) {
            const char* version_string_fields[] = {
                "RELEASE", "INCREMENTAL", "SECURITY_PATCH", "CODENAME"
            };

            for (size_t i = 0; i < sizeof(version_string_fields) / sizeof(version_string_fields[0]); i++) {
                const char* val = get_prop(version_string_fields[i]);
                if (val) {
                    set_static_string_field(version_class, version_string_fields[i], val);
                    fields_spoofed++;
                }
            }

            const char* sdk_int_str = get_prop("SDK_INT");
            if (sdk_int_str) {
                int sdk_int = atoi(sdk_int_str);
                if (sdk_int > 0) {
                    set_static_int_field(version_class, "SDK_INT", sdk_int);
                    fields_spoofed++;
                }
            }

            const char* init_sdk_str = get_prop("DEVICE_INITIAL_SDK_INT");
            if (init_sdk_str) {
                int init_sdk = atoi(init_sdk_str);
                if (init_sdk > 0) {
                    set_static_int_field(version_class, "DEVICE_INITIAL_SDK_INT", init_sdk);
                    fields_spoofed++;
                }
            }

            const char* time_str = get_prop("TIME");
            if (time_str) {
                long long time_val = atoll(time_str);
                if (time_val > 0) {
                    set_static_long_field(version_class, "TIME", time_val);
                    fields_spoofed++;
                }
            }

            env_->DeleteLocalRef(version_class);
        }

        LOGI("%s: %d Build fields spoofed", process_name_, fields_spoofed);
    }
};

REGISTER_ZYGISK_MODULE(TernakModule)
