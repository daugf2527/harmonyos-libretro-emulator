/*
 * Libretro 通用 Native 渲染器
 * 支持动态加载任何 Libretro 核心
 */

#ifndef LIBRETRO_NATIVE_RENDERER_H
#define LIBRETRO_NATIVE_RENDERER_H

#include "core/libretro/env_dispatcher.h"
#include "core/libretro/retro_common.h"
#include "interfaces/graphics/i_renderer.h" // 1. 引入接口
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <mutex>
#include <native_window/external_window.h>
#include <string>
#include <unordered_map>
#include <vector>

struct NativeResourceManager;

namespace libretro {

// 核心信息
struct CoreInfo {
  std::string id;
  std::string name;
  std::string soFile;
  std::string description;
  int defaultWidth;
  int defaultHeight;
};

// ROM 信息
struct RomInfo {
  std::string id;
  std::string name;
  std::string file;
  std::string coreId;
};

// 游戏状态
enum class GameState { STOPPED, RUNNING, PAUSED };

struct LibretroRuntimeStats {
  uint64_t videoRefreshCalls = 0;
  uint64_t videoNullFrames = 0;
  uint64_t videoDupeFrames = 0;
  uint64_t audioBatchCalls = 0;
  uint64_t audioFramesIn = 0;

  uint64_t nwRequestBufferCalls = 0;
  uint64_t nwRequestBufferFailures = 0;
  uint64_t nwAbortBufferCalls = 0;
  uint64_t nbFromWindowBufferFailures = 0;
  uint64_t nbMapFailures = 0;
  uint64_t nbUnmapFailures = 0;
  uint64_t nwFlushBufferCalls = 0;
  uint64_t nwFlushBufferFailures = 0;
  uint64_t fencePollCalls = 0;
  uint64_t fencePollFailures = 0;
  uint64_t fencePollTimeouts = 0;
};

class LibretroNativeRenderer : public interfaces::IRenderer { // 2. 继承接口
public:
  explicit LibretroNativeRenderer(std::string id);
  ~LibretroNativeRenderer() override;

  // 接口实现: IRenderer
  bool Initialize(OHNativeWindow *window) override;
  void Release() override;
  void Render(const void *data, int width, int height, size_t pitch) override;
  void OnSurfaceChanged(int width, int height) override;
  int GetWidth() const override;
  int GetHeight() const override;

  // 核心和 ROM 管理
  bool LoadCore(const std::string &corePath,
                const std::string &filesDir = std::string(),
                const std::string &cacheDir = std::string());
  bool LoadRom(const std::string &romPath,
               NativeResourceManager *nativeResourceManager,
               const std::string &filesDir = std::string(),
               const std::string &cacheDir = std::string());
  void UnloadRom();
  void UnloadCore();

  // 游戏控制
  void Start();
  void Pause();
  void Resume();
  void Stop();
  void RunFrame();

  // 输入处理
  void SetButtonState(unsigned port, unsigned device, unsigned index,
                      unsigned id, bool pressed);
  void ClearButtonStates();

  // 状态查询
  GameState GetState() const { return state_; }
  bool IsRunning() const { return state_ == GameState::RUNNING; }
  bool IsPaused() const { return state_ == GameState::PAUSED; }
  bool HasCoreLoaded() const { return coreHandle_ != nullptr; }
  bool HasRomLoaded() const { return !romData_.empty() || !romPathStable_.empty(); }

  // 核心信息
  int GetVideoWidth() const { return videoWidth_; }
  int GetVideoHeight() const { return videoHeight_; }
  double GetFps() const { return fps_; }
  int GetAudioSampleRate() const { return audioSampleRate_; }

  void GetRuntimeStats(LibretroRuntimeStats &out) const;
  void ResetRuntimeStats();

  // 静态实例获取
  static LibretroNativeRenderer *GetInstance(const std::string &id);

private:
  // Libretro 回调
  static void VideoRefreshCallback(const void *data, unsigned width,
                                   unsigned height, size_t pitch);
  static size_t AudioSampleBatchCallback(const int16_t *data, size_t frames);
  static void InputPollCallback();
  static int16_t InputStateCallback(unsigned port, unsigned device,
                                    unsigned index, unsigned id);
  static bool EnvironmentCallback(unsigned cmd, void *data);

  // 内部方法
  bool LoadCoreFunctions();
  void SetupCallbacks();
  void RenderFrame(const void *data, unsigned width, unsigned height,
                   size_t pitch);

  // 成员变量
  std::string id_;
  OHNativeWindow *window_;
  void *coreHandle_;
  GameState state_;

  // Libretro 函数指针
  void (*retro_init_)();
  void (*retro_deinit_)();
  unsigned (*retro_api_version_)();
  void (*retro_get_system_info_)(struct retro_system_info *);
  void (*retro_get_system_av_info_)(struct retro_system_av_info *);
  void (*retro_set_environment_)(retro_environment_t);
  void (*retro_set_video_refresh_)(retro_video_refresh_t);
  void (*retro_set_audio_sample_)(retro_audio_sample_t);
  void (*retro_set_audio_sample_batch_)(retro_audio_sample_batch_t);
  void (*retro_set_input_poll_)(retro_input_poll_t);
  void (*retro_set_input_state_)(retro_input_state_t);
  bool (*retro_load_game_)(const struct retro_game_info *);
  void (*retro_unload_game_)();
  void (*retro_run_)();
  void (*retro_reset_)();

  // 视频信息
  int videoWidth_;
  int videoHeight_;
  // 当前窗口几何尺寸 (用于 SET_BUFFER_GEOMETRY 优化)
  int geometryWidth_ = 0;
  int geometryHeight_ = 0;
  double fps_;
  retro_pixel_format pixelFormat_;

  // 音频信息
  int audioSampleRate_;

  std::chrono::steady_clock::time_point lastRunTimestamp_{};
  bool hasLastRunTimestamp_ = false;

  // Env 状态（方案B：通用 EnvDispatcher）
  EnvState envState_;

  // Core 信息
  struct retro_system_info systemInfo_{};
  bool hasSystemInfo_ = false;
  bool needFullpath_ = false;
  bool gameLoaded_ = false;
  bool isGambatte_ = false;

  // ROM 生命周期与路径（保证至少到 retro_unload_game 前有效）
  std::vector<uint8_t> romData_;
  std::string romPathStable_;
  std::string filesDir_;
  std::string contentDir_;
  std::string cacheDir_;

  std::vector<uint8_t> lastVideoFrame_;
  unsigned lastVideoWidth_ = 0;
  unsigned lastVideoHeight_ = 0;
  size_t lastVideoPitch_ = 0;

  mutable std::mutex statsMutex_;
  LibretroRuntimeStats stats_{};

  // 输入状态
  std::mutex inputMutex_;
  bool buttonStates_[16]; // 支持 16 个按键

  // 线程安全
  mutable std::recursive_mutex renderMutex_;

  // 静态实例映射（用于回调）
  static std::unordered_map<std::string, LibretroNativeRenderer *> instances_;
  static std::mutex instancesMutex_;
  static thread_local LibretroNativeRenderer *currentInstance_;
};

} // namespace libretro

#endif // LIBRETRO_NATIVE_RENDERER_H
