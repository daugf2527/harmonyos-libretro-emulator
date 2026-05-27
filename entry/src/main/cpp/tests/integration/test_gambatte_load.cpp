/*
 * [LEGACY] This is a raw dlopen prototype for testing Gambatte loading.
 * It does NOT use the shared CoreLoader class and is superseded by CoreLoader unit tests.
 *
 * Gambatte 核心加载测试
 * 快速验证 dlopen 和函数指针获取
 */

#include <dlfcn.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include "core/libretro/libretro.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD060
#define LOG_TAG "GambatteTest"
#undef LOG_FLOW
#define LOG_FLOW "Test"
#include "common/log_prefix.h"

// Libretro 函数指针类型
typedef void (*retro_init_t)(void);
typedef void (*retro_deinit_t)(void);
typedef unsigned (*retro_api_version_t)(void);
typedef void (*retro_get_system_info_t)(struct retro_system_info *info);
typedef void (*retro_set_environment_t)(retro_environment_t);
typedef void (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void (*retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void (*retro_set_input_state_t)(retro_input_state_t);

// 测试 Gambatte 核心加载
static napi_value TestGambatteLoad(napi_env env, napi_callback_info info) {
    LOGF(LOG_INFO, "=== 开始测试 Gambatte 核心加载 ===");
    
    // 获取参数（核心路径）
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        LOGF(LOG_ERROR, " 缺少核心路径参数");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 获取核心路径
    size_t str_size;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
    char* core_path = new char[str_size + 1];
    napi_get_value_string_utf8(env, args[0], core_path, str_size + 1, &str_size);
    
    LOGF(LOG_INFO, "核心路径: %{public}s", core_path);
    
    // 步骤 1: dlopen 加载核心
    LOGF(LOG_INFO, "步骤 1: 尝试 dlopen 加载...");
    void* handle = dlopen(core_path, RTLD_LAZY);
    
    if (!handle) {
        const char* error = dlerror();
        LOGF(LOG_ERROR, " dlopen 失败: %{public}s", error ? error : "unknown");
        delete[] core_path;
        
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    LOGF(LOG_INFO, " dlopen 成功! handle = %{public}p", handle);
    
    // 步骤 2: 获取 API 版本
    LOGF(LOG_INFO, "步骤 2: 获取 API 版本...");
    retro_api_version_t retro_api_version = (retro_api_version_t)dlsym(handle, "retro_api_version");
    
    if (!retro_api_version) {
        LOGF(LOG_ERROR, " 获取 retro_api_version 失败");
        dlclose(handle);
        delete[] core_path;
        
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    unsigned api_version = retro_api_version();
    LOGF(LOG_INFO, " API 版本: %{public}u (期望: 1)", api_version);
    
    // 步骤 3: 获取系统信息
    LOGF(LOG_INFO, "步骤 3: 获取系统信息...");
    retro_get_system_info_t retro_get_system_info = 
        (retro_get_system_info_t)dlsym(handle, "retro_get_system_info");
    
    if (!retro_get_system_info) {
        LOGF(LOG_ERROR, " 获取 retro_get_system_info 失败");
        dlclose(handle);
        delete[] core_path;
        
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    struct retro_system_info system_info = {0};
    retro_get_system_info(&system_info);
    
    LOGF(LOG_INFO, " 系统信息:");
    LOGF(LOG_INFO, "  - 库名称: %{public}s", system_info.library_name ? system_info.library_name : "NULL");
    LOGF(LOG_INFO, "  - 库版本: %{public}s", system_info.library_version ? system_info.library_version : "NULL");
    LOGF(LOG_INFO, "  - 支持扩展名: %{public}s", system_info.valid_extensions ? system_info.valid_extensions : "NULL");
    LOGF(LOG_INFO, "  - 需要完整路径: %{public}d", system_info.need_fullpath);
    LOGF(LOG_INFO, "  - 阻止提取: %{public}d", system_info.block_extract);
    
    // 步骤 4: 检查所有必需的函数指针
    LOGF(LOG_INFO, "步骤 4: 检查所有必需的函数指针...");
    
    struct {
        const char* name;
        void* ptr;
    } functions[] = {
        {"retro_init", dlsym(handle, "retro_init")},
        {"retro_deinit", dlsym(handle, "retro_deinit")},
        {"retro_set_environment", dlsym(handle, "retro_set_environment")},
        {"retro_set_video_refresh", dlsym(handle, "retro_set_video_refresh")},
        {"retro_set_audio_sample", dlsym(handle, "retro_set_audio_sample")},
        {"retro_set_audio_sample_batch", dlsym(handle, "retro_set_audio_sample_batch")},
        {"retro_set_input_poll", dlsym(handle, "retro_set_input_poll")},
        {"retro_set_input_state", dlsym(handle, "retro_set_input_state")},
        {"retro_get_system_av_info", dlsym(handle, "retro_get_system_av_info")},
        {"retro_reset", dlsym(handle, "retro_reset")},
        {"retro_run", dlsym(handle, "retro_run")},
        {"retro_load_game", dlsym(handle, "retro_load_game")},
        {"retro_unload_game", dlsym(handle, "retro_unload_game")},
        {"retro_serialize_size", dlsym(handle, "retro_serialize_size")},
        {"retro_serialize", dlsym(handle, "retro_serialize")},
        {"retro_unserialize", dlsym(handle, "retro_unserialize")},
    };
    
    int success_count = 0;
    int total_count = sizeof(functions) / sizeof(functions[0]);
    
    for (int i = 0; i < total_count; i++) {
        if (functions[i].ptr) {
            LOGF(LOG_INFO, "   %{public}s: %{public}p", functions[i].name, functions[i].ptr);
            success_count++;
        } else {
            LOGF(LOG_ERROR, "   %{public}s: NULL", functions[i].name);
        }
    }
    
    LOGF(LOG_INFO, "函数指针检查: %{public}d/%{public}d 成功", success_count, total_count);
    
    // 步骤 5: 设置必要的回调（避免空指针）
    LOGF(LOG_INFO, "步骤 5: 设置必要的回调...");
    
    // 设置 environment 回调（参考 game2048_native_app.cpp 的实现）
    retro_set_environment_t retro_set_environment = 
        (retro_set_environment_t)dlsym(handle, "retro_set_environment");
    if (retro_set_environment) {
        // 提供一个基础的 environment 回调（处理必需的命令）
        auto env_callback = [](unsigned cmd, void* data) -> bool {
            switch (cmd) {
                // 1. 设置旋转
                case RETRO_ENVIRONMENT_SET_ROTATION:
                    LOGF(LOG_INFO, "  ENV: SET_ROTATION");
                    return true;
                
                // 9. 获取系统目录
                case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
                    if (data) {
                        const char** dir = (const char**)data;
                        *dir = "/data/storage/el1/bundle/system";
                        LOGF(LOG_INFO, "  ENV: GET_SYSTEM_DIRECTORY");
                    }
                    return true;
                
                // 10. 设置像素格式
                case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
                    if (data) {
                        ::retro_pixel_format* fmt = (::retro_pixel_format*)data;
                        LOGF(LOG_INFO, "  ENV: SET_PIXEL_FORMAT = %{public}d", *fmt);
                        return (*fmt == ::RETRO_PIXEL_FORMAT_XRGB8888);
                    }
                    return false;
                
                // 11. 设置输入描述符
                case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
                    LOGF(LOG_INFO, "  ENV: SET_INPUT_DESCRIPTORS");
                    return true;
                
                // 16. 获取变量
                case RETRO_ENVIRONMENT_GET_VARIABLE:
                    LOGF(LOG_INFO, "  ENV: GET_VARIABLE");
                    return false;
                
                // 17. 设置变量
                case RETRO_ENVIRONMENT_SET_VARIABLES:
                    LOGF(LOG_INFO, "  ENV: SET_VARIABLES");
                    return true;
                
                // 19. 获取存档目录
                case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
                    if (data) {
                        const char** dir = (const char**)data;
                        *dir = "/data/storage/el2/base/haps/entry/files/saves";
                        LOGF(LOG_INFO, "  ENV: GET_SAVE_DIRECTORY");
                    }
                    return true;
                
                default:
                    LOGF(LOG_INFO, "  ENV: Unhandled command %{public}u", cmd);
                    return false;
            }
        };
        retro_set_environment(+env_callback);
        LOGF(LOG_INFO, " Environment 回调已设置");
    }
    
    // 步骤 6: 测试初始化
    LOGF(LOG_INFO, "步骤 6: 测试初始化...");
    retro_init_t retro_init = (retro_init_t)dlsym(handle, "retro_init");
    
    if (retro_init) {
        LOGF(LOG_INFO, "调用 retro_init()...");
        retro_init();
        LOGF(LOG_INFO, " retro_init() 成功");
        
        // 清理
        retro_deinit_t retro_deinit = (retro_deinit_t)dlsym(handle, "retro_deinit");
        if (retro_deinit) {
            LOGF(LOG_INFO, "调用 retro_deinit()...");
            retro_deinit();
            LOGF(LOG_INFO, " retro_deinit() 成功");
        }
    }
    
    // 步骤 7: 关闭核心
    LOGF(LOG_INFO, "步骤 7: 关闭核心...");
    dlclose(handle);
    LOGF(LOG_INFO, " dlclose 成功");
    
    delete[] core_path;
    
    // 总结
    LOGF(LOG_INFO, "=== Gambatte 核心加载测试完成 ===");
    LOGF(LOG_INFO, "结果: %{public}s", (success_count == total_count) ? " 全部通过" : " 部分失败");
    
    napi_value result;
    napi_get_boolean(env, success_count == total_count, &result);
    return result;
}

// 导出函数供主模块使用
void RegisterGambatteTestNapi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"testGambatteLoad", nullptr, TestGambatteLoad, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
