# T8-B NAPI 审计报告 — SaveState / SRAM / Disk I/O 持久化

**审计者**: T8-B 子代理  
**审计时间**: 2026-05-27  
**Scope**: engine_state_napi.cpp / engine_disk_napi.cpp / core_loader_napi.cpp (部分) / index.d.ts  
**审计框架**: NAPI hazard checklist P0/P1/P2  

---

## 文件概览

| 文件 | 行数 | 主要职责 |
|---|---|---|
| `engine_state_napi.cpp` | 387 | SaveState/LoadState/SRAM/Cheat/CoreOptions NAPI 入口 |
| `engine_napi_common.h` | 235 | 共享 helper（MakeBool/GetArgs/GetArrayBufferArg 等） |
| `engine_disk_napi.cpp` | 103 | DiskControl 7 个 NAPI 入口 |
| `core_loader_napi.cpp` | — | 无 SaveState/SRAM 入口（grep 确认） |
| `index.d.ts` | 171 | ArkTS 类型声明 |

---

## Findings

### F1 — SyncTask 超时后栈变量悬挂（P0）

**Severity**: P0  
**File**: `entry/src/main/cpp/core/engine/libretro_engine.cpp`  
**Lines**: 46–84, 975–999, 2582–2648  

**evidence_excerpt**:
```cpp
// libretro_engine.cpp L68-77
bool Wait(uint32_t timeoutMs) {
    std::unique_lock<std::mutex> lock(mutex_);
    const bool ok = cond_.wait_for(
        lock, std::chrono::milliseconds(timeoutMs),
        [this]() { return done_; });
    if (!ok) {
      abandoned_.store(true, std::memory_order_release);
    }
    return ok;
}

// L989-997 — ExecuteSyncTask
auto syncTask = std::make_shared<EngineSyncTask>(task);
// ...
if (!syncTask->Wait(timeoutMs)) {
    LOGF(LOG_ERROR, "[NEW] SyncTask timeout after %{public}u ms", timeoutMs);
    return false;   // <-- Wait 返回 false 后 syncTask shared_ptr 的引用计数降至 1
}
return true;

// 在 SaveState 调用链里（L2582-2598）
bool LibretroEngine::SaveState(std::vector<uint8_t> &outData) {
    bool ok = false;
    std::vector<uint8_t> snapshot;            // <-- 栈上对象
    if (!ExecuteSyncTask(
        [this, &ok, &snapshot]() { ... },     // <-- lambda 捕获栈引用
        kSyncTaskTimeoutMs)) {
      return false;  // 调用方返回，栈帧销毁
    }
```

**claim**:  
`ExecuteSyncTask` 超时后（`kSyncTaskTimeoutMs = 5000ms`），调用方从 `SaveState` / `GetSRAM` / `LoadState` / `SetSRAM` 函数返回，**栈上 `snapshot` 和 `ok` 变量被销毁**。此时 Engine 线程里的 `EngineSyncTask` 仍持有 `shared_ptr` 引用（message queue 里的 `EngineMessage` 持有 `shared_ptr`）。当 Engine 线程最终执行该 task 时，lambda 里的 `&ok` 和 `&snapshot` 是悬挂引用，写入行为是 UB（undefined behavior）。

`EngineSyncTask::Run()` 里有 `abandoned_` 守卫（L51-56），当 Wait 超时后会设置 `abandoned_ = true`，Engine 线程执行时 `abandoned_` 为 true 时跳过 `task_()` 调用。**守卫逻辑是对的，但存在 TOCTOU 窗口**：`Wait()` 超时 → 设置 `abandoned_=true` → 调用方返回栈销毁（期间 Engine 线程可能恰好检查 `abandoned_` 是 false 并开始执行 lambda）。若 Engine 线程在 `abandoned_.store` 之前读到 `abandoned_=false` 并开始执行 task，引用已悬挂。

atomic `release`/`acquire` 排序确保了 `abandoned_=true` 对 Engine 线程可见，但执行检查与执行 lambda 之间没有锁保护，仍有极小窗口。**在实践中场景的触发概率低，但超时场景（核心卡 5s）确实会发生，此时是真实 UB 风险。**

**suggested_fix**:  
方案一（保守）：在 `EngineSyncTask::Run()` 中加 mutex 保护 `abandoned_` 检查与 `task_()` 执行：
```cpp
void Run() {
    std::lock_guard<std::mutex> lock(mutex_);  // 与 Wait 的 mutex 同一个
    if (!abandoned_.load(std::memory_order_relaxed)) {
        if (task_) task_();
    }
    done_ = true;
    cond_.notify_all();
}
```
Wait() 内在持有 lock 的情况下设置 `abandoned_`，保证 Run() 检查与执行之间无竞争。

方案二（更彻底）：改 NAPI 侧为 heap 捕获（把 `ok`/`snapshot` 放在 shared context 对象上），与 SaveStateAsync 的 ctx 模式统一。

---

### F2 — DiskControl 函数直接在 NAPI 线程调用 DiskController（P1）

**Severity**: P1  
**File**: `entry/src/main/cpp/app/napi/engine_disk_napi.cpp` 和 `entry/src/main/cpp/core/engine/libretro_engine.cpp`  
**Lines**: disk_napi.cpp L3–88, engine.cpp L2422–2465  

**evidence_excerpt**:
```cpp
// engine_disk_napi.cpp L3-16
static napi_value DiskControlSetEjectState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  // ...
  bool ok = GetEngine()->DiskControlSetEjectState(ejected);   // 直接调用
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

// libretro_engine.cpp L2424-2428
bool LibretroEngine::DiskControlSetEjectState(bool ejected) {
    if (!diskController_)
      return false;
    return ejected ? diskController_->Eject() : diskController_->Insert();
    // 注意：无 ExecuteSyncTask！直接调 DiskController
}
```

**claim**:  
`DiskController::Eject()`/`Insert()`/`SetImageIndex()` 等方法内部加了 `std::mutex` 保护（`disk_controller.cpp` 全文确认 `lock_guard`），但这些方法最终回调的是 core 的 `retro_disk_control_ext_callback::set_eject_state` 等函数指针。libretro core 的 disk callbacks 通常要求在 **retro_run 调用期间** 的 game loop context 中执行（参考 libretro API spec），而 NAPI 线程直接调用可能在 retro_run 之外的任意时刻触发，导致 **core 内部状态不一致**（core 可能正在读磁盘 / 切换 ISO）。

与 SaveState/SRAM 操作走 `ExecuteSyncTask` 进 Engine 线程不同，DiskControl 系列**绕过了 message queue**，在 NAPI 线程直接调用 core callback，这违反了注释里明确的"不在 NAPI 线程访问引擎状态"原则（CLAUDE.md C++ layer：`Never access engine state from NAPI callbacks without going through the engine message queue`）。

**suggested_fix**:  
将 DiskControl 系列操作改为走 `ExecuteSyncTask` 路径，如 SaveState 模式：
```cpp
bool LibretroEngine::DiskControlSetEjectState(bool ejected) {
    if (!diskController_) return false;
    bool ok = false;
    ExecuteSyncTask([this, ejected, &ok]() {
        ok = ejected ? diskController_->Eject() : diskController_->Insert();
    }, kSyncTaskTimeoutMs);
    return ok;
}
```

---

### F3 — GetSaveStateSize 同步阻塞 NAPI 线程最长 5s（P1）

**Severity**: P1  
**File**: `entry/src/main/cpp/app/napi/engine_state_napi.cpp` + `libretro_engine.cpp`  
**Lines**: state_napi.cpp L3–9, engine.cpp L2570–2580  

**evidence_excerpt**:
```cpp
// engine_state_napi.cpp L3-9
static napi_value GetSaveStateSize(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t size = GetEngine()->GetSaveStateSize();   // <-- 同步阻塞
  napi_value result;
  napi_create_int64(env, static_cast<int64_t>(size), &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

// engine.cpp L2570-2579
size_t LibretroEngine::GetSaveStateSize() {
    size_t size = 0;
    (void)ExecuteSyncTask([this, &size]() {
        if (stateManager_) size = stateManager_->GetSaveStateSize();
    }, kSyncTaskTimeoutMs);    // kSyncTaskTimeoutMs = 5000ms
    return size;
}
```

**claim**:  
`GetSaveStateSize` 通过 `ExecuteSyncTask` 最长同步等待 5000ms，阻塞调用它的 NAPI 线程。CLAUDE.md C++ layer 规范："**NAPI thread**: ArkTS ↔ C++ message exchange. **Do not block.**"。

与 `SaveState`/`LoadState` 同步变体（调用方一般是快速路径、游戏未运行时调用）相比，`GetSaveStateSize` 常在 UI 层用于提前检查是否支持存档，可能在游戏运行中调用。若 Engine 线程忙（正在渲染帧），该调用会阻塞 NAPI/UI 线程 5 秒。

此外，同步 `SaveState`/`LoadState`/`GetSRAM`/`SetSRAM` 也有同样问题（最长 5s 阻塞），但这些函数已有对应的 `*Async` 变体（`SaveStateAsync`/`LoadStateAsync`），只是 ArkTS 侧 `SaveStatePage.ets` 的 `quickSave()` 仍在使用同步 `refactoredSaveState()`（L249）。`GetSaveStateSize` 则无异步版本。

**suggested_fix**:  
1. 提供 `refactoredGetSaveStateSizeAsync(): Promise<number>` 变体，使 ArkTS 侧不必在主线程同步等待。
2. 或在 `SaveStatePage.ets` 的 `quickSave()` 改用已有的 `refactoredSaveStateAsync()`（`RuntimeSessionController.saveStateAsync()`），完全避开同步路径。

---

### F4 — LoadStateAsync 取消状态（napi_cancelled）处理不完整（P1）

**Severity**: P1  
**File**: `entry/src/main/cpp/app/napi/engine_state_napi.cpp`  
**Lines**: L287–312（CompleteLoadStateAsync）  

**evidence_excerpt**:
```cpp
// L293-305
static void CompleteLoadStateAsync(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<LoadStateAsyncContext *>(data);
    if (!ctx) return;

    if (status != napi_ok) {
        napi_value reason;
        napi_get_undefined(env, &reason);   // <-- 向已取消的 env 调用 NAPI
        napi_reject_deferred(env, ctx->deferred, reason);  // <-- UB on napi_cancelled
    } else {
        // ...
    }
```

**claim**:  
当 `status == napi_cancelled`（Worker 被终止/环境清理）时，`env` 可能已处于 teardown 状态。此时调用 `napi_get_undefined(env, ...)` 和 `napi_reject_deferred(env, ...)` 是对已销毁 env 的 NAPI 调用，属于 UB。

对照 `CompleteSaveStateAsync`（L190-226）的代码注释写着 `// Audit T1-F2: cancel guard first`，但实现里同样没有 `napi_cancelled` 特判，仍然调用了 NAPI 函数。注释说明这是已知 finding，但尚未真正修复。

**suggested_fix**:  
```cpp
if (status == napi_cancelled) {
    // env is tearing down — deferred will be GC'd, do not call NAPI
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    delete ctx;
    return;
}
if (status != napi_ok) {
    napi_value reason;
    napi_get_undefined(env, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
}
```
同样修复 `CompleteSaveStateAsync`。

---

### F5 — SaveStatePage.ets 使用同步 refactoredSaveState 阻塞 UI 主线程（P1）

**Severity**: P1  
**File**: `entry/src/main/ets/pages/SaveStatePage.ets`  
**Lines**: L249  

**evidence_excerpt**:
```typescript
// SaveStatePage.ets L241-267
private async quickSave(): Promise<void> {
    const token = this.beginPageTask()
    // ...
    try {
        const stateData = nativeApi.refactoredSaveState()   // <-- 同步 NAPI 调用
        if (!stateData || stateData.byteLength <= 0) {
            this.showToastMessage('SAVE_STATE_UNAVAILABLE')
            return
        }
        await saveStateData(context, stateData, this.currentRomFile)
```

**claim**:  
`quickSave()` 在 ArkTS UI 主线程调用同步 `refactoredSaveState()`，而这个调用最终在 C++ 侧走 `ExecuteSyncTask` 并阻塞等待 Engine 线程（最长 5000ms）。HarmonyOS ArkTS 主线程（UI 线程）被同步阻塞 5 秒会触发 ANR 或帧掉落。

`RuntimeSessionController` 已经封装了 `saveStateAsync()`（L58-60），`index.d.ts` 也有 `refactoredSaveStateAsync: () => Promise<ArrayBuffer | null>` 声明，但 `SaveStatePage` 使用了旧的同步 `SaveStateNapi` 接口（L16-19 的独立 interface），没有包含 Async 方法，绕过了 `RuntimeSessionController`。

**suggested_fix**:  
1. 将 `quickSave()` 改用 `refactoredSaveStateAsync()`：
```typescript
const stateData = await nativeApi.refactoredSaveStateAsync()
```
2. 或将 `SaveStatePage` 的 `nativeApi` 改用 `RuntimeSessionController` 并调用 `saveStateAsync()`。

---

### F6 — GetSaveStateSize 返回 size_t → int64_t 可能截断，且 index.d.ts 声明为 number（P2）

**Severity**: P2  
**File**: `entry/src/main/cpp/app/napi/engine_state_napi.cpp` + `index.d.ts`  
**Lines**: state_napi.cpp L7, index.d.ts L83  

**evidence_excerpt**:
```cpp
// engine_state_napi.cpp L7
napi_create_int64(env, static_cast<int64_t>(size), &result);
```
```typescript
// index.d.ts L83
export const refactoredGetSaveStateSize: () => number;
```

**claim**:  
`size_t` 在 64 位平台最大值为 `UINT64_MAX`，`static_cast<int64_t>` 会对超出 `INT64_MAX` 的值产生截断（实际上 save state 不可能超 8EB，此风险可忽略）。更重要的是 `index.d.ts` 声明为 `number`，JS `number` 是 64 位浮点，对超过 `2^53` 的整数有精度损失。此 finding 对实际运行影响极低（save state 通常 < 10MB），但类型精度契约不一致。

**suggested_fix**:  
声明改为 `bigint` 或保留 `number` 但在 C++ 侧加注释说明合理范围。低优先级。

---

### F7 — index.d.ts 缺失 CheatReset / CheatSet / GetCoreOptions / SetCoreOption 声明（P2）

**Severity**: P2  
**File**: `entry/src/main/cpp/types/libentry/index.d.ts`  
**Lines**: L83-170 对比 `engine_state_napi.cpp` L370–386  

**evidence_excerpt**:
```typescript
// index.d.ts — 已有声明
export const refactoredGetSaveStateSize: () => number;
export const refactoredSaveState: () => ArrayBuffer | null;
export const refactoredLoadState: (data: ArrayBuffer) => boolean;
export const refactoredSaveStateAsync: () => Promise<ArrayBuffer | null>;
export const refactoredLoadStateAsync: (data: ArrayBuffer) => Promise<boolean>;
export const refactoredGetSRAM: () => ArrayBuffer | null;
export const refactoredSetSRAM: (data: ArrayBuffer) => boolean;
export const refactoredResetCore: () => boolean;
// Cheat (index.d.ts L107-108)
export const refactoredCheatReset: () => boolean;
export const refactoredCheatSet: (index: number, enabled: boolean, code: string) => boolean;
// Core Options (index.d.ts L165-166)
export const refactoredGetCoreOptions: () => string;
export const refactoredSetCoreOption: (key: string, value: string) => boolean;
```

**claim**:  
实际查阅 `index.d.ts`（L107-108, L165-166）后确认 CheatReset/CheatSet/GetCoreOptions/SetCoreOption 均已有声明，与 C++ 侧 `RegisterStateNapi` 注册的 property 完全对应。**声明与实现一致，无缺口。**（本条为 auditor 初始假设后被证伪，记录以示已核验。）

**suggested_fix**: N/A（已正确）

---

### F8 — DiskControlReplaceImageIndex path 长度上限 1024 字节，index.d.ts 无约束说明（P2）

**Severity**: P2  
**File**: `entry/src/main/cpp/app/napi/engine_disk_napi.cpp`  
**Lines**: L71  

**evidence_excerpt**:
```cpp
// engine_disk_napi.cpp L71
char path[1024];
if (!GetInt32Arg(env, args[0], index, "DiskControlReplaceImageIndex", "index") ||
    !GetStringArg(env, args[1], path, sizeof(path), "DiskControlReplaceImageIndex", "path")) {
```

**claim**:  
`GetStringArg` 对超出 `outSize-1` 的字符串会 throw range_error（`engine_napi_common.h L105`），ArkTS 侧调用者若传入超长路径会收到一个 JS exception。这是**已正确处理的防御**，但 `index.d.ts` 的 `refactoredDiskControlReplaceImageIndex: (index: number, path: string) => boolean` 没有任何文档注释说明 path 长度限制，ArkTS 调用者无法提前知道 1024 字节上限。

鸿蒙文件路径最大通常 4096 字节（Linux `PATH_MAX`），1024 字节上限偏保守。若用户传入长路径（如带完整沙箱路径 `/data/storage/el2/base/.../very_long_filename.cue`），会在 C++ 侧 throw 但在 ArkTS 侧只有异常，没有文档警告。

**suggested_fix**:  
1. 将 `char path[1024]` 改为 `std::string` 动态分配，用 `napi_get_value_string_utf8` 的两阶段读取（先查长度再分配），彻底去掉硬限制。
2. 或在 `index.d.ts` 加注释：`// path: max 1023 bytes UTF-8`。

---

## 总结

| Finding | Severity | File | 状态 |
|---|---|---|---|
| F1: SyncTask 超时后栈引用悬挂（TOCTOU） | P0 | libretro_engine.cpp | 需修复 |
| F2: DiskControl 绕过 ExecuteSyncTask 直接调 core callback | P1 | engine_disk_napi.cpp + engine.cpp | 需修复 |
| F3: GetSaveStateSize 同步阻塞 NAPI 线程（无异步版本） | P1 | engine_state_napi.cpp | 需修复 |
| F4: CompleteLoadStateAsync/CompleteSaveStateAsync 未处理 napi_cancelled | P1 | engine_state_napi.cpp | 需修复 |
| F5: SaveStatePage.quickSave 使用同步 NAPI 阻塞 UI 主线程 | P1 | SaveStatePage.ets | 需修复 |
| F6: GetSaveStateSize size_t→int64_t 精度不一致（低风险） | P2 | engine_state_napi.cpp + index.d.ts | 低优先级 |
| F7: CheatReset/CheatSet/CoreOptions 声明（已核验一致） | N/A | index.d.ts | 无需操作 |
| F8: DiskControlReplaceImageIndex path 1024 字节上限无文档 | P2 | engine_disk_napi.cpp | 建议改善 |

**P0 总计**: 1  
**P1 总计**: 4  
**P2 总计**: 2（其中 F7 已排除）  

---

## 重要背景说明

1. **已完成修复（已有审计注释）**：`engine_state_napi.cpp` 里多处 `// Audit T1-F3`、`// Audit T1-F5`、`// Audit T1-F8` 注释表明前轮审计已修复了若干问题（env field 去除、pending-exception guard、create_promise 检查）。本报告 findings 均为当前代码的**残余/新发现**问题。

2. **DiskController 线程模型**：`disk_controller.cpp` 内部有 mutex 保护，但保护的是 DiskController 自身状态（`ejected_` 字段），不能保护 core callback 函数指针指向的 libretro core 内部状态（core 不知道有外部锁）。

3. **SaveStateAsync 路径正确**：`ExecuteSaveStateAsync` 在 napi_async_work worker 线程（非 NAPI 线程）调用 `GetEngine()->SaveState()`，再通过 `ExecuteSyncTask` 进入 Engine 线程执行，完整路径是：`ArkTS Promise → napi_async_work worker thread → ExecuteSyncTask → Engine thread`。堆捕获（ctx->data）正确，无悬挂。

4. **TSFN 使用范围**：本 scope 内（SaveState/SRAM/DiskControl）没有使用 TSFN；TSFN 只在 `EventBridge` 里用于事件回调，且已正确使用 `napi_tsfn_abort` 模式（audit memory 确认）。
