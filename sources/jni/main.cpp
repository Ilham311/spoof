#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "zygisk.hpp"

#define LOG_TAG "TernakZygisk"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

#define TARGETS_FILE "/data/adb/modules/ternak_device_changer/hook_targets.txt"
#define SPOOF_FILE "/data/adb/modules/ternak_device_changer/spoof.prop"
#define PIF_FILE "/data/adb/pif.prop"

#define MAX_SPOOF_PROPS 64
#define MAX_PROP_LEN 256

// Basic new/delete for ANDROID_STL=none
void* operator new(size_t size) {
    return malloc(size);
}
void operator delete(void* ptr) noexcept {
    free(ptr);
}
void* operator new[](size_t size) {
    return malloc(size);
}
void operator delete[](void* ptr) noexcept {
    free(ptr);
}
void operator delete(void* ptr, size_t) noexcept {
    free(ptr);
}

struct SpoofProp {
    char key[MAX_PROP_LEN];
    char value[MAX_PROP_LEN];
};

static void clearException(JNIEnv* env) {
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
}

class TernakModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api* api, JNIEnv* env) override {
        this->api = api;
        this->env = env;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        if (!args || !args->nice_name) {
            api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        const char* process_name_cstr = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!process_name_cstr) {
            clearException(env);
            api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        strncpy(process_name, process_name_cstr, sizeof(process_name) - 1);
        process_name[sizeof(process_name) - 1] = '\0';

        env->ReleaseStringUTFChars(args->nice_name, process_name_cstr);
        clearException(env);

        bool is_target = false;

        bool has_valid_targets = false;
        FILE* targets_fp = fopen(TARGETS_FILE, "r");
        if (targets_fp) {
            char line[256];
            while (fgets(line, sizeof(line), targets_fp)) {
                char* p = line;
                while (*p == ' ' || *p == '\t') p++;
                size_t len = strlen(p);
                while (len > 0 && (p[len - 1] == '\n' || p[len - 1] == '\r' || p[len - 1] == ' ' || p[len - 1] == '\t')) {
                    p[--len] = '\0';
                }

                if (len == 0 || p[0] == '#') continue;

                char* star_pos = strchr(p, '*');
                if (star_pos) {
                    if (star_pos != p + len - 1) {
                        LOGW("Wildcard '*' not at the end of line: %s, skipping", p);
                        continue;
                    }
                    *star_pos = '\0';
                    if (p[0] == '\0') {
                        LOGW("Empty wildcard prefix, skipping line");
                        continue;
                    }
                    has_valid_targets = true;
                    if (strncmp(process_name, p, strlen(p)) == 0) {
                        is_target = true;
                        break;
                    }
                } else {
                    has_valid_targets = true;
                    if (strcmp(process_name, p) == 0) {
                        is_target = true;
                        break;
                    }
                }
            }
            fclose(targets_fp);
        }

        if (!has_valid_targets) {
            const char* defaults[] = {
                "com.shopee.id",
                "com.tokopedia.tkpd",
                "com.ss.android.ugc.trill",
                "com.zhiliaoapp.musically",
                "com.liuzh.deviceinfo",
                "com.cwsl.mydevice"
            };
            for (size_t i = 0; i < sizeof(defaults) / sizeof(defaults[0]); ++i) {
                if (strcmp(process_name, defaults[i]) == 0) {
                    is_target = true;
                    break;
                }
            }
        }

        if (!is_target) {
            api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        if (!loadSpoofProps(SPOOF_FILE)) {
            if (!loadSpoofProps(PIF_FILE)) {
                LOGW("Target %s matched but no spoof source available, skipping hook", process_name);
                api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
                return;
            }
        }
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs* args) override {
        if (spoof_count == 0) return;
        apply_build_spoof();
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs* args) override {
        api->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api* api;
    JNIEnv* env;
    char process_name[256];
    SpoofProp spoof_props[MAX_SPOOF_PROPS];
    int spoof_count = 0;

    bool loadSpoofProps(const char* filepath) {
        FILE* fp = fopen(filepath, "r");
        if (!fp) {
            LOGD("Failed to open spoof file: %s", filepath);
            return false;
        }

        bool loaded_any = false;
        char line[512];
        while (fgets(line, sizeof(line), fp)) {
            char* p = line;
            while (*p == ' ' || *p == '\t') p++;
            size_t len = strlen(p);
            while (len > 0 && (p[len - 1] == '\n' || p[len - 1] == '\r' || p[len - 1] == ' ' || p[len - 1] == '\t')) {
                p[--len] = '\0';
            }

            if (len == 0 || p[0] == '#') continue;

            char* eq = strchr(p, '=');
            if (!eq) continue;

            *eq = '\0';
            const char* key = p;
            const char* val = eq + 1;

            if (strncmp(key, "spoof", 5) == 0 || strcmp(key, "DEBUG") == 0 || strcmp(key, "verboseLogs") == 0) {
                continue;
            }

            if (spoof_count < MAX_SPOOF_PROPS) {
                strncpy(spoof_props[spoof_count].key, key, MAX_PROP_LEN - 1);
                spoof_props[spoof_count].key[MAX_PROP_LEN - 1] = '\0';

                strncpy(spoof_props[spoof_count].value, val, MAX_PROP_LEN - 1);
                spoof_props[spoof_count].value[MAX_PROP_LEN - 1] = '\0';

                spoof_count++;
                loaded_any = true;
            }
        }
        fclose(fp);

        if (loaded_any) {
             LOGD("Loaded spoof props from %s", filepath);
        }

        return loaded_any;
    }

    void setStringField(jclass clazz, const char* fieldName, const char* value) {
        jfieldID fieldId = env->GetStaticFieldID(clazz, fieldName, "Ljava/lang/String;");
        clearException(env);
        if (fieldId) {
            jstring jstr = env->NewStringUTF(value);
            clearException(env);
            if (jstr) {
                env->SetStaticObjectField(clazz, fieldId, jstr);
                clearException(env);
                env->DeleteLocalRef(jstr);
            }
        }
    }

    void setIntField(jclass clazz, const char* fieldName, const char* value) {
        int intVal = atoi(value);
        if (intVal <= 0) return;

        jfieldID fieldId = env->GetStaticFieldID(clazz, fieldName, "I");
        clearException(env);
        if (fieldId) {
            env->SetStaticIntField(clazz, fieldId, intVal);
            clearException(env);
        }
    }

    void setLongField(jclass clazz, const char* fieldName, const char* value) {
        long long longVal = atoll(value);
        if (longVal <= 0) return;

        jfieldID fieldId = env->GetStaticFieldID(clazz, fieldName, "J");
        clearException(env);
        if (fieldId) {
            env->SetStaticLongField(clazz, fieldId, (jlong)longVal);
            clearException(env);
        }
    }

    void apply_build_spoof() {
        if (!env) return;

        jclass build_class = env->FindClass("android/os/Build");
        clearException(env);
        jclass version_class = env->FindClass("android/os/Build$VERSION");
        clearException(env);

        if (!build_class || !version_class) {
            LOGE("Failed to find Build or Build$VERSION class");
            return;
        }

        int count = 0;

        for (int i = 0; i < spoof_count; ++i) {
            const char* key = spoof_props[i].key;
            const char* val = spoof_props[i].value;

            if (strcmp(key, "BRAND") == 0 || strcmp(key, "MANUFACTURER") == 0 || strcmp(key, "MODEL") == 0 ||
                strcmp(key, "DEVICE") == 0 || strcmp(key, "PRODUCT") == 0 || strcmp(key, "FINGERPRINT") == 0 ||
                strcmp(key, "ID") == 0 || strcmp(key, "BOARD") == 0 || strcmp(key, "HARDWARE") == 0 ||
                strcmp(key, "TAGS") == 0 || strcmp(key, "TYPE") == 0 || strcmp(key, "BOOTLOADER") == 0 ||
                strcmp(key, "HOST") == 0 || strcmp(key, "USER") == 0) {
                setStringField(build_class, key, val);
                count++;
            } else if (strcmp(key, "RELEASE") == 0 || strcmp(key, "INCREMENTAL") == 0 || strcmp(key, "SECURITY_PATCH") == 0 || strcmp(key, "CODENAME") == 0) {
                setStringField(version_class, key, val);
                count++;
            } else if (strcmp(key, "SDK_INT") == 0 || strcmp(key, "DEVICE_INITIAL_SDK_INT") == 0) {
                setIntField(version_class, key, val);
                count++;
            } else if (strcmp(key, "TIME") == 0) {
                setLongField(build_class, key, val);
                count++;
            }
        }

        LOGI("%s: %d Build fields spoofed", process_name, count);

        env->DeleteLocalRef(build_class);
        env->DeleteLocalRef(version_class);
    }
};

REGISTER_ZYGISK_MODULE(TernakModule)
