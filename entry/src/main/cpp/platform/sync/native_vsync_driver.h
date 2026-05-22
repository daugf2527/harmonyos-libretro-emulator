#ifndef PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H
#define PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

#if defined(__has_include)
#if __has_include(<native_vsync/native_vsync.h>)
#include <native_vsync/native_vsync.h>
#define LIBRETRO_HAS_NATIVE_VSYNC 1
#else
#define LIBRETRO_HAS_NATIVE_VSYNC 0
struct OH_NativeVSync;
#endif
#else
#define LIBRETRO_HAS_NATIVE_VSYNC 0
struct OH_NativeVSync;
#endif

namespace libretro {

class NativeVSyncDriver {
public:
  using FrameCallback = std::function<void(long long)>;

  NativeVSyncDriver();
  ~NativeVSyncDriver();

  NativeVSyncDriver(const NativeVSyncDriver &) = delete;
  NativeVSyncDriver &operator=(const NativeVSyncDriver &) = delete;

  bool Start(const std::string &name, const FrameCallback &callback);
  void Stop();
  bool RequestNextFrame();
  bool IsRunning() const;

private:
  // Lifecycle token,通过 shared_ptr 持有,保证残留 vsync 回调可安全检测
  // NativeVSyncDriver 是否仍存活,避免析构后 OH_NativeVSync_Destroy 未取消的
  // pending 回调造成 use-after-free。
  struct Alive {
    std::atomic<bool> v{true};
  };

  struct CallbackContext {
    std::weak_ptr<Alive> alive;
    NativeVSyncDriver *self;
  };

#if LIBRETRO_HAS_NATIVE_VSYNC
  static void OnFrame(long long timestamp, void *data);
#endif

  mutable std::mutex mutex_;
  FrameCallback callback_;
  OH_NativeVSync *nativeVsync_ = nullptr;
  bool running_ = false;
  std::shared_ptr<Alive> alive_;
  std::unique_ptr<CallbackContext> callbackContext_;
};

} // namespace libretro

#endif // PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H
