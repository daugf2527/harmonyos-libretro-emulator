#include "gles_renderer.h"
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <hilog/log.h>
#include <pthread.h>
#include <time.h>
#include <vector>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "GLESRenderer"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

// 兼容性定义
#ifndef GL_BGRA_EXT
#define GL_BGRA_EXT 0x80E1
#endif

namespace libretro {

namespace {
#if defined(__x86_64__) || defined(__i386__)
constexpr int kDefaultSwapInterval = 0;
#else
constexpr int kDefaultSwapInterval = 1;
#endif

constexpr size_t kDiagLogBurst = 3;
constexpr size_t kDiagLogInterval = 600;

int ClampSwapInterval(int interval) {
  return interval <= 0 ? 0 : 1;
}

bool ShouldLogSwapError(size_t &count) {
  count++;
  return count <= 5 || (count % 120) == 0;
}

bool IsRecoverableSwapError(EGLint err) {
  return err == EGL_BAD_SURFACE || err == EGL_BAD_NATIVE_WINDOW ||
         err == EGL_BAD_MATCH;
}

const char *EglErrorName(EGLint err) {
  switch (err) {
  case EGL_SUCCESS:
    return "EGL_SUCCESS";
  case EGL_NOT_INITIALIZED:
    return "EGL_NOT_INITIALIZED";
  case EGL_BAD_ACCESS:
    return "EGL_BAD_ACCESS";
  case EGL_BAD_ALLOC:
    return "EGL_BAD_ALLOC";
  case EGL_BAD_ATTRIBUTE:
    return "EGL_BAD_ATTRIBUTE";
  case EGL_BAD_CONTEXT:
    return "EGL_BAD_CONTEXT";
  case EGL_BAD_CONFIG:
    return "EGL_BAD_CONFIG";
  case EGL_BAD_CURRENT_SURFACE:
    return "EGL_BAD_CURRENT_SURFACE";
  case EGL_BAD_DISPLAY:
    return "EGL_BAD_DISPLAY";
  case EGL_BAD_SURFACE:
    return "EGL_BAD_SURFACE";
  case EGL_BAD_MATCH:
    return "EGL_BAD_MATCH";
  case EGL_BAD_PARAMETER:
    return "EGL_BAD_PARAMETER";
  case EGL_BAD_NATIVE_PIXMAP:
    return "EGL_BAD_NATIVE_PIXMAP";
  case EGL_BAD_NATIVE_WINDOW:
    return "EGL_BAD_NATIVE_WINDOW";
  case EGL_CONTEXT_LOST:
    return "EGL_CONTEXT_LOST";
  default:
    return "EGL_UNKNOWN";
  }
}
} // namespace

unsigned GLESRenderer::BeginUploadScratch() {
  const unsigned ringSize = static_cast<unsigned>(upload_scratch_ring_.size());
  if (ringSize == 0) {
    return 0;
  }

  auto ShouldLog = [](size_t &count) -> bool {
    count++;
    return count <= kDiagLogBurst || (count % kDiagLogInterval) == 0;
  };
  auto NowNs = []() -> uint64_t {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
        static_cast<uint64_t>(ts.tv_nsec);
  };

  // Try to find a free/safe slot without waiting.
  for (unsigned i = 0; i < ringSize; ++i) {
    const unsigned slot = (upload_ring_index_ + i) % ringSize;
    GLsync fence = upload_fence_ring_[slot];
    if (!fence) {
      if (ShouldLog(pbo_slot_log_count_)) {
        LOGF(LOG_INFO,
             "[GLES_DIAG] PBO slot free: slot=%{public}u ring_size=%{public}u index=%{public}u",
             slot, ringSize, upload_ring_index_);
      }
      upload_ring_index_ = (slot + 1) % ringSize;
      return slot;
    }

    const GLenum res = glClientWaitSync(fence, 0, 0);
    if (ShouldLog(pbo_wait_sample_log_count_)) {
      LOGF(LOG_INFO,
           "[GLES_DIAG] PBO wait (non-block) sample: slot=%{public}u res=%{public}u",
           slot, static_cast<unsigned>(res));
    }
    if (res == GL_WAIT_FAILED && ShouldLog(pbo_wait_log_count_)) {
      LOGF(LOG_WARN,
           "[GLES_DIAG] PBO wait (non-block) failed: slot=%{public}u err=0x%{public}X",
           slot, static_cast<unsigned>(glGetError()));
    }
    if (res == GL_ALREADY_SIGNALED || res == GL_CONDITION_SATISFIED) {
      glDeleteSync(fence);
      upload_fence_ring_[slot] = nullptr;
      upload_ring_index_ = (slot + 1) % ringSize;
      return slot;
    }
  }

  // All slots are still in use by GPU. Wait on the next slot deterministically.
  const unsigned slot = upload_ring_index_;
  if (ShouldLog(pbo_slot_log_count_)) {
    LOGF(LOG_INFO,
         "[GLES_DIAG] PBO all busy: ring_size=%{public}u wait_slot=%{public}u",
         ringSize, slot);
  }
  GLsync fence = upload_fence_ring_[slot];
  if (fence) {
    // Wait up to ~3 frames worth of time. This is a controlled, explainable
    // wait.
    uint64_t waitStart = NowNs();
    GLenum lastRes = GL_TIMEOUT_EXPIRED;
    for (int attempt = 0; attempt < 3; ++attempt) {
      const GLenum res =
          glClientWaitSync(fence, GL_SYNC_FLUSH_COMMANDS_BIT, 16000000ULL);
      lastRes = res;
      if (ShouldLog(pbo_wait_log_count_)) {
        LOGF(LOG_INFO,
             "[GLES_DIAG] PBO wait (block): slot=%{public}u attempt=%{public}d res=%{public}u",
             slot, attempt, static_cast<unsigned>(res));
      }
      if (res == GL_ALREADY_SIGNALED || res == GL_CONDITION_SATISFIED) {
        break;
      }
      if (res == GL_WAIT_FAILED && ShouldLog(pbo_wait_log_count_)) {
        LOGF(LOG_WARN,
             "[GLES_DIAG] PBO wait (block) failed: slot=%{public}u err=0x%{public}X",
             slot, static_cast<unsigned>(glGetError()));
      }
    }
    const uint64_t waitEnd = NowNs();
    if (lastRes != GL_ALREADY_SIGNALED && lastRes != GL_CONDITION_SATISFIED) {
      if (ShouldLog(pbo_wait_timeout_log_count_)) {
        LOGF(LOG_WARN,
             "[GLES_DIAG] PBO wait timeout: slot=%{public}u res=%{public}u "
             "dur_ns=%{public}u",
             slot, static_cast<unsigned>(lastRes),
             static_cast<unsigned>(waitEnd - waitStart));
      }
    }
    glDeleteSync(fence);
    upload_fence_ring_[slot] = nullptr;
  }

  upload_ring_index_ = (slot + 1) % ringSize;
  return slot;
}

void GLESRenderer::EndUploadScratch(unsigned slot) {
  if (slot >= upload_fence_ring_.size()) {
    return;
  }
  if (upload_fence_ring_[slot]) {
    glDeleteSync(upload_fence_ring_[slot]);
    upload_fence_ring_[slot] = nullptr;
  }
  upload_fence_ring_[slot] = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
  if (upload_fence_ring_[slot] == nullptr) {
    if (pbo_fence_log_count_ < 10 || (pbo_fence_log_count_ % 120) == 0) {
      pbo_fence_log_count_++;
      LOGF(LOG_WARN,
           "[GLES_DIAG] PBO fence create failed: slot=%{public}u err=0x%{public}X",
           slot, static_cast<unsigned>(glGetError()));
    }
  } else {
    if (pbo_fence_log_count_ < 5 || (pbo_fence_log_count_ % 120) == 0) {
      pbo_fence_log_count_++;
      LOGF(LOG_INFO,
           "[GLES_DIAG] PBO fence created: slot=%{public}u", slot);
    }
  }
}

// 顶点着色器：全屏四边形
// 简单的 Pass-through Shader，将顶点坐标和纹理坐标传递给片段着色器
static const char *VERTEX_SHADER_SOURCE = R"(#version 300 es
layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texCoord;
out vec2 v_texCoord;
void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texCoord = a_texCoord;
}
)";

// 片段着色器：支持通道交换 (Swizzle)
static const char *FRAGMENT_SHADER_SOURCE = R"(#version 300 es
precision mediump float;
in vec2 v_texCoord;
layout(location = 0) out vec4 outColor;
uniform sampler2D s_texture;
uniform int u_swizzle_rb; // 0 = Normal, 1 = Swap Red/Blue

void main() {
    vec4 texColor = texture(s_texture, v_texCoord);
    // 强制 Alpha = 1.0
    if (u_swizzle_rb == 1) {
         outColor = vec4(texColor.b, texColor.g, texColor.r, 1.0);
    } else {
         outColor = vec4(texColor.rgb, 1.0);
    }
}
)";

GLESRenderer::GLESRenderer()
    : program_(0, [](GLuint id) { glDeleteProgram(id); }),
      vao_(0, [](GLuint id) { glDeleteVertexArrays(1, &id); }),
      vbo_(0, [](GLuint id) { glDeleteBuffers(1, &id); }),
      texture_(0, [](GLuint id) { glDeleteTextures(1, &id); }),
      swap_interval_(kDefaultSwapInterval) {}

GLESRenderer::~GLESRenderer() { Deinit(); }

// 初始化 EGL 和 GLES 环境
// 必须在游戏线程调用，以确保 EGLContext 绑定在正确的线程上
bool GLESRenderer::Init(OHNativeWindow *window) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);

  if (!window) {
    return false;
  }

  // If already initialized for this window, do nothing
  if (window_ == window && egl_display_ != EGL_NO_DISPLAY) {
    return true;
  }

  // Use Deinit() to clean up previous state if any.
  // recursive_mutex allows this re-entrant lock.
  if (egl_display_ != EGL_NO_DISPLAY) {
    Deinit();
  }

  // 1. Create EGL Context
  if (!CreateEGLContext(window)) {
    LOGF(LOG_ERROR,
                 "Failed to create EGL context");
    return false;
  }

  // 2. Create Shader Program
  if (!CreateProgram()) {
    LOGF(LOG_ERROR,
                 "Failed to create shader program");
    Deinit();
    return false;
  }

  // 3. Setup Buffers (VAO/VBO/Texture)
  SetupBuffers();

  // 4. Check Optional Features
  CheckXEngineSupport();

  const char *glVersion = reinterpret_cast<const char *>(glGetString(GL_VERSION));
  const char *glRenderer = reinterpret_cast<const char *>(glGetString(GL_RENDERER));
  const char *glVendor = reinterpret_cast<const char *>(glGetString(GL_VENDOR));
  const char *glSlVersion =
      reinterpret_cast<const char *>(glGetString(GL_SHADING_LANGUAGE_VERSION));
  if (glVersion && glRenderer) {
    LOGF(LOG_INFO,
         "GLES info: %{public}s | %{public}s", glVersion, glRenderer);
  }
  if (glVendor) {
    LOGF(LOG_INFO, "[GLES_DIAG] GLES vendor: %{public}s", glVendor);
  }
  if (glSlVersion) {
    LOGF(LOG_INFO, "[GLES_DIAG] GLES GLSL: %{public}s", glSlVersion);
  }

  window_ = window;
  healthy_ = true;
  last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                        std::memory_order_release);
  last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                std::memory_order_release);
  LOGF(LOG_INFO,
               "GLESRenderer initialized successfully");
  return true;
}

void GLESRenderer::DestroySurfaceOnly() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (egl_display_ == EGL_NO_DISPLAY) {
    egl_surface_ = EGL_NO_SURFACE;
    return;
  }

  if (egl_surface_ != EGL_NO_SURFACE) {
    // Best-effort drain to reduce driver warnings like "host is using destroying surface".
    if (eglGetCurrentDisplay() == egl_display_ &&
        eglGetCurrentContext() == egl_context_) {
      glFinish();
    }

    // Make context not current before destroying surface
    eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);

    if (!eglDestroySurface(egl_display_, egl_surface_)) {
      EGLint err = eglGetError();
      LOGF(LOG_ERROR,
                   "eglDestroySurface failed: 0x%{public}x", err);
    }
    egl_surface_ = EGL_NO_SURFACE;
  }
}

bool GLESRenderer::RecreateSurface(OHNativeWindow *window) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (!window) {
    healthy_ = false;
    last_egl_error_.store(static_cast<int>(EGL_BAD_NATIVE_WINDOW),
                          std::memory_order_release);
    last_swap_failure_kind_.store(
        static_cast<int>(SwapFailureKind::RECOVERABLE_SURFACE),
        std::memory_order_release);
    return false;
  }
  if (egl_display_ == EGL_NO_DISPLAY || egl_context_ == EGL_NO_CONTEXT) {
    return Init(window);
  }
  DestroySurfaceOnly();

  egl_surface_ = eglCreateWindowSurface(egl_display_, egl_config_,
                                        (EGLNativeWindowType)window, nullptr);
  if (egl_surface_ == EGL_NO_SURFACE) {
    EGLint err = eglGetError();
    healthy_ = false;
    last_egl_error_.store(static_cast<int>(err), std::memory_order_release);
    last_swap_failure_kind_.store(
        static_cast<int>(SwapFailureKind::RECOVERABLE_SURFACE),
        std::memory_order_release);
    LOGF(LOG_ERROR,
                 "Failed to recreate EGL surface: 0x%{public}x", err);
    return false;
  }

  if (!eglMakeCurrent(egl_display_, egl_surface_, egl_surface_, egl_context_)) {
    EGLint err = eglGetError();
    healthy_ = false;
    last_egl_error_.store(static_cast<int>(err), std::memory_order_release);
    last_swap_failure_kind_.store(
        static_cast<int>(SwapFailureKind::RECOVERABLE_SURFACE),
        std::memory_order_release);
    LOGF(LOG_ERROR,
         "Failed to make EGL current after surface recreate: 0x%{public}x", err);
    eglDestroySurface(egl_display_, egl_surface_);
    egl_surface_ = EGL_NO_SURFACE;
    return false;
  }
  swap_interval_ = ClampSwapInterval(swap_interval_);
  eglSwapInterval(egl_display_, swap_interval_);

  EGLint w = 0, h = 0;
  if (eglQuerySurface(egl_display_, egl_surface_, EGL_WIDTH, &w) &&
      eglQuerySurface(egl_display_, egl_surface_, EGL_HEIGHT, &h)) {
    Resize(w, h);
    LOGF(LOG_INFO,
         "EGL surface recreated: window=%{public}p size=%{public}dx%{public}d",
         window, w, h);
  } else {
    LOGF(LOG_INFO,
                 "EGL surface recreated: window=%{public}p", window);
  }

  window_ = window;
  healthy_ = true;
  last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                        std::memory_order_release);
  last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                std::memory_order_release);
  return true;
}

void GLESRenderer::CheckXEngineSupport() {
  xengine_supported_ = false;
  xengine_handle_ = dlopen("libxengine.so", RTLD_LAZY);
  if (!xengine_handle_) {
    LOGF(LOG_WARN,
                 "dlopen libxengine.so failed");
    return;
  }

  hms_xeg_getString_ =
      (PFN_HMS_XEG_GETSTRING)dlsym(xengine_handle_, "HMS_XEG_GetString");
  hms_xeg_spatialUpscaleParameter_ = (PFN_HMS_XEG_SPATIALUPSCALEPARAMETER)dlsym(
      xengine_handle_, "HMS_XEG_SpatialUpscaleParameter");
  hms_xeg_renderSpatialUpscale_ = (PFN_HMS_XEG_RENDERSPATIALUPSCALE)dlsym(
      xengine_handle_, "HMS_XEG_RenderSpatialUpscale");

  if (hms_xeg_getString_ && hms_xeg_spatialUpscaleParameter_ &&
      hms_xeg_renderSpatialUpscale_) {
    const GLubyte *extensions = hms_xeg_getString_(XEG_EXTENSIONS);
    if (extensions) {
      std::string extStr = reinterpret_cast<const char *>(extensions);
      if (extStr.find(XEG_SPATIAL_UPSCALE_EXTENSION_NAME) !=
          std::string::npos) {
        xengine_supported_ = true;
        LOGF(LOG_INFO,
                     " XEngine Spatial Upscale Supported");
      } else {
        LOGF(LOG_WARN,
             " XEngine Spatial Upscale NOT Supported (Extension missing)");
        dlclose(xengine_handle_);
        xengine_handle_ = nullptr;
        hms_xeg_getString_ = nullptr;
        hms_xeg_spatialUpscaleParameter_ = nullptr;
        hms_xeg_renderSpatialUpscale_ = nullptr;
      }
    } else {
      LOGF(LOG_WARN,
           " XEngine Spatial Upscale NOT Supported (Extensions query failed)");
      dlclose(xengine_handle_);
      xengine_handle_ = nullptr;
      hms_xeg_getString_ = nullptr;
      hms_xeg_spatialUpscaleParameter_ = nullptr;
      hms_xeg_renderSpatialUpscale_ = nullptr;
    }
  } else {
    LOGF(LOG_WARN,
                 "Failed to resolve XEngine symbols");
    dlclose(xengine_handle_);
    xengine_handle_ = nullptr;
  }
}

void GLESRenderer::SetXEngineEnabled(bool enabled) {
  if (enabled && !xengine_supported_) {
    LOGF(LOG_WARN,
                 "Cannot enable XEngine: Not supported");
    return;
  }
  use_xengine_ = enabled;
  LOGF(LOG_INFO,
               "XEngine AI Upscale: %{public}s", enabled ? "ON" : "OFF");
}

// 动态设置 VSync
void GLESRenderer::SetSwapInterval(int interval) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  swap_interval_ = ClampSwapInterval(interval);
  if (egl_display_ != EGL_NO_DISPLAY && egl_context_ != EGL_NO_CONTEXT) {
    eglSwapInterval(egl_display_, swap_interval_);
    LOGF(LOG_INFO,
                 "VSync set to: %{public}d", swap_interval_);
  } else {
    LOGF(LOG_INFO, "VSync pending apply: %{public}d", swap_interval_);
  }
}

void GLESRenderer::SetDiagnosticsEnabled(bool enabled) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  diag_enabled_ = enabled;
  LOGF(LOG_INFO, "GLES diagnostics: %{public}s", enabled ? "ON" : "OFF");
}

void GLESRenderer::Deinit() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  healthy_ = true;
  last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                        std::memory_order_release);
  last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                std::memory_order_release);
  if (xengine_handle_) {
    dlclose(xengine_handle_);
    xengine_handle_ = nullptr;
    xengine_supported_ = false;
    hms_xeg_getString_ = nullptr;
    hms_xeg_spatialUpscaleParameter_ = nullptr;
    hms_xeg_renderSpatialUpscale_ = nullptr;
  }

  // ScopedGLObj 管理 GL 对象生命周期，这里显式 reset 以确保在 Deinit 时释放。

  // Make context current to allow safe deletion
  bool contextCurrent = false;
  if (egl_display_ != EGL_NO_DISPLAY && egl_context_ != EGL_NO_CONTEXT) {
    if (eglGetCurrentDisplay() == egl_display_ &&
        eglGetCurrentContext() == egl_context_) {
      glFinish();
    }
    contextCurrent = eglMakeCurrent(egl_display_, EGL_NO_SURFACE,
                                    EGL_NO_SURFACE, egl_context_);
  }

  if (!contextCurrent) {
    LOGF(LOG_ERROR,
         "EGL context not current during Deinit, releasing GL handles "
         "without glDelete* to avoid UB (resources will be reclaimed by "
         "EGL display teardown)");
    (void)texture_.release();
    (void)program_.release();
    (void)vbo_.release();
    (void)vao_.release();
    for (auto &f : upload_fence_ring_) {
      f = nullptr;  // 丢弃 fence sync 句柄
    }
    for (auto &pbo : pbo_ring_) {
      pbo = 0;  // 丢弃 PBO 句柄
    }
  } else {
    texture_.reset();
    program_.reset();
    vbo_.reset();
    vao_.reset();

    for (auto &f : upload_fence_ring_) {
      if (f) {
        glDeleteSync(f);
        f = nullptr;
      }
    }

    for (auto &pbo : pbo_ring_) {
      if (pbo != 0) {
        glDeleteBuffers(1, &pbo);
        pbo = 0;
      }
    }
  }

  if (egl_display_ != EGL_NO_DISPLAY) {
    eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);

    if (egl_surface_ != EGL_NO_SURFACE) {
      eglDestroySurface(egl_display_, egl_surface_);
    }
    egl_surface_ = EGL_NO_SURFACE;

    if (egl_context_ != EGL_NO_CONTEXT) {
      eglDestroyContext(egl_display_, egl_context_);
    }
    egl_context_ = EGL_NO_CONTEXT;

    eglTerminate(egl_display_);
  }

  egl_display_ = EGL_NO_DISPLAY;
  window_ = nullptr;

  tex_width_ = 0;
  tex_height_ = 0;
  current_format_ = RETRO_PIXEL_FORMAT_UNKNOWN;

  // Shrink memory
  for (auto &buf : upload_scratch_ring_) {
    buf.clear();
    buf.shrink_to_fit(); // [Fix Memory Leak]
  }
  upload_ring_index_ = 0;
  viewport_width_ = 0;
  viewport_height_ = 0;
  render_skip_log_count_ = 0;
  render_debug_log_count_ = 0;
  gl_error_log_count_ = 0;
  egl_swap_error_log_count_ = 0;
}

bool GLESRenderer::CreateEGLContext(OHNativeWindow *window) {
  egl_display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (egl_display_ == EGL_NO_DISPLAY) {
    return false;
  }

  EGLint major, minor;
  if (!eglInitialize(egl_display_, &major, &minor)) {
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  LOGF(LOG_INFO,
               "EGL init: display=%{public}p version=%{public}d.%{public}d",
               egl_display_, major, minor);

  // 配置属性：GLES 3.0, RGB888
  EGLint attribs[] = {EGL_RENDERABLE_TYPE,
                      EGL_OPENGL_ES3_BIT,
                      EGL_SURFACE_TYPE,
                      EGL_WINDOW_BIT,
                      EGL_RED_SIZE,
                      8,
                      EGL_GREEN_SIZE,
                      8,
                      EGL_BLUE_SIZE,
                      8,
                      EGL_ALPHA_SIZE,
                      8,
                      EGL_NONE};

  EGLint numConfigs;
  if (!eglChooseConfig(egl_display_, attribs, &egl_config_, 1, &numConfigs) ||
      numConfigs < 1) {
    LOGF(LOG_ERROR,
                 "Failed to choose EGL config");
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  if (!eglBindAPI(EGL_OPENGL_ES_API)) {
    LOGF(LOG_ERROR,
                 "eglBindAPI(EGL_OPENGL_ES_API) failed");
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  {
    EGLint r = 0, g = 0, b = 0, a = 0, d = 0, s = 0;
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_RED_SIZE, &r);
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_GREEN_SIZE, &g);
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_BLUE_SIZE, &b);
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_ALPHA_SIZE, &a);
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_DEPTH_SIZE, &d);
    eglGetConfigAttrib(egl_display_, egl_config_, EGL_STENCIL_SIZE, &s);
    LOGF(LOG_INFO,
                 "EGL config: num=%{public}d "
                 "RGBA=%{public}d/%{public}d/%{public}d/%{public}d "
                 "DS=%{public}d/%{public}d",
                 numConfigs, r, g, b, a, d, s);
  }

  EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  egl_context_ =
      eglCreateContext(egl_display_, egl_config_, EGL_NO_CONTEXT, ctxAttribs);
  if (egl_context_ == EGL_NO_CONTEXT) {
    EGLint err = eglGetError();
    LOGF(LOG_ERROR,
                 "Failed to create EGL context: 0x%{public}x", err);
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  egl_surface_ = eglCreateWindowSurface(egl_display_, egl_config_,
                                        (EGLNativeWindowType)window, nullptr);
  if (egl_surface_ == EGL_NO_SURFACE) {
    EGLint err = eglGetError();
    LOGF(LOG_ERROR,
                 "Failed to create EGL surface: 0x%{public}x", err);
    eglDestroyContext(egl_display_, egl_context_);
    egl_context_ = EGL_NO_CONTEXT;
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  LOGF(LOG_INFO,
               "EGL surface created: window=%{public}p surface=%{public}p "
               "context=%{public}p",
               window, egl_surface_, egl_context_);

  if (!eglMakeCurrent(egl_display_, egl_surface_, egl_surface_, egl_context_)) {
    EGLint err = eglGetError();
    LOGF(LOG_ERROR,
                 "Failed to make EGL current: 0x%{public}x", err);
    eglDestroySurface(egl_display_, egl_surface_);
    egl_surface_ = EGL_NO_SURFACE;
    eglDestroyContext(egl_display_, egl_context_);
    egl_context_ = EGL_NO_CONTEXT;
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
    return false;
  }

  swap_interval_ = ClampSwapInterval(swap_interval_);
  eglSwapInterval(egl_display_, swap_interval_);
  LOGF(LOG_INFO, "Swap interval initialized: %{public}d", swap_interval_);

  {
    EGLint w = 0, h = 0;
    if (eglQuerySurface(egl_display_, egl_surface_, EGL_WIDTH, &w) &&
        eglQuerySurface(egl_display_, egl_surface_, EGL_HEIGHT, &h)) {
      LOGF(LOG_INFO,
                   "EGL surface size: %{public}dx%{public}d", w, h);
      if (w > 0 && h > 0) {
        viewport_width_ = w;
        viewport_height_ = h;
        glViewport(0, 0, w, h);
        LOGF(LOG_INFO,
             "Viewport set: %{public}dx%{public}d", w, h);
      }
    }
  }

  return true;
}

GLuint GLESRenderer::CompileShader(GLenum type, const char *source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);

  GLint status;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
  if (!status) {
    char log[512];
    glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
    LOGF(LOG_ERROR,
                 "Shader compile error: %{public}s", log);
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

bool GLESRenderer::CreateProgram() {
  GLuint vs = CompileShader(GL_VERTEX_SHADER, VERTEX_SHADER_SOURCE);
  GLuint fs = CompileShader(GL_FRAGMENT_SHADER, FRAGMENT_SHADER_SOURCE);

  if (!vs || !fs) {
    if (vs) {
      glDeleteShader(vs);
    }
    if (fs) {
      glDeleteShader(fs);
    }
    return false;
  }

  GLuint p = glCreateProgram();
  glAttachShader(p, vs);
  glAttachShader(p, fs);
  glLinkProgram(p);

  GLint status;
  glGetProgramiv(p, GL_LINK_STATUS, &status);
  if (!status) {
    char log[512];
    glGetProgramInfoLog(p, sizeof(log), nullptr, log);
    LOGF(LOG_ERROR,
                 "Program link error: %{public}s", log);
    glDeleteProgram(p);
    glDeleteShader(vs);
    glDeleteShader(fs);
    return false;
  }

  program_.reset(p); // 转移所有权

  glUseProgram(program_);
  sampler_loc_ = glGetUniformLocation(program_, "s_texture");
  uniform_swizzle_loc_ = glGetUniformLocation(program_, "u_swizzle_rb");

  if (sampler_loc_ >= 0) {
    glUniform1i(sampler_loc_, 0);
  } else {
    LOGF(LOG_WARN,
                 "Uniform not found: s_texture");
  }

  // Set default swizzle
  if (uniform_swizzle_loc_ >= 0) {
    glUniform1i(uniform_swizzle_loc_, 0);
  }

  glDeleteShader(vs);
  glDeleteShader(fs);
  return true;
}

void GLESRenderer::SetupBuffers() {
  float vertices[] = {
      // Position(XY)   // TexCoord(UV)
      -1.0f, 1.0f,  0.0f, 0.0f, // Top Left
      -1.0f, -1.0f, 0.0f, 1.0f, // Bottom Left
      1.0f,  1.0f,  1.0f, 0.0f, // Top Right
      1.0f,  -1.0f, 1.0f, 1.0f, // Bottom Right
  };

  GLuint _vao;
  glGenVertexArrays(1, &_vao);
  glBindVertexArray(_vao);
  vao_.reset(_vao);

  GLuint _vbo;
  glGenBuffers(1, &_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, _vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
  vbo_.reset(_vbo);

  // Pos
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void *)0);
  glEnableVertexAttribArray(0);

  // UV
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                        (void *)(2 * sizeof(float)));
  glEnableVertexAttribArray(1);

  // Texture
  GLuint _tex;
  glGenTextures(1, &_tex);
  glBindTexture(GL_TEXTURE_2D, _tex);
  texture_.reset(_tex); // 托管

  // 关键：最近邻插值实现锐利像素
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

void GLESRenderer::Resize(int width, int height) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  viewport_width_ = width;
  viewport_height_ = height;
  glViewport(0, 0, width, height);
}

void GLESRenderer::Render(const void *data, unsigned width, unsigned height,
                          size_t pitch, retro_pixel_format format,
                          float content_aspect_ratio, bool is_dupe) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (is_dupe &&
      (tex_width_ == 0 || tex_height_ == 0 ||
       current_format_ == RETRO_PIXEL_FORMAT_UNKNOWN)) {
    return;
  }
  if ((!is_dupe && !data) || width == 0 || height == 0 || !healthy_ || !window_) {
    render_skip_log_count_++;
    if (render_skip_log_count_ <= 5 ||
        (render_skip_log_count_ % 120) == 0) {
      LOGF(LOG_WARN,
           "GLES render skipped: data=%{public}d size=%{public}ux%{public}u "
           "healthy=%{public}d window=%{public}p dupe=%{public}d",
           data ? 1 : 0, width, height, healthy_ ? 1 : 0, window_, is_dupe ? 1 : 0);
    }
    return;
  }

  glUseProgram(program_);
  glBindVertexArray(vao_);

  // Clear background
  glClear(GL_COLOR_BUFFER_BIT);

  // 1. Calculate Aspect Ratio
  float srcAspect = content_aspect_ratio;
  if (!(srcAspect > 0.0f)) {
    srcAspect = static_cast<float>(width) / static_cast<float>(height);
  }
  float dstAspect = 1.0f;
  if (viewport_width_ > 0 && viewport_height_ > 0) {
    dstAspect = static_cast<float>(viewport_width_) /
                static_cast<float>(viewport_height_);
  }

  float scaleX = 1.0f;
  float scaleY = 1.0f;
  if (dstAspect > srcAspect) {
    scaleX = srcAspect / dstAspect;
  } else if (dstAspect < srcAspect) {
    scaleY = dstAspect / srcAspect;
  }

  const float vertices[] = {
      -scaleX, scaleY,  0.0f, 0.0f, // TL
      -scaleX, -scaleY, 0.0f, 1.0f, // BL
      scaleX,  scaleY,  1.0f, 0.0f, // TR
      scaleX,  -scaleY, 1.0f, 1.0f, // BR
  };
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(vertices), vertices);

  // 2. Texture Upload (Zero Copy Optimized)
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, texture_);

  // Determine GL Format based on Retro Format
  GLenum internalFormat = GL_RGB;
  GLenum pixelFormat = GL_RGB;
  GLenum pixelType = GL_UNSIGNED_BYTE;
  int alignment = 4;
  bool swizzleRB = false;

  switch (format) {
  case RETRO_PIXEL_FORMAT_RGB565:
    alignment = 2; // 16-bit
    internalFormat = GL_RGB565;
    pixelFormat = GL_RGB;
    pixelType = GL_UNSIGNED_SHORT_5_6_5;
    break;
  case RETRO_PIXEL_FORMAT_0RGB1555:
    alignment = 2;
    internalFormat = GL_RGB5_A1;
    pixelFormat = GL_RGBA;
    pixelType = GL_UNSIGNED_SHORT_5_5_5_1;
    break;
  case RETRO_PIXEL_FORMAT_XRGB8888:
    alignment = 4;
    internalFormat = GL_RGBA8;
    pixelFormat = GL_RGBA;
    pixelType = GL_UNSIGNED_BYTE;
    // Use shader swizzle for RB swap
    swizzleRB = true;
    break;
  default:
    return; // Unknown
  }

  // Set Shader State
  if (uniform_swizzle_loc_ >= 0) {
    glUniform1i(uniform_swizzle_loc_, swizzleRB ? 1 : 0);
  }

  const bool diagEnabled = diag_enabled_;

  auto LogGlError = [&](const char *stage) {
    if (!diagEnabled) {
      return;
    }
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
      gl_error_log_count_++;
      if (gl_error_log_count_ <= kDiagLogBurst ||
          (gl_error_log_count_ % kDiagLogInterval) == 0) {
        LOGF(LOG_ERROR,
             "GL error after %{public}s: 0x%{public}x", stage, err);
      }
    } else {
      gl_error_sample_log_count_++;
      if (gl_error_sample_log_count_ <= kDiagLogBurst ||
          (gl_error_sample_log_count_ % kDiagLogInterval) == 0) {
        LOGF(LOG_INFO,
             "[GLES_DIAG] GL ok after %{public}s", stage);
      }
    }
  };

  auto ClearGlErrors = [&]() {
    if (!diagEnabled) {
      return;
    }
    while (glGetError() != GL_NO_ERROR) {
    }
  };

  // 3. Handle Pitch (Stride) and PBO Upload
  const unsigned long frameId = ++render_frame_id_;
  auto NowNs = []() -> uint64_t {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
        static_cast<uint64_t>(ts.tv_nsec);
  };
  auto ShouldLog = [](size_t &count) -> bool {
    count++;
    return count <= kDiagLogBurst || (count % kDiagLogInterval) == 0;
  };
  if (diagEnabled && (render_stage_log_count_ < kDiagLogBurst ||
      (render_stage_log_count_ % kDiagLogInterval) == 0)) {
    render_stage_log_count_++;
    LOGF(LOG_INFO,
         "[GLES_DIAG] GLES frame begin: id=%{public}lu dupe=%{public}d size=%{public}ux%{public}u",
         frameId, is_dupe ? 1 : 0, width, height);
  }

  if (!is_dupe) {
    const int bpp = (alignment == 2) ? 2 : 4;
    const int rowLength = static_cast<int>(pitch / bpp);
    const size_t dataSize = pitch * height;

    const void *uploadData = data;
    thread_local std::vector<uint16_t> rgb1555_conv_buf;
    if (format == RETRO_PIXEL_FORMAT_0RGB1555 && data) {
      const size_t pixelCount = dataSize / 2;
      rgb1555_conv_buf.resize(pixelCount);
      const auto *src = static_cast<const uint16_t *>(data);
      for (size_t i = 0; i < pixelCount; ++i) {
        rgb1555_conv_buf[i] = static_cast<uint16_t>((src[i] << 1) | 1);
      }
      uploadData = rgb1555_conv_buf.data();
    }

    if (diagEnabled && ShouldLog(render_param_log_count_)) {
      unsigned long tid = static_cast<unsigned long>(pthread_self());
      LOGF(LOG_INFO,
           "[GLES_DIAG] GLES render params: data=%{public}p size=%{public}ux%{public}u "
           "pitch=%{public}zu row=%{public}d bpp=%{public}d fmt=%{public}d "
           "dupe=%{public}d viewport=%{public}dx%{public}d window=%{public}p "
           "tid=%{public}lu",
           data, width, height, pitch, rowLength, bpp,
           static_cast<int>(format), is_dupe ? 1 : 0,
           viewport_width_, viewport_height_, window_, tid);
    }

    if (diagEnabled && ShouldLog(render_ctx_log_count_)) {
      EGLDisplay curDisplay = eglGetCurrentDisplay();
      EGLContext curContext = eglGetCurrentContext();
      EGLSurface curDraw = eglGetCurrentSurface(EGL_DRAW);
      EGLSurface curRead = eglGetCurrentSurface(EGL_READ);
      LOGF(LOG_INFO,
           "[GLES_DIAG] GLES context: cur_display=%{public}p cur_context=%{public}p "
           "cur_draw=%{public}p cur_read=%{public}p "
           "egl_display=%{public}p egl_context=%{public}p egl_surface=%{public}p",
           curDisplay, curContext, curDraw, curRead,
           egl_display_, egl_context_, egl_surface_);
    }

    // Driver compatibility path:
    // For some Harmony devices/simulators, PBO upload path can produce noisy
    // driver-side diagnostics. Use direct texture upload for stable behavior.
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    GLenum errUnpackBind = GL_NO_ERROR;
    if (diagEnabled) {
      errUnpackBind = glGetError();
    }
    if (diagEnabled && errUnpackBind != GL_NO_ERROR &&
        ShouldLog(pbo_error_log_count_)) {
      LOGF(LOG_WARN,
           "[GLES_DIAG] direct upload: unbind unpack buffer failed err=0x%{public}X",
           static_cast<unsigned>(errUnpackBind));
    }

    ClearGlErrors();

    int unpackAlignment = 1;
    if ((pitch % 4) == 0) {
      unpackAlignment = 4;
    } else if ((pitch % 2) == 0) {
      unpackAlignment = 2;
    }

    GLint prevUnpackAlignment = 4;
    GLint prevUnpackRowLength = 0;
    if (diagEnabled) {
      glGetIntegerv(GL_UNPACK_ALIGNMENT, &prevUnpackAlignment);
      glGetIntegerv(GL_UNPACK_ROW_LENGTH, &prevUnpackRowLength);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlignment);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
    LogGlError("pixel_store");
    if (diagEnabled && ShouldLog(pbo_unpack_log_count_)) {
      GLint curAlign = 0;
      GLint curRowLen = 0;
      glGetIntegerv(GL_UNPACK_ALIGNMENT, &curAlign);
      GLenum errAlign = glGetError();
      glGetIntegerv(GL_UNPACK_ROW_LENGTH, &curRowLen);
      GLenum errRow = glGetError();
      LOGF(LOG_INFO,
           "[GLES_DIAG] upload unpack: align=%{public}d row_len=%{public}d "
           "err_align=0x%{public}X err_row=0x%{public}X",
           curAlign, curRowLen,
           static_cast<unsigned>(errAlign),
           static_cast<unsigned>(errRow));
    }

    if (render_debug_log_count_ < 3) {
      render_debug_log_count_++;
      LOGF(LOG_INFO,
           "GLES direct render: size=%{public}u row=%{public}d "
           "fmt=%{public}d align=%{public}d",
           static_cast<unsigned>(dataSize), rowLength,
           static_cast<int>(format), unpackAlignment);
    }

    // Direct Texture Upload from client memory
    GLint boundTex = 0;
    GLenum errTexBind = GL_NO_ERROR;
    if (diagEnabled) {
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &boundTex);
      errTexBind = glGetError();
    }

    const bool useTexImage = (width != tex_width_ || height != tex_height_ ||
        format != current_format_);
    const uint64_t texStart = NowNs();
    if (useTexImage) {
      glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, width, height, 0,
                   pixelFormat, pixelType, uploadData);
      tex_width_ = width;
      tex_height_ = height;
      current_format_ = format;
    } else {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, pixelFormat,
                      pixelType, uploadData);
    }
    const uint64_t texEnd = NowNs();
    if (diagEnabled && ShouldLog(pbo_tex_log_count_)) {
      LOGF(LOG_INFO,
           "[GLES_DIAG] tex upload (direct): path=%{public}s size=%{public}ux%{public}u "
           "fmt=%{public}d type=%{public}u bound_tex=%{public}d "
           "err_tex_bind=0x%{public}X",
           useTexImage ? "TexImage" : "TexSubImage",
           width, height, static_cast<int>(format),
           static_cast<unsigned>(pixelType), boundTex,
           static_cast<unsigned>(errTexBind));
    }
    if (diagEnabled && ShouldLog(pbo_tex_timing_log_count_)) {
      LOGF(LOG_INFO,
           "[GLES_DIAG] tex time (direct): frame=%{public}lu path=%{public}s "
           "ns=%{public}u",
           frameId, useTexImage ? "TexImage" : "TexSubImage",
           static_cast<unsigned>(texEnd - texStart));
    }
    LogGlError("tex_upload");

    glPixelStorei(GL_UNPACK_ROW_LENGTH, prevUnpackRowLength);
    glPixelStorei(GL_UNPACK_ALIGNMENT, prevUnpackAlignment);
  }

  // XEngine hook
  if (use_xengine_ && xengine_supported_ && hms_xeg_spatialUpscaleParameter_ &&
      hms_xeg_renderSpatialUpscale_) {
    GLfloat sharpness = 0.3f;
    hms_xeg_spatialUpscaleParameter_(XEG_SPATIAL_UPSCALE_SHARPNESS, &sharpness);
    hms_xeg_renderSpatialUpscale_(texture_);
  } else {
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  }
  LogGlError("draw");

  // Swap Buffers
  const uint64_t swapStart = NowNs();
  const EGLBoolean swapOk = eglSwapBuffers(egl_display_, egl_surface_);
  const uint64_t swapEnd = NowNs();
  if (!swapOk) {
    EGLint err = eglGetError();
    last_egl_error_.store(static_cast<int>(err), std::memory_order_release);
    if (err == EGL_CONTEXT_LOST) {
      healthy_ = false;
      last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::CONTEXT_LOST),
                                    std::memory_order_release);
      if (ShouldLogSwapError(egl_swap_error_log_count_)) {
        LOGF(LOG_ERROR, "EGL Context Lost: 0x%{public}x (%{public}s)", err,
             EglErrorName(err));
      }
    } else if (IsRecoverableSwapError(err)) {
      healthy_ = false;
      last_swap_failure_kind_.store(
          static_cast<int>(SwapFailureKind::RECOVERABLE_SURFACE),
          std::memory_order_release);
      if (ShouldLogSwapError(egl_swap_error_log_count_)) {
        LOGF(LOG_WARN,
             "eglSwapBuffers recoverable failure: 0x%{public}x (%{public}s), "
             "mark surface lost",
             err, EglErrorName(err));
      }
    } else {
      healthy_ = false;
      last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::FATAL),
                                    std::memory_order_release);
      if (ShouldLogSwapError(egl_swap_error_log_count_)) {
        LOGF(LOG_ERROR, "eglSwapBuffers failed: 0x%{public}x (%{public}s)",
             err, EglErrorName(err));
      }
    }
  } else {
    last_egl_error_.store(static_cast<int>(EGL_SUCCESS),
                          std::memory_order_release);
    last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE),
                                  std::memory_order_release);
    egl_swap_log_count_++;
    if (diagEnabled && (egl_swap_log_count_ <= kDiagLogBurst ||
        (egl_swap_log_count_ % kDiagLogInterval) == 0)) {
      LOGF(LOG_INFO,
           "[GLES_DIAG] eglSwapBuffers ok: frame=%{public}lu", frameId);
    }
  }
  if (diagEnabled && ShouldLog(swap_timing_log_count_)) {
    LOGF(LOG_INFO,
         "[GLES_DIAG] eglSwapBuffers time: frame=%{public}lu ok=%{public}d "
         "ns=%{public}u",
         frameId, swapOk ? 1 : 0,
         static_cast<unsigned>(swapEnd - swapStart));
  }

  if (diagEnabled && (render_stage_log_count_ < kDiagLogBurst ||
      (render_stage_log_count_ % kDiagLogInterval) == 0)) {
    render_stage_log_count_++;
    LOGF(LOG_INFO,
         "[GLES_DIAG] GLES frame end: id=%{public}lu", frameId);
  }
}

} // namespace libretro
