#include "libretro_engine.h"
#include "core_quirks_manager.h"
#include "common/file_security.h"
#include "common/string_utils.h"
#include "interfaces/graphics/i_renderer.h"
#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstring>
#include <thread>
#if defined(__has_include) &&                                                  \
    __has_include("../../platform/resource/rom_loader.h")
#include "../../platform/resource/rom_loader.h"
#else
#include "platform/resource/rom_loader.h"
#endif
#include "../../platform/audio/audio_bridge.h"
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>
#include <hilog/log.h>
#include "qos/qos.h"

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD010
#undef LOG_TAG
#define LOG_TAG "LibretroEngine"
#undef LOG_FLOW
#define LOG_FLOW "Engine"
#include "common/log_prefix.h"

namespace libretro {

// 静态实例指针，用于回调桥接（Phase 1 简化处理，仅支持单实例）
//
// 设计警告:本项目同时存在 GetInstance() 的 Meyer's singleton (line ~282) 和
// 此处的 g_engineInstance 全局指针,后者由构造函数 store(this)。两套生命周期:
//   - GetInstance() 的静态局部 `instance` 在程序退出最末才析构
//   - g_engineInstance 由构造函数写入,析构函数写回 nullptr (line 324)
// 当前默认只创建一个实例,无冲突;但若未来某处在单例外另建实例,
// g_engineInstance 会被覆盖,且析构顺序可能不一致。修复方向:
//   1) 彻底删除 g_engineInstance,所有回调改走 GetInstance(),或
//   2) 把 g_engineInstance 改为只在 GetInstance() 首次访问时设置一次。
// 在此之前,新增代码请只通过 GetInstanceSnapshot() 访问当前实例。
static std::atomic<LibretroEngine *> g_engineInstance{nullptr};

class EngineSyncTask {
public:
  explicit EngineSyncTask(std::function<void()> task) : task_(std::move(task)) {}

  void Run() {
    // T8-B-F1: abandoned_ 检查与 task_() 执行必须在同一 mutex 临界区内,
    // 否则 Wait 在 Run 检查 abandoned_=false 之后、task_() 之前超时,
    // 调用方栈帧销毁,task_() 触发悬挂引用 UB。
    // task_() 持锁执行不会死锁: Wait 内的 wait_for 已释放 lock 在等待 done_。
    std::lock_guard<std::mutex> lock(mutex_);
    if (!abandoned_ && task_) {
      task_();
    }
    done_ = true;
    cond_.notify_all();
  }

  bool Wait(uint32_t timeoutMs) {
    std::unique_lock<std::mutex> lock(mutex_);
    const bool ok = cond_.wait_for(
        lock, std::chrono::milliseconds(timeoutMs),
        [this]() { return done_; });
    if (!ok) {
      // T8-B-F1: 在持有 mutex 时设置 abandoned_; 与 Run() 的临界区互斥,
      // 保证 task_() 要么完整执行,要么完整跳过——不会与栈销毁竞争。
      abandoned_ = true;
    }
    return ok;
  }

private:
  std::function<void()> task_;
  std::mutex mutex_;
  std::condition_variable cond_;
  bool done_ = false;
  std::atomic<bool> abandoned_{false};
};

namespace {
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";
constexpr const char *kAudioDiagPrefix = "[AUDIO_DIAG]";
constexpr uint32_t kSyncTaskTimeoutMs = 5000;
thread_local LibretroEngine *g_engineThreadInstance = nullptr;

bool IsMessagePathTooLong(const std::string &path) {
  return path.size() >= EngineMessageLoadPath::kPathCapacity;
}

LibretroEngine *GetEngineInstanceSnapshot() {
  return g_engineInstance.load(std::memory_order_acquire);
}

const char *SurfaceStateToString(int state) {
  switch (state) {
  case 0:
    return "uninitialized";
  case 1:
    return "created";
  case 2:
    return "valid";
  case 3:
    return "paused";
  case 4:
    return "destroyed";
  default:
    return "unknown";
  }
}

class EngineRendererAdapter : public interfaces::IRenderer {
public:
  explicit EngineRendererAdapter(LibretroEngine *engine) : engine_(engine) {}

  bool Initialize(OHNativeWindow *window) override {
    (void)window;
    WarnOnce("Initialize");
    return false;
  }

  void Release() override { WarnOnce("Release"); }

  void Render(const void *data, int width, int height, size_t pitch) override {
    (void)data;
    (void)width;
    (void)height;
    (void)pitch;
    WarnOnce("Render");
  }

  void OnSurfaceChanged(int width, int height) override {
    (void)width;
    (void)height;
    WarnOnce("OnSurfaceChanged");
  }

  int GetWidth() const override {
    return engine_ ? static_cast<int>(engine_->GetVideoWidth()) : 0;
  }

  int GetHeight() const override {
    return engine_ ? static_cast<int>(engine_->GetVideoHeight()) : 0;
  }

  bool SetScalingMode(int mode) override {
    if (!engine_) {
      return false;
    }
    engine_->SetScalingMode(mode);
    return true;
  }

  bool SetSoftwareMaxResolution(int maxWidth, int maxHeight) override {
    if (!engine_ || maxWidth <= 0 || maxHeight <= 0) {
      return false;
    }
    engine_->SetSoftwareMaxResolution(static_cast<unsigned>(maxWidth),
                                      static_cast<unsigned>(maxHeight));
    return true;
  }

  bool SetAIUpscale(bool enabled) override {
    if (!engine_) {
      return false;
    }
    engine_->SetAIUpscale(enabled);
    return true;
  }

  bool SetHwRenderAllowed(bool enabled) override {
    if (!engine_) {
      return false;
    }
    engine_->SetHwRenderAllowed(enabled);
    return true;
  }

private:
  void WarnOnce(const char *method) {
    if (warned_) {
      return;
    }
    warned_ = true;
    LOGF(LOG_WARN,
         "IRenderer::%{public}s is not bound to render thread yet",
         method);
  }

  LibretroEngine *engine_ = nullptr;
  bool warned_ = false;
};

bool ShouldLog(size_t &counter, size_t burst, size_t interval) {
  counter++;
  if (counter <= burst) {
    return true;
  }
  if (interval == 0) {
    return false;
  }
  return (counter % interval) == 0;
}

int64_t NowUs() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

bool IsGameLoadedState(EngineState state) {
  return state == EngineState::GAME_LOADED || state == EngineState::RUNNING ||
         state == EngineState::PAUSED;
}

bool IsCoreLoadedState(EngineState state) {
  return state == EngineState::CORE_LOADED || IsGameLoadedState(state);
}

bool IsExpectedLateWindowQueueDrop(bool running, EngineState state,
                                   const ThreadSafeQueue<EngineMessage> &queue) {
  if (!queue.IsClosed()) {
    return false;
  }
  return !running || state == EngineState::STOPPING ||
         state == EngineState::STOPPED;
}

bool IsValidTransition(EngineState from, EngineState to) {
  if (from == to) {
    return true;
  }
  switch (from) {
  case EngineState::INIT:
    return to == EngineState::STARTING || to == EngineState::STOPPING ||
           to == EngineState::STOPPED;
  case EngineState::STARTING:
    return to == EngineState::CORE_LOADED || to == EngineState::LOADING ||
           to == EngineState::ERROR || to == EngineState::STOPPING;
  case EngineState::CORE_LOADED:
    return to == EngineState::LOADING || to == EngineState::GAME_LOADED ||
           to == EngineState::STOPPING || to == EngineState::ERROR;
  case EngineState::LOADING:
    return to == EngineState::CORE_LOADED || to == EngineState::GAME_LOADED ||
           to == EngineState::RUNNING || to == EngineState::ERROR ||
           to == EngineState::STOPPING;
  case EngineState::GAME_LOADED:
    return to == EngineState::RUNNING || to == EngineState::PAUSED ||
           to == EngineState::CORE_LOADED || to == EngineState::STOPPING ||
           to == EngineState::ERROR;
  case EngineState::RUNNING:
    return to == EngineState::PAUSED || to == EngineState::STOPPING ||
           to == EngineState::CORE_LOADED || to == EngineState::ERROR;
  case EngineState::PAUSED:
    return to == EngineState::RUNNING || to == EngineState::STOPPING ||
           to == EngineState::CORE_LOADED || to == EngineState::ERROR;
  case EngineState::STOPPING:
    return to == EngineState::STOPPED;
  case EngineState::STOPPED:
    return to == EngineState::STARTING || to == EngineState::INIT ||
           to == EngineState::LOADING; // Audit T2-F1: allow STOPPED→LOADING
  case EngineState::ERROR:
    return to == EngineState::STOPPING || to == EngineState::INIT ||
           to == EngineState::STARTING;
  default:
    return false;
  }
}
} // namespace

LibretroEngine::LibretroEngine() {
  LOGF(LOG_INFO, "[NEW] LibretroEngine Created");
  g_engineInstance.store(this, std::memory_order_release);

  // Initialize InputManager
  inputManager_ = std::make_unique<InputManager>(&eventBridge_);
  inputPortRouter_ = std::make_unique<InputPortRouter>(inputManager_.get());
  inputManager_->SetPortRouter(inputPortRouter_.get());
  inputManager_->SetControllerPortDeviceCallback(
      [this](unsigned port, unsigned device) {
        SetControllerPortDevice(port, device);
      });
  rendererInterface_ = std::make_unique<EngineRendererAdapter>(this);
  renderThread_ = std::make_unique<RenderThread>(videoPipeline_, envState_);
  renderThread_->SetNativeVSyncEnabled(
      native_vsync_enabled_.load(std::memory_order_relaxed));
  videoPipeline_.SetGlesDiagnosticsEnabled(
      gles_diag_enabled_.load(std::memory_order_relaxed));
  // Initialize CoreStateManager
  stateManager_ = std::make_unique<CoreStateManager>(coreLoader_);
  // Initialize DiskController
  diskController_ = std::make_unique<DiskController>();
  // HW Render framebuffer provider
  SetGlobalHwRenderFramebufferCallback([]() -> uintptr_t {
    LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
    if (!engine) {
      return 0;
    }
    return engine->GetHwRenderFramebuffer();
  });

  lastTickTime_ = std::chrono::steady_clock::now();
  lastFpsTime_ = 0;
  frameCount_ = 0;
  currentFps_ = 0.0f;
  SetPhase(EnginePhase::IDLE);
}

LibretroEngine *LibretroEngine::GetInstance() {
  static LibretroEngine instance;
  return &instance;
}

LibretroEngine::~LibretroEngine() {
  const bool stopped = Stop();
  if (!stopped && gameThread_.joinable()) {
    LOGF(LOG_ERROR,
         "[NEW] Destructor fallback join: waiting for game thread after stop timeout");
    gameThread_.join();
    running_ = false;
    stopRequested_.store(false);
    stopTimedOut_.store(false);
    stopInProgress_.store(false);
    state_.store(EngineState::STOPPED);
    stateCond_.notify_all();
  }
  g_engineInstance.store(nullptr, std::memory_order_release);
  LOGF(LOG_INFO, "[NEW] LibretroEngine Destroyed");
}

void LibretroEngine::SetPhase(EnginePhase phase) {
  phase_.store(phase, std::memory_order_release);
  phaseStartUs_.store(NowUs(), std::memory_order_release);
}

const char *LibretroEngine::PhaseToString(EnginePhase phase) {
  switch (phase) {
  case EnginePhase::IDLE:
    return "IDLE";
  case EnginePhase::WAIT_MESSAGE:
    return "WAIT_MESSAGE";
  case EnginePhase::PROCESS_FRAME:
    return "PROCESS_FRAME";
  case EnginePhase::RETRO_RUN:
    return "RETRO_RUN";
  case EnginePhase::VIDEO_RENDER:
    return "VIDEO_RENDER";
  case EnginePhase::VULKAN_ACQUIRE:
    return "VULKAN_ACQUIRE";
  case EnginePhase::STOP_WAIT:
    return "STOP_WAIT";
  default:
    return "UNKNOWN";
  }
}

int64_t LibretroEngine::GetPhaseDurationMs() const {
  const int64_t startUs = phaseStartUs_.load(std::memory_order_acquire);
  if (startUs <= 0) {
    return 0;
  }
  const int64_t nowUs = NowUs();
  if (nowUs <= startUs) {
    return 0;
  }
  return (nowUs - startUs) / 1000;
}

bool LibretroEngine::Start() {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  LOGF(LOG_INFO, " [NEW] LibretroEngine::Start() called");
  if (startInProgress_.exchange(true)) {
    LOGF(LOG_WARN, "[NEW] Start ignored: start already in progress");
    SetLastErrorInfo("start_in_progress", "Start",
                     "Start ignored: start already in progress");
    return false;
  }
  // RAII guard: reset startInProgress_ on all exit paths, including exceptions
  // thrown by std::thread construction or any early-return below.
  struct StartGuard {
    std::atomic<bool> &flag;
    bool released = false;
    explicit StartGuard(std::atomic<bool> &f) : flag(f) {}
    void release() { released = true; }
    ~StartGuard() {
      if (!released) {
        flag.store(false);
      }
    }
  } startGuard(startInProgress_);
  struct RunningGuard {
    std::atomic<bool> &flag;
    bool released = false;
    explicit RunningGuard(std::atomic<bool> &f) : flag(f) {}
    void release() { released = true; }
    ~RunningGuard() {
      if (!released) {
        flag.store(false, std::memory_order_release);
      }
    }
  };

  if (stopInProgress_.load()) {
    LOGF(LOG_WARN, "[NEW] Start ignored: stop in progress");
    SetLastErrorInfo("start_blocked_stop_in_progress", "Start",
                     "Start ignored: stop in progress");
    return false;
  }
  if (stopTimedOut_.load()) {
    LOGF(LOG_ERROR, "[NEW] Start blocked: previous stop timed out");
    SetLastErrorInfo("start_blocked_stop_timeout", "Start",
                     "previous stop timed out; call refactoredResetEngine");
    return false;
  }
  if (running_) {
    LOGF(LOG_WARN, "[NEW] Already running, skip Start");
    return true;
  }

  // 统一重置所有状态（解决重入问题）
  Reset();
  stopRequested_.store(false);
  gameLoopExited_.store(false);
  TransitionTo(EngineState::STARTING);

  running_.store(true);
  RunningGuard runningGuard(running_);
  // std::thread constructor may throw std::system_error if thread creation
  // fails. The StartGuard above ensures startInProgress_ is reset in that case.
  try {
    gameThread_ = std::thread(&LibretroEngine::GameLoop, this);
  } catch (const std::exception &e) {
    const std::string message = std::string("game thread start failed: ") + e.what();
    LOGF(LOG_ERROR, "[NEW] %{public}s", message.c_str());
    SetLastErrorInfo("game_thread_start_failed", "Start", message);
    TransitionTo(EngineState::ERROR);
    return false;
  } catch (...) {
    const std::string message = "game thread start failed: unknown exception";
    LOGF(LOG_ERROR, "[NEW] %{public}s", message.c_str());
    SetLastErrorInfo("game_thread_start_failed", "Start", message);
    TransitionTo(EngineState::ERROR);
    return false;
  }
  if (renderThread_ && render_thread_enabled_.load(std::memory_order_relaxed)) {
    renderThread_->SetEnabled(true);
    renderThread_->SetNativeVSyncEnabled(
        native_vsync_enabled_.load(std::memory_order_relaxed));
    if (!renderThread_->Start()) {
      const std::string message = "render thread start returned false";
      LOGF(LOG_ERROR, "[NEW] %{public}s", message.c_str());
      SetLastErrorInfo("render_thread_start_failed", "Start", message);
      stopRequested_.store(true, std::memory_order_release);
      messageQueue_.Close();
      if (gameThread_.joinable()) {
        gameThread_.join();
      }
      TransitionTo(EngineState::ERROR);
      return false;
    }
  }
  LOGF(LOG_INFO, " [NEW] Engine Thread Started");
  runningGuard.release();
  startGuard.release();
  startInProgress_.store(false);

  auto scopedWindowInit = windowGuard_.AcquireWindow();
  OHNativeWindow *windowSnapshot = scopedWindowInit.Get();
  if (windowSnapshot) {
    uint64_t generation = surface_generation_.load(std::memory_order_acquire);
    if (generation == 0) {
      generation =
          surface_generation_.fetch_add(1, std::memory_order_acq_rel) + 1;
    }
    if (surface_session_id_.load(std::memory_order_acquire) == 0) {
      surface_session_id_.store(1, std::memory_order_release);
    }
    if (!messageQueue_.Push(EngineMessage::MakeWindowMessage(
            MessageType::WindowCreated, windowSnapshot, false, generation))) {
      LOGF(LOG_WARN, "[NEW] WindowCreated dropped: message queue closed");
    }
    const int cachedW = last_window_width_.load();
    const int cachedH = last_window_height_.load();
    surface_state_.store((cachedW > 0 && cachedH > 0) ? SurfaceState::VALID
                                                      : SurfaceState::CREATED,
                         std::memory_order_release);
    if (cachedW > 0 && cachedH > 0) {
      if (!messageQueue_.Push(
              EngineMessage::MakeWindowResizeMessage(cachedW, cachedH))) {
        LOGF(LOG_WARN, "[NEW] WindowResized dropped: message queue closed");
      }
    }
  }
  return true;
}

bool LibretroEngine::Stop() {
  // Audit T2-F4: unique_lock so we can release before blocking wait
  std::unique_lock<std::recursive_mutex> ctrlLock(controlMutex_);
  if (stopInProgress_.exchange(true)) {
    LOGF(LOG_WARN, "[NEW] Stop ignored: stop already in progress");
    return false;
  }
  if (!running_) {
    stopInProgress_.store(false);
    return true;
  }

  LOGF(LOG_INFO, " [NEW] Stopping Engine...");
  // Stop() 作为一次新的生命周期收敛操作，先清掉旧错误；
  // 后续停机阶段产生的新错误必须保留下来，不能在末尾再无条件清空。
  ClearLastErrorInfo();
  const EnginePhase phase = phase_.load(std::memory_order_acquire);
  const int64_t phaseMs = GetPhaseDurationMs();
  LOGF(LOG_INFO,
       "[NEW] Stop requested: phase=%{public}s, phase_ms=%{public}lld",
       PhaseToString(phase), static_cast<long long>(phaseMs));

  // 发送停止消息并关闭队列
  // 由引擎线程处理状态切换与清理，避免提前进入 STOPPING 跳过 Stop 消息。
  if (!messageQueue_.Push({MessageType::Stop, {}})) {
    LOGF(LOG_WARN, "[NEW] Stop dropped: message queue closed");
    stopInProgress_.store(false);
    return false;
  }
  messageQueue_.Close();
  ctrlLock.unlock(); // Audit T2-F4: release controlMutex_ before 5s wait

  constexpr uint32_t STOP_TIMEOUT_MS = 5000;
  bool exited = false;
  {
    std::unique_lock<std::mutex> lock(stopMutex_);
    exited =
        stopCond_.wait_for(lock, std::chrono::milliseconds(STOP_TIMEOUT_MS),
                           [this]() { return gameLoopExited_.load(); });
  }
  if (!exited) {
    if (renderThread_) {
      renderThread_->Stop();
    }
    stopTimedOut_.store(true);
    LOGF(LOG_ERROR, "[NEW] Stop timeout after %{public}u ms", STOP_TIMEOUT_MS);
    const EnginePhase currentPhase = phase_.load(std::memory_order_acquire);
    const int64_t currentPhaseMs = GetPhaseDurationMs();
    const std::string phaseName = PhaseToString(currentPhase);
    const std::string timeoutMsg =
        "phase=" + phaseName + ", phase_ms=" + std::to_string(currentPhaseMs);
    LOGF(LOG_ERROR,
         "[NEW] Stop timeout phase=%{public}s, phase_ms=%{public}lld",
         phaseName.c_str(), static_cast<long long>(currentPhaseMs));
    SetLastErrorInfo("stop_timeout", phaseName, timeoutMsg);
    stopInProgress_.store(false);
    return false;
  }

  if (gameThread_.joinable()) {
    gameThread_.join();
  }
  if (renderThread_) {
    renderThread_->Stop();
  }

  running_.store(false);
  TransitionTo(EngineState::STOPPED);
  stopRequested_.store(false);
  stopTimedOut_.store(false);
  stopInProgress_.store(false);
  LOGF(LOG_INFO, " [NEW] Engine Stopped");
  return true;
}

void LibretroEngine::Reset() {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  LOGF(LOG_INFO, " [NEW] LibretroEngine::Reset() - Resetting all state");

  // 1. 确保引擎已停止
  if (running_) {
    LOGF(LOG_WARN, "[NEW] Reset called while running, stopping first...");
    if (!Stop()) {
      LOGF(LOG_ERROR,
           "[NEW] Reset aborted: stop did not complete, skip destructive cleanup");
      return;
    }
  }
  if (renderThread_) {
    renderThread_->Stop();
    renderThread_->ResetStats();
  }

  stopRequested_.store(false);
  stopTimedOut_.store(false);
  startInProgress_.store(false);
  stopInProgress_.store(false);
  {
    std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
    pendingFilesDir_.clear();
  }

  // 2. 重置消息队列（清空残留消息并重新打开）
  messageQueue_.Reopen();
  LOGF(LOG_INFO, "[NEW]    MessageQueue cleared and reopened");

  // 3. 卸载核心（如果已加载）
  if (coreLoader_.IsLoaded()) {
    LOGF(LOG_INFO, "[NEW]    Unloading core...");
    UnloadGameIfNeeded("reset");
    if (coreLoader_.GetDeinit()) {
      coreLoader_.GetDeinit()();
    }
    coreLoader_.UnloadCore();
    LOGF(LOG_INFO, "[NEW]    Core unloaded");
  }
  envState_.ResetCoreState();

  // 4. 重置 AudioBridge
  auto *audioBridge = AudioBridge::GetInstance();
  if (audioBridge) {
    audioBridge->Stop();
    LOGF(LOG_INFO, "%{public}s AudioBridge stopped", kAudioChainPrefix);
  }

  // 5. 重置引擎状态。Reset 是强制收敛入口，不能受普通状态迁移表限制。
  // P2-5: 直接写 state_ 后必须持 stateMutex_ 再 notify_all，与 TransitionTo
  // 保持一致，防止 WaitForState 的 wait_for 在 store 和 notify 之间醒来后
  // 重新进入等待，导致永久阻塞。
  state_.store(EngineState::INIT);
  {
    std::lock_guard<std::mutex> lk(stateMutex_);
    stateCond_.notify_all();
  }
  eventBridge_.Emit("engine_state", "{\"state\": 0}", false);
  ClearLastErrorInfo();
  frameCount_ = 0;
  currentFps_ = 0.0f;
  hasSystemInfo_ = false;
  currentCorePath_.clear();
  currentGamePath_.clear();
  currentGameData_.reset();
  gameLoaded_.store(false, std::memory_order_release);
  videoWidth_ = 0;
  videoHeight_ = 0;
  videoMaxWidth_ = 0;
  videoMaxHeight_ = 0;
  targetFps_ = 60.0;
  videoPipeline_.SetTargetFps(60.0);
  audioSampleRate_ = 44100.0;

  videoPipeline_.ClearFrameCache();
  videoPipeline_.ForceReconfiguration();
  frameBufferPool_.Clear();
  windowMessageDropLogCount_ = 0;
  windowResizeDropLogCount_ = 0;
  surfaceInvalidDropLogCount_ = 0;
  surface_state_.store(SurfaceState::UNINITIALIZED, std::memory_order_release);
  surface_session_id_.store(0, std::memory_order_release);
  surface_generation_.store(0, std::memory_order_release);
  lastAudioStatusEmitUs_.store(0, std::memory_order_release);

  // 6. 重置输入快照
  // 6. 重置输入快照
  if (inputManager_) {
    inputManager_->Clear();
  }

  LOGF(LOG_INFO, " [NEW] Reset complete - Ready for fresh start");
}

void LibretroEngine::UnloadGameIfNeeded(const char *reason) {
  if (!coreLoader_.IsLoaded()) {
    return;
  }
  auto unload = coreLoader_.GetUnloadGame();
  if (!unload) {
    return;
  }
  if (!gameLoaded_.load(std::memory_order_acquire)) {
    return;
  }
  LOGF(LOG_INFO, "[NEW] Unloading game (%{public}s)",
       reason ? reason : "unknown");
  unload();
  gameLoaded_.store(false, std::memory_order_release);
  TransitionTo(EngineState::CORE_LOADED);
  currentGamePath_.clear();
  currentGameData_.reset();
  envState_.ClearInputDescriptorMask();
}

bool LibretroEngine::Pause() {
  if (!messageQueue_.Push({MessageType::Pause, {}})) {
    LOGF(LOG_WARN, "[NEW] Pause dropped: message queue closed");
    SetLastErrorInfo("pause_dispatch_failed", "Pause",
                     "message queue closed before pause dispatch");
    return false;
  }
  return true;
}

bool LibretroEngine::Resume() {
  if (!messageQueue_.Push({MessageType::Resume, {}})) {
    LOGF(LOG_WARN, "[NEW] Resume dropped: message queue closed");
    SetLastErrorInfo("resume_dispatch_failed", "Resume",
                     "message queue closed before resume dispatch");
    return false;
  }
  return true;
}

bool LibretroEngine::Cancel() {
  LOGF(LOG_INFO, "[NEW] Cancel called");
  if (!messageQueue_.Push({MessageType::Cancel, {}})) {
    LOGF(LOG_WARN, "[NEW] Cancel dropped: message queue closed");
    SetLastErrorInfo("cancel_dispatch_failed", "Cancel",
                     "message queue closed before cancel dispatch");
    return false;
  }
  return true;
}

bool LibretroEngine::LoadCore(const std::string &corePath) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  if (IsMessagePathTooLong(corePath)) {
    LOGF(LOG_ERROR,
         "[NEW] LoadCore rejected: path too long (%{public}zu >= %{public}zu)",
         corePath.size(), EngineMessageLoadPath::kPathCapacity);
    SetLastErrorInfo("core_path_too_long", "LoadCore",
                     "core path exceeds EngineMessageLoadPath capacity");
    return false;
  }
  // 自动启动引擎（如果未运行）
  if (!running_) {
    LOGF(LOG_INFO, "[NEW] LoadCore: Engine not running, auto-starting...");
    if (!Start()) {
      LOGF(LOG_ERROR, "[NEW] LoadCore aborted: auto-start failed");
      if (GetLastErrorInfo().reason.empty()) {
        SetLastErrorInfo("core_start_failed", "LoadCore",
                         "LoadCore auto-start failed");
      }
      return false;
    }
  }
  if (!messageQueue_.Push(
          EngineMessage::MakeLoadMessage(MessageType::LoadCore, corePath))) {
    LOGF(LOG_WARN, "[NEW] LoadCore dropped: message queue closed");
    SetLastErrorInfo("core_load_queue_closed", "LoadCore",
                     "LoadCore message queue closed");
    return false;
  }
  return true;
}

bool LibretroEngine::LoadGame(const std::string &gamePath,
                              std::shared_ptr<std::vector<uint8_t>> data) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  if (IsMessagePathTooLong(gamePath)) {
    LOGF(LOG_ERROR,
         "[NEW] LoadRom rejected: path too long (%{public}zu >= %{public}zu)",
         gamePath.size(), EngineMessageLoadPath::kPathCapacity);
    SetLastErrorInfo("rom_path_too_long", "LoadGame",
                     "rom path exceeds EngineMessageLoadPath capacity");
    return false;
  }
  if (!messageQueue_.Push(EngineMessage::MakeLoadMessage(MessageType::LoadRom,
                                                         gamePath, data))) {
    LOGF(LOG_WARN, "[NEW] LoadRom dropped: message queue closed");
    SetLastErrorInfo("rom_load_queue_closed", "LoadGame",
                     "LoadGame message queue closed");
    return false;
  }
  return true;
}

void LibretroEngine::SetNativeWindow(const std::string &xcomponentId,
                                     OHNativeWindow *window,
                                     bool forceRebind) {
  LOGF(LOG_INFO,
       "[NEW] Engine: SetNativeWindow %{public}s %{public}p "
       "(force=%{public}d)",
       xcomponentId.c_str(), window, forceRebind ? 1 : 0);

  bool changed = false;
  uint64_t generation = 0;
  bool bumpSession = false;
  bool generationBumped = false;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    auto currentWindow = windowGuard_.AcquireWindow();
    if (current_xcomponent_id_ != xcomponentId || currentWindow.Get() != window) {
      changed = true;
      windowGuard_.SetWindow(window);
      current_xcomponent_id_ = xcomponentId;
      bumpSession = true;
    }

    const bool bumpGeneration = changed || (forceRebind && window != nullptr);
    if (bumpGeneration) {
      generation = surface_generation_.fetch_add(1, std::memory_order_acq_rel) + 1;
      bumpSession = true;
      generationBumped = true;
    } else {
      generation = surface_generation_.load(std::memory_order_acquire);
    }
  }
  if (bumpSession) {
    surface_session_id_.fetch_add(1, std::memory_order_acq_rel);
  }
  if (generationBumped && renderThread_) {
    renderThread_->InvalidateFrameQueueForGeneration(generation);
  }

  if (changed) {
    last_window_width_.store(0);
    last_window_height_.store(0);
  }

  if (!window) {
    surface_state_.store(SurfaceState::DESTROYED, std::memory_order_release);
  } else {
    const int cachedW = last_window_width_.load(std::memory_order_acquire);
    const int cachedH = last_window_height_.load(std::memory_order_acquire);
    const SurfaceState next = (cachedW > 0 && cachedH > 0)
                                  ? SurfaceState::VALID
                                  : SurfaceState::CREATED;
    surface_state_.store(next, std::memory_order_release);
  }

  // 统一窗口事件：由 generation 显式驱动重绑，不再发送隐式 WindowRebind。
  const bool needWindowMessage = changed || (forceRebind && window != nullptr);
  if (needWindowMessage) {
    if (!messageQueue_.Push(EngineMessage::MakeWindowMessage(
            window ? MessageType::WindowCreated : MessageType::WindowDestroyed,
            window, false, generation))) {
      const EngineState stateSnapshot = state_.load(std::memory_order_acquire);
      const bool runningSnapshot = running_.load(std::memory_order_acquire);
      if (IsExpectedLateWindowQueueDrop(runningSnapshot, stateSnapshot,
                                        messageQueue_)) {
        return;
      }
      windowMessageDropLogCount_++;
      if (windowMessageDropLogCount_ <= 5 ||
          (windowMessageDropLogCount_ % 60) == 0) {
        const int cachedW = last_window_width_.load();
        const int cachedH = last_window_height_.load();
        LOGF(LOG_WARN,
             "[NEW] Window message dropped: queue closed (running=%{public}d, "
             "state=%{public}d, cached=%{public}dx%{public}d)",
             running_.load() ? 1 : 0, static_cast<int>(state_.load()), cachedW,
             cachedH);
      }
    }
  }

  // NativeWindow 生命周期只通过消息交给引擎线程/渲染线程处理。
}

void LibretroEngine::ClearNativeWindowIfMatch(const std::string &xcomponentId,
                                              OHNativeWindow *destroyedWindow) {
  bool match = false;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    auto currentWindow = windowGuard_.AcquireWindow();
    if (current_xcomponent_id_ != xcomponentId) {
      match = false;
    } else if (destroyedWindow) {
      match = (currentWindow.Get() == destroyedWindow);
    } else {
      match = (currentWindow.Get() != nullptr);
    }
  }

  if (match) {
    SetNativeWindow(xcomponentId, nullptr, false);
  }
}

void LibretroEngine::OnNativeWindowResized(const std::string &xcomponentId,
                                           int width, int height) {
  LOGF(LOG_INFO,
       " [NEW] Engine: OnNativeWindowResized %{public}s %{public}dx%{public}d",
       xcomponentId.c_str(), width, height);
  bool hasWindow = false;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    auto currentWindow = windowGuard_.AcquireWindow();
    hasWindow = (currentWindow.Get() != nullptr && current_xcomponent_id_ == xcomponentId);
  }
  if (width > 0 && height > 0) {
    if (hasWindow) {
      last_window_width_.store(width);
      last_window_height_.store(height);
    }
  }
  if (hasWindow) {
    // 只有在窗口有有效尺寸后，才允许进入渲染路径。
    // 无效尺寸（最小化/小窗过渡）进入 PAUSED，严格禁止提交 buffer。
    const SurfaceState previous = surface_state_.load(std::memory_order_acquire);
    if (width > 0 && height > 0) {
      surface_state_.store(SurfaceState::VALID, std::memory_order_release);
      if (previous != SurfaceState::VALID) {
        const uint64_t generation =
            surface_generation_.fetch_add(1, std::memory_order_acq_rel) + 1;
        surface_session_id_.fetch_add(1, std::memory_order_acq_rel);
        if (renderThread_) {
          renderThread_->InvalidateFrameQueueForGeneration(generation);
        }
        auto scopedWindowResize = windowGuard_.AcquireWindow();
        OHNativeWindow *windowSnapshot = scopedWindowResize.Get();
        if (windowSnapshot &&
            !messageQueue_.Push(
                EngineMessage::MakeWindowMessage(MessageType::WindowCreated,
                                                 windowSnapshot, false,
                                                 generation))) {
          const EngineState stateSnapshot =
              state_.load(std::memory_order_acquire);
          const bool runningSnapshot = running_.load(std::memory_order_acquire);
          if (IsExpectedLateWindowQueueDrop(runningSnapshot, stateSnapshot,
                                            messageQueue_)) {
            return;
          }
          windowResizeDropLogCount_++;
          if (windowResizeDropLogCount_ <= 5 ||
              (windowResizeDropLogCount_ % 60) == 0) {
            LOGF(LOG_WARN,
                 "[NEW] WindowCreated on resize recovery dropped: gen=%{public}llu",
                 static_cast<unsigned long long>(generation));
          }
        }
      }
    } else {
      surface_state_.store(SurfaceState::PAUSED, std::memory_order_release);
    }
  }
  if (hasWindow) {
    // 由引擎线程处理 Resize，避免 UI 线程触碰 EGL/GL。
    // 使用合并策略：如果队列尾部已经是 Resize 消息，则更新为最新尺寸
    auto coalesceFunc = [](const EngineMessage &back,
                           const EngineMessage &incoming) {
      return back.type == MessageType::WindowResized &&
             incoming.type == MessageType::WindowResized;
    };

    if (!messageQueue_.PushCoalesce(
            EngineMessage::MakeWindowResizeMessage(width, height),
            coalesceFunc)) {
      const EngineState stateSnapshot = state_.load(std::memory_order_acquire);
      const bool runningSnapshot = running_.load(std::memory_order_acquire);
      if (IsExpectedLateWindowQueueDrop(runningSnapshot, stateSnapshot,
                                        messageQueue_)) {
        return;
      }
      windowResizeDropLogCount_++;
      if (windowResizeDropLogCount_ <= 5 ||
          (windowResizeDropLogCount_ % 60) == 0) {
        const int cachedW = last_window_width_.load();
        const int cachedH = last_window_height_.load();
        LOGF(LOG_WARN,
             "[NEW] WindowResized dropped: queue closed "
             "(size=%{public}dx%{public}d, cached=%{public}dx%{public}d, "
             "running=%{public}d, state=%{public}d)",
             width, height, cachedW, cachedH, running_.load() ? 1 : 0,
             static_cast<int>(state_.load()));
      }
    }
  }
}

bool LibretroEngine::DispatchKeyboardEvent(bool down, unsigned keycode,
                                           uint32_t character,
                                           uint16_t key_modifiers) {
  auto dispatchNow = [this, down, keycode, character, key_modifiers]() -> bool {
    if (!coreLoader_.IsLoaded()) {
      return false;
    }
    const ::retro_keyboard_callback *callback = envState_.GetKeyboardCallback();
    if (!callback || !callback->callback) {
      return false;
    }
    callback->callback(down, keycode, character, key_modifiers);
    return true;
  };

  // Engine 线程或未运行状态下，直接执行（避免无意义排队）。
  if (g_engineThreadInstance == this ||
      !running_.load(std::memory_order_acquire)) {
    return dispatchNow();
  }

  // 输入线程（如 UI/MMI）禁止同步等待 Engine，避免 APP_INPUT_BLOCK。
  auto syncTask = std::make_shared<EngineSyncTask>(
      [this, down, keycode, character, key_modifiers]() {
        if (!coreLoader_.IsLoaded()) {
          return;
        }
        const ::retro_keyboard_callback *callback =
            envState_.GetKeyboardCallback();
        if (!callback || !callback->callback) {
          return;
        }
        callback->callback(down, keycode, character, key_modifiers);
      });

  if (!messageQueue_.Push(EngineMessage::MakeSyncTaskMessage(syncTask))) {
    LOGF(LOG_WARN, "[NEW] DispatchKeyboardEvent dropped: message queue closed");
    return false;
  }
  return true;
}

bool LibretroEngine::SetFilesDir(const std::string &filesDir) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  if (IsMessagePathTooLong(filesDir)) {
    LOGF(LOG_ERROR,
         "[NEW] SetFilesDir rejected: path too long (%{public}zu >= %{public}zu)",
         filesDir.size(), EngineMessageLoadPath::kPathCapacity);
    SetLastErrorInfo("files_dir_path_too_long", "SetFilesDir",
                     "filesDir exceeds EngineMessageLoadPath capacity");
    return false;
  }
  const EngineState st = state_.load();
  if (IsCoreLoadedState(st) || st == EngineState::LOADING ||
      st == EngineState::STOPPING) {
    LOGF(LOG_WARN, "[NEW] SetFilesDir ignored after core loaded: %{public}s",
         security::DescribePathForLog(filesDir).c_str());
    SetLastErrorInfo("files_dir_set_ignored_state", "SetFilesDir",
                     "SetFilesDir ignored due current engine state");
    return false;
  }

  if (running_.load()) {
    {
      std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
      pendingFilesDir_ = filesDir;
    }
    bool applyOk = false;
    const bool dispatched = ExecuteSyncTask(
        [this, &filesDir, &applyOk]() { applyOk = ApplyFilesDir(filesDir); },
        kSyncTaskTimeoutMs);
    if (!dispatched) {
      std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
      pendingFilesDir_.clear();
      SetLastErrorInfo("files_dir_sync_dispatch_failed", "SetFilesDir",
                       "failed to dispatch SetFilesDir sync task");
      return false;
    }
    if (!applyOk) {
      std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
      pendingFilesDir_.clear();
      return false;
    }
    return true;
  }

  // 引擎未运行时可直接设置（无并发读写）
  return ApplyFilesDir(filesDir);
}

std::string LibretroEngine::GetFilesDir() const {
  {
    std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
    if (!pendingFilesDir_.empty()) {
      return pendingFilesDir_;
    }
  }
  const char *dir = envState_.GetBaseDir();
  return dir ? std::string(dir) : "";
}

interfaces::IRenderer *LibretroEngine::GetRendererInterface() const {
  return rendererInterface_.get();
}

bool LibretroEngine::ExecuteSyncTask(const std::function<void()> &task,
                                     uint32_t timeoutMs,
                                     const char *operation) {
  const std::string opName =
      (operation && operation[0] != '\0') ? operation : "ExecuteSyncTask";
  if (!task) {
    SetLastErrorInfo("sync_task_missing", opName,
                     "sync task callback is null");
    return false;
  }
  if (g_engineThreadInstance == this || !running_.load()) {
    task();
    return true;
  }
  if (messageQueue_.IsClosed()) {
    LOGF(LOG_WARN, "[NEW] SyncTask dropped: message queue closed");
    SetLastErrorInfo("sync_task_queue_closed", opName,
                     "message queue closed before sync task dispatch");
    return false;
  }

  auto syncTask = std::make_shared<EngineSyncTask>(task);
  if (!messageQueue_.Push(EngineMessage::MakeSyncTaskMessage(syncTask))) {
    LOGF(LOG_WARN, "[NEW] SyncTask push failed: message queue closed");
    SetLastErrorInfo("sync_task_dispatch_failed", opName,
                     "message queue rejected sync task");
    return false;
  }
  if (!syncTask->Wait(timeoutMs)) {
    LOGF(LOG_ERROR, "[NEW] SyncTask timeout after %{public}u ms", timeoutMs);
    SetLastErrorInfo("sync_task_timeout", opName,
                     "sync task timed out waiting for engine thread");
    return false;
  }
  return true;
}

bool LibretroEngine::ApplyFilesDir(const std::string &filesDir) {
  if (!envState_.SetBaseDir(filesDir)) {
    LOGF(LOG_ERROR, "[NEW] EnvState BaseDir set failed: %{public}s",
         security::DescribePathForLog(filesDir).c_str());
    SetLastErrorInfo("files_dir_env_set_failed", "SetFilesDir",
                     "EnvState::SetBaseDir failed");
    return false;
  }
  {
    std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
    if (pendingFilesDir_ == filesDir) {
      pendingFilesDir_.clear();
    }
  }
  LOGF(LOG_INFO, "[NEW] EnvState BaseDir set: %{public}s",
       security::DescribePathForLog(filesDir).c_str());
  return true;
}

void LibretroEngine::SetMinimumAudioLatency(unsigned latency_ms) {
  envState_.SetPendingMinimumAudioLatencyMs(latency_ms);
}

void LibretroEngine::SetAIUpscale(bool enabled) {
  videoPipeline_.SetXEngineEnabled(enabled);
}

void LibretroEngine::SetHwRenderAllowed(bool allowed) {
  envState_.SetHwRenderAllowed(allowed);
  LOGF(LOG_INFO, "HW render allowed set to: %{public}d", allowed ? 1 : 0);
}

void LibretroEngine::SetRenderThreadEnabled(bool enabled) {
  const bool current =
      render_thread_enabled_.load(std::memory_order_acquire);
  if (current == enabled) {
    return;
  }

  if (!enabled) {
    LOGF(LOG_WARN,
         "SetRenderThreadEnabled(false) ignored: RenderThread is mandatory");
    return;
  }
  // Keep API compatibility: render thread is always enabled in unified pipeline.
  render_thread_enabled_.store(true, std::memory_order_release);
}

void LibretroEngine::SetNativeVSyncEnabled(bool enabled) {
  native_vsync_enabled_.store(enabled, std::memory_order_release);
  if (renderThread_) {
    renderThread_->SetNativeVSyncEnabled(enabled);
  }
  LOGF(LOG_INFO, "Native VSync enabled set to: %{public}d",
       enabled ? 1 : 0);
}

void LibretroEngine::SetGlesDiagEnabled(bool enabled) {
  gles_diag_enabled_.store(enabled, std::memory_order_release);
  videoPipeline_.SetGlesDiagnosticsEnabled(enabled);
  LOGF(LOG_INFO, "GLES diagnostics enabled set to: %{public}d",
       enabled ? 1 : 0);
}

RuntimeStats LibretroEngine::GetStats() const {
  RuntimeStats snapshot;
  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    snapshot = stats_;
  }

  if (render_thread_enabled_.load(std::memory_order_acquire) && renderThread_) {
    const auto renderStats = renderThread_->GetStats();
    snapshot.videoDroppedFrames += renderStats.droppedFrames;
    snapshot.nwRequestBufferCalls += renderStats.nwRequestBufferCalls;
    snapshot.nwRequestBufferFailures += renderStats.nwRequestBufferFailures;
    snapshot.nwFlushBufferCalls += renderStats.nwFlushBufferCalls;
    snapshot.nwFlushBufferFailures += renderStats.nwFlushBufferFailures;
    snapshot.nwAbortBufferCalls += renderStats.nwAbortBufferCalls;
    snapshot.nbFromWindowBufferFailures +=
        renderStats.nbFromWindowBufferFailures;
    snapshot.nbMapFailures += renderStats.nbMapFailures;
    snapshot.nbUnmapFailures += renderStats.nbUnmapFailures;
    snapshot.fenceWaitCalls += renderStats.fenceWaitCalls;
    snapshot.fenceWaitFailures += renderStats.fenceWaitFailures;
    snapshot.fenceTimeoutCount += renderStats.fenceTimeoutCount;

    if (renderStats.frameTimeCount > 0) {
      if (snapshot.frameCount == 0 || snapshot.frameTimeMin == UINT64_MAX ||
          renderStats.frameTimeMin < snapshot.frameTimeMin) {
        snapshot.frameTimeMin = renderStats.frameTimeMin;
      }
      if (renderStats.frameTimeMax > snapshot.frameTimeMax) {
        snapshot.frameTimeMax = renderStats.frameTimeMax;
      }
      snapshot.frameTimeSum += renderStats.frameTimeSum;
      snapshot.frameCount += renderStats.frameTimeCount;
    }

    snapshot.queuePushed = renderStats.queuePushed;
    snapshot.queuePopped = renderStats.queuePopped;
    snapshot.queueDroppedOldest = renderStats.queueDroppedOldest;
    snapshot.queueDroppedStaleOnPop = renderStats.queueDroppedStaleOnPop;
    snapshot.queueDepthMax = renderStats.queueDepthMax;
    snapshot.renderTickNoFrame = renderStats.renderTickNoFrame;
    snapshot.renderThreadRenderedFrames = renderStats.renderedFrames;
    snapshot.renderThreadDroppedFrames = renderStats.droppedFrames;
    snapshot.vsyncCallbacks = renderStats.vsyncCallbacks;
    snapshot.vsyncFallbackTicks = renderStats.vsyncFallbackTicks;
    snapshot.vsyncRequestFailures = renderStats.vsyncRequestFailures;
  }

  return snapshot;
}

void LibretroEngine::ResetStats() {
  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    stats_.Reset();
  }
  if (renderThread_) {
    renderThread_->ResetStats();
  }
}

bool LibretroEngine::InitializeEventBridge(napi_env env, napi_value callback) {
  return eventBridge_.Initialize(env, callback);
}

void LibretroEngine::GameLoop() {
  // API12+ QoS：将引擎主循环线程标记为最高交互优先级，
  // 强制大核调度、减少高负载抢占（音频线程已由 OH_AudioWorkgroup 覆盖，此处仅 Game 线程）。
  int qosRet = OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE);
  LOGF(LOG_INFO, "[QoS] GameLoop thread QoS set ret=%{public}d", qosRet);
  // 平台能力探测:QoS 成功(ret==0)=平台支持实时调度(真机)→ 音频走低延迟浅缓冲;
  // 失败(ret==-1,模拟器无 RT 调度)→ 音频走深缓冲扛抖动。须早于游戏加载(AudioBridge
  // ::Initialize 读此标志选 profile)注入,故置于 GameLoop 入口。
  AudioBridge::GetInstance()->SetRtSchedulingAvailable(qosRet == 0);
  LOGF(LOG_INFO, " [NEW] GameLoop Thread Entry: ID = %{public}zu",
       std::hash<std::thread::id>{}(std::this_thread::get_id()));
  g_engineThreadInstance = this;
  SetPhase(EnginePhase::IDLE);

  while (running_.load()) {
    if (stopRequested_.load()) {
      TransitionTo(EngineState::STOPPING);
      break;
    }

    // 0. 检查是否处于停止状态，若是则退出循环
    EngineState currentState = state_.load();
    if (currentState == EngineState::STOPPING ||
        currentState == EngineState::STOPPED) {
      break;
    }

    if (currentState == EngineState::RUNNING) {
      // 1. 运行态：非阻塞处理待处理消息
      EngineMessage msg;
      // 优先处理所有积压消息，直到队列为空或状态变为非运行
      while (messageQueue_.Pop(msg)) {
        LOGF(LOG_DEBUG, "HandleMessage(Running): type=%{public}d",
             static_cast<int>(msg.type));
        HandleMessage(msg);
        if (state_.load() != EngineState::RUNNING) {
          break; // 状态变更（如 Pause/Stop），立即跳出处理逻辑
        }
      }

      // 如果处理完消息后仍是运行态，则执行帧
      if (state_.load() == EngineState::RUNNING) {
        if (stopRequested_.load()) {
          TransitionTo(EngineState::STOPPING);
          break;
        }
        const auto frameStart = std::chrono::steady_clock::now();
        ProcessFrame();
        frameCount_++;

        // 节拍器：若 retro_run 内部未走视频管线节拍（如 loading、菜单态、
        // hwrender 早退路径），这里兜底 sleep 到目标帧时间，避免 frameCount
        // 飙升到 1000+ FPS。VideoPipeline 内部仍有自己的节拍，本节拍仅作上限。
        const double safeTargetFps = (targetFps_.load() > 0.0) ? targetFps_.load() : 60.0;
        const int64_t targetFrameUs =
            static_cast<int64_t>(1000000.0 / safeTargetFps);
        auto frameEnd = std::chrono::steady_clock::now();
        const int64_t elapsedUs =
            std::chrono::duration_cast<std::chrono::microseconds>(
                frameEnd - frameStart)
                .count();
        if (engineDiagWindowStart_.time_since_epoch().count() == 0) {
          engineDiagWindowStart_ = frameStart;
        }
        engineDiagFrames_++;
        if (elapsedUs > engineDiagMaxFrameUs_) {
          engineDiagMaxFrameUs_ = elapsedUs;
        }
        const int64_t lastRetroMs =
            lastRetroRunMs_.load(std::memory_order_relaxed);
        if (lastRetroMs > engineDiagMaxRetroMs_) {
          engineDiagMaxRetroMs_ = lastRetroMs;
        }
        if (elapsedUs > targetFrameUs) {
          engineDiagOverBudgetFrames_++;
        }
        const auto engineDiagElapsedMs =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                frameEnd - engineDiagWindowStart_)
                .count();
        if (engineDiagElapsedMs >= 1000) {
          auto *audioBridge = AudioBridge::GetInstance();
          int audioUsagePercent = -1;
          int audioSyncMode = -1;
          int audioPlaying = 0;
          uint64_t audioCallbackCount = 0;
          uint64_t audioCallbackFramesRead = 0;
          int64_t audioCallbackAgeMs = -1;
          const char *audioRunState = "none";
          if (audioBridge) {
            audioUsagePercent = static_cast<int>(
                audioBridge->GetBufferUsage() * 100.0f + 0.5f);
            audioSyncMode = static_cast<int>(audioBridge->GetSyncMode());
            audioPlaying = audioBridge->IsPlaying() ? 1 : 0;
            audioRunState =
                AudioBridge::AudioRunStateToString(audioBridge->GetRunState());
            uint64_t callbackCount = 0;
            uint64_t callbackFramesRead = 0;
            int64_t lastCallbackMs = 0;
            audioBridge->GetCallbackDiag(callbackCount, callbackFramesRead,
                                         lastCallbackMs);
            audioCallbackCount = callbackCount;
            audioCallbackFramesRead = callbackFramesRead;
            if (lastCallbackMs > 0) {
              const int64_t nowMs =
                  std::chrono::duration_cast<std::chrono::milliseconds>(
                      frameEnd.time_since_epoch())
                      .count();
              audioCallbackAgeMs = nowMs - lastCallbackMs;
            }
          }
          LOGF(LOG_INFO,
               "%{public}s engine_window: ms=%{public}lld, frames=%{public}llu, "
               "fps_x100=%{public}d, target_x100=%{public}d, "
               "over_budget=%{public}llu, max_frame_us=%{public}lld, "
               "max_retro_ms=%{public}lld, audio_usage=%{public}d%%, "
               "audio_state=%{public}s, audio_playing=%{public}d, "
               "sync_mode=%{public}d, audio_cb_count=%{public}llu, "
               "audio_cb_read_frames=%{public}llu, audio_cb_age_ms=%{public}lld",
               kAudioChainPrefix, static_cast<long long>(engineDiagElapsedMs),
               static_cast<unsigned long long>(engineDiagFrames_),
               static_cast<int>(engineDiagFrames_ * 100000.0 /
                                static_cast<double>(engineDiagElapsedMs)),
               static_cast<int>(safeTargetFps * 100.0),
               static_cast<unsigned long long>(engineDiagOverBudgetFrames_),
               static_cast<long long>(engineDiagMaxFrameUs_),
               static_cast<long long>(engineDiagMaxRetroMs_), audioUsagePercent,
               audioRunState, audioPlaying, audioSyncMode,
               static_cast<unsigned long long>(audioCallbackCount),
               static_cast<unsigned long long>(audioCallbackFramesRead),
               static_cast<long long>(audioCallbackAgeMs));
          engineDiagWindowStart_ = frameEnd;
          engineDiagFrames_ = 0;
          engineDiagMaxFrameUs_ = 0;
          engineDiagMaxRetroMs_ = 0;
          engineDiagOverBudgetFrames_ = 0;
        }
        const auto frameInterval = std::chrono::microseconds(targetFrameUs);
        if (nextFrameDeadline_.time_since_epoch().count() == 0 ||
            frameStart > nextFrameDeadline_ + frameInterval) {
          nextFrameDeadline_ = frameStart + frameInterval;
        } else {
          nextFrameDeadline_ += frameInterval;
        }
        auto sleepNow = std::chrono::steady_clock::now();
        while (sleepNow + std::chrono::microseconds(1500) <
               nextFrameDeadline_) {
          std::this_thread::sleep_for(std::chrono::microseconds(500));
          sleepNow = std::chrono::steady_clock::now();
        }
        while (std::chrono::steady_clock::now() < nextFrameDeadline_) {
          std::this_thread::yield();
        }
        frameEnd = std::chrono::steady_clock::now();

        // 3. 上报 FPS
        auto now = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
                            now - lastTickTime_.load())
                            .count();
        if (duration >= 1000) {
          currentFps_ = frameCount_ * 1000.0f / duration;

          // 获取统计快照
          RuntimeStats currentStats;
          {
            std::lock_guard<std::mutex> lock(statsMutex_);
            currentStats = stats_;
            // 重置周期性统计
            stats_.videoRefreshCalls = 0;
            stats_.videoNullFrames = 0;
            stats_.videoDupeFrames = 0;
            stats_.audioBatchCalls = 0;
            stats_.audioFramesIn = 0;
          }

          // 获取音频缓冲统计
          size_t audioUnderruns = 0;
          size_t audioOverruns = 0;
          float audioUsage = 0.0f;
          auto *audioBridge = AudioBridge::GetInstance();
          if (audioBridge) {
            audioBridge->GetBufferStats(audioUnderruns, audioOverruns);
            audioBridge->ResetBufferStats();
            audioUsage = audioBridge->GetBufferUsage();
          }
          const auto audioState = audioBridge ? audioBridge->GetRunState()
                                              : AudioBridge::AudioRunState::INIT;

          // 获取视频管线丢帧统计
          size_t videoDrops = videoPipeline_.GetDropCount();
          videoPipeline_.ResetDropCount();
          const auto renderModeState = videoPipeline_.GetRenderModeState();
          const auto engineSurfaceState =
              surface_state_.load(std::memory_order_acquire);
          WindowSessionSnapshot windowSnapshot{};
          if (renderThread_) {
            windowSnapshot = renderThread_->GetWindowSessionSnapshot();
          }
          const uint64_t surfaceSessionId =
              (windowSnapshot.sessionId != 0)
                  ? windowSnapshot.sessionId
                  : surface_session_id_.load(std::memory_order_acquire);
          const uint64_t surfaceGeneration =
              (windowSnapshot.generation != 0)
                  ? windowSnapshot.generation
                  : surface_generation_.load(std::memory_order_acquire);

          char fpsJson[256];
          snprintf(fpsJson, sizeof(fpsJson),
                   "{\"fps\": %.2f, \"dupes\": %llu, \"nulls\": %llu, "
                   "\"drops\": %zu, \"underruns\": %zu, \"overruns\": %zu, "
                   "\"audioBufferUsage\": %.2f}",
                   currentFps_,
                   (unsigned long long)currentStats.videoDupeFrames,
                   (unsigned long long)currentStats.videoNullFrames, videoDrops,
                   audioUnderruns, audioOverruns, audioUsage);

          LOGF(LOG_INFO,
               " [Stats] FPS: %{public}.2f | Dupes: %{public}llu | Nulls: "
               "%{public}llu | Drops: %{public}zu | Audio U/O: "
               "%{public}zu/%{public}zu | Buf: %{public}.1f%%",
               currentFps_, (unsigned long long)currentStats.videoDupeFrames,
               (unsigned long long)currentStats.videoNullFrames, videoDrops,
               audioUnderruns, audioOverruns, audioUsage * 100.0f);
          LOGF(LOG_INFO,
               " [Snapshot] sid=%{public}llu gen=%{public}llu "
               "engine_window=%{public}s render_window=%{public}s "
               "active=%{public}d size=%{public}dx%{public}d "
               "render=%{public}s audio=%{public}s",
               static_cast<unsigned long long>(surfaceSessionId),
               static_cast<unsigned long long>(surfaceGeneration),
               SurfaceStateToString(static_cast<int>(engineSurfaceState)),
               WindowSessionStateToString(windowSnapshot.state),
               windowSnapshot.active ? 1 : 0, windowSnapshot.width,
               windowSnapshot.height,
               VideoPipeline::RenderModeStateToString(renderModeState),
               AudioBridge::AudioRunStateToString(audioState));

          eventBridge_.Emit("fps_update", fpsJson, false);
          frameCount_ = 0;
          lastTickTime_.store(now);
        }
      }
    } else {
      // 2. 非运行态（INIT/PAUSED 等）：阻塞等待消息（替代 sleep_for 轮询）
      // 这样可以彻底消除空闲时的 CPU 占用，并实现零延迟响应
      EngineMessage msg;
      SetPhase(EnginePhase::WAIT_MESSAGE);
      if (messageQueue_.WaitAndPop(msg)) {
        LOGF(LOG_DEBUG, "HandleMessage(Idle): type=%{public}d",
             static_cast<int>(msg.type));
        HandleMessage(msg);
      } else {
        // 队列被关闭且为空（通常意味着 Stop 被调用或析构）
        if (messageQueue_.IsClosed() || stopRequested_.load()) {
          LOGF(LOG_INFO, "MessageQueue closed, exiting GameLoop");
          break;
        }
      }
      SetPhase(EnginePhase::IDLE);
    }
  }

  if (renderThread_) {
    renderThread_->Stop();
  }

  // RenderThread::Stop() owns all renderer teardown. Keep engine side stateless.
  videoPipeline_.Reset();

  LOGF(LOG_INFO, " [NEW] GameLoop Thread Exit");
  g_engineThreadInstance = nullptr;
  gameLoopExited_.store(true);
  stopCond_.notify_all();
}

void LibretroEngine::HandleMessage(const EngineMessage &msg) {
  switch (msg.type) {
  case MessageType::Pause:
    if (state_.load() == EngineState::RUNNING) {
      TransitionTo(EngineState::PAUSED);
    } else {
      LOGF(LOG_WARN, "[NEW] Pause ignored: state=%{public}d",
           static_cast<int>(state_.load()));
    }
    break;
  case MessageType::Resume:
    if (state_.load() == EngineState::PAUSED) {
      TransitionTo(EngineState::RUNNING);
    } else {
      LOGF(LOG_WARN, "[NEW] Resume ignored: state=%{public}d",
           static_cast<int>(state_.load()));
    }
    break;
  case MessageType::Stop:
    LOGF(LOG_INFO, "[NEW] Message: Stop Received");
    stopRequested_.store(true);
    UnloadGameIfNeeded("stop");
    TransitionTo(EngineState::STOPPING);
    break;
  case MessageType::Cancel:
    LOGF(LOG_INFO, "[NEW] Message: Cancel Received");
    // Cancel 只在 STARTING/LOADING 状态有效，直接 Reset 回 INIT
    {
      EngineState currentState = state_.load();
      if (currentState == EngineState::STARTING ||
          currentState == EngineState::LOADING ||
          currentState == EngineState::CORE_LOADED) {
        LOGF(LOG_INFO, "[NEW] Cancel: resetting from state=%{public}d",
             static_cast<int>(currentState));
        UnloadGameIfNeeded("cancel");
        if (coreLoader_.IsLoaded()) {
          if (diskController_) {
            diskController_->ClearCallbacks();
          }
          if (coreLoader_.GetDeinit()) {
            coreLoader_.GetDeinit()();
          }
          coreLoader_.UnloadCore();
        }
        envState_.ResetCoreState();
        Reset();
        TransitionTo(EngineState::INIT);
      } else {
        LOGF(LOG_WARN, "[NEW] Cancel ignored: state=%{public}d",
             static_cast<int>(currentState));
      }
    }
    break;
  case MessageType::LoadCore:
    if (!(state_.load() == EngineState::INIT ||
          state_.load() == EngineState::STARTING ||
          state_.load() == EngineState::STOPPED ||
          state_.load() == EngineState::ERROR)) {
      LOGF(LOG_WARN, "[NEW] LoadCore ignored: state=%{public}d",
           static_cast<int>(state_.load()));
      break;
    }
    TransitionTo(EngineState::LOADING);
    currentCorePath_ = msg.payload.loadPath.path;
    LOGF(LOG_INFO, "[NEW] Message: LoadCore path=%{public}s",
         security::DescribePathForLog(currentCorePath_).c_str());
    // 先卸载旧核心（如果已加载）
    if (coreLoader_.IsLoaded()) {
      LOGF(LOG_INFO, "[NEW] Unloading previous core before loading new one");
      UnloadGameIfNeeded("switch_core");
      // T8-A-F2: 在 UnloadCore (dlclose) 之前清零 DiskController callbacks_,
      // 否则 callbacks_ 持有指向已释放代码页的悬空函数指针。
      if (diskController_) {
        diskController_->ClearCallbacks();
      }
      if (coreLoader_.GetDeinit()) {
        coreLoader_.GetDeinit()();
      }
      coreLoader_.UnloadCore();
    }
    envState_.ResetCoreState();
    if (coreLoader_.LoadCore(currentCorePath_)) {
      // 设置核心路径到 EnvState
      envState_.SetLibretroPath(currentCorePath_);

      // 如果 ArkTS 未提前设置 filesDir，使用后备推断逻辑
      if (envState_.GetSystemDirectory() == nullptr ||
          strlen(envState_.GetSystemDirectory()) == 0) {
        size_t lastSlash = currentCorePath_.rfind('/');
        if (lastSlash != std::string::npos) {
          std::string baseDir = currentCorePath_.substr(0, lastSlash);
          size_t parentSlash = baseDir.rfind('/');
          if (parentSlash != std::string::npos) {
            std::string appDir = baseDir.substr(0, parentSlash);
            envState_.SetBaseDir(appDir + "/files");
            LOGF(LOG_WARN,
                 "[NEW] EnvState BaseDir (fallback): %{public}s/files",
                 security::DescribePathForLog(appDir).c_str());
          }
        }
      }

      SetupCallbacks();
      coreLoader_.GetInit()();

      // 获取核心信息
      memset(&systemInfo_, 0, sizeof(systemInfo_));
      coreLoader_.GetSystemInfo()(&systemInfo_);
      hasSystemInfo_ = true;
      LOGF(LOG_INFO,
           "[NEW] Core Info: need_fullpath=%{public}s, "
           "supports_no_game=%{public}s",
           systemInfo_.need_fullpath ? "YES" : "NO",
           envState_.SupportsNoGame() ? "YES" : "NO");

      // Detect Core Quirks
      DetectCoreQuirks();

      ClearLastErrorInfo();
      TransitionTo(EngineState::CORE_LOADED);
    } else {
      LOGF(LOG_ERROR, " [NEW] LoadCore Failed: %{public}s",
           security::DescribePathForLog(currentCorePath_).c_str());

      // 构建转义后的错误信息，避免 payload JSON 被特殊字符破坏。

      std::string step = coreLoader_.GetLastErrorStep();
      std::string msg = coreLoader_.GetLastErrorMessage();

      std::string stepEsc;
      std::string msgEsc;
      common::JsonEscape(step, stepEsc);
      common::JsonEscape(msg, msgEsc);

      std::string payload = "{\"reason\": \"core_load_failed\", \"step\": \"" +
                            stepEsc + "\", \"message\": \"" + msgEsc + "\"}";
      eventBridge_.Emit("core_crash", payload, true);
      SetLastErrorInfo("core_load_failed", step, msg);
      // 确保状态与核心实际加载状态一致，避免 UI 误判
      hasSystemInfo_ = false;
      currentCorePath_.clear();
      currentGamePath_.clear();
      currentGameData_.reset();
      gameLoaded_.store(false, std::memory_order_release);
      envState_.ClearCoreOptions();
      TransitionTo(EngineState::ERROR);
    }
    break;
  case MessageType::LoadRom: {
    EngineState prevState = state_.load();
    if (!IsCoreLoadedState(prevState)) {
      LOGF(LOG_WARN, "[NEW] LoadRom ignored: state=%{public}d",
           static_cast<int>(prevState));
      break;
    }
    currentGamePath_ = msg.payload.loadPath.path;
    currentGameData_ = msg.payload.loadPath.data;
    LOGF(LOG_INFO, "[NEW] Message: LoadRom path=%{public}s, data=%{public}s",
         security::DescribePathForLog(currentGamePath_).c_str(),
         currentGameData_ ? "YES" : "NO");
    if (!currentGamePath_.empty() &&
        !security::ValidateRomPath(currentGamePath_)) {
      LOGF(LOG_ERROR, " [NEW] LoadRom blocked: invalid ROM path %{public}s",
           security::DescribePathForLog(currentGamePath_).c_str());
      currentGamePath_.clear();
      currentGameData_.reset();
      eventBridge_.Emit("core_crash", "{\"reason\": \"rom_path_invalid\"}",
                        true);
      SetLastErrorInfo("rom_path_invalid", "", "");
      TransitionTo(EngineState::ERROR);
      break;
    }
    if (coreLoader_.IsLoaded()) {
      if (prevState == EngineState::GAME_LOADED ||
          prevState == EngineState::RUNNING ||
          prevState == EngineState::PAUSED) {
        UnloadGameIfNeeded("reload_rom");
      }
      TransitionTo(EngineState::LOADING);
      const bool emptyContent = currentGamePath_.empty() && !currentGameData_;
      if (emptyContent) {
        if (envState_.SupportsNoGame()) {
          if (prevState == EngineState::GAME_LOADED ||
              prevState == EngineState::RUNNING ||
              prevState == EngineState::PAUSED) {
            LOGF(LOG_INFO,
                 "[NEW] LoadRom ignored for no-game core (already loaded)");
            break;
          }

          LOGF(LOG_INFO, "[NEW] Empty ROM path for no-game core: calling "
                         "retro_load_game(NULL)");

          if (coreLoader_.GetLoadGame()(nullptr)) {
            gameLoaded_.store(true, std::memory_order_release);
            struct retro_system_av_info avInfo = {0};
            coreLoader_.GetSystemAvInfo()(&avInfo);

            videoWidth_ = avInfo.geometry.base_width;
            videoHeight_ = avInfo.geometry.base_height;
            targetFps_ = avInfo.timing.fps;

            auto *bridge = AudioBridge::GetInstance();
            if (bridge) {
              const bool reset_ok = bridge->Reset(avInfo.timing.sample_rate);
              LOGF(LOG_INFO,
                   "%{public}s AudioBridge reset (no-game): ok=%{public}d, "
                   "rate=%{public}.2f",
                   kAudioChainPrefix, reset_ok ? 1 : 0,
                   avInfo.timing.sample_rate);
              if (!reset_ok) {
                LOGF(LOG_ERROR,
                     " [NEW] LoadRom(no-game) Failed: AudioBridge reset failed");
                currentGameData_.reset();
                eventBridge_.Emit("core_crash",
                                  "{\"reason\": \"audio_bridge_reset_failed\"}",
                                  true);
                SetLastErrorInfo("audio_bridge_reset_failed", "LoadRom",
                                 "AudioBridge reset failed for no-game core");
                TransitionTo(EngineState::ERROR);
                break;
              }
            }

            ClearLastErrorInfo();
            TransitionTo(EngineState::GAME_LOADED);
            TransitionTo(EngineState::RUNNING);
          } else {
            LOGF(LOG_ERROR, " [NEW] LoadRom(no-game) Failed: "
                            "retro_load_game(NULL) returned false");
            eventBridge_.Emit("core_crash",
                              "{\"reason\": \"no_game_load_failed\"}", true);
            currentGameData_.reset();
            SetLastErrorInfo("no_game_load_failed", "", "");
            TransitionTo(EngineState::ERROR);
          }
          break;
        }

        LOGF(LOG_ERROR,
             " [NEW] LoadRom Failed: empty rom path for non-no-game core");
        eventBridge_.Emit("core_crash", "{\"reason\": \"empty_rom_path\"}",
                          true);
        SetLastErrorInfo("empty_rom_path", "", "");
        TransitionTo(EngineState::ERROR);
        break;
      }

      const bool needFullpath = hasSystemInfo_ && systemInfo_.need_fullpath;
      const bool isRawfilePath = (currentGamePath_.rfind("roms/", 0) == 0) ||
                                 (currentGamePath_.rfind("./roms/", 0) == 0);
      if (needFullpath && currentGamePath_.empty()) {
        LOGF(LOG_ERROR,
             " [NEW] LoadRom Failed: core requires fullpath but path is empty");
        currentGameData_.reset();
        eventBridge_.Emit("core_crash",
                          "{\"reason\": \"need_fullpath_missing_path\"}", true);
        SetLastErrorInfo("need_fullpath_missing_path", "", "");
        TransitionTo(EngineState::ERROR);
        break;
      }
      if (needFullpath && isRawfilePath) {
        LOGF(LOG_ERROR, " [NEW] LoadRom Failed: core requires fullpath but got "
                        "rawfile path");
        currentGamePath_.clear();
        currentGameData_.reset();
        eventBridge_.Emit("core_crash",
                          "{\"reason\": \"need_fullpath_rawfile\"}", true);
        SetLastErrorInfo("need_fullpath_rawfile", "", "");
        TransitionTo(EngineState::ERROR);
        break;
      }

      // 如果没有内存数据，且核心不需要全路径，由引擎线程尝试读取
      if (!currentGameData_ && hasSystemInfo_ && !needFullpath) {
        LOGF(LOG_INFO,
             "[NEW] Attempting to load local ROM from engine thread...");
        auto res = ROMLoader::LoadFromPath(currentGamePath_);
        if (res.success) {
          currentGameData_ =
              std::make_shared<std::vector<uint8_t>>(std::move(res.data));
          LOGF(LOG_INFO, "[NEW] Local ROM loaded: %{public}zu bytes",
               currentGameData_->size());
        } else {
          LOGF(LOG_WARN, "[NEW] Failed to load local ROM: %{public}s",
               res.error_message.c_str());
        }
      }
      if (!needFullpath && !currentGameData_) {
        LOGF(LOG_ERROR,
             " [NEW] LoadRom Failed: core requires ROM data but data is empty");
        eventBridge_.Emit("core_crash", "{\"reason\": \"rom_data_missing\"}",
                          true);
        SetLastErrorInfo("rom_data_missing", "", "");
        TransitionTo(EngineState::ERROR);
        break;
      }
      const char *pathPtr =
          currentGamePath_.empty() ? nullptr : currentGamePath_.c_str();
      struct retro_game_info gameInfo = {pathPtr, nullptr, 0, nullptr};
      if (!needFullpath && currentGameData_) {
        gameInfo.data = currentGameData_->data();
        gameInfo.size = currentGameData_->size();
      }

      if (coreLoader_.GetLoadGame()(&gameInfo)) {
        LOGF(LOG_INFO, " [NEW] LoadRom Success");
        gameLoaded_.store(true, std::memory_order_release);
        if (needFullpath) {
          currentGameData_.reset();
        }
        ClearLastErrorInfo();

        // 获取音视频配置并初始化音频桥
        struct retro_system_av_info avInfo = {0};
        coreLoader_.GetSystemAvInfo()(&avInfo);

        LOGF(LOG_INFO,
             "[NEW] AV Info: base_width=%{public}u, base_height=%{public}u, "
             "max_width=%{public}u, max_height=%{public}u, fps=%{public}.2f, "
             "sample_rate=%{public}.2f",
             avInfo.geometry.base_width, avInfo.geometry.base_height,
             avInfo.geometry.max_width, avInfo.geometry.max_height,
             avInfo.timing.fps, avInfo.timing.sample_rate);

        // 更新 AV 信息
        videoWidth_ = avInfo.geometry.base_width;
        videoHeight_ = avInfo.geometry.base_height;
        videoMaxWidth_ = avInfo.geometry.max_width;
        videoMaxHeight_ = avInfo.geometry.max_height;
        targetFps_ = avInfo.timing.fps;
        videoPipeline_.SetTargetFps(targetFps_);
        audioSampleRate_ = avInfo.timing.sample_rate;
        if (hw_render_enabled_.load()) {
          HwRenderRuntimeInfo runtime{};
          runtime.video_width = videoWidth_;
          runtime.video_height = videoHeight_;
          runtime.video_max_width = videoMaxWidth_;
          runtime.video_max_height = videoMaxHeight_;
          if (renderThread_) {
            renderThread_->SetHwRenderRuntimeInfo(runtime);
          } else {
            LOGF(LOG_ERROR, "AV runtime update ignored: render thread unavailable");
          }
        }
        // Sanity Check: 音频采样率保护
        if (audioSampleRate_ < 8000.0 || audioSampleRate_ > 192000.0) {
          // Gambatte 等核心可能报告系统时钟频率 (2MHz+)，需修正为标准音频采样率
          // Game Boy 标准采样率通常为 32768 Hz (2^15)
          double fallbackRate = 32768.0; // 修改采样率修正值为 32768 Hz
          LOGF(LOG_WARN,
               " [NEW] Abnormal audio sample rate detected: %{public}.2f "
               "Hz. Clamping to %{public}.2f Hz to match GB standard.",
               audioSampleRate_.load(), fallbackRate);
          audioSampleRate_ = fallbackRate;
          avInfo.timing.sample_rate = fallbackRate;
        }
        LOGF(LOG_INFO,
             "%{public}s AV applied: fps=%{public}.2f, audio_rate=%{public}.2f, "
             "video=%{public}ux%{public}u",
             kAudioChainPrefix, targetFps_.load(), audioSampleRate_.load(), videoWidth_,
             videoHeight_);
        auto *bridge = AudioBridge::GetInstance();
        if (bridge) {
          // 使用 Reset() 而非 Initialize()，确保 DRC 和重采样器正确重置
          const bool reset_ok = bridge->Reset(avInfo.timing.sample_rate);
          LOGF(LOG_INFO,
               "%{public}s AudioBridge reset: ok=%{public}d, "
               "rate=%{public}.2f",
               kAudioChainPrefix, reset_ok ? 1 : 0,
               avInfo.timing.sample_rate);
          if (!reset_ok) {
            LOGF(LOG_ERROR,
                 " [NEW] LoadRom Failed: AudioBridge reset failed");
            currentGameData_.reset();
            eventBridge_.Emit("core_crash",
                              "{\"reason\": \"audio_bridge_reset_failed\"}",
                              true);
            SetLastErrorInfo("audio_bridge_reset_failed", "LoadRom",
                             "AudioBridge reset failed after retro_load_game");
            TransitionTo(EngineState::ERROR);
            break;
          }
        }

        // ...
        TransitionTo(EngineState::GAME_LOADED);
        // 自动开始游戏
        TransitionTo(EngineState::RUNNING);
      } else {
        LOGF(LOG_ERROR,
             " [NEW] LoadRom Failed: retro_load_game returned false");
        currentGameData_.reset();
        eventBridge_.Emit("core_crash", "{\"reason\": \"load_game_failed\"}",
                          true);
        SetLastErrorInfo("load_game_failed", "", "");
        TransitionTo(EngineState::ERROR);
      }
    } else {
      LOGF(LOG_ERROR, " [NEW] LoadRom Failed: Core not loaded");
      currentGamePath_.clear();
      currentGameData_.reset();
      eventBridge_.Emit("core_crash", "{\"reason\": \"core_not_loaded\"}",
                        true);
      SetLastErrorInfo("core_not_loaded", "", "");
      TransitionTo(EngineState::ERROR);
    }
  } break;
  case MessageType::SetFilesDir: {
    const std::string requestPath = msg.payload.loadPath.path;
    EngineState st = state_.load();
    if (IsCoreLoadedState(st) || st == EngineState::LOADING ||
        st == EngineState::STOPPING) {
      LOGF(LOG_WARN, "[NEW] SetFilesDir ignored after core loaded: %{public}s",
           security::DescribePathForLog(msg.payload.loadPath.path).c_str());
      {
        std::lock_guard<std::mutex> hintLock(filesDirHintMutex_);
        if (pendingFilesDir_ == requestPath) {
          pendingFilesDir_.clear();
        }
      }
      SetLastErrorInfo("files_dir_set_ignored_state", "SetFilesDir",
                       "SetFilesDir ignored due current engine state");
      break;
    }
    (void)ApplyFilesDir(requestPath);
    break;
  }
  case MessageType::WindowCreated:
  case MessageType::WindowRebind:
    if (++windowEventLogCount_ % 30 == 0) {
      LOGF(LOG_INFO, "[NEW] Message: %{public}s",
           msg.type == MessageType::WindowRebind ? "WindowRebind(legacy)"
                                                 : "WindowCreated");
    }
    {
      const uint64_t generation = msg.payload.window.generation;
      const uint64_t latestGeneration =
          surface_generation_.load(std::memory_order_acquire);
      if (generation != 0 && generation != latestGeneration) {
        if (ShouldLog(windowEventLogCount_, 3, 120)) {
          LOGF(LOG_WARN,
               "[NEW] Skip stale window message: type=%{public}d gen=%{public}llu latest=%{public}llu",
               static_cast<int>(msg.type),
               static_cast<unsigned long long>(generation),
               static_cast<unsigned long long>(latestGeneration));
        }
        break;
      }
      if (renderThread_) {
        auto scopedWindowRt = windowGuard_.AcquireWindow();
        OHNativeWindow *windowSnapshot = scopedWindowRt.Get();
        renderThread_->SetWindow(windowSnapshot, generation);
        HwRenderRuntimeInfo runtime{};
        runtime.video_width = videoWidth_;
        runtime.video_height = videoHeight_;
        runtime.video_max_width = videoMaxWidth_;
        runtime.video_max_height = videoMaxHeight_;
        renderThread_->SetHwRenderRuntimeInfo(runtime);
        break;
      }
      LOGF(LOG_ERROR, "Window message ignored: render thread unavailable");
      break;
    }
  case MessageType::WindowResized: {
    const int width = msg.payload.windowSize.width;
    const int height = msg.payload.windowSize.height;
    if (renderThread_) {
      renderThread_->SetWindowSize(width, height);
      break;
    }
    LOGF(LOG_ERROR, "WindowResized ignored: render thread unavailable");
    break;
  }
  case MessageType::WindowDestroyed:
    if (++windowEventLogCount_ % 30 == 0) {
      LOGF(LOG_INFO, "[NEW] Message: WindowDestroyed");
    }
    {
      const uint64_t generation = msg.payload.window.generation;
      const uint64_t latestGeneration =
          surface_generation_.load(std::memory_order_acquire);
      if (generation != 0 && generation != latestGeneration) {
        if (ShouldLog(windowEventLogCount_, 3, 120)) {
          LOGF(LOG_WARN,
               "[NEW] Skip stale window destroy: gen=%{public}llu latest=%{public}llu",
               static_cast<unsigned long long>(generation),
               static_cast<unsigned long long>(latestGeneration));
        }
        break;
      }
    }
    if (renderThread_) {
      renderThread_->SetWindow(nullptr, msg.payload.window.generation);
      break;
    }
    LOGF(LOG_ERROR, "WindowDestroyed ignored: render thread unavailable");
    break;
  case MessageType::SyncTask:
    if (msg.payload.syncTask.task) {
      msg.payload.syncTask.task->Run();
    }
    break;
  default:
    break;
  }
}

void LibretroEngine::SetupCallbacks() {
  if (!coreLoader_.IsLoaded())
    return;

  // retro_set_* functions are void — they have no return value to check.
  // Observability is provided by tracking which symbols the core exported
  // and logging a summary at INFO level. Missing non-critical callbacks are
  // logged at WARN; the engine continues without them (libretro spec allows
  // cores to omit optional callbacks).

  bool hasEnv = false;
  bool hasVideoRefresh = false;
  bool hasAudioSample = false;
  bool hasAudioBatch = false;
  bool hasInputPoll = false;
  bool hasInputState = false;

  if (auto fn = coreLoader_.GetSetEnvironment()) {
    fn(OnEnvironment);
    hasEnv = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_environment");
  }

  if (auto fn = coreLoader_.GetSetVideoRefresh()) {
    fn(OnVideoRefresh);
    hasVideoRefresh = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_video_refresh");
  }

  if (auto fn = coreLoader_.GetSetAudioSample()) {
    fn(OnAudioSample);
    hasAudioSample = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_audio_sample");
  }

  if (auto fn = coreLoader_.GetSetAudioSampleBatch()) {
    fn(OnAudioSampleBatch);
    hasAudioBatch = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_audio_sample_batch");
  }

  if (auto fn = coreLoader_.GetSetInputPoll()) {
    fn(InputManager::OnInputPoll);
    hasInputPoll = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_input_poll");
  }

  if (auto fn = coreLoader_.GetSetInputState()) {
    fn(InputManager::OnInputState);
    hasInputState = true;
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_input_state");
  }

  // 注册全局 Rumble 回调
  SetGlobalRumbleCallback(InputManager::OnRumble);

  // 注册全局 Sensor 回调
  SetGlobalSensorCallbacks(InputManager::OnSensorSetState,
                           InputManager::OnSensorGetInput);

  // Summary log: one line showing which callbacks were successfully registered.
  LOGF(LOG_INFO,
       "SetupCallbacks: env=%{public}d video=%{public}d "
       "audio_sample=%{public}d audio_batch=%{public}d "
       "input_poll=%{public}d input_state=%{public}d",
       hasEnv ? 1 : 0, hasVideoRefresh ? 1 : 0,
       hasAudioSample ? 1 : 0, hasAudioBatch ? 1 : 0,
       hasInputPoll ? 1 : 0, hasInputState ? 1 : 0);
}

// [REMOVED] Old Input Callbacks (Moved to InputManager)

void LibretroEngine::ProcessFrame() {
  if (!coreLoader_.IsLoaded() || state_.load() != EngineState::RUNNING) {
    return;
  }
  if (stopRequested_.load()) {
    return;
  }
  SetPhase(EnginePhase::PROCESS_FRAME);

  if (++processFrameLogCount_ % 300 == 0) {
    LOGF(LOG_INFO, " [NEW] ProcessFrame #%{public}zu", processFrameLogCount_);
  }

  const auto now = std::chrono::steady_clock::now();

  // 进入 retro_run 上下文
  envState_.EnterRetroRun();
  if (stopRequested_.load()) {
    envState_.ExitRetroRun();
    return;
  }

  // 1. Frame Time 回调（精确帧时间）
  if (auto cb = envState_.GetFrameTimeCallback()) {
    ::retro_usec_t delta_us = envState_.GetFrameTimeReference();
    if (hasLastRunTimestamp_) {
      delta_us = std::chrono::duration_cast<std::chrono::microseconds>(
                     now - lastRunTimestamp_)
                     .count();
    }
    cb(delta_us);
  }

  // 2. Audio Buffer Status 回调
  if (auto cb = envState_.GetAudioBufferStatusCallback()) {
    auto *audioBridge = AudioBridge::GetInstance();
    const bool active = (audioBridge && audioBridge->IsRunning());
    const auto audioState =
        audioBridge ? audioBridge->GetRunState()
                    : AudioBridge::AudioRunState::INIT;
    unsigned occupancy = 0;
    bool underrun_likely = false;
    size_t underruns = 0;
    size_t overruns = 0;
    if (active) {
      float usage = audioBridge->GetBufferUsage();
      if (usage < 0.0f)
        usage = 0.0f;
      else if (usage > 1.0f)
        usage = 1.0f;
      occupancy = static_cast<unsigned>(usage * 100.0f + 0.5f);
      underrun_likely = occupancy <= 10;
      audioBridge->GetBufferStats(underruns, overruns);
    }
    cb(active, occupancy, underrun_likely);
    const bool underrun_inc = underruns > lastAudioUnderruns_;
    const bool overrun_inc = overruns > lastAudioOverruns_;
    const bool low_buffer = active && occupancy <= 10;
    const int64_t now_us = NowUs();
    const int64_t last_emit_us =
        lastAudioStatusEmitUs_.load(std::memory_order_acquire);
    const bool emit_status = low_buffer || underrun_inc || overrun_inc ||
                             (now_us - last_emit_us) >= 200000;
    char payload[160];
    snprintf(payload, sizeof(payload),
             "{\"active\": %s, \"state\": \"%s\", \"occupancy\": %u, "
             "\"underrun\": %s, \"underruns\": %zu, \"overruns\": %zu}",
             active ? "true" : "false",
             AudioBridge::AudioRunStateToString(audioState), occupancy,
             underrun_likely ? "true" : "false", underruns, overruns);
    if (emit_status) {
      lastAudioStatusEmitUs_.store(now_us, std::memory_order_release);
      eventBridge_.Emit("audio_status", payload, false);
    }
    if (emit_status &&
        (++audioStatusLogCount_ <= 5 || (audioStatusLogCount_ % 300) == 0)) {
      LOGF(LOG_INFO,
           "%{public}s AudioStatus: active=%{public}d, state=%{public}s, "
           "occupancy=%{public}u, underrun=%{public}d, underruns=%{public}zu, "
           "overruns=%{public}zu",
           kAudioChainPrefix, active ? 1 : 0,
           AudioBridge::AudioRunStateToString(audioState), occupancy,
           underrun_likely ? 1 : 0, underruns, overruns);
    }
    if ((low_buffer || underrun_inc || overrun_inc) &&
        ShouldLog(audioLowLogCount_, 3, 120)) {
      const int64_t retro_ms =
          lastRetroRunMs_.load(std::memory_order_relaxed);
      const int64_t render_ms =
          lastVideoRenderMs_.load(std::memory_order_relaxed);
      const int render_res =
          lastVideoRenderResult_.load(std::memory_order_relaxed);
      const unsigned render_w =
          lastVideoRenderWidth_.load(std::memory_order_relaxed);
      const unsigned render_h =
          lastVideoRenderHeight_.load(std::memory_order_relaxed);
      const size_t render_pitch =
          lastVideoRenderPitch_.load(std::memory_order_relaxed);
      int sync_mode = -1;
      int playing = 0;
      if (audioBridge) {
        sync_mode = static_cast<int>(audioBridge->GetSyncMode());
        playing = audioBridge->IsPlaying() ? 1 : 0;
      }
      LOGF(LOG_WARN,
           "%{public}s AudioLow: occ=%{public}u%%, underrun=%{public}d, "
           "underruns=%{public}zu, overruns=%{public}zu, retro_ms=%{public}lld, "
           "render_ms=%{public}lld, render_res=%{public}d, "
           "render=%{public}ux%{public}u pitch=%{public}zu, playing=%{public}d, "
           "sync_mode=%{public}d",
           kAudioChainPrefix, occupancy, underrun_likely ? 1 : 0, underruns,
           overruns, static_cast<long long>(retro_ms),
           static_cast<long long>(render_ms), render_res, render_w, render_h,
           render_pitch, playing, sync_mode);
    }
    lastAudioUnderruns_ = underruns;
    lastAudioOverruns_ = overruns;
  }

  // 3. 执行核心帧
  constexpr int64_t kSlowRetroRunMs = 200;
  SetPhase(EnginePhase::RETRO_RUN);
  const auto retroStart = std::chrono::steady_clock::now();
  coreLoader_.GetRun()();
  const auto retroMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now() - retroStart)
                           .count();
  lastRetroRunMs_.store(retroMs, std::memory_order_relaxed);
  if (retroMs >= kSlowRetroRunMs && ShouldLog(slowRetroRunLogCount_, 3, 120)) {
    const char *coreName = (hasSystemInfo_ && systemInfo_.library_name)
                               ? systemInfo_.library_name
                               : "unknown";
    LOGF(LOG_WARN, "[Perf] Slow retro_run: %{public}lld ms (core=%{public}s)",
         static_cast<long long>(retroMs), coreName);
  }
  SetPhase(EnginePhase::PROCESS_FRAME);
  if (stopRequested_.load()) {
    envState_.ExitRetroRun();
    return;
  }

  // 4. 消费待处理的最小音频延迟
  unsigned latency_ms = 0;
  if (envState_.ConsumePendingMinimumAudioLatencyMs(latency_ms)) {
    auto *audioBridge = AudioBridge::GetInstance();
    if (audioBridge) {
      LOGF(LOG_INFO,
           "%{public}s Applying minimum audio latency: %{public}u ms",
           kAudioChainPrefix, latency_ms);
      audioBridge->SetMinimumLatencyMs(latency_ms);
    }
  }

  if (envState_.ConsumeVariableUpdated()) {
    eventBridge_.Emit("options_update", "{}", false);
  }

  // 5. 消费核心运行时 SET_SYSTEM_AV_INFO 请求(分辨率/帧率/采样率热切换)
  ::retro_system_av_info pendingAv{};
  if (envState_.ConsumePendingAvInfo(pendingAv)) {
    if (pendingAv.geometry.base_width > 0 && pendingAv.geometry.base_height > 0) {
      videoPipeline_.SetGeometry(pendingAv.geometry.base_width,
                                 pendingAv.geometry.base_height,
                                 pendingAv.geometry.aspect_ratio);
      videoWidth_ = static_cast<int>(pendingAv.geometry.base_width);
      videoHeight_ = static_cast<int>(pendingAv.geometry.base_height);
    }
    if (pendingAv.timing.fps > 0.0) {
      targetFps_ = pendingAv.timing.fps;
      videoPipeline_.SetTargetFps(pendingAv.timing.fps);
    }
    if (pendingAv.timing.sample_rate > 0.0 &&
        std::abs(audioSampleRate_ - pendingAv.timing.sample_rate) > 1.0) {
      audioSampleRate_ = pendingAv.timing.sample_rate;
      auto *audioBridge = AudioBridge::GetInstance();
      if (audioBridge) {
        audioBridge->Reset(static_cast<int32_t>(pendingAv.timing.sample_rate));
        LOGF(LOG_INFO,
             "%{public}s AV info update: sample_rate -> %{public}.0f",
             kAudioChainPrefix, pendingAv.timing.sample_rate);
      }
    }
  }

  // 更新时间戳
  lastRunTimestamp_ = now;
  hasLastRunTimestamp_ = true;

  // 退出 retro_run 上下文
  envState_.ExitRetroRun();
}

// --- Libretro 静态回调桥接实现 ---

void LibretroEngine::OnVideoRefresh(const void *data, unsigned width,
                                    unsigned height, size_t pitch) {
  LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
  if (!engine)
    return;

  if (engine->surface_state_.load() != SurfaceState::VALID) {
    // Surface 未处于有效状态时直接丢帧。
    // 这比仅检查 window 指针更可靠，能覆盖 Created/Destroyed 等生命周期中间态。
    engine->surfaceInvalidDropLogCount_++;
    if (engine->surfaceInvalidDropLogCount_ <= 5 ||
        (engine->surfaceInvalidDropLogCount_ % 120) == 0) {
      auto scopedWindowLog = engine->windowGuard_.AcquireWindow();
      OHNativeWindow *windowSnapshot = scopedWindowLog.Get();
      const int cachedW = engine->last_window_width_.load();
      const int cachedH = engine->last_window_height_.load();
      LOGF(LOG_WARN,
           "[NEW] Drop frame: surface invalid (surface=%{public}d, "
           "window=%{public}p, cached=%{public}dx%{public}d, state=%{public}d)",
           static_cast<int>(engine->surface_state_.load()),
           windowSnapshot, cachedW, cachedH,
           static_cast<int>(engine->state_.load()));
    }
    {
      std::lock_guard<std::mutex> lock(engine->statsMutex_);
      engine->stats_.videoRefreshCalls++;
      if (!data) {
        engine->stats_.videoNullFrames++;
      }
      engine->stats_.videoDroppedFrames++;
    }
    return;
  }

  if (engine->renderThread_) {
    VideoFramePacket packet{};
    packet.frameId =
        ++engine->videoFrameSeq_;
    packet.surfaceGeneration =
        engine->surface_generation_.load(std::memory_order_acquire);
    packet.timestampUs = NowUs();
    packet.width = width;
    packet.height = height;
    packet.pitch = pitch;
    packet.pixelFormat = engine->videoPipeline_.GetPixelFormat();

    if (engine->envState_.IsHwRenderEnabled()) {
      if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        packet.kind = VideoFrameKind::HW_SWAP;
      } else if (!data) {
        packet.kind = VideoFrameKind::HW_NULL;
      } else {
        packet.kind = VideoFrameKind::HW_NULL;
      }
    } else if (!data) {
      packet.kind = VideoFrameKind::NULL_FRAME;
      packet.isDupe = true;
    } else {
      packet.kind = VideoFrameKind::SOFTWARE;
      const size_t bytes = pitch * height;
      auto storage = engine->frameBufferPool_.Acquire(bytes);
      if (!storage || storage->size() < bytes) {
        std::lock_guard<std::mutex> lock(engine->statsMutex_);
        engine->stats_.videoRefreshCalls++;
        engine->stats_.videoDroppedFrames++;
        return;
      }
      if (bytes > 0 && data) {
        std::memcpy(storage->data(), data, bytes);
      }
      packet.storage = std::move(storage);
    }

    const bool enqueueOk = engine->renderThread_->EnqueueFrame(
        std::move(packet));
    {
      std::lock_guard<std::mutex> lock(engine->statsMutex_);
      engine->stats_.videoRefreshCalls++;
      if (!data) {
        engine->stats_.videoNullFrames++;
      }
      if (!enqueueOk) {
        engine->stats_.videoDroppedFrames++;
      }
    }
    return;
  }

  engine->skip_frame_counter_ = 0;
  if (ShouldLog(engine->videoRefreshLogCount_, 5, 120)) {
    LOGF(LOG_ERROR,
         "Drop frame: render thread unavailable (state=%{public}d, "
         "hw=%{public}d, frame=%{public}ux%{public}u)",
         static_cast<int>(engine->state_.load()),
         engine->envState_.IsHwRenderEnabled() ? 1 : 0, width,
         height);
  }
  {
    std::lock_guard<std::mutex> lock(engine->statsMutex_);
    engine->stats_.videoRefreshCalls++;
    if (!data) {
      engine->stats_.videoNullFrames++;
    }
    engine->stats_.videoDroppedFrames++;
  }
}

void LibretroEngine::OnAudioSample(int16_t left, int16_t right) {
  static size_t audio_sample_log_count = 0;
  if (++audio_sample_log_count <= 5 || (audio_sample_log_count % 300) == 0) {
    LOGF(LOG_INFO,
         "%{public}s AudioSample: L=%{public}d, R=%{public}d",
         kAudioChainPrefix, left, right);
  }
  int16_t samples[2] = {left, right};
  OnAudioSampleBatch(samples, 1);
}

size_t LibretroEngine::OnAudioSampleBatch(const int16_t *data, size_t frames) {
  LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
  if (!engine)
    return 0;

  // [Fix] Gambatte Quirk: Reports stereo samples as frames?
  // 1097 frames @ 60fps = 65820 Hz. This is exactly 2x 32910 Hz.
  // If we configured 32768 Hz, 1097 frames is 2x expected.
  size_t actualFrames = frames;
  if (CoreQuirksManager::GetInstance().Get().audio_stereo_frame_bug && frames > 800) {
    actualFrames = frames / 2;
  }

  // 更新统计
  size_t batch_count = 0;
  {
    std::lock_guard<std::mutex> lock(engine->statsMutex_);
    engine->stats_.audioBatchCalls++;
    engine->stats_.audioFramesIn += actualFrames;
    batch_count = engine->stats_.audioBatchCalls;
  }

  static size_t audio_cb_diag_log_count = 0;
  const bool shouldLogAudioCb =
      (++audio_cb_diag_log_count <= 3) || (audio_cb_diag_log_count % 1200) == 0;
  if (shouldLogAudioCb) {
    bool has_signal = false;
    if (data && actualFrames > 0) {
      size_t sample_check = actualFrames * 2;
      if (sample_check > 64) {
        sample_check = 64;
      }
      for (size_t i = 0; i < sample_check; ++i) {
        if (data[i] != 0) {
          has_signal = true;
          break;
        }
      }
    }
    auto *bridge_snapshot = AudioBridge::GetInstance();
    const bool bridge_running =
        (bridge_snapshot && bridge_snapshot->IsRunning());
    const bool bridge_playing =
        (bridge_snapshot && bridge_snapshot->IsPlaying());
    int sync_mode = -1;
    if (bridge_snapshot) {
      sync_mode = static_cast<int>(bridge_snapshot->GetSyncMode());
    }
    LOGF(LOG_INFO,
         "%{public}s AudioCB: frames=%{public}zu actual=%{public}zu "
         "signal=%{public}d, data=%{public}p, bridge_running=%{public}d, "
         "playing=%{public}d, sync_mode=%{public}d",
         kAudioChainPrefix, frames, actualFrames, has_signal ? 1 : 0, data,
         bridge_running ? 1 : 0, bridge_playing ? 1 : 0, sync_mode);
    int32_t expected_frames = 0;
    if (engine->targetFps_ > 0.0) {
      expected_frames = static_cast<int32_t>(
          engine->audioSampleRate_ / engine->targetFps_);
    }
    int32_t delta_frames =
        static_cast<int32_t>(actualFrames) - expected_frames;
    int32_t fps_x100 =
        static_cast<int32_t>(engine->targetFps_ * 100.0);
    int32_t rate_i =
        static_cast<int32_t>(engine->audioSampleRate_);
    LOGF(LOG_INFO,
         "%{public}s %{public}s AudioCB exp: fps_x100=%{public}d, "
         "rate=%{public}d, expected=%{public}d, actual=%{public}d, "
         "delta=%{public}d",
         kAudioChainPrefix, kAudioDiagPrefix, fps_x100, rate_i,
         expected_frames, static_cast<int32_t>(actualFrames), delta_frames);
  }

  // 提交到 AudioBridge
  auto *bridge = AudioBridge::GetInstance();
  if (bridge && bridge->IsRunning()) {
    return bridge->ProcessAudio(data, actualFrames);
  } else {
    // [DEBUG] 如果 Bridge 没运行，打印警告 (节流)
    if (batch_count % 60 == 0) {
      LOGF(LOG_WARN,
           "%{public}s Audio dropped: Bridge not running (ptr=%{public}p)",
           kAudioChainPrefix, bridge);
    }
  }
  return 0;
}

bool LibretroEngine::OnEnvironment(unsigned cmd, void *data) {
  LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
  if (!engine) {
    return false;
  }

  // 调用 EnvDispatcher 处理完整的环境命令
  bool handled =
      HandleEnvironmentCommand(engine->envState_, cmd, data);

  if (cmd == RETRO_ENVIRONMENT_SET_HW_RENDER && handled) {
    engine->hw_render_enabled_.store(
        engine->envState_.IsHwRenderEnabled());
    {
      const auto &cb = engine->envState_.GetHwRenderCallback();
      LOGF(LOG_INFO,
           "[NEW] HW render requested: enabled=%{public}d, ctx=%{public}d, "
           "cache=%{public}d",
           engine->hw_render_enabled_.load() ? 1 : 0,
           static_cast<int>(cb.context_type), cb.cache_context ? 1 : 0);
    }
    auto scopedWindowHw = engine->windowGuard_.AcquireWindow();
    OHNativeWindow *windowSnapshot = scopedWindowHw.Get();
    uint64_t generation =
        engine->surface_generation_.load(std::memory_order_acquire);
    if (windowSnapshot) {
      generation = engine->surface_generation_.fetch_add(
                       1, std::memory_order_acq_rel) +
                   1;
      engine->surface_session_id_.fetch_add(1,
                                                      std::memory_order_acq_rel);
      if (engine->renderThread_) {
        engine->renderThread_->InvalidateFrameQueueForGeneration(
            generation);
      }
    }
    HwRenderRuntimeInfo runtime{};
    runtime.video_width = engine->videoWidth_;
    runtime.video_height = engine->videoHeight_;
    runtime.video_max_width = engine->videoMaxWidth_;
    runtime.video_max_height = engine->videoMaxHeight_;
    if (engine->renderThread_) {
      // HW 渲染开关变更通过 generation 显式驱动窗口重绑，保持串行化。
      engine->renderThread_->SetWindow(windowSnapshot, generation);
      engine->renderThread_->SetHwRenderRuntimeInfo(runtime);
    } else {
      LOGF(LOG_ERROR, "HW render update ignored: render thread unavailable");
    }
  }

  // 特殊处理：将像素格式同步到 VideoPipeline
  if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && handled) {
    retro_pixel_format format = engine->envState_.GetPixelFormat();
    engine->videoPipeline_.SetPixelFormat(format);
    LOGF(LOG_INFO, "Pixel format set to: %{public}d", static_cast<int>(format));
    char payload[64];
    snprintf(payload, sizeof(payload), "{\"format\": %d}",
             static_cast<int>(format));
    engine->eventBridge_.Emit("pixel_format_update", payload, false);
  }

  if (cmd == RETRO_ENVIRONMENT_GET_CAN_DUPE && handled) {
    bool can = engine->envState_.CanDupe();
    engine->videoPipeline_.SetCanDupe(can);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_GEOMETRY && handled) {
    unsigned bw = engine->envState_.GetGeometryBaseWidth();
    unsigned bh = engine->envState_.GetGeometryBaseHeight();
    float aspect = engine->envState_.GetGeometryAspectRatio();
    engine->videoPipeline_.SetGeometry(bw, bh, aspect);
    if (engine->hw_render_enabled_.load()) {
      HwRenderRuntimeInfo runtime{};
      runtime.video_width = engine->videoWidth_;
      runtime.video_height = engine->videoHeight_;
      runtime.video_max_width = engine->videoMaxWidth_;
      runtime.video_max_height = engine->videoMaxHeight_;
      if (engine->renderThread_) {
        engine->renderThread_->SetHwRenderRuntimeInfo(runtime);
      } else {
        LOGF(LOG_ERROR, "Geometry HW update ignored: render thread unavailable");
      }
    }
    char payload[96];
    snprintf(
        payload, sizeof(payload),
        "{\"base_width\": %u, \"base_height\": %u, \"aspect_ratio\": %.6f}", bw,
        bh, aspect);
    engine->eventBridge_.Emit("geometry_update", payload, false);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_MESSAGE && handled) {
    const ::retro_message *msg = (const ::retro_message *)data;
    const char *m = (msg && msg->msg) ? msg->msg : "";
    unsigned frames = msg ? msg->frames : 0;

    std::string mStr = m;
    std::string mEsc;
    common::JsonEscape(mStr, mEsc);
    std::string payload = "{\"msg\": \"" + mEsc +
                          "\", \"frames\": " + std::to_string(frames) + "}";
    engine->eventBridge_.Emit("core_message", payload, false);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE && handled) {
    if (engine->diskController_) {
      engine->diskController_->SetCallbacks(
          (const struct retro_disk_control_callback *)data);
    }
    engine->eventBridge_.Emit("disk_control", "{\"type\": \"basic\"}",
                                        false);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE && handled) {
    if (engine->diskController_) {
      engine->diskController_->SetCallbacks(
          (const struct retro_disk_control_ext_callback *)data);
    }
    engine->eventBridge_.Emit("disk_control", "{\"type\": \"ext\"}",
                                        false);
  }

  return handled;
}

// --- 视频配置实现 ---

void LibretroEngine::SetScalingMode(int mode) {
  // 0: Hardware (Default), 1: Software, 2: GLES
  VideoPipeline::ScalingMode sm;
  const char *modeStr = "UNKNOWN";

  switch (mode) {
  case 1:
    sm = VideoPipeline::ScalingMode::SOFTWARE_SCALING;
    modeStr = "SOFTWARE";
    break;
  case 2:
    sm = VideoPipeline::ScalingMode::GLES_SCALING;
    modeStr = "GLES";
    break;
  case 0:
  default:
    sm = VideoPipeline::ScalingMode::HARDWARE_SCALING;
    modeStr = "HARDWARE";
    break;
  }

#if defined(__i386__) || defined(__x86_64__)
  if (sm != VideoPipeline::ScalingMode::GLES_SCALING) {
    LOGF(LOG_WARN,
         " [NEW] SetScalingMode override on x86: req=%{public}d (%{public}s) -> GLES",
         mode, modeStr);
    sm = VideoPipeline::ScalingMode::GLES_SCALING;
    modeStr = "GLES";
  }
#endif

  videoPipeline_.SetScalingMode(sm);

  LOGF(LOG_INFO, " [NEW] SetScalingMode: %{public}d (%{public}s)", mode,
       modeStr);
}

void LibretroEngine::SetSwapInterval(int interval) {
  const int applied = (interval <= 0) ? 0 : 1;
  videoPipeline_.SetSwapInterval(applied);
  LOGF(LOG_INFO,
       " [NEW] SetSwapInterval: req=%{public}d, applied=%{public}d", interval,
       applied);
}

void LibretroEngine::SetSoftwareMaxResolution(unsigned maxWidth,
                                              unsigned maxHeight) {
  videoPipeline_.SetSoftwareResolutionMax(maxWidth, maxHeight);
  LOGF(LOG_INFO, " [NEW] SetSoftwareMaxResolution: %{public}ux%{public}u",
       maxWidth, maxHeight);
}

bool LibretroEngine::SetCoreOption(const std::string &key,
                                   const std::string &value) {
  return envState_.SetCoreOptionValue(key.c_str(), value.c_str());
}

std::string LibretroEngine::GetCoreOptionsJson() const {
  std::string s = "[";
  const auto defs = envState_.GetCoreOptionDefinitions();
  for (size_t i = 0; i < defs.size(); ++i) {
    const auto &d = defs[i];
    std::string keyEsc, descEsc, valEsc;
    common::JsonEscape(d.key, keyEsc);
    common::JsonEscape(d.desc, descEsc);
    const char *cur = envState_.GetVariable(d.key.c_str());
    std::string curVal = cur ? std::string(cur) : std::string();
    common::JsonEscape(curVal, valEsc);
    s += "{\"key\": \"" + keyEsc + "\", \"desc\": \"" + descEsc +
         "\", \"value\": \"" + valEsc + "\", \"values\": [";
    for (size_t j = 0; j < d.values.size(); ++j) {
      const auto &v = d.values[j];
      std::string vvEsc, vlEsc;
      common::JsonEscape(v.value, vvEsc);
      common::JsonEscape(v.label, vlEsc);
      s += "{\"value\": \"" + vvEsc + "\", \"label\": \"" + vlEsc + "\"}";
      if (j + 1 < d.values.size())
        s += ",";
    }
    s += "]}";
    if (i + 1 < defs.size())
      s += ",";
  }
  s += "]";
  return s;
}

// --- 磁盘控制接口 ---
// T8-B-F2: 全部走 ExecuteSyncTask 进 Engine 线程,与 SaveState/SRAM 同模式。
// 否则 NAPI 线程直接调用 DiskController 会在 retro_run 之外触发 core disk callbacks,
// 违反 libretro core 的 game-loop context 要求,可能损坏 core 内部状态。

bool LibretroEngine::DiskControlSetEjectState(bool ejected) {
  if (!diskController_)
    return false;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, ejected, &ok]() {
            ok = ejected ? diskController_->Eject() : diskController_->Insert();
          },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

bool LibretroEngine::DiskControlGetEjectState() {
  if (!diskController_)
    return false;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok]() { ok = diskController_->IsEjected(); },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

unsigned LibretroEngine::DiskControlGetImageIndex() {
  if (!diskController_)
    return 0;
  unsigned result = 0;
  if (!ExecuteSyncTask(
          [this, &result]() { result = diskController_->GetImageIndex(); },
          kSyncTaskTimeoutMs)) {
    return 0;
  }
  return result;
}

bool LibretroEngine::DiskControlSetImageIndex(unsigned index) {
  if (!diskController_)
    return false;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, index, &ok]() { ok = diskController_->SetImageIndex(index); },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

unsigned LibretroEngine::DiskControlGetNumImages() {
  if (!diskController_)
    return 0;
  unsigned result = 0;
  if (!ExecuteSyncTask(
          [this, &result]() { result = diskController_->GetNumImages(); },
          kSyncTaskTimeoutMs)) {
    return 0;
  }
  return result;
}

bool LibretroEngine::DiskControlReplaceImageIndex(unsigned index,
                                                  const std::string &path) {
  if (!diskController_)
    return false;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, index, &path, &ok]() {
            ok = diskController_->ReplaceImageIndex(index, path);
          },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

bool LibretroEngine::DiskControlAddImageIndex() {
  if (!diskController_)
    return false;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok]() { ok = diskController_->AddImageIndex(); },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

void LibretroEngine::TransitionTo(EngineState newState) {
  // 使用 CAS 循环避免 load → validate → store 之间的 TOCTOU。
  EngineState oldState = state_.load();
  while (true) {
    if (oldState == newState) {
      return;
    }
    if (!IsValidTransition(oldState, newState)) {
      LOGF(LOG_WARN, "Illegal state transition: %{public}d -> %{public}d",
           static_cast<int>(oldState), static_cast<int>(newState));
      return;
    }
    if (state_.compare_exchange_strong(oldState, newState)) {
      break;
    }
    // CAS 失败:oldState 已被更新为当前实际值,重试。
  }
  {
    std::lock_guard<std::mutex> lk(stateMutex_); // Audit T2-F2: hold stateMutex_ before notify_all to prevent notification loss
    stateCond_.notify_all();
  }
  LOGF(LOG_INFO, "State Transition: -> %{public}d",
       static_cast<int>(newState));
  nextFrameDeadline_ = std::chrono::steady_clock::time_point{};

  // 通知 ArkTS 侧状态变更
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"state\": %d}",
           static_cast<int>(newState));
  eventBridge_.Emit("engine_state", payload, false);

  // 音频负载随状态切换
  auto *bridge = AudioBridge::GetInstance();
  if (!bridge)
    return;

  if (newState == EngineState::RUNNING) {
    const bool ok = bridge->Start();
    LOGF(LOG_INFO,
         "%{public}s AudioBridge start on RUNNING: ok=%{public}d, "
         "running=%{public}d, playing=%{public}d, sync_mode=%{public}d",
         kAudioChainPrefix, ok ? 1 : 0, bridge->IsRunning() ? 1 : 0,
         bridge->IsPlaying() ? 1 : 0,
         static_cast<int>(bridge->GetSyncMode()));
    if (!ok) {
      eventBridge_.Emit("core_crash",
                        "{\"reason\": \"audio_bridge_start_failed\", "
                        "\"step\": \"TransitionTo\", "
                        "\"message\": \"AudioBridge failed to enter running state\"}",
                        true);
      SetLastErrorInfo("audio_bridge_start_failed", "TransitionTo",
                       "AudioBridge failed to enter running state");
      TransitionTo(EngineState::ERROR);
      return;
    }
  } else if (newState == EngineState::PAUSED ||
             newState == EngineState::STOPPING) {
    const bool ok = bridge->Pause();
    LOGF(LOG_INFO,
         "%{public}s AudioBridge pause on state=%{public}d: ok=%{public}d, "
         "running=%{public}d, playing=%{public}d",
         kAudioChainPrefix, static_cast<int>(newState), ok ? 1 : 0,
         bridge->IsRunning() ? 1 : 0, bridge->IsPlaying() ? 1 : 0);
    if (!ok) {
      eventBridge_.Emit("core_crash",
                        "{\"reason\": \"audio_bridge_pause_failed\", "
                        "\"step\": \"TransitionTo\", "
                        "\"message\": \"AudioBridge failed to pause for engine state change\"}",
                        true);
      SetLastErrorInfo("audio_bridge_pause_failed", "TransitionTo",
                       "AudioBridge failed to pause for engine state change");
      if (newState == EngineState::PAUSED) {
        TransitionTo(EngineState::ERROR);
      }
      return;
    }
  } else if (newState == EngineState::STOPPED) {
    const bool ok = bridge->Stop();
    LOGF(LOG_INFO,
         "%{public}s AudioBridge stop on STOPPED: ok=%{public}d, "
         "running=%{public}d, playing=%{public}d",
         kAudioChainPrefix, ok ? 1 : 0, bridge->IsRunning() ? 1 : 0,
         bridge->IsPlaying() ? 1 : 0);
    if (!ok) {
      eventBridge_.Emit("core_crash",
                        "{\"reason\": \"audio_bridge_stop_failed\", "
                        "\"step\": \"TransitionTo\", "
                        "\"message\": \"AudioBridge failed to stop during engine shutdown\"}",
                        true);
      SetLastErrorInfo("audio_bridge_stop_failed", "TransitionTo",
                       "AudioBridge failed to stop during engine shutdown");
      return;
    }
  }
}

bool LibretroEngine::WaitForState(EngineState target, uint32_t timeoutMs) {
  if (state_.load() == target) {
    return true;
  }
  if (timeoutMs == 0) {
    return state_.load() == target; // Audit T2-F3: non-blocking poll, no mutex needed
  }
  std::unique_lock<std::mutex> lock(stateMutex_);
  return stateCond_.wait_for(
      lock, std::chrono::milliseconds(timeoutMs),
      [this, target]() { return state_.load() == target; });
}

LibretroEngine::EngineErrorInfo LibretroEngine::GetLastErrorInfo() const {
  std::lock_guard<std::mutex> lock(errorMutex_);
  return lastError_;
}

void LibretroEngine::ClearLastErrorInfo() {
  std::lock_guard<std::mutex> lock(errorMutex_);
  lastError_ = {};
}

void LibretroEngine::SetLastErrorInfo(const std::string &reason,
                                      const std::string &step,
                                      const std::string &message) {
  std::lock_guard<std::mutex> lock(errorMutex_);
  lastError_.reason = reason;
  lastError_.step = step;
  lastError_.message = message;
}

void LibretroEngine::DetectCoreQuirks() {
  if (!hasSystemInfo_) {
    CoreQuirksManager::GetInstance().Reset();
    return;
  }
  CoreQuirksManager::GetInstance().Detect(systemInfo_);
}

// --- SaveState 实现 ---

size_t LibretroEngine::GetSaveStateSize() {
  // T8-A-F1: 拒绝在 !IsGameLoadedState() 时调用——core 未加载游戏时
  // serialize_size 行为未定义,且无 game state 时返回 0 已是死路。
  if (!IsGameLoadedState(state_.load())) {
    SetLastErrorInfo("save_state_size_game_not_loaded", "GetSaveStateSize",
                     "GetSaveStateSize requires a loaded game");
    return 0;
  }
  size_t size = 0;
  (void)ExecuteSyncTask(
      [this, &size]() {
        if (stateManager_) {
          size = stateManager_->GetSaveStateSize();
        }
      },
      kSyncTaskTimeoutMs, "GetSaveStateSize");
  return size;
}

bool LibretroEngine::SaveState(std::vector<uint8_t> &outData) {
  // T8-A-F1: 状态机 guard——拒绝在 game 未加载时调用 retro_serialize,
  // 也防止 !running_ 时 ExecuteSyncTask 快速路径在 NAPI 线程直接执行 retro_serialize。
  if (!IsGameLoadedState(state_.load())) {
    LOGF(LOG_WARN, "[NEW] SaveState rejected: state=%{public}d (game not loaded)",
         static_cast<int>(state_.load()));
    SetLastErrorInfo("save_state_game_not_loaded", "SaveState",
                     "SaveState requires a loaded game");
    return false;
  }
  bool ok = false;
  std::vector<uint8_t> snapshot;
  if (!ExecuteSyncTask(
          [this, &ok, &snapshot]() {
            if (stateManager_) {
              ok = stateManager_->SaveState(snapshot);
            }
          },
          kSyncTaskTimeoutMs, "SaveState")) {
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("save_state_failed", "SaveState",
                     "Core state serialization returned false");
    return false;
  }
  outData = std::move(snapshot);
  return true;
}

bool LibretroEngine::CaptureSaveStateBundle(SaveStateCaptureBundle &outBundle) {
  if (!IsGameLoadedState(state_.load())) {
    LOGF(LOG_WARN,
         "[NEW] CaptureSaveStateBundle rejected: state=%{public}d (game not loaded)",
         static_cast<int>(state_.load()));
    SetLastErrorInfo("save_state_bundle_game_not_loaded",
                     "CaptureSaveStateBundle",
                     "CaptureSaveStateBundle requires a loaded game");
    return false;
  }

  SaveStateCaptureBundle bundle{};
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, &bundle]() {
            if (stateManager_) {
              ok = stateManager_->SaveState(bundle.stateData);
            }
          },
          kSyncTaskTimeoutMs, "CaptureSaveStateBundle")) {
    return false;
  }
  if (!ok || bundle.stateData.empty()) {
    SetLastErrorInfo("save_state_bundle_failed", "CaptureSaveStateBundle",
                     "SaveState bundle capture returned empty snapshot");
    return false;
  }

  (void)videoPipeline_.CaptureLastFrameRgba(bundle.thumbnail.rgba,
                                            bundle.thumbnail.width,
                                            bundle.thumbnail.height);
  outBundle = std::move(bundle);
  return true;
}

bool LibretroEngine::LoadState(const std::vector<uint8_t> &data) {
  // T8-A-F1: 同 SaveState——游戏未加载时拒绝。
  if (!IsGameLoadedState(state_.load())) {
    LOGF(LOG_WARN, "[NEW] LoadState rejected: state=%{public}d (game not loaded)",
         static_cast<int>(state_.load()));
    SetLastErrorInfo("load_state_game_not_loaded", "LoadState",
                     "LoadState requires a loaded game");
    return false;
  }
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, &data]() {
            if (stateManager_) {
              ok = stateManager_->LoadState(data);
            }
          },
          kSyncTaskTimeoutMs, "LoadState")) {
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("load_state_failed", "LoadState",
                     "Core state deserialization returned false");
  }
  return ok;
}

// --- SRAM 接口 ---

bool LibretroEngine::GetSRAM(std::vector<uint8_t> &outData) {
  // T8-A-F1: SRAM 同样需要游戏已加载。
  if (!IsGameLoadedState(state_.load())) {
    LOGF(LOG_WARN, "[NEW] GetSRAM rejected: state=%{public}d (game not loaded)",
         static_cast<int>(state_.load()));
    SetLastErrorInfo("get_sram_game_not_loaded", "GetSRAM",
                     "GetSRAM requires a loaded game");
    return false;
  }
  bool ok = false;
  std::vector<uint8_t> snapshot;
  if (!ExecuteSyncTask(
          [this, &ok, &snapshot]() {
            if (stateManager_) {
              ok = stateManager_->GetSRAM(snapshot);
            }
          },
          kSyncTaskTimeoutMs, "GetSRAM")) {
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("get_sram_failed", "GetSRAM",
                     "Failed to read SRAM from core");
    return false;
  }
  outData = std::move(snapshot);
  return true;
}

bool LibretroEngine::SetSRAM(const std::vector<uint8_t> &data) {
  // T8-A-F1: SRAM 写入同样需要游戏已加载。
  if (!IsGameLoadedState(state_.load())) {
    LOGF(LOG_WARN, "[NEW] SetSRAM rejected: state=%{public}d (game not loaded)",
         static_cast<int>(state_.load()));
    SetLastErrorInfo("set_sram_game_not_loaded", "SetSRAM",
                     "SetSRAM requires a loaded game");
    return false;
  }
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, &data]() {
            if (stateManager_) {
              ok = stateManager_->SetSRAM(data);
            }
          },
          kSyncTaskTimeoutMs, "SetSRAM")) {
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("set_sram_failed", "SetSRAM",
                     "Failed to write SRAM into core");
  }
  return ok;
}

uintptr_t LibretroEngine::GetHwRenderFramebuffer() const {
  if (!hw_render_enabled_.load()) {
    return 0;
  }
  return videoPipeline_.GetHwRenderFramebuffer();
}

// --- 核心控制实现 ---

bool LibretroEngine::ResetCore() {
  bool ok = false;
  const bool dispatched = ExecuteSyncTask(
      [this, &ok]() {
        if (!coreLoader_.IsLoaded()) {
          return;
        }
        auto fn = coreLoader_.GetReset();
        if (fn) {
          fn();
          ok = true;
          LOGF(LOG_INFO, "Core reset");
        }
      },
      kSyncTaskTimeoutMs, "ResetCore");
  if (!dispatched) {
    LOGF(LOG_WARN, "[NEW] ResetCore skipped: sync dispatch failed");
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("reset_core_unavailable", "ResetCore",
                     "Core reset callback is unavailable");
  }
  return ok;
}

// --- 金手指实现 ---

bool LibretroEngine::CheatReset() {
  bool ok = false;
  const bool dispatched = ExecuteSyncTask(
      [this, &ok]() {
        if (stateManager_) {
          stateManager_->CheatReset();
          ok = true;
        }
      },
      kSyncTaskTimeoutMs, "CheatReset");
  if (!dispatched) {
    LOGF(LOG_WARN, "[NEW] CheatReset skipped: sync dispatch failed");
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("cheat_reset_unavailable", "CheatReset",
                     "Cheat reset is unavailable in current core state");
  }
  return ok;
}

bool LibretroEngine::CheatSet(unsigned index, bool enabled,
                              const std::string &code) {
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, index, enabled, &code]() {
            if (stateManager_) {
              ok = stateManager_->CheatSet(index, enabled, code);
            }
          },
          kSyncTaskTimeoutMs, "CheatSet")) {
    return false;
  }
  if (!ok) {
    SetLastErrorInfo("cheat_set_failed", "CheatSet",
                     "Core rejected cheat update");
  }
  return ok;
}

// --- 控制器/区域实现 ---

void LibretroEngine::SetControllerPortDevice(unsigned port, unsigned device) {
  const bool dispatched = ExecuteSyncTask(
      [this, port, device]() {
        if (!coreLoader_.IsLoaded()) {
          return;
        }
        auto fn = coreLoader_.GetSetControllerPortDevice();
        if (fn) {
          fn(port, device);
          LOGF(LOG_INFO, "Set controller port %{public}u to device %{public}u",
               port, device);
        }
      },
      kSyncTaskTimeoutMs);
  if (!dispatched) {
    LOGF(LOG_WARN,
         "[NEW] SetControllerPortDevice skipped: sync dispatch failed (port=%{public}u, device=%{public}u)",
         port, device);
  }
}

unsigned LibretroEngine::GetRegion() {
  unsigned region = 0;
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &region, &ok]() {
            if (!coreLoader_.IsLoaded()) {
              return;
            }
            auto fn = coreLoader_.GetGetRegion();
            if (fn) {
              region = fn();
              ok = true;
            }
          },
          kSyncTaskTimeoutMs, "GetRegion")) {
    return 0;
  }
  if (!ok) {
    SetLastErrorInfo("region_unavailable", "GetRegion",
                     "Region query callback is unavailable");
  }
  return ok ? region : 0;
}

} // namespace libretro
