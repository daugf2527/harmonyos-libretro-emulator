#ifndef LIBRETRO_ENGINE_LIBRETRO_ENGINE_H
#define LIBRETRO_ENGINE_LIBRETRO_ENGINE_H

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../libretro/core_loader.h"
#include "../libretro/disk_controller.h"
#include "../libretro/env_dispatcher.h"
#include "core_state_manager.h"
#include "engine_messages.h"
#include "event_bridge.h"
#include "frame_buffer_pool.h"
#include "input_manager.h"
#include "input_port_router.h"
#include "message_queue.h"
#include "render_thread.h"
#include "video_pipeline.h"
#include "window_guard.h"

namespace interfaces {
class IInputManager;
class IRenderer;
} // namespace interfaces

namespace libretro {

/**
 * @brief 运行时统计信息
 */
struct RuntimeStats {
  // 视频统计
  uint64_t videoRefreshCalls = 0;
  uint64_t videoNullFrames = 0;
  uint64_t videoDupeFrames = 0;
  uint64_t videoDroppedFrames = 0;

  // 音频统计
  uint64_t audioBatchCalls = 0;
  uint64_t audioFramesIn = 0;

  // NativeWindow 统计
  uint64_t nwRequestBufferCalls = 0;
  uint64_t nwRequestBufferFailures = 0;
  uint64_t nwFlushBufferCalls = 0;
  uint64_t nwFlushBufferFailures = 0;
  uint64_t nwAbortBufferCalls = 0;

  // NativeBuffer 统计
  uint64_t nbFromWindowBufferFailures = 0;
  uint64_t nbMapFailures = 0;
  uint64_t nbUnmapFailures = 0;

  // Fence 统计
  uint64_t fenceWaitCalls = 0;
  uint64_t fenceWaitFailures = 0;
  uint64_t fenceTimeoutCount = 0;

  // 帧时间统计（微秒）
  uint64_t frameTimeMin = UINT64_MAX;
  uint64_t frameTimeMax = 0;
  uint64_t frameTimeSum = 0;
  uint64_t frameCount = 0;

  // RenderThread + Queue 统计
  uint64_t queuePushed = 0;
  uint64_t queuePopped = 0;
  uint64_t queueDroppedOldest = 0;
  uint64_t queueDroppedStaleOnPop = 0;
  uint64_t queueDepthMax = 0;
  uint64_t renderTickNoFrame = 0;
  uint64_t renderThreadRenderedFrames = 0;
  uint64_t renderThreadDroppedFrames = 0;
  uint64_t vsyncCallbacks = 0;
  uint64_t vsyncFallbackTicks = 0;
  uint64_t vsyncRequestFailures = 0;

  void Reset() {
    videoRefreshCalls = videoNullFrames = videoDupeFrames = videoDroppedFrames =
        0;
    audioBatchCalls = audioFramesIn = 0;
    nwRequestBufferCalls = nwRequestBufferFailures = 0;
    nwFlushBufferCalls = nwFlushBufferFailures = nwAbortBufferCalls = 0;
    nbFromWindowBufferFailures = nbMapFailures = nbUnmapFailures = 0;
    fenceWaitCalls = fenceWaitFailures = fenceTimeoutCount = 0;
    frameTimeMin = UINT64_MAX;
    frameTimeMax = 0;
    frameTimeSum = frameCount = 0;
    queuePushed = queuePopped = queueDroppedOldest = 0;
    queueDroppedStaleOnPop = queueDepthMax = 0;
    renderTickNoFrame = renderThreadRenderedFrames = renderThreadDroppedFrames = 0;
    vsyncCallbacks = vsyncFallbackTicks = vsyncRequestFailures = 0;
  }
};

struct SaveStateThumbnail {
  std::vector<uint8_t> rgba;
  unsigned width = 0;
  unsigned height = 0;
};

struct SaveStateCaptureBundle {
  std::vector<uint8_t> stateData;
  SaveStateThumbnail thumbnail;
};

/**
 * @brief 引擎状态机定义
 */
enum class EngineState {
  INIT = 0,        // 初始状态
  CORE_LOADED = 1, // 核心已加载
  GAME_LOADED = 2, // 游戏已加载
  RUNNING = 3,     // 运行中
  PAUSED = 4,      // 已暂停
  STOPPING = 5,    // 停止中
  STOPPED = 6,     // 已停止
  STARTING = 7,    // 启动中
  LOADING = 8,     // 加载中
  ERROR = 9        // 错误态
};

/**
 * @brief LibretroEngine 核心引擎类
 * 负责主循环调度、状态管理、跨线程消息同步及 NativeWindow 渲染。
 */
class LibretroEngine {
public:
  struct EngineErrorInfo {
    std::string reason;
    std::string step;
    std::string message;
  };

  // 使用单例模式或显式生命周期管理（建议显式管理，由 NAPI 层持有）
  LibretroEngine();
  ~LibretroEngine();

  // 获取全局单例
  static LibretroEngine *GetInstance();

  // 禁止拷贝
  LibretroEngine(const LibretroEngine &) = delete;
  LibretroEngine &operator=(const LibretroEngine &) = delete;

  // --- 控制接口 (由 UI/JS 线程调用) ---
  bool Start();
  bool Stop();
  bool Pause();
  bool Resume();
  void Cancel();

  /**
   * @brief 统一重置引擎状态（解决重入问题）
   * 重置：消息队列、CoreLoader、AudioBridge、引擎状态、统计信息
   * 在 Start() 调用前自动执行，确保干净的初始状态
   */
  void Reset();

  bool LoadCore(const std::string &corePath);
  bool LoadGame(const std::string &gamePath,
                std::shared_ptr<std::vector<uint8_t>> data = nullptr);

  void SetNativeWindow(const std::string &xcomponentId, OHNativeWindow *window,
                       bool forceRebind = false);
  void ClearNativeWindowIfMatch(const std::string &xcomponentId,
                                OHNativeWindow *destroyedWindow);

  /**
   * @brief 通知引擎窗口大小已改变
   * 由平台层 XComponent 的 Surface Changed/SizeChanged 等事件回调触发
   */
  void OnNativeWindowResized(const std::string &xcomponentId, int width,
                             int height);

  bool DispatchKeyboardEvent(bool down, unsigned keycode, uint32_t character,
                             uint16_t key_modifiers);
  bool SetFilesDir(const std::string &filesDir);
  std::string GetFilesDir() const;
  interfaces::IRenderer *GetRendererInterface() const;

  // --- SaveState 接口 ---
  size_t GetSaveStateSize();
  bool SaveState(std::vector<uint8_t> &outData);
  bool CaptureSaveStateBundle(SaveStateCaptureBundle &outBundle);
  bool LoadState(const std::vector<uint8_t> &data);

  // --- SRAM 接口 ---
  bool GetSRAM(std::vector<uint8_t> &outData);
  bool SetSRAM(const std::vector<uint8_t> &data);

  // --- 核心控制 ---
  bool ResetCore();

  // --- 金手指接口 ---
  bool CheatReset();
  bool CheatSet(unsigned index, bool enabled, const std::string &code);

  // --- 控制器/区域接口 ---
  void SetControllerPortDevice(unsigned port, unsigned device);
  unsigned GetRegion();

  // --- AV 信息查询 ---
  unsigned GetVideoWidth() const { return videoWidth_; }
  unsigned GetVideoHeight() const { return videoHeight_; }
  double GetFps() const { return targetFps_; }
  double GetAudioSampleRate() const { return audioSampleRate_; }
  uintptr_t GetHwRenderFramebuffer() const;

  // --- 视频配置 ---
  void SetScalingMode(int mode); // 0=Hardware, 1=Software, 2=GLES
  void SetSwapInterval(int interval); // 0=Disable VSync, 1=Enable VSync
  void SetSoftwareMaxResolution(unsigned maxWidth, unsigned maxHeight);
  void SetAIUpscale(bool enabled);
  void SetHwRenderAllowed(bool allowed);
  void SetRenderThreadEnabled(bool enabled);
  void SetNativeVSyncEnabled(bool enabled);
  void SetGlesDiagEnabled(bool enabled);

  bool SetCoreOption(const std::string &key, const std::string &value);
  std::string GetCoreOptionsJson() const;

  // RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS 上报的 button mask
  // (bit N = RETRO_DEVICE_ID_JOYPAD_N 被 core 声明使用,0 = core 未声明)。
  uint16_t GetInputDescriptorMask() const {
    return envState_.GetInputDescriptorMask();
  }

  // --- 磁盘控制接口 ---
  bool DiskControlSetEjectState(bool ejected);
  bool DiskControlGetEjectState();
  unsigned DiskControlGetImageIndex();
  bool DiskControlSetImageIndex(unsigned index);
  unsigned DiskControlGetNumImages();
  bool DiskControlReplaceImageIndex(unsigned index, const std::string &path);
  bool DiskControlAddImageIndex();

  // --- 回调设置 ---
  bool InitializeEventBridge(napi_env env, napi_value callback);

  // --- 音频调节 ---
  void SetMinimumAudioLatency(unsigned latency_ms);

  // --- 状态查询 ---
  EngineState GetState() const { return state_.load(); }
  bool IsRunning() const { return state_.load() == EngineState::RUNNING; }
  bool HasCoreLoaded() const { return coreLoader_.IsLoaded(); }
  bool HasGameLoaded() const {
    return gameLoaded_.load(std::memory_order_acquire);
  }
  bool WaitForState(EngineState target, uint32_t timeoutMs);
  EngineErrorInfo GetLastErrorInfo() const;
  void ClearLastErrorInfo();
  void SetLastErrorInfo(const std::string &reason, const std::string &step,
                        const std::string &message);

private:
  enum class EnginePhase : uint8_t {
    IDLE = 0,
    WAIT_MESSAGE,
    PROCESS_FRAME,
    RETRO_RUN,
    VIDEO_RENDER,
    VULKAN_ACQUIRE,
    STOP_WAIT
  };

  void SetPhase(EnginePhase phase);
  static const char *PhaseToString(EnginePhase phase);
  int64_t GetPhaseDurationMs() const;

  // --- 内部线程逻辑 ---
  void GameLoop();
  void HandleMessage(const EngineMessage &msg);
  void SetupCallbacks();
  void ProcessFrame();

  // --- Libretro 静态回调桥接 ---
  static void OnVideoRefresh(const void *data, unsigned width, unsigned height,
                             size_t pitch);
  static void OnAudioSample(int16_t left, int16_t right);
  static size_t OnAudioSampleBatch(const int16_t *data, size_t frames);
  static bool OnEnvironment(unsigned cmd, void *data);

  // --- 新增: Rumble 回调 ---
  static bool OnRumble(unsigned port, retro_rumble_effect effect,
                       uint16_t strength);

  // --- 新增: Sensor 回调 ---
  static bool OnSensorSetState(unsigned port, retro_sensor_action action,
                               unsigned rate);
  static float OnSensorGetInput(unsigned port, unsigned id);

  // --- 状态转换辅助 ---
  void TransitionTo(EngineState newState);
  void UnloadGameIfNeeded(const char *reason);
  void DetectCoreQuirks();
  bool ApplyFilesDir(const std::string &filesDir);
  bool ExecuteSyncTask(const std::function<void()> &task, uint32_t timeoutMs,
                       const char *operation = "ExecuteSyncTask");

  // --- 成员变量 ---
  std::atomic<EngineState> state_{EngineState::INIT};
  std::atomic<bool> running_{false};
  std::atomic<bool> stopRequested_{false};
  std::atomic<bool> startInProgress_{false};
  std::atomic<bool> stopInProgress_{false};
  std::atomic<bool> stopTimedOut_{false};
  std::recursive_mutex controlMutex_;
  mutable std::mutex filesDirHintMutex_;
  std::string pendingFilesDir_;
  std::thread gameThread_;
  std::mutex stateMutex_;
  std::condition_variable stateCond_;
  std::mutex stopMutex_;
  std::condition_variable stopCond_;
  std::atomic<bool> gameLoopExited_{false};

  // 核心管理
  CoreLoader coreLoader_;
  VideoPipeline videoPipeline_;
  FrameBufferPool frameBufferPool_{3};
  EnvState envState_; // Libretro 环境状态
  std::atomic<EnginePhase> phase_{EnginePhase::IDLE};
  std::atomic<int64_t> phaseStartUs_{0};
  std::atomic<bool> gameLoaded_{false};

  // 消息队列与输入快照
  ThreadSafeQueue<EngineMessage> messageQueue_;
  std::unique_ptr<InputManager> inputManager_;
  std::unique_ptr<InputPortRouter> inputPortRouter_;
  std::unique_ptr<interfaces::IRenderer> rendererInterface_;
  std::unique_ptr<RenderThread> renderThread_;
  std::unique_ptr<CoreStateManager> stateManager_;
  std::unique_ptr<DiskController> diskController_;

  // NativeWindow 保护
  // Render/EGL 保护锁：与 windowMutex_ 同时使用时必须先锁 renderMutex_
  std::mutex renderMutex_;
  std::mutex windowMutex_;
  WindowGuard windowGuard_;
  std::string current_xcomponent_id_;

  enum class SurfaceState {
    UNINITIALIZED,
    CREATED,
    VALID,
    PAUSED,
    DESTROYED,
  };
  std::atomic<SurfaceState> surface_state_{SurfaceState::UNINITIALIZED};
  std::atomic<uint64_t> surface_session_id_{0};
  std::atomic<uint64_t> surface_generation_{0};
  std::atomic<int> last_window_width_{0};
  std::atomic<int> last_window_height_{0};

  // Event 桥接 (TSFN 封装)
  EventBridge eventBridge_;

  // 性能统计与心跳
  std::atomic<std::chrono::steady_clock::time_point> lastTickTime_;
  double lastFpsTime_;
  uint32_t frameCount_;
  float currentFps_;

  // Frame Time 回调支持
  std::chrono::steady_clock::time_point lastRunTimestamp_;
  bool hasLastRunTimestamp_{false};

  // 核心路径记录
  std::string currentCorePath_;
  std::string currentGamePath_;
  std::shared_ptr<std::vector<uint8_t>> currentGameData_;
  struct retro_system_info systemInfo_ {};
  bool hasSystemInfo_{false};

  // AV 信息
  unsigned videoWidth_{0};
  unsigned videoHeight_{0};
  unsigned videoMaxWidth_{0};
  unsigned videoMaxHeight_{0};
  // [2026-06-08 C-F4] atomic:Engine 线程写,NAPI 线程经 GetFps/GetAudioSampleRate
  // (refactoredGetAVInfo)读 → 原 plain double 8 字节跨线程读 = 撕裂读(formally UB)。
  // unsigned(videoWidth_ 等 4 字节对齐)平台本就原子,故仅 double 两个需原子化。
  std::atomic<double> targetFps_{60.0};
  std::atomic<double> audioSampleRate_{44100.0};

  // 运行时统计
  RuntimeStats stats_;
  mutable std::mutex statsMutex_;

  // 错误状态
  EngineErrorInfo lastError_{};
  mutable std::mutex errorMutex_;

  // 日志节流计数器（从 static 移为成员变量，避免多线程数据竞争）
  size_t processFrameLogCount_{0};
  size_t videoRefreshLogCount_{0};
  size_t windowEventLogCount_{0};
  size_t windowMessageDropLogCount_{0};
  size_t windowResizeDropLogCount_{0};
  size_t surfaceInvalidDropLogCount_{0};
  size_t audioStatusLogCount_{0};
  size_t audioLowLogCount_{0};
  std::atomic<int64_t> lastRetroRunMs_{0};
  std::atomic<int64_t> lastVideoRenderMs_{0};
  std::atomic<int> lastVideoRenderResult_{0};
  std::atomic<unsigned> lastVideoRenderWidth_{0};
  std::atomic<unsigned> lastVideoRenderHeight_{0};
  std::atomic<size_t> lastVideoRenderPitch_{0};
  std::atomic<uint64_t> videoFrameSeq_{0};
  std::atomic<int64_t> lastAudioStatusEmitUs_{0};
  size_t lastAudioUnderruns_{0};
  size_t lastAudioOverruns_{0};
  std::chrono::steady_clock::time_point engineDiagWindowStart_{};
  std::chrono::steady_clock::time_point nextFrameDeadline_{};
  uint64_t engineDiagFrames_{0};
  int64_t engineDiagMaxFrameUs_{0};
  int64_t engineDiagMaxRetroMs_{0};
  uint64_t engineDiagOverBudgetFrames_{0};
  std::atomic<bool> hw_render_enabled_{false};
  std::atomic<bool> render_thread_enabled_{true};
  std::atomic<bool> native_vsync_enabled_{true};
  std::atomic<bool> gles_diag_enabled_{false};
  size_t slowRetroRunLogCount_{0};
  size_t slowVideoRenderLogCount_{0};
  size_t skip_frame_counter_{0};

public:
  // 统计接口
  RuntimeStats GetStats() const;
  void ResetStats();
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_LIBRETRO_ENGINE_H
