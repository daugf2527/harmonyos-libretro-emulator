/*
 * Libretro 通用 Native 渲染器实现
 */

#include "libretro_native_renderer.h"
#include "pixel_converter.h"
#include "platform/audio/audio_bridge.h"
#include "input/retropad_napi.h"
#include "platform/resource/rom_loader.h"
#include "common/file_utils.h"
#include "common/fence_utils.h"
#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <hilog/log.h>
#include <native_buffer/native_buffer.h>
#include <poll.h>
#include <rawfile/raw_file_manager.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__has_include)
#if __has_include(<native_window/graphic_error_code.h>)
#include <native_window/graphic_error_code.h>
#endif
#endif
#include <vector>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "LibretroRenderer"

// Define SET_BUFFER_GEOMETRY if not available
#ifndef SET_BUFFER_GEOMETRY
#define SET_BUFFER_GEOMETRY 0
#endif

#ifndef NATIVE_ERROR_NO_BUFFER
#define NATIVE_ERROR_NO_BUFFER 40601000
#endif

namespace libretro {

// 静态成员初始化
std::unordered_map<std::string, LibretroNativeRenderer *>
    LibretroNativeRenderer::instances_;
std::mutex LibretroNativeRenderer::instancesMutex_;
thread_local LibretroNativeRenderer *LibretroNativeRenderer::currentInstance_ = nullptr;

LibretroNativeRenderer::LibretroNativeRenderer(std::string id)
    : id_(std::move(id)), window_(nullptr), coreHandle_(nullptr),
      state_(GameState::STOPPED), retro_init_(nullptr), retro_deinit_(nullptr),
      retro_api_version_(nullptr), retro_get_system_info_(nullptr),
      retro_get_system_av_info_(nullptr), retro_set_environment_(nullptr),
      retro_set_video_refresh_(nullptr), retro_set_audio_sample_(nullptr),
      retro_set_audio_sample_batch_(nullptr), retro_set_input_poll_(nullptr),
      retro_set_input_state_(nullptr), retro_load_game_(nullptr),
      retro_unload_game_(nullptr), retro_run_(nullptr), retro_reset_(nullptr),
      videoWidth_(0), videoHeight_(0), fps_(60.0),
      pixelFormat_(RETRO_PIXEL_FORMAT_XRGB8888), audioSampleRate_(44100) {

  // 清空按键状态
  std::memset(buttonStates_, 0, sizeof(buttonStates_));

  // 注册实例
  std::lock_guard<std::mutex> lock(instancesMutex_);
  instances_[id_] = this;

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LibretroNativeRenderer 创建: %{public}s", id_.c_str());
}

LibretroNativeRenderer::~LibretroNativeRenderer() {
  Release();

  // 注销实例
  std::lock_guard<std::mutex> lock(instancesMutex_);
  instances_.erase(id_);
  if (currentInstance_ == this) {
    currentInstance_ = nullptr;
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LibretroNativeRenderer 销毁: %{public}s", id_.c_str());
}

LibretroNativeRenderer *
LibretroNativeRenderer::GetInstance(const std::string &id) {
  std::lock_guard<std::mutex> lock(instancesMutex_);
  auto it = instances_.find(id);
  if (it != instances_.end()) {
    return it->second;
  }
  return nullptr;
}

bool LibretroNativeRenderer::Initialize(OHNativeWindow *window) {
  std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
  if (!window) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 窗口为空");
    return false;
  }

  if (window_ != window) {
    if (window_) {
      OH_NativeWindow_NativeObjectUnreference(window_);
    }
    window_ = window;
    OH_NativeWindow_NativeObjectReference(window_);
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ LibretroNativeRenderer 初始化成功");
  return true;
}

void LibretroNativeRenderer::Release() {
  std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
  // 先停止音频
  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    audioBridge->Stop();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "AudioBridge已停止");
  }

  Stop();
  UnloadRom();
  UnloadCore();

  if (window_) {
    OH_NativeWindow_NativeObjectUnreference(window_);
    window_ = nullptr;
  }
}

bool LibretroNativeRenderer::LoadCore(const std::string &corePath,
                                      const std::string &filesDir,
                                      const std::string &cacheDir) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始加载核心: %{public}s", corePath.c_str());

  ResetRuntimeStats();

  // 卸载旧核心
  UnloadCore();

  // 加载动态库
  coreHandle_ = dlopen(corePath.c_str(), RTLD_LAZY);
  if (!coreHandle_) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 加载核心失败: %{public}s", dlerror());
    return false;
  }

  // 加载函数指针
  if (!LoadCoreFunctions()) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 加载核心函数失败");
    UnloadCore();
    return false;
  }

  filesDir_ = filesDir;
  cacheDir_ = cacheDir;

  envState_.SetBaseDir(filesDir_);
  if (!cacheDir_.empty()) {
    envState_.SetCacheDirectory(cacheDir_);
    (void)common::EnsureDirExists(cacheDir_);
  }
  envState_.SetLibretroPath(corePath);
  envState_.SetCanDupe(true);

  // 设置回调
  SetupCallbacks();

  // 初始化核心
  {
    struct Guard {
      LibretroNativeRenderer **slot;
      LibretroNativeRenderer *prev;
      ~Guard() { *slot = prev; }
    } guard{&currentInstance_, currentInstance_};
    currentInstance_ = this;
    retro_init_();
  }

  hasSystemInfo_ = false;
  needFullpath_ = false;
  gameLoaded_ = false;
  std::memset(&systemInfo_, 0, sizeof(systemInfo_));
  if (retro_get_system_info_) {
    retro_get_system_info_(&systemInfo_);
    hasSystemInfo_ = true;
    needFullpath_ = systemInfo_.need_fullpath;
  }

  // Check for Gambatte
  isGambatte_ = (std::string(systemInfo_.library_name) == "Gambatte");
  if (isGambatte_) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ℹ️ [Native] Detected Gambatte core. Applying specific fixes.");
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Core need_fullpath=%{public}d", needFullpath_);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 核心加载成功");
  return true;
}

bool LibretroNativeRenderer::LoadCoreFunctions() {
#define LOAD_SYM(name, type)                                                   \
  dlerror();                                                                   \
  name##_ = reinterpret_cast<type>(dlsym(coreHandle_, #name));                 \
  {                                                                            \
    const char *sym_err = dlerror();                                           \
    if (!name##_ || sym_err) {                                                 \
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG,                                                    \
                   "❌ 加载函数失败: %{public}s (%{public}s)",               \
                   #name, sym_err ? sym_err : "unknown");                    \
      return false;                                                            \
    }                                                                          \
  }

  LOAD_SYM(retro_init, void (*)());
  LOAD_SYM(retro_deinit, void (*)());
  LOAD_SYM(retro_api_version, unsigned (*)());
  LOAD_SYM(retro_get_system_info, void (*)(struct retro_system_info *));
  LOAD_SYM(retro_get_system_av_info, void (*)(struct retro_system_av_info *));
  LOAD_SYM(retro_set_environment, void (*)(retro_environment_t));
  LOAD_SYM(retro_set_video_refresh, void (*)(retro_video_refresh_t));
  LOAD_SYM(retro_set_audio_sample, void (*)(retro_audio_sample_t));
  LOAD_SYM(retro_set_audio_sample_batch, void (*)(retro_audio_sample_batch_t));
  LOAD_SYM(retro_set_input_poll, void (*)(retro_input_poll_t));
  LOAD_SYM(retro_set_input_state, void (*)(retro_input_state_t));
  LOAD_SYM(retro_load_game, bool (*)(const struct retro_game_info *));
  LOAD_SYM(retro_unload_game, void (*)());
  LOAD_SYM(retro_run, void (*)());
  LOAD_SYM(retro_reset, void (*)());

#undef LOAD_SYM

  return true;
}

void LibretroNativeRenderer::SetupCallbacks() {
  struct Guard {
    LibretroNativeRenderer **slot;
    LibretroNativeRenderer *prev;
    ~Guard() { *slot = prev; }
  } guard{&currentInstance_, currentInstance_};
  currentInstance_ = this;

  retro_set_environment_(EnvironmentCallback);
  retro_set_video_refresh_(VideoRefreshCallback);
  retro_set_audio_sample_(libretro::AudioBridge::AudioSampleCallback);
  retro_set_audio_sample_batch_(AudioSampleBatchCallback);
  retro_set_input_poll_(InputPollCallback);
  retro_set_input_state_(InputStateCallback);
}

bool LibretroNativeRenderer::LoadRom(
    const std::string &romPath, NativeResourceManager *nativeResourceManager,
    const std::string &filesDir, const std::string &cacheDir) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "开始加载 ROM: %{public}s", romPath.c_str());

  if (!coreHandle_) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 核心未加载");
    return false;
  }

  libretro::ROMLoadResult loadResult;
  loadResult.success = false;

  if (nativeResourceManager) {
    loadResult = libretro::ROMLoader::LoadFromRawFile(romPath, nativeResourceManager);
  }

  if (!loadResult.success) {
    if (romPath.find("://") != std::string::npos) {
      loadResult = libretro::ROMLoader::LoadFromUri(romPath);
    } else {
      loadResult = libretro::ROMLoader::LoadFromPath(romPath);
    }
  }

  if (!loadResult.success) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ ROM 加载失败: %{public}s", loadResult.error_message.c_str());
    return false;
  }

  std::vector<uint8_t> romDataLocal = std::move(loadResult.data);

  if (!hasSystemInfo_ && retro_get_system_info_) {
    std::memset(&systemInfo_, 0, sizeof(systemInfo_));
    struct Guard {
      LibretroNativeRenderer **slot;
      LibretroNativeRenderer *prev;
      ~Guard() { *slot = prev; }
    } guard{&currentInstance_, currentInstance_};
    currentInstance_ = this;
    retro_get_system_info_(&systemInfo_);
    hasSystemInfo_ = true;
    needFullpath_ = systemInfo_.need_fullpath;
  }

  filesDir_ = filesDir;
  cacheDir_ = cacheDir;
  envState_.SetBaseDir(filesDir_);
  if (!cacheDir_.empty()) {
    envState_.SetCacheDirectory(cacheDir_);
    (void)common::EnsureDirExists(cacheDir_);
  }
  romPathStable_.clear();
  contentDir_.clear();
  romData_.clear();

  const std::string basePathForName = loadResult.path.empty() ? romPath : loadResult.path;

  if (needFullpath_) {
    if (filesDir_.empty()) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ need_fullpath=true 但 filesDir 为空");
      return false;
    }

    std::string romsDir = filesDir_ + "/roms";
    if (!common::EnsureDirExists(romsDir)) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 创建 roms 目录失败");
      return false;
    }

    std::string baseName = common::GetBaseName(basePathForName);
    if (baseName.empty()) {
      baseName = "content.rom";
    }

    contentDir_ = romsDir;
    romPathStable_ = romsDir + "/" + baseName;
    if (!common::WriteFileAll(romPathStable_, romDataLocal.data(), romDataLocal.size())) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ ROM 落盘失败");
      return false;
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ ROM 已落盘: %{public}s", romPathStable_.c_str());
  } else {
    romPathStable_ = basePathForName;
    romData_ = std::move(romDataLocal);
  }

  // 加载游戏
  struct retro_game_info gameInfo;
  gameInfo.path = needFullpath_ ? romPathStable_.c_str() : romPathStable_.empty() ? nullptr : romPathStable_.c_str();
  if (needFullpath_) {
    gameInfo.data = nullptr;
    gameInfo.size = 0;
  } else {
    gameInfo.data = romData_.data();
    gameInfo.size = romData_.size();
  }
  gameInfo.meta = nullptr;

  {
    struct Guard {
      LibretroNativeRenderer **slot;
      LibretroNativeRenderer *prev;
      ~Guard() { *slot = prev; }
    } guard{&currentInstance_, currentInstance_};
    currentInstance_ = this;
    if (!retro_load_game_(&gameInfo)) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ retro_load_game() 失败");
      return false;
    }
  }

  gameLoaded_ = true;

  // 获取 AV 信息
  struct retro_system_av_info avInfo;
  {
    struct Guard {
      LibretroNativeRenderer **slot;
      LibretroNativeRenderer *prev;
      ~Guard() { *slot = prev; }
    } guard{&currentInstance_, currentInstance_};
    currentInstance_ = this;
    retro_get_system_av_info_(&avInfo);
  }

  videoWidth_ = avInfo.geometry.base_width;
  videoHeight_ = avInfo.geometry.base_height;
  fps_ = avInfo.timing.fps;
  audioSampleRate_ = avInfo.timing.sample_rate;

  // Sanity Check: 音频采样率保护
  if (audioSampleRate_ < 8000.0 || audioSampleRate_ > 192000.0) {
    // Gambatte 等核心可能报告系统时钟频率 (2MHz+)，需修正为标准音频采样率
    // Game Boy 标准采样率通常为 32768 Hz (2^15)
    double fallbackRate = 32768.0;
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                "⚠️ [Native] Abnormal audio sample rate detected: %{public}d "
                "Hz. Clamping to %{public}.2f Hz to match GB standard.",
                audioSampleRate_, fallbackRate);
    audioSampleRate_ = static_cast<int>(fallbackRate);
    // 注意：这里没有修改 avInfo，因为后面 Reset 用的是 audioSampleRate_ 成员变量
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ ROM 加载成功");
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  分辨率: %{public}dx%{public}d", videoWidth_,
              videoHeight_);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  帧率: %{public}.2f FPS", fps_);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "  音频: %{public}d Hz", audioSampleRate_);

  // 根据核心采样率重置音频系统
  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    bool resetSuccess = audioBridge->Reset(audioSampleRate_);
    if (resetSuccess) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ AudioBridge 重置成功: %{public}d Hz",
                  audioSampleRate_);
    } else {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ AudioBridge 重置失败");
    }
  }

  return true;
}

void LibretroNativeRenderer::UnloadRom() {
  if (gameLoaded_ && coreHandle_ && retro_unload_game_) {
    Stop();
    {
      struct Guard {
        LibretroNativeRenderer **slot;
        LibretroNativeRenderer *prev;
        ~Guard() { *slot = prev; }
      } guard{&currentInstance_, currentInstance_};
      currentInstance_ = this;
      retro_unload_game_();
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "ROM 已卸载");
  }

  gameLoaded_ = false;

  romData_.clear();
  romPathStable_.clear();
  cacheDir_.clear();

  lastVideoFrame_.clear();
  lastVideoWidth_ = 0;
  lastVideoHeight_ = 0;
  lastVideoPitch_ = 0;

  ResetRuntimeStats();
}

void LibretroNativeRenderer::UnloadCore() {
  if (coreHandle_) {
    if (gameLoaded_ && retro_unload_game_) {
      {
        struct Guard {
          LibretroNativeRenderer **slot;
          LibretroNativeRenderer *prev;
          ~Guard() { *slot = prev; }
        } guard{&currentInstance_, currentInstance_};
        currentInstance_ = this;
        retro_unload_game_();
      }
    }
    gameLoaded_ = false;

    if (retro_deinit_) {
      struct Guard {
        LibretroNativeRenderer **slot;
        LibretroNativeRenderer *prev;
        ~Guard() { *slot = prev; }
      } guard{&currentInstance_, currentInstance_};
      currentInstance_ = this;
      retro_deinit_();
    }
    dlclose(coreHandle_);
    coreHandle_ = nullptr;

    romData_.clear();
    romPathStable_.clear();
    cacheDir_.clear();

    lastVideoFrame_.clear();
    lastVideoWidth_ = 0;
    lastVideoHeight_ = 0;
    lastVideoPitch_ = 0;

    ResetRuntimeStats();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "核心已卸载");
  }
}

void LibretroNativeRenderer::Start() {
  if (state_ == GameState::STOPPED || state_ == GameState::PAUSED) {
    if (!gameLoaded_ && coreHandle_ && retro_load_game_ && envState_.SupportsNoGame()) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "no-game core detected: calling retro_load_game(NULL)");
      {
        struct Guard {
          LibretroNativeRenderer **slot;
          LibretroNativeRenderer *prev;
          ~Guard() { *slot = prev; }
        } guard{&currentInstance_, currentInstance_};
        currentInstance_ = this;
        if (!retro_load_game_(nullptr)) {
          OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ retro_load_game(NULL) 失败 (no-game)");
          return;
        }
      }
      gameLoaded_ = true;

      if (retro_get_system_av_info_) {
        struct retro_system_av_info avInfo;
        {
          struct Guard {
            LibretroNativeRenderer **slot;
            LibretroNativeRenderer *prev;
            ~Guard() { *slot = prev; }
          } guard{&currentInstance_, currentInstance_};
          currentInstance_ = this;
          retro_get_system_av_info_(&avInfo);
        }

        videoWidth_ = avInfo.geometry.base_width;
        videoHeight_ = avInfo.geometry.base_height;
        fps_ = avInfo.timing.fps;
        audioSampleRate_ = avInfo.timing.sample_rate;

        auto *audioBridge = libretro::AudioBridge::GetInstance();
        if (audioBridge) {
          bool resetSuccess = audioBridge->Reset(audioSampleRate_);
          if (resetSuccess) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ AudioBridge 重置成功: %{public}d Hz",
                        audioSampleRate_);
          } else {
            OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ AudioBridge 重置失败");
          }
        }
      }
    }

    state_ = GameState::RUNNING;
    hasLastRunTimestamp_ = false;

    auto *audioBridge = libretro::AudioBridge::GetInstance();
    if (audioBridge) {
      audioBridge->Start();
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "游戏开始运行");
  }
}

void LibretroNativeRenderer::Pause() {
  if (state_ == GameState::RUNNING) {
    state_ = GameState::PAUSED;

    auto *audioBridge = libretro::AudioBridge::GetInstance();
    if (audioBridge) {
      audioBridge->Pause();
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "游戏暂停");
  }
}

void LibretroNativeRenderer::Resume() {
  if (state_ == GameState::PAUSED) {
    state_ = GameState::RUNNING;
    hasLastRunTimestamp_ = false;

    auto *audioBridge = libretro::AudioBridge::GetInstance();
    if (audioBridge) {
      audioBridge->Start();
    }

    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "游戏继续");
  }
}

void LibretroNativeRenderer::Stop() {
  if (state_ == GameState::STOPPED) {
    return;
  }

  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    audioBridge->Stop();
  }

  state_ = GameState::STOPPED;
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "游戏停止");
}

void LibretroNativeRenderer::RunFrame() {
  if (state_ == GameState::RUNNING && retro_run_) {
    std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
    struct Guard {
      LibretroNativeRenderer **slot;
      LibretroNativeRenderer *prev;
      ~Guard() { *slot = prev; }
    } guard{&currentInstance_, currentInstance_};
    currentInstance_ = this;

    const auto now = std::chrono::steady_clock::now();
    envState_.EnterRetroRun();

    if (auto cb = envState_.GetFrameTimeCallback()) {
      ::retro_usec_t delta_us = envState_.GetFrameTimeReference();
      if (hasLastRunTimestamp_) {
        delta_us = std::chrono::duration_cast<std::chrono::microseconds>(
                       now - lastRunTimestamp_)
                       .count();
      }
      cb(delta_us);
    }

    if (auto cb = envState_.GetAudioBufferStatusCallback()) {
      auto *audioBridge = libretro::AudioBridge::GetInstance();
      const bool active = (audioBridge && audioBridge->IsRunning());
      unsigned occupancy = 0;
      bool underrun_likely = false;
      if (active) {
        float usage = audioBridge->GetBufferUsage();
        if (usage < 0.0f) {
          usage = 0.0f;
        } else if (usage > 1.0f) {
          usage = 1.0f;
        }
        occupancy = static_cast<unsigned>(usage * 100.0f + 0.5f);
        underrun_likely = occupancy <= 10;
      }
      cb(active, occupancy, underrun_likely);
    }

    retro_run_();

    unsigned latency_ms = 0;
    if (envState_.ConsumePendingMinimumAudioLatencyMs(latency_ms)) {
      auto *audioBridge = libretro::AudioBridge::GetInstance();
      if (audioBridge) {
        audioBridge->SetMinimumLatencyMs(latency_ms);
      }
    }

    lastRunTimestamp_ = now;
    hasLastRunTimestamp_ = true;
    envState_.ExitRetroRun();
  }
}

void LibretroNativeRenderer::SetButtonState(unsigned port, unsigned device,
                                            unsigned index, unsigned id,
                                            bool pressed) {
  if (device == RETRO_DEVICE_JOYPAD && id < 16) {
    SetRetroPadButtonState(static_cast<int32_t>(port), static_cast<int32_t>(id),
                           pressed);
  }
}

void LibretroNativeRenderer::ClearButtonStates() {
  for (int32_t port = 0; port < 4; port++) {
    for (int32_t i = 0; i < 16; i++) {
      SetRetroPadButtonState(port, i, false);
    }
  }
}

// Libretro 回调实现
void LibretroNativeRenderer::VideoRefreshCallback(const void *data,
                                                  unsigned width,
                                                  unsigned height,
                                                  size_t pitch) {
  if (!currentInstance_) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(currentInstance_->statsMutex_);
    currentInstance_->stats_.videoRefreshCalls++;
  }
  currentInstance_->RenderFrame(data, width, height, pitch);
}

size_t LibretroNativeRenderer::AudioSampleBatchCallback(const int16_t *data,
                                                        size_t frames) {
  if (!currentInstance_) {
    return frames; // 返回frames让核心认为数据已处理
  }

  // [Fix] Gambatte Quirk: Reports stereo samples as frames?
  size_t actualFrames = frames;
  if (currentInstance_->isGambatte_ && frames > 800) {
      actualFrames = frames / 2;
  }

  {
    std::lock_guard<std::mutex> lock(currentInstance_->statsMutex_);
    currentInstance_->stats_.audioBatchCalls++;
    currentInstance_->stats_.audioFramesIn += static_cast<uint64_t>(actualFrames);
  }

  // 调用AudioBridge处理音频数据
  return libretro::AudioBridge::AudioSampleBatchCallback(data, actualFrames);
}

void LibretroNativeRenderer::InputPollCallback() {
  // 输入轮询（当前不需要额外操作）
}

int16_t LibretroNativeRenderer::InputStateCallback(unsigned port,
                                                   unsigned device,
                                                   unsigned index,
                                                   unsigned id) {
  if (!currentInstance_)
    return 0;

  if (device == RETRO_DEVICE_JOYPAD && index != 0) {
    return 0;
  }

  static size_t inputReadLogs = 0;

  if (device == RETRO_DEVICE_JOYPAD && id == RETRO_DEVICE_ID_JOYPAD_MASK) {
    uint16_t mask = 0;
    for (unsigned i = 0; i < 16; i++) {
      if (GetRetroPadState(port, RETRO_DEVICE_JOYPAD, 0, i)) {
        mask |= static_cast<uint16_t>(1u << i);
      }
    }

    if (mask != 0 && inputReadLogs < 20) {
      inputReadLogs++;
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                  "InputState: port=%{public}u JOYPAD_MASK=0x%{public}x",
                  port, mask);
    }
    return static_cast<int16_t>(mask);
  }

  int16_t v = GetRetroPadState(port, device, index, id);
  if (v != 0 && inputReadLogs < 20) {
    inputReadLogs++;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                "InputState: port=%{public}u device=%{public}u index=%{public}u id=%{public}u v=%{public}d",
                port, device, index, id, v);
  }

  return v;
}

bool LibretroNativeRenderer::EnvironmentCallback(unsigned cmd, void *data) {
  if (!currentInstance_) {
    return false;
  }

  bool ok = HandleEnvironmentCommand(currentInstance_->envState_, cmd, data);
  if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && data) {
    currentInstance_->pixelFormat_ = *(retro_pixel_format *)data;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "像素格式: %{public}d", currentInstance_->pixelFormat_);
  }
  return ok;
}

void LibretroNativeRenderer::RenderFrame(const void *data, unsigned width,
                                         unsigned height, size_t pitch) {
  std::lock_guard<std::recursive_mutex> renderLock(renderMutex_);
  if (!window_)
    return;

  if (!data) {
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.videoNullFrames++;
    }
    if (!envState_.CanDupe()) {
      return;
    }

    if (lastVideoFrame_.empty() || lastVideoWidth_ == 0 || lastVideoHeight_ == 0 ||
        lastVideoPitch_ == 0) {
      return;
    }

    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.videoDupeFrames++;
    }

    data = lastVideoFrame_.data();
    width = lastVideoWidth_;
    height = lastVideoHeight_;
    pitch = lastVideoPitch_;
  } else {
    if (pitch != 0 && height != 0) {
      size_t bytes = pitch * static_cast<size_t>(height);
      if (bytes / static_cast<size_t>(height) == pitch) {
        lastVideoFrame_.assign(static_cast<const uint8_t *>(data),
                               static_cast<const uint8_t *>(data) + bytes);
        lastVideoWidth_ = width;
        lastVideoHeight_ = height;
        lastVideoPitch_ = pitch;
      }
    }
  }

  // ========== 0. 硬件缩放配置 (SET_BUFFER_GEOMETRY) ==========
  if (width > 0 && height > 0 && (width != geometryWidth_ || height != geometryHeight_)) {
    // 尝试设置缓冲区几何尺寸，利用硬件合成器的缩放能力
    // SET_BUFFER_GEOMETRY = 0
    int32_t ret = OH_NativeWindow_NativeWindowHandleOpt(window_, SET_BUFFER_GEOMETRY, width, height);
    if (ret == 0) {
      geometryWidth_ = width;
      geometryHeight_ = height;
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ [Native] SET_BUFFER_GEOMETRY success: %{public}dx%{public}d", width, height);
    } else {
      OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ [Native] SET_BUFFER_GEOMETRY failed: %{public}d", ret);
    }
  }

  // ========== 1. 请求 Buffer ==========
  OHNativeWindowBuffer *buffer = nullptr;
  int fenceFd = -1;

  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    stats_.nwRequestBufferCalls++;
  }
  int32_t ret =
      OH_NativeWindow_NativeWindowRequestBuffer(window_, &buffer, &fenceFd);
  if (ret != 0 || !buffer) {
    if (ret != NATIVE_ERROR_NO_BUFFER) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "RequestBuffer failed: %{public}d", ret);
    }
    if (fenceFd >= 0) {
      close(fenceFd);
    }
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.nwRequestBufferFailures++;
    }
    return;
  }

  if (fenceFd >= 0) {
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.fencePollCalls++;
    }

    int waitRet = common::WaitAndCloseFence(fenceFd);
    
    if (waitRet != 0) {
      std::lock_guard<std::mutex> lock(statsMutex_);
      if (waitRet < 0) {
        stats_.fencePollFailures++;
      } else {
        stats_.fencePollTimeouts++;
      }
    }
    fenceFd = -1;
  }

  // ========== 2. 转换为 NativeBuffer 并映射内存 ==========
  OH_NativeBuffer *nativeBuffer = nullptr;
  ret = OH_NativeBuffer_FromNativeWindowBuffer(buffer, &nativeBuffer);
  if (ret != 0 || !nativeBuffer) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "FromNativeWindowBuffer failed: %{public}d", ret);

    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.nbFromWindowBufferFailures++;
      stats_.nwAbortBufferCalls++;
    }
    OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
    return;
  }

  void *virAddr = nullptr;
  ret = OH_NativeBuffer_Map(nativeBuffer, &virAddr);
  if (ret != 0 || !virAddr) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "NativeBuffer_Map failed: %{public}d", ret);

    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.nbMapFailures++;
      stats_.nwAbortBufferCalls++;
    }
    OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
    return;
  }

  // ========== 3. 获取 Buffer 配置 ==========
  OH_NativeBuffer_Config config;
  OH_NativeBuffer_GetConfig(nativeBuffer, &config);

  uint32_t *dest = static_cast<uint32_t *>(virAddr);

  // ========== 4. 计算缩放比例 (保持宽高比) ==========
  float scaleX = static_cast<float>(config.width) / width;
  float scaleY = static_cast<float>(config.height) / height;
  float scale = std::min(scaleX, scaleY);

  int scaledWidth = static_cast<int>(width * scale);
  int scaledHeight = static_cast<int>(height * scale);
  int offsetX = (config.width - scaledWidth) / 2;
  int offsetY = (config.height - scaledHeight) / 2;

  // ========== 5. 清空背景为黑色 ==========
  std::memset(dest, 0, config.height * config.stride);

  // ========== 6. 像素格式转换和缩放渲染 ==========
  uint32_t *destRegion = dest + offsetY * (config.stride / 4) + offsetX;

  // 根据像素格式选择转换方式（完全遵循 Libretro 官方标准）
  static retro_pixel_format lastLoggedPixelFormat =
      RETRO_PIXEL_FORMAT_XRGB8888;
  const bool pixelFormatChanged = (pixelFormat_ != lastLoggedPixelFormat);

  libretro::PixelFormat srcFormat;
  switch (pixelFormat_) {
  case RETRO_PIXEL_FORMAT_0RGB1555:
    srcFormat = libretro::PixelFormat::RGB0555;
    if (pixelFormatChanged) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "使用 0RGB1555 格式 (Libretro 默认格式)");
    }
    break;
  case RETRO_PIXEL_FORMAT_RGB565:
    srcFormat = libretro::PixelFormat::RGB565;
    if (pixelFormatChanged) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "使用 RGB565 格式 (Libretro 推荐 16位格式)");
    }
    break;
  case RETRO_PIXEL_FORMAT_XRGB8888:
    srcFormat = libretro::PixelFormat::XRGB8888;
    if (pixelFormatChanged) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "使用 XRGB8888 格式 (Libretro 推荐 32位格式)");
    }
    break;
  default:
    srcFormat = libretro::PixelFormat::XRGB8888;
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "⚠️ 未知像素格式 %{public}d，使用默认 XRGB8888",
                 pixelFormat_);
    break;
  }

  if (pixelFormatChanged) {
    lastLoggedPixelFormat = pixelFormat_;
  }

  // 使用 NEON 优化的像素转换器
  libretro::PixelConverter::ConvertAndScale(
      data,                            // 源数据
      srcFormat,                       // 源格式
      width,                           // 源宽度
      height,                          // 源高度
      pitch,                           // 源行字节数
      destRegion,                      // 目标数据 (RGBA8888)
      libretro::PixelFormat::RGBA8888, // 目标格式
      scaledWidth,                     // 目标宽度
      scaledHeight,                    // 目标高度
      config.stride / 4                // 目标行像素数
  );

  // ========== 7. 解除内存映射 ==========
  ret = OH_NativeBuffer_Unmap(nativeBuffer);
  if (ret != 0) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "NativeBuffer_Unmap failed: %{public}d", ret);

    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.nbUnmapFailures++;
      stats_.nwAbortBufferCalls++;
    }
    OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
    return;
  }

  // ========== 8. 提交 Buffer ==========
  Region region{nullptr, 0}; // 全屏刷新
  const int acquireFenceFd = -1;

  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    stats_.nwFlushBufferCalls++;
  }
  ret = OH_NativeWindow_NativeWindowFlushBuffer(window_, buffer, acquireFenceFd,
                                                region);
  if (ret != 0) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "FlushBuffer failed: %{public}d", ret);
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.nwFlushBufferFailures++;
      stats_.nwAbortBufferCalls++;
    }

    OH_NativeWindow_NativeWindowAbortBuffer(window_, buffer);
    return;
  }

  static int frameCount = 0;
  frameCount++;
  if (frameCount <= 3 || (frameCount % 600) == 0) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                "✅ Libretro 渲染帧 #%{public}d (%{public}dx%{public}d -> "
                "%{public}dx%{public}d)",
                frameCount, width, height, scaledWidth, scaledHeight);
  }
}

// ========== IRenderer 接口实现 ==========

void LibretroNativeRenderer::Render(const void *data, int width, int height,
                                    size_t pitch) {
  RenderFrame(data, width, height, pitch);
}

void LibretroNativeRenderer::OnSurfaceChanged(int width, int height) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChanged: %{public}dx%{public}d", width,
              height);
}

int LibretroNativeRenderer::GetWidth() const { return videoWidth_; }

int LibretroNativeRenderer::GetHeight() const { return videoHeight_; }

void LibretroNativeRenderer::GetRuntimeStats(LibretroRuntimeStats &out) const {
  std::lock_guard<std::mutex> lock(statsMutex_);
  out = stats_;
}

void LibretroNativeRenderer::ResetRuntimeStats() {
  std::lock_guard<std::mutex> lock(statsMutex_);
  stats_ = LibretroRuntimeStats{};
}

} // namespace libretro
