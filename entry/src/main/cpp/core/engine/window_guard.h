#ifndef LIBRETRO_ENGINE_WINDOW_GUARD_H
#define LIBRETRO_ENGINE_WINDOW_GUARD_H

#include <mutex>
#include <native_window/external_window.h>

namespace libretro {

/**
 * @brief WindowGuard 负责 OHNativeWindow 的线程安全访问。
 * 核心设计：
 * 1. UI 线程销毁窗口时持有锁并清空指针。
 * 2. 游戏线程渲染时持有锁并获取指针。
 * 3. 显式引用计数管理。
 */
class WindowGuard {
public:
  WindowGuard() : window_(nullptr) {}
  ~WindowGuard() { SetWindow(nullptr); }

  /**
   * @brief 设置或清空 NativeWindow（UI 线程调用）
   */
  void SetWindow(OHNativeWindow *window) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (window_ == window) {
      return;
    }

    if (window_) {
      OH_NativeWindow_NativeObjectUnreference(window_);
    }

    window_ = window;

    if (window_) {
      OH_NativeWindow_NativeObjectReference(window_);
    }
  }

  /**
   * @brief RAII wrapper for safely holding a window reference
   */
  class ScopedWindow {
  public:
    ScopedWindow(OHNativeWindow *window) : window_(window) {
      if (window_) {
        OH_NativeWindow_NativeObjectReference(window_);
      }
    }

    ~ScopedWindow() {
      if (window_) {
        OH_NativeWindow_NativeObjectUnreference(window_);
      }
    }

    // Disable copy
    ScopedWindow(const ScopedWindow &) = delete;
    ScopedWindow &operator=(const ScopedWindow &) = delete;

    // Enable move
    ScopedWindow(ScopedWindow &&other) noexcept : window_(other.window_) {
      other.window_ = nullptr;
    }
    ScopedWindow &operator=(ScopedWindow &&other) noexcept {
      if (this != &other) {
        if (window_) {
          OH_NativeWindow_NativeObjectUnreference(window_);
        }
        window_ = other.window_;
        other.window_ = nullptr;
      }
      return *this;
    }

    OHNativeWindow *Get() const { return window_; }
    operator bool() const { return window_ != nullptr; }

  private:
    OHNativeWindow *window_;
  };

  /**
   * @brief Safely acquire the window with reference counting.
   * The returned ScopedWindow holds a strong reference to the native window,
   * preventing it from being destroyed while in use.
   */
  ScopedWindow AcquireWindow() {
    std::lock_guard<std::mutex> lock(mutex_);
    return ScopedWindow(window_);
  }

  /**
   * @brief 获取锁引用，由调用方控制临界区
   */
  std::mutex &GetMutex() { return mutex_; }

private:
  OHNativeWindow *PeekWindow() {
    return window_;
  }

  OHNativeWindow *window_;
  std::mutex mutex_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_WINDOW_GUARD_H
