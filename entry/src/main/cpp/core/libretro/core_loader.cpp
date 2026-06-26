/*
 * Libretro Core Loader Implementation
 * Phase 3.1 - 动态加载 Libretro 核心 (.so 文件)
 * 遵循鸿蒙官方最佳实践: 使用 dlopen/dlsym 标准 API
 */
#include "core_loader.h"
#include "common/file_security.h"
#include <cerrno>
#include <cstring>
#include <dlfcn.h>
#include <hilog/log.h>
#include <mutex>
#include <sys/stat.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "CoreLoader"
#undef LOG_FLOW
#define LOG_FLOW "Core"
#include "common/log_prefix.h"

namespace {
void PreloadGraphicsLibs() {
  static std::once_flag once;
  std::call_once(once, []() {
    const char *libs[] = {"libGLESv3.so", "libGLESv2.so", "libGLESv1_CM.so",
                          "libEGL.so"};
    for (const char *lib : libs) {
      // handle intentionally leaked: keeps GL symbols loaded for core's lifetime
      void *handle = dlopen(lib, RTLD_NOW | RTLD_LOCAL);
      if (handle) {
        LOGF(LOG_INFO, "Preloaded graphics lib: %{public}s", lib);
      } else {
        const char *err = dlerror();
        const std::string safeErr =
            security::SanitizeErrorMessageForLog(err ? err : "unknown");
        LOGF(LOG_WARN,
             "Preload graphics lib failed: %{public}s (%{public}s)", lib,
             safeErr.c_str());
      }
    }
  });
}

void *DlopenLocal(const char *path, std::string &outErr) {
  struct Attempt {
    int flags;
    const char *label;
  };
  const Attempt attempts[] = {
      {RTLD_NOW | RTLD_LOCAL, "RTLD_NOW | RTLD_LOCAL"},
      {RTLD_LAZY | RTLD_LOCAL, "RTLD_LAZY | RTLD_LOCAL"},
  };
  void *handle = nullptr;
  outErr.clear();
  for (const auto &attempt : attempts) {
    dlerror(); // clear
    LOGF(LOG_INFO, "Attempting dlopen with %{public}s...", attempt.label);
    handle = dlopen(path, attempt.flags);
    if (handle) {
      return handle;
    }
    const char *err = dlerror();
    outErr = security::SanitizeErrorMessageForLog(err ? err : "unknown");
    LOGF(LOG_ERROR, "dlopen (%{public}s) failed: %{public}s", attempt.label,
         outErr.c_str());
  }
  return nullptr;
}
} // namespace

CoreLoader::~CoreLoader() { UnloadCore(); }

bool CoreLoader::LoadCore(const std::string &corePath) {
  recordError_ = true;
  lastErrorStep_.clear();
  lastErrorMessage_.clear();

  if (IsLoaded()) {
    LOGF(LOG_ERROR,
                 "Core already loaded, unload first");
    SetLastError("already_loaded", "Core already loaded, unload first");
    return false;
  }

  //  Security: Validate core path to prevent path traversal attacks
  if (!security::ValidateCorePath(corePath)) {
    LOGF(LOG_ERROR,
                 "Security: Core path validation failed: %{public}s",
                 security::DescribePathForLog(corePath).c_str());
    SetLastError("security_check", "Core path not in allowed directories");
    return false;
  }

  LOGF(LOG_INFO,
               "Loading Libretro core: %{public}s",
               security::DescribePathForLog(corePath).c_str());

  // 预加载图形库以满足部分 HW 核心的符号依赖（如 glGetIntegerv）
  PreloadGraphicsLibs();

  // 1. 检查文件是否存在
  struct stat fileStat;
  if (stat(corePath.c_str(), &fileStat) != 0) {
    LOGF(LOG_ERROR,
                 "File does not exist or cannot be accessed: %{public}s",
                 security::DescribePathForLog(corePath).c_str());
    char errBuf[128] = {};
    strerror_r(errno, errBuf, sizeof(errBuf));
    LOGF(LOG_ERROR,
                 "errno: %{public}d (%{public}s)", errno, errBuf);
    SetLastError("stat", errBuf);
    return false;
  }
  LOGF(LOG_INFO,
               "File found! Size: %{public}lld bytes, Mode: %{public}o",
               static_cast<long long>(fileStat.st_size), fileStat.st_mode);

  // 1. 使用 dlopen 加载动态库 (仅 RTLD_LOCAL，避免符号污染)
  std::string dlopenErr;
  coreHandle_ = DlopenLocal(corePath.c_str(), dlopenErr);
  if (!coreHandle_) {
    LOGF(LOG_ERROR, "All dlopen attempts failed!");
    LOGF(LOG_ERROR,
         "请确认: 1) .so 文件存在于沙箱路径 2) 架构匹配 "
         "(arm64/x86_64) 3) 文件权限正确");
    SetLastError("dlopen", dlopenErr.empty() ? "unknown" : dlopenErr);
    return false;
  }

  LOGF(LOG_INFO,
               " Dynamic library loaded successfully!");
  LOGF(LOG_INFO,
               "dlopen succeeded! Handle: %{public}p", coreHandle_);

  // 2. 加载必需的核心函数 (按官方 Libretro API 规范)
  bool success = true;

  // 生命周期函数 (必需)
  success &= LoadSymbol(retro_init_, "retro_init");
  success &= LoadSymbol(retro_deinit_, "retro_deinit");
  success &= LoadSymbol(retro_api_version_, "retro_api_version");

  // 信息查询函数 (必需)
  success &= LoadSymbol(retro_get_system_info_, "retro_get_system_info");
  success &= LoadSymbol(retro_get_system_av_info_, "retro_get_system_av_info");

  // 回调设置函数 (必需 - 关键!)
  success &= LoadSymbol(retro_set_environment_, "retro_set_environment");
  success &= LoadSymbol(retro_set_video_refresh_, "retro_set_video_refresh");
  success &= LoadSymbol(retro_set_audio_sample_, "retro_set_audio_sample");
  success &=
      LoadSymbol(retro_set_audio_sample_batch_, "retro_set_audio_sample_batch");
  success &= LoadSymbol(retro_set_input_poll_, "retro_set_input_poll");
  success &= LoadSymbol(retro_set_input_state_, "retro_set_input_state");
  success &= LoadSymbol(retro_set_controller_port_device_,
                        "retro_set_controller_port_device");

  // 游戏控制函数 (必需)
  success &= LoadSymbol(retro_reset_, "retro_reset");
  success &= LoadSymbol(retro_run_, "retro_run");

  // 游戏加载函数 (必需)
  success &= LoadSymbol(retro_load_game_, "retro_load_game");
  success &= LoadSymbol(retro_unload_game_, "retro_unload_game");

  // 3. 加载可选函数 (不强制要求,失败不影响核心加载)
  recordError_ = false;
  LoadSymbol(retro_serialize_size_, "retro_serialize_size");
  LoadSymbol(retro_serialize_, "retro_serialize");
  LoadSymbol(retro_unserialize_, "retro_unserialize");
  LoadSymbol(retro_cheat_reset_, "retro_cheat_reset");
  LoadSymbol(retro_cheat_set_, "retro_cheat_set");
  LoadSymbol(retro_load_game_special_, "retro_load_game_special");
  LoadSymbol(retro_get_region_, "retro_get_region");
  LoadSymbol(retro_get_memory_data_, "retro_get_memory_data");
  LoadSymbol(retro_get_memory_size_, "retro_get_memory_size");
  recordError_ = true;

  if (!success) {
    LOGF(LOG_ERROR,
                 "Failed to load required symbols from core");
    if (lastErrorStep_.empty()) {
      SetLastError("dlsym_required",
                   "Failed to load required symbols from core");
    }
    UnloadCore();
    return false;
  }

  // 4. 验证 API 版本
  unsigned apiVersion = retro_api_version_();
  if (apiVersion != RETRO_API_VERSION) {
    LOGF(LOG_ERROR,
                 "API version mismatch: core=%{public}u, expected=%{public}u",
                 apiVersion, RETRO_API_VERSION);
    SetLastError("api_version", "API version mismatch");
    UnloadCore();
    return false;
  }

  // 5. 获取核心信息
  struct retro_system_info sysInfo = {};
  retro_get_system_info_(&sysInfo);
  const char *libraryName =
      sysInfo.library_name ? sysInfo.library_name : "unknown";
  const char *libraryVersion =
      sysInfo.library_version ? sysInfo.library_version : "unknown";
  const char *validExtensions =
      sysInfo.valid_extensions ? sysInfo.valid_extensions : "";
  LOGF(LOG_INFO,
               "Core loaded successfully!");
  LOGF(LOG_INFO, "  Name: %{public}s",
               libraryName);
  LOGF(LOG_INFO, "  Version: %{public}s",
               libraryVersion);
  LOGF(LOG_INFO,
               "  Extensions: %{public}s", validExtensions);
  LOGF(LOG_INFO,
               "  API Version: %{public}u", apiVersion);

  return true;
}

void CoreLoader::UnloadCore() {
  if (coreHandle_) {
    LOGF(LOG_INFO,
                 "Unloading Libretro core...");

    // 使用 dlclose 关闭动态库 (遵循鸿蒙官方文档)
    dlclose(coreHandle_);
    coreHandle_ = nullptr;

    // 重置所有函数指针 (按官方 libretro.h 顺序)
    // 生命周期函数
    retro_init_ = nullptr;
    retro_deinit_ = nullptr;
    retro_api_version_ = nullptr;
    retro_get_system_info_ = nullptr;
    retro_get_system_av_info_ = nullptr;

    // 回调设置函数
    retro_set_environment_ = nullptr;
    retro_set_video_refresh_ = nullptr;
    retro_set_audio_sample_ = nullptr;
    retro_set_audio_sample_batch_ = nullptr;
    retro_set_input_poll_ = nullptr;
    retro_set_input_state_ = nullptr;
    retro_set_controller_port_device_ = nullptr;

    // 游戏控制函数
    retro_reset_ = nullptr;
    retro_run_ = nullptr;

    // Save State 函数
    retro_serialize_size_ = nullptr;
    retro_serialize_ = nullptr;
    retro_unserialize_ = nullptr;

    // Cheat 函数
    retro_cheat_reset_ = nullptr;
    retro_cheat_set_ = nullptr;

    // 游戏加载函数
    retro_load_game_ = nullptr;
    retro_load_game_special_ = nullptr;
    retro_unload_game_ = nullptr;

    // 其他函数
    retro_get_region_ = nullptr;
    retro_get_memory_data_ = nullptr;
    retro_get_memory_size_ = nullptr;

    LOGF(LOG_INFO,
                 "Core unloaded successfully");
  }
}

template <typename T> bool CoreLoader::LoadSymbol(T &func, const char *name) {
  // 使用 dlsym 解析符号 (标准 POSIX API,鸿蒙完全支持)
  func = reinterpret_cast<T>(dlsym(coreHandle_, name));
  if (!func) {
    const char *error = dlerror();
    const std::string safeError =
        security::SanitizeErrorMessageForLog(error ? error : "unknown error");
    LOGF(LOG_ERROR,
                 "Failed to load symbol '%{public}s': %{public}s", name,
                 safeError.c_str());
    if (recordError_) {
      SetLastError(std::string("dlsym:") + name, safeError);
    }
    return false;
  }
  LOGF(LOG_INFO,
               "Symbol loaded: %{public}s", name);
  return true;
}
