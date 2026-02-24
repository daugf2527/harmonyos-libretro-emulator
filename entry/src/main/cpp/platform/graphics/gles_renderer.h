#ifndef PLATFORM_GRAPHICS_GLES_RENDERER_H
#define PLATFORM_GRAPHICS_GLES_RENDERER_H

#include "libretro/libretro.h"
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <array>
#include <native_window/external_window.h>
#include <string>
#include <vector>
#include <xengine/xeg_gles_extension.h>
#include <xengine/xeg_gles_spatial_upscale.h>

#include <functional>
#include <mutex>

namespace libretro {

// RAII Wrapper for GL Objects
template <typename T> class ScopedGLObj {
public:
  using Deleter = std::function<void(T)>;
  ScopedGLObj() : id_(0), deleter_([](T) {}) {}
  ScopedGLObj(T id, Deleter d) : id_(id), deleter_(d) {}
  ~ScopedGLObj() {
    if (id_)
      deleter_(id_);
  }

  // Disable copy
  ScopedGLObj(const ScopedGLObj &) = delete;
  ScopedGLObj &operator=(const ScopedGLObj &) = delete;

  // Enable move
  ScopedGLObj(ScopedGLObj &&other) noexcept
      : id_(other.id_), deleter_(other.deleter_) {
    other.id_ = 0;
  }
  ScopedGLObj &operator=(ScopedGLObj &&other) noexcept {
    if (this != &other) {
      if (id_)
        deleter_(id_);
      id_ = other.id_;
      deleter_ = other.deleter_;
      other.id_ = 0;
    }
    return *this;
  }

  T get() const { return id_; }
  operator T() const { return id_; }
  void reset(T new_id = 0) {
    if (id_)
      deleter_(id_);
    id_ = new_id;
  }

private:
  T id_;
  Deleter deleter_;
};

class GLESRenderer {
public:
  GLESRenderer();
  ~GLESRenderer();

  bool Init(OHNativeWindow *window);
  bool RecreateSurface(OHNativeWindow *window);
  void Deinit();
  void DestroySurfaceOnly();
  void Resize(int width, int height);

  // Uploads texture and draws the quad
  void Render(const void *data, unsigned width, unsigned height, size_t pitch,
              retro_pixel_format format, float content_aspect_ratio, bool is_dupe = false);

  // Swap Interval Control (VSync)
  // interval: 0 = Disable VSync (Turbo), 1 = Enable VSync (Normal)
  void SetSwapInterval(int interval);

  // XEngine Control
  void SetXEngineEnabled(bool enabled);
  bool IsXEngineSupported() const { return xengine_supported_; }
  bool IsHealthy() const { return healthy_; }

private:
  unsigned BeginUploadScratch();
  void EndUploadScratch(unsigned slot);

  bool CreateEGLContext(OHNativeWindow *window);
  bool CreateProgram();
  GLuint CompileShader(GLenum type, const char *source);
  void SetupBuffers();
  void CheckXEngineSupport();

  std::recursive_mutex mutex_;
  OHNativeWindow *window_ = nullptr;

  // EGL State
  EGLDisplay egl_display_ = EGL_NO_DISPLAY;
  EGLConfig egl_config_;
  EGLContext egl_context_ = EGL_NO_CONTEXT;
  EGLSurface egl_surface_ = EGL_NO_SURFACE;

  // GL State
  ScopedGLObj<GLuint> program_;
  ScopedGLObj<GLuint> vao_;
  ScopedGLObj<GLuint> vbo_;
  ScopedGLObj<GLuint> texture_;
  GLint sampler_loc_ = -1;
  GLint uniform_swizzle_loc_ = -1; // New: RB Swizzle Uniform

  // Texture State
  unsigned tex_width_ = 0;
  unsigned tex_height_ = 0;
  retro_pixel_format current_format_ = RETRO_PIXEL_FORMAT_UNKNOWN;

  std::array<std::vector<uint8_t>, 3> upload_scratch_ring_;
  std::array<GLuint, 3> pbo_ring_{0, 0, 0};
  std::array<GLsync, 3> upload_fence_ring_{{nullptr, nullptr, nullptr}};
  unsigned upload_ring_index_ = 0;

  // Render State
  int viewport_width_ = 0;
  int viewport_height_ = 0;
  size_t render_skip_log_count_ = 0;
  size_t render_debug_log_count_ = 0;
  size_t gl_error_log_count_ = 0;
  size_t pbo_debug_log_count_ = 0;
  size_t pbo_error_log_count_ = 0;
  size_t pbo_wait_log_count_ = 0;
  size_t pbo_wait_sample_log_count_ = 0;
  size_t pbo_fence_log_count_ = 0;
  size_t pbo_slot_log_count_ = 0;
  size_t render_param_log_count_ = 0;
  size_t pbo_map_detail_log_count_ = 0;
  size_t pbo_unmap_detail_log_count_ = 0;
  size_t pbo_tex_log_count_ = 0;
  size_t render_ctx_log_count_ = 0;
  size_t pbo_unpack_log_count_ = 0;
  size_t pbo_buffer_param_log_count_ = 0;
  size_t pbo_fence_state_log_count_ = 0;
  size_t render_stage_log_count_ = 0;
  size_t egl_swap_log_count_ = 0;
  size_t gl_error_sample_log_count_ = 0;
  unsigned long render_frame_id_ = 0;
  size_t pbo_wait_timeout_log_count_ = 0;
  size_t pbo_timing_log_count_ = 0;
  size_t pbo_tex_timing_log_count_ = 0;
  size_t swap_timing_log_count_ = 0;
  int swap_interval_ = 1;

  // XEngine State
  bool xengine_supported_ = false;
  bool use_xengine_ = false;
  void *xengine_handle_ = nullptr;

  bool healthy_ = true;

  // XEngine Function Pointers
  typedef const GLubyte *(*PFN_HMS_XEG_GETSTRING)(GLenum name);
  typedef void (*PFN_HMS_XEG_SPATIALUPSCALEPARAMETER)(GLenum pname,
                                                      const GLfloat *params);
  typedef void (*PFN_HMS_XEG_RENDERSPATIALUPSCALE)(GLuint texture);

  PFN_HMS_XEG_GETSTRING hms_xeg_getString_ = nullptr;
  PFN_HMS_XEG_SPATIALUPSCALEPARAMETER hms_xeg_spatialUpscaleParameter_ =
      nullptr;
  PFN_HMS_XEG_RENDERSPATIALUPSCALE hms_xeg_renderSpatialUpscale_ = nullptr;
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_GLES_RENDERER_H
