/*
 * 状态管理器接口 - 处理即时存档和 SRAM
 */

#ifndef INTERFACES_I_STATE_MANAGER_H
#define INTERFACES_I_STATE_MANAGER_H

#include <cstddef>
#include <cstdint>
#include <vector>

namespace interfaces {

/**
 * @brief 状态管理器接口
 * 对应 ArkTS refactoredSaveState/LoadState 等接口
 */
class IStateManager {
public:
  virtual ~IStateManager() = default;

  // Save State (即时存档)
  virtual size_t GetSaveStateSize() const = 0;
  virtual std::vector<uint8_t> SaveState() = 0;
  virtual bool LoadState(const std::vector<uint8_t> &data) = 0;

  // SRAM (电池记忆)
  virtual std::vector<uint8_t> GetSRAM() const = 0;
  virtual bool SetSRAM(const std::vector<uint8_t> &data) = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_STATE_MANAGER_H
