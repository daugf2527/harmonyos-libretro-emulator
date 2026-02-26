#include "native_vsync_driver.h"

#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "NativeVSyncDrv"
#undef LOG_FLOW
#define LOG_FLOW "VSync"
#include "common/log_prefix.h"

namespace libretro {

NativeVSyncDriver::~NativeVSyncDriver() { Stop(); }

bool NativeVSyncDriver::Start(const std::string &name,
                              const FrameCallback &callback) {
  std::lock_guard<std::mutex> lock(mutex_);
  callback_ = callback;

#if LIBRETRO_HAS_NATIVE_VSYNC
  if (running_) {
    return true;
  }

  std::string usedName = name.empty() ? "libretro_render" : name;
  nativeVsync_ =
      OH_NativeVSync_Create(usedName.c_str(), static_cast<unsigned>(usedName.size()));
  if (!nativeVsync_) {
    LOGF(LOG_WARN, "NativeVSync create failed");
    running_ = false;
    return false;
  }

  running_ = true;
  return true;
#else
  (void)name;
  LOGF(LOG_WARN, "NativeVSync header not available, fallback to timer");
  running_ = false;
  return false;
#endif
}

void NativeVSyncDriver::Stop() {
  std::lock_guard<std::mutex> lock(mutex_);
#if LIBRETRO_HAS_NATIVE_VSYNC
  if (nativeVsync_) {
    OH_NativeVSync_Destroy(nativeVsync_);
    nativeVsync_ = nullptr;
  }
#endif
  running_ = false;
  callback_ = nullptr;
}

bool NativeVSyncDriver::RequestNextFrame() {
  std::lock_guard<std::mutex> lock(mutex_);
#if LIBRETRO_HAS_NATIVE_VSYNC
  if (!running_ || !nativeVsync_) {
    return false;
  }
  return OH_NativeVSync_RequestFrame(nativeVsync_, OnFrame, this) == 0;
#else
  return false;
#endif
}

bool NativeVSyncDriver::IsRunning() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return running_;
}

#if LIBRETRO_HAS_NATIVE_VSYNC
void NativeVSyncDriver::OnFrame(long long timestamp, void *data) {
  if (!data) {
    return;
  }
  auto *self = static_cast<NativeVSyncDriver *>(data);
  FrameCallback callback;
  {
    std::lock_guard<std::mutex> lock(self->mutex_);
    callback = self->callback_;
  }
  if (callback) {
    callback(timestamp);
  }
}
#endif

} // namespace libretro
