#ifndef LIBRETRO_ENGINE_CORE_STATE_MANAGER_H
#define LIBRETRO_ENGINE_CORE_STATE_MANAGER_H

#include "../libretro/core_loader.h"
#include <cstdint>
#include <string>
#include <vector>

namespace libretro {

/**
 * @brief CoreStateManager
 * Manages save states, SRAM (memory), and cheats.
 * Decoupled from LibretroEngine to separate concerns.
 */
class CoreStateManager {
public:
  explicit CoreStateManager(CoreLoader &coreLoader);
  ~CoreStateManager() = default;

  // --- SaveState Interface ---
  size_t GetSaveStateSize() const;
  bool SaveState(std::vector<uint8_t> &outData);
  bool LoadState(const std::vector<uint8_t> &data);

  // --- SRAM Interface ---
  bool GetSRAM(std::vector<uint8_t> &outData);
  bool SetSRAM(const std::vector<uint8_t> &data);

  // --- Cheat Interface ---
  void CheatReset();
  bool CheatSet(unsigned index, bool enabled, const std::string &code);

  // --- Controller/Region Config (Optional refactor, included in original plan
  // scope? The plan mentioned "CoreState & Cheat", but Controller/Region logic
  // often goes with core configuration. Let's stick to the plan strictly:
  // SaveState, SRAM, Cheat. However, Controller/Region were next to them in the
  // file. Let's keep the scope focused on State/Memory/Cheats as planned.

private:
  CoreLoader &coreLoader_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_CORE_STATE_MANAGER_H
