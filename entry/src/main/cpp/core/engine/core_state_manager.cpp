#include "core_state_manager.h"
#include <algorithm>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "CoreStateManager"
#undef LOG_FLOW
#define LOG_FLOW "Engine"
#include "common/log_prefix.h"

namespace libretro {

CoreStateManager::CoreStateManager(CoreLoader &coreLoader)
    : coreLoader_(coreLoader) {
  LOGF(LOG_INFO,
               "CoreStateManager created");
}

// --- SaveState Implementation ---

size_t CoreStateManager::GetSaveStateSize() const {
  if (!coreLoader_.IsLoaded()) {
    return 0;
  }
  auto fn = coreLoader_.GetSerializeSize();
  return fn ? fn() : 0;
}

bool CoreStateManager::SaveState(std::vector<uint8_t> &outData) {
  if (!coreLoader_.IsLoaded()) {
    return false;
  }
  auto sizeFn = coreLoader_.GetSerializeSize();
  auto saveFn = coreLoader_.GetSerialize();
  if (!sizeFn || !saveFn) {
    LOGF(LOG_WARN,
                 "Core does not support savestates");
    return false;
  }

  size_t size = sizeFn();
  if (size == 0) {
    return false;
  }

  outData.resize(size);
  if (saveFn(outData.data(), size)) {
    LOGF(LOG_INFO,
                 "State saved: %{public}zu bytes", size);
    return true;
  }
  return false;
}

bool CoreStateManager::LoadState(const std::vector<uint8_t> &data) {
  if (!coreLoader_.IsLoaded() || data.empty()) {
    return false;
  }
  auto fn = coreLoader_.GetUnserialize();
  if (!fn) {
    LOGF(LOG_WARN,
                 "Core does not support loadstate");
    return false;
  }
  return fn(data.data(), data.size());
}

// --- SRAM Implementation ---

bool CoreStateManager::GetSRAM(std::vector<uint8_t> &outData) {
  if (!coreLoader_.IsLoaded()) {
    return false;
  }
  auto dataFn = coreLoader_.GetGetMemoryData();
  auto sizeFn = coreLoader_.GetGetMemorySize();
  if (!dataFn || !sizeFn) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr || size == 0) {
    return false;
  }
  outData.assign(static_cast<uint8_t *>(ptr),
                 static_cast<uint8_t *>(ptr) + size);
  return true;
}

bool CoreStateManager::SetSRAM(const std::vector<uint8_t> &data) {
  if (!coreLoader_.IsLoaded() || data.empty()) {
    return false;
  }
  auto dataFn = coreLoader_.GetGetMemoryData();
  auto sizeFn = coreLoader_.GetGetMemorySize();
  if (!dataFn || !sizeFn) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr || size == 0) {
    return false;
  }
  size_t copySize = std::min(size, data.size());
  std::memcpy(ptr, data.data(), copySize);
  return true;
}

// --- Cheat Implementation ---

void CoreStateManager::CheatReset() {
  if (!coreLoader_.IsLoaded()) {
    return;
  }
  auto fn = coreLoader_.GetCheatReset();
  if (fn) {
    fn();
    LOGF(LOG_INFO, "Cheats reset");
  }
}

bool CoreStateManager::CheatSet(unsigned index, bool enabled,
                                const std::string &code) {
  if (!coreLoader_.IsLoaded()) {
    return false;
  }
  auto fn = coreLoader_.GetCheatSet();
  if (!fn) {
    LOGF(LOG_WARN,
                 "Core does not support cheats");
    return false;
  }
  fn(index, enabled, code.c_str());
  LOGF(LOG_INFO,
               "Cheat %{public}u %{public}s: %{public}s", index,
               enabled ? "enabled" : "disabled", code.c_str());
  return true;
}

} // namespace libretro
