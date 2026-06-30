/*
 * Phase 3.2 - Game2048 Native 应用实现
 * Phase 3.3 - 添加音频桥接支持
 * Phase 3.4 - 添加 RetroPad 输入支持
 */

#include "game2048_native_app.h"
#include "input/retropad_napi.h" // Phase 3.4 - RetroPad 输入
#include "core/libretro/retro_common.h" // 官方 Libretro API 定义 (包含所有回调类型)
#include "hilog/log.h"
#include "platform/audio/audio_bridge.h" // Phase 3.3 - 音频桥接
#include <dlfcn.h>

// ========== Libretro 注册函数类型定义 ==========
// 注意: 官方 libretro.h 已定义所有回调类型 (retro_environment_t 等)
//       但没有定义注册函数类型，所以我们需要自己定义
typedef void (*retro_set_environment_t)(retro_environment_t);
typedef void (*retro_set_video_refresh_t)(retro_video_refresh_t);
typedef void (*retro_set_audio_sample_t)(retro_audio_sample_t);
typedef void (*retro_set_audio_sample_batch_t)(retro_audio_sample_batch_t);
typedef void (*retro_set_input_poll_t)(retro_input_poll_t);
typedef void (*retro_set_input_state_t)(retro_input_state_t);

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "Game2048NativeApp"

// 全局实例指针
Game2048NativeApp *Game2048NativeApp::s_instance = nullptr;

Game2048NativeApp::Game2048NativeApp(const std::string &id)
    : id_(id), renderer_(std::make_shared<Game2048NativeRenderer>(id)) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048NativeApp created: %{public}s", id_.c_str());
  s_instance = this; // 设置全局实例
}

Game2048NativeApp::~Game2048NativeApp() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048NativeApp destroyed: %{public}s", id_.c_str());
  StopVSync();
  DeinitGame();

  if (nativeVSync_) {
    OH_NativeVSync_Destroy(nativeVSync_);
    nativeVSync_ = nullptr;
  }

  s_instance = nullptr;
}

// ========== XComponent 回调注册 ==========

// 静态回调函数 (转发到实例方法)
static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreatedCB: %{public}s", idStr);

  if (Game2048NativeApp::s_instance) {
    Game2048NativeApp::s_instance->OnSurfaceCreated(
        static_cast<OHNativeWindow *>(window));
  }
}

static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  uint64_t width, height;
  OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChangedCB: %{public}s %{public}lux%{public}lu",
              idStr, width, height);

  if (Game2048NativeApp::s_instance) {
    Game2048NativeApp::s_instance->OnSurfaceChanged(
        static_cast<OHNativeWindow *>(window), width, height);
  }
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyedCB: %{public}s", idStr);

  if (Game2048NativeApp::s_instance) {
    Game2048NativeApp::s_instance->OnSurfaceDestroyed();
  }
}

void Game2048NativeApp::RegisterCallback(
    OH_NativeXComponent *nativeXComponent) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RegisterCallback: %{public}s", id_.c_str());

  // 设置回调函数 (成员变量,生命周期与对象一致)
  renderCallback_.OnSurfaceCreated = OnSurfaceCreatedCB;
  renderCallback_.OnSurfaceChanged = OnSurfaceChangedCB;
  renderCallback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
  renderCallback_.DispatchTouchEvent = nullptr; // 后续实现

  // 注册回调
  OH_NativeXComponent_RegisterCallback(nativeXComponent, &renderCallback_);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Callbacks registered successfully");
}

// ========== XComponent 回调 ==========

void Game2048NativeApp::OnSurfaceCreated(OHNativeWindow *window) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreated: %{public}s", id_.c_str());
  if (renderer_) {
    renderer_->OnSurfaceCreated(window);
  }
}

void Game2048NativeApp::OnSurfaceChanged(OHNativeWindow *window, int32_t width,
                                         int32_t height) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChanged: %{public}dx%{public}d", width,
              height);
  if (renderer_) {
    renderer_->OnSurfaceChanged(window, width, height);
  }
}

void Game2048NativeApp::OnSurfaceDestroyed() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyed: %{public}s", id_.c_str());
  if (renderer_) {
    renderer_->OnSurfaceDestroyed();
  }
}

// ========== 游戏控制 ==========

bool Game2048NativeApp::InitGame(const std::string &soPath,
                                 const std::string &filesDir) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "InitGame: %{public}s", soPath.c_str());

  envState_.SetBaseDir(filesDir);
  envState_.SetLibretroPath(soPath);
  envState_.SetCanDupe(false);
  envState_.SetVariable("2048_fps", "30");

  // Phase 3.3: 初始化音频桥接
  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (!audioBridge->Initialize(48000)) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to initialize audio bridge");
    // 音频失败不影响游戏运行,继续
  } else {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Audio bridge initialized");
  }

  // 加载 Libretro 核心
  libretroHandle_ = dlopen(soPath.c_str(), RTLD_LAZY);
  if (!libretroHandle_) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "dlopen failed: %{public}s", dlerror());
    return false;
  }

  // 获取函数指针
  auto retro_init = (void (*)())dlsym(libretroHandle_, "retro_init");
  auto retro_deinit = (void (*)())dlsym(libretroHandle_, "retro_deinit");
  auto retro_reset = (void (*)())dlsym(libretroHandle_, "retro_reset");
  auto retro_run = (void (*)())dlsym(libretroHandle_, "retro_run");
  auto retro_load_game =
      (bool (*)(void *))dlsym(libretroHandle_, "retro_load_game");
  auto retro_unload_game = (void (*)())dlsym(libretroHandle_, "retro_unload_game");

  auto retro_set_environment =
      (retro_set_environment_t)dlsym(libretroHandle_, "retro_set_environment");
  auto retro_set_video_refresh = (retro_set_video_refresh_t)dlsym(
      libretroHandle_, "retro_set_video_refresh");
  auto retro_set_input_poll =
      (retro_set_input_poll_t)dlsym(libretroHandle_, "retro_set_input_poll");
  auto retro_set_input_state =
      (retro_set_input_state_t)dlsym(libretroHandle_, "retro_set_input_state");
  auto retro_set_audio_sample = (retro_set_audio_sample_t)dlsym(
      libretroHandle_, "retro_set_audio_sample");
  auto retro_set_audio_sample_batch = (retro_set_audio_sample_batch_t)dlsym(
      libretroHandle_, "retro_set_audio_sample_batch");

  if (!retro_init || !retro_run) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "获取函数指针失败");
    dlclose(libretroHandle_);
    libretroHandle_ = nullptr;

    // 清空函数指针
    {
      std::lock_guard<std::mutex> lock(stateMutex_);
      retro_init_ = nullptr;
      retro_deinit_ = nullptr;
      retro_reset_ = nullptr;
      retro_run_ = nullptr;
      retro_load_game_ = nullptr;
      retro_unload_game_ = nullptr;
    }

    return false;
  }

  {
    std::lock_guard<std::mutex> lock(stateMutex_);
    retro_init_ = retro_init;
    retro_deinit_ = retro_deinit;
    retro_reset_ = retro_reset;
    retro_run_ = retro_run;
    retro_load_game_ = retro_load_game;
    retro_unload_game_ = retro_unload_game;
  }

  // 设置回调函数 (无需强制转换，类型安全)
  retro_set_environment(EnvironmentCallback);
  retro_set_video_refresh(VideoRefreshCallback);
  retro_set_input_poll(InputPollCallback);
  retro_set_input_state(InputStateCallback);
  retro_set_audio_sample(AudioSampleCallback);
  retro_set_audio_sample_batch(AudioSampleBatchCallback);

  // 初始化 Libretro
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_init");
  retro_init_();

  // 加载游戏
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_load_game");
  bool loaded = retro_load_game_(nullptr);

  if (loaded) {
    {
      std::lock_guard<std::mutex> lock(stateMutex_);
      gameRunning_ = true;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 游戏初始化成功");

    // Phase 3.3: 启动音频播放
    if (audioBridge->Start()) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Audio playback started");
    }
  }

  return loaded;
}

// VSync 回调函数
static void OnVSyncCallback(long long timestamp, void *data) {
  Game2048NativeApp *app = static_cast<Game2048NativeApp *>(data);
  if (app) {
    app->OnVSyncFrame(timestamp);
  }
}

void Game2048NativeApp::StartVSync() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StartVSync: %{public}s", id_.c_str());

  std::lock_guard<std::mutex> lock(stateMutex_);
  if (vsyncRunning_) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "VSync already running");
    return;
  }

  // 创建 VSync 实例
  if (!nativeVSync_) {
    std::string vsyncName = "game2048_vsync_" + id_;
    nativeVSync_ = OH_NativeVSync_Create(vsyncName.c_str(), vsyncName.length());
    if (!nativeVSync_) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create NativeVSync");
      return;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ NativeVSync created: %{public}s",
                vsyncName.c_str());
  }

  vsyncRunning_ = true;

  // 请求第一帧
  OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ VSync started (跟随系统帧率)");
}

void Game2048NativeApp::StopVSync() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StopVSync: %{public}s", id_.c_str());
  std::lock_guard<std::mutex> lock(stateMutex_);
  vsyncRunning_ = false;
}

void Game2048NativeApp::OnVSyncFrame(long long timestamp) {
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (!vsyncRunning_ || !gameRunning_ || !retro_run_) {
    return;
  }

  // Phase 3.5: 添加详细日志来追踪 retro_run 调用
  static int run_count = 0;
  static long long last_log_time = 0;
  static int log_interval = 0; // 动态计算日志间隔
  run_count++;

  // 首次运行时，根据实际 FPS 计算日志间隔
  if (run_count == 1) {
    last_log_time = timestamp;
  } else if (run_count == 2 && log_interval == 0) {
    // 第二帧时估算 FPS，设置日志间隔为 1 秒
    long long frame_time = timestamp - last_log_time;
    if (frame_time > 0) {
      float estimated_fps = 1000000000.0f / frame_time;
      log_interval = (int)(estimated_fps + 0.5f); // 约 1 秒打印一次
      if (log_interval < 30)
        log_interval = 30; // 最少 30 帧
      if (log_interval > 120)
        log_interval = 120; // 最多 120 帧
    }
  }

  // 每隔约 1 秒打印一次日志
  if (log_interval > 0 && run_count % log_interval == 1) {
    long long delta = timestamp - last_log_time;
    float fps = (log_interval * 1000000000.0f) / delta;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
        "🎮 [Native] retro_run() 调用 #%{public}d, 系统FPS: %.1f, 间隔: %.1fms",
        run_count, fps, delta / 1000000.0f);
    last_log_time = timestamp;
  }

  // 运行一帧游戏逻辑（跟随系统 VSync）
  retro_run_();

  if (log_interval > 0 && run_count % log_interval == 1) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ [Native] retro_run() 完成 #%{public}d", run_count);
  }

  // 请求下一帧 (持续循环)
  if (vsyncRunning_) {
    OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
  }
}

void Game2048NativeApp::ResetGame() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ResetGame");
  if (retro_reset_) {
    retro_reset_();
  }
}

void Game2048NativeApp::DeinitGame() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "DeinitGame");
  std::lock_guard<std::mutex> lock(stateMutex_);

  // 防止重复调用
  if (!libretroHandle_) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ DeinitGame: 游戏已经清理过了");
    return;
  }

  gameRunning_ = false;

  // Phase 3.3: 停止音频播放
  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge && audioBridge->Stop()) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Audio playback stopped");
  }

  // 调用 libretro 清理函数（必须在 dlclose 之前）
  if (retro_unload_game_) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_unload_game");
    retro_unload_game_();
  }

  if (retro_deinit_) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "调用 retro_deinit");
    retro_deinit_();
  }

  // 关闭动态库
  if (libretroHandle_) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "关闭 libretro 动态库");
    dlclose(libretroHandle_);
    libretroHandle_ = nullptr;
  }

  // 清空函数指针
  retro_init_ = nullptr;
  retro_deinit_ = nullptr;
  retro_reset_ = nullptr;
  retro_run_ = nullptr;
  retro_load_game_ = nullptr;
  retro_unload_game_ = nullptr;

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ DeinitGame 完成");
}

void Game2048NativeApp::SetInput(int keyId, bool pressed) {
  if (keyId >= 0 && keyId < 16) {
    inputState_[keyId] = pressed;
    SetRetroPadButtonState(0, keyId, pressed);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "SetInput: key=%{public}d, pressed=%{public}d", keyId,
                pressed);
  }
}

// ========== Libretro 回调函数 ==========

void Game2048NativeApp::VideoRefreshCallback(const void *data, unsigned width,
                                             unsigned height, size_t pitch) {
  // Phase 3.5: 添加详细日志来诊断动画问题
  static int frame_count = 0;
  static int null_frame_count = 0;
  static int render_count = 0;
  frame_count++;

  if (!data) {
    null_frame_count++;
    // 每 30 帧打印一次统计
    if (frame_count % 30 == 0) {
      OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                  "⚠️ [Native] VideoRefresh: data=NULL (总计: "
                  "%{public}d/%{public}d = %.1f%%)",
                  null_frame_count, frame_count,
                  (null_frame_count * 100.0f) / frame_count);
    }
    return; // ❌ 核心没有新数据，跳过渲染
  }

  if (!s_instance || !s_instance->renderer_) {
    return;
  }

  render_count++;

  // 每 30 帧打印一次统计
  if (frame_count % 30 == 0) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                "🎨 [Native] VideoRefresh: %{public}ux%{public}u, 有效帧: "
                "%{public}d/%{public}d (%.1f%%), 渲染: %{public}d",
                width, height, frame_count - null_frame_count, frame_count,
                ((frame_count - null_frame_count) * 100.0f) / frame_count,
                render_count);
  }

  // 直接渲染到 NativeWindow
  s_instance->renderer_->RenderFrame(data, width, height, pitch);
}

bool Game2048NativeApp::EnvironmentCallback(unsigned cmd, void *data) {
  if (!s_instance) {
    return false;
  }

  if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && data) {
    ::retro_pixel_format *fmt = (::retro_pixel_format *)data;
    s_instance->envState_.SetPixelFormat(*fmt);
    return (*fmt == ::RETRO_PIXEL_FORMAT_XRGB8888);
  }

  bool ok = libretro::HandleEnvironmentCommand(s_instance->envState_, cmd, data);
  if (cmd == RETRO_ENVIRONMENT_SET_VARIABLES) {
    s_instance->envState_.SetVariable("2048_fps", "30");
    return true;
  }

  return ok;
}

void Game2048NativeApp::InputPollCallback(void) {
  // 空实现
}

int16_t Game2048NativeApp::InputStateCallback(unsigned port, unsigned device,
                                              unsigned index, unsigned id) {
  // Phase 3.4: 使用 RetroPad 输入系统
  return GetRetroPadState(port, device, index, id);
}

void Game2048NativeApp::AudioSampleCallback(int16_t left, int16_t right) {
  // Phase 3.3: 转发到音频桥接
  libretro::AudioBridge::AudioSampleCallback(left, right);
}

size_t Game2048NativeApp::AudioSampleBatchCallback(const int16_t *data,
                                                   size_t frames) {
  // Phase 3.3: 转发到音频桥接 (推荐使用)
  return libretro::AudioBridge::AudioSampleBatchCallback(data, frames);
}
