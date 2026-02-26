#ifndef LIBRETRO_ENGINE_RENDER_THREAD_H
#define LIBRETRO_ENGINE_RENDER_THREAD_H

#include "bounded_latest_frame_queue.h"
#include "video_pipeline.h"
#include "window_session.h"
#include "platform/sync/native_vsync_driver.h"
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <thread>

namespace libretro {

class EnvState;

struct RenderThreadStats {
  uint64_t renderedFrames = 0;
  uint64_t droppedFrames = 0;
  uint64_t renderTickNoFrame = 0;
  uint64_t vsyncCallbacks = 0;
  uint64_t vsyncFallbackTicks = 0;
  uint64_t vsyncRequestFailures = 0;

  uint64_t nwRequestBufferCalls = 0;
  uint64_t nwRequestBufferFailures = 0;
  uint64_t nwFlushBufferCalls = 0;
  uint64_t nwFlushBufferFailures = 0;
  uint64_t nwAbortBufferCalls = 0;
  uint64_t nbFromWindowBufferFailures = 0;
  uint64_t nbMapFailures = 0;
  uint64_t nbUnmapFailures = 0;
  uint64_t fenceWaitCalls = 0;
  uint64_t fenceWaitFailures = 0;
  uint64_t fenceTimeoutCount = 0;

  uint64_t frameTimeMin = UINT64_MAX;
  uint64_t frameTimeMax = 0;
  uint64_t frameTimeSum = 0;
  uint64_t frameTimeCount = 0;

  uint64_t queuePushed = 0;
  uint64_t queuePopped = 0;
  uint64_t queueDroppedOldest = 0;
  uint64_t queueDroppedStaleOnPop = 0;
  uint64_t queueDepthMax = 0;
};

struct WindowSessionSnapshot {
  uint64_t sessionId = 0;
  uint64_t generation = 0;
  WindowSessionState state = WindowSessionState::DETACHED;
  int width = 0;
  int height = 0;
  bool active = false;
  bool hasWindow = false;
};

class RenderThread {
public:
  RenderThread(VideoPipeline &pipeline, EnvState &envState);
  ~RenderThread();

  RenderThread(const RenderThread &) = delete;
  RenderThread &operator=(const RenderThread &) = delete;

  void SetEnabled(bool enabled);
  bool IsEnabled() const { return enabled_.load(std::memory_order_acquire); }

  void SetNativeVSyncEnabled(bool enabled);
  bool IsNativeVSyncEnabled() const {
    return nativeVsyncEnabled_.load(std::memory_order_acquire);
  }

  bool Start();
  void Stop();

  void SetWindow(OHNativeWindow *window, uint64_t generation = 0);
  void InvalidateFrameQueueForGeneration(uint64_t generation);
  void SetWindowSize(int width, int height);
  void SetHwRenderRuntimeInfo(const HwRenderRuntimeInfo &runtime);

  bool EnqueueFrame(VideoFramePacket &&packet);

  RenderThreadStats GetStats() const;
  void ResetStats();
  WindowSessionSnapshot GetWindowSessionSnapshot() const;

private:
  enum class ControlType : uint8_t {
    SET_WINDOW = 0,
    RESIZE = 1,
    TICK = 2,
    STOP = 3,
    HW_RUNTIME = 4,
  };

  struct ControlMessage {
    ControlType type = ControlType::TICK;
    OHNativeWindow *window = nullptr;
    uint64_t generation = 0;
    int width = 0;
    int height = 0;
    int64_t timestampUs = 0;
    HwRenderRuntimeInfo runtime{};
  };

  void ThreadMain();
  void PushControl(ControlMessage &&message);
  void HandleControl(const ControlMessage &message);
  void HandleSetWindow(OHNativeWindow *window, uint64_t generation);
  void HandleResize(int width, int height);
  void HandleTick();
  void HandleRuntimeChanged(const HwRenderRuntimeInfo &runtime);
  bool HasPendingLifecycleControl() const;

  void StartVSyncIfNeeded();
  void StopVSync();
  void RequestNextVSync();
  void PublishWindowSessionSnapshot();

  void MergeRenderMetrics(const VideoPipeline::RenderMetrics &metrics);

  VideoPipeline &videoPipeline_;
  EnvState &envState_;

  std::atomic<bool> enabled_{true};
  std::atomic<bool> nativeVsyncEnabled_{true};

  std::atomic<bool> running_{false};
  std::atomic<bool> stopRequested_{false};

  mutable std::mutex controlMutex_;
  std::condition_variable controlCond_;
  std::deque<ControlMessage> controlQueue_;

  std::thread renderThread_;
  WindowSession windowSession_{};
  std::atomic<uint64_t> windowSessionIdSnapshot_{0};
  std::atomic<uint64_t> windowGenerationSnapshot_{0};
  std::atomic<int> windowStateSnapshot_{
      static_cast<int>(WindowSessionState::DETACHED)};
  std::atomic<int> windowWidthSnapshot_{0};
  std::atomic<int> windowHeightSnapshot_{0};
  std::atomic<bool> windowActiveSnapshot_{false};
  std::atomic<bool> windowHasHandleSnapshot_{false};
  std::atomic<uint64_t> staleGenerationDropLogCount_{0};
  HwRenderRuntimeInfo hwRuntime_{};

  NativeVSyncDriver nativeVsyncDriver_;
  std::atomic<bool> nativeVsyncActive_{false};

  BoundedLatestFrameQueue frameQueue_{2};

  mutable std::mutex statsMutex_;
  RenderThreadStats stats_{};
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_RENDER_THREAD_H
