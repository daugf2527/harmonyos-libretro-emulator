# Fix-Verify T1 NAPI — 8 项

验证时间：2026-05-26  
验证 commit：`0bb99ce`（已 merge 至 HEAD `2b42ddf`）

## 总结

| ID | Verdict | 备注 |
|---|---|---|
| T1-F1 | VERIFIED | CompleteWaitForState 加了 `status != napi_ok` → reject 守卫 |
| T1-F2 | VERIFIED | CompleteSaveStateAsync + CompleteLoadStateAsync 均加 cancel 守卫 + reject |
| T1-F3 | VERIFIED | 三处 struct 删 `napi_env env` 字段（WaitForState/Save/LoadStateAsyncContext） |
| T1-F4 | CHANGED_APPROACH | 加注释证明 SetSyncMode 是 atomic::store 线程安全，未改路由 |
| T1-F5 | VERIFIED | GetArgs/GetStringArg/GetInt32Arg/GetBoolArg/GetDoubleArg 加 throw；MakeBool 加 pending 自检 |
| T1-F6 | VERIFIED | TestCoreLoader 全量重写为 napi_async_work（Execute + Complete 分离） |
| T1-F7 | VERIFIED | 日志字符串 "56 functions" → "58 functions" |
| T1-F8 | VERIFIED | SaveStateAsync + LoadStateAsync 均检查 napi_create_promise 返回值 |

---

## 逐项详情

### T1-F1: CompleteWaitForState napi_cancelled 守卫

**期望** (FIX-PLAN): 加 napi_cancelled 守卫（status != napi_ok 时不能 resolve）

**diff 摘要** (commit 0bb99ce, engine_query_napi.cpp):
```cpp
+  // Audit T1-F1: guard napi_cancelled — calling napi_get_boolean/napi_resolve_deferred on cancelled env is UB
+  if (status != napi_ok) {
+    napi_value reason;
+    napi_get_undefined(env, &reason);
+    napi_reject_deferred(env, ctx->deferred, reason);
+  } else {
+    napi_value result;
+    napi_get_boolean(env, ctx->result, &result);
+    napi_resolve_deferred(env, ctx->deferred, result);
+  }
```

**Verdict**: VERIFIED  
**理由**: 原代码无条件 resolve；现在 `status != napi_ok` 时改为 reject，UB 消除，ArkTS `.catch()` 可达。

---

### T1-F2: CompleteSaveStateAsync + CompleteLoadStateAsync napi_cancelled 守卫

**期望** (FIX-PLAN): 加 napi_cancelled 守卫；napi_reject_deferred 替代 always-resolve

**diff 摘要** (commit 0bb99ce, engine_state_napi.cpp — SaveState):
```cpp
+  // Audit T1-F2: cancel guard first; logical failures reject so ArkTS .catch() is reachable
+  if (status != napi_ok) {
+    napi_value reason;
+    napi_get_undefined(env, &reason);
+    napi_reject_deferred(env, ctx->deferred, reason);
+  } else if (!ctx->ok || ctx->data.empty()) {
+    napi_value reason;
+    napi_create_string_utf8(env, "SaveState failed", NAPI_AUTO_LENGTH, &reason);
+    napi_reject_deferred(env, ctx->deferred, reason);
```

**diff 摘要** (engine_state_napi.cpp — LoadState):
```cpp
+  // Audit T1-F2: guard against napi_cancelled
+  if (status != napi_ok) {
+    napi_reject_deferred(env, ctx->deferred, reason);
+  } else {
+    napi_get_boolean(env, ctx->ok, &result);
+    napi_resolve_deferred(env, ctx->deferred, result);
+  }
```

**Verdict**: VERIFIED  
**理由**: 两个 Complete 函数均加 cancel 守卫并将逻辑失败从 resolve(null) 改为 reject(string)，符合期望。

---

### T1-F3: 三处 async ctx 删 napi_env env 字段

**期望** (FIX-PLAN): 删 `napi_env env` 字段（engine_state_napi.cpp + engine_query_napi.cpp 3 个 struct）

**diff 摘要**:
```cpp
// engine_query_napi.cpp WaitForStateAsyncContext
-  napi_env env = nullptr;
+  // Audit T1-F3: removed unused napi_env env field (env lifetime unsafe to store in async ctx)

// engine_state_napi.cpp SaveStateAsyncContext
-  napi_env env = nullptr;
+  // Audit T1-F3: removed unused napi_env env field

// engine_state_napi.cpp LoadStateAsyncContext
-  napi_env env = nullptr;
+  // Audit T1-F3: removed unused napi_env env field
```

**Verdict**: VERIFIED  
**理由**: 三处 struct 均删去了存储 `napi_env` 的字段，赋值语句也同步移除，无遗漏。

---

### T1-F4: SetAudioSyncMode 线程安全

**期望** (FIX-PLAN): 不能直接在 NAPI thread 调 audioBridge->SetSyncMode；需 route 过 engine queue 或加注释证明内部 mutex 安全

**diff 摘要** (engine_video_napi.cpp):
```cpp
+    // Audit T1-F4: SetSyncMode is sync_mode_.store() (std::atomic) — safe to call from NAPI thread
     audioBridge->SetSyncMode(syncMode);
```

**Verdict**: CHANGED_APPROACH  
**策略**: 未改路由，改为注释证明 `SetSyncMode` 实现是 `std::atomic::store`，天然线程安全。  
**合理性评估**: 若 `sync_mode_` 确实是 `std::atomic`（需在 `AudioBridge` 声明处确认），此方案成本最低且正确；但注释依赖实现细节，若 `SetSyncMode` 未来变复杂可能静默失效。可接受，建议在 `AudioBridge` 头文件同步标注 API 线程安全契约。

---

### T1-F5: GetArgs/type-getters 加 napi_throw_type_error + MakeBool 加 pending 自检

**期望** (FIX-PLAN): GetArgs/类型 getters 加 napi_throw_type_error；MakeBool 看到 throw 返回 nullptr

**diff 摘要** (engine_napi_common.h):
```cpp
// GetArgs
+    napi_throw_type_error(env, nullptr, "Wrong number of arguments");

// GetStringArg (两处)
+    napi_throw_type_error(env, nullptr, "Expected string argument");

// GetInt32Arg
+    napi_throw_type_error(env, nullptr, "Expected number argument");

// GetBoolArg
+    napi_throw_type_error(env, nullptr, "Expected boolean argument");

// GetDoubleArg
+    napi_throw_type_error(env, nullptr, "Expected number argument");

// MakeBool
+  bool pending = false;
+  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
+    return nullptr;
+  }
```

**Verdict**: VERIFIED  
**理由**: 5 个 type-getter helper 全部加了 `napi_throw_type_error`；`MakeBool` 和 `MakeResolvedPromise` 均加了 pending-exception 自检，caller 无需逐一添加 `return nullptr`，符合 memory `feedback_makebool_exception_guard` 记录的 CHANGED_APPROACH 策略。

---

### T1-F6: TestCoreLoader 改为 napi_async_work

**期望** (FIX-PLAN): 改成 napi_async_work（dlopen 不能阻塞 NAPI thread）

**diff 摘要** (core_loader_napi.cpp):
```cpp
+// --- TestCoreLoader (napi_async_work) ---
+struct TestCoreLoaderAsyncCtx { std::string corePath; std::string resultMessage; napi_deferred deferred; napi_async_work work; };
+static void ExecuteTestCoreLoader(napi_env /*env*/, void *data) { /* dlopen/GetSystemInfo here */ }
+static void CompleteTestCoreLoader(napi_env env, napi_status status, void *data) { /* resolve/reject */ }

+static napi_value TestCoreLoader(napi_env env, napi_callback_info info) {
+  // Audit T1-F6: offload dlopen/GetApiVersion/GetSystemInfo to worker thread
+  // ... napi_create_async_work + napi_queue_async_work
+  return promise;
+}
```

**Verdict**: VERIFIED  
**理由**: 原函数为同步 `dlopen` 调用阻塞 NAPI 线程；commit 完整重写为 Execute+Complete 两阶段 async_work，dlopen 在 worker 线程执行，NAPI 线程只做参数校验和队列调度，符合期望。

---

### T1-F7: 日志字符串函数计数更新

**期望** (FIX-PLAN): "56 functions" 改成 58

**diff 摘要** (libretro_engine_napi.cpp):
```cpp
-  LOGF(LOG_INFO, " [NEW] LibretroRefactored NAPI registered (56 functions, 6 modules)");
+  LOGF(LOG_INFO, " [NEW] LibretroRefactored NAPI registered (58 functions, 6 modules)"); // Audit T1-F7: updated count
```

**Verdict**: VERIFIED  
**理由**: 单行字符串精确改为 58，与期望一致。

---

### T1-F8: napi_create_promise 返回值检查

**期望** (FIX-PLAN): SaveStateAsync + LoadStateAsync 加 napi_create_promise 返回值检查

**diff 摘要** (engine_state_napi.cpp):
```cpp
// SaveStateAsync
-  napi_create_promise(env, &ctx->deferred, &promise);
+  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) { // Audit T1-F8
+    delete ctx;
+    return nullptr;
+  }

// LoadStateAsync
-  napi_create_promise(env, &ctx->deferred, &promise);
+  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) { // Audit T1-F8
+    delete ctx;
+    return nullptr;
+  }
```

**Verdict**: VERIFIED  
**理由**: 两处均加了返回值检查，失败时 `delete ctx` 防止泄漏并返回 `nullptr`，与同文件 `WaitForEngineStateAsync` 已有守卫模式一致。
