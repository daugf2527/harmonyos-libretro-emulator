/*
 * Virtual file system interface
 */

#ifndef INTERFACES_VFS_I_VIRTUAL_FILE_SYSTEM_H
#define INTERFACES_VFS_I_VIRTUAL_FILE_SYSTEM_H

#include <cstdint>
#include <string>
#include <vector>

namespace interfaces {

class IVirtualFileSystem {
public:
  virtual ~IVirtualFileSystem() = default;

  virtual bool ReadFile(const std::string &path,
                        std::vector<uint8_t> &out_data) = 0;
  virtual bool FileExists(const std::string &path) const = 0;
  virtual std::vector<std::string> ListDir(const std::string &dir) const = 0;
};

} // namespace interfaces

#endif // INTERFACES_VFS_I_VIRTUAL_FILE_SYSTEM_H
