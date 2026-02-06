#ifndef PLATFORM_GRAPHICS_GRAPHICS_CONTEXT_H
#define PLATFORM_GRAPHICS_GRAPHICS_CONTEXT_H

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <native_window/external_window.h>

namespace libretro {

struct GraphicsConfig {
  bool gl_es3 = true; // Prefer GLES 3.0
  bool vsync = true;  // Enable VSync
  bool debug = false; // Enable Debug Context (if supported)
  int depth_bits = 0; // Depth buffer bits (0 = disable)
  int stencil_bits = 0; // Stencil buffer bits (0 = disable)
};

/**
 * @brief GraphicsContext
 * Manages EGL Display, Context, and Surface lifecycle.
 * Provides a unified interface for initializing hardware rendering.
 */
class GraphicsContext {
public:
  GraphicsContext();
  ~GraphicsContext();

  /**
   * @brief Initialize EGL context and surface for the given window.
   * @param window Raw NativeWindow pointer.
   * @param config EGL Configuration settings.
   * @return true if successful.
   */
  bool Initialize(OHNativeWindow *window, const GraphicsConfig &config);

  /**
   * @brief Destroy EGL context and surface.
   */
  void Destroy();

  /**
   * @brief Swap front and back buffers.
   */
  bool SwapBuffers();

  /**
   * @brief Recreate surface if window changed (Handle window
   * resize/reconfiguration).
   */
  bool UpdateSurface(OHNativeWindow *window);

  // Getters
  bool IsReady() const { return ready_; }
  bool HasContext() const { return egl_context_ != EGL_NO_CONTEXT; }
  bool IsConfigCompatible(const GraphicsConfig &config) const {
    return currentConfig_.gl_es3 == config.gl_es3 &&
           currentConfig_.vsync == config.vsync &&
           currentConfig_.debug == config.debug &&
           currentConfig_.depth_bits == config.depth_bits &&
           currentConfig_.stencil_bits == config.stencil_bits;
  }
  int GetWidth() const { return width_; }
  int GetHeight() const { return height_; }

  void ReleaseSurface();

private:
  bool CreateContext(const GraphicsConfig &config);
  bool CreateSurface(OHNativeWindow *window);
  void DestroySurface();

  EGLDisplay egl_display_ = EGL_NO_DISPLAY;
  EGLConfig egl_config_ = nullptr;
  EGLContext egl_context_ = EGL_NO_CONTEXT;
  EGLSurface egl_surface_ = EGL_NO_SURFACE;

  bool ready_ = false;
  int width_ = 0;
  int height_ = 0;

  // Config cache to recreate surface
  GraphicsConfig currentConfig_;
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_GRAPHICS_CONTEXT_H
