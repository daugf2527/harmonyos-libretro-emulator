#ifndef PLATFORM_GRAPHICS_HW_RENDER_PRESENTER_H
#define PLATFORM_GRAPHICS_HW_RENDER_PRESENTER_H

#include <GLES3/gl3.h>
#include <cstdint>

namespace libretro {

struct HwRenderConfig {
  bool use_es3 = true;
  bool depth = false;
  bool stencil = false;
  bool bottom_left_origin = true;
};

class HwRenderPresenter {
public:
  HwRenderPresenter() = default;
  ~HwRenderPresenter();

  bool Initialize(unsigned target_width, unsigned target_height,
                  const HwRenderConfig &config);
  void Destroy();
  bool EnsureTarget(unsigned target_width, unsigned target_height,
                    const HwRenderConfig &config);

  bool IsReady() const { return ready_; }
  uintptr_t GetFramebuffer() const { return ready_ ? framebuffer_ : 0; }

  void Present(int viewport_width, int viewport_height,
               float content_aspect_ratio, unsigned content_width,
               unsigned content_height);

private:
  bool CreateProgram();
  void DestroyProgram();
  bool CreateRenderTarget(unsigned width, unsigned height);
  void DestroyRenderTarget();
  void UpdateQuad(float scale_x, float scale_y, float u_max, float v_top,
                  float v_bottom);

  HwRenderConfig config_{};
  bool ready_ = false;
  unsigned target_width_ = 0;
  unsigned target_height_ = 0;

  GLuint framebuffer_ = 0;
  GLuint color_tex_ = 0;
  GLuint depth_rb_ = 0;
  GLuint stencil_rb_ = 0;
  GLuint program_ = 0;
  GLuint vbo_ = 0;

  GLint attrib_pos_ = -1;
  GLint attrib_tex_ = -1;
  GLint uniform_tex_ = -1;
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_HW_RENDER_PRESENTER_H
