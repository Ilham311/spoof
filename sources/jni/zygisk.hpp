#pragma once

#include <jni.h>

namespace zygisk {

enum Option : int {
    FORCE_DENYLIST_UNMOUNT = 0,
    DLCLOSE_MODULE_LIBRARY = 1
};

enum StateFlag : uint32_t {
    PROCESS_GRANTED_ROOT = (1 << 0),
    PROCESS_ON_DENYLIST = (1 << 1)
};

struct AppSpecializeArgs {
    int &uid;
    int &gid;
    int *&gids;
    int &gids_count;
    int &runtime_flags;
    int *&rlimits;
    int &mount_external;
    const char *&se_info;
    const char *&nice_name;
    const char *&instruction_set;
    const char *&app_data_dir;
    const bool *is_top_app;
    const bool *is_child_zygote;
    const char *const *pkg_data_info_list;
    const char *const *whitelisted_data_info_list;
    const bool *mount_data_dirs;
    const bool *mount_storage_dirs;
    const int *fds_to_ignore;
};

struct ServerSpecializeArgs {
    int &uid;
    int &gid;
    int *&gids;
    int &gids_count;
    int &runtime_flags;
    int &permitted_capabilities;
    int &effective_capabilities;
};

class Api;

class ModuleBase {
public:
    virtual ~ModuleBase() = default;
    virtual void onLoad(Api *api, JNIEnv *env) {}
    virtual void preAppSpecialize(AppSpecializeArgs *args) {}
    virtual void postAppSpecialize(const AppSpecializeArgs *args) {}
    virtual void preServerSpecialize(ServerSpecializeArgs *args) {}
    virtual void postServerSpecialize(const ServerSpecializeArgs *args) {}
};

class Api {
public:
    virtual void connectCompanion(int fd) = 0;
    virtual int getModuleDir() = 0;
    virtual void setOption(Option opt) = 0;
    virtual uint32_t getFlags() = 0;
    virtual void pltHookRegister(const char *path, const char *symbol, void *new_func, void **old_func) = 0;
    virtual void pltHookExclude(const char *path, const char *symbol) = 0;
    virtual bool pltHookCommit() = 0;
};

} // namespace zygisk

extern "C" {
__attribute__((visibility("default"))) void zygisk_module_entry(int version, void *api, void *module);
__attribute__((visibility("default"))) void zygisk_companion_entry(int version, void *api, void *companion);
__attribute__((visibility("default"), weak)) void zygisk_internal_register_module(void *module);
}

#define REGISTER_ZYGISK_MODULE(clazz) \
void zygisk_internal_register_module(void *module) { \
    *(void **)module = new clazz(); \
}

#define REGISTER_ZYGISK_COMPANION(func) \
void zygisk_companion_entry(int version, void *api, void *companion) { \
    *(void **)companion = (void *)(func); \
}
