#ifndef PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H
#define PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H

#include <functional>
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

  NativeVSyncDriver() = default;
  ~NativeVSyncDriver();

  NativeVSyncDriver(const NativeVSyncDriver &) = delete;
  NativeVSyncDriver &operator=(const NativeVSyncDriver &) = delete;

  bool Start(const std::string &name, const FrameCallback &callback);
  void Stop();
  bool RequestNextFrame();
  bool IsRunning() const;

private:
#if LIBRETRO_HAS_NATIVE_VSYNC
  static void OnFrame(long long timestamp, void *data);
#endif

  mutable std::mutex mutex_;
  FrameCallback callback_;
  OH_NativeVSync *nativeVsync_ = nullptr;
  bool running_ = false;
};

} // namespace libretro

#endif // PLATFORM_SYNC_NATIVE_VSYNC_DRIVER_H
