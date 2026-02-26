#include "render_thread.h"

#include "core/libretro/env_dispatcher.h"
#include <algorithm>
#include <chrono>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
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
    : videoPipeline_(pipeline), envState_(envState) {}

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

void RenderThread::SetWindow(OHNativeWindow *window, bool forceRebind) {
  ControlMessage message;
  message.type = ControlType::SET_WINDOW;
  message.window = window;
  message.forceRebind = forceRebind;
  if (message.window) {
    OH_NativeWindow_NativeObjectReference(message.window);
  }
  PushControl(std::move(message));
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

void RenderThread::ThreadMain() {
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
  HandleSetWindow(nullptr, false);
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
    HandleSetWindow(message.window, message.forceRebind);
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

void RenderThread::HandleSetWindow(OHNativeWindow *window, bool forceRebind) {
  if (window_ == window && !forceRebind) {
    if (window) {
      OH_NativeWindow_NativeObjectUnreference(window);
    }
    return;
  }

  // Drop queued frames on window lifecycle mutation to avoid stale surface use.
  frameQueue_.Clear();

  if (forceRebind && window_ == window && window_) {
    const bool softwareOnly =
        !envState_.IsHwRenderEnabled() && !videoPipeline_.HasHardwareContext();
    if (softwareOnly) {
      // Software path does not need destructive teardown for same window.
      // Re-apply configuration only.
      videoPipeline_.ForceReconfiguration();
      OH_NativeWindow_NativeObjectUnreference(window);
      return;
    }
    LOGF(LOG_INFO, "RenderThread: force window rebind %{public}p", window);
  }

  if (window_) {
    if (envState_.IsHwRenderEnabled() || videoPipeline_.HasHardwareContext()) {
      videoPipeline_.OnHardwareWindowDestroyed(envState_);
    }
    VideoPipeline::ResetNativeWindow(window_);
    OH_NativeWindow_NativeObjectUnreference(window_);
    window_ = nullptr;
    videoPipeline_.Reset();
  }

  window_ = window;
  if (!window_) {
    return;
  }

  videoPipeline_.ForceReconfiguration();

  if (envState_.IsHwRenderEnabled()) {
    videoPipeline_.InitializeHardwareRenderer(window_, envState_, hwRuntime_);
  }
}

void RenderThread::HandleResize(int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  videoPipeline_.SetWindowSize(width, height);
  if (window_ && envState_.IsHwRenderEnabled()) {
    videoPipeline_.OnHardwareWindowResized(window_, width, height, envState_);
  }
}

void RenderThread::HandleTick() {
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

  if (!window_) {
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
  const auto result = videoPipeline_.Render(window_, pixels, packet.width,
                                            packet.height, packet.pitch,
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
  if (window_ && envState_.IsHwRenderEnabled()) {
    videoPipeline_.OnHardwareGeometryChanged(envState_, runtime);
  }
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
