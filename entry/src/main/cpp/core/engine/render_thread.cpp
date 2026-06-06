#include "render_thread.h"

#include "core/libretro/env_dispatcher.h"
#include <algorithm>
#include <chrono>
#include <hilog/log.h>
#include "qos/qos.h"

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD008
#undef LOG_TAG
#define LOG_TAG "RenderThread"
#undef LOG_FLOW
#define LOG_FLOW "Render"
#include "common/log_prefix.h"

namespace libretro {
namespace {
int64_t NowUs() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
} // namespace

RenderThread::RenderThread(VideoPipeline &pipeline, EnvState &envState)
    : videoPipeline_(pipeline), envState_(envState) {
  PublishWindowSessionSnapshot();
}

RenderThread::~RenderThread() { Stop(); }

void RenderThread::SetEnabled(bool enabled) {
  const bool old = enabled_.exchange(enabled, std::memory_order_acq_rel);
  if (old == enabled) {
    return;
  }
  if (enabled) {
    (void)Start();
  } else {
    Stop();
  }
}

void RenderThread::SetNativeVSyncEnabled(bool enabled) {
  nativeVsyncEnabled_.store(enabled, std::memory_order_release);
  if (running_.load(std::memory_order_acquire)) {
    if (enabled) {
      StartVSyncIfNeeded();
      if (nativeVsyncActive_.load(std::memory_order_acquire)) {
        RequestNextVSync();
      }
    } else {
      StopVSync();
    }
    controlCond_.notify_one();
  }
}

bool RenderThread::Start() {
  if (!enabled_.load(std::memory_order_acquire)) {
    return true;
  }
  if (running_.exchange(true, std::memory_order_acq_rel)) {
    return true;
  }

  stopRequested_.store(false, std::memory_order_release);
  {
    std::lock_guard<std::mutex> lock(controlMutex_);
    controlQueue_.clear();
  }
  frameQueue_.Clear();

  renderThread_ = std::thread(&RenderThread::ThreadMain, this);
  return true;
}

void RenderThread::Stop() {
  if (!running_.exchange(false, std::memory_order_acq_rel)) {
    return;
  }

  stopRequested_.store(true, std::memory_order_release);
  ControlMessage message;
  message.type = ControlType::STOP;
  PushControl(std::move(message));

  if (renderThread_.joinable()) {
    renderThread_.join();
  }
}

void RenderThread::SetWindow(OHNativeWindow *window, uint64_t generation) {
  ControlMessage message;
  message.type = ControlType::SET_WINDOW;
  message.window = window;
  message.generation = generation;
  if (message.window) {
    OH_NativeWindow_NativeObjectReference(message.window);
  }
  PushControl(std::move(message));
}

void RenderThread::InvalidateFrameQueueForGeneration(uint64_t generation) {
  frameQueue_.Clear();
  if (generation > 0) {
    staleGenerationDropLogCount_.store(0, std::memory_order_release);
  }
}

void RenderThread::SetWindowSize(int width, int height) {
  ControlMessage message;
  message.type = ControlType::RESIZE;
  message.width = width;
  message.height = height;
  PushControl(std::move(message));
}

void RenderThread::SetHwRenderRuntimeInfo(const HwRenderRuntimeInfo &runtime) {
  ControlMessage message;
  message.type = ControlType::HW_RUNTIME;
  message.runtime = runtime;
  PushControl(std::move(message));
}

bool RenderThread::EnqueueFrame(VideoFramePacket &&packet) {
  const bool ok = frameQueue_.Push(std::move(packet));
  if (!ok) {
    return false;
  }

  if (!nativeVsyncActive_.load(std::memory_order_acquire)) {
    ControlMessage message;
    message.type = ControlType::TICK;
    message.timestampUs = NowUs();
    PushControl(std::move(message));
  }
  return true;
}

RenderThreadStats RenderThread::GetStats() const {
  RenderThreadStats out;
  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    out = stats_;
  }

  const auto queueStats = frameQueue_.GetStats();
  out.queuePushed = queueStats.pushed;
  out.queuePopped = queueStats.popped;
  out.queueDroppedOldest = queueStats.droppedOldest;
  out.queueDroppedStaleOnPop = queueStats.droppedStaleOnPop;
  out.queueDepthMax = queueStats.depthMax;
  return out;
}

void RenderThread::ResetStats() {
  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    stats_ = RenderThreadStats{};
  }
  frameQueue_.ResetStats();
}

WindowSessionSnapshot RenderThread::GetWindowSessionSnapshot() const {
  WindowSessionSnapshot out{};
  out.sessionId = windowSessionIdSnapshot_.load(std::memory_order_acquire);
  out.generation = windowGenerationSnapshot_.load(std::memory_order_acquire);
  out.state = static_cast<WindowSessionState>(
      windowStateSnapshot_.load(std::memory_order_acquire));
  out.width = windowWidthSnapshot_.load(std::memory_order_acquire);
  out.height = windowHeightSnapshot_.load(std::memory_order_acquire);
  out.active = windowActiveSnapshot_.load(std::memory_order_acquire);
  out.hasWindow = windowHasHandleSnapshot_.load(std::memory_order_acquire);
  return out;
}

void RenderThread::ThreadMain() {
  // API12+ QoS：渲染线程同样标记为最高交互优先级，与 Game 线程一致争取大核。
  int qosRet = OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE);
  LOGF(LOG_INFO, "[QoS] RenderThread QoS set ret=%{public}d", qosRet);
  // 平台门控:QoS 成功(真机,有 RT 调度、多大核)→ 允许 FramePacer 末尾 hybrid 极短
  // 自旋收窄帧抖动;失败(模拟器,无 RT、少 vCPU、软件 GPU 已占满核)→ 禁忙等自旋改纯
  // sleep,不让 RenderThread 用 PAUSE 烧满一个虚拟核去抢 GameLoop / 软件 GL 的核。
  // 依据:外网实证 PAUSE 忙等填毫秒级帧节拍在 VM/模拟器是反模式;FramePacer(093d3a8
  // 2026-05-24 引入)正落在 5.0.5→6.0.2 回归窗口。详见 docs/audit/2026-06-06-video-swap-stall.md。
  videoPipeline_.SetFramePacerBusyWaitAllowed(qosRet == 0);
  StartVSyncIfNeeded();
  if (nativeVsyncActive_.load(std::memory_order_acquire)) {
    RequestNextVSync();
  }

  while (true) {
    ControlMessage message;
    bool hasMessage = false;

    {
      std::unique_lock<std::mutex> lock(controlMutex_);
      if (controlQueue_.empty() && !stopRequested_.load(std::memory_order_acquire)) {
        if (nativeVsyncActive_.load(std::memory_order_acquire)) {
          controlCond_.wait(lock, [this]() {
            return stopRequested_.load(std::memory_order_acquire) ||
                   !controlQueue_.empty();
          });
        } else {
          controlCond_.wait_for(lock, std::chrono::milliseconds(16), [this]() {
            return stopRequested_.load(std::memory_order_acquire) ||
                   !controlQueue_.empty();
          });
          if (controlQueue_.empty() &&
              !stopRequested_.load(std::memory_order_acquire)) {
            message.type = ControlType::TICK;
            message.timestampUs = NowUs();
            hasMessage = true;
            std::lock_guard<std::mutex> statsLock(statsMutex_);
            stats_.vsyncFallbackTicks++;
          }
        }
      }

      if (!hasMessage && !controlQueue_.empty()) {
        message = std::move(controlQueue_.front());
        controlQueue_.pop_front();
        hasMessage = true;
      }
    }

    if (!hasMessage && stopRequested_.load(std::memory_order_acquire)) {
      break;
    }

    if (hasMessage) {
      if (message.type == ControlType::STOP) {
        break;
      }
      HandleControl(message);
    }
  }

  StopVSync();
  HandleSetWindow(nullptr, 0);
  frameQueue_.Clear();
}

void RenderThread::PushControl(ControlMessage &&message) {
  {
    std::lock_guard<std::mutex> lock(controlMutex_);
    if (message.type == ControlType::TICK) {
      // Coalesce continuous ticks to avoid starving lifecycle controls.
      if (!controlQueue_.empty() &&
          controlQueue_.back().type == ControlType::TICK) {
        return;
      }
    } else {
      // Prioritize lifecycle/control messages over render ticks.
      controlQueue_.erase(
          std::remove_if(controlQueue_.begin(), controlQueue_.end(),
                         [](const ControlMessage &m) {
                           return m.type == ControlType::TICK;
                         }),
          controlQueue_.end());

      if (message.type == ControlType::SET_WINDOW) {
        // Keep only latest pending SetWindow. Release stale retained refs.
        for (auto it = controlQueue_.begin(); it != controlQueue_.end();) {
          if (it->type == ControlType::SET_WINDOW) {
            if (it->window) {
              OH_NativeWindow_NativeObjectUnreference(it->window);
            }
            it = controlQueue_.erase(it);
          } else {
            ++it;
          }
        }
      } else if (message.type == ControlType::RESIZE) {
        // Keep only latest resize signal.
        controlQueue_.erase(
            std::remove_if(controlQueue_.begin(), controlQueue_.end(),
                           [](const ControlMessage &m) {
                             return m.type == ControlType::RESIZE;
                           }),
            controlQueue_.end());
      }
    }

    controlQueue_.emplace_back(std::move(message));
  }
  controlCond_.notify_one();
}

void RenderThread::HandleControl(const ControlMessage &message) {
  switch (message.type) {
  case ControlType::SET_WINDOW:
    HandleSetWindow(message.window, message.generation);
    break;
  case ControlType::RESIZE:
    HandleResize(message.width, message.height);
    break;
  case ControlType::TICK:
    HandleTick();
    break;
  case ControlType::HW_RUNTIME:
    HandleRuntimeChanged(message.runtime);
    break;
  case ControlType::STOP:
    break;
  }
}

void RenderThread::HandleSetWindow(OHNativeWindow *window,
                                   uint64_t generation) {
  static uint32_t windowSessionLogCount = 0;
  const bool generationChanged =
      (generation > 0 && generation != windowSession_.generation);
  if (windowSession_.window == window && generationChanged) {
    static uint32_t generationOnlyRebindLogCount = 0;
    const uint32_t n = ++generationOnlyRebindLogCount;
    if (n <= 5 || (n % 120) == 0) {
      LOGF(LOG_INFO,
           "WindowSession generation rebind: sid=%{public}llu old_gen=%{public}llu new_gen=%{public}llu",
           static_cast<unsigned long long>(windowSession_.sessionId),
           static_cast<unsigned long long>(windowSession_.generation),
           static_cast<unsigned long long>(generation));
    }
  }
  if (windowSession_.window == window && !generationChanged) {
    if (window) {
      OH_NativeWindow_NativeObjectUnreference(window);
    }
    return;
  }

  // Any lifecycle mutation invalidates in-flight frames from previous generation.
  frameQueue_.Clear();
  if (generation > 0) {
    windowSession_.generation = generation;
  } else {
    windowSession_.generation++;
  }
  windowSession_.sessionId++;
  windowSession_.active = false;
  // 必须等待当前代际的有效 Resize 才允许渲染，避免沿用旧尺寸过早 RequestBuffer。
  windowSession_.width = 0;
  windowSession_.height = 0;

  if (windowSession_.window) {
    if (envState_.IsHwRenderEnabled() || videoPipeline_.HasHardwareContext()) {
      videoPipeline_.OnHardwareWindowDestroyed(envState_);
    }
    VideoPipeline::ResetNativeWindow(windowSession_.window);
    OH_NativeWindow_NativeObjectUnreference(windowSession_.window);
    windowSession_.window = nullptr;
    videoPipeline_.Reset();
  }

  windowSession_.window = window;
  if (!windowSession_.window) {
    windowSession_.state = WindowSessionState::DESTROYED;
    const uint32_t n = ++windowSessionLogCount;
    if (n <= 5 || (n % 60) == 0) {
      LOGF(LOG_INFO,
           "WindowSession update: sid=%{public}llu gen=%{public}llu state=%{public}s active=%{public}d size=%{public}dx%{public}d window=%{public}p",
           static_cast<unsigned long long>(windowSession_.sessionId),
           static_cast<unsigned long long>(windowSession_.generation),
           WindowSessionStateToString(windowSession_.state),
           windowSession_.active ? 1 : 0, windowSession_.width,
           windowSession_.height, windowSession_.window);
    }
    PublishWindowSessionSnapshot();
    return;
  }

  windowSession_.state = WindowSessionState::ATTACHED_PENDING_SIZE;
  windowSession_.active = false;
  videoPipeline_.ForceReconfiguration();

  if (envState_.IsHwRenderEnabled()) {
    videoPipeline_.InitializeHardwareRenderer(windowSession_.window, envState_,
                                              hwRuntime_);
  }
  const uint32_t n = ++windowSessionLogCount;
  if (n <= 5 || (n % 60) == 0) {
    LOGF(LOG_INFO,
         "WindowSession update: sid=%{public}llu gen=%{public}llu state=%{public}s active=%{public}d size=%{public}dx%{public}d window=%{public}p",
         static_cast<unsigned long long>(windowSession_.sessionId),
         static_cast<unsigned long long>(windowSession_.generation),
         WindowSessionStateToString(windowSession_.state),
         windowSession_.active ? 1 : 0, windowSession_.width,
         windowSession_.height, windowSession_.window);
  }
  PublishWindowSessionSnapshot();
}

void RenderThread::HandleResize(int width, int height) {
  static uint32_t windowResizeLogCount = 0;
  windowSession_.width = width;
  windowSession_.height = height;
  videoPipeline_.SetWindowSize(width, height);

  if (width <= 0 || height <= 0) {
    windowSession_.active = false;
    windowSession_.state = windowSession_.window ? WindowSessionState::PAUSED_SURFACE
                                                 : WindowSessionState::DETACHED;
    const uint32_t n = ++windowResizeLogCount;
    if (n <= 5 || (n % 120) == 0) {
      LOGF(LOG_INFO,
           "WindowSession resize: sid=%{public}llu gen=%{public}llu state=%{public}s active=%{public}d size=%{public}dx%{public}d",
           static_cast<unsigned long long>(windowSession_.sessionId),
           static_cast<unsigned long long>(windowSession_.generation),
           WindowSessionStateToString(windowSession_.state),
           windowSession_.active ? 1 : 0, windowSession_.width,
           windowSession_.height);
    }
    PublishWindowSessionSnapshot();
    return;
  }

  if (!windowSession_.window) {
    windowSession_.active = false;
    windowSession_.state = WindowSessionState::DETACHED;
    const uint32_t n = ++windowResizeLogCount;
    if (n <= 5 || (n % 120) == 0) {
      LOGF(LOG_INFO,
           "WindowSession resize: sid=%{public}llu gen=%{public}llu state=%{public}s active=%{public}d size=%{public}dx%{public}d",
           static_cast<unsigned long long>(windowSession_.sessionId),
           static_cast<unsigned long long>(windowSession_.generation),
           WindowSessionStateToString(windowSession_.state),
           windowSession_.active ? 1 : 0, windowSession_.width,
           windowSession_.height);
    }
    PublishWindowSessionSnapshot();
    return;
  }

  windowSession_.active = true;
  windowSession_.state = WindowSessionState::READY;
  if (envState_.IsHwRenderEnabled()) {
    videoPipeline_.OnHardwareWindowResized(windowSession_.window, width, height,
                                           envState_);
  }
  const uint32_t n = ++windowResizeLogCount;
  if (n <= 5 || (n % 120) == 0) {
    LOGF(LOG_INFO,
         "WindowSession resize: sid=%{public}llu gen=%{public}llu state=%{public}s active=%{public}d size=%{public}dx%{public}d",
         static_cast<unsigned long long>(windowSession_.sessionId),
         static_cast<unsigned long long>(windowSession_.generation),
         WindowSessionStateToString(windowSession_.state),
         windowSession_.active ? 1 : 0, windowSession_.width,
         windowSession_.height);
  }
  PublishWindowSessionSnapshot();
}

void RenderThread::HandleTick() {
  if (HasPendingLifecycleControl()) {
    static uint32_t deferredTickLogCount = 0;
    const uint32_t n = ++deferredTickLogCount;
    if (n <= 5 || (n % 120) == 0) {
      LOGF(LOG_INFO, "Render tick deferred: pending lifecycle controls");
    }
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.renderTickNoFrame++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  VideoFramePacket packet;
  if (!frameQueue_.PopLatest(packet)) {
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.renderTickNoFrame++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  if (!windowSession_.IsRenderable()) {
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.droppedFrames++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  if (packet.surfaceGeneration != 0 &&
      packet.surfaceGeneration != windowSession_.generation) {
    const uint64_t staleCount =
        staleGenerationDropLogCount_.fetch_add(1, std::memory_order_acq_rel) +
        1;
    if (staleCount <= 5 || (staleCount % 120) == 0) {
      LOGF(LOG_INFO,
           "Drop stale frame: frame_gen=%{public}llu session_gen=%{public}llu sid=%{public}llu kind=%{public}d",
           static_cast<unsigned long long>(packet.surfaceGeneration),
           static_cast<unsigned long long>(windowSession_.generation),
           static_cast<unsigned long long>(windowSession_.sessionId),
           static_cast<int>(packet.kind));
    }
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.droppedFrames++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  if (packet.kind == VideoFrameKind::HW_SWAP) {
    videoPipeline_.SwapHardwareBuffers(envState_);
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.renderedFrames++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  if (packet.kind == VideoFrameKind::HW_NULL ||
      packet.kind == VideoFrameKind::NULL_FRAME) {
    bool requestVsync = false;
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.renderedFrames++;
      requestVsync = nativeVsyncActive_.load(std::memory_order_acquire);
    }
    if (requestVsync) {
      RequestNextVSync();
    }
    return;
  }

  const void *pixels = nullptr;
  if (packet.storage && !packet.storage->empty()) {
    pixels = packet.storage->data();
  }

  VideoPipeline::RenderMetrics metrics{};
  const auto result = videoPipeline_.Render(windowSession_.window, pixels,
                                            packet.width, packet.height,
                                            packet.pitch,
                                            &metrics);
  MergeRenderMetrics(metrics);

  {
    std::lock_guard<std::mutex> lock(statsMutex_);
    if (result == VideoPipeline::RenderResult::DROPPED) {
      stats_.droppedFrames++;
    } else {
      stats_.renderedFrames++;
    }
  }

  if (nativeVsyncActive_.load(std::memory_order_acquire)) {
    RequestNextVSync();
  }
}

void RenderThread::HandleRuntimeChanged(const HwRenderRuntimeInfo &runtime) {
  hwRuntime_ = runtime;
  if (windowSession_.window && windowSession_.active &&
      envState_.IsHwRenderEnabled()) {
    videoPipeline_.OnHardwareGeometryChanged(envState_, runtime);
  }
}

bool RenderThread::HasPendingLifecycleControl() const {
  std::lock_guard<std::mutex> lock(controlMutex_);
  for (const auto &message : controlQueue_) {
    if (message.type != ControlType::TICK &&
        message.type != ControlType::STOP) {
      return true;
    }
  }
  return false;
}

void RenderThread::StartVSyncIfNeeded() {
  if (!nativeVsyncEnabled_.load(std::memory_order_acquire)) {
    nativeVsyncActive_.store(false, std::memory_order_release);
    return;
  }

  const bool started = nativeVsyncDriver_.Start(
      "libretro_render",
      [this](long long timestamp) {
        {
          std::lock_guard<std::mutex> lock(statsMutex_);
          stats_.vsyncCallbacks++;
        }
        ControlMessage message;
        message.type = ControlType::TICK;
        message.timestampUs = timestamp;
        PushControl(std::move(message));
      });
  nativeVsyncActive_.store(started, std::memory_order_release);
}

void RenderThread::StopVSync() {
  nativeVsyncDriver_.Stop();
  nativeVsyncActive_.store(false, std::memory_order_release);
}

void RenderThread::RequestNextVSync() {
  if (!nativeVsyncActive_.load(std::memory_order_acquire)) {
    return;
  }
  if (!nativeVsyncDriver_.RequestNextFrame()) {
    {
      std::lock_guard<std::mutex> lock(statsMutex_);
      stats_.vsyncRequestFailures++;
    }
    // Driver request failure: degrade to timer fallback and wake main loop.
    nativeVsyncDriver_.Stop();
    nativeVsyncActive_.store(false, std::memory_order_release);
    controlCond_.notify_one();
  }
}

void RenderThread::PublishWindowSessionSnapshot() {
  windowSessionIdSnapshot_.store(windowSession_.sessionId,
                                 std::memory_order_release);
  windowGenerationSnapshot_.store(windowSession_.generation,
                                  std::memory_order_release);
  windowStateSnapshot_.store(static_cast<int>(windowSession_.state),
                             std::memory_order_release);
  windowWidthSnapshot_.store(windowSession_.width, std::memory_order_release);
  windowHeightSnapshot_.store(windowSession_.height, std::memory_order_release);
  windowActiveSnapshot_.store(windowSession_.active,
                              std::memory_order_release);
  windowHasHandleSnapshot_.store(windowSession_.window != nullptr,
                                 std::memory_order_release);
}

void RenderThread::MergeRenderMetrics(const VideoPipeline::RenderMetrics &metrics) {
  std::lock_guard<std::mutex> lock(statsMutex_);
  stats_.nwRequestBufferCalls += metrics.nwRequestBufferCalls;
  stats_.nwRequestBufferFailures += metrics.nwRequestBufferFailures;
  stats_.nwFlushBufferCalls += metrics.nwFlushBufferCalls;
  stats_.nwFlushBufferFailures += metrics.nwFlushBufferFailures;
  stats_.nwAbortBufferCalls += metrics.nwAbortBufferCalls;
  stats_.nbFromWindowBufferFailures += metrics.nbFromWindowBufferFailures;
  stats_.nbMapFailures += metrics.nbMapFailures;
  stats_.nbUnmapFailures += metrics.nbUnmapFailures;
  stats_.fenceWaitCalls += metrics.fenceWaitCalls;
  stats_.fenceWaitFailures += metrics.fenceWaitFailures;
  stats_.fenceTimeoutCount += metrics.fenceTimeoutCount;

  if (metrics.frameTimeUs > 0) {
    if (metrics.frameTimeUs < stats_.frameTimeMin) {
      stats_.frameTimeMin = metrics.frameTimeUs;
    }
    if (metrics.frameTimeUs > stats_.frameTimeMax) {
      stats_.frameTimeMax = metrics.frameTimeUs;
    }
    stats_.frameTimeSum += metrics.frameTimeUs;
    stats_.frameTimeCount++;
  }
}

} // namespace libretro
