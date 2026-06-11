#ifndef LIBRETRO_ENGINE_VIDEO_PIPELINE_H
#define LIBRETRO_ENGINE_VIDEO_PIPELINE_H

#include "../../platform/graphics/gles_renderer.h"
#include "window_state_manager.h"
#include "core/libretro/libretro.h"
#include "frame_pacer.h"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <vector>

namespace libretro {
class EnvState;
class GraphicsContext;
class HwRenderPresenter;
class VulkanContext;
class VulkanPresenter;
class SoftwareRenderBackend;
class GlesRenderBackend;
class HwRenderBackend;

struct HwRenderRuntimeInfo {
  unsigned video_width = 0;
  unsigned video_height = 0;
  unsigned video_max_width = 0;
  unsigned video_max_height = 0;
};

/**
 * @brief 视频管线，负责将 Libretro 原始像素数据渲染到 NativeWindow。
 */
class VideoPipeline {
public:
  VideoPipeline();
  ~VideoPipeline();

  static void ResetNativeWindow(OHNativeWindow *window);

  /**
   * @brief 配置渲染几何（对应 Libretro 的 av_info.geometry）
   */
  void SetGeometry(unsigned width, unsigned height, float aspect_ratio) {
    geometry_base_width_ = width;
    geometry_base_height_ = height;
    geometry_aspect_ratio_ = aspect_ratio;
    geometry_changed_.store(true);
  }

  /**
   * @brief 设置物理窗口大小
   */
  void SetWindowSize(int width, int height) {
    const int prevW = window_width_.load();
    const int prevH = window_height_.load();
    if (prevW != width || prevH != height) {
      window_width_.store(width);
      window_height_.store(height);
      geometry_changed_.store(true);
    }
  }

  void GetWindowSize(int &width, int &height) const {
    width = window_width_.load();
    height = window_height_.load();
  }

  bool InitializeHardwareRenderer(OHNativeWindow *window, EnvState &env_state,
                                  const HwRenderRuntimeInfo &runtime);
  void DestroyHardwareRenderer(EnvState &env_state);
  void SwapHardwareBuffers(EnvState &env_state);
  void OnHardwareWindowResized(OHNativeWindow *window, int width, int height,
                               EnvState &env_state);
  void OnHardwareWindowDestroyed(EnvState &env_state);
  void OnHardwareGeometryChanged(EnvState &env_state,
                                 const HwRenderRuntimeInfo &runtime);
  bool HandleVulkanAcquire(
      OHNativeWindow *window, EnvState &env_state,
      const std::function<void()> &on_acquire_begin,
      const std::function<void()> &on_acquire_end);
  uintptr_t GetHwRenderFramebuffer() const;
  bool HasHardwareContext() const;

  /**
   * @brief 设置像素格式
   */
  void SetPixelFormat(retro_pixel_format format) {
    if (pixel_format_ != format) {
      pixel_format_ = format;
      ClearFrameCache();
      geometry_changed_.store(true);
    }
  }

  retro_pixel_format GetPixelFormat() const { return pixel_format_; }
  bool CaptureLastFrameRgba(std::vector<uint8_t> &rgba, unsigned &width,
                            unsigned &height) const;

  enum class ScalingMode {
    /**
     * @brief 硬件缩放模式 (Hardware Scaling)
     *
     * 机制: 请求与游戏源分辨率一致的 Buffer (如 160x144)，由系统合成器
     * (HWC/DSS) 负责缩放上屏。 优点: 极低 CPU/GPU 开销，性能最佳
     * (60FPS+)，省电。 缺点: 系统缩放通常强制使用双线性过滤
     * (Bilinear)，导致像素画质模糊，无法实现锐利像素。 适用: 3D
     * 游戏，或对画质要求不高、追求极致流畅度的低端设备。
     */
    HARDWARE_SCALING,

    /**
     * @brief 软件缩放模式 (Software Scaling)
     *
     * 机制: 请求较高分辨率的 Buffer (如 720p)，CPU 使用 NEON
     * 指令集进行最近邻插值 (Nearest Neighbor) 缩放。 优点: 像素画质清晰锐利。
     * 缺点: CPU 开销巨大 (需每帧搬运和计算数百万像素)，可能导致发热、掉帧
     * (30FPS)。 适用: 极低分辨率的 2D 游戏 (如 GB/FC)，且设备 CPU 性能强劲时。
     */
    SOFTWARE_SCALING,

    /**
     * @brief OpenGL ES 渲染模式 (GLES Rendering) - **推荐**
     *
     * 机制: 请求全屏分辨率 Buffer，使用 OpenGL ES 3.0
     * 将游戏画面作为纹理上传，由 GPU 绘制全屏四边形。 Shader 中强制使用
     * GL_NEAREST 采样器。 优点: 完美结合了硬件加速的性能 (60FPS)
     * 和软件缩放的画质 (像素锐利)。 缺点: 需要 EGL 上下文管理，实现复杂度稍高
     * (已封装在 GLESRenderer 中)。 适用:
     * 所有场景，特别是追求完美模拟体验的用户。
     */
    GLES_SCALING
  };

  /**
   * @brief 设置缩放模式
   */
  void SetScalingMode(ScalingMode mode) {
    // Windows 模拟器（x86/x86_64）禁用非 GLES 路径，避免 NativeWindow
    // RequestBuffer 在高压下触发系统侧崩溃。
#if defined(__i386__) || defined(__x86_64__)
    if (mode != ScalingMode::GLES_SCALING) {
      mode = ScalingMode::GLES_SCALING;
    }
#endif
    if (scaling_mode_.load() != mode) {
      scaling_mode_.store(mode);
      geometry_changed_.store(true);
      if (mode == ScalingMode::SOFTWARE_SCALING) {
        const auto state = GetRenderModeState();
        if (state != RenderModeState::DEGRADED_TO_SW &&
            state != RenderModeState::RECOVERING) {
          SetRenderModeState(RenderModeState::SW_READY);
        }
      } else if (mode == ScalingMode::GLES_SCALING) {
        SetRenderModeState(RenderModeState::GLES_READY);
      } else {
        SetRenderModeState(RenderModeState::HW_READY);
      }
    }
  }

  /**
   * @brief 设置软件缩放的最大分辨率限制
   */
  void SetSoftwareResolutionMax(unsigned maxWidth, unsigned maxHeight) {
    software_max_width_.store(maxWidth);
    software_max_height_.store(maxHeight);
    geometry_changed_.store(true);
  }

  void SetTargetFps(double fps) {
    framePacer_.SetTargetFps(fps);
  }

  // 平台门控转发:模拟器(无 RT)禁 FramePacer 忙等自旋,改纯 sleep,避免 RenderThread
  // 烧满虚拟核抢 GameLoop 的核。由 RenderThread 据 OH_QoS_SetThreadQoS 成败注入。
  void SetFramePacerBusyWaitAllowed(bool allowed) {
    framePacer_.SetBusyWaitAllowed(allowed);
  }

  /**
   * @brief 启用/禁用 XEngine AI 超分
   */
  void SetXEngineEnabled(bool enabled) {
    if (xengine_enabled_.exchange(enabled) != enabled) {
      xengine_dirty_.store(true);
    }
  }

  /**
   * @brief 设置 VSync (Swap Interval)
   * interval: 0 = Disable (Turbo), 1 = Enable (Normal)
   */
  void SetSwapInterval(int interval) {
    gles_renderer_.SetSwapInterval(interval);
  }

  void SetGlesDiagnosticsEnabled(bool enabled) {
    gles_renderer_.SetDiagnosticsEnabled(enabled);
  }

  enum class RenderResult {
    RENDERED,
    DUPED,
    DROPPED,
  };

  enum class RenderModeState : uint8_t {
    SW_READY = 0,
    GLES_READY = 1,
    HW_READY = 2,
    DEGRADED_TO_SW = 3,
    RECOVERING = 4,
  };

  static const char *RenderModeStateToString(RenderModeState state);
  RenderModeState GetRenderModeState() const {
    return static_cast<RenderModeState>(
        render_mode_state_.load(std::memory_order_acquire));
  }

  struct RenderMetrics {
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
    uint64_t frameTimeUs = 0;
  };

  class IRenderBackend {
  public:
    virtual ~IRenderBackend() = default;
    virtual const char *GetName() const = 0;
    virtual void Reset() = 0;
    virtual bool Initialize(OHNativeWindow *window, EnvState &env_state,
                            const HwRenderRuntimeInfo *runtime) = 0;
    virtual void Shutdown(EnvState &env_state) = 0;
    virtual RenderResult RenderFrame(
        OHNativeWindow *window, const void *data, unsigned width,
        unsigned height, size_t pitch, bool isDupeRequest,
        RenderMetrics *metrics,
        const std::chrono::steady_clock::time_point &start) = 0;
    virtual void SwapBuffers(EnvState &env_state) = 0;
    virtual void OnWindowResized(OHNativeWindow *window, int width, int height,
                                 EnvState &env_state) = 0;
    virtual void OnWindowDestroyed(EnvState &env_state) = 0;
    virtual void OnGeometryChanged(EnvState &env_state,
                                   const HwRenderRuntimeInfo &runtime) = 0;
    virtual bool HandleAcquire(OHNativeWindow *window, EnvState &env_state,
                               const std::function<void()> &on_acquire_begin,
                               const std::function<void()> &on_acquire_end) = 0;
    virtual uintptr_t GetFramebuffer() const = 0;
    virtual bool HasContext() const = 0;
  };

  RenderResult Render(OHNativeWindow *window, const void *data, unsigned width,
                      unsigned height, size_t pitch,
                      RenderMetrics *metrics = nullptr);

private:
  friend class SoftwareRenderBackend;
  friend class GlesRenderBackend;
  friend class HwRenderBackend;

  void EnsureBackends();
  bool InitializeHardwareRendererImpl(OHNativeWindow *window,
                                      EnvState &env_state,
                                      const HwRenderRuntimeInfo &runtime);
  void DestroyHardwareRendererImpl(EnvState &env_state);
  void SwapHardwareBuffersImpl(EnvState &env_state);
  void OnHardwareWindowResizedImpl(OHNativeWindow *window, int width, int height,
                                   EnvState &env_state);
  void OnHardwareWindowDestroyedImpl(EnvState &env_state);
  void OnHardwareGeometryChangedImpl(EnvState &env_state,
                                     const HwRenderRuntimeInfo &runtime);
  bool HandleVulkanAcquireImpl(
      OHNativeWindow *window, EnvState &env_state,
      const std::function<void()> &on_acquire_begin,
      const std::function<void()> &on_acquire_end);
  uintptr_t GetHwRenderFramebufferImpl() const;
  bool HasHardwareContextImpl() const;
  void UpdateVulkanPresenterContent(EnvState &env_state,
                                    const HwRenderRuntimeInfo *runtime);
  bool SyncVulkanSwapchainState(EnvState &env_state);
  bool RecreateVulkanSwapchain(OHNativeWindow *window, int width, int height,
                               EnvState &env_state, bool force);
  void EnsureWindowConfiguredIfNeeded(OHNativeWindow *window, unsigned width,
                                      unsigned height);
  RenderResult RenderGLES(OHNativeWindow *window, const void *data,
                          unsigned width, unsigned height, size_t pitch,
                          bool isDupeRequest);
  RenderResult RenderCPU(OHNativeWindow *window, const void *data,
                         unsigned width, unsigned height, size_t pitch,
                         bool isDupeRequest, RenderMetrics *m,
                         const std::chrono::steady_clock::time_point &start);
  enum class PreflightDropReason {
    NONE = 0,
    NULL_WINDOW,
    INVALID_WINDOW_SIZE,
    INVALID_FRAME,
    CPU_BACKPRESSURE,
  };
  static const char *PreflightDropReasonToString(PreflightDropReason reason);
  PreflightDropReason EvaluateRenderPreflight(OHNativeWindow *window,
                                              unsigned width, unsigned height,
                                              size_t pitch, ScalingMode mode,
                                              bool isDupeRequest) const;
  void UpdateCpuBackpressure(int64_t requestUs, bool requestFailed);
  float ResolveSourceAspect(unsigned width, unsigned height) const;
  void EnsureCpuLayout(unsigned width, unsigned height, int dstWidth,
                       int dstHeight);
  void MarkHardwarePathFailure(const char *reason);
  void MarkHardwarePathRecovered(const char *reason);
  void SetRenderModeState(RenderModeState state);
  void EnterDegradedMode(ScalingMode sourceMode, const char *reason);
  void MaybeRecoverDegradedMode(ScalingMode &mode,
                                const std::chrono::steady_clock::time_point &now);

  enum class GlesState {
    UNINITIALIZED,
    READY,
    SURFACE_LOST,
    CONTEXT_LOST,
    WAIT_WINDOW,
    FATAL,
  };

  unsigned base_width_ = 0;
  unsigned base_height_ = 0;
  unsigned geometry_base_width_ = 0;
  unsigned geometry_base_height_ = 0;
  float geometry_aspect_ratio_ = 0.0f;
  unsigned last_request_width_ = 0;
  unsigned last_request_height_ = 0;
  ScalingMode last_request_mode_ = ScalingMode::GLES_SCALING;
  std::atomic<int> window_width_{0};
  std::atomic<int> window_height_{0};
  WindowStateManager window_state_manager_;

  std::atomic<bool> geometry_changed_{false};

  // Retry logic for geometry configuration
  unsigned retry_count_ = 0;
  std::chrono::steady_clock::time_point last_retry_time_{};
  std::chrono::steady_clock::time_point cpu_backpressure_until_{};
  uint32_t cpu_request_slow_streak_ = 0;
  uint32_t preflight_drop_log_count_ = 0;
  struct CpuLayoutCache {
    bool valid = false;
    unsigned src_width = 0;
    unsigned src_height = 0;
    int dst_width = 0;
    int dst_height = 0;
    float src_aspect = 0.0f;
    int scaled_width = 0;
    int scaled_height = 0;
    int offset_x = 0;
    int offset_y = 0;
    bool has_black_bars = false;
  } cpu_layout_cache_;
  uint32_t cpu_layout_recalc_log_count_ = 0;
  uint32_t hw_failure_streak_ = 0;
  uint32_t hw_failure_log_count_ = 0;
  // Default to GLES_SCALING as it provides the best balance of performance
  // (60FPS) and quality (Sharp)
  std::atomic<ScalingMode> scaling_mode_{ScalingMode::GLES_SCALING};

  std::atomic<unsigned> software_max_width_{1280};
  std::atomic<unsigned> software_max_height_{720};

  FramePacer framePacer_;

  std::atomic<bool> xengine_enabled_{false};
  std::atomic<bool> xengine_dirty_{false};

  // Audit T4-F5: Engine thread only — SetPixelFormat and Render() must both be called on Engine thread
  retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;

  // 渲染统计
  size_t frame_count_ = 0;
  size_t drop_count_ = 0;
  // Audit T4-F7: per-init "HW render present active" log throttle (replaces a
  // function-local `static bool logged` that survived destroy/reinit and silenced
  // the diagnostic forever after the first activation).
  size_t hw_present_log_count_ = 0;

  // Dupe 帧缓存
  mutable std::mutex frame_cache_mutex_;
  std::vector<uint8_t> lastFrame_;
  unsigned lastFrameWidth_ = 0;
  unsigned lastFrameHeight_ = 0;
  size_t lastFramePitch_ = 0;
  retro_pixel_format lastFramePixelFormat_ = RETRO_PIXEL_FORMAT_UNKNOWN;
  bool canDupe_ = true;

  // GLES 渲染器
  GLESRenderer gles_renderer_;
  GlesState gles_state_ = GlesState::UNINITIALIZED;
  unsigned gles_swap_fail_count_ = 0;
  size_t gles_surface_recreate_attempts_ = 0;
  size_t gles_surface_recreate_failures_ = 0;
  size_t gles_full_reinit_attempts_ = 0;
  size_t gles_full_reinit_failures_ = 0;
  size_t gles_auto_degrade_count_ = 0;
  std::chrono::steady_clock::time_point last_gles_init_fail_time_{};
  std::chrono::steady_clock::time_point gles_next_retry_time_{};
  uint32_t config_log_count_ = 0;
  std::chrono::steady_clock::time_point last_config_log_time_{};
  uint32_t render_log_count_ = 0;
  std::unique_ptr<GraphicsContext> graphics_context_;
  std::unique_ptr<HwRenderPresenter> hw_presenter_;
  std::unique_ptr<VulkanContext> vulkan_context_;
  std::unique_ptr<VulkanPresenter> vulkan_presenter_;
  std::unique_ptr<IRenderBackend> software_backend_;
  std::unique_ptr<IRenderBackend> gles_backend_;
  std::unique_ptr<IRenderBackend> hw_backend_;
  OHNativeWindow *hw_window_{nullptr};
  uint32_t vk_sync_index_{0};
  size_t vk_acquire_fail_count_{0};
  size_t vk_acquire_outdated_count_{0};
  size_t vk_present_fail_count_{0};
  std::chrono::steady_clock::time_point last_vk_swapchain_recreate_time_{};
  std::atomic<int> render_mode_state_{
      static_cast<int>(RenderModeState::GLES_READY)};
  ScalingMode degraded_from_mode_{ScalingMode::SOFTWARE_SCALING};
  std::chrono::steady_clock::time_point degrade_recover_after_{};
  uint32_t degrade_recover_attempts_{0};
  uint32_t degrade_recover_failures_{0};
  uint32_t degrade_state_log_count_{0};

public:
  void SetCanDupe(bool canDupe) {
    if (canDupe_ != canDupe) {
      canDupe_ = canDupe;
      ClearFrameCache();
    }
  }

  void ForceReconfiguration() { geometry_changed_.store(true); }

  void ClearFrameCache() {
    std::lock_guard<std::mutex> lock(frame_cache_mutex_);
    lastFrame_.clear();
    lastFrameWidth_ = 0;
    lastFrameHeight_ = 0;
    lastFramePitch_ = 0;
    lastFramePixelFormat_ = RETRO_PIXEL_FORMAT_UNKNOWN;
  }

  void Reset() {
    base_width_ = 0;
    base_height_ = 0;
    geometry_base_width_ = 0;
    geometry_base_height_ = 0;
    geometry_aspect_ratio_ = 0.0f;
    last_request_width_ = 0;
    last_request_height_ = 0;
    last_request_mode_ = scaling_mode_.load();
    window_width_.store(0);
    window_height_.store(0);
    geometry_changed_.store(false);
    ClearFrameCache();
    frame_count_ = 0;
    drop_count_ = 0;

    if (gles_state_ != GlesState::UNINITIALIZED) {
      gles_renderer_.Deinit();
      gles_state_ = GlesState::UNINITIALIZED;
    }
    gles_swap_fail_count_ = 0;
    gles_surface_recreate_attempts_ = 0;
    gles_surface_recreate_failures_ = 0;
    gles_full_reinit_attempts_ = 0;
    gles_full_reinit_failures_ = 0;
    gles_auto_degrade_count_ = 0;
    last_gles_init_fail_time_ = std::chrono::steady_clock::time_point{};
    gles_next_retry_time_ = std::chrono::steady_clock::time_point{};
    config_log_count_ = 0;
    last_config_log_time_ = std::chrono::steady_clock::time_point{};
    render_log_count_ = 0;
    cpu_backpressure_until_ = std::chrono::steady_clock::time_point{};
    cpu_request_slow_streak_ = 0;
    preflight_drop_log_count_ = 0;
    cpu_layout_cache_ = CpuLayoutCache{};
    cpu_layout_recalc_log_count_ = 0;
    hw_failure_streak_ = 0;
    hw_failure_log_count_ = 0;
    window_state_manager_.Reset();
    vk_sync_index_ = 0;
    vk_acquire_fail_count_ = 0;
    vk_acquire_outdated_count_ = 0;
    vk_present_fail_count_ = 0;
    last_vk_swapchain_recreate_time_ = std::chrono::steady_clock::time_point{};
    degraded_from_mode_ = ScalingMode::SOFTWARE_SCALING;
    degrade_recover_after_ = std::chrono::steady_clock::time_point{};
    degrade_recover_attempts_ = 0;
    degrade_recover_failures_ = 0;
    degrade_state_log_count_ = 0;
    const ScalingMode currentMode = scaling_mode_.load();
    RenderModeState state = RenderModeState::SW_READY;
    if (currentMode == ScalingMode::GLES_SCALING) {
      state = RenderModeState::GLES_READY;
    } else if (currentMode == ScalingMode::HARDWARE_SCALING) {
      state = RenderModeState::HW_READY;
    }
    render_mode_state_.store(static_cast<int>(state),
                             std::memory_order_release);
    if (software_backend_) {
      software_backend_->Reset();
    }
    if (gles_backend_) {
      gles_backend_->Reset();
    }
    if (hw_backend_) {
      hw_backend_->Reset();
    }
  }

  size_t GetDropCount() const { return drop_count_; }
  void ResetDropCount() { drop_count_ = 0; }
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_VIDEO_PIPELINE_H
