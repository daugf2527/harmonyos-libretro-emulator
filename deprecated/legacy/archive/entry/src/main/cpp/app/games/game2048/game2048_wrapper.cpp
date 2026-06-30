/*
 * Phase 3.2 - Game2048 Wrapper
 * 完整的 Libretro 游戏包装器,实现视频/音频/输入桥接
 *
 * 参考:
 * - https://www.virtualdub.org/blog2/entry_190.html (Pitch 处理)
 * - https://www.retroreversing.com/CreateALibRetroFrontEndInRust (Libretro
 * 前端实现)
 * - /Users/asd/NativeSoIntegration (鸿蒙官方示例)
 */

#include "game2048_wrapper.h"
#include "core/libretro/retro_common.h" // 官方 Libretro API 定义 (包含所有回调类型)
#include "hilog/log.h"
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD002 // 应用域
#define LOG_TAG "Game2048"

// ========== Libretro 函数指针类型 ==========
// 注意: 官方 libretro.h 已定义所有回调类型 (retro_init_t, retro_environment_t
// 等)
//       我们只需确保包含 retro_common.h

// ========== Libretro 注册函数类型定义 ==========
// 官方 libretro.h 有时候不定义 pointer typedefs，如果 retro_common.h
// 定义了就无需再定义。 根据之前的 grep 结果，retro_common.h
// 已经补充了这些定义。 所以这里全部注释掉或删除。

// ========== 全局变量 ==========
// 注意: 变量名添加 _ptr 后缀以避免与官方 libretro.h 中的函数声明冲突
static void *g_libretro_handle = nullptr;
static retro_init_t retro_init_ptr = nullptr;
static retro_deinit_t retro_deinit_ptr = nullptr;
static retro_reset_t retro_reset_ptr = nullptr;
static retro_run_t retro_run_ptr = nullptr;
static retro_api_version_t retro_api_version_ptr = nullptr;
static retro_load_game_t retro_load_game_ptr = nullptr;
static retro_unload_game_t retro_unload_game_ptr = nullptr;

// 回调注册函数指针
static retro_set_environment_t retro_set_environment_ptr = nullptr;
static retro_set_video_refresh_t retro_set_video_refresh_ptr = nullptr;
static retro_set_audio_sample_t retro_set_audio_sample_ptr = nullptr;
static retro_set_audio_sample_batch_t retro_set_audio_sample_batch_ptr =
    nullptr;
static retro_set_input_poll_t retro_set_input_poll_ptr = nullptr;
static retro_set_input_state_t retro_set_input_state_ptr = nullptr;

// ========== 视频帧缓冲区 ==========
static uint8_t *g_frame_buffer = nullptr;
static size_t g_frame_buffer_size = 0;
static int g_frame_width = 0;
static int g_frame_height = 0;
static bool g_frame_updated = false;

// ========== 输入状态存储 ==========
// 支持16个按键 (Libretro 标准)
static bool g_input_state[16] = {false};

// ========== 视频回调函数 ==========
/**
 * Libretro 视频刷新回调
 *
 * @param data   像素数据指针 (XRGB8888 格式)
 * @param width  帧宽度 (像素)
 * @param height 帧高度 (像素)
 * @param pitch  每行字节数 (stride)
 *
 * 参考: https://www.virtualdub.org/blog2/entry_190.html
 * 关键: 必须处理 pitch != width*4 的情况!
 */
static void video_refresh_callback(const void *data, unsigned width,
                                   unsigned height, size_t pitch) {
  static int frame_count = 0;
  static int null_count = 0;

  frame_count++;

  // Phase 3.5: 添加详细日志
  if (!data) {
    null_count++;
    if (frame_count % 30 == 0) {
      OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
          "⚠️ [Canvas] video_refresh: data=NULL (总计: %{public}d/%{public}d)",
          null_count, frame_count);
    }
    return;
  }

  // 每 30 帧打印一次日志
  if (frame_count % 30 == 0) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "🎨 [Canvas] video_refresh: %{public}ux%{public}u, pitch=%{public}zu "
        "(理论=%{public}u), 有效帧: %{public}d/%{public}d",
        width, height, pitch, width * 4, frame_count - null_count, frame_count);
  }

  // 首帧详细调试
  if (data && frame_count == 1) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "========== Native 首帧调试信息 ==========");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "帧尺寸: %{public}ux%{public}u", width, height);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Pitch: %{public}zu 字节/行", pitch);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "理论行宽: %{public}u 字节/行 (width * 4)", width * 4);

    if (pitch != width * 4) {
      OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ Pitch 不匹配! 差异=%{public}d 字节",
                  (int)(pitch - width * 4));
    } else {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Pitch 匹配,可以直接复制");
    }

    // 打印前 64 字节的原始数据
    const uint8_t *bytes = static_cast<const uint8_t *>(data);
    char hex[512] = {0};
    int offset = 0;
    for (int i = 0; i < 64 && offset < 500; i++) {
      offset += snprintf(hex + offset, sizeof(hex) - offset, "%02x ", bytes[i]);
      if ((i + 1) % 16 == 0) {
        offset += snprintf(hex + offset, sizeof(hex) - offset, "\n");
      }
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Native 原始数据前64字节:\n%{public}s", hex);

    // 打印关键位置的像素值
    const uint32_t *pixels = static_cast<const uint32_t *>(data);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "--- Native 像素值 (32位整数) ---");
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "左上角[0]: 0x%{public}08x", pixels[0]);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "第1行第10列[10]: 0x%{public}08x", pixels[10]);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "第1行中间[%{public}u]: 0x%{public}08x", width / 2,
                pixels[width / 2]);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "========================================");
  }

  if (width == 0 || height == 0) {
    return;
  }

  // 分配或重新分配帧缓冲区
  size_t required_size = width * height * 4; // XRGB8888 = 4 bytes per pixel
  if (g_frame_buffer_size < required_size) {
    delete[] g_frame_buffer;
    g_frame_buffer = new uint8_t[required_size];
    g_frame_buffer_size = required_size;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "帧缓冲区已分配: %{public}zu 字节", required_size);
  }

  // ========== 关键: 处理 pitch 不匹配的情况 ==========
  // 参考: https://www.virtualdub.org/blog2/entry_190.html
  // "You can't just memcpy() across the image"

  const uint8_t *src = static_cast<const uint8_t *>(data);
  uint8_t *dst = g_frame_buffer;

  if (pitch == width * 4) {
    // ✅ Pitch 匹配 - 可以直接复制整块数据
    memcpy(dst, src, required_size);
  } else {
    // ⚠️ Pitch 不匹配 - 必须逐行复制
    // 原因: pitch 包含填充字节,直接复制会导致图像错乱
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
        "⚠️ Pitch 不匹配! pitch=%{public}zu, width*4=%{public}u, 使用逐行复制",
        pitch, width * 4);

    size_t row_bytes = width * 4; // 每行实际像素数据
    for (unsigned y = 0; y < height; y++) {
      memcpy(dst + y * row_bytes, // 目标: 紧凑排列
             src + y * pitch,     // 源: 使用 pitch 跳过填充
             row_bytes);          // 只复制像素数据
    }
  }

  g_frame_width = width;
  g_frame_height = height;
  g_frame_updated = true;
}

// ========== Environment 回调函数 ==========
/**
 * Libretro Environment 回调
 * 处理核心的各种请求 (像素格式、系统目录等)
 */
static bool environment_callback(unsigned cmd, void *data) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "environment callback: cmd=%{public}u", cmd);

  // RETRO_ENVIRONMENT_SET_PIXEL_FORMAT = 10
  if (cmd == 10) {
    unsigned pixel_format = *(unsigned *)data;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "核心请求像素格式: %{public}u (0=RGB1555, 1=XRGB8888, 2=RGB565)",
        pixel_format);

    // 我们只支持 XRGB8888 (值为 1)
    if (pixel_format == 1) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 接受 XRGB8888 像素格式");
      return true;
    } else {
      OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ 不支持的像素格式: %{public}u", pixel_format);
      return false;
    }
  }

  // 其他命令暂时返回 false
  return false;
}

// ========== 输入回调函数 ==========
/**
 * 输入轮询回调 - 空实现
 */
static void input_poll_callback(void) {
  // 空实现 - 输入状态由 ArkTS 侧通过 setInput() 更新
}

/**
 * 输入状态回调
 *
 * @param port   控制器端口 (通常为 0)
 * @param device 设备类型 (1 = RETRO_DEVICE_JOYPAD)
 * @param index  子设备索引 (通常为 0)
 * @param id     按键 ID (0-15)
 *
 * 按键 ID 映射:
 * 0=B, 1=Y, 2=Select, 3=Start, 4=Up, 5=Down, 6=Left, 7=Right, 8=A, 9=X
 */
static int16_t input_state_callback(unsigned port, unsigned device,
                                    unsigned index, unsigned id) {
  if (id < 16) {
    return g_input_state[id] ? 1 : 0;
  }
  return 0;
}

// ========== 音频回调函数 ==========
/**
 * 单个音频样本回调 - 空实现
 */
static void audio_sample_callback(int16_t left, int16_t right) {
  // 空实现 - 2048 核心没有音频
}

/**
 * 批量音频样本回调 - 空实现
 */
static size_t audio_sample_batch_callback(const int16_t *data, size_t frames) {
  // 空实现 - 2048 核心没有音频
  return frames;
}

// ========== NAPI 函数实现 ==========

/**
 * 初始化游戏
 *
 * @param soPath Libretro 核心路径
 * @return boolean 是否成功
 */
static napi_value InitGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "=== InitGame 被调用 ===");

  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  // 获取 SO 库路径
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *so_path = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], so_path, str_size + 1, &str_size);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "加载 SO 库: %{public}s", so_path);

  // 加载 SO 库
  g_libretro_handle = dlopen(so_path, RTLD_LAZY);
  delete[] so_path;

  if (!g_libretro_handle) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "dlopen 失败: %{public}s", dlerror());
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "SO 库加载成功");

  // 获取核心函数指针
  retro_init_ptr = (retro_init_t)dlsym(g_libretro_handle, "retro_init");
  retro_deinit_ptr = (retro_deinit_t)dlsym(g_libretro_handle, "retro_deinit");
  retro_reset_ptr = (retro_reset_t)dlsym(g_libretro_handle, "retro_reset");
  retro_run_ptr = (retro_run_t)dlsym(g_libretro_handle, "retro_run");
  retro_api_version_ptr =
      (retro_api_version_t)dlsym(g_libretro_handle, "retro_api_version");
  retro_load_game_ptr =
      (retro_load_game_t)dlsym(g_libretro_handle, "retro_load_game");
  retro_unload_game_ptr =
      (retro_unload_game_t)dlsym(g_libretro_handle, "retro_unload_game");

  // 获取回调注册函数指针
  retro_set_environment_ptr = (retro_set_environment_t)dlsym(
      g_libretro_handle, "retro_set_environment");
  retro_set_video_refresh_ptr = (retro_set_video_refresh_t)dlsym(
      g_libretro_handle, "retro_set_video_refresh");
  retro_set_audio_sample_ptr = (retro_set_audio_sample_t)dlsym(
      g_libretro_handle, "retro_set_audio_sample");
  retro_set_audio_sample_batch_ptr = (retro_set_audio_sample_batch_t)dlsym(
      g_libretro_handle, "retro_set_audio_sample_batch");
  retro_set_input_poll_ptr =
      (retro_set_input_poll_t)dlsym(g_libretro_handle, "retro_set_input_poll");
  retro_set_input_state_ptr = (retro_set_input_state_t)dlsym(
      g_libretro_handle, "retro_set_input_state");

  // 检查必需的函数指针
  if (!retro_init_ptr || !retro_run_ptr || !retro_set_environment_ptr) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Canvas: 获取函数指针失败");
    dlclose(g_libretro_handle);
    g_libretro_handle = nullptr;

    // 清空所有函数指针
    retro_init_ptr = nullptr;
    retro_deinit_ptr = nullptr;
    retro_reset_ptr = nullptr;
    retro_run_ptr = nullptr;
    retro_api_version_ptr = nullptr;
    retro_load_game_ptr = nullptr;
    retro_unload_game_ptr = nullptr;

    retro_set_environment_ptr = nullptr;
    retro_set_video_refresh_ptr = nullptr;
    retro_set_audio_sample_ptr = nullptr;
    retro_set_audio_sample_batch_ptr = nullptr;
    retro_set_input_poll_ptr = nullptr;
    retro_set_input_state_ptr = nullptr;

    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "函数指针获取成功");

  // 设置回调函数 (使用函数指针，类型安全)
  retro_set_environment_ptr(environment_callback);
  retro_set_video_refresh_ptr(video_refresh_callback);
  retro_set_input_poll_ptr(input_poll_callback);
  retro_set_input_state_ptr(input_state_callback);
  retro_set_audio_sample_ptr(audio_sample_callback);
  retro_set_audio_sample_batch_ptr(audio_sample_batch_callback);

  // 初始化 libretro
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_init");
  retro_init_ptr();

  // 加载游戏 (2048 不需要 ROM,传 nullptr)
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_load_game");
  bool loaded = retro_load_game_ptr(nullptr);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "游戏初始化完成: %{public}d", loaded);

  napi_value result;
  napi_get_boolean(env, loaded, &result);
  return result;
}

/**
 * 运行一帧
 *
 * @return FrameData | null 帧数据对象
 */
static napi_value RunFrame(napi_env env, napi_callback_info info) {
  if (!retro_run_ptr) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "游戏未初始化");
    return nullptr;
  }

  // Phase 3.5: 添加详细日志来追踪 Canvas 模式
  static int run_count = 0;
  static auto last_time = std::chrono::steady_clock::now();
  run_count++;

  if (run_count % 30 == 1) { // 每 30 帧打印一次
    auto now = std::chrono::steady_clock::now();
    auto delta =
        std::chrono::duration_cast<std::chrono::milliseconds>(now - last_time)
            .count();
    float fps = delta > 0 ? (30000.0f / delta) : 0.0f;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                "🎮 [Canvas] retro_run() 调用 #%{public}d, 实际FPS: %.1f, "
                "间隔: %{public}lldms",
                run_count, fps, (long long)delta);
    last_time = now;
  }

  g_frame_updated = false;
  retro_run_ptr();

  if (run_count % 30 == 1) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "✅ [Canvas] retro_run() 完成 #%{public}d, frame_updated=%{public}d",
        run_count, g_frame_updated);
  }

  // 返回帧数据
  if (g_frame_updated && g_frame_buffer) {
    napi_value result;
    napi_create_object(env, &result);

    napi_value width, height;
    napi_create_int32(env, g_frame_width, &width);
    napi_create_int32(env, g_frame_height, &height);
    napi_set_named_property(env, result, "width", width);
    napi_set_named_property(env, result, "height", height);

    // 创建 ArrayBuffer
    void *buffer_data;
    napi_value array_buffer;
    size_t buffer_size = g_frame_width * g_frame_height * 4;
    napi_create_arraybuffer(env, buffer_size, &buffer_data, &array_buffer);
    memcpy(buffer_data, g_frame_buffer, buffer_size);
    napi_set_named_property(env, result, "data", array_buffer);

    return result;
  }

  return nullptr;
}

/**
 * 重置游戏
 */
static napi_value ResetGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "=== ResetGame 被调用 ===");

  if (retro_reset_ptr) {
    retro_reset_ptr();
  }

  return nullptr;
}

/**
 * 清理资源
 */
static napi_value DeinitGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "=== Canvas DeinitGame 被调用 ===");

  // 防止重复调用
  if (!g_libretro_handle) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ Canvas DeinitGame: 游戏已经清理过了");
    return nullptr;
  }

  // 调用 libretro 清理函数（必须在 dlclose 之前）
  if (retro_unload_game_ptr) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Canvas: 调用 retro_unload_game");
    retro_unload_game_ptr();
  }

  if (retro_deinit_ptr) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Canvas: 调用 retro_deinit");
    retro_deinit_ptr();
  }

  // 关闭动态库
  if (g_libretro_handle) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Canvas: 关闭 libretro 动态库");
    dlclose(g_libretro_handle);
    g_libretro_handle = nullptr;
  }

  // 清空所有函数指针
  retro_init_ptr = nullptr;
  retro_deinit_ptr = nullptr;
  retro_reset_ptr = nullptr;
  retro_run_ptr = nullptr;
  retro_api_version_ptr = nullptr;
  retro_load_game_ptr = nullptr;
  retro_unload_game_ptr = nullptr;

  retro_set_environment_ptr = nullptr;
  retro_set_video_refresh_ptr = nullptr;
  retro_set_audio_sample_ptr = nullptr;
  retro_set_audio_sample_batch_ptr = nullptr;
  retro_set_input_poll_ptr = nullptr;
  retro_set_input_state_ptr = nullptr;

  // 清理帧缓冲区
  if (g_frame_buffer) {
    delete[] g_frame_buffer;
    g_frame_buffer = nullptr;
    g_frame_buffer_size = 0;
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Canvas DeinitGame 完成");

  return nullptr;
}

/**
 * 设置输入状态
 *
 * @param keyId   按键 ID (0-15)
 * @param pressed 是否按下
 */
static napi_value SetInput(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  // 获取按键 ID 和状态
  int32_t key_id;
  bool pressed;
  napi_get_value_int32(env, args[0], &key_id);
  napi_get_value_bool(env, args[1], &pressed);

  if (key_id >= 0 && key_id < 16) {
    g_input_state[key_id] = pressed;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "设置输入: key=%{public}d, pressed=%{public}d", key_id,
                pressed);
  }

  return nullptr;
}

// ========== 导出函数 (供 hello.cpp 调用) ==========
napi_value Game2048_InitGame(napi_env env, napi_callback_info info) {
  return InitGame(env, info);
}

napi_value Game2048_RunFrame(napi_env env, napi_callback_info info) {
  return RunFrame(env, info);
}

napi_value Game2048_ResetGame(napi_env env, napi_callback_info info) {
  return ResetGame(env, info);
}

napi_value Game2048_DeinitGame(napi_env env, napi_callback_info info) {
  return DeinitGame(env, info);
}

napi_value Game2048_SetInput(napi_env env, napi_callback_info info) {
  return SetInput(env, info);
}
