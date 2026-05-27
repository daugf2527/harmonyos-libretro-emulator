# T8-A Fix Verify

audit-id: audit-20260527-124137
verifier: T8-F-A subagent
date: 2026-05-27

---

## F1: SaveState/LoadState 状态机 guard

- **status: COMPLETE**
- **evidence:**

  `IsGameLoadedState()` 定义（libretro_engine.cpp L214-216）:
  ```cpp
  bool IsGameLoadedState(EngineState state) {
    return state == EngineState::GAME_LOADED || state == EngineState::RUNNING ||
           state == EngineState::PAUSED;
  }
  ```
  覆盖 finding 建议的三种状态（RUNNING / PAUSED / GAME_LOADED），完全匹配。

  5 个函数均已加 guard，带 `T8-A-F1` 注释标记：
  | 函数 | 行号 | 注释标记 |
  |------|------|---------|
  | `GetSaveStateSize` | L2621-2625 | `T8-A-F1` |
  | `SaveState` | L2638-2644 | `T8-A-F1` |
  | `LoadState` | L2664-2669 | `T8-A-F1` |
  | `GetSRAM` | L2686-2691 | `T8-A-F1` |
  | `SetSRAM` | L2711-2716 | `T8-A-F1` |

  SaveState / LoadState / GetSRAM / SetSRAM 在 guard 失败时均输出 `LOG_WARN` 含状态值，便于 hilog 排查。`GetSaveStateSize` guard 失败时返回 0（静默，无日志）——此函数是 size query，返回 0 本身即是明确信号，不影响功能正确性，可接受。

- **notes:** 无 nice-to-have 遗漏。

---

## F2: DiskController ClearCallbacks — 换核路径

- **status: COMPLETE**
- **evidence:**

  `DiskController::ClearCallbacks()` 已添加（disk_controller.h L34，disk_controller.cpp L36-44）：
  ```cpp
  void DiskController::ClearCallbacks() {
    // T8-A-F2: 在 core dlclose 前调用,清零悬空函数指针。
    std::lock_guard<std::mutex> lock(mutex_);
    callbacks_ = {};
    is_ext_ = false;
    ejected_ = false;
    LOGF(LOG_INFO, "Disk control callbacks cleared (T8-A-F2)");
  }
  ```
  实现与 suggested_fix 完全一致（mutex 保护 + callbacks_ 清零 + is_ext_ / ejected_ 重置）。

  调用顺序（libretro_engine.cpp L1329-1340）：
  ```cpp
  if (coreLoader_.IsLoaded()) {
    UnloadGameIfNeeded("switch_core");
    // T8-A-F2: 在 UnloadCore (dlclose) 之前清零 DiskController callbacks_
    if (diskController_) {
      diskController_->ClearCallbacks();   // ← step 1
    }
    if (coreLoader_.GetDeinit()) {
      coreLoader_.GetDeinit()();           // ← step 2: retro_deinit
    }
    coreLoader_.UnloadCore();              // ← step 3: dlclose
  }
  ```
  顺序正确：`ClearCallbacks()` 在 `UnloadCore()` (dlclose) **之前**调用，符合 finding 要求。

- **notes (nice-to-have 未做):**
  原 finding suggested_fix 建议在 `HandleMessage Stop`（L1309-1313）也调用一次 `ClearCallbacks()` 作为防御性清理。
  当前 Stop 路径代码：
  ```cpp
  case MessageType::Stop:
    stopRequested_.store(true);
    UnloadGameIfNeeded("stop");
    TransitionTo(EngineState::STOPPING);
    break;
  ```
  Stop 路径中**未调用** `ClearCallbacks()`。

  原 finding 分析："Stop 路径（HandleMessage Stop → UnloadGameIfNeeded → 但不 UnloadCore）不触发此问题，仅换核路径触发。" Stop 不执行 `dlclose`，因此不会造成悬空指针问题——此项**不是必须项**，只是防御性建议。

  主 Claude 判定此项为 "建议同时在 HandleMessage Stop 也调用一次，作为防御性清理" 且说明 "nice-to-have，如果没做不算 MISSING"。**不影响 COMPLETE 判定，但记录在案，供后续按需补充。**

---

## F3: GetSRAM/SetSRAM 调用顺序 (size → data)

- **status: COMPLETE**
- **evidence:**

  `GetSRAM`（core_state_manager.cpp L90-98）：
  ```cpp
  // T8-A-F3: 先查 size 再取 data 指针——libretro 惯用顺序。
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (size == 0) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr) {
    return false;
  }
  ```

  `SetSRAM`（core_state_manager.cpp L114-122）：
  ```cpp
  // T8-A-F3: 先 size 再 data，与 GetSRAM 保持一致。
  size_t size = sizeFn(RETRO_MEMORY_SAVE_RAM);
  if (size == 0) {
    return false;
  }
  void *ptr = dataFn(RETRO_MEMORY_SAVE_RAM);
  if (!ptr) {
    return false;
  }
  ```

  顺序已从 `dataFn → sizeFn` 改为 `sizeFn → dataFn`，`size == 0` 时提前 return，与 suggested_fix 完全一致。两个函数均已修复。

- **notes:** 无遗漏。

---

## F4: IStateManager 死代码接口删除

- **status: COMPLETE**
- **evidence:**

  `entry/src/main/cpp/interfaces/state/i_state_manager.h` 已从工作树删除：
  - `Glob` 搜索该路径返回空结果（文件不存在）。
  - `git diff HEAD -- entry/src/main/cpp/interfaces/state/i_state_manager.h` 显示 `deleted file mode 100644`，即文件已被 staged git rm。
  - git log 显示该文件仅出现在初始提交 `0493afc init clean source`，当前 HEAD 不再追踪该文件。

  选项 A（推荐）已执行：直接删除死代码接口文件。

- **notes:** 无。

---

## F5: size==0 静默失败增加区分性日志

- **status: COMPLETE**
- **evidence:**

  `SaveState`（core_state_manager.cpp L45-50）：
  ```cpp
  size_t size = sizeFn();
  if (size == 0) {
    // T8-A-F5: 区分"游戏未加载"vs"core serialize 内部出错"——便于排查。
    LOGF(LOG_WARN, "SaveState: serialize_size returned 0 (game state may not be ready)");
    return false;
  }
  ```

  `LoadState`（core_state_manager.cpp L62-67）：
  ```cpp
  if (!coreLoader_.IsLoaded() || data.empty()) {
    // T8-A-F5: 区分 "core 未加载" vs "传入空 data"。
    if (data.empty()) {
      LOGF(LOG_WARN, "LoadState: input data is empty");
    }
    return false;
  }
  ```

  两条路径均已补充区分性 LOG_WARN，与 suggested_fix 要求一致。

  注：finding 提到"更根本的修复是在 LibretroEngine 层增加状态机 guard（F1）"——F1 已完整实现，使正常路径下 `CoreStateManager::SaveState` 的 `size==0` 路径仅在 core 本身有问题时触发，日志描述也准确反映了这一点（"may not be ready"）。

- **notes:** 无遗漏。

---

## 汇总

| Finding | 严重级 | status | 备注 |
|---------|--------|--------|------|
| F1: SaveState/LoadState 5 函数 state guard | P1 | COMPLETE | 5/5 函数全覆盖 |
| F2: DiskController ClearCallbacks 换核路径 | P1 | COMPLETE | Stop nice-to-have 未做，不影响判定 |
| F3: GetSRAM/SetSRAM size→data 顺序 | P2 | COMPLETE | |
| F4: i_state_manager.h 死代码删除 | P2 | COMPLETE | git rm 已 staged |
| F5: size==0 区分日志 | P2 | COMPLETE | |

**4 COMPLETE, 0 PARTIAL, 0 MISSING, 0 REGRESSION**

### 待跟进（非阻塞）

- **F2 Stop 路径 ClearCallbacks（nice-to-have）**: `HandleMessage Stop` 未调用 `ClearCallbacks()`。因 Stop 路径不执行 `dlclose`，无悬空指针风险，可在下一个迭代周期按需补充，不影响当前 fix 完整性。
