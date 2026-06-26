#include "core_state_manager.h"
#include <algorithm>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD011
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
    // T8-A-F5: 区分"游戏未加载"vs"core serialize 内部出错"——便于排查。
    // 上层 LibretroEngine::SaveState 已加 state guard,正常路径不会到这里;
    // 若仍走到,说明 core 在 GAME_LOADED 状态下 serialize_size 返回 0,是 core 问题。
    LOGF(LOG_WARN, "SaveState: serialize_size returned 0 (game state may not be ready)");
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
    // T8-A-F5: 区分 "core 未加载" vs "传入空 data"。
    if (data.empty()) {
      LOGF(LOG_WARN, "LoadState: input data is empty");
    }
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
  // T8-A-F3: 先查 size 再取 data 指针——libretro 惯用顺序。
  // 部分 core 在 size 调用时才初始化内部 SRAM 结构,反向调用可能拿到未初始化指针。
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (size == 0) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr) {
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
  // T8-A-F3: 先 size 再 data,与 GetSRAM 保持一致。
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (size == 0) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr) {
    return false;
  }
  size_t copySize = std::min(size, data.size());
  if (copySize < data.size()) {
    LOGF(LOG_WARN, "SetSRAM: input truncated from %{public}zu to %{public}zu bytes",
         data.size(), copySize);
  }
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
               "Cheat %{public}u %{public}s (code_len=%{public}zu)", index,
               enabled ? "enabled" : "disabled", code.size());
  return true;
}

} // namespace libretro
