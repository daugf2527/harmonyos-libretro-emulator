#ifndef LIBRETRO_ENGINE_WINDOW_STATE_MANAGER_H
#define LIBRETRO_ENGINE_WINDOW_STATE_MANAGER_H

#include <cstdint>
#include <functional>
#include <native_window/external_window.h>

namespace libretro {

class WindowStateManager {
public:
  struct WindowState {
    unsigned width = 0;
    unsigned height = 0;
    uint64_t usage = 0;
    int swap_interval = -1;
    int source_type = -1;
    int scaling_mode = -1;
  };

  struct ApplyResult {
    bool geometry_ok = true;
    bool usage_ok = true;
    bool swap_ok = true;
    bool source_ok = true;
    bool scaling_ok = true;
  };

  void Reset();
  ApplyResult Apply(OHNativeWindow *window, const WindowState &state,
                    const std::function<void(const char *, int32_t, int32_t)>
                        &on_fail);
  void ResetToDefaults(OHNativeWindow *window);

private:
  WindowState last_state_{};
  bool has_state_ = false;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_WINDOW_STATE_MANAGER_H
