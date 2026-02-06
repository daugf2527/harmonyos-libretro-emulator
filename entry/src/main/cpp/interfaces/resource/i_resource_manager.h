/*
 * 资源管理器接口 - HarmonyOS资源访问
 *
 * 设计原则:
 * - RAII: 使用智能指针管理资源
 * - 可测试: 可Mock文件系统
 */

#ifndef INTERFACES_I_RESOURCE_MANAGER_H
#define INTERFACES_I_RESOURCE_MANAGER_H

#include "interfaces/vfs/i_virtual_file_system.h"
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace interfaces {

/**
 * @brief 资源管理器接口
 *
 * 对应规范:
 * - HarmonyOS: NativeResourceManager API
 */
class IResourceManager : public IVirtualFileSystem {
public:
  virtual ~IResourceManager() = default;

  /**
   * @brief 从rawfile加载资源
   * @param path rawfile路径
   * @param out_data 输出资源数据
   * @return true 成功，false 失败
   */
  virtual bool LoadRawFile(const std::string &path,
                           std::vector<uint8_t> &out_data) = 0;

  /**
   * @brief 检查rawfile是否存在
   */
  virtual bool FileExists(const std::string &path) const = 0;

  /**
   * @brief 获取指定目录下的文件列表
   * @param dir 目录路径（相对于rawfile根目录）
   * @return 文件名列表
   */
  virtual std::vector<std::string> GetRawFileList(const std::string &dir) const = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_RESOURCE_MANAGER_H
