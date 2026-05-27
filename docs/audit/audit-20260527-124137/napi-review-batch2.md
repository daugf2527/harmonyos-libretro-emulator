# T8 批次 2 NAPI Review

review-id: napi-review-batch2-20260527
date: 2026-05-27
reviewer: napi-boundary-reviewer
files: engine_state_napi.cpp, entry/src/main/cpp/types/libentry/index.d.ts

---

## Checklist

### A. napi_cancelled 处理正确性

**A.1 cancelled 分支内是否完全无其他 napi_* 调用**

结论: PASS

CompleteSaveStateAsync (L282-290)、CompleteLoadStateAsync (L390-398)、
CompleteGetSaveStateSizeAsync (L35-43) 三处 cancelled 分支内只有：
LOGF（非 NAPI 调用）、napi_delete_async_work（见 A.2 讨论）、delete ctx。
无 napi_resolve_deferred / napi_reject_deferred / napi_create_* / napi_get_* 等
JS 交互调用。

**A.2 napi_delete_async_work 在 napi_cancelled 时是否安全**

结论: CONCERN（见 Concern-1）

HarmonyOS SDK native_api.h 文档："The work should not be deleted before the complete
callback invocation, even if it has been successfully cancelled." 说明 complete callback
内调用 napi_delete_async_work 是合法时机。

napi_cancelled 触发有两种路径：
(a) 显式 napi_cancel_async_work（env 完全有效，调用绝对安全）
(b) env teardown（运行时销毁阶段）

Node.js NAPI 规范中 complete callback 总在 env 被最终销毁之前的 drain 阶段调用，
因此 env 在回调内仍有效。HarmonyOS SDK 文档未对此场景作出明确声明。当前实现
与整个项目所有 async_work 完全一致（engine_lifecycle_napi.cpp / engine_query_napi.cpp
均在 complete 内 delete_async_work），评级降为 CONCERN 而非 FAIL。

**A.3 delete ctx 后无 use-after-free 风险**

结论: PASS

三处 cancelled 分支均在 delete ctx 后立即 return，后续无任何对 ctx 字段的访问。
ctx->work 在 delete 前置 nullptr，内存状态干净。

**A.4 与 Audit T1-F2 注释一致性**

结论: PASS

原 T1-F2 注释（现 CompleteLoadStateAsync L400）"guard against napi_cancelled" 实际是
status != napi_ok 合并处理（cancelled 和其他错误放同一分支）。T8-B-F4 在三处 Complete
函数中均拆出独立 cancelled 分支，语义更精确：cancelled = env 已撤销不能做 JS 操作；
其他错误 = env 有效可以 reject。三个 Complete 函数现在结构完全对齐。

---

### B. GetSaveStateSizeAsync 资源生命周期

**B.1 context struct 字段在所有 path 是否正确清理**

结论: PASS（含 Concern-2 关于 create_promise 失败路径的接口一致性问题）

- napi_create_promise 失败（L64-67）：delete ctx + return nullptr。
  deferred 和 work 均未初始化，无泄漏。
- napi_create_async_work 失败（L73-79）：resolve_deferred(0) + delete ctx。
  work 为 nullptr 无需 delete_async_work，正确。
- napi_queue_async_work 失败（L82-91）：delete_async_work + resolve_deferred(0) + delete ctx。
  顺序正确。
- 正常路径（排队成功）：Complete 回调清理 work + delete ctx。

**B.2 napi_create_promise 失败 → return nullptr 的 ArkTS 端影响**

结论: CONCERN（见 Concern-2）

GetSaveStateSizeAsync (L64-67) 和 SaveStateAsync (L330-333) 在 create_promise 失败时
return nullptr，ArkTS 侧收到 null/undefined 而非 Promise，await 会抛类型错误。
LoadStateAsync (L441-444) 在同一情况下 return MakeResolvedPromise(env, false)，
返回可 await 的 resolved Promise。三者行为不一致。

**B.3 create_async_work 失败 → resolve_deferred(0) 后 delete ctx**

结论: PASS

resolve_deferred 在 delete ctx 前调用，deferred 被消费后 delete ctx 安全，无双重释放。

**B.4 queue_async_work 失败 → delete_async_work + resolve_deferred(0) + delete ctx**

结论: PASS

正确顺序：先 delete_async_work（释放 work 句柄），再 resolve_deferred（不触碰 work），
再 delete ctx。work 已置 nullptr，无双重释放风险。

---

### C. TSFN 相关

**C.1 确认无误增 TSFN**

结论: PASS

本次改动全部为 napi_async_work 模式，无任何 napi_create_threadsafe_function /
napi_acquire_threadsafe_function / napi_release_threadsafe_function 调用。
GetSaveStateSizeAsync 不需要从 worker thread 回调 ArkTS，模式选择正确。

---

### D. State guard 与异步的耦合

**D.1 ExecuteGetSaveStateSizeAsync 在 worker thread 调用 GetSaveStateSize 的 TOCTOU**

结论: CONCERN（见 Concern-3）

GetSaveStateSize 在 worker thread 执行：
1. state_.load() 原子读 IsGameLoadedState 检查
2. 检查通过后 ExecuteSyncTask 向 engine 消息队列 push SyncTask 并 Wait(5000ms)

竞态窗口：step 1 通过后游戏被卸载，SyncTask 执行时 stateManager_ 已 teardown。
engine 端 stateManager_ 空指针检查会拦截，返回 size=0，无 crash。

async 版比 sync 版竞态窗口更大（worker thread 调度延迟可达数十 ms），但结果有界（返回 0），
与 C++ 注释"返回 0 已是死路"的设计意图一致。SaveState/LoadState 同样存在此 TOCTOU，
不是本次引入的新问题。

**D.2 ExecuteSyncTask 从 worker thread 的死锁分析**

结论: PASS

ExecuteSyncTask 内部有 kSyncTaskTimeoutMs=5000ms 超时保护，不会永远阻塞。
worker thread 的 g_engineThreadInstance（thread_local）为 nullptr，不等于 this，
正确走消息队列路径而非快速路径。各 SyncTask 使用独立 condition_variable，无锁竞争。

---

### E. Error path 一致性

**E.1 基础设施错误 resolve(0) 与"正常 size=0"语义混淆**

结论: CONCERN（见 Concern-4）

create_async_work 失败（L73-79）和 queue_async_work 失败（L82-91）是运行时内部错误，
不应与"游戏未加载 size=0"混淆。当前两类情况均 resolve(0)，ArkTS 调用方无法区分。
SaveStateAsync 在同类失败时 resolve(null)，语义已优于 resolve(0)。
当前无 ArkTS 调用方，不阻塞合并，建议下轮改为 reject。

---

### F. index.d.ts 契约

**F.1 () => Promise<number> 类型与实现匹配**

结论: PASS

C++ 侧 napi_create_int64(env, static_cast<int64_t>(ctx->size), &result) 对应
TypeScript Promise<number>。size_t 在 HarmonyOS ARMv7 上最大 4GB，JS number 可无损
表示 2^53 以内整数，无精度问题。

**F.2 同步版 refactoredGetSaveStateSize 缺 @deprecated 标注**

结论: CONCERN（见 Concern-5）

index.d.ts L83 同步版与 L84 异步版共存，C++ 注释已说"新调用方应使用 Async 变体"，
但 d.ts 无任何标注，调用方可能误用同步版阻塞 NAPI 线程最长 5s。

---

### G. mutex / 线程顺序

**G.1 async worker thread 调用 ExecuteSyncTask 的线程安全性**

结论: PASS

ExecuteSyncTask 有超时保护（5000ms），worker thread 不持有 engine 层锁，
各 SyncTask 互不竞争。无死锁风险。超时时 GetSaveStateSize 返回 0，
Complete 回调 resolve(0)。

---

## 必修问题

无 FAIL 项，无需强制修复。

---

## 建议（CONCERN 汇总）

**Concern-1（A.2）napi_delete_async_work 在 cancelled complete 回调内的文档空白**

HarmonyOS SDK 文档未明确背书 env teardown 场景下 napi_delete_async_work 的安全性。
当前实现与全项目一致，可接受。若后续发现 HarmonyOS 实现有特殊限制，需全项目统一修改。
不阻塞合并。

**Concern-2（B.2）create_promise 失败路径不一致**

GetSaveStateSizeAsync (L64-67) 和 SaveStateAsync (L330-333)：return nullptr。
LoadStateAsync (L441-444)：return MakeResolvedPromise(env, false)。
建议前两处对齐为返回可 await 的 resolved Promise，而不是让 ArkTS 侧收到非 Promise 值。

修复方向（GetSaveStateSizeAsync）：引入 MakeResolvedInt64Promise(env, 0) 辅助函数，
类似已有的 MakeResolvedPromise(env, bool)，create_promise 失败时用二次 create_promise
resolve(0) 返回。

**Concern-3（D.1）async 版 TOCTOU 窗口大于 sync 版**

不需要 C++ 层改动。建议 ArkTS 调用方对 size==0 做"游戏未加载"判断，
不要把 0 当作合法存档大小使用。

**Concern-4（E.1）基础设施错误 resolve(0) 语义模糊**

建议 create_async_work 和 queue_async_work 失败时改为 reject：
  napi_value errMsg;
  napi_create_string_utf8(env, "GetSaveStateSizeAsync infra error", NAPI_AUTO_LENGTH, &errMsg);
  napi_reject_deferred(env, ctx->deferred, errMsg);
当前无 ArkTS 调用方，改动安全，优先级低。

**Concern-5（F.2）index.d.ts 同步版缺 @deprecated 注释**

建议在 entry/src/main/cpp/types/libentry/index.d.ts L83 前加：
  /** @deprecated 阻塞 NAPI 线程最长 5s，新调用方请使用 refactoredGetSaveStateSizeAsync */
  export const refactoredGetSaveStateSize: () => number;

**Concern-6（范围外）其他 Complete 函数 cancelled 处理不一致**

engine_lifecycle_napi.cpp 的 CompleteGetRawFileListAsync (L217)、
CompleteStopEngineAsync (L825) 和 core_loader_napi.cpp 的 CompleteTestCoreLoader (L537)
均未单独处理 napi_cancelled，在 env teardown 时会调用 napi_create_string_utf8 +
napi_reject_deferred，属于 UB。不在本批次范围，建议下轮统一补齐。

---

## 总结

**PASS**

无 FAIL 项，5 项 CONCERN（+ 1 范围外旁观）均不阻塞合并。

T8-B-F4 的 napi_cancelled 单独分支逻辑正确，三个 Complete 函数结构完全对齐，
没有遗漏任何 napi_* 调用。
T8-B-F3 的 GetSaveStateSizeAsync 实现遵循既有模式，资源生命周期在所有错误路径下
正确清理，无泄漏。
index.d.ts 类型契约（() => Promise<number>）与 C++ 实现完全匹配。

优先修复建议（按影响排序）：
1. Concern-2：create_promise 失败路径对齐（ArkTS 接口安全性）
2. Concern-4：基础设施错误改为 reject（语义清晰）
3. Concern-5：d.ts 加 @deprecated（误用预防）
4. Concern-6：其他 Complete 函数 cancelled 处理（下轮统一修复）
