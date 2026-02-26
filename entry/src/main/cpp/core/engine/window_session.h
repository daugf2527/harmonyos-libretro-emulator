#ifndef LIBRETRO_ENGINE_WINDOW_SESSION_H
#define LIBRETRO_ENGINE_WINDOW_SESSION_H

#include <cstdint>
#include <native_window/external_window.h>

namespace libretro {

enum class WindowSessionState : uint8_t {
  DETACHED = 0,
  ATTACHED_PENDING_SIZE = 1,
  READY = 2,
  PAUSED_SURFACE = 3,
  DESTROYED = 4,
};

struct WindowSession {
  uint64_t sessionId = 0;
  uint64_t generation = 0;
  WindowSessionState state = WindowSessionState::DETACHED;
  int width = 0;
  int height = 0;
  bool active = false;
  OHNativeWindow *window = nullptr;

  bool IsRenderable() const {
    return window != nullptr && active && state == WindowSessionState::READY &&
           width > 0 && height > 0;
  }
};

const char *WindowSessionStateToString(WindowSessionState state);

} // namespace libretro

#endif // LIBRETRO_ENGINE_WINDOW_SESSION_H
