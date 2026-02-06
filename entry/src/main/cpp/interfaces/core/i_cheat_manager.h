/*
 * 金手指管理器接口
 */

#ifndef INTERFACES_I_CHEAT_MANAGER_H
#define INTERFACES_I_CHEAT_MANAGER_H

#include <string>

namespace interfaces {

/**
 * @brief 金手指管理器接口
 * 对应 ArkTS refactoredCheat... 接口
 */
class ICheatManager {
public:
  virtual ~ICheatManager() = default;

  virtual bool Reset() = 0;
  virtual bool SetCheat(int index, bool enabled, const std::string &code) = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_CHEAT_MANAGER_H
