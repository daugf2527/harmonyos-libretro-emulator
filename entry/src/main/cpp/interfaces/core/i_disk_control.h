/*
 * 磁盘控制接口 - 处理多盘游戏换盘
 */

#ifndef INTERFACES_I_DISK_CONTROL_H
#define INTERFACES_I_DISK_CONTROL_H

#include <string>

namespace interfaces {

/**
 * @brief 磁盘控制接口
 * 对应 ArkTS refactoredDiskControl... 接口
 */
class IDiskControl {
public:
  virtual ~IDiskControl() = default;

  virtual bool SetEjectState(bool ejected) = 0;
  virtual bool GetEjectState() const = 0;
  
  virtual int GetImageIndex() const = 0;
  virtual bool SetImageIndex(int index) = 0;
  
  virtual int GetNumImages() const = 0;
  
  virtual bool ReplaceImageIndex(int index, const std::string &path) = 0;
  virtual bool AddImageIndex() = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_DISK_CONTROL_H
