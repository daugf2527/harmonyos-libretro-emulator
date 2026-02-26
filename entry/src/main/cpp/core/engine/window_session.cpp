#include "window_session.h"

namespace libretro {

const char *WindowSessionStateToString(WindowSessionState state) {
  switch (state) {
  case WindowSessionState::DETACHED:
    return "detached";
  case WindowSessionState::ATTACHED_PENDING_SIZE:
    return "attached_pending_size";
  case WindowSessionState::READY:
    return "ready";
  case WindowSessionState::PAUSED_SURFACE:
    return "paused_surface";
  case WindowSessionState::DESTROYED:
    return "destroyed";
  default:
    return "unknown";
  }
}

} // namespace libretro
