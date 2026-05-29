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

#ifndef PLATFORM_RESOURCE_MANAGER_H
#define PLATFORM_RESOURCE_MANAGER_H

#include "interfaces/resource/i_resource_manager.h"
#include <mutex>
#include <string>
#include <vector>

// 前向声明 HarmonyOS NativeResourceManager
struct NativeResourceManager;

namespace libretro {

/**
 * @brief 平台资源管理器实现
 *
 * 负责文件和资源加载，支持普通文件系统和 HarmonyOS RawFile
 */
class PlatformResourceManager : public interfaces::IResourceManager {
public:
  static PlatformResourceManager *GetInstance();
  static void DestroyInstance();

  // IResourceManager 接口实现
  bool LoadRawFile(const std::string &path,
                   std::vector<uint8_t> &out_data) override;
  bool FileExists(const std::string &path) const override;
  std::vector<std::string> GetRawFileList(const std::string &dir) const override;
  bool ReadFile(const std::string &path,
                std::vector<uint8_t> &out_data) override;
  std::vector<std::string> ListDir(const std::string &dir) const override;

  // 显式传入 NativeResourceManager，避免依赖单例缓存句柄生命周期。
  bool LoadRawFileWithManager(const std::string &path,
                              NativeResourceManager *native_mgr,
                              std::vector<uint8_t> &out_data);

  // 初始化 (传入 HarmonyOS 资源管理器句柄)
  void Initialize(NativeResourceManager *native_mgr);

  // 释放内部句柄引用，使后续 Get*() 调用安全降级到文件系统路径。
  // 不释放 NativeResourceManager 本身的所有权（由调用方负责）。
  void Release();

private:
  PlatformResourceManager();
  ~PlatformResourceManager() override;
  bool LoadRawFileUnlocked(const std::string &path,
                           NativeResourceManager *native_mgr,
                           std::vector<uint8_t> &out_data) const;
  std::vector<std::string> GetRawFileListUnlocked(
      const std::string &dir, NativeResourceManager *native_mgr) const;
  mutable std::mutex mutex_;

  NativeResourceManager *native_resource_manager_ = nullptr;

  PlatformResourceManager(const PlatformResourceManager &) = delete;
  PlatformResourceManager &operator=(const PlatformResourceManager &) = delete;
};

} // namespace libretro

#endif // PLATFORM_RESOURCE_MANAGER_H
