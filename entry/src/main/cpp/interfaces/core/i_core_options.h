/*
 * 核心选项接口
 */

#ifndef INTERFACES_I_CORE_OPTIONS_H
#define INTERFACES_I_CORE_OPTIONS_H

#include <string>

namespace interfaces {

/**
 * @brief 核心选项接口
 * 对应 ArkTS refactoredGetCoreOptions/SetCoreOption 接口
 */
class ICoreOptions {
public:
  virtual ~ICoreOptions() = default;

  virtual std::string GetCoreOptions() const = 0;
  virtual bool SetCoreOption(const std::string &key, const std::string &value) = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_CORE_OPTIONS_H
