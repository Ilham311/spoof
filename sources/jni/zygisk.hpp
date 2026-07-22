// zygisk.hpp — Zygisk API v4
// Kompatibel dengan Magisk Zygisk & Zygisk-Next.
// Lisensi: Apache-2.0 (mengikuti sumber Magisk).

#pragma once

#include <jni.h>
#include <cstdint>

#define ZYGISK_API_VERSION 4

namespace zygisk {

struct AppSpecializeArgs;
struct ServerSpecializeArgs;

namespace internal { struct api_table; }
using api_table = internal::api_table;

enum Option : int {
    FORCE_DENYLIST_UNMOUNT = 0,
    DLCLOSE_MODULE_LIBRARY = 1,
};

enum StateFlag : uint32_t {
    PROCESS_GRANTED_ROOT = (1u << 0),
    PROCESS_ON_DENYLIST  = (1u << 1),
};

class Api;

class ModuleBase {
public:
    virtual ~ModuleBase() = default;
    virtual void onLoad([[maybe_unused]] Api *api, [[maybe_unused]] JNIEnv *env) {}
    virtual void preAppSpecialize([[maybe_unused]] AppSpecializeArgs *args) {}
    virtual void postAppSpecialize([[maybe_unused]] const AppSpecializeArgs *args) {}
    virtual void preServerSpecialize([[maybe_unused]] ServerSpecializeArgs *args) {}
    virtual void postServerSpecialize([[maybe_unused]] const ServerSpecializeArgs *args) {}
};

struct AppSpecializeArgs {
    jint         &uid;
    jint         &gid;
    jintArray    &gids;
    jint         &runtime_flags;
    jobjectArray &rlimits;
    jint         &mount_external;
    jstring      &se_info;
    jstring      &nice_name;
    jstring      &instruction_set;
    jstring      &app_data_dir;

    // Nullable — hanya tersedia di API level tertentu
    jintArray    *const fds_to_ignore;
    jboolean     *const is_child_zygote;
    jboolean     *const is_top_app;
    jobjectArray *const pkg_data_info_list;
    jobjectArray *const whitelisted_data_info_list;
    jboolean     *const mount_data_dirs;
    jboolean     *const mount_storage_dirs;
};

struct ServerSpecializeArgs {
    jint      &uid;
    jint      &gid;
    jintArray &gids;
    jint      &runtime_flags;
    jlong     &permitted_capabilities;
    jlong     &effective_capabilities;
};

class Api {
public:
    int  connectCompanion();
    int  getModuleDir();
    void setOption(Option opt);
    uint32_t getFlags();

    // PLT hook (untuk hook symbol native, opsional)
    void pltHookRegister(const char *regex, const char *symbol, void *newFunc, void **oldFunc);
    bool pltHookCommit();
    int  pltHookExclude(const char *regex, const char *symbol);

private:
    api_table *tbl;
    friend bool zygisk_internal_register_module(api_table *, ModuleBase *);
};

} // namespace zygisk

// Bridge yang di-inject oleh Zygisk loader saat modul di-dlopen
extern "C" [[gnu::visibility("default")]] [[maybe_unused]]
void zygisk_module_entry(zygisk::api_table *, JNIEnv *);

extern "C" [[gnu::visibility("default")]] [[maybe_unused]]
void zygisk_companion_entry(int);

extern "C" [[gnu::weak]]
bool zygisk_internal_register_module(zygisk::api_table *, zygisk::ModuleBase *);

#define REGISTER_ZYGISK_MODULE(clazz)                                         \
    [[gnu::visibility("default")]] extern "C"                                 \
    void zygisk_module_entry(zygisk::api_table *table, JNIEnv *env) {         \
        static clazz _z_module;                                               \
        static zygisk::Api _z_api;                                            \
        if (!zygisk_internal_register_module) return;                         \
        if (!zygisk_internal_register_module(table, &_z_module)) return;      \
        _z_module.onLoad(&_z_api, env);                                       \
    }

#define REGISTER_ZYGISK_COMPANION(func)                                       \
    [[gnu::visibility("default")]] extern "C"                                 \
    void zygisk_companion_entry(int client) { func(client); }
