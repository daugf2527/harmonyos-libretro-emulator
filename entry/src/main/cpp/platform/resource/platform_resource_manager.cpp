/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "platform_resource_manager.h"
#include <dirent.h>
#include <fstream>
#include <hilog/log.h>
#include <rawfile/raw_file_manager.h>
#include <sys/stat.h>
#include <unistd.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "PlatformResourceManager"
#undef LOG_FLOW
#define LOG_FLOW "ROM"
#include "common/log_prefix.h"

// 如果有 rawfile 相关头文件需要引入
// #include <rawfile/raw_file_manager.h>

namespace libretro {

PlatformResourceManager::PlatformResourceManager() {
  LOGF(LOG_INFO, "PlatformResourceManager created");
}

PlatformResourceManager::~PlatformResourceManager() {
  LOGF(LOG_INFO, "PlatformResourceManager destroyed");
}

PlatformResourceManager *PlatformResourceManager::GetInstance() {
  static PlatformResourceManager instance;
  return &instance;
}

void PlatformResourceManager::DestroyInstance() {
  // Meyers singleton: 生命周期由运行时管理；保留接口以兼容历史调用点。
}

void PlatformResourceManager::Initialize(NativeResourceManager *native_mgr) {
  std::lock_guard<std::mutex> lock(mutex_);
  native_resource_manager_ = native_mgr;
  LOGF(LOG_INFO, "PlatformResourceManager initialized with NativeResourceManager: %{public}p", native_mgr);
}

bool PlatformResourceManager::LoadRawFileUnlocked(
    const std::string &path,
    NativeResourceManager *native_mgr,
    std::vector<uint8_t> &out_data) const {
  if (path.empty()) {
    return false;
  }

  // 1. 尝试作为普通文件加载 (沙箱路径)
  if (FileExists(path)) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (file.is_open()) {
      std::streamsize size = file.tellg();
      file.seekg(0, std::ios::beg);

      constexpr size_t kMaxSize = 512ULL * 1024ULL * 1024ULL;
      if (size <= 0 || static_cast<size_t>(size) > kMaxSize) {
        LOGF(LOG_ERROR,
             "Invalid file size: %{public}lld (%{public}s)",
             static_cast<long long>(size), path.c_str());
        return false;
      }

      if (size > 0) {
        out_data.resize(size);
        if (file.read(reinterpret_cast<char *>(out_data.data()), size)) {
          LOGF(LOG_INFO, "Loaded file from filesystem: %{public}zu bytes", size);
          return true;
        }
        out_data.clear();
      }
    }
  }

  // 2. 尝试从 RawFile 加载 (如果已初始化)
  if (native_mgr) {
    RawFile *rawFile = OH_ResourceManager_OpenRawFile(native_mgr, path.c_str());
    if (!rawFile) {
      LOGF(LOG_WARN, "OpenRawFile failed: %{public}s", path.c_str());
    } else {
      long sizeLong = OH_ResourceManager_GetRawFileSize(rawFile);
      if (sizeLong <= 0) {
        LOGF(LOG_ERROR, "Invalid rawfile size: %{public}ld (%{public}s)", sizeLong, path.c_str());
        OH_ResourceManager_CloseRawFile(rawFile);
        return false;
      }

      constexpr size_t kMaxSize = 512ULL * 1024ULL * 1024ULL;
      size_t size = static_cast<size_t>(sizeLong);
      if (size > kMaxSize) {
        LOGF(LOG_ERROR, "Rawfile too large: %{public}zu (%{public}s)", size, path.c_str());
        OH_ResourceManager_CloseRawFile(rawFile);
        return false;
      }

      out_data.resize(size);
      int readBytes =
          OH_ResourceManager_ReadRawFile(rawFile, out_data.data(), size);
      OH_ResourceManager_CloseRawFile(rawFile);

      if (readBytes < 0 || static_cast<size_t>(readBytes) != size) {
        LOGF(LOG_ERROR, "ReadRawFile failed: %{public}d/%{public}zu (%{public}s)", readBytes, size, path.c_str());
        out_data.clear();
        return false;
      }

      LOGF(LOG_INFO, "Loaded rawfile: %{public}zu bytes (%{public}s)", size, path.c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR, "Failed to load file: %{public}s", path.c_str());
  return false;
}

bool PlatformResourceManager::LoadRawFile(const std::string &path,
                                          std::vector<uint8_t> &out_data) {
  std::lock_guard<std::mutex> lock(mutex_);
  return LoadRawFileUnlocked(path, native_resource_manager_, out_data);
}

bool PlatformResourceManager::LoadRawFileWithManager(
    const std::string &path,
    NativeResourceManager *native_mgr,
    std::vector<uint8_t> &out_data) {
  std::lock_guard<std::mutex> lock(mutex_);
  return LoadRawFileUnlocked(path, native_mgr, out_data);
}

bool PlatformResourceManager::FileExists(const std::string &path) const {
  struct stat buffer;
  return (stat(path.c_str(), &buffer) == 0);
}

std::vector<std::string> PlatformResourceManager::GetRawFileListUnlocked(
    const std::string &dir, NativeResourceManager *native_mgr) const {
  std::vector<std::string> fileList;
  if (!native_mgr) {
    return fileList;
  }

  // 尝试打开 RawDir
  RawDir *rawDir = OH_ResourceManager_OpenRawDir(native_mgr, dir.c_str());
  if (!rawDir) {
    LOGF(LOG_WARN, "OpenRawDir failed: %{public}s", dir.c_str());
    return fileList;
  }

  int count = OH_ResourceManager_GetRawFileCount(rawDir);
  for (int i = 0; i < count; i++) {
    const char *fileName = OH_ResourceManager_GetRawFileName(rawDir, i);
    if (fileName) {
      fileList.push_back(fileName);
    }
  }

  OH_ResourceManager_CloseRawDir(rawDir);
  return fileList;
}

std::vector<std::string> PlatformResourceManager::GetRawFileList(const std::string &dir) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return GetRawFileListUnlocked(dir, native_resource_manager_);
}

bool PlatformResourceManager::ReadFile(const std::string &path,
                                       std::vector<uint8_t> &out_data) {
  return LoadRawFile(path, out_data);
}

std::vector<std::string> PlatformResourceManager::ListDir(const std::string &dir) const {
  std::vector<std::string> fileList;
  if (dir.empty()) {
    return fileList;
  }

  struct stat st;
  if (stat(dir.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
    DIR *dp = opendir(dir.c_str());
    if (!dp) {
      return fileList;
    }
    dirent *entry = nullptr;
    while ((entry = readdir(dp)) != nullptr) {
      const char *name = entry->d_name;
      if (!name || name[0] == '\0') {
        continue;
      }
      if (name[0] == '.' &&
          (name[1] == '\0' || (name[1] == '.' && name[2] == '\0'))) {
        continue;
      }
      fileList.push_back(name);
    }
    closedir(dp);
    return fileList;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  return GetRawFileListUnlocked(dir, native_resource_manager_);
}

} // namespace libretro
