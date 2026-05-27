/*
 * [LEGACY] This is a raw dlopen prototype for testing Gambatte ROM loading.
 * It does NOT use the shared CoreLoader class and is superseded by LibretroEngine integration tests.
 *
 * Gambatte ROM 加载和运行测试
 * 测试完整的游戏加载流程
 */

#include <dlfcn.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <cstring>
#include <vector>
#include <rawfile/raw_file_manager.h>
#include "core/libretro/libretro.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD061
#define LOG_TAG "GambatteROMTest"
#undef LOG_FLOW
#define LOG_FLOW "Test"
#include "common/log_prefix.h"

// Libretro 函数指针类型
typedef void (*retro_init_t)(void);
typedef void (*retro_deinit_t)(void);
typedef unsigned (*retro_api_version_t)(void);
typedef void (*retro_get_system_info_t)(struct retro_system_info *info);
typedef void (*retro_get_system_av_info_t)(struct retro_system_av_info *info);
typedef void (*retro_set_environment_t)(retro_environment_t);
typedef void (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void (*retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void (*retro_set_input_state_t)(retro_input_state_t);
typedef bool (*retro_load_game_t)(const struct retro_game_info *game);
typedef void (*retro_unload_game_t)(void);
typedef void (*retro_run_t)(void);
typedef void (*retro_reset_t)(void);

// 全局统计数据
static int g_frame_count = 0;
static int g_video_callback_count = 0;
static int g_audio_callback_count = 0;

// 视频回调
static void VideoCallback(const void *data, unsigned width, unsigned height, size_t pitch) {
    g_video_callback_count++;
    if (g_video_callback_count <= 3 || g_video_callback_count % 20 == 0) {
        LOGF(LOG_INFO, "  视频帧 %{public}d: %{public}ux%{public}u, pitch=%{public}zu", 
                   g_video_callback_count, width, height, pitch);
    }
}

// 音频回调
static size_t AudioBatchCallback(const int16_t *data, size_t frames) {
    g_audio_callback_count++;
    if (g_audio_callback_count <= 3 || g_audio_callback_count % 20 == 0) {
        LOGF(LOG_INFO, "  音频数据 %{public}d: %{public}zu frames", 
                   g_audio_callback_count, frames);
    }
    return frames;
}

// 输入轮询回调（空实现）
static void InputPollCallback(void) {
    // 空实现
}

// 输入状态回调（空实现）
static int16_t InputStateCallback(unsigned port, unsigned device, unsigned index, unsigned id) {
    return 0; // 没有输入
}

// 测试 Gambatte ROM 加载和运行
static napi_value TestGambatteROM(napi_env env, napi_callback_info info) {
    LOGF(LOG_INFO, "=== 开始测试 Gambatte ROM 加载和运行 ===");
    
    // 获取参数（核心路径、ROM 文件名、ResourceManager）
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        LOGF(LOG_ERROR, " 缺少参数（需要核心路径、ROM 文件名、ResourceManager）");
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 获取核心路径
    size_t core_path_size;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &core_path_size);
    char* core_path = new char[core_path_size + 1];
    napi_get_value_string_utf8(env, args[0], core_path, core_path_size + 1, &core_path_size);
    
    // 获取 ROM 文件名（rawfile 相对路径）
    size_t rom_filename_size;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &rom_filename_size);
    char* rom_filename = new char[rom_filename_size + 1];
    napi_get_value_string_utf8(env, args[1], rom_filename, rom_filename_size + 1, &rom_filename_size);
    
    LOGF(LOG_INFO, "核心路径: %{public}s", core_path);
    LOGF(LOG_INFO, "ROM 文件名: %{public}s", rom_filename);
    
    // 重置统计
    g_frame_count = 0;
    g_video_callback_count = 0;
    g_audio_callback_count = 0;
    
    // 步骤 1: 加载核心
    LOGF(LOG_INFO, "步骤 1: 加载核心...");
    void* handle = dlopen(core_path, RTLD_LAZY);
    if (!handle) {
        LOGF(LOG_ERROR, " dlopen 失败: %{public}s", dlerror());
        delete[] core_path;
        delete[] rom_filename;
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    LOGF(LOG_INFO, " 核心加载成功");
    
    // 获取函数指针
    retro_init_t retro_init = (retro_init_t)dlsym(handle, "retro_init");
    retro_deinit_t retro_deinit = (retro_deinit_t)dlsym(handle, "retro_deinit");
    retro_set_environment_t retro_set_environment = (retro_set_environment_t)dlsym(handle, "retro_set_environment");
    retro_set_video_refresh_t retro_set_video_refresh = (retro_set_video_refresh_t)dlsym(handle, "retro_set_video_refresh");
    retro_set_audio_sample_batch_t retro_set_audio_sample_batch = (retro_set_audio_sample_batch_t)dlsym(handle, "retro_set_audio_sample_batch");
    retro_set_input_poll_t retro_set_input_poll = (retro_set_input_poll_t)dlsym(handle, "retro_set_input_poll");
    retro_set_input_state_t retro_set_input_state = (retro_set_input_state_t)dlsym(handle, "retro_set_input_state");
    retro_load_game_t retro_load_game = (retro_load_game_t)dlsym(handle, "retro_load_game");
    retro_unload_game_t retro_unload_game = (retro_unload_game_t)dlsym(handle, "retro_unload_game");
    retro_run_t retro_run = (retro_run_t)dlsym(handle, "retro_run");
    retro_get_system_av_info_t retro_get_system_av_info = (retro_get_system_av_info_t)dlsym(handle, "retro_get_system_av_info");
    
    // 步骤 2: 设置 Environment 回调
    LOGF(LOG_INFO, "步骤 2: 设置回调...");
    auto env_callback = [](unsigned cmd, void* data) -> bool {
        switch (cmd) {
            case RETRO_ENVIRONMENT_SET_ROTATION:
                LOGF(LOG_INFO, "  ENV: SET_ROTATION");
                return true;
            
            case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
                if (data) {
                    const char** dir = (const char**)data;
                    *dir = "/data/storage/el1/bundle/system";
                    LOGF(LOG_INFO, "  ENV: GET_SYSTEM_DIRECTORY -> %{public}s", *dir);
                }
                return true;
            
            case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
                if (data) {
                    ::retro_pixel_format* fmt = (::retro_pixel_format*)data;
                    LOGF(LOG_INFO, "  ENV: SET_PIXEL_FORMAT = %{public}d", *fmt);
                    // Gambatte 支持 XRGB8888 和 RGB565
                    return (*fmt == ::RETRO_PIXEL_FORMAT_XRGB8888 || *fmt == ::RETRO_PIXEL_FORMAT_RGB565);
                }
                return false;
            
            case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
                LOGF(LOG_INFO, "  ENV: SET_INPUT_DESCRIPTORS");
                return true;
            
            case RETRO_ENVIRONMENT_SET_VARIABLES:
                LOGF(LOG_INFO, "  ENV: SET_VARIABLES");
                return true;
            
            case RETRO_ENVIRONMENT_GET_VARIABLE:
                LOGF(LOG_INFO, "  ENV: GET_VARIABLE");
                return false;
            
            case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
                if (data) {
                    const char** dir = (const char**)data;
                    *dir = "/data/storage/el2/base/haps/entry/files/saves";
                    LOGF(LOG_INFO, "  ENV: GET_SAVE_DIRECTORY -> %{public}s", *dir);
                }
                return true;
            
            case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
                LOGF(LOG_INFO, "  ENV: SET_SUPPORT_NO_GAME");
                return true;
            
            case RETRO_ENVIRONMENT_GET_CAN_DUPE:
                if (data) {
                    bool* can_dupe = (bool*)data;
                    *can_dupe = true;
                    LOGF(LOG_INFO, "  ENV: GET_CAN_DUPE -> true");
                }
                return true;
            
            default:
                LOGF(LOG_INFO, "  ENV: Unhandled command %{public}u", cmd);
                return false;
        }
    };
    retro_set_environment(+env_callback);
    
    // 设置视频回调
    retro_set_video_refresh(VideoCallback);
    
    // 设置音频回调
    retro_set_audio_sample_batch(AudioBatchCallback);
    
    // 设置输入回调
    retro_set_input_poll(InputPollCallback);
    retro_set_input_state(InputStateCallback);
    
    LOGF(LOG_INFO, " 所有回调已设置");
    
    // 步骤 3: 初始化核心
    LOGF(LOG_INFO, "步骤 3: 初始化核心...");
    retro_init();
    LOGF(LOG_INFO, " retro_init() 成功");
    
    // 步骤 4: 初始化 ResourceManager 并读取 ROM 文件
    LOGF(LOG_INFO, "步骤 4: 读取 ROM 文件...");
    
    // 初始化 Native ResourceManager
    NativeResourceManager* nativeResourceManager = OH_ResourceManager_InitNativeResourceManager(env, args[2]);
    if (!nativeResourceManager) {
        LOGF(LOG_ERROR, " 初始化 ResourceManager 失败");
        retro_deinit();
        dlclose(handle);
        delete[] core_path;
        delete[] rom_filename;
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 打开 rawfile
    RawFile* rawFile = OH_ResourceManager_OpenRawFile(nativeResourceManager, rom_filename);
    if (!rawFile) {
        LOGF(LOG_ERROR, " 无法打开 ROM 文件: %{public}s", rom_filename);
        OH_ResourceManager_ReleaseNativeResourceManager(nativeResourceManager);
        retro_deinit();
        dlclose(handle);
        delete[] core_path;
        delete[] rom_filename;
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    // 获取文件大小
    long rom_size = OH_ResourceManager_GetRawFileSize(rawFile);
    LOGF(LOG_INFO, "ROM 文件大小: %{public}ld bytes", rom_size);
    
    // 读取文件内容
    std::vector<uint8_t> rom_data(rom_size);
    int bytes_read = OH_ResourceManager_ReadRawFile(rawFile, rom_data.data(), rom_size);
    
    // 关闭文件
    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(nativeResourceManager);
    
    if (bytes_read != rom_size) {
        LOGF(LOG_ERROR, " 读取 ROM 文件失败: 期望 %{public}ld bytes, 实际 %{public}d bytes", rom_size, bytes_read);
        retro_deinit();
        dlclose(handle);
        delete[] core_path;
        delete[] rom_filename;
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    
    LOGF(LOG_INFO, " ROM 文件读取成功: %{public}zu bytes", rom_data.size());
    
    // 步骤 5: 检查核心是否需要完整路径
    LOGF(LOG_INFO, "步骤 5: 检查系统信息...");
    retro_get_system_info_t retro_get_system_info_func = (retro_get_system_info_t)dlsym(handle, "retro_get_system_info");
    struct retro_system_info sys_info;
    retro_get_system_info_func(&sys_info);
    
    LOGF(LOG_INFO, "  need_fullpath: %{public}d", sys_info.need_fullpath);
    LOGF(LOG_INFO, "  block_extract: %{public}d", sys_info.block_extract);
    
    // 步骤 6: 加载 ROM
    LOGF(LOG_INFO, "步骤 6: 加载 ROM...");
    struct retro_game_info game_info;
    
    if (sys_info.need_fullpath) {
        // 核心需要完整路径，但我们无法提供文件系统路径（rawfile 限制）
        LOGF(LOG_ERROR, " 核心需要完整路径，但 rawfile 无法提供文件系统路径");
        LOGF(LOG_INFO, "  解决方案：需要将 ROM 复制到沙箱目录");
        game_info.path = nullptr;  // 尝试传递 NULL
        game_info.data = rom_data.data();
        game_info.size = rom_data.size();
    } else {
        // 核心接受内存数据
        game_info.path = rom_filename;  // 可以是相对路径或 NULL
        game_info.data = rom_data.data();
        game_info.size = rom_data.size();
    }
    game_info.meta = nullptr;
    
    LOGF(LOG_INFO, "  game_info.path: %{public}s", game_info.path ? game_info.path : "NULL");
    LOGF(LOG_INFO, "  game_info.data: %{public}p", game_info.data);
    LOGF(LOG_INFO, "  game_info.size: %{public}zu", game_info.size);
    
    if (!retro_load_game(&game_info)) {
        LOGF(LOG_ERROR, " retro_load_game() 失败");
        retro_deinit();
        dlclose(handle);
        delete[] core_path;
        delete[] rom_filename;
        napi_value result;
        napi_get_boolean(env, false, &result);
        return result;
    }
    LOGF(LOG_INFO, " retro_load_game() 成功");
    
    // 步骤 6: 获取 AV 信息
    LOGF(LOG_INFO, "步骤 6: 获取 AV 信息...");
    struct retro_system_av_info av_info;
    retro_get_system_av_info(&av_info);
    LOGF(LOG_INFO, "  视频: %{public}ux%{public}u @ %.2f FPS",
               av_info.geometry.base_width, av_info.geometry.base_height,
               av_info.timing.fps);
    LOGF(LOG_INFO, "  音频: %.2f Hz", av_info.timing.sample_rate);
    
    // 步骤 7: 运行 60 帧
    LOGF(LOG_INFO, "步骤 7: 运行 60 帧...");
    for (int i = 0; i < 60; i++) {
        retro_run();
        g_frame_count++;
    }
    LOGF(LOG_INFO, " 运行 60 帧成功");
    LOGF(LOG_INFO, "  总帧数: %{public}d", g_frame_count);
    LOGF(LOG_INFO, "  视频回调: %{public}d 次", g_video_callback_count);
    LOGF(LOG_INFO, "  音频回调: %{public}d 次", g_audio_callback_count);
    
    // 步骤 8: 卸载 ROM
    LOGF(LOG_INFO, "步骤 8: 卸载 ROM...");
    retro_unload_game();
    LOGF(LOG_INFO, " retro_unload_game() 成功");
    
    // 步骤 9: 清理
    LOGF(LOG_INFO, "步骤 9: 清理...");
    retro_deinit();
    LOGF(LOG_INFO, " retro_deinit() 成功");
    
    dlclose(handle);
    LOGF(LOG_INFO, " dlclose 成功");
    
    delete[] core_path;
    delete[] rom_filename;
    
    // 总结
    LOGF(LOG_INFO, "=== Gambatte ROM 测试完成 ===");
    bool success = (g_video_callback_count > 0 && g_audio_callback_count > 0);
    LOGF(LOG_INFO, "结果: %{public}s", success ? " 全部通过" : " 部分失败");
    
    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

// 导出函数供主模块使用
void RegisterGambatteROMTestNapi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"testGambatteROM", nullptr, TestGambatteROM, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
