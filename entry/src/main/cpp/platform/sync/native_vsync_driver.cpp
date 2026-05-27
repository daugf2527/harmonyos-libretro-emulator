#include "native_vsync_driver.h"

#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD040
#undef LOG_TAG
#define LOG_TAG "NativeVSyncDrv"
#undef LOG_FLOW
#define LOG_FLOW "VSync"
#include "common/log_prefix.h"

namespace libretro {

NativeVSyncDriver::NativeVSyncDriver()
    : alive_(std::make_shared<Alive>()) {}

NativeVSyncDriver::~NativeVSyncDriver() {
  Stop();
  // 标记对象已死,任何残留的 OH_NativeVSync 回调进入 OnFrame 后会立即返回。
  // alive_ 是 shared_ptr,回调端持有的 weak_ptr 仍能安全 lock 检测。
  alive_->v.store(false, std::memory_order_release);
}

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
  // 注意:callbackContext_ 不在此释放,因为 OH_NativeVSync_Destroy 不保证
  // 已 pending 的回调被取消。析构时再释放(此时 alive_ 已置 false,
  // 任何残留回调会安全返回)。
}

bool NativeVSyncDriver::RequestNextFrame() {
  std::lock_guard<std::mutex> lock(mutex_);
#if LIBRETRO_HAS_NATIVE_VSYNC
  if (!running_ || !nativeVsync_) {
    return false;
  }
  if (!callbackContext_) {
    callbackContext_ = std::make_unique<CallbackContext>();
    callbackContext_->alive = alive_;
    callbackContext_->self = this;
  }
  return OH_NativeVSync_RequestFrame(nativeVsync_, OnFrame,
                                     callbackContext_.get()) == 0;
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
  auto *ctx = static_cast<CallbackContext *>(data);
  auto alive = ctx->alive.lock();
  if (!alive || !alive->v.load(std::memory_order_acquire)) {
    // driver 已析构,不能访问 ctx->self
    return;
  }
  auto *self = ctx->self;
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
