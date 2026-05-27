# T8-A C++ SaveState/SRAM 状态管理审计

audit-id: audit-20260527-124137
scope: entry/src/main/cpp/core/engine + interfaces/state
agent: T8-A
date: 2026-05-27

## Findings

---

## F1: SaveState/LoadState 在 Engine 停止后 (!running_) 旁路 Engine 线程，在 NAPI 线程直接调用 retro_serialize/retro_unserialize

- severity: P1
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 975-982 (ExecuteSyncTask 快速路径), 2582-2598 (SaveState), 2601-2612 (LoadState)
- evidence_excerpt: |
    // libretro_engine.cpp L975-982
    bool LibretroEngine::ExecuteSyncTask(const std::function<void()> &task,
                                         uint32_t timeoutMs) {
      if (!task) {
        return false;
      }
      if (g_engineThreadInstance == this || !running_.load()) {
        task();   // ← !running_ 时直接在调用方线程（NAPI 线程）执行
        return true;
      }
- claim: |
    `ExecuteSyncTask` 的快速路径在两种条件下跳过消息队列直接执行 task：
    (1) 当前线程是 Engine 线程（`g_engineThreadInstance == this`）；
    (2) Engine 已停止（`!running_.load()`）。
    
    条件 (2) 导致：当引擎调用了 `Stop()` 后（`running_=false`），但 `coreLoader_` 仍持有有效
    handle（`Stop()` 不调用 `coreLoader_.UnloadCore()`，仅 `UnloadGameIfNeeded` 卸载游戏），
    此时 ArkTS 侧调用 `refactoredSaveState` / `refactoredLoadState` 会通过
    `ExecuteSyncTask !running_` 快速路径，在 NAPI 线程（ArkTS JS 线程）直接执行
    `retro_serialize` / `retro_unserialize`。
    
    `SaveState` 和 `LoadState` 本身均无状态机检查（无 `state_.load() == RUNNING` guard），
    只依赖 `coreLoader_.IsLoaded()`（仅检查 dlopen handle）。
    在 core 已通过 `retro_init()` 初始化、但游戏未加载（CORE_LOADED 状态）时，
    调用 `retro_serialize` 也满足 `IsLoaded()` 条件，属于 libretro UB（游戏状态不存在时
    serialize 行为未定义）。
    
    `SaveState` / `LoadState` 和 `GetSRAM` / `SetSRAM` 均经由 `ExecuteSyncTask` 调度，
    相同问题同样影响 SRAM 读写路径。
- suggested_fix: |
    在 `LibretroEngine::SaveState`、`LoadState`、`GetSRAM`、`SetSRAM` 函数入口处增加
    状态机前置检查，只允许 `RUNNING`、`PAUSED`、`GAME_LOADED` 三种状态通过，其余状态
    直接返回 false。示例：
    ```cpp
    const EngineState st = state_.load();
    if (st != EngineState::RUNNING && st != EngineState::PAUSED &&
        st != EngineState::GAME_LOADED) {
      return false;  // SaveState/LoadState 类型
    }
    ```
    此 guard 在 `ExecuteSyncTask` 调用前执行，当 `!running_` 时仍可提前拒绝，避免在 NAPI
    线程触及 libretro core。

---

## F2: DiskController::callbacks_ 在 core unload 后持有悬空函数指针

- severity: P1
- file: entry/src/main/cpp/core/engine/libretro_engine.cpp
- line: 1332-1349 (HandleMessage LoadCore 中旧 core unload 段), entry/src/main/cpp/core/libretro/disk_controller.h L44-48
- evidence_excerpt: |
    // libretro_engine.cpp L1332-1339
    if (coreLoader_.IsLoaded()) {
      LOGF(LOG_INFO, "[NEW] Unloading previous core before loading new one");
      UnloadGameIfNeeded("switch_core");
      if (coreLoader_.GetDeinit()) {
        coreLoader_.GetDeinit()();
      }
      coreLoader_.UnloadCore();   // dlclose 发生在这里
    }
    // disk_controller.h L44-46
    retro_disk_control_ext_callback callbacks_{};  // 函数指针，来自已卸载的 core
    bool is_ext_ = false;
    bool ejected_ = false;
- claim: |
    `DiskController::callbacks_` 存储了 core 通过 `RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE`
    / `SET_DISK_CONTROL_EXT_INTERFACE` 注册的函数指针。这些函数指针指向已加载 core 的
    .so 代码段。
    
    当换核（HandleMessage LoadCore）时，`coreLoader_.UnloadCore()` 会执行 `dlclose`，
    释放旧 core 的代码页，但 `diskController_` 的 `callbacks_` 未被清零，仍指向已卸载的
    内存地址（悬空指针）。
    
    `DiskController` 类没有 `ClearCallbacks()` 方法。HandleMessage LoadCore 中旧 core 卸载后
    未重置 `diskController_->callbacks_`。新 core 若不使用 Disk Control，`callbacks_` 将
    维持悬空状态。此后调用 `DiskControlSetEjectState`、`DiskControlGetEjectState` 等方法时，
    `diskController_->Eject()` 等函数会调用 `callbacks_.set_eject_state`（已失效指针），
    导致访问已释放内存，crash 或 undefined behavior。
    
    `Stop()` 路径（HandleMessage Stop → UnloadGameIfNeeded → 但不 UnloadCore）不触发此问题，
    仅换核路径触发。
- suggested_fix: |
    为 `DiskController` 增加 `ClearCallbacks()` 方法，将 `callbacks_` 清零并将 `is_ext_`
    设为 false：
    ```cpp
    void DiskController::ClearCallbacks() {
        std::lock_guard<std::mutex> lock(mutex_);
        callbacks_ = {};
        is_ext_ = false;
        ejected_ = false;
    }
    ```
    在 `HandleMessage LoadCore` 中 `coreLoader_.UnloadCore()` 之前调用
    `diskController_->ClearCallbacks()`。建议同时在 `HandleMessage Stop`（`UnloadGameIfNeeded`
    之后、`TransitionTo(STOPPING)` 之前）也调用一次，作为防御性清理。

---

## F3: GetSRAM/SetSRAM 中 retro_get_memory_data 先于 retro_get_memory_size 调用（顺序颠倒）

- severity: P2
- file: entry/src/main/cpp/core/engine/core_state_manager.cpp
- line: 82-83 (GetSRAM), 101-102 (SetSRAM)
- evidence_excerpt: |
    // core_state_manager.cpp L82-88
    void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);        // 先取 data pointer
    size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);       // 再取 size
    if (!ptr || size == 0) {
      return false;
    }
    outData.assign(static_cast<uint8_t *>(ptr),
                   static_cast<uint8_t *>(ptr) + size);
- claim: |
    libretro 规范的惯用调用顺序是先查 `retro_get_memory_size` 确认非零，再调用
    `retro_get_memory_data` 取指针。部分 core 实现中，`retro_get_memory_data` 可能在
    内部依赖 size 查询的副作用才能返回有效指针（少数 core 会在 size 调用时初始化内部
    SRAM 结构）。
    
    当前代码先调用 `dataFn`（`retro_get_memory_data`），再调用 `sizeFn`（`retro_get_memory_size`）。
    `!ptr || size == 0` 的复合检查能防御最终的空指针 / 零大小情况，但无法防御 core 因
    调用顺序问题返回"指针非空但内容未初始化"的情况。
    
    SetSRAM（L101-102）存在相同的顺序问题。
- suggested_fix: |
    交换两次调用的顺序，先 sizeFn，再 dataFn，并在 size == 0 时提前返回：
    ```cpp
    size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
    if (size == 0) return false;
    void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
    if (!ptr) return false;
    ```
    同样适用于 SetSRAM（L101-102）。

---

## F4: IStateManager 接口与 CoreStateManager 签名不一致，且接口从未被使用（死代码）

- severity: P2
- file: entry/src/main/cpp/interfaces/state/i_state_manager.h (L23-29), entry/src/main/cpp/core/engine/core_state_manager.h
- line: 23-29 (i_state_manager.h)
- evidence_excerpt: |
    // i_state_manager.h L22-29
    virtual size_t GetSaveStateSize() const = 0;
    virtual std::vector<uint8_t> SaveState() = 0;          // 返回 vector
    virtual bool LoadState(const std::vector<uint8_t> &data) = 0;
    virtual std::vector<uint8_t> GetSRAM() const = 0;      // 返回 vector
    virtual bool SetSRAM(const std::vector<uint8_t> &data) = 0;
    
    // core_state_manager.h 实际签名（CoreStateManager 不继承 IStateManager）
    bool SaveState(std::vector<uint8_t> &outData);          // 输出参数
    bool GetSRAM(std::vector<uint8_t> &outData);            // 输出参数
- claim: |
    `IStateManager` 接口声明 `SaveState()` 返回 `std::vector<uint8_t>`（无成功/失败区分），
    `GetSRAM()` 同理。但实际实现类 `CoreStateManager` 使用 `bool + &outData` 签名（可区分
    失败情况），且 `CoreStateManager` 未继承 `IStateManager`。
    
    搜索全仓库，`IStateManager` 没有任何使用方（无 `#include "i_state_manager.h"` 的调用者，
    也无任何 `IStateManager*` 类型变量）。该接口是死代码。
    
    死代码本身不引起运行时问题，但签名不一致容易误导后续开发者——若将来有人想让
    `CoreStateManager` 实现此接口，签名不匹配会导致编译错误，或者错误地修改现有
    实现以迁就接口的较弱返回值语义（丢失失败判断）。
- suggested_fix: |
    选项 A（推荐）：删除 `i_state_manager.h`，因为该接口未被使用。
    选项 B：若需要保留接口用于将来的多实现场景，修正接口签名与 `CoreStateManager` 保持一致：
    ```cpp
    virtual bool SaveState(std::vector<uint8_t> &outData) = 0;
    virtual bool GetSRAM(std::vector<uint8_t> &outData) const = 0;
    ```
    并让 `CoreStateManager` 继承 `IStateManager`（`public interfaces::IStateManager`）。

---

## F5: SaveState/LoadState 在 CORE_LOADED（游戏未加载）状态下无错误日志区分，静默返回失败

- severity: P2
- file: entry/src/main/cpp/core/engine/core_state_manager.cpp
- line: 32-55 (SaveState), 58-68 (LoadState)
- evidence_excerpt: |
    // core_state_manager.cpp L44-46
    size_t size = sizeFn();
    if (size == 0) {
      return false;   // 静默失败，无日志
    }
- claim: |
    当游戏未加载（CORE_LOADED 状态）时，`retro_serialize_size` 通常返回 0，
    `CoreStateManager::SaveState` 在 L44-46 检查 `size == 0` 后直接返回 false，没有
    任何日志输出。上层 `LibretroEngine::SaveState` 无状态 guard，会将此静默失败
    透传到 NAPI 层，NAPI 层仅返回 null 给 ArkTS。
    
    这使得"core 已加载但游戏未加载时调用 SaveState"与"serialize 本身出错"产生的
    symptom 完全相同（均返回 null），无法从 hilog 中区分，给调试带来困难。
    
    类似地，`LoadState` 在 `data.empty()` 检查后无区分性日志。
- suggested_fix: |
    在 `size == 0` 检查处补充 LOG_WARN 说明原因。更根本的修复是在 `LibretroEngine` 层
    的 `SaveState`/`LoadState` 函数中增加状态机 guard（见 F1），使调用在到达
    `CoreStateManager` 之前就被拒绝并记录明确日志。

---

## 汇总

| ID  | 严重级 | 文件 | 一句话摘要 |
|-----|--------|------|-----------|
| F1  | P1     | libretro_engine.cpp | SaveState/LoadState 无状态 guard，Engine 停止后 NAPI 线程旁路直调 retro_serialize |
| F2  | P1     | libretro_engine.cpp / disk_controller.h | DiskController callbacks_ 在 core unload 后持有悬空函数指针 |
| F3  | P2     | core_state_manager.cpp | GetSRAM/SetSRAM 调用顺序：retro_get_memory_data 先于 retro_get_memory_size |
| F4  | P2     | i_state_manager.h | IStateManager 与 CoreStateManager 签名不一致且接口为死代码 |
| F5  | P2     | core_state_manager.cpp | size==0 静默失败无区分日志 |

无 P0 findings。P1: 2 项，P2: 3 项，共 5 项。
