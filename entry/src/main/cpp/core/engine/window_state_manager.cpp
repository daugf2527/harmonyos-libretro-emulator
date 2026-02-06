#include "window_state_manager.h"
#include <native_buffer/native_buffer.h>

// Define SET_BUFFER_GEOMETRY if not available in SDK headers
#ifndef SET_BUFFER_GEOMETRY
#define SET_BUFFER_GEOMETRY 0
#endif

#ifndef SET_SWAP_INTERVAL
#define SET_SWAP_INTERVAL 8
#endif

namespace libretro {

void WindowStateManager::Reset() {
  has_state_ = false;
  last_state_ = WindowState{};
}

WindowStateManager::ApplyResult WindowStateManager::Apply(
    OHNativeWindow *window, const WindowState &state,
    const std::function<void(const char *, int32_t, int32_t)> &on_fail) {
  ApplyResult result{};
  if (!window) {
    result.geometry_ok = false;
    return result;
  }

  if (state.width > 0 && state.height > 0) {
    const int32_t err = OH_NativeWindow_NativeWindowHandleOpt(
        window, SET_BUFFER_GEOMETRY, state.width, state.height);
    result.geometry_ok = (err == 0);
    if (!result.geometry_ok && on_fail) {
      on_fail("SET_BUFFER_GEOMETRY", SET_BUFFER_GEOMETRY, err);
    }
  } else {
    result.geometry_ok = false;
    if (on_fail) {
      on_fail("SET_BUFFER_GEOMETRY", SET_BUFFER_GEOMETRY, -1);
    }
  }

  if (state.usage != 0) {
    const int32_t err =
        OH_NativeWindow_NativeWindowHandleOpt(window, SET_USAGE, state.usage);
    result.usage_ok = (err == 0);
    if (!result.usage_ok && on_fail) {
      on_fail("SET_USAGE", SET_USAGE, err);
    }
  }

  if (state.swap_interval >= 0) {
    const int32_t err = OH_NativeWindow_NativeWindowHandleOpt(
        window, SET_SWAP_INTERVAL, state.swap_interval);
    result.swap_ok = (err == 0);
    if (!result.swap_ok && on_fail) {
      on_fail("SET_SWAP_INTERVAL", SET_SWAP_INTERVAL, err);
    }
  }

  if (state.source_type >= 0) {
    const int32_t err = OH_NativeWindow_NativeWindowHandleOpt(
        window, SET_SOURCE_TYPE, state.source_type);
    result.source_ok = (err == 0);
    if (!result.source_ok && on_fail) {
      on_fail("SET_SOURCE_TYPE", SET_SOURCE_TYPE, err);
    }
  }

  if (state.scaling_mode >= 0) {
    const int max_mode = static_cast<int>(OH_SCALING_MODE_SCALE_FIT_V2);
    if (state.scaling_mode > max_mode) {
      result.scaling_ok = false;
      if (on_fail) {
        on_fail("SET_SCALING_MODE", state.scaling_mode, -1);
      }
    } else {
      const auto mode = static_cast<OHScalingModeV2>(state.scaling_mode);
      const int32_t err =
          OH_NativeWindow_NativeWindowSetScalingModeV2(window, mode);
      result.scaling_ok = (err == 0);
      if (!result.scaling_ok && on_fail) {
        on_fail("SET_SCALING_MODE", state.scaling_mode, err);
      }
    }
  }

  if (result.geometry_ok && result.usage_ok && result.swap_ok &&
      result.source_ok && result.scaling_ok) {
    last_state_ = state;
    has_state_ = true;
  }

  return result;
}

void WindowStateManager::ResetToDefaults(OHNativeWindow *window) {
  if (!window) {
    return;
  }
  WindowState state{};
  state.width = 1;
  state.height = 1;
  state.usage = NATIVEBUFFER_USAGE_CPU_WRITE;
  state.scaling_mode = OH_SCALING_MODE_SCALE_TO_WINDOW_V2;
  Apply(window, state, nullptr);
  has_state_ = false;
}

} // namespace libretro
