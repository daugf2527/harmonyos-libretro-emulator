#include "video_pipeline.h"
#include "common/fence_utils.h"
#include "core/libretro/env_dispatcher.h"
#include "platform/graphics/graphics_context.h"
#include "platform/graphics/hw_render_presenter.h"
#include "platform/graphics/pixel_converter.h"
#include "platform/graphics/vulkan_context.h"
#include "platform/graphics/vulkan_presenter.h"
#include <algorithm>
#include <cerrno>
#include <cstring>
#include <limits>
#include <hilog/log.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#if defined(__has_include)
#if __has_include(<native_window/graphic_error_code.h>)
#include <native_window/graphic_error_code.h>
#endif
#endif
#include <unistd.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD009
#undef LOG_TAG
#define LOG_TAG "VideoPipeline"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

// Define SET_BUFFER_GEOMETRY if not available in SDK headers
#ifndef SET_BUFFER_GEOMETRY
#define SET_BUFFER_GEOMETRY 0
#endif

#ifndef NATIVE_ERROR_OK
#define NATIVE_ERROR_OK 0
#endif

#ifndef NATIVE_ERROR_NO_BUFFER
#define NATIVE_ERROR_NO_BUFFER 40601000
#endif

#ifndef SET_SWAP_INTERVAL
#define SET_SWAP_INTERVAL 8
#endif

namespace libretro {

VideoPipeline::VideoPipeline() = default;

VideoPipeline::~VideoPipeline() = default;

class SoftwareRenderBackend : public VideoPipeline::IRenderBackend {
public:
  explicit SoftwareRenderBackend(VideoPipeline &pipeline) : pipeline_(pipeline) {}

  const char *GetName() const override { return "SoftwareBackend"; }
  void Reset() override {}

  bool Initialize(OHNativeWindow *, EnvState &,
                  const HwRenderRuntimeInfo *) override {
    return true;
  }
  void Shutdown(EnvState &) override {}

  VideoPipeline::RenderResult RenderFrame(
      OHNativeWindow *window, const void *data, unsigned width, unsigned height,
      size_t pitch, bool isDupeRequest, VideoPipeline::RenderMetrics *metrics,
      const std::chrono::steady_clock::time_point &start) override {
    return pipeline_.RenderCPU(window, data, width, height, pitch, isDupeRequest,
                               metrics, start);
  }

  void SwapBuffers(EnvState &) override {}

  void OnWindowResized(OHNativeWindow *, int, int, EnvState &) override {}
  void OnWindowDestroyed(EnvState &) override {}
  void OnGeometryChanged(EnvState &, const HwRenderRuntimeInfo &) override {}

  bool HandleAcquire(OHNativeWindow *, EnvState &,
                     const std::function<void()> &,
                     const std::function<void()> &) override {
    return false;
  }

  uintptr_t GetFramebuffer() const override { return 0; }
  bool HasContext() const override { return false; }

private:
  VideoPipeline &pipeline_;
};

class GlesRenderBackend : public VideoPipeline::IRenderBackend {
public:
  explicit GlesRenderBackend(VideoPipeline &pipeline) : pipeline_(pipeline) {}

  const char *GetName() const override { return "GlesBackend"; }
  void Reset() override {}

  bool Initialize(OHNativeWindow *, EnvState &,
                  const HwRenderRuntimeInfo *) override {
    return true;
  }
  void Shutdown(EnvState &) override {}

  VideoPipeline::RenderResult RenderFrame(
      OHNativeWindow *window, const void *data, unsigned width, unsigned height,
      size_t pitch, bool isDupeRequest, VideoPipeline::RenderMetrics *metrics,
      const std::chrono::steady_clock::time_point &start) override {
    (void)metrics;
    (void)start;
    return pipeline_.RenderGLES(window, data, width, height, pitch,
                                isDupeRequest);
  }

  void SwapBuffers(EnvState &) override {}

  void OnWindowResized(OHNativeWindow *, int, int, EnvState &) override {}
  void OnWindowDestroyed(EnvState &) override {}
  void OnGeometryChanged(EnvState &, const HwRenderRuntimeInfo &) override {}

  bool HandleAcquire(OHNativeWindow *, EnvState &,
                     const std::function<void()> &,
                     const std::function<void()> &) override {
    return false;
  }

  uintptr_t GetFramebuffer() const override { return 0; }
  bool HasContext() const override { return false; }

private:
  VideoPipeline &pipeline_;
};

class HwRenderBackend : public VideoPipeline::IRenderBackend {
public:
  explicit HwRenderBackend(VideoPipeline &pipeline) : pipeline_(pipeline) {}

  const char *GetName() const override { return "HwRenderBackend"; }
  void Reset() override {}

  bool Initialize(OHNativeWindow *window, EnvState &env_state,
                  const HwRenderRuntimeInfo *runtime) override {
    if (!runtime) {
      return false;
    }
    return pipeline_.InitializeHardwareRendererImpl(window, env_state, *runtime);
  }
  void Shutdown(EnvState &env_state) override {
    pipeline_.DestroyHardwareRendererImpl(env_state);
  }

  VideoPipeline::RenderResult RenderFrame(
      OHNativeWindow *, const void *data, unsigned, unsigned, size_t, bool,
      VideoPipeline::RenderMetrics *,
      const std::chrono::steady_clock::time_point &) override {
    // HW path is driven by SwapBuffers; RenderFrame should be a no-op.
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
      return VideoPipeline::RenderResult::RENDERED;
    }
    if (!data) {
      return VideoPipeline::RenderResult::RENDERED;
    }
    static size_t unexpected_hw_data_count = 0;
    unexpected_hw_data_count++;
    if (unexpected_hw_data_count <= 3 || (unexpected_hw_data_count % 60) == 0) {
      LOGF(LOG_WARN, "HW render received unexpected data pointer");
    }
    return VideoPipeline::RenderResult::DROPPED;
  }

  void SwapBuffers(EnvState &env_state) override {
    pipeline_.SwapHardwareBuffersImpl(env_state);
  }

  void OnWindowResized(OHNativeWindow *window, int width, int height,
                       EnvState &env_state) override {
    pipeline_.OnHardwareWindowResizedImpl(window, width, height, env_state);
  }
  void OnWindowDestroyed(EnvState &env_state) override {
    pipeline_.OnHardwareWindowDestroyedImpl(env_state);
  }
  void OnGeometryChanged(EnvState &env_state,
                         const HwRenderRuntimeInfo &runtime) override {
    pipeline_.OnHardwareGeometryChangedImpl(env_state, runtime);
  }

  bool HandleAcquire(OHNativeWindow *window, EnvState &env_state,
                     const std::function<void()> &on_acquire_begin,
                     const std::function<void()> &on_acquire_end) override {
    return pipeline_.HandleVulkanAcquireImpl(window, env_state, on_acquire_begin,
                                             on_acquire_end);
  }

  uintptr_t GetFramebuffer() const override {
    return pipeline_.GetHwRenderFramebufferImpl();
  }
  bool HasContext() const override {
    return pipeline_.HasHardwareContextImpl();
  }

private:
  VideoPipeline &pipeline_;
};

namespace {
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

bool ShouldLog(uint32_t &counter, uint32_t burst, uint32_t interval) {
  counter++;
  if (counter <= burst) {
    return true;
  }
  if (interval == 0) {
    return false;
  }
  return (counter % interval) == 0;
}

void BuildHwRenderConfig(const retro_hw_render_callback &cb,
                         HwRenderConfig &out) {
  if (cb.context_type == RETRO_HW_CONTEXT_OPENGLES2) {
    out.use_es3 = false;
  } else if (cb.context_type == RETRO_HW_CONTEXT_OPENGLES_VERSION) {
    out.use_es3 = (cb.version_major >= 3);
  } else {
    out.use_es3 = true;
  }
  out.depth = cb.depth;
  out.stencil = cb.stencil;
  out.bottom_left_origin = cb.bottom_left_origin;
}

void ResolveTargetSize(const EnvState &env_state,
                       const HwRenderRuntimeInfo &runtime, unsigned &out_w,
                       unsigned &out_h) {
  out_w = env_state.GetGeometryBaseWidth();
  out_h = env_state.GetGeometryBaseHeight();
  if (out_w == 0 || out_h == 0) {
    out_w = runtime.video_width;
    out_h = runtime.video_height;
  }
  if (out_w == 0 || out_h == 0) {
    out_w = runtime.video_max_width;
    out_h = runtime.video_max_height;
  }
}

} // namespace

const char *VideoPipeline::PreflightDropReasonToString(
    PreflightDropReason reason) {
  switch (reason) {
  case PreflightDropReason::NONE:
    return "none";
  case PreflightDropReason::NULL_WINDOW:
    return "null_window";
  case PreflightDropReason::INVALID_WINDOW_SIZE:
    return "invalid_window_size";
  case PreflightDropReason::INVALID_FRAME:
    return "invalid_frame";
  case PreflightDropReason::CPU_BACKPRESSURE:
    return "cpu_backpressure";
  default:
    return "unknown";
  }
}

VideoPipeline::PreflightDropReason VideoPipeline::EvaluateRenderPreflight(
    OHNativeWindow *window, unsigned width, unsigned height, size_t pitch,
    ScalingMode mode, bool isDupeRequest) const {
  if (!window) {
    return PreflightDropReason::NULL_WINDOW;
  }
  if (window_width_.load(std::memory_order_acquire) <= 0 ||
      window_height_.load(std::memory_order_acquire) <= 0) {
    return PreflightDropReason::INVALID_WINDOW_SIZE;
  }

  const bool cpuMode = (mode != ScalingMode::GLES_SCALING);
  if (cpuMode && !isDupeRequest) {
    if (width == 0 || height == 0 || pitch == 0) {
      return PreflightDropReason::INVALID_FRAME;
    }
    const auto now = std::chrono::steady_clock::now();
    if (cpu_backpressure_until_ != std::chrono::steady_clock::time_point{} &&
        now < cpu_backpressure_until_) {
      return PreflightDropReason::CPU_BACKPRESSURE;
    }
  }

  return PreflightDropReason::NONE;
}

void VideoPipeline::UpdateCpuBackpressure(int64_t requestUs, bool requestFailed) {
  constexpr int64_t kSlowThresholdUs = 50000;
  constexpr int64_t kRecoverThresholdUs = 20000;

  if (requestFailed) {
    cpu_request_slow_streak_ = std::min<uint32_t>(cpu_request_slow_streak_ + 1, 100);
  } else if (requestUs >= kSlowThresholdUs) {
    cpu_request_slow_streak_ = std::min<uint32_t>(cpu_request_slow_streak_ + 1, 100);
  } else if (requestUs <= kRecoverThresholdUs) {
    cpu_request_slow_streak_ = 0;
  } else if (cpu_request_slow_streak_ > 0) {
    cpu_request_slow_streak_--;
  }

  int cooldownMs = 0;
  if (requestFailed) {
    cooldownMs = 200;
  } else if (requestUs >= 90000) {
    cooldownMs = 400;
  } else if (cpu_request_slow_streak_ >= 3) {
    cooldownMs = 250;
  }

  if (cooldownMs <= 0) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  const auto until = now + std::chrono::milliseconds(cooldownMs);
  if (until > cpu_backpressure_until_) {
    cpu_backpressure_until_ = until;
  }
  if (ShouldLog(preflight_drop_log_count_, 5, 60)) {
    LOGF(LOG_WARN,
         "CPU backpressure armed: req=%{public}lld us fail=%{public}d streak=%{public}u cooldown=%{public}d ms",
         static_cast<long long>(requestUs), requestFailed ? 1 : 0,
         cpu_request_slow_streak_, cooldownMs);
  }
}

float VideoPipeline::ResolveSourceAspect(unsigned width, unsigned height) const {
  float srcAspect = geometry_aspect_ratio_;
  if (!(srcAspect > 0.0f) && geometry_base_width_ > 0 &&
      geometry_base_height_ > 0) {
    srcAspect = static_cast<float>(geometry_base_width_) /
                static_cast<float>(geometry_base_height_);
  }
  if (!(srcAspect > 0.0f) && width > 0 && height > 0) {
    srcAspect = static_cast<float>(width) / static_cast<float>(height);
  }
  if (!(srcAspect > 0.0f)) {
    srcAspect = 1.0f;
  }
  return srcAspect;
}

void VideoPipeline::EnsureCpuLayout(unsigned width, unsigned height, int dstWidth,
                                    int dstHeight) {
  if (dstWidth <= 0 || dstHeight <= 0) {
    cpu_layout_cache_ = CpuLayoutCache{};
    return;
  }

  const float srcAspect = ResolveSourceAspect(width, height);
  float aspectDelta = srcAspect - cpu_layout_cache_.src_aspect;
  if (aspectDelta < 0.0f) {
    aspectDelta = -aspectDelta;
  }

  const bool needRecalc =
      !cpu_layout_cache_.valid || cpu_layout_cache_.src_width != width ||
      cpu_layout_cache_.src_height != height ||
      cpu_layout_cache_.dst_width != dstWidth ||
      cpu_layout_cache_.dst_height != dstHeight || aspectDelta > 0.0001f;
  if (!needRecalc) {
    return;
  }

  const float dstAspect = static_cast<float>(dstWidth) /
                          static_cast<float>(dstHeight);
  int scaledWidth = dstWidth;
  int scaledHeight = dstHeight;
  if (dstAspect > srcAspect) {
    scaledWidth = static_cast<int>(static_cast<float>(dstHeight) * srcAspect);
    scaledHeight = dstHeight;
  } else if (dstAspect < srcAspect) {
    scaledWidth = dstWidth;
    scaledHeight = static_cast<int>(static_cast<float>(dstWidth) / srcAspect);
  }

  if (scaledWidth < 1) {
    scaledWidth = 1;
  }
  if (scaledHeight < 1) {
    scaledHeight = 1;
  }

  const int offsetX = (dstWidth - scaledWidth) / 2;
  const int offsetY = (dstHeight - scaledHeight) / 2;
  const bool hasBlackBars =
      !(offsetX == 0 && offsetY == 0 && scaledWidth == dstWidth &&
        scaledHeight == dstHeight);

  cpu_layout_cache_.valid = true;
  cpu_layout_cache_.src_width = width;
  cpu_layout_cache_.src_height = height;
  cpu_layout_cache_.dst_width = dstWidth;
  cpu_layout_cache_.dst_height = dstHeight;
  cpu_layout_cache_.src_aspect = srcAspect;
  cpu_layout_cache_.scaled_width = scaledWidth;
  cpu_layout_cache_.scaled_height = scaledHeight;
  cpu_layout_cache_.offset_x = offsetX;
  cpu_layout_cache_.offset_y = offsetY;
  cpu_layout_cache_.has_black_bars = hasBlackBars;

  if (ShouldLog(cpu_layout_recalc_log_count_, 5, 120)) {
    LOGF(LOG_INFO,
         "CPU layout recalculated: src=%{public}ux%{public}u dst=%{public}dx%{public}d "
         "scaled=%{public}dx%{public}d off=%{public}d,%{public}d bars=%{public}d",
         width, height, dstWidth, dstHeight, scaledWidth, scaledHeight,
         offsetX, offsetY, hasBlackBars ? 1 : 0);
  }
}

void VideoPipeline::MarkHardwarePathFailure(const char *reason) {
  if (scaling_mode_.load(std::memory_order_acquire) !=
      ScalingMode::HARDWARE_SCALING) {
    return;
  }

  hw_failure_streak_ = std::min<uint32_t>(hw_failure_streak_ + 1, 100);
  if (ShouldLog(hw_failure_log_count_, 5, 60)) {
    LOGF(LOG_WARN,
         "HW path failure: reason=%{public}s streak=%{public}u",
         reason ? reason : "unknown", hw_failure_streak_);
  }

  if (hw_failure_streak_ >= 3) {
    EnterDegradedMode(ScalingMode::HARDWARE_SCALING,
                      reason ? reason : "hw_path_failed");
    hw_failure_streak_ = 0;
  }
}

void VideoPipeline::MarkHardwarePathRecovered(const char *reason) {
  if (scaling_mode_.load(std::memory_order_acquire) !=
      ScalingMode::HARDWARE_SCALING) {
    return;
  }
  if (hw_failure_streak_ > 0 && ShouldLog(hw_failure_log_count_, 5, 60)) {
    LOGF(LOG_INFO, "HW path recovered: reason=%{public}s",
         reason ? reason : "unknown");
  }
  hw_failure_streak_ = 0;
  SetRenderModeState(RenderModeState::HW_READY);
}

const char *VideoPipeline::RenderModeStateToString(RenderModeState state) {
  switch (state) {
  case RenderModeState::SW_READY:
    return "sw_ready";
  case RenderModeState::GLES_READY:
    return "gles_ready";
  case RenderModeState::HW_READY:
    return "hw_ready";
  case RenderModeState::DEGRADED_TO_SW:
    return "degraded_to_sw";
  case RenderModeState::RECOVERING:
    return "recovering";
  default:
    return "unknown";
  }
}

void VideoPipeline::SetRenderModeState(RenderModeState state) {
  const int next = static_cast<int>(state);
  const int prev = render_mode_state_.exchange(next, std::memory_order_acq_rel);
  if (prev == next) {
    return;
  }

  degrade_state_log_count_++;
  if (degrade_state_log_count_ <= 5 || (degrade_state_log_count_ % 60) == 0) {
    LOGF(LOG_INFO, "RenderModeState: %{public}s -> %{public}s",
         RenderModeStateToString(static_cast<RenderModeState>(prev)),
         RenderModeStateToString(state));
  }
}

void VideoPipeline::EnterDegradedMode(ScalingMode sourceMode,
                                      const char *reason) {
#if defined(__i386__) || defined(__x86_64__)
  // Windows 模拟器强制 GLES-only：禁止自动降级到软件路径。
  if (sourceMode != ScalingMode::SOFTWARE_SCALING) {
    if (ShouldLog(render_log_count_, 5, 60)) {
      LOGF(LOG_WARN,
           "Skip software degrade on x86: reason=%{public}s source=%{public}d",
           reason ? reason : "unknown", static_cast<int>(sourceMode));
    }
    return;
  }
#endif
  if (sourceMode == ScalingMode::SOFTWARE_SCALING) {
    return;
  }

  degraded_from_mode_ = sourceMode;
  if (scaling_mode_.load(std::memory_order_acquire) == sourceMode) {
    scaling_mode_.store(ScalingMode::SOFTWARE_SCALING, std::memory_order_release);
    geometry_changed_.store(true, std::memory_order_release);
  }

  degrade_recover_failures_ =
      std::min<uint32_t>(degrade_recover_failures_ + 1, 100);
  if (degrade_recover_failures_ >= 3) {
    // Too many failed recoveries: keep software mode until next explicit switch.
    degraded_from_mode_ = ScalingMode::SOFTWARE_SCALING;
  }

  const uint32_t level = std::min<uint32_t>(degrade_recover_failures_, 5);
  const int cooldownMs = 3000 + static_cast<int>((level - 1) * 1000);
  degrade_recover_after_ =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(cooldownMs);
  SetRenderModeState(RenderModeState::DEGRADED_TO_SW);

  if (ShouldLog(render_log_count_, 5, 60)) {
    LOGF(LOG_WARN,
         "Render degraded to software: reason=%{public}s source=%{public}d "
         "failures=%{public}u recover_after_ms=%{public}d",
         reason ? reason : "unknown", static_cast<int>(sourceMode),
         degrade_recover_failures_, cooldownMs);
  }
}

void VideoPipeline::MaybeRecoverDegradedMode(
    ScalingMode &mode, const std::chrono::steady_clock::time_point &now) {
  if (GetRenderModeState() != RenderModeState::DEGRADED_TO_SW) {
    return;
  }
  if (mode != ScalingMode::SOFTWARE_SCALING) {
    return;
  }
  if (degraded_from_mode_ == ScalingMode::SOFTWARE_SCALING) {
    return;
  }
  if (now < degrade_recover_after_) {
    return;
  }
  if (degrade_recover_attempts_ >= 5) {
    return;
  }

  degrade_recover_attempts_++;
  mode = degraded_from_mode_;
  scaling_mode_.store(mode, std::memory_order_release);
  geometry_changed_.store(true, std::memory_order_release);
  if (mode == ScalingMode::GLES_SCALING) {
    gles_state_ = GlesState::UNINITIALIZED;
    gles_next_retry_time_ = std::chrono::steady_clock::time_point{};
  }
  SetRenderModeState(RenderModeState::RECOVERING);
  if (ShouldLog(render_log_count_, 5, 60)) {
    LOGF(LOG_INFO,
         "Render recovery attempt: target_mode=%{public}d attempt=%{public}u",
         static_cast<int>(mode), degrade_recover_attempts_);
  }
}

void VideoPipeline::EnsureBackends() {
  if (!software_backend_) {
    software_backend_ = std::make_unique<SoftwareRenderBackend>(*this);
  }
  if (!gles_backend_) {
    gles_backend_ = std::make_unique<GlesRenderBackend>(*this);
  }
  if (!hw_backend_) {
    hw_backend_ = std::make_unique<HwRenderBackend>(*this);
  }
}

void VideoPipeline::UpdateVulkanPresenterContent(
    EnvState &env_state, const HwRenderRuntimeInfo *runtime) {
  if (!vulkan_presenter_) {
    return;
  }
  unsigned content_w = env_state.GetGeometryBaseWidth();
  unsigned content_h = env_state.GetGeometryBaseHeight();
  if ((content_w == 0 || content_h == 0) && runtime) {
    content_w = runtime->video_width;
    content_h = runtime->video_height;
  }
  if ((content_w == 0 || content_h == 0) && runtime) {
    content_w = runtime->video_max_width;
    content_h = runtime->video_max_height;
  }
  if (content_w > 0 && content_h > 0) {
    vulkan_presenter_->SetContentSize(content_w, content_h);
  }
}

bool VideoPipeline::SyncVulkanSwapchainState(EnvState &env_state) {
  if (!vulkan_context_ || !vulkan_context_->IsReady() || !vulkan_presenter_) {
    return false;
  }
  vulkan_presenter_->SetSwapchain(vulkan_context_->GetSwapchain());
  vulkan_presenter_->SetSwapchainImages(vulkan_context_->GetSwapchainImages());
  vulkan_presenter_->SetSwapchainExtent(vulkan_context_->GetSwapchainExtent());
  vulkan_presenter_->SetSwapchainUsage(vulkan_context_->GetSwapchainImageUsage());
  const size_t image_count = vulkan_context_->GetSwapchainImages().size();
  if (image_count == 0) {
    return false;
  }
  uint32_t mask = 1;
  if (image_count >= 32) {
    mask = 0xFFFFFFFFu;
  } else {
    mask = static_cast<uint32_t>((1u << image_count) - 1u);
  }
  vulkan_presenter_->SetSyncIndexMask(mask);
  vulkan_presenter_->SetSyncIndex(0);
  vk_sync_index_ = 0;
  env_state.SetVulkanInterface(&vulkan_presenter_->GetInterface());
  return true;
}

bool VideoPipeline::RecreateVulkanSwapchain(OHNativeWindow *window, int width,
                                            int height, EnvState &env_state,
                                            bool force) {
  if (!vulkan_context_ || !vulkan_context_->IsReady()) {
    return false;
  }
  const auto now = std::chrono::steady_clock::now();
  if (!force && last_vk_swapchain_recreate_time_ !=
                    std::chrono::steady_clock::time_point{}) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_vk_swapchain_recreate_time_);
    if (elapsed.count() < 200) {
      return false;
    }
  }
  if (!vulkan_context_->RecreateSwapchain(window, width, height)) {
    return false;
  }
  last_vk_swapchain_recreate_time_ = now;
  return SyncVulkanSwapchainState(env_state);
}

void VideoPipeline::ResetNativeWindow(OHNativeWindow *window) {
  if (!window) {
    return;
  }
  // Use 1x1 size to release memory pressure
  OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, 1, 1);
  // Reset usage to CPU write (safest default)
  OH_NativeWindow_NativeWindowHandleOpt(window, SET_USAGE,
                                        NATIVEBUFFER_USAGE_CPU_WRITE);
  // Reset scaling mode
  OH_NativeWindow_NativeWindowSetScalingModeV2(
      window, OH_SCALING_MODE_SCALE_TO_WINDOW_V2);
  LOGF(LOG_INFO,
       "VideoPipeline: NativeWindow reset to safe state (1x1, CPU_WRITE)");
}

void VideoPipeline::EnsureWindowConfiguredIfNeeded(OHNativeWindow *window,
                                                   unsigned width,
                                                   unsigned height) {
  const bool needConfigUpdate =
      (base_width_ != width || base_height_ != height ||
       geometry_changed_.exchange(false));
  if (!needConfigUpdate) {
    return;
  }

  // Calculate target config first
  unsigned requestWidth = width;
  unsigned requestHeight = height;
  bool isCpuWrite = true;

  ScalingMode mode = scaling_mode_.load();

  const int winW = window_width_.load();
  const int winH = window_height_.load();
  const unsigned swMaxW = software_max_width_.load();
  const unsigned swMaxH = software_max_height_.load();

  if (mode == ScalingMode::GLES_SCALING) {
    if (winW > 0 && winH > 0) {
      requestWidth = static_cast<unsigned>(winW);
      requestHeight = static_cast<unsigned>(winH);
    } else {
      requestWidth = 1280;
      requestHeight = 720;
    }
    isCpuWrite = false;
  } else if (mode == ScalingMode::SOFTWARE_SCALING) {
    float scaleX = (float)swMaxW / width;
    float scaleY = (float)swMaxH / height;
    float scale = std::min(scaleX, scaleY);
    if (scale < 1.0f)
      scale = 1.0f;
    requestWidth = static_cast<unsigned>(width * scale);
    requestHeight = static_cast<unsigned>(height * scale);
    requestWidth &= ~1;
    requestHeight &= ~1;
  }

  const bool requestChanged =
      (requestWidth != last_request_width_ ||
       requestHeight != last_request_height_ || mode != last_request_mode_);

  // [Fix] Smart Retry: If config changed, reset retry count immediately
  if (requestChanged && retry_count_ > 0) {
    LOGF(LOG_INFO, "VideoPipeline: Config changed, resetting retry count");
    retry_count_ = 0;
  }

  // Anti-loop protection: if we failed too many times recently, back off
  auto now = std::chrono::steady_clock::now();
  if (!requestChanged && retry_count_ > 10) {
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - last_retry_time_)
                        .count();
    // Use a much shorter cooldown (200ms) for stability without blocking rotation
    if (duration < 200) {
      // Cooldown active, ignore this update request and put the flag back
      geometry_changed_.store(true);
      
      // Log throttle for cooldown message (every 1s)
      static std::chrono::steady_clock::time_point last_cooldown_log = {};
      auto log_elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                             now - last_cooldown_log).count();
      
      if (log_elapsed > 1000) { 
        LOGF(LOG_WARN, "VideoPipeline: Config retry cooldown active (count=%u)",
             retry_count_);
        last_cooldown_log = now;
      }
      return;
    }
    // Cooldown 结束后重置重试计数，重新尝试配置。
    retry_count_ = 0;
    LOGF(LOG_INFO, "VideoPipeline: Config retry cooldown ended");
  }

  const bool missingWindowSize = (winW <= 0 || winH <= 0);
  const auto nowLog = std::chrono::steady_clock::now();
  bool shouldLog = false;
  if (config_log_count_ < 5) {
    shouldLog = true;
  } else if (requestChanged || missingWindowSize) {
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                       nowLog - last_config_log_time_)
                       .count();
    if (elapsed >= 2000) {
      shouldLog = true;
    }
  }
  if (shouldLog) {
    config_log_count_++;
    last_config_log_time_ = nowLog;
    LOGF(LOG_INFO,
         "Config Update: Mode=%{public}d, Src=%{public}ux%{public}u -> "
         "Req=%{public}ux%{public}u, Win=%{public}dx%{public}d",
         static_cast<int>(mode), width, height, requestWidth, requestHeight,
         winW, winH);
  }

  base_width_ = width;
  base_height_ = height;

  bool geometryOk = true;
  {
    static uint32_t optFailLogCount = 0;

    auto LogOptFail = [&](const char *name, int32_t code, int32_t err) {
      optFailLogCount++;
      // If we are in a retry loop (retry_count_ > 0), force log more frequently (e.g. every 5 secs)
      // or if it's the *first* failure after a success.
      // Current logic: first 5 logs, then every 60th log.
      // We want to ensure that if retry_count_ is high, we definitely see this log.
      bool forceLog = (retry_count_ > 10 && (optFailLogCount % 10) == 0); 

      if (optFailLogCount <= 5 || (optFailLogCount % 60) == 0 || forceLog) {
        LOGF(LOG_WARN, "%{public}s failed: code=%{public}d err=%{public}d (retry=%{public}u)",
             name, code, err, retry_count_);
      }
    };

    WindowStateManager::WindowState state{};
    state.width = requestWidth;
    state.height = requestHeight;
    if (mode == ScalingMode::GLES_SCALING) {
#if defined(NATIVEBUFFER_USAGE_HW_RENDER)
      state.usage =
          NATIVEBUFFER_USAGE_HW_RENDER | NATIVEBUFFER_USAGE_HW_TEXTURE;
#else
      state.usage = NATIVEBUFFER_USAGE_HW_TEXTURE;
#endif
    } else if (isCpuWrite) {
      // 软件渲染路径仅保留最小必要配置，降低 producer 状态异常风险。
      state.usage = NATIVEBUFFER_USAGE_CPU_WRITE;
    }

    const auto result = window_state_manager_.Apply(window, state, LogOptFail);
    geometryOk = result.geometry_ok;
    if (!geometryOk) {
      geometry_changed_.store(true);
      retry_count_++;
      last_retry_time_ = now;
    } else {
      retry_count_ = 0;
    }
    if (!result.usage_ok || !result.swap_ok || !result.source_ok ||
        !result.scaling_ok) {
      // Do not force per-frame reconfiguration on optional opt failures.
      // Continuous HandleOpt retries can destabilize producer/consumer state.
      static uint32_t optPartialFailLogCount = 0;
      optPartialFailLogCount++;
      if (optPartialFailLogCount <= 5 || (optPartialFailLogCount % 120) == 0) {
        LOGF(LOG_WARN,
             "Window opts partial failure: usage=%{public}d swap=%{public}d "
             "source=%{public}d scaling=%{public}d (geometry_ok=%{public}d)",
             result.usage_ok ? 1 : 0, result.swap_ok ? 1 : 0,
             result.source_ok ? 1 : 0, result.scaling_ok ? 1 : 0,
             geometryOk ? 1 : 0);
      }
    }
  }

  if (mode == ScalingMode::GLES_SCALING && gles_state_ == GlesState::READY &&
      requestChanged && geometryOk) {
    gles_renderer_.Resize(static_cast<int>(requestWidth),
                          static_cast<int>(requestHeight));
  }

  if (geometryOk) {
    last_request_width_ = requestWidth;
    last_request_height_ = requestHeight;
  }
  last_request_mode_ = mode;
}

VideoPipeline::RenderResult
VideoPipeline::RenderGLES(OHNativeWindow *window, const void *data,
                          unsigned width, unsigned height, size_t pitch,
                          bool isDupeRequest) {
  const auto now = std::chrono::steady_clock::now();
  auto scheduleRetry = [this, &now](size_t failures) {
    int delayMs = 100;
    if (failures > 3) {
      delayMs = 1000;
    } else if (failures > 1) {
      delayMs = 300;
    }
    gles_next_retry_time_ = now + std::chrono::milliseconds(delayMs);
  };
  auto enterReady = [this]() {
    gles_state_ = GlesState::READY;
    gles_swap_fail_count_ = 0;
    gles_surface_recreate_failures_ = 0;
    gles_full_reinit_failures_ = 0;
    last_gles_init_fail_time_ = std::chrono::steady_clock::time_point{};
    gles_next_retry_time_ = std::chrono::steady_clock::time_point{};
    gles_renderer_.SetXEngineEnabled(xengine_enabled_.load());
    xengine_dirty_.store(false);
    degrade_recover_failures_ = 0;
    degrade_recover_attempts_ = 0;
    SetRenderModeState(RenderModeState::GLES_READY);
  };

  if (!window) {
    if (gles_state_ != GlesState::WAIT_WINDOW) {
      gles_state_ = GlesState::WAIT_WINDOW;
      if (ShouldLog(render_log_count_, 3, 60)) {
        LOGF(LOG_WARN, "GLES entering WAIT_WINDOW (null window)");
      }
    }
    drop_count_++;
    return RenderResult::DROPPED;
  }
  if (gles_state_ == GlesState::WAIT_WINDOW) {
    gles_state_ = GlesState::UNINITIALIZED;
    gles_next_retry_time_ = std::chrono::steady_clock::time_point{};
  }

  if (gles_next_retry_time_.time_since_epoch().count() > 0 &&
      now < gles_next_retry_time_) {
    drop_count_++;
    return RenderResult::DROPPED;
  }

  if (gles_state_ == GlesState::SURFACE_LOST) {
    gles_surface_recreate_attempts_++;
    if (gles_renderer_.RecreateSurface(window)) {
      if (ShouldLog(render_log_count_, 3, 60)) {
        LOGF(LOG_INFO, "GLES surface recreate recovered: attempts=%{public}zu",
             gles_surface_recreate_attempts_);
      }
      enterReady();
    } else {
      gles_swap_fail_count_++;
      gles_surface_recreate_failures_++;
      scheduleRetry(gles_surface_recreate_failures_);
      if (gles_surface_recreate_failures_ >= 3) {
        gles_state_ = GlesState::UNINITIALIZED;
        if (ShouldLog(render_log_count_, 3, 30)) {
          LOGF(LOG_WARN,
               "GLES surface recreate escalate to full reinit: fail=%{public}zu",
               gles_surface_recreate_failures_);
        }
      } else if (ShouldLog(render_log_count_, 3, 60)) {
        LOGF(LOG_WARN, "GLES surface recreate failed: fail=%{public}zu",
             gles_surface_recreate_failures_);
      }
      drop_count_++;
      return RenderResult::DROPPED;
    }
  }

  if (gles_state_ == GlesState::CONTEXT_LOST ||
      gles_state_ == GlesState::UNINITIALIZED) {
    gles_full_reinit_attempts_++;
    gles_renderer_.Deinit();
    if (gles_renderer_.Init(window)) {
      if (ShouldLog(render_log_count_, 3, 30)) {
        LOGF(LOG_INFO,
             "GLES full reinit recovered: attempts=%{public}zu fail=%{public}zu",
             gles_full_reinit_attempts_, gles_full_reinit_failures_);
      }
      enterReady();
    } else {
      gles_full_reinit_failures_++;
      gles_swap_fail_count_++;
      last_gles_init_fail_time_ = now;
      gles_state_ = GlesState::UNINITIALIZED;
      scheduleRetry(gles_full_reinit_failures_);
      if (gles_full_reinit_failures_ >= 5) {
        gles_auto_degrade_count_++;
        EnterDegradedMode(ScalingMode::GLES_SCALING, "gles_full_reinit_failed");
        gles_state_ = GlesState::FATAL;
      }
      if (ShouldLog(render_log_count_, 3, 30)) {
        LOGF(LOG_ERROR, "GLES full reinit failed: fail=%{public}zu",
             gles_full_reinit_failures_);
      }
      drop_count_++;
      return RenderResult::DROPPED;
    }
  }

  if (gles_state_ == GlesState::FATAL) {
    if (ShouldLog(render_log_count_, 3, 120)) {
      LOGF(LOG_WARN, "GLES in FATAL state, dropping frame");
    }
    drop_count_++;
    return RenderResult::DROPPED;
  }

  if (xengine_dirty_.exchange(false)) {
    gles_renderer_.SetXEngineEnabled(xengine_enabled_.load());
  }

  if (gles_state_ != GlesState::READY) {
    drop_count_++;
    return RenderResult::DROPPED;
  }

  float aspect = geometry_aspect_ratio_;
  if (!(aspect > 0.0f) && geometry_base_width_ > 0 &&
      geometry_base_height_ > 0) {
    aspect = static_cast<float>(geometry_base_width_) /
             static_cast<float>(geometry_base_height_);
  }

  gles_renderer_.Render(data, width, height, pitch, pixel_format_, aspect,
                        isDupeRequest);

  if (!gles_renderer_.IsHealthy()) {
    gles_swap_fail_count_++;
    const auto kind = gles_renderer_.GetLastSwapFailureKind();
    const EGLint err = gles_renderer_.GetLastEglError();
    if (kind == GLESRenderer::SwapFailureKind::CONTEXT_LOST) {
      gles_state_ = GlesState::CONTEXT_LOST;
    } else {
      gles_state_ = GlesState::SURFACE_LOST;
    }
    scheduleRetry(gles_swap_fail_count_);
    if (ShouldLog(render_log_count_, 3, 60)) {
      LOGF(LOG_WARN,
           "GLES unhealthy: kind=%{public}d err=0x%{public}X fail=%{public}u",
           static_cast<int>(kind), static_cast<unsigned>(err),
           gles_swap_fail_count_);
    }
    drop_count_++;
    return RenderResult::DROPPED;
  }

  frame_count_++;
  SetRenderModeState(RenderModeState::GLES_READY);
  return isDupeRequest ? RenderResult::DUPED : RenderResult::RENDERED;
}

VideoPipeline::RenderResult
VideoPipeline::RenderCPU(OHNativeWindow *window, const void *data,
                         unsigned width, unsigned height, size_t pitch,
                         bool isDupeRequest, RenderMetrics *m,
                         const std::chrono::steady_clock::time_point &start) {
  if (!window) {
    return RenderResult::DROPPED;
  }
  OH_NativeWindow_NativeObjectReference(window);
  struct WindowRefGuard {
    OHNativeWindow *window = nullptr;
    ~WindowRefGuard() {
      if (window) {
        OH_NativeWindow_NativeObjectUnreference(window);
      }
    }
  } windowGuard{window};

  // 2. CPU 渲染路径 (Hardware/Software Scaling)
  auto t_start = std::chrono::steady_clock::now();
  OHNativeWindowBuffer *buffer = nullptr;
  int fenceFd = -1;
  m->nwRequestBufferCalls++;
  int32_t ret =
      OH_NativeWindow_NativeWindowRequestBuffer(window, &buffer, &fenceFd);
  
  auto t_req = std::chrono::steady_clock::now();
  const int64_t requestUs = std::chrono::duration_cast<std::chrono::microseconds>(
                                t_req - t_start)
                                .count();

  if (ret != 0 || !buffer) {
    UpdateCpuBackpressure(requestUs, true);
    m->nwRequestBufferFailures++;
    drop_count_++;
    if (drop_count_ % 60 == 0 || drop_count_ < 5) {
      LOGF(LOG_WARN, "Frame dropped (RequestBuffer): ret=%{public}d", ret);
    }
    if (fenceFd >= 0) {
      common::WaitAndCloseFence(fenceFd, 0);
      fenceFd = -1;
    }
    if (buffer) {
      m->nwAbortBufferCalls++;
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    }
    // Avoid forcing per-frame HandleOpt retries on transient queue pressure.
    return RenderResult::DROPPED;
  }
  UpdateCpuBackpressure(requestUs, false);

  // 2.5 等待 Fence
  if (fenceFd >= 0) {
    constexpr int kFenceTimeoutMs = 33;
    m->fenceWaitCalls++;
    int waitRet = common::WaitAndCloseFence(fenceFd, kFenceTimeoutMs);
    fenceFd = -1;
    if (waitRet != 0) {
      m->fenceWaitFailures++;
      if (waitRet > 0) {
        m->fenceTimeoutCount++;
        LOGF(LOG_WARN,
             "VideoPipeline: Fence timeout (%{public}d ms). "
             "GPU/Compositor might be slow.",
             kFenceTimeoutMs);
      } else {
        LOGF(LOG_ERROR, "VideoPipeline: Fence wait error.");
      }

      m->nwAbortBufferCalls++;
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
      drop_count_++;
      return RenderResult::DROPPED;
    }
  }
  auto t_fence = std::chrono::steady_clock::now();

  // 3. Map Buffer
  OH_NativeBuffer *nativeBuffer = nullptr;
  ret = OH_NativeBuffer_FromNativeWindowBuffer(buffer, &nativeBuffer);
  void *addr = nullptr;
  if (ret == 0) {
    ret = OH_NativeBuffer_Map(nativeBuffer, &addr);
  }
  
  auto t_map = std::chrono::steady_clock::now();

  if (ret != 0 || !addr) {
    if (!nativeBuffer) {
      m->nbFromWindowBufferFailures++;
    } else {
      m->nbMapFailures++;
      if (ret == 0) {
        // Audit T5-F1: Map succeeded (ret==0) but addr==nullptr; Unmap required per contract
        OH_NativeBuffer_Unmap(nativeBuffer);
      }
    }
    m->nwAbortBufferCalls++;
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    if (nativeBuffer) {
      OH_NativeBuffer_Unreference(nativeBuffer);
    }
    drop_count_++;
    return RenderResult::DROPPED;
  }

  auto t4 = std::chrono::steady_clock::now();

  // 获取 Buffer 实际尺寸
  OH_NativeBuffer_Config config{};
  // HarmonyOS NDK 当前签名为 void，直接读取结构体并校验字段。
  OH_NativeBuffer_GetConfig(nativeBuffer, &config);
  if (config.width <= 0 || config.height <= 0 || config.stride <= 0) {
    m->nwAbortBufferCalls++;
    (void)OH_NativeBuffer_Unmap(nativeBuffer);
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    OH_NativeBuffer_Unreference(nativeBuffer);
    drop_count_++;
    if (ShouldLog(render_log_count_, 5, 60)) {
      LOGF(LOG_ERROR,
           "Invalid NativeBuffer config: w=%{public}d h=%{public}d stride=%{public}d",
           config.width, config.height, config.stride);
    }
    return RenderResult::DROPPED;
  }

  int32_t dstWidth = config.width;
  int32_t dstHeight = config.height;
  int32_t strideBytes = config.stride;
  constexpr int32_t kBytesPerPixel = 4;
  if (strideBytes < dstWidth * kBytesPerPixel) {
    // Defensive fallback: some runtimes may report stride in pixels.
    if (strideBytes >= dstWidth) {
      const int64_t converted =
          static_cast<int64_t>(strideBytes) * kBytesPerPixel;
      if (converted > std::numeric_limits<int32_t>::max()) {
        m->nwAbortBufferCalls++;
        (void)OH_NativeBuffer_Unmap(nativeBuffer);
        OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
        OH_NativeBuffer_Unreference(nativeBuffer);
        drop_count_++;
        if (ShouldLog(render_log_count_, 5, 60)) {
          LOGF(LOG_ERROR,
               "NativeBuffer stride overflow: raw=%{public}d width=%{public}d",
               config.stride, config.width);
        }
        return RenderResult::DROPPED;
      }
      strideBytes = static_cast<int32_t>(converted);
    } else {
      m->nwAbortBufferCalls++;
      (void)OH_NativeBuffer_Unmap(nativeBuffer);
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
      OH_NativeBuffer_Unreference(nativeBuffer);
      drop_count_++;
      if (ShouldLog(render_log_count_, 5, 60)) {
        LOGF(LOG_ERROR,
             "NativeBuffer stride too small: raw=%{public}d width=%{public}d",
             config.stride, config.width);
      }
      return RenderResult::DROPPED;
    }
  }
  if ((strideBytes % kBytesPerPixel) != 0) {
    m->nwAbortBufferCalls++;
    (void)OH_NativeBuffer_Unmap(nativeBuffer);
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    OH_NativeBuffer_Unreference(nativeBuffer);
    drop_count_++;
    if (ShouldLog(render_log_count_, 5, 60)) {
      LOGF(LOG_ERROR,
           "NativeBuffer stride not aligned: raw=%{public}d bytes=%{public}d",
           config.stride, strideBytes);
    }
    return RenderResult::DROPPED;
  }

  bool destIsBgra = false;
#if defined(NATIVEBUFFER_PIXEL_FMT_RGBA_8888) &&                               \
    defined(NATIVEBUFFER_PIXEL_FMT_BGRA_8888)
  if (config.format == NATIVEBUFFER_PIXEL_FMT_RGBA_8888) {
    destIsBgra = false;
  } else if (config.format == NATIVEBUFFER_PIXEL_FMT_BGRA_8888) {
    destIsBgra = true;
  } else {
    LOGF(LOG_ERROR, "Unsupported NativeBuffer format: %{public}d",
         config.format);
    m->nwAbortBufferCalls++;
    OH_NativeBuffer_Unmap(nativeBuffer);
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    OH_NativeBuffer_Unreference(nativeBuffer);
    drop_count_++;
    return RenderResult::DROPPED;
  }
#endif

  // 4. 计算缩放并转换（仅在关键尺寸/宽高比变化时重算）
  EnsureCpuLayout(width, height, dstWidth, dstHeight);
  const int scaledWidth = cpu_layout_cache_.scaled_width;
  const int scaledHeight = cpu_layout_cache_.scaled_height;
  const int offsetX = cpu_layout_cache_.offset_x;
  const int offsetY = cpu_layout_cache_.offset_y;

  // 清空背景 (如果有黑边)
  uint8_t *dst = static_cast<uint8_t *>(addr);
  const int32_t dstStridePixels = strideBytes / kBytesPerPixel;
  if (cpu_layout_cache_.has_black_bars) {
    uint32_t *dst32 = reinterpret_cast<uint32_t *>(dst);
    const uint32_t black = 0xFF000000u;

    const int contentX0 = offsetX;
    const int contentY0 = offsetY;
    const int contentX1 = offsetX + scaledWidth;
    const int contentY1 = offsetY + scaledHeight;

    auto FillRowSpan = [&](int y, int x0, int x1) {
      if (y < 0 || y >= dstHeight) {
        return;
      }
      x0 = std::max(0, x0);
      x1 = std::min(dstWidth, x1);
      if (x1 <= x0) {
        return;
      }
      uint32_t *row =
          dst32 + static_cast<size_t>(y) * static_cast<size_t>(dstStridePixels);
      std::fill(row + x0, row + x1, black);
    };

    for (int y = 0; y < contentY0; y++) {
      FillRowSpan(y, 0, dstWidth);
    }
    for (int y = contentY1; y < dstHeight; y++) {
      FillRowSpan(y, 0, dstWidth);
    }
    for (int y = contentY0; y < contentY1; y++) {
      if (contentX0 > 0) {
        FillRowSpan(y, 0, contentX0);
      }
      if (contentX1 < dstWidth) {
        FillRowSpan(y, contentX1, dstWidth);
      }
    }
  }

  uint32_t *destRegion =
      reinterpret_cast<uint32_t *>(
          dst + static_cast<size_t>(offsetY) * static_cast<size_t>(strideBytes)) +
      offsetX;

  PixelFormat srcFormat;
  switch (pixel_format_) {
  case RETRO_PIXEL_FORMAT_0RGB1555:
    srcFormat = PixelFormat::RGB0555;
    break;
  case RETRO_PIXEL_FORMAT_RGB565:
    srcFormat = PixelFormat::RGB565;
    break;
  default:
    srcFormat = PixelFormat::XRGB8888;
    break;
  }

  if (!destIsBgra) {
    PixelConverter::ConvertAndScale(data, srcFormat, width, height, pitch,
                                    destRegion, PixelFormat::RGBA8888,
                                    scaledWidth, scaledHeight,
                                    static_cast<unsigned>(dstStridePixels));
  } else {
    PixelConverter::ConvertAndScale(data, srcFormat, width, height, pitch,
                                    destRegion, PixelFormat::BGRA8888,
                                    scaledWidth, scaledHeight,
                                    static_cast<unsigned>(dstStridePixels));
  }

  auto t5 = std::chrono::steady_clock::now();

  {
    constexpr long long kSlowConvThresholdUs = 25000;
    const long long convUsNow =
        std::chrono::duration_cast<std::chrono::microseconds>(t5 - t4).count();
    if (convUsNow >= kSlowConvThresholdUs) {
      static std::atomic<uint32_t> slowConvLogCount{0};
      const uint32_t n = slowConvLogCount.fetch_add(1) + 1;
      if (n <= 5 || (n % 60) == 0) {
        const bool hasBlackBars =
            cpu_layout_cache_.has_black_bars;
        LOGF(LOG_WARN,
             "SlowConv: conv=%{public}lldus mode=%{public}d "
             "src=%{public}ux%{public}u pitch=%{public}zu fmt=%{public}d "
             "dst=%{public}dx%{public}d stride=%{public}d "
             "scaled=%{public}dx%{public}d off=%{public}d,%{public}d "
             "bars=%{public}d bgra=%{public}d",
             convUsNow, static_cast<int>(scaling_mode_.load()), width, height,
             pitch, config.format, dstWidth, dstHeight, strideBytes, scaledWidth,
             scaledHeight, offsetX, offsetY, hasBlackBars ? 1 : 0,
             destIsBgra ? 1 : 0);
      }
    }
  }

  ret = OH_NativeBuffer_Unmap(nativeBuffer);
  auto t_unmap = std::chrono::steady_clock::now();
  
  if (ret != 0) {
    m->nbUnmapFailures++;
    m->nwAbortBufferCalls++;
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    OH_NativeBuffer_Unreference(nativeBuffer);
    drop_count_++;
    return RenderResult::DROPPED;
  }

  // 5. 提交
  // Use API default full-dirty region (rects=nullptr, rectNumber=0).
  // This avoids passing transient stack rect pointers into vendor surface cache.
  ::Region region{nullptr, 0};
  m->nwFlushBufferCalls++;
  ret =
      OH_NativeWindow_NativeWindowFlushBuffer(window, buffer, fenceFd, region);
  
  auto t6 = std::chrono::steady_clock::now();
  
  if (ret != 0) {
    m->nwFlushBufferFailures++;
    if (drop_count_ % 60 == 0 || drop_count_ < 5) {
      LOGF(LOG_ERROR, "FlushBuffer failed: ret=%{public}d", ret);
    }
    m->nwAbortBufferCalls++;
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    OH_NativeBuffer_Unreference(nativeBuffer);
    drop_count_++;
    return RenderResult::DROPPED;
  }
  OH_NativeBuffer_Unreference(nativeBuffer);

  // Check total time and log breakdown if slow (> 20ms)
  long long totalUs =
      std::chrono::duration_cast<std::chrono::microseconds>(t6 - t_start)
          .count();
  
  if (totalUs > 20000) {
      long long t_req_us = std::chrono::duration_cast<std::chrono::microseconds>(t_req - t_start).count();
      long long t_fence_us = std::chrono::duration_cast<std::chrono::microseconds>(t_fence - t_req).count();
      long long t_map_us = std::chrono::duration_cast<std::chrono::microseconds>(t_map - t_fence).count();
      long long t_prep_us = std::chrono::duration_cast<std::chrono::microseconds>(t4 - t_map).count();
      long long t_conv_us = std::chrono::duration_cast<std::chrono::microseconds>(t5 - t4).count();
      long long t_unmap_us = std::chrono::duration_cast<std::chrono::microseconds>(t_unmap - t5).count();
      long long t_flush_us = std::chrono::duration_cast<std::chrono::microseconds>(t6 - t_unmap).count();
      
      static uint32_t slowRenderLogCount = 0;
      slowRenderLogCount++;
      if (slowRenderLogCount <= 10 || (slowRenderLogCount % 60) == 0) {
          LOGF(LOG_WARN, 
               "Slow RenderCPU: Total=%{public}lld us | Req=%{public}lld | Fence=%{public}lld | Map=%{public}lld | Prep=%{public}lld | Conv=%{public}lld | Unmap=%{public}lld | Flush=%{public}lld",
               totalUs, t_req_us, t_fence_us, t_map_us, t_prep_us, t_conv_us, t_unmap_us, t_flush_us);
      }
  }

  if (frame_count_ % 60 == 0) {
    long long perfTotalUs =
        std::chrono::duration_cast<std::chrono::microseconds>(t6 - start)
            .count();
    long long convUs =
        std::chrono::duration_cast<std::chrono::microseconds>(t5 - t4).count();
    LOGF(LOG_INFO,
         "Perf: Total=%{public}lld us, Conv=%{public}lld us, Mode=%{public}d",
         perfTotalUs, convUs, static_cast<int>(scaling_mode_.load()));
  }
  frame_count_++;
  return isDupeRequest ? RenderResult::DUPED : RenderResult::RENDERED;
}

VideoPipeline::RenderResult
VideoPipeline::Render(OHNativeWindow *window, const void *data, unsigned width,
                      unsigned height, size_t pitch, RenderMetrics *metrics) {
  framePacer_.BeginFrame();
  auto start = std::chrono::steady_clock::now();

  RenderMetrics localMetrics{};
  RenderMetrics *m = metrics ? metrics : &localMetrics;
  if (metrics) {
    *metrics = RenderMetrics{};
  }

  auto Finish = [&](RenderResult r) {
    framePacer_.EndFrame();
    if (m) {
      m->frameTimeUs = static_cast<uint64_t>(
          std::chrono::duration_cast<std::chrono::microseconds>(
              std::chrono::steady_clock::now() - start)
              .count());
    }
    return r;
  };

  if (!data) {
    return Finish(RenderResult::RENDERED); // Null frame is considered "rendered" (no-op)
  }

  ScalingMode mode = scaling_mode_.load();
#if defined(__i386__) || defined(__x86_64__)
  if (mode != ScalingMode::GLES_SCALING) {
    mode = ScalingMode::GLES_SCALING;
    scaling_mode_.store(mode, std::memory_order_release);
    geometry_changed_.store(true, std::memory_order_release);
  }
#endif
  const auto now = std::chrono::steady_clock::now();
  MaybeRecoverDegradedMode(mode, now);
  // 注意:命名为 isDupeRequest 但实际语义是"HW 有效帧标记"。按 libretro 协议
  // dupe 是 (data == NULL),但 line 1399 已把 NULL 直接当 no-op RENDERED 返回,
  // 因此此处只剩 HW 有效帧的语义。彻底协议化的 dupe 处理(在 NULL 时复用上帧)
  // 留作后续单独 PR,需同步评估 GLES/Vulkan 路径的 DUPED 返回值含义。
  const bool isDupeRequest = (data == RETRO_HW_FRAME_BUFFER_VALID);
  const auto preflightReason =
      EvaluateRenderPreflight(window, width, height, pitch, mode, isDupeRequest);
  if (preflightReason != PreflightDropReason::NONE) {
    if (preflightReason == PreflightDropReason::NULL_WINDOW) {
      m->nwRequestBufferFailures++;
    }
    drop_count_++;
    if (ShouldLog(preflight_drop_log_count_, 5, 120)) {
      LOGF(LOG_WARN, "Frame dropped (preflight=%{public}s): mode=%{public}d "
                     "frame=%{public}ux%{public}u pitch=%{public}zu",
           PreflightDropReasonToString(preflightReason),
           static_cast<int>(mode), width, height, pitch);
    }
    return Finish(RenderResult::DROPPED);
  }

  EnsureBackends();
  EnsureWindowConfiguredIfNeeded(window, width, height);

  // ... Render implementation ...
  RenderResult result = RenderResult::DROPPED;
  if (mode == ScalingMode::GLES_SCALING) {
    result = gles_backend_->RenderFrame(window, data, width, height, pitch,
                                        isDupeRequest, m, start);
  } else {
    // Clean up GLES resources if we are not in GLES mode
    if (gles_state_ != GlesState::UNINITIALIZED) {
      gles_renderer_.Deinit();
      gles_state_ = GlesState::UNINITIALIZED;
    }
    gles_swap_fail_count_ = 0;
    gles_surface_recreate_failures_ = 0;
    gles_full_reinit_failures_ = 0;
    gles_next_retry_time_ = std::chrono::steady_clock::time_point{};

    result = software_backend_->RenderFrame(window, data, width, height, pitch,
                                            isDupeRequest, m, start);
  }

  if (result == RenderResult::RENDERED && mode == ScalingMode::SOFTWARE_SCALING) {
    // Additional sleep for software mode if needed? 
    // Usually CPU render takes enough time, but maybe not.
    // FramePacer handles it if we call EndFrame() for RENDERED too, but for now only for DROPPED.
  }

  if (result != RenderResult::DROPPED) {
    if (mode == ScalingMode::GLES_SCALING) {
      SetRenderModeState(RenderModeState::GLES_READY);
    } else if (mode == ScalingMode::HARDWARE_SCALING) {
      SetRenderModeState(RenderModeState::HW_READY);
    } else {
      const auto state = GetRenderModeState();
      if (state != RenderModeState::DEGRADED_TO_SW &&
          state != RenderModeState::RECOVERING) {
        SetRenderModeState(RenderModeState::SW_READY);
      }
    }
  }

  return Finish(result);
}

bool VideoPipeline::InitializeHardwareRenderer(OHNativeWindow *window,
                                               EnvState &env_state,
                                               const HwRenderRuntimeInfo &runtime) {
  EnsureBackends();
  return hw_backend_->Initialize(window, env_state, &runtime);
}

bool VideoPipeline::InitializeHardwareRendererImpl(OHNativeWindow *window,
                                                   EnvState &env_state,
                                                   const HwRenderRuntimeInfo &runtime) {
  if (!env_state.IsHwRenderEnabled() || !window) {
    return false;
  }

  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    if (!vulkan_context_) {
      vulkan_context_ = std::make_unique<VulkanContext>();
    }
    if (!vulkan_presenter_) {
      vulkan_presenter_ = std::make_unique<VulkanPresenter>();
    }
    const bool sameWindowReady =
        vulkan_context_->IsReady() && hw_window_ == window;
    if (sameWindowReady) {
      UpdateVulkanPresenterContent(env_state, &runtime);
      SyncVulkanSwapchainState(env_state);
      MarkHardwarePathRecovered("hw_vk_same_window_ready");
      return true;
    }

    if (vulkan_context_->IsReady()) {
      DestroyHardwareRendererImpl(env_state);
    }

    if (!vulkan_context_->Initialize(window, env_state)) {
      DestroyHardwareRendererImpl(env_state);
      MarkHardwarePathFailure("hw_vk_context_init_failed");
      return false;
    }

    if (hw_window_ != window) {
      if (hw_window_) {
        OH_NativeWindow_NativeObjectUnreference(hw_window_);
      }
      hw_window_ = window;
      OH_NativeWindow_NativeObjectReference(hw_window_);
    }

    if (!vulkan_presenter_->Initialize(*vulkan_context_)) {
      DestroyHardwareRendererImpl(env_state);
      MarkHardwarePathFailure("hw_vk_presenter_init_failed");
      return false;
    }

    UpdateVulkanPresenterContent(env_state, &runtime);
    if (!SyncVulkanSwapchainState(env_state)) {
      DestroyHardwareRendererImpl(env_state);
      MarkHardwarePathFailure("hw_vk_sync_swapchain_failed");
      return false;
    }

    LOGF(LOG_INFO, " [Vulkan] Hardware Renderer Initialized");
    MarkHardwarePathRecovered("hw_vk_initialized");
    if (cb.context_reset) {
      cb.context_reset();
    }
    return true;
  }

  if (!graphics_context_) {
    graphics_context_ = std::make_unique<GraphicsContext>();
  }

  GraphicsConfig config;
  config.vsync = false;
  config.debug = cb.debug_context;
  config.depth_bits = cb.depth ? 24 : 0;
  config.stencil_bits = cb.stencil ? 8 : 0;
  if (cb.context_type == RETRO_HW_CONTEXT_OPENGLES2) {
    config.gl_es3 = false;
  } else if (cb.context_type == RETRO_HW_CONTEXT_OPENGLES_VERSION) {
    config.gl_es3 = (cb.version_major >= 3);
  } else {
    config.gl_es3 = true;
  }

  const bool configCompatible = graphics_context_->IsConfigCompatible(config);
  const bool sameWindowReady =
      graphics_context_->IsReady() && hw_window_ == window;
  if (sameWindowReady && configCompatible) {
    if (!hw_presenter_) {
      hw_presenter_ = std::make_unique<HwRenderPresenter>();
    }
    unsigned targetW = 0;
    unsigned targetH = 0;
    ResolveTargetSize(env_state, runtime, targetW, targetH);
    HwRenderConfig hwConfig{};
    BuildHwRenderConfig(cb, hwConfig);
    if (targetW > 0 && targetH > 0) {
      if (!hw_presenter_->EnsureTarget(targetW, targetH, hwConfig)) {
        LOGF(LOG_WARN, "HW render presenter init failed");
      } else {
        LOGF(LOG_INFO, "HW render presenter ready: %{public}ux%{public}u",
             targetW, targetH);
      }
    }
    MarkHardwarePathRecovered("hw_egl_same_window_ready");
    return true;
  }

  const bool shouldDestroy = graphics_context_->HasContext() &&
                             (!configCompatible || !cb.cache_context);
  if (shouldDestroy) {
    DestroyHardwareRendererImpl(env_state);
  }

  const bool hadContext = graphics_context_->HasContext();
  if (!graphics_context_->Initialize(window, config)) {
    MarkHardwarePathFailure("hw_egl_context_init_failed");
    return false;
  }

  if (hw_window_ != window) {
    if (hw_window_) {
      OH_NativeWindow_NativeObjectUnreference(hw_window_);
    }
    hw_window_ = window;
    OH_NativeWindow_NativeObjectReference(hw_window_);
  }

  LOGF(LOG_INFO, " [EGL] Hardware Renderer Initialized");

  if (!hw_presenter_) {
    hw_presenter_ = std::make_unique<HwRenderPresenter>();
  }

  unsigned targetW = 0;
  unsigned targetH = 0;
  ResolveTargetSize(env_state, runtime, targetW, targetH);
  HwRenderConfig hwConfig{};
  BuildHwRenderConfig(cb, hwConfig);
  if (targetW > 0 && targetH > 0) {
    if (!hw_presenter_->EnsureTarget(targetW, targetH, hwConfig)) {
      LOGF(LOG_WARN, "HW render presenter init failed");
    } else {
      LOGF(LOG_INFO, "HW render presenter ready: %{public}ux%{public}u",
           targetW, targetH);
    }
  }

  if (!hadContext && cb.context_reset) {
    cb.context_reset();
  }

  MarkHardwarePathRecovered("hw_egl_initialized");
  return true;
}

void VideoPipeline::DestroyHardwareRenderer(EnvState &env_state) {
  EnsureBackends();
  hw_backend_->Shutdown(env_state);
}

void VideoPipeline::DestroyHardwareRendererImpl(EnvState &env_state) {
  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    env_state.SetVulkanInterface(nullptr);
    if (vulkan_presenter_) {
      vulkan_presenter_->Destroy();
      vulkan_presenter_.reset();
    }
    if (vulkan_context_) {
      vulkan_context_->Destroy();
      vulkan_context_.reset();
    }
    if (hw_window_) {
      VideoPipeline::ResetNativeWindow(hw_window_);
      window_state_manager_.Reset();
      OH_NativeWindow_NativeObjectUnreference(hw_window_);
      hw_window_ = nullptr;
    }
    vk_sync_index_ = 0;
    vk_acquire_fail_count_ = 0;
    vk_acquire_outdated_count_ = 0;
    vk_present_fail_count_ = 0;
    last_vk_swapchain_recreate_time_ = std::chrono::steady_clock::time_point{};
    return;
  }

  if (!graphics_context_ || !graphics_context_->HasContext()) {
    if (hw_window_) {
      VideoPipeline::ResetNativeWindow(hw_window_);
      window_state_manager_.Reset();
      OH_NativeWindow_NativeObjectUnreference(hw_window_);
      hw_window_ = nullptr;
    }
    return;
  }

  const bool contextReady = graphics_context_->IsReady();
  if (contextReady && cb.context_destroy) {
    cb.context_destroy();
  }

  if (hw_presenter_) {
    if (contextReady) {
      hw_presenter_->Destroy();
    }
    hw_presenter_.reset();
  }

  graphics_context_->Destroy();

  if (hw_window_) {
    VideoPipeline::ResetNativeWindow(hw_window_);
    window_state_manager_.Reset();
    OH_NativeWindow_NativeObjectUnreference(hw_window_);
    hw_window_ = nullptr;
  }
}

void VideoPipeline::SwapHardwareBuffers(EnvState &env_state) {
  EnsureBackends();
  hw_backend_->SwapBuffers(env_state);
}

void VideoPipeline::SwapHardwareBuffersImpl(EnvState &env_state) {
  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    if (!vulkan_context_ || !vulkan_context_->IsReady() || !vulkan_presenter_ ||
        !vulkan_presenter_->IsReady()) {
      MarkHardwarePathFailure("hw_vk_not_ready");
      return;
    }
    if (!vulkan_presenter_->Present()) {
      const bool need_recreate =
          vulkan_presenter_->ShouldRecreateSwapchain() ||
          vulkan_context_->ShouldRecreateSwapchain();
      if (need_recreate) {
        int windowW = window_width_.load();
        int windowH = window_height_.load();
        if (!RecreateVulkanSwapchain(hw_window_, windowW, windowH, env_state,
                                     false)) {
          if (ShouldLog(vk_present_fail_count_, 3, 60)) {
            LOGF(LOG_WARN, "Vulkan swapchain recreate failed (present)");
          }
          MarkHardwarePathFailure("hw_vk_recreate_failed");
        } else {
          MarkHardwarePathRecovered("hw_vk_recreate_ok");
        }
      } else {
        if (ShouldLog(vk_present_fail_count_, 3, 60)) {
          LOGF(LOG_WARN, "Vulkan present failed");
        }
        MarkHardwarePathFailure("hw_vk_present_failed");
      }
    } else {
      MarkHardwarePathRecovered("hw_vk_present_ok");
    }
    return;
  }

  if (!graphics_context_ || !graphics_context_->IsReady()) {
    MarkHardwarePathFailure("hw_egl_not_ready");
    return;
  }
  static bool logged = false;
  if (!logged) {
    logged = true;
    LOGF(LOG_INFO, "HW render present active");
  }
  if (hw_presenter_ && hw_presenter_->IsReady()) {
    int windowW = window_width_.load();
    int windowH = window_height_.load();
    if (windowW <= 0 || windowH <= 0) {
      windowW = graphics_context_->GetWidth();
      windowH = graphics_context_->GetHeight();
    }
    unsigned contentW = env_state.GetGeometryBaseWidth();
    unsigned contentH = env_state.GetGeometryBaseHeight();
    float aspect = env_state.GetGeometryAspectRatio();
    if (!(aspect > 0.0f) && contentW > 0 && contentH > 0) {
      aspect = static_cast<float>(contentW) /
               static_cast<float>(contentH);
    }
    hw_presenter_->Present(windowW, windowH, aspect, contentW, contentH);
  }
  if (!graphics_context_->SwapBuffers()) {
    MarkHardwarePathFailure("hw_egl_swap_failed");
  } else {
    MarkHardwarePathRecovered("hw_egl_swap_ok");
  }
}

void VideoPipeline::OnHardwareWindowResized(OHNativeWindow *window, int width,
                                            int height, EnvState &env_state) {
  EnsureBackends();
  hw_backend_->OnWindowResized(window, width, height, env_state);
}

void VideoPipeline::OnHardwareWindowResizedImpl(OHNativeWindow *window, int width,
                                                int height, EnvState &env_state) {
  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    if (!vulkan_context_ || !vulkan_context_->IsReady()) {
      MarkHardwarePathFailure("hw_vk_resize_not_ready");
      return;
    }
    if (!RecreateVulkanSwapchain(window, width, height, env_state, false)) {
      MarkHardwarePathFailure("hw_vk_resize_recreate_failed");
    } else {
      MarkHardwarePathRecovered("hw_vk_resize_ok");
    }
    return;
  }
  if (!graphics_context_ || !graphics_context_->HasContext() || !window) {
    MarkHardwarePathFailure("hw_egl_resize_invalid");
    return;
  }
  if (!graphics_context_->UpdateSurface(window)) {
    LOGF(LOG_WARN, "HW render UpdateSurface failed on resize");
    MarkHardwarePathFailure("hw_egl_resize_update_failed");
    DestroyHardwareRendererImpl(env_state);
  } else {
    MarkHardwarePathRecovered("hw_egl_resize_ok");
  }
}

void VideoPipeline::OnHardwareWindowDestroyed(EnvState &env_state) {
  EnsureBackends();
  hw_backend_->OnWindowDestroyed(env_state);
}

void VideoPipeline::OnHardwareWindowDestroyedImpl(EnvState &env_state) {
  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    DestroyHardwareRendererImpl(env_state);
    return;
  }
  if (!graphics_context_) {
    return;
  }
  if (cb.cache_context && graphics_context_->HasContext()) {
    graphics_context_->ReleaseSurface();
    if (hw_window_) {
      OH_NativeWindow_NativeObjectUnreference(hw_window_);
      hw_window_ = nullptr;
    }
  } else {
    DestroyHardwareRendererImpl(env_state);
  }
}

void VideoPipeline::OnHardwareGeometryChanged(
    EnvState &env_state, const HwRenderRuntimeInfo &runtime) {
  EnsureBackends();
  hw_backend_->OnGeometryChanged(env_state, runtime);
}

void VideoPipeline::OnHardwareGeometryChangedImpl(
    EnvState &env_state, const HwRenderRuntimeInfo &runtime) {
  const auto &cb = env_state.GetHwRenderCallback();
  if (cb.context_type == RETRO_HW_CONTEXT_VULKAN) {
    UpdateVulkanPresenterContent(env_state, &runtime);
    return;
  }
  if (!graphics_context_ || !graphics_context_->IsReady()) {
    return;
  }
  if (!hw_presenter_) {
    hw_presenter_ = std::make_unique<HwRenderPresenter>();
  }
  unsigned targetW = 0;
  unsigned targetH = 0;
  ResolveTargetSize(env_state, runtime, targetW, targetH);
  HwRenderConfig hwConfig{};
  BuildHwRenderConfig(cb, hwConfig);
  if (targetW > 0 && targetH > 0) {
    if (!hw_presenter_->EnsureTarget(targetW, targetH, hwConfig)) {
      LOGF(LOG_WARN, "HW render presenter resize failed");
    }
  }
}

bool VideoPipeline::HandleVulkanAcquire(
    OHNativeWindow *window, EnvState &env_state,
    const std::function<void()> &on_acquire_begin,
    const std::function<void()> &on_acquire_end) {
  EnsureBackends();
  return hw_backend_->HandleAcquire(window, env_state, on_acquire_begin,
                                    on_acquire_end);
}

bool VideoPipeline::HandleVulkanAcquireImpl(
    OHNativeWindow *window, EnvState &env_state,
    const std::function<void()> &on_acquire_begin,
    const std::function<void()> &on_acquire_end) {
  if (!window) {
    return false;
  }
  if (!vulkan_context_ || !vulkan_context_->IsReady() || !vulkan_presenter_ ||
      !vulkan_presenter_->IsReady()) {
    return false;
  }

  const auto &api = vulkan_context_->GetApi();
  if (!api.acquire_next_image_khr) {
    return false;
  }

  if (vulkan_context_->ShouldRecreateSwapchain() ||
      vulkan_presenter_->ShouldRecreateSwapchain()) {
    int windowW = window_width_.load();
    int windowH = window_height_.load();
    if (!RecreateVulkanSwapchain(window, windowW, windowH, env_state, false)) {
      MarkHardwarePathFailure("hw_vk_acquire_recreate_failed");
      return false;
    }
  }

  if (on_acquire_begin) {
    on_acquire_begin();
  }

  const uint32_t acquire_index = vk_sync_index_;
  VkSemaphore acquire_semaphore =
      vulkan_presenter_->GetAcquireSemaphore(acquire_index);
  if (acquire_semaphore == VK_NULL_HANDLE) {
    if (on_acquire_end) {
      on_acquire_end();
    }
    return false;
  }

  uint32_t image_index = 0;
  const VkResult res = api.acquire_next_image_khr(
      vulkan_context_->GetDevice(), vulkan_context_->GetSwapchain(),
      UINT64_MAX, acquire_semaphore, VK_NULL_HANDLE, &image_index);

  if (res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR) {
    if (ShouldLog(vk_acquire_outdated_count_, 3, 60)) {
      LOGF(LOG_WARN, "Vulkan acquire out of date: %{public}d", res);
    }
    int windowW = window_width_.load();
    int windowH = window_height_.load();
    RecreateVulkanSwapchain(window, windowW, windowH, env_state, true);
    MarkHardwarePathFailure("hw_vk_acquire_out_of_date");
    if (on_acquire_end) {
      on_acquire_end();
    }
    return false;
  }
  if (res != VK_SUCCESS) {
    if (ShouldLog(vk_acquire_fail_count_, 3, 60)) {
      LOGF(LOG_WARN, "Vulkan acquire failed: %{public}d", res);
    }
    if (on_acquire_end) {
      on_acquire_end();
    }
    MarkHardwarePathFailure("hw_vk_acquire_failed");
    return false;
  }

  if (image_index != acquire_index) {
    vulkan_presenter_->SwapAcquireSemaphores(acquire_index, image_index);
  }
  vulkan_presenter_->SetSyncIndex(image_index);
  vk_sync_index_ = image_index;

  if (on_acquire_end) {
    on_acquire_end();
  }
  MarkHardwarePathRecovered("hw_vk_acquire_ok");
  return true;
}

uintptr_t VideoPipeline::GetHwRenderFramebuffer() const {
  if (hw_backend_) {
    return hw_backend_->GetFramebuffer();
  }
  return GetHwRenderFramebufferImpl();
}

uintptr_t VideoPipeline::GetHwRenderFramebufferImpl() const {
  if (!graphics_context_ || !graphics_context_->IsReady()) {
    return 0;
  }
  if (!hw_presenter_ || !hw_presenter_->IsReady()) {
    return 0;
  }
  return hw_presenter_->GetFramebuffer();
}

bool VideoPipeline::HasHardwareContext() const {
  if (hw_backend_) {
    return hw_backend_->HasContext();
  }
  return HasHardwareContextImpl();
}

bool VideoPipeline::HasHardwareContextImpl() const {
  if (vulkan_context_ && vulkan_context_->IsReady()) {
    return true;
  }
  return graphics_context_ && graphics_context_->HasContext();
}

} // namespace libretro
