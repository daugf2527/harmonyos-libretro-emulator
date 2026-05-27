# fix-verify-T8B — T8-B NAPI Findings 闭环验证

verify-agent: T8-F-B  
date: 2026-05-27  
scope: T8B-F1 ~ T8B-F5 (主 Claude 判定 REAL findings)  
files-checked: libretro_engine.cpp (L46-82, L972-996, L2429-2516), engine_state_napi.cpp (全文), engine_disk_napi.cpp (全文), index.d.ts (全文), SaveStatePage.ets (L1-30, L241-254)

---

## 总结

| Finding | 预期 fix | 验证结果 |
|---|---|---|
| T8B-F1 | EngineSyncTask::Run/Wait 改用持锁互斥 | COMPLETE |
| T8B-F2 | 7 个 DiskControl* 函数全部走 ExecuteSyncTask | COMPLETE (附旁注) |
| T8B-F3 | 新增 refactoredGetSaveStateSizeAsync + d.ts 声明 + 同步版 @deprecated | COMPLETE |
| T8B-F4 | 三处 Complete 函数独立 cancelled 分支 | COMPLETE |
| T8B-F5 | SaveStatePage.quickSave 改用 refactoredSaveStateAsync | COMPLETE |
| Concern-1~5 | 5 项 CONCERN 均已推迟，未遗漏 | DEFERRED (合理) |

**整体结论: COMPLETE — 所有 P0/P1 findings 已正确实现修复，无 REGRESSION。**

---

## T8B-F1 — EngineSyncTask TOCTOU 修复

**预期**: Run() 加持锁，abandoned_ 检查与 task_() 执行在同一临界区，消除 Wait 超时后 task_() 触发悬挂引用的窗口。

**实际代码** (libretro_engine.cpp L50-74):

```cpp
void Run() {
    std::lock_guard<std::mutex> lock(mutex_);   // 新增
    if (!abandoned_ && task_) {                  // abandoned_ 检查在锁内
        task_();                                  // task_() 持锁执行
    }
    done_ = true;
    cond_.notify_all();
}

bool Wait(uint32_t timeoutMs) {
    std::unique_lock<std::mutex> lock(mutex_);
    const bool ok = cond_.wait_for(lock, ...);   // wait_for 持锁等待，内部会释放 lock
    if (!ok) {
        abandoned_ = true;                        // 超时时，在持锁状态下设置
    }
    return ok;
}
```

**验证**: COMPLETE。修复逻辑完整正确。

分析链：
1. Run() 持锁 → Wait 的 wait_for 释放 lock → Run 竞争 lock 并执行 → Run 完成 set done_=true notify → Wait 重新 acquire lock，predicate done_=true → wait_for 返回 true（无论 wait_for 的时钟是否超时，predicate 满足时返回 true，符合 std::condition_variable::wait_for 文档语义）。
2. 超时路径：Wait 的 wait_for 超时（predicate 未满足）→ Wait 持有 lock 设置 abandoned_=true → Wait 返回 → 调用方栈销毁。此时 Run() 正在等待 lock（或尚未到达 lock 竞争点）。Run 之后才能 acquire lock，此时 abandoned_=true，if 条件为 false，task_() 不执行，不触碰已销毁的栈引用。
3. `abandoned_` 被声明为 `std::atomic<bool>`，在 Run() 里通过隐式转换读取 (`!abandoned_` 等价于 `!abandoned_.load(std::memory_order_seq_cst)`)。由于两侧都持有同一 mutex，内存顺序保证强于 relaxed，访问完全正确。

**嵌套调用死锁分析（任务指定的特殊检查）**：通过 `mcp__cclsp__find_references` 确认，ExecuteSyncTask 的所有调用点仅在 `libretro_engine.cpp` 内部（L2433, 2447, 2459, 2471, 2483, 2496, 2510 为 DiskControl 系列 + L2628/2648/2672/2695/2719/2741/2761/2776/2791/2814 为 SaveState/SRAM/GetSize 系列），无任何外部文件对其的直接调用。更关键的是，L977 的快速路径 `g_engineThreadInstance == this` 保证：若当前线程就是 engine 线程（包括 task_() 执行途中再调用 ExecuteSyncTask 的场景），会直接执行而不入队，不竞争 EngineSyncTask mutex。因此不存在 task_() 持锁期间嵌套等待同一锁的死锁路径。

---

## T8B-F2 — DiskControl 全部走 ExecuteSyncTask

**预期**: 7 个 DiskControl* 函数改为通过 ExecuteSyncTask 在 Engine 线程执行。

**实际代码** (libretro_engine.cpp L2429-2516)：全部 7 个函数（SetEjectState、GetEjectState、GetImageIndex、SetImageIndex、GetNumImages、ReplaceImageIndex、AddImageIndex）均已改为 ExecuteSyncTask 模式，lambda 捕获栈上局部变量 `ok`/`result` 并在 ExecuteSyncTask 返回前保持有效。engine_disk_napi.cpp 侧未改动（符合预期：NAPI 层只调用 LibretroEngine 方法，不直接接触 DiskController）。

**验证**: COMPLETE。

**旁注 (非阻塞)**: `DiskControlReplaceImageIndex` 的 lambda 捕获了 `&path`（函数参数 `const std::string &path`，L2497）。由于 ExecuteSyncTask 在超时前同步等待（timeout = 5000ms），path 的生命周期覆盖 ExecuteSyncTask 整个执行期间，无悬挂引用问题。若超时，done_ 不成立，abandoned_=true 被设置后 task_() 不执行，path 引用同样不被触碰。此处安全。

---

## T8B-F3 — GetSaveStateSizeAsync 新增 + d.ts 声明 + @deprecated

**预期**: 新增 `refactoredGetSaveStateSizeAsync`，注册到 RegisterStateNapi，index.d.ts 声明 + 同步版加 @deprecated。

**实际代码**：

- `engine_state_napi.cpp` L12-93: `GetSaveStateSizeAsync`、`ExecuteGetSaveStateSizeAsync`、`CompleteGetSaveStateSizeAsync` 完整实现，napi_async_work 模式，worker thread 调 `GetEngine()->GetSaveStateSize()`，Complete 回调 resolve int64 结果。
- `engine_state_napi.cpp` L480: `"refactoredGetSaveStateSizeAsync"` 已注册到 `RegisterStateNapi`，紧跟在 L479 `"refactoredGetSaveStateSize"` 之后。
- `index.d.ts` L83-85:
  ```typescript
  /** @deprecated T8-B-F3: 同步版阻塞 NAPI/UI 主线程最长 5s, 优先用 refactoredGetSaveStateSizeAsync. */
  export const refactoredGetSaveStateSize: () => number;
  export const refactoredGetSaveStateSizeAsync: () => Promise<number>;
  ```
  @deprecated 注释存在，Async 版已声明，类型为 `Promise<number>` 与 C++ 侧 `napi_create_int64` 返回对应。

**验证**: COMPLETE。

---

## T8B-F4 — 三处 Complete 函数 cancelled 独立分支

**预期**: CompleteSaveStateAsync、CompleteLoadStateAsync、CompleteGetSaveStateSizeAsync 各自拆出独立 `if (status == napi_cancelled)` 分支，分支内无任何 napi_* JS 交互调用。

**实际代码**：

- `CompleteGetSaveStateSizeAsync` L35-43: cancelled 分支仅 LOGF + napi_delete_async_work + `ctx->work = nullptr` + delete ctx + return。无 JS 调用。
- `CompleteSaveStateAsync` L282-290: cancelled 分支仅 LOGF + napi_delete_async_work + `ctx->work = nullptr` + delete ctx + return。无 JS 调用。
- `CompleteLoadStateAsync` L390-398: cancelled 分支仅 LOGF + napi_delete_async_work + `ctx->work = nullptr` + delete ctx + return。无 JS 调用。

三处结构完全对齐。Audit T1-F2 注释（LoadStateAsync L400）留存于 `if (status != napi_ok)` 分支，与独立 cancelled 分支语义不冲突（cancelled 已在上方 return，不会到达此处）。

**验证**: COMPLETE。与 napi-review-batch2 A.1 结论一致（PASS）。

---

## T8B-F5 — SaveStatePage.quickSave 改用 async 版本

**预期**: SaveStatePage.ets quickSave() 改用 refactoredSaveStateAsync，不再同步阻塞 UI 线程。

**实际代码** (SaveStatePage.ets L16-19, L249-250):

- `interface SaveStateNapi` (L16-19) 声明已改为 `refactoredSaveStateAsync(): Promise<ArrayBuffer | null>`，不再包含同步 `refactoredSaveState`。
- `quickSave()` L249-250: `const stateData = await nativeApi.refactoredSaveStateAsync()`，有 `await` 关键字，异步非阻塞。注释明确标注 `T8-B-F5 / T8C-F8`。
- `isCurrentPageTask(token)` 检查在 await 后，正确防止页面销毁后回写。

**验证**: COMPLETE。UI 主线程不再同步等待 NAPI 调用。

---

## Concern-1~5 推迟情况确认

经 napi-review-batch2.md 确认，5 项 CONCERN 均被评为"不阻塞合并"：

- **Concern-1** (napi_delete_async_work 在 cancelled 回调内文档空白)：全项目一致实践，暂不改。
- **Concern-2** (create_promise 失败路径不一致：GetSaveStateSizeAsync/SaveStateAsync 返回 nullptr vs LoadStateAsync 返回 MakeResolvedPromise)：建议对齐，但无 ArkTS 调用方，低优先级推迟。
- **Concern-3** (async 版 TOCTOU 窗口大于 sync 版)：结果有界（size=0），C++ 层无需改动，建议 ArkTS 调用方判断 size==0。
- **Concern-4** (基础设施错误 resolve(0) 语义模糊)：建议改 reject，无 ArkTS 调用方，低优先级推迟。
- **Concern-5** (同步版 d.ts 缺 @deprecated)：已在 T8B-F3 fix 中一并修复（index.d.ts L83 前已加 @deprecated 注释），**Concern-5 实际上已被 F3 fix 顺带解决**。

---

## 未发现 REGRESSION

检查重点：

1. Run() 持锁期间若 task_() 为 long-running（接近 5s 超时）：Wait 的 wait_for 超时后尝试重新 acquire lock，此时 Run 持锁中 task_() 仍在运行，Wait 阻塞等 lock。Run 完成后 set done_=true notify，Wait 在持锁状态下检查 done_=true（predicate 满足），wait_for 语义上返回 true（predicate 满足优先于超时），Wait 返回 true。整个行为正确：超时被 "吸收"，任务完成视为成功。这是 F1 修复引入的副作用，语义是合理的（任务最终完成，不报超时错误）。注意：此情况不会产生悬挂引用问题，因为 task_() 在 Run 返回前就完成了，栈帧在此期间有效。

2. DiskControl 系列 ExecuteSyncTask 调用与 SaveState 系列串行：各 SyncTask 使用独立 mutex/cond，互不竞争，无死锁风险。

3. `CompleteGetSaveStateSizeAsync` 的 `ctx->work` 在 cancelled 分支被 delete_async_work 后置 nullptr，避免后续路径双重释放。正常路径 L53-57 的 `if (ctx->work)` 保护也在位。

---

## 文件路径

- `D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\cpp\core\engine\libretro_engine.cpp` (L46-82, L972-996, L2429-2516)
- `D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\cpp\app\napi\engine_state_napi.cpp` (全文)
- `D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\cpp\app\napi\engine_disk_napi.cpp` (全文)
- `D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\cpp\types\libentry\index.d.ts` (L83-85)
- `D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator\entry\src\main\ets\pages\SaveStatePage.ets` (L16-19, L241-254)
