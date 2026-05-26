# FIX-VERIFY-T2: libretro_engine.cpp 状态机 6 项 fix 验证

**验证日期**: 2026-05-26  
**目标 commit**: `0bb99ce`  
**验证人**: T2 Engine fix-verify agent  
**文件**: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

---

## 总结表

| ID | 描述 | 状态 |
|---|---|---|
| T2-F1 | IsValidTransition STOPPED case 加 LOADING | ✅ VERIFIED |
| T2-F2 | TransitionTo: notify_all 持 stateMutex_ 调用 | ✅ VERIFIED |
| T2-F3 | WaitForState timeoutMs==0 移除多余锁 + 注释 | ✅ VERIFIED |
| T2-F4 | Stop() 拆分锁范围 ctrlLock 在 wait_for 前 unlock | ✅ VERIFIED |
| T2-F5 | line 38 过时注释修正 | ✅ VERIFIED |
| T2-F6 | 3 处局部 g_engineInstance 重命名为 engine | ✅ VERIFIED (4处) |

**全部 6 项 VERIFIED。**

---

## 逐项详情

### T2-F1 — IsValidTransition STOPPED→LOADING

**期望**: STOPPED case 允许列表加入 `LOADING`。

**当前代码** (line 256-258):
```cpp
case EngineState::STOPPED:
  return to == EngineState::STARTING || to == EngineState::INIT ||
         to == EngineState::LOADING; // Audit T2-F1: allow STOPPED→LOADING
```

**判定**: ✅ VERIFIED — `LOADING` 已加入 STOPPED 允许列表，带 audit 注释。

---

### T2-F2 — TransitionTo: notify_all 持锁调用

**期望**: `stateCond_.notify_all()` 移到持 `stateMutex_` 时调用，防止通知丢失。

**当前代码** (line 2484-2486):
```cpp
{
  std::lock_guard<std::mutex> lk(stateMutex_); // Audit T2-F2: hold stateMutex_ before notify_all to prevent notification loss
  stateCond_.notify_all();
```

**判定**: ✅ VERIFIED — CAS 成功后在持 `stateMutex_` 的 lock_guard 范围内调用 notify_all。

---

### T2-F3 — WaitForState timeoutMs==0 移除多余锁

**期望**: timeoutMs==0 fast-path 是 atomic load，不需要持 stateMutex_；移除锁并加文档注释。

**当前代码** (line 2528-2538):
```cpp
bool LibretroEngine::WaitForState(EngineState target, uint32_t timeoutMs) {
  if (state_.load() == target) {
    return true;
  }
  if (timeoutMs == 0) {
    return state_.load() == target; // Audit T2-F3: non-blocking poll, no mutex needed
  }
  std::unique_lock<std::mutex> lock(stateMutex_);
  return stateCond_.wait_for(...);
}
```

**判定**: ✅ VERIFIED — timeoutMs==0 分支只做 atomic load，无 mutex；有 audit 注释说明原因。

---

### T2-F4 — Stop() 拆分锁范围

**期望**: 将 `lock_guard<recursive_mutex>` 改为 `unique_lock`，在 wait_for 之前 unlock，避免 controlMutex_ 持锁 5s 阻塞其他 API。

**当前代码** (line 443-470):
```cpp
bool LibretroEngine::Stop() {
  // Audit T2-F4: unique_lock so we can release before blocking wait
  std::unique_lock<std::recursive_mutex> ctrlLock(controlMutex_);
  ...
  ctrlLock.unlock(); // Audit T2-F4: release controlMutex_ before 5s wait
  ...
  stopCond_.wait_for(lock, std::chrono::milliseconds(STOP_TIMEOUT_MS), ...);
```

**判定**: ✅ VERIFIED — 改为 unique_lock 并在 wait_for 前 unlock，两处 audit 注释齐全。

---

### T2-F5 — 过时注释修正

**期望**: line 38 原注释称"析构函数不写回 nullptr"，但 line 324 确实写了 nullptr；修正为实际行为。

**当前代码** (line 38):
```cpp
//   - g_engineInstance 由构造函数写入,析构函数写回 nullptr (line 324)
```

**line 324 确认**:
```cpp
g_engineInstance.store(nullptr, std::memory_order_release);
```

**判定**: ✅ VERIFIED — 注释已更新为"写回 nullptr (line 324)"，与代码实际行为一致。

---

### T2-F6 — 局部变量 g_engineInstance 重命名为 engine

**期望**: ~2001/2118/2206 三处局部变量 `g_engineInstance` 改为 `engine`，消除对全局同名静态变量的 shadowing。

**当前 HEAD grep 结果** (4 处):
```
line 293:  LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
line 2004: LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
line 2121: LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
line 2209: LibretroEngine *engine = GetEngineInstanceSnapshot(); // Audit T2-F6: renamed from g_engineInstance to avoid shadowing global
```

**判定**: ✅ VERIFIED — 实际改了 4 处（diff 中可见 ~293/2001/2118/2206），FIX-PLAN 说"3 处"是因为 FIX-PLAN 写于 audit 时未含析构函数处（line 293）；全部 local shadowing 已消除，且每处均有 audit 注释。

---

## 结论

T2 全部 6 项 fix 均已在 commit `0bb99ce` 中落地，代码当前 HEAD 与 commit 一致。T2-F7 (DESIGN) 按计划跳过，不需要修复。
