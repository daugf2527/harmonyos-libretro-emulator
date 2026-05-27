#include "fence_utils.h"
#include <cstdint>
#include <dlfcn.h>
#include <mutex>
#include <poll.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD050
#undef LOG_TAG
#define LOG_TAG "FenceUtils"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace common {

namespace {

struct NativeFenceApi {
  void *handle = nullptr;
  using WaitFn = bool (*)(int, uint32_t);
  using CloseFn = void (*)(int);
  using IsValidFn = bool (*)(int);
  WaitFn wait = nullptr;
  CloseFn close = nullptr;
  IsValidFn isValid = nullptr;
  bool available = false;
};

NativeFenceApi &GetNativeFenceApi() {
  static NativeFenceApi api;
  static std::once_flag once;
  std::call_once(once, []() {
    // handle intentionally kept open for process lifetime (static singleton)
    api.handle = dlopen("libnative_fence.so", RTLD_NOW | RTLD_LOCAL);
    if (!api.handle) {
      api.available = false;
      return;
    }
    api.wait = reinterpret_cast<NativeFenceApi::WaitFn>(dlsym(api.handle, "OH_NativeFence_Wait"));
    api.close = reinterpret_cast<NativeFenceApi::CloseFn>(dlsym(api.handle, "OH_NativeFence_Close"));
    api.isValid = reinterpret_cast<NativeFenceApi::IsValidFn>(dlsym(api.handle, "OH_NativeFence_IsValid"));
    api.available = (api.wait != nullptr && api.close != nullptr && api.isValid != nullptr);
    if (!api.available) {
      dlclose(api.handle);
      api.handle = nullptr;
      api.wait = nullptr;
      api.close = nullptr;
      api.isValid = nullptr;
    }
  });
  return api;
}

int WaitAndCloseFencePoll(int fenceFd, int timeoutMs) {
  struct pollfd pfd;
  std::memset(&pfd, 0, sizeof(pfd));
  pfd.fd = fenceFd;
  pfd.events = POLLIN;

  int ret = -1;
  do {
    ret = poll(&pfd, 1, timeoutMs);
  } while (ret == -1 && (errno == EINTR || errno == EAGAIN));

  int result = 0;
  if (ret < 0) {
    LOGF(LOG_ERROR,
                 "WaitAndCloseFence: poll failed: %{public}d", errno);
    result = -1;
  } else if (ret == 0) {
    if (timeoutMs >= 100) {
      LOGF(LOG_WARN,
                   "WaitAndCloseFence: poll timeout after %{public}d ms",
                   timeoutMs);
    }
    result = 1;
  }

  close(fenceFd);
  return result;
}

} // namespace

int WaitAndCloseFence(int fenceFd, int timeoutMs) {
  if (fenceFd < 0) {
    return 0; // 无需等待
  }

  const auto &api = GetNativeFenceApi();
  if (api.available) {
    const bool valid = api.isValid(fenceFd);
    const uint32_t timeout = (timeoutMs < 0) ? static_cast<uint32_t>(-1) : static_cast<uint32_t>(timeoutMs);
    const bool ok = valid ? api.wait(fenceFd, timeout) : false;
    api.close(fenceFd);
    if (!ok) {
      if (timeoutMs >= 100) {
        LOGF(LOG_WARN,
                     "WaitAndCloseFence: NativeFence wait failed/timeout after %{public}d ms",
                     timeoutMs);
      }
      return 1;
    }
    return 0;
  }

  return WaitAndCloseFencePoll(fenceFd, timeoutMs);
}

} // namespace common
