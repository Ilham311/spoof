/*
 * Copyright 2022-2023 John "topjohnwu" Wu
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <jni.h>
#include <stdint.h>

#define ZYGISK_API_VERSION 4

/*
 * Zygisk API v4
 */

namespace zygisk {

struct Api;
struct AppSpecializeArgs;
struct ServerSpecializeArgs;

enum Option : uint32_t {
    /**
     * Force Magisk's denylist unmount routine to run on this process.
     *
     * Setting this option only makes sense in preAppSpecialize.
     * The actual unmounting happens during app process specialization.
     *
     * Set this option when you want to hide Magisk and Zygisk from this process.
     */
    FORCE_DENYLIST_UNMOUNT = 0,

    /**
     * When this option is set, your module's library will be dlclose-ed after post[XXX]Specialize.
     *
     * Be aware that after dlclose-ing your module, all of your PLT hooks will be unregistered.
     */
    DLCLOSE_MODULE_LIBRARY = 1,
};

enum StateFlag : uint32_t {
    /**
     * The user has granted root access to this process
     */
    PROCESS_GRANTED_ROOT = (1 << 0),

    /**
     * This process was added to the denylist
     */
    PROCESS_ON_DENYLIST = (1 << 1),
};

class ModuleBase {
public:
    /**
     * This method is called as soon as the module is loaded into the zygote process.
     *
     * @param api  a pointer to the Zygisk API. This pointer is valid throughout the whole lifecycle of the zygote process.
     * @param env  a pointer to the JNIEnv of the zygote process.
     */
    virtual void onLoad(Api *api, JNIEnv *env) {}

    /**
     * This method is called before the app process is specialized.
     *
     * @param args  a pointer to the AppSpecializeArgs. The structure is NOT valid after this method returns.
     */
    virtual void preAppSpecialize(AppSpecializeArgs *args) {}

    /**
     * This method is called after the app process is specialized.
     */
    virtual void postAppSpecialize(const AppSpecializeArgs *args) {}

    /**
     * This method is called before the system server process is specialized.
     *
     * @param args  a pointer to the ServerSpecializeArgs. The structure is NOT valid after this method returns.
     */
    virtual void preServerSpecialize(ServerSpecializeArgs *args) {}

    /**
     * This method is called after the system server process is specialized.
     */
    virtual void postServerSpecialize(const ServerSpecializeArgs *args) {}
};

struct AppSpecializeArgs {
    // Required arguments. These arguments are guaranteed to exist on all Android versions.
    int &uid;
    int &gid;
    jintArray &gids;
    int &runtime_flags;
    int &rlimits;
    int &mount_external;
    jstring &se_info;
    jstring &nice_name;
    jintArray &instruction_set;
    jstring &app_data_dir;

    // Optional arguments. Please check whether the pointer is null before dereferencing
    jboolean *is_top_app;
    jboolean *is_child_zygote;
    jobjectArray *pkg_data_info_list;
    jobjectArray *whitelisted_data_info_list;
    jboolean *mount_data_dirs;
    jboolean *mount_storage_dirs;
    jintArray *fds_to_ignore;
};

struct ServerSpecializeArgs {
    int &uid;
    int &gid;
    jintArray &gids;
    int &runtime_flags;
    jlong &permitted_capabilities;
    jlong &effective_capabilities;
};

struct Api {
    /**
     * Connect to a daemon process and get a file descriptor.
     *
     * The companion process is started by Magisk. You can use this file descriptor to communicate with the daemon process.
     * This process has the same privileges as the Magisk daemon (root).
     *
     * @return a file descriptor to the daemon process. Returns -1 if the connection failed.
     */
    virtual int connectCompanion() = 0;

    /**
     * Get the file descriptor of the module directory.
     *
     * This directory is strictly for the module's own usage, no other process has access to it.
     *
     * @return a file descriptor to the module directory. Returns -1 if the operation failed.
     */
    virtual int getModuleDir() = 0;

    /**
     * Set an option for the current process.
     *
     * @param opt  the option to set.
     */
    virtual void setOption(Option opt) = 0;

    /**
     * Get the state flags of the current process.
     *
     * @return a bitmask of StateFlag.
     */
    virtual uint32_t getFlags() = 0;

    /**
     * Hook a PLT entry in the current process.
     *
     * @param target_so_path   the path to the shared object to hook.
     * @param symbol           the name of the symbol to hook.
     * @param new_func         a pointer to the new function.
     * @param old_func         a pointer to a pointer where the original function address will be stored.
     */
    virtual void pltHookRegister(const char *target_so_path, const char *symbol, void *new_func, void **old_func) = 0;

    /**
     * Exclude a PLT entry from being hooked.
     *
     * @param target_so_path   the path to the shared object.
     * @param symbol           the name of the symbol to exclude.
     */
    virtual void pltHookExclude(const char *target_so_path, const char *symbol) = 0;

    /**
     * Commit all registered PLT hooks.
     *
     * @return true if all hooks are successfully committed.
     */
    virtual bool pltHookCommit() = 0;
};

} // namespace zygisk

extern "C" {

void zygisk_module_entry(zygisk::Api *api, JNIEnv *env);
void zygisk_companion_entry(int client);
__attribute__((weak)) void zygisk_internal_register_module(void *api, void *env, void *module);

}

#define REGISTER_ZYGISK_MODULE(clazz) \
void zygisk_module_entry(zygisk::Api *api, JNIEnv *env) { \
    zygisk_internal_register_module(api, env, new clazz()); \
}

#define REGISTER_ZYGISK_COMPANION(func) \
void zygisk_companion_entry(int client) { \
    func(client); \
}
