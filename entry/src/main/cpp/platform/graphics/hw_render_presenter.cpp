#include "hw_render_presenter.h"
#include <algorithm>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "HwRenderPresenter"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

namespace {

bool HasExtension(const char *ext_name) {
  const char *ext = reinterpret_cast<const char *>(glGetString(GL_EXTENSIONS));
  if (!ext || !ext_name || ext_name[0] == '\0') {
    return false;
  }
  const char *start = ext;
  size_t name_len = strlen(ext_name);
  while (true) {
    const char *pos = strstr(start, ext_name);
    if (!pos) {
      return false;
    }
    const char *end = pos + name_len;
    if ((pos == ext || pos[-1] == ' ') && (*end == ' ' || *end == '\0')) {
      return true;
    }
    start = end;
  }
}

struct GLStateBackup {
  GLint program = 0;
  GLint array_buffer = 0;
  GLint framebuffer = 0;
  GLint active_texture = 0;
  GLint texture_binding = 0;
  GLint viewport[4] = {0, 0, 0, 0};
  GLfloat clear_color[4] = {0.0f, 0.0f, 0.0f, 0.0f};
  GLboolean blend = GL_FALSE;
  GLboolean depth_test = GL_FALSE;
  GLboolean scissor = GL_FALSE;
  GLboolean cull = GL_FALSE;
  GLint attrib0_enabled = 0;
  GLint attrib1_enabled = 0;
};

GLStateBackup CaptureState(GLint attrib_pos, GLint attrib_tex) {
  GLStateBackup state;
  glGetIntegerv(GL_CURRENT_PROGRAM, &state.program);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &state.array_buffer);
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &state.framebuffer);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &state.active_texture);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &state.texture_binding);
  glGetIntegerv(GL_VIEWPORT, state.viewport);
  glGetFloatv(GL_COLOR_CLEAR_VALUE, state.clear_color);
  state.blend = glIsEnabled(GL_BLEND);
  state.depth_test = glIsEnabled(GL_DEPTH_TEST);
  state.scissor = glIsEnabled(GL_SCISSOR_TEST);
  state.cull = glIsEnabled(GL_CULL_FACE);
  if (attrib_pos >= 0) {
    glGetVertexAttribiv(attrib_pos, GL_VERTEX_ATTRIB_ARRAY_ENABLED,
                        &state.attrib0_enabled);
  }
  if (attrib_tex >= 0) {
    glGetVertexAttribiv(attrib_tex, GL_VERTEX_ATTRIB_ARRAY_ENABLED,
                        &state.attrib1_enabled);
  }
  return state;
}

void RestoreState(const GLStateBackup &state, GLint attrib_pos,
                  GLint attrib_tex) {
  if (attrib_pos >= 0 && !state.attrib0_enabled) {
    glDisableVertexAttribArray(attrib_pos);
  }
  if (attrib_tex >= 0 && !state.attrib1_enabled) {
    glDisableVertexAttribArray(attrib_tex);
  }
  glUseProgram(state.program);
  glBindBuffer(GL_ARRAY_BUFFER, state.array_buffer);
  glBindFramebuffer(GL_FRAMEBUFFER, state.framebuffer);
  glActiveTexture(state.active_texture);
  glBindTexture(GL_TEXTURE_2D, state.texture_binding);
  glViewport(state.viewport[0], state.viewport[1], state.viewport[2],
             state.viewport[3]);
  glClearColor(state.clear_color[0], state.clear_color[1],
               state.clear_color[2], state.clear_color[3]);
  if (state.blend)
    glEnable(GL_BLEND);
  else
    glDisable(GL_BLEND);
  if (state.depth_test)
    glEnable(GL_DEPTH_TEST);
  else
    glDisable(GL_DEPTH_TEST);
  if (state.scissor)
    glEnable(GL_SCISSOR_TEST);
  else
    glDisable(GL_SCISSOR_TEST);
  if (state.cull)
    glEnable(GL_CULL_FACE);
  else
    glDisable(GL_CULL_FACE);
}

} // namespace

HwRenderPresenter::~HwRenderPresenter() { Destroy(); }

bool HwRenderPresenter::Initialize(unsigned target_width, unsigned target_height,
                                   const HwRenderConfig &config) {
  config_ = config;
  if (target_width == 0 || target_height == 0) {
    LOGF(LOG_ERROR,
                 "Invalid HW render target size: %{public}ux%{public}u",
                 target_width, target_height);
    return false;
  }

  if (!CreateProgram()) {
    return false;
  }

  if (!CreateRenderTarget(target_width, target_height)) {
    DestroyProgram();
    return false;
  }

  if (vbo_ == 0) {
    glGenBuffers(1, &vbo_);
  }

  target_width_ = target_width;
  target_height_ = target_height;
  ready_ = true;
  return true;
}

void HwRenderPresenter::Destroy() {
  DestroyRenderTarget();
  DestroyProgram();
  if (vbo_ != 0) {
    glDeleteBuffers(1, &vbo_);
    vbo_ = 0;
  }
  ready_ = false;
}

bool HwRenderPresenter::EnsureTarget(unsigned target_width,
                                     unsigned target_height,
                                     const HwRenderConfig &config) {
  if (!ready_) {
    return Initialize(target_width, target_height, config);
  }

  bool program_change = (config.use_es3 != config_.use_es3);
  bool depth_change = (config.depth != config_.depth ||
                       config.stencil != config_.stencil);

  config_.bottom_left_origin = config.bottom_left_origin;
  config_.use_es3 = config.use_es3;
  config_.depth = config.depth;
  config_.stencil = config.stencil;

  if (program_change) {
    DestroyProgram();
    if (!CreateProgram()) {
      ready_ = false;
      return false;
    }
  }

  if (depth_change || target_width != target_width_ ||
      target_height != target_height_) {
    if (!CreateRenderTarget(target_width, target_height)) {
      ready_ = false;
      return false;
    }
    target_width_ = target_width;
    target_height_ = target_height;
  }

  return true;
}

void HwRenderPresenter::Present(int viewport_width, int viewport_height,
                                float content_aspect_ratio,
                                unsigned content_width,
                                unsigned content_height) {
  if (!ready_) {
    return;
  }
  if (viewport_width <= 0 || viewport_height <= 0) {
    return;
  }

  const float src_width =
      content_width > 0 ? static_cast<float>(content_width)
                        : static_cast<float>(target_width_);
  const float src_height =
      content_height > 0 ? static_cast<float>(content_height)
                         : static_cast<float>(target_height_);
  float src_aspect = content_aspect_ratio;
  if (!(src_aspect > 0.0f) && src_width > 0.0f && src_height > 0.0f) {
    src_aspect = src_width / src_height;
  }

  float dst_aspect = static_cast<float>(viewport_width) /
                     static_cast<float>(viewport_height);
  float scale_x = 1.0f;
  float scale_y = 1.0f;
  if (src_aspect > 0.0f) {
    if (dst_aspect > src_aspect) {
      scale_x = src_aspect / dst_aspect;
    } else if (dst_aspect < src_aspect) {
      scale_y = dst_aspect / src_aspect;
    }
  }

  float u_max = 1.0f;
  float v_max = 1.0f;
  if (target_width_ > 0 && target_height_ > 0 && src_width > 0.0f &&
      src_height > 0.0f) {
    u_max = std::min(1.0f, src_width / static_cast<float>(target_width_));
    v_max = std::min(1.0f, src_height / static_cast<float>(target_height_));
  }

  const float v_top = config_.bottom_left_origin ? v_max : 0.0f;
  const float v_bottom = config_.bottom_left_origin ? 0.0f : v_max;

  // GLStateBackup state = CaptureState(attrib_pos_, attrib_tex_); // Removed to avoid pipeline stall

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, viewport_width, viewport_height);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(program_);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  UpdateQuad(scale_x, scale_y, u_max, v_top, v_bottom);

  if (attrib_pos_ >= 0) {
    glEnableVertexAttribArray(attrib_pos_);
    glVertexAttribPointer(attrib_pos_, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(float), reinterpret_cast<void *>(0));
  }
  if (attrib_tex_ >= 0) {
    glEnableVertexAttribArray(attrib_tex_);
    glVertexAttribPointer(attrib_tex_, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(float),
                          reinterpret_cast<void *>(2 * sizeof(float)));
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, color_tex_);
  if (uniform_tex_ >= 0) {
    glUniform1i(uniform_tex_, 0);
  }

  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  // RestoreState(state, attrib_pos_, attrib_tex_); // Removed
  // Restore FBO binding for the core
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
}

bool HwRenderPresenter::CreateProgram() {
  if (program_ != 0) {
    return true;
  }

  const char *vs_es3 =
      "#version 300 es\n"
      "layout(location=0) in vec2 aPos;\n"
      "layout(location=1) in vec2 aTex;\n"
      "out vec2 vTex;\n"
      "void main() {\n"
      "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
      "  vTex = aTex;\n"
      "}\n";

  const char *fs_es3 =
      "#version 300 es\n"
      "precision mediump float;\n"
      "in vec2 vTex;\n"
      "uniform sampler2D uTex;\n"
      "out vec4 fragColor;\n"
      "void main() {\n"
      "  fragColor = texture(uTex, vTex);\n"
      "}\n";

  const char *vs_es2 =
      "attribute vec2 aPos;\n"
      "attribute vec2 aTex;\n"
      "varying vec2 vTex;\n"
      "void main() {\n"
      "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
      "  vTex = aTex;\n"
      "}\n";

  const char *fs_es2 =
      "precision mediump float;\n"
      "varying vec2 vTex;\n"
      "uniform sampler2D uTex;\n"
      "void main() {\n"
      "  gl_FragColor = texture2D(uTex, vTex);\n"
      "}\n";

  const char *vs_src = config_.use_es3 ? vs_es3 : vs_es2;
  const char *fs_src = config_.use_es3 ? fs_es3 : fs_es2;

  GLuint vs = glCreateShader(GL_VERTEX_SHADER);
  glShaderSource(vs, 1, &vs_src, nullptr);
  glCompileShader(vs);
  GLint vs_ok = GL_FALSE;
  glGetShaderiv(vs, GL_COMPILE_STATUS, &vs_ok);
  if (vs_ok != GL_TRUE) {
    char log[512] = {0};
    glGetShaderInfoLog(vs, sizeof(log) - 1, nullptr, log);
    LOGF(LOG_ERROR,
                 "HW renderer vertex shader compile failed: %{public}s",
                 log);
    glDeleteShader(vs);
    return false;
  }

  GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(fs, 1, &fs_src, nullptr);
  glCompileShader(fs);
  GLint fs_ok = GL_FALSE;
  glGetShaderiv(fs, GL_COMPILE_STATUS, &fs_ok);
  if (fs_ok != GL_TRUE) {
    char log[512] = {0};
    glGetShaderInfoLog(fs, sizeof(log) - 1, nullptr, log);
    LOGF(LOG_ERROR,
                 "HW renderer fragment shader compile failed: %{public}s",
                 log);
    glDeleteShader(vs);
    glDeleteShader(fs);
    return false;
  }

  program_ = glCreateProgram();
  glAttachShader(program_, vs);
  glAttachShader(program_, fs);
  glLinkProgram(program_);
  GLint link_ok = GL_FALSE;
  glGetProgramiv(program_, GL_LINK_STATUS, &link_ok);
  glDeleteShader(vs);
  glDeleteShader(fs);
  if (link_ok != GL_TRUE) {
    char log[512] = {0};
    glGetProgramInfoLog(program_, sizeof(log) - 1, nullptr, log);
    LOGF(LOG_ERROR,
                 "HW renderer program link failed: %{public}s",
                 log);
    glDeleteProgram(program_);
    program_ = 0;
    return false;
  }

  attrib_pos_ = glGetAttribLocation(program_, "aPos");
  attrib_tex_ = glGetAttribLocation(program_, "aTex");
  uniform_tex_ = glGetUniformLocation(program_, "uTex");
  return true;
}

void HwRenderPresenter::DestroyProgram() {
  if (program_ != 0) {
    glDeleteProgram(program_);
    program_ = 0;
  }
  attrib_pos_ = -1;
  attrib_tex_ = -1;
  uniform_tex_ = -1;
}

bool HwRenderPresenter::CreateRenderTarget(unsigned width, unsigned height) {
  DestroyRenderTarget();

  glGenFramebuffers(1, &framebuffer_);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);

  glGenTextures(1, &color_tex_);
  glBindTexture(GL_TEXTURE_2D, color_tex_);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, nullptr);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         color_tex_, 0);

  if (config_.depth || config_.stencil) {
    bool packed_ok = config_.use_es3 ||
                     HasExtension("GL_OES_packed_depth_stencil") ||
                     HasExtension("GL_EXT_packed_depth_stencil");
    if (config_.depth && config_.stencil && packed_ok) {
      glGenRenderbuffers(1, &depth_rb_);
      glBindRenderbuffer(GL_RENDERBUFFER, depth_rb_);
      glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width,
                            height);
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                GL_RENDERBUFFER, depth_rb_);
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                                GL_RENDERBUFFER, depth_rb_);
    } else {
      if (config_.depth) {
        glGenRenderbuffers(1, &depth_rb_);
        glBindRenderbuffer(GL_RENDERBUFFER, depth_rb_);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width,
                              height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                  GL_RENDERBUFFER, depth_rb_);
      }
      if (config_.stencil) {
        glGenRenderbuffers(1, &stencil_rb_);
        glBindRenderbuffer(GL_RENDERBUFFER, stencil_rb_);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width,
                              height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                                  GL_RENDERBUFFER, stencil_rb_);
      }
    }
  }

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    LOGF(LOG_WARN,
                 "HW render FBO incomplete: 0x%{public}x. Fallback to color only",
                 status);
    DestroyRenderTarget();

    glGenFramebuffers(1, &framebuffer_);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
    glGenTextures(1, &color_tex_);
    glBindTexture(GL_TEXTURE_2D, color_tex_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, color_tex_, 0);
    status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      LOGF(LOG_ERROR,
                   "HW render FBO creation failed: 0x%{public}x", status);
      DestroyRenderTarget();
      return false;
    }
  }

  LOGF(LOG_INFO,
               "HW render FBO created: %{public}ux%{public}u depth=%{public}d stencil=%{public}d",
               width, height, config_.depth, config_.stencil);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return true;
}

void HwRenderPresenter::DestroyRenderTarget() {
  if (depth_rb_ != 0) {
    glDeleteRenderbuffers(1, &depth_rb_);
    depth_rb_ = 0;
  }
  if (stencil_rb_ != 0) {
    glDeleteRenderbuffers(1, &stencil_rb_);
    stencil_rb_ = 0;
  }
  if (color_tex_ != 0) {
    glDeleteTextures(1, &color_tex_);
    color_tex_ = 0;
  }
  if (framebuffer_ != 0) {
    glDeleteFramebuffers(1, &framebuffer_);
    framebuffer_ = 0;
  }
}

void HwRenderPresenter::UpdateQuad(float scale_x, float scale_y, float u_max,
                                   float v_top, float v_bottom) {
  const float vertices[] = {
      -scale_x, scale_y, 0.0f, v_top,    // TL
      -scale_x, -scale_y, 0.0f, v_bottom, // BL
      scale_x,  scale_y, u_max, v_top,   // TR
      scale_x,  -scale_y, u_max, v_bottom, // BR
  };
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
}

} // namespace libretro
