#include "libretro_engine.h"
#include "core_quirks_manager.h"
#include "common/file_security.h"
#include "common/string_utils.h"
#include "interfaces/graphics/i_renderer.h"
#include <chrono>
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

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "LibretroEngine"
#undef LOG_FLOW
#define LOG_FLOW "Engine"
#include "common/log_prefix.h"

namespace libretro {

// 静态实例指针，用于回调桥接（Phase 1 简化处理，仅支持单实例）
static LibretroEngine *g_engineInstance = nullptr;

class EngineSyncTask {
public:
  explicit EngineSyncTask(std::function<void()> task) : task_(std::move(task)) {}

  void Run() {
    if (task_) {
      task_();
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      done_ = true;
    }
    cond_.notify_all();
  }

  bool Wait(uint32_t timeoutMs) {
    std::unique_lock<std::mutex> lock(mutex_);
    return cond_.wait_for(lock, std::chrono::milliseconds(timeoutMs),
                          [this]() { return done_; });
  }

private:
  std::function<void()> task_;
  std::mutex mutex_;
  std::condition_variable cond_;
  bool done_ = false;
};

namespace {
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";
constexpr const char *kAudioDiagPrefix = "[AUDIO_DIAG]";
constexpr uint32_t kSyncTaskTimeoutMs = 5000;
thread_local LibretroEngine *g_engineThreadInstance = nullptr;

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
    return to == EngineState::STARTING || to == EngineState::INIT;
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
  g_engineInstance = this;

  // Initialize InputManager
  inputManager_ = std::make_unique<InputManager>(&eventBridge_);
  inputPortRouter_ = std::make_unique<InputPortRouter>(inputManager_.get());
  inputManager_->SetPortRouter(inputPortRouter_.get());
  inputManager_->SetControllerPortDeviceCallback(
      [this](unsigned port, unsigned device) {
        SetControllerPortDevice(port, device);
      });
  rendererInterface_ = std::make_unique<EngineRendererAdapter>(this);
  // Initialize CoreStateManager
  stateManager_ = std::make_unique<CoreStateManager>(coreLoader_);
  // Initialize DiskController
  diskController_ = std::make_unique<DiskController>();
  // HW Render framebuffer provider
  SetGlobalHwRenderFramebufferCallback([]() -> uintptr_t {
    if (!g_engineInstance) {
      return 0;
    }
    return g_engineInstance->GetHwRenderFramebuffer();
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
  g_engineInstance = nullptr;
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
    return false;
  }
  if (stopInProgress_.load()) {
    LOGF(LOG_WARN, "[NEW] Start ignored: stop in progress");
    startInProgress_.store(false);
    return false;
  }
  if (stopTimedOut_.load()) {
    LOGF(LOG_ERROR, "[NEW] Start blocked: previous stop timed out");
    startInProgress_.store(false);
    return false;
  }
  if (running_) {
    LOGF(LOG_WARN, "[NEW] Already running, skip Start");
    startInProgress_.store(false);
    return true;
  }

  // 统一重置所有状态（解决重入问题）
  Reset();
  stopRequested_.store(false);
  gameLoopExited_.store(false);
  TransitionTo(EngineState::STARTING);

  running_ = true;
  gameThread_ = std::thread(&LibretroEngine::GameLoop, this);
  LOGF(LOG_INFO, " [NEW] Engine Thread Started");
  startInProgress_.store(false);

  OHNativeWindow *windowSnapshot = nullptr;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    windowSnapshot = window_;
    if (windowSnapshot) {
      OH_NativeWindow_NativeObjectReference(windowSnapshot);
    }
  }
  if (windowSnapshot) {
    if (!messageQueue_.Push(EngineMessage::MakeWindowMessage(
            MessageType::WindowCreated, windowSnapshot))) {
      LOGF(LOG_WARN, "[NEW] WindowCreated dropped: message queue closed");
    }
    const int cachedW = last_window_width_.load();
    const int cachedH = last_window_height_.load();
    if (cachedW > 0 && cachedH > 0) {
      if (!messageQueue_.Push(
              EngineMessage::MakeWindowResizeMessage(cachedW, cachedH))) {
        LOGF(LOG_WARN, "[NEW] WindowResized dropped: message queue closed");
      }
    }
    OH_NativeWindow_NativeObjectUnreference(windowSnapshot);
  }
  return true;
}

bool LibretroEngine::Stop() {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  if (stopInProgress_.exchange(true)) {
    LOGF(LOG_WARN, "[NEW] Stop ignored: stop already in progress");
    return false;
  }
  if (!running_) {
    stopInProgress_.store(false);
    return true;
  }

  LOGF(LOG_INFO, " [NEW] Stopping Engine...");
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

  constexpr uint32_t STOP_TIMEOUT_MS = 5000;
  bool exited = false;
  {
    std::unique_lock<std::mutex> lock(stopMutex_);
    exited =
        stopCond_.wait_for(lock, std::chrono::milliseconds(STOP_TIMEOUT_MS),
                           [this]() { return gameLoopExited_.load(); });
  }
  if (!exited) {
    stopTimedOut_.store(true);
    LOGF(LOG_ERROR, "[NEW] Stop timeout after %{public}u ms", STOP_TIMEOUT_MS);
    const EnginePhase currentPhase = phase_.load(std::memory_order_acquire);
    const int64_t currentPhaseMs = GetPhaseDurationMs();
    LOGF(LOG_ERROR,
         "[NEW] Stop timeout phase=%{public}s, phase_ms=%{public}lld",
         PhaseToString(currentPhase), static_cast<long long>(currentPhaseMs));
    stopInProgress_.store(false);
    return false;
  }

  if (gameThread_.joinable()) {
    gameThread_.join();
  }

  running_ = false;
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

  stopRequested_.store(false);
  stopTimedOut_.store(false);
  startInProgress_.store(false);
  stopInProgress_.store(false);

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

  // 5. 重置引擎状态
  state_.store(EngineState::INIT);
  ClearLastErrorInfo();
  frameCount_ = 0;
  currentFps_ = 0.0f;
  hasSystemInfo_ = false;
  currentCorePath_.clear();
  currentGamePath_.clear();
  currentGameData_.reset();
  videoWidth_ = 0;
  videoHeight_ = 0;
  videoMaxWidth_ = 0;
  videoMaxHeight_ = 0;
  targetFps_ = 60.0;
  videoPipeline_.SetTargetFps(60.0);
  audioSampleRate_ = 44100.0;

  videoPipeline_.ClearFrameCache();
  videoPipeline_.ForceReconfiguration();
  windowMessageDropLogCount_ = 0;
  windowResizeDropLogCount_ = 0;
  surfaceInvalidDropLogCount_ = 0;

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
  EngineState st = state_.load();
  if (!IsGameLoadedState(st)) {
    return;
  }
  LOGF(LOG_INFO, "[NEW] Unloading game (%{public}s)",
       reason ? reason : "unknown");
  unload();
  TransitionTo(EngineState::CORE_LOADED);
  currentGameData_.reset();
}

void LibretroEngine::Pause() {
  if (!messageQueue_.Push({MessageType::Pause, {}})) {
    LOGF(LOG_WARN, "[NEW] Pause dropped: message queue closed");
  }
}

void LibretroEngine::Resume() {
  if (!messageQueue_.Push({MessageType::Resume, {}})) {
    LOGF(LOG_WARN, "[NEW] Resume dropped: message queue closed");
  }
}

bool LibretroEngine::LoadCore(const std::string &corePath) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  // 自动启动引擎（如果未运行）
  if (!running_) {
    LOGF(LOG_INFO, "[NEW] LoadCore: Engine not running, auto-starting...");
    Start();
  }
  if (!messageQueue_.Push(
          EngineMessage::MakeLoadMessage(MessageType::LoadCore, corePath))) {
    LOGF(LOG_WARN, "[NEW] LoadCore dropped: message queue closed");
    return false;
  }
  return true;
}

bool LibretroEngine::LoadGame(const std::string &gamePath,
                              std::shared_ptr<std::vector<uint8_t>> data) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  if (!messageQueue_.Push(EngineMessage::MakeLoadMessage(MessageType::LoadRom,
                                                         gamePath, data))) {
    LOGF(LOG_WARN, "[NEW] LoadRom dropped: message queue closed");
    return false;
  }
  return true;
}

void LibretroEngine::SetNativeWindow(const std::string &xcomponentId,
                                     OHNativeWindow *window) {
  LOGF(LOG_INFO, "[NEW] Engine: SetNativeWindow %{public}s %{public}p",
       xcomponentId.c_str(), window);

  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    if (current_xcomponent_id_ != xcomponentId || window_ != window) {
      changed = true;
      if (window_) {
        OH_NativeWindow_NativeObjectUnreference(window_);
      }
      window_ = window;
      current_xcomponent_id_ = xcomponentId;
      if (window_) {
        OH_NativeWindow_NativeObjectReference(window_);
      }
    }
  }

  if (changed) {
    last_window_width_.store(0);
    last_window_height_.store(0);
  }

  surface_state_.store(window ? SurfaceState::CREATED
                              : SurfaceState::DESTROYED);

  // 仅当句柄真正变化时通知引擎线程，避免 OnSurfaceChanged
  // 重复触发导致资源反复重建。
  if (changed) {
    if (!messageQueue_.Push(EngineMessage::MakeWindowMessage(
            window ? MessageType::WindowCreated : MessageType::WindowDestroyed,
            window))) {
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

  if (window) {
    // 窗口参数变更/系统重置配置时，强制重置 VideoPipeline 配置
    // （即使 window 指针未变，也需要重新打 opt/重建 EGLSurface 等）
    videoPipeline_.ForceReconfiguration();
  } else {
    // 窗口销毁时，不要在 UI 线程直接 Reset，防止 EGL 线程冲突
    // 而是依赖 WindowDestroyed 消息在 GameLoop 中处理
  }
}

void LibretroEngine::ClearNativeWindowIfMatch(const std::string &xcomponentId,
                                              OHNativeWindow *destroyedWindow) {
  bool match = false;
  {
    std::lock_guard<std::mutex> lock(windowMutex_);
    if (current_xcomponent_id_ != xcomponentId) {
      match = false;
    } else if (destroyedWindow) {
      match = (window_ == destroyedWindow);
    } else {
      match = (window_ != nullptr);
    }
  }

  if (match) {
    SetNativeWindow(xcomponentId, nullptr);
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
    hasWindow = (window_ != nullptr && current_xcomponent_id_ == xcomponentId);
  }
  if (width > 0 && height > 0) {
    if (hasWindow) {
      last_window_width_.store(width);
      last_window_height_.store(height);
    }
  }
  if (width > 0 && height > 0 && hasWindow) {
    // 只有在窗口有有效尺寸后，才允许进入渲染路径。
    // 避免 SurfaceCreated 之后但尺寸未就绪时触发渲染导致的试探/异常。
    surface_state_.store(SurfaceState::VALID);
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

void LibretroEngine::SendInput(int port, int id, bool pressed) {
  if (inputManager_) {
    inputManager_->SendInput(port, id, pressed);
  }
}

void LibretroEngine::SendAnalog(int port, int index, int id, int16_t value) {
  if (inputManager_) {
    inputManager_->SendAnalog(port, index, id, value);
  }
}

bool LibretroEngine::SendVirtualInput(int port, int id, bool pressed) {
  if (!inputPortRouter_ || !inputPortRouter_->CanSendVirtual(port)) {
    return false;
  }
  if (inputManager_) {
    return inputManager_->SendInput(port, id, pressed);
  }
  return false;
}

bool LibretroEngine::SendVirtualAnalog(int port, int index, int id,
                                       int16_t value) {
  if (!inputPortRouter_ || !inputPortRouter_->CanSendVirtual(port)) {
    return false;
  }
  if (inputManager_) {
    return inputManager_->SendAnalog(port, index, id, value);
  }
  return false;
}

void LibretroEngine::SendPointer(int port, int16_t x, int16_t y, bool pressed) {
  if (inputManager_) {
    inputManager_->SendPointer(port, x, y, pressed);
  }
}

void LibretroEngine::SendSensor(int port, int id, float value) {
  if (inputManager_) {
    inputManager_->SendSensor(port, id, value);
  }
}

bool LibretroEngine::AssignPortSource(int port, InputSourceType sourceType,
                                      const std::string &deviceId) {
  if (!inputPortRouter_) {
    return false;
  }
  return inputPortRouter_->AssignPort(port, sourceType, deviceId);
}

bool LibretroEngine::UnassignPortSource(int port) {
  if (!inputPortRouter_) {
    return false;
  }
  return inputPortRouter_->UnassignPort(port);
}

bool LibretroEngine::ResolvePortForDevice(const std::string &deviceId,
                                          InputSourceType sourceType,
                                          int &outPort) {
  if (!inputPortRouter_) {
    return false;
  }
  return inputPortRouter_->ResolvePortForDevice(deviceId, sourceType, outPort);
}

void LibretroEngine::RecordInputDevice(const std::string &deviceId,
                                       InputSourceType sourceType,
                                       const std::string &name) {
  if (!inputPortRouter_) {
    return;
  }
  inputPortRouter_->RecordDeviceSeen(deviceId, sourceType, name);
}

std::vector<InputDeviceInfo> LibretroEngine::ListInputDevices() const {
  if (!inputPortRouter_) {
    return {};
  }
  return inputPortRouter_->ListDevices();
}

bool LibretroEngine::CanSendVirtual(int port) const {
  if (!inputPortRouter_) {
    return false;
  }
  return inputPortRouter_->CanSendVirtual(port);
}

bool LibretroEngine::SetFilesDir(const std::string &filesDir) {
  std::lock_guard<std::recursive_mutex> lock(controlMutex_);
  const EngineState st = state_.load();
  if (IsCoreLoadedState(st) || st == EngineState::LOADING ||
      st == EngineState::STOPPING) {
    LOGF(LOG_WARN, "[NEW] SetFilesDir ignored after core loaded: %{public}s",
         filesDir.c_str());
    return false;
  }

  if (running_.load()) {
    if (messageQueue_.IsClosed()) {
      LOGF(LOG_WARN, "[NEW] SetFilesDir dropped: message queue closed");
      return false;
    }
    if (!messageQueue_.Push(EngineMessage::MakeLoadMessage(
            MessageType::SetFilesDir, filesDir))) {
      LOGF(LOG_WARN, "[NEW] SetFilesDir dropped: message queue closed");
      return false;
    }
    return true;
  }

  // 引擎未运行时可直接设置（无并发读写）
  envState_.SetBaseDir(filesDir);
  LOGF(LOG_INFO, "[NEW] EnvState BaseDir set from ArkTS: %{public}s",
       filesDir.c_str());
  return true;
}

std::string LibretroEngine::GetFilesDir() const {
  const char *dir = envState_.GetBaseDir();
  return dir ? std::string(dir) : "";
}

interfaces::IInputManager *LibretroEngine::GetInputInterface() const {
  return inputManager_.get();
}

interfaces::IRenderer *LibretroEngine::GetRendererInterface() const {
  return rendererInterface_.get();
}

bool LibretroEngine::ExecuteSyncTask(const std::function<void()> &task,
                                     uint32_t timeoutMs) {
  if (!task) {
    return false;
  }
  if (g_engineThreadInstance == this || !running_.load()) {
    task();
    return true;
  }
  if (messageQueue_.IsClosed()) {
    LOGF(LOG_WARN, "[NEW] SyncTask dropped: message queue closed");
    return false;
  }

  auto syncTask = std::make_shared<EngineSyncTask>(task);
  if (!messageQueue_.Push(EngineMessage::MakeSyncTaskMessage(syncTask))) {
    LOGF(LOG_WARN, "[NEW] SyncTask push failed: message queue closed");
    return false;
  }
  if (!syncTask->Wait(timeoutMs)) {
    LOGF(LOG_ERROR, "[NEW] SyncTask timeout after %{public}u ms", timeoutMs);
    return false;
  }
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

bool LibretroEngine::InitializeEventBridge(napi_env env, napi_value callback) {
  return eventBridge_.Initialize(env, callback);
}

void LibretroEngine::GameLoop() {
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
        ProcessFrame();
        frameCount_++;

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

          // 获取视频管线丢帧统计
          size_t videoDrops = videoPipeline_.GetDropCount();
          videoPipeline_.ResetDropCount();

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

  {
    std::lock_guard<std::mutex> renderLock(renderMutex_);
    videoPipeline_.DestroyHardwareRenderer(envState_);
  }
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
         currentCorePath_.c_str());
    // 先卸载旧核心（如果已加载）
    if (coreLoader_.IsLoaded()) {
      LOGF(LOG_INFO, "[NEW] Unloading previous core before loading new one");
      UnloadGameIfNeeded("switch_core");
      coreLoader_.GetDeinit()();
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
                 appDir.c_str());
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
           currentCorePath_.c_str());

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
         currentGamePath_.c_str(), currentGameData_ ? "YES" : "NO");
    if (!currentGamePath_.empty() &&
        !security::ValidateRomPath(currentGamePath_)) {
      LOGF(LOG_ERROR, " [NEW] LoadRom blocked: invalid ROM path %{public}s",
           currentGamePath_.c_str());
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
          std::lock_guard<std::mutex> renderLock(renderMutex_);
          HwRenderRuntimeInfo runtime{};
          runtime.video_width = videoWidth_;
          runtime.video_height = videoHeight_;
          runtime.video_max_width = videoMaxWidth_;
          runtime.video_max_height = videoMaxHeight_;
          videoPipeline_.OnHardwareGeometryChanged(envState_, runtime);
        }
        // Sanity Check: 音频采样率保护
        if (audioSampleRate_ < 8000.0 || audioSampleRate_ > 192000.0) {
          // Gambatte 等核心可能报告系统时钟频率 (2MHz+)，需修正为标准音频采样率
          // Game Boy 标准采样率通常为 32768 Hz (2^15)
          double fallbackRate = 32768.0; // 修改采样率修正值为 32768 Hz
          LOGF(LOG_WARN,
               " [NEW] Abnormal audio sample rate detected: %{public}.2f "
               "Hz. Clamping to %{public}.2f Hz to match GB standard.",
               audioSampleRate_, fallbackRate);
          audioSampleRate_ = fallbackRate;
          avInfo.timing.sample_rate = fallbackRate;
        }
        LOGF(LOG_INFO,
             "%{public}s AV applied: fps=%{public}.2f, audio_rate=%{public}.2f, "
             "video=%{public}ux%{public}u",
             kAudioChainPrefix, targetFps_, audioSampleRate_, videoWidth_,
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
    EngineState st = state_.load();
    if (IsCoreLoadedState(st) || st == EngineState::LOADING ||
        st == EngineState::STOPPING) {
      LOGF(LOG_WARN, "[NEW] SetFilesDir ignored after core loaded: %{public}s",
           msg.payload.loadPath.path);
      break;
    }
    if (!envState_.SetBaseDir(msg.payload.loadPath.path)) {
      LOGF(LOG_ERROR, "[NEW] EnvState BaseDir set from Engine thread failed");
    } else {
      LOGF(LOG_INFO, "[NEW] EnvState BaseDir set from Engine thread: %{public}s",
           msg.payload.loadPath.path);
    }
    break;
  }
  case MessageType::WindowCreated:
    if (++windowEventLogCount_ % 30 == 0) {
      LOGF(LOG_INFO, "[NEW] Message: WindowCreated");
    }
    if (hw_render_enabled_.load()) {
      std::lock_guard<std::mutex> renderLock(renderMutex_);
      OHNativeWindow *windowSnapshot = nullptr;
      {
        std::lock_guard<std::mutex> lock(windowMutex_);
        windowSnapshot = window_;
        if (windowSnapshot) {
          OH_NativeWindow_NativeObjectReference(windowSnapshot);
        }
      }
      if (windowSnapshot) {
        HwRenderRuntimeInfo runtime{};
        runtime.video_width = videoWidth_;
        runtime.video_height = videoHeight_;
        runtime.video_max_width = videoMaxWidth_;
        runtime.video_max_height = videoMaxHeight_;
        videoPipeline_.InitializeHardwareRenderer(windowSnapshot, envState_,
                                                  runtime);
        OH_NativeWindow_NativeObjectUnreference(windowSnapshot);
      }
    }
    break;
  case MessageType::WindowResized: {
    const int width = msg.payload.windowSize.width;
    const int height = msg.payload.windowSize.height;
    videoPipeline_.SetWindowSize(width, height);
    if (hw_render_enabled_.load()) {
      std::lock_guard<std::mutex> renderLock(renderMutex_);
      OHNativeWindow *windowSnapshot = nullptr;
      {
        std::lock_guard<std::mutex> lock(windowMutex_);
        windowSnapshot = window_;
        if (windowSnapshot) {
          OH_NativeWindow_NativeObjectReference(windowSnapshot);
        }
      }
      if (windowSnapshot) {
        videoPipeline_.OnHardwareWindowResized(windowSnapshot, width, height,
                                               envState_);
        OH_NativeWindow_NativeObjectUnreference(windowSnapshot);
      }
    }
    break;
  }
  case MessageType::WindowDestroyed:
    if (++windowEventLogCount_ % 30 == 0) {
      LOGF(LOG_INFO, "[NEW] Message: WindowDestroyed");
    }
    if (hw_render_enabled_.load() || videoPipeline_.HasHardwareContext()) {
      std::lock_guard<std::mutex> renderLock(renderMutex_);
      videoPipeline_.OnHardwareWindowDestroyed(envState_);
    }
    // [FIX] Always reset native window state on destruction to prevent reuse issues
    // even for software cores (which don't use DestroyHardwareRenderer)
    if (msg.payload.window.window) {
      VideoPipeline::ResetNativeWindow(msg.payload.window.window);
    }
    // [FIX] 在游戏线程清理 VideoPipeline (GLES 资源)
    videoPipeline_.Reset();
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

  bool hasAudioSample = false;
  bool hasAudioBatch = false;

  // [FIX] 添加对 retro_set_video_refresh 等函数的空指针检查
  // Mesen 核心可能在加载时某些函数指针未正确获取或核心本身未导出所有符号

  if (auto fn = coreLoader_.GetSetEnvironment()) {
    fn(OnEnvironment);
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_environment");
  }

  if (auto fn = coreLoader_.GetSetVideoRefresh()) {
    fn(OnVideoRefresh);
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
  LOGF(LOG_INFO,
       "%{public}s Audio callbacks registered: sample=%{public}d, "
       "batch=%{public}d",
       kAudioChainPrefix, hasAudioSample ? 1 : 0, hasAudioBatch ? 1 : 0);

  if (auto fn = coreLoader_.GetSetInputPoll()) {
    fn(InputManager::OnInputPoll);
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_input_poll");
  }

  if (auto fn = coreLoader_.GetSetInputState()) {
    fn(InputManager::OnInputState);
  } else {
    LOGF(LOG_WARN, "Core missing retro_set_input_state");
  }

  // 注册全局 Rumble 回调
  SetGlobalRumbleCallback(InputManager::OnRumble);

  // 注册全局 Sensor 回调
  SetGlobalSensorCallbacks(InputManager::OnSensorSetState,
                           InputManager::OnSensorGetInput);
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

  if (envState_.IsHwRenderEnabled() &&
      envState_.GetHwContextType() == RETRO_HW_CONTEXT_VULKAN) {
    std::lock_guard<std::mutex> renderLock(renderMutex_);
    OHNativeWindow *windowSnapshot = nullptr;
    {
      std::lock_guard<std::mutex> lock(windowMutex_);
      windowSnapshot = window_;
      if (windowSnapshot) {
        OH_NativeWindow_NativeObjectReference(windowSnapshot);
      }
    }
    videoPipeline_.HandleVulkanAcquire(
        windowSnapshot, envState_,
        [this]() { SetPhase(EnginePhase::VULKAN_ACQUIRE); },
        [this]() { SetPhase(EnginePhase::PROCESS_FRAME); });
    if (windowSnapshot) {
      OH_NativeWindow_NativeObjectUnreference(windowSnapshot);
    }
  }

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
    char payload[96];
    snprintf(payload, sizeof(payload),
             "{\"active\": %s, \"occupancy\": %u, \"underrun\": %s, "
             "\"underruns\": %zu, \"overruns\": %zu}",
             active ? "true" : "false", occupancy,
             underrun_likely ? "true" : "false", underruns, overruns);
    eventBridge_.Emit("audio_status", payload, false);
    if (++audioStatusLogCount_ <= 5 || (audioStatusLogCount_ % 300) == 0) {
      LOGF(LOG_INFO,
           "%{public}s AudioStatus: active=%{public}d, occupancy=%{public}u, "
           "underrun=%{public}d, underruns=%{public}zu, overruns=%{public}zu",
           kAudioChainPrefix, active ? 1 : 0, occupancy,
           underrun_likely ? 1 : 0, underruns, overruns);
    }

    const bool underrun_inc = underruns > lastAudioUnderruns_;
    const bool overrun_inc = overruns > lastAudioOverruns_;
    const bool low_buffer = active && occupancy <= 10;
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

  // 更新时间戳
  lastRunTimestamp_ = now;
  hasLastRunTimestamp_ = true;

  // 退出 retro_run 上下文
  envState_.ExitRetroRun();
}

// --- Libretro 静态回调桥接实现 ---

void LibretroEngine::OnVideoRefresh(const void *data, unsigned width,
                                    unsigned height, size_t pitch) {
  if (!g_engineInstance)
    return;

  if (g_engineInstance->surface_state_.load() != SurfaceState::VALID) {
    // Surface 未处于有效状态时直接丢帧。
    // 这比仅检查 window 指针更可靠，能覆盖 Created/Destroyed 等生命周期中间态。
    g_engineInstance->surfaceInvalidDropLogCount_++;
    if (g_engineInstance->surfaceInvalidDropLogCount_ <= 5 ||
        (g_engineInstance->surfaceInvalidDropLogCount_ % 120) == 0) {
      OHNativeWindow *windowSnapshot = nullptr;
      {
        std::lock_guard<std::mutex> lock(g_engineInstance->windowMutex_);
        windowSnapshot = g_engineInstance->window_;
      }
      const int cachedW = g_engineInstance->last_window_width_.load();
      const int cachedH = g_engineInstance->last_window_height_.load();
      LOGF(LOG_WARN,
           "[NEW] Drop frame: surface invalid (surface=%{public}d, "
           "window=%{public}p, cached=%{public}dx%{public}d, state=%{public}d)",
           static_cast<int>(g_engineInstance->surface_state_.load()),
           windowSnapshot, cachedW, cachedH,
           static_cast<int>(g_engineInstance->state_.load()));
    }
    {
      std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
      g_engineInstance->stats_.videoRefreshCalls++;
      if (!data) {
        g_engineInstance->stats_.videoNullFrames++;
      }
      g_engineInstance->stats_.videoDroppedFrames++;
    }
    return;
  }

  // Auto Frame Skip for Audio Stability
  // 如果音频缓冲区低于 20% 且没有连续跳过超过 3 帧，则主动跳帧以优先保证音频处理
  auto *audioBridge = AudioBridge::GetInstance();
  if (audioBridge && audioBridge->IsRunning()) {
      float usage = audioBridge->GetBufferUsage();
      if (usage < 0.2f && g_engineInstance->skip_frame_counter_ < 3) {
          g_engineInstance->skip_frame_counter_++;
          
          static size_t skipLogCount = 0;
          if (++skipLogCount % 60 == 0) {
             LOGF(LOG_WARN, "[Perf] Auto-skipping frame (audio usage=%.1f%%)", usage * 100.0f);
          }

          {
              std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
              g_engineInstance->stats_.videoDroppedFrames++;
              g_engineInstance->stats_.videoRefreshCalls++;
          }
          return;
      }
  }
  g_engineInstance->skip_frame_counter_ = 0;

  const bool nullFrameRequested = (data == nullptr);

  if (g_engineInstance->envState_.IsHwRenderEnabled()) {
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
      if (++g_engineInstance->videoRefreshLogCount_ % 120 == 0) {
        LOGF(LOG_INFO, " [NEW] OnVideoRefresh (HW): valid framebuffer");
      }
      {
        std::lock_guard<std::mutex> renderLock(g_engineInstance->renderMutex_);
        g_engineInstance->videoPipeline_.SwapHardwareBuffers(
            g_engineInstance->envState_);
      }

      {
        std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
        g_engineInstance->stats_.videoRefreshCalls++;
      }
      return;
    }
    if (!data) {
      if (++g_engineInstance->videoRefreshLogCount_ % 120 == 0) {
        LOGF(LOG_INFO, " [NEW] OnVideoRefresh (HW): null frame");
      }
      {
        std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
        g_engineInstance->stats_.videoRefreshCalls++;
        g_engineInstance->stats_.videoNullFrames++;
      }
      return;
    }
  }

  OHNativeWindow *window = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_engineInstance->windowMutex_);
    window = g_engineInstance->window_;
    if (window) {
      OH_NativeWindow_NativeObjectReference(window);
    }
  }
  if (++g_engineInstance->videoRefreshLogCount_ % 300 == 0) {
    LOGF(LOG_INFO,
         " [NEW] OnVideoRefresh #%{public}zu: %{public}ux%{public}u "
         "pitch=%{public}zu",
         g_engineInstance->videoRefreshLogCount_, width, height, pitch);
  }

  VideoPipeline::RenderMetrics metrics{};
  constexpr int64_t kSlowVideoRenderMs = 50;
  g_engineInstance->SetPhase(EnginePhase::VIDEO_RENDER);
  const auto renderStart = std::chrono::steady_clock::now();
  const auto result = g_engineInstance->videoPipeline_.Render(
      window, data, width, height, pitch, &metrics);
  const auto renderMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                            std::chrono::steady_clock::now() - renderStart)
                            .count();
  if (g_engineInstance) {
    g_engineInstance->lastVideoRenderMs_.store(renderMs,
                                               std::memory_order_relaxed);
    g_engineInstance->lastVideoRenderResult_.store(static_cast<int>(result),
                                                   std::memory_order_relaxed);
    g_engineInstance->lastVideoRenderWidth_.store(width,
                                                  std::memory_order_relaxed);
    g_engineInstance->lastVideoRenderHeight_.store(height,
                                                   std::memory_order_relaxed);
    g_engineInstance->lastVideoRenderPitch_.store(pitch,
                                                  std::memory_order_relaxed);
  }
  if (renderMs >= kSlowVideoRenderMs &&
      ShouldLog(g_engineInstance->slowVideoRenderLogCount_, 3, 120)) {
    LOGF(LOG_WARN,
         "[Perf] Slow video render: %{public}lld ms (%{public}ux%{public}u, "
         "pitch=%{public}zu, result=%{public}d)",
         static_cast<long long>(renderMs), width, height, pitch,
         static_cast<int>(result));
  }
  g_engineInstance->SetPhase(EnginePhase::RETRO_RUN);

  {
    std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
    g_engineInstance->stats_.videoRefreshCalls++;
    if (nullFrameRequested) {
      g_engineInstance->stats_.videoNullFrames++;
    }
    if (result == VideoPipeline::RenderResult::DUPED) {
      g_engineInstance->stats_.videoDupeFrames++;
    }
    if (result == VideoPipeline::RenderResult::DROPPED) {
      g_engineInstance->stats_.videoDroppedFrames++;
    }

    g_engineInstance->stats_.nwRequestBufferCalls +=
        metrics.nwRequestBufferCalls;
    g_engineInstance->stats_.nwRequestBufferFailures +=
        metrics.nwRequestBufferFailures;
    g_engineInstance->stats_.nwFlushBufferCalls += metrics.nwFlushBufferCalls;
    g_engineInstance->stats_.nwFlushBufferFailures +=
        metrics.nwFlushBufferFailures;
    g_engineInstance->stats_.nwAbortBufferCalls += metrics.nwAbortBufferCalls;
    g_engineInstance->stats_.nbFromWindowBufferFailures +=
        metrics.nbFromWindowBufferFailures;
    g_engineInstance->stats_.nbMapFailures += metrics.nbMapFailures;
    g_engineInstance->stats_.nbUnmapFailures += metrics.nbUnmapFailures;
    g_engineInstance->stats_.fenceWaitCalls += metrics.fenceWaitCalls;
    g_engineInstance->stats_.fenceWaitFailures += metrics.fenceWaitFailures;
    g_engineInstance->stats_.fenceTimeoutCount += metrics.fenceTimeoutCount;

    if (metrics.frameTimeUs > 0) {
      if (metrics.frameTimeUs < g_engineInstance->stats_.frameTimeMin) {
        g_engineInstance->stats_.frameTimeMin = metrics.frameTimeUs;
      }
      if (metrics.frameTimeUs > g_engineInstance->stats_.frameTimeMax) {
        g_engineInstance->stats_.frameTimeMax = metrics.frameTimeUs;
      }
      g_engineInstance->stats_.frameTimeSum += metrics.frameTimeUs;
      g_engineInstance->stats_.frameCount++;
    }
  }
  if (window) {
    OH_NativeWindow_NativeObjectUnreference(window);
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
  if (!g_engineInstance)
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
    std::lock_guard<std::mutex> lock(g_engineInstance->statsMutex_);
    g_engineInstance->stats_.audioBatchCalls++;
    g_engineInstance->stats_.audioFramesIn += actualFrames;
    batch_count = g_engineInstance->stats_.audioBatchCalls;
  }

  if (batch_count <= 5 || (batch_count % 300) == 0) {
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
    if (g_engineInstance->targetFps_ > 0.0) {
      expected_frames = static_cast<int32_t>(
          g_engineInstance->audioSampleRate_ / g_engineInstance->targetFps_);
    }
    int32_t delta_frames =
        static_cast<int32_t>(actualFrames) - expected_frames;
    int32_t fps_x100 =
        static_cast<int32_t>(g_engineInstance->targetFps_ * 100.0);
    int32_t rate_i =
        static_cast<int32_t>(g_engineInstance->audioSampleRate_);
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
  if (!g_engineInstance) {
    return false;
  }

  // 调用 EnvDispatcher 处理完整的环境命令
  bool handled =
      HandleEnvironmentCommand(g_engineInstance->envState_, cmd, data);

  if (cmd == RETRO_ENVIRONMENT_SET_HW_RENDER && handled) {
    g_engineInstance->hw_render_enabled_.store(
        g_engineInstance->envState_.IsHwRenderEnabled());
    {
      const auto &cb = g_engineInstance->envState_.GetHwRenderCallback();
      LOGF(LOG_INFO,
           "[NEW] HW render requested: enabled=%{public}d, ctx=%{public}d, "
           "cache=%{public}d",
           g_engineInstance->hw_render_enabled_.load() ? 1 : 0,
           static_cast<int>(cb.context_type), cb.cache_context ? 1 : 0);
    }
    if (g_engineInstance->hw_render_enabled_.load()) {
      bool hasWindow = false;
      {
        std::lock_guard<std::mutex> lock(g_engineInstance->windowMutex_);
        hasWindow = (g_engineInstance->window_ != nullptr);
      }
      if (hasWindow) {
        std::lock_guard<std::mutex> renderLock(g_engineInstance->renderMutex_);
        OHNativeWindow *windowSnapshot = nullptr;
        {
          std::lock_guard<std::mutex> lock(g_engineInstance->windowMutex_);
          windowSnapshot = g_engineInstance->window_;
          if (windowSnapshot) {
            OH_NativeWindow_NativeObjectReference(windowSnapshot);
          }
        }
        if (windowSnapshot) {
          HwRenderRuntimeInfo runtime{};
          runtime.video_width = g_engineInstance->videoWidth_;
          runtime.video_height = g_engineInstance->videoHeight_;
          runtime.video_max_width = g_engineInstance->videoMaxWidth_;
          runtime.video_max_height = g_engineInstance->videoMaxHeight_;
          g_engineInstance->videoPipeline_.InitializeHardwareRenderer(
              windowSnapshot, g_engineInstance->envState_, runtime);
          OH_NativeWindow_NativeObjectUnreference(windowSnapshot);
        }
      }
    } else {
      if (g_engineInstance->videoPipeline_.HasHardwareContext()) {
        std::lock_guard<std::mutex> renderLock(g_engineInstance->renderMutex_);
        g_engineInstance->videoPipeline_.DestroyHardwareRenderer(
            g_engineInstance->envState_);
      }
    }
  }

  // 特殊处理：将像素格式同步到 VideoPipeline
  if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && handled) {
    retro_pixel_format format = g_engineInstance->envState_.GetPixelFormat();
    g_engineInstance->videoPipeline_.SetPixelFormat(format);
    LOGF(LOG_INFO, "Pixel format set to: %{public}d", static_cast<int>(format));
    char payload[64];
    snprintf(payload, sizeof(payload), "{\"format\": %d}",
             static_cast<int>(format));
    g_engineInstance->eventBridge_.Emit("pixel_format_update", payload, false);
  }

  if (cmd == RETRO_ENVIRONMENT_GET_CAN_DUPE && handled) {
    bool can = g_engineInstance->envState_.CanDupe();
    g_engineInstance->videoPipeline_.SetCanDupe(can);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_GEOMETRY && handled) {
    unsigned bw = g_engineInstance->envState_.GetGeometryBaseWidth();
    unsigned bh = g_engineInstance->envState_.GetGeometryBaseHeight();
    float aspect = g_engineInstance->envState_.GetGeometryAspectRatio();
    g_engineInstance->videoPipeline_.SetGeometry(bw, bh, aspect);
    if (g_engineInstance->hw_render_enabled_.load()) {
      std::lock_guard<std::mutex> renderLock(g_engineInstance->renderMutex_);
      HwRenderRuntimeInfo runtime{};
      runtime.video_width = g_engineInstance->videoWidth_;
      runtime.video_height = g_engineInstance->videoHeight_;
      runtime.video_max_width = g_engineInstance->videoMaxWidth_;
      runtime.video_max_height = g_engineInstance->videoMaxHeight_;
      g_engineInstance->videoPipeline_.OnHardwareGeometryChanged(
          g_engineInstance->envState_, runtime);
    }
    char payload[96];
    snprintf(
        payload, sizeof(payload),
        "{\"base_width\": %u, \"base_height\": %u, \"aspect_ratio\": %.6f}", bw,
        bh, aspect);
    g_engineInstance->eventBridge_.Emit("geometry_update", payload, false);
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
    g_engineInstance->eventBridge_.Emit("core_message", payload, false);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE && handled) {
    if (g_engineInstance->diskController_) {
      g_engineInstance->diskController_->SetCallbacks(
          (const struct retro_disk_control_callback *)data);
    }
    g_engineInstance->eventBridge_.Emit("disk_control", "{\"type\": \"basic\"}",
                                        false);
  }

  if (cmd == RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE && handled) {
    if (g_engineInstance->diskController_) {
      g_engineInstance->diskController_->SetCallbacks(
          (const struct retro_disk_control_ext_callback *)data);
    }
    g_engineInstance->eventBridge_.Emit("disk_control", "{\"type\": \"ext\"}",
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

  videoPipeline_.SetScalingMode(sm);

  LOGF(LOG_INFO, " [NEW] SetScalingMode: %{public}d (%{public}s)", mode,
       modeStr);
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
  const auto &defs = envState_.GetCoreOptionDefinitions();
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

bool LibretroEngine::DiskControlSetEjectState(bool ejected) {
  if (!diskController_)
    return false;
  return ejected ? diskController_->Eject() : diskController_->Insert();
}

bool LibretroEngine::DiskControlGetEjectState() {
  if (!diskController_)
    return false;
  return diskController_->IsEjected();
}

unsigned LibretroEngine::DiskControlGetImageIndex() {
  if (!diskController_)
    return 0;
  return diskController_->GetImageIndex();
}

bool LibretroEngine::DiskControlSetImageIndex(unsigned index) {
  if (!diskController_)
    return false;
  return diskController_->SetImageIndex(index);
}

unsigned LibretroEngine::DiskControlGetNumImages() {
  if (!diskController_)
    return 0;
  return diskController_->GetNumImages();
}

bool LibretroEngine::DiskControlReplaceImageIndex(unsigned index,
                                                  const std::string &path) {
  if (!diskController_)
    return false;
  return diskController_->ReplaceImageIndex(index, path);
}

bool LibretroEngine::DiskControlAddImageIndex() {
  if (!diskController_)
    return false;
  return diskController_->AddImageIndex();
}

void LibretroEngine::TransitionTo(EngineState newState) {
  EngineState oldState = state_.load();
  if (!IsValidTransition(oldState, newState)) {
    LOGF(LOG_WARN, "Illegal state transition: %{public}d -> %{public}d",
         static_cast<int>(oldState), static_cast<int>(newState));
    return;
  }
  if (oldState == newState) {
    return;
  }
  state_.store(newState);
  stateCond_.notify_all();
  LOGF(LOG_INFO, "State Transition: %{public}d -> %{public}d",
       static_cast<int>(oldState), static_cast<int>(newState));

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
  } else if (newState == EngineState::PAUSED ||
             newState == EngineState::STOPPING) {
    const bool ok = bridge->Pause();
    LOGF(LOG_INFO,
         "%{public}s AudioBridge pause on state=%{public}d: ok=%{public}d, "
         "running=%{public}d, playing=%{public}d",
         kAudioChainPrefix, static_cast<int>(newState), ok ? 1 : 0,
         bridge->IsRunning() ? 1 : 0, bridge->IsPlaying() ? 1 : 0);
  } else if (newState == EngineState::STOPPED) {
    const bool ok = bridge->Stop();
    LOGF(LOG_INFO,
         "%{public}s AudioBridge stop on STOPPED: ok=%{public}d, "
         "running=%{public}d, playing=%{public}d",
         kAudioChainPrefix, ok ? 1 : 0, bridge->IsRunning() ? 1 : 0,
         bridge->IsPlaying() ? 1 : 0);
  }
}

bool LibretroEngine::WaitForState(EngineState target, uint32_t timeoutMs) {
  if (state_.load() == target) {
    return true;
  }
  std::unique_lock<std::mutex> lock(stateMutex_);
  if (timeoutMs == 0) {
    return state_.load() == target;
  }
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
  size_t size = 0;
  (void)ExecuteSyncTask(
      [this, &size]() {
        if (stateManager_) {
          size = stateManager_->GetSaveStateSize();
        }
      },
      kSyncTaskTimeoutMs);
  return size;
}

bool LibretroEngine::SaveState(std::vector<uint8_t> &outData) {
  bool ok = false;
  std::vector<uint8_t> snapshot;
  if (!ExecuteSyncTask(
          [this, &ok, &snapshot]() {
            if (stateManager_) {
              ok = stateManager_->SaveState(snapshot);
            }
          },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  if (!ok) {
    return false;
  }
  outData = std::move(snapshot);
  return true;
}

bool LibretroEngine::LoadState(const std::vector<uint8_t> &data) {
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, &data]() {
            if (stateManager_) {
              ok = stateManager_->LoadState(data);
            }
          },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  return ok;
}

// --- SRAM 接口 ---

bool LibretroEngine::GetSRAM(std::vector<uint8_t> &outData) {
  bool ok = false;
  std::vector<uint8_t> snapshot;
  if (!ExecuteSyncTask(
          [this, &ok, &snapshot]() {
            if (stateManager_) {
              ok = stateManager_->GetSRAM(snapshot);
            }
          },
          kSyncTaskTimeoutMs)) {
    return false;
  }
  if (!ok) {
    return false;
  }
  outData = std::move(snapshot);
  return true;
}

bool LibretroEngine::SetSRAM(const std::vector<uint8_t> &data) {
  bool ok = false;
  if (!ExecuteSyncTask(
          [this, &ok, &data]() {
            if (stateManager_) {
              ok = stateManager_->SetSRAM(data);
            }
          },
          kSyncTaskTimeoutMs)) {
    return false;
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

void LibretroEngine::ResetCore() {
  const bool dispatched = ExecuteSyncTask(
      [this]() {
        if (!coreLoader_.IsLoaded()) {
          return;
        }
        auto fn = coreLoader_.GetReset();
        if (fn) {
          fn();
          LOGF(LOG_INFO, "Core reset");
        }
      },
      kSyncTaskTimeoutMs);
  if (!dispatched) {
    LOGF(LOG_WARN, "[NEW] ResetCore skipped: sync dispatch failed");
  }
}

// --- 金手指实现 ---

void LibretroEngine::CheatReset() {
  const bool dispatched = ExecuteSyncTask(
      [this]() {
        if (stateManager_) {
          stateManager_->CheatReset();
        }
      },
      kSyncTaskTimeoutMs);
  if (!dispatched) {
    LOGF(LOG_WARN, "[NEW] CheatReset skipped: sync dispatch failed");
  }
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
          kSyncTaskTimeoutMs)) {
    return false;
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
          kSyncTaskTimeoutMs)) {
    return 0;
  }
  return ok ? region : 0;
}

} // namespace libretro
