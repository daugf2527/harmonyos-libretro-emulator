#include "graphics_context.h"
#include <GLES3/gl3.h> // For GL_TRUE/FALSE if needed, or mostly EGL here.
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "GraphicsContext"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

GraphicsContext::GraphicsContext() = default;

GraphicsContext::~GraphicsContext() { Destroy(); }

bool GraphicsContext::Initialize(OHNativeWindow *window,
                                 const GraphicsConfig &config) {
  if (!window)
    return false;

  currentConfig_ = config;

  // 1. Initialize Display
  if (egl_display_ == EGL_NO_DISPLAY) {
    egl_display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (egl_display_ == EGL_NO_DISPLAY) {
      LOGF(LOG_ERROR,
                   "Failed to get EGL display");
      return false;
    }

    EGLint major, minor;
    if (!eglInitialize(egl_display_, &major, &minor)) {
      LOGF(LOG_ERROR,
                   "Failed to initialize EGL");
      eglTerminate(egl_display_);
      egl_display_ = EGL_NO_DISPLAY;
      return false;
    }
    LOGF(LOG_INFO,
                 "EGL Initialized: %{public}d.%{public}d", major, minor);
  }

  // 2. Create Context (if not exists)
  if (egl_context_ == EGL_NO_CONTEXT) {
    if (!CreateContext(config)) {
      return false;
    }
  }

  // 3. Create Surface
  if (!CreateSurface(window)) {
    return false;
  }

  ready_ = true;
  return true;
}

bool GraphicsContext::CreateContext(const GraphicsConfig &config) {
  EGLint depth = config.depth_bits;
  EGLint stencil = config.stencil_bits;
  EGLint attribs[] = {EGL_RENDERABLE_TYPE,
                      config.gl_es3 ? EGL_OPENGL_ES3_BIT : EGL_OPENGL_ES2_BIT,
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
                      EGL_DEPTH_SIZE,
                      depth,
                      EGL_STENCIL_SIZE,
                      stencil,
                      EGL_NONE};

  EGLint numConfigs = 0;
  if (!eglChooseConfig(egl_display_, attribs, &egl_config_, 1, &numConfigs) ||
      numConfigs < 1) {
    if (depth != 0 || stencil != 0) {
      LOGF(LOG_WARN,
                   "Failed to choose EGL config with depth=%{public}d stencil=%{public}d, fallback to 0",
                   depth, stencil);
      depth = 0;
      stencil = 0;
      for (int i = 0; attribs[i] != EGL_NONE; i += 2) {
        if (attribs[i] == EGL_DEPTH_SIZE) attribs[i + 1] = 0;
        if (attribs[i] == EGL_STENCIL_SIZE) attribs[i + 1] = 0;
      }
      currentConfig_.depth_bits = 0;
      currentConfig_.stencil_bits = 0;
      if (!eglChooseConfig(egl_display_, attribs, &egl_config_, 1, &numConfigs) ||
          numConfigs < 1) {
        LOGF(LOG_ERROR,
                     "Failed to choose EGL config");
        return false;
      }
    } else {
      LOGF(LOG_ERROR,
                   "Failed to choose EGL config");
      return false;
    }
  }

  if (!eglBindAPI(EGL_OPENGL_ES_API)) {
    LOGF(LOG_ERROR,
                 "Failed to bind OpenGL ES API");
    return false;
  }

  EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, config.gl_es3 ? 3 : 2,
                         EGL_NONE};

  egl_context_ =
      eglCreateContext(egl_display_, egl_config_, EGL_NO_CONTEXT, ctxAttribs);
  if (egl_context_ == EGL_NO_CONTEXT) {
    // Fallback to ES2 if ES3 failed but was requested?
    // For now, adhere to config strictness or logic from GLESRenderer which
    // tries fallback.
    if (config.gl_es3) {
      LOGF(LOG_WARN,
                   "Failed to create ES3 context, trying ES2...");
      EGLint ctxAttribs2[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
      egl_context_ = eglCreateContext(egl_display_, egl_config_, EGL_NO_CONTEXT,
                                      ctxAttribs2);
      if (egl_context_ != EGL_NO_CONTEXT) {
        currentConfig_.gl_es3 = false;
      }
    }

    if (egl_context_ == EGL_NO_CONTEXT) {
      LOGF(LOG_ERROR,
                   "Failed to create EGL context");
      return false;
    }
  }
  return true;
}

bool GraphicsContext::CreateSurface(OHNativeWindow *window) {
  if (egl_surface_ != EGL_NO_SURFACE) {
    DestroySurface();
  }

  egl_surface_ = eglCreateWindowSurface(egl_display_, egl_config_,
                                        (EGLNativeWindowType)window, nullptr);
  if (egl_surface_ == EGL_NO_SURFACE) {
    LOGF(LOG_ERROR,
                 "Failed to create EGL surface");
    return false;
  }

  if (!eglMakeCurrent(egl_display_, egl_surface_, egl_surface_, egl_context_)) {
    LOGF(LOG_ERROR,
                 "Failed to make context current");
    DestroySurface();
    return false;
  }

  // Apply VSync Config
  eglSwapInterval(egl_display_, currentConfig_.vsync ? 1 : 0);
  LOGF(LOG_INFO,
               "VSync enabled: %{public}d", currentConfig_.vsync ? 1 : 0);

  eglQuerySurface(egl_display_, egl_surface_, EGL_WIDTH, &width_);
  eglQuerySurface(egl_display_, egl_surface_, EGL_HEIGHT, &height_);

  return true;
}

void GraphicsContext::DestroySurface() {
  if (egl_display_ == EGL_NO_DISPLAY)
    return;

  eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  if (egl_surface_ != EGL_NO_SURFACE) {
    eglDestroySurface(egl_display_, egl_surface_);
    egl_surface_ = EGL_NO_SURFACE;
  }
}

void GraphicsContext::Destroy() {
  DestroySurface();

  if (egl_display_ != EGL_NO_DISPLAY) {
    if (egl_context_ != EGL_NO_CONTEXT) {
      eglDestroyContext(egl_display_, egl_context_);
      egl_context_ = EGL_NO_CONTEXT;
    }
    eglTerminate(egl_display_);
    egl_display_ = EGL_NO_DISPLAY;
  }
  ready_ = false;
}

bool GraphicsContext::SwapBuffers() {
  if (!ready_ || egl_display_ == EGL_NO_DISPLAY ||
      egl_surface_ == EGL_NO_SURFACE) {
    return false;
  }
  if (!eglSwapBuffers(egl_display_, egl_surface_)) {
    EGLint err = eglGetError();
    LOGF(LOG_ERROR,
                 "SwapBuffers failed: 0x%{public}x", err);
    return false;
  }
  return true;
}

bool GraphicsContext::UpdateSurface(OHNativeWindow *window) {
  // Recreate surface simply calls CreateSurface which handles destruction of
  // old one. Assuming context is preserved.
  return CreateSurface(window);
}

void GraphicsContext::ReleaseSurface() {
  DestroySurface();
  ready_ = false;
  width_ = 0;
  height_ = 0;
}

} // namespace libretro
