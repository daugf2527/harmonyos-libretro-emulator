# 加载 / 切换 / 生命周期"不稳"审计 (2026-06-07)

> 角度:游戏加载 / 切换 / 生命周期的偶发卡死 / 偶发慢 / 状态异常。没人查过的新角度。
> 范围:**只读审计,禁改代码**。区分 App 可修源 vs 模拟器固有。
> 工具:cclsp(find_references)+ codegraph(explore/影响面)+ web-search(ANR 阈值核实)。
> 关键文件:`entry/src/main/cpp/core/engine/libretro_engine.cpp`、`app/napi/engine_lifecycle_napi.cpp`、`engine_state_napi.cpp`、`engine_disk_napi.cpp`、`engine_query_napi.cpp`、ArkTS 切换/会话控制器。

---

## TL;DR — 排序后的可修源(诚实结论)

**整体评价**:加载/切换/生命周期路径**比想象的健壮**。single-flight token、cancel、failure recovery、Stop 超时、SyncTask 悬挂引用守卫(T8-B-F1)、输入走 lock-free snapshot(不洪泛队列)——这些已是修过多轮的成熟代码。**未发现确定性死锁或竞态**。

真正的不稳风险集中在 **"同步 NAPI × 5s 阻塞 × UI 线程"** 这一类,且大部分目前**未被 UI 实际触达**(latent 而非 active):

| # | 风险 | 严重度 | App 可修? | 是否 active |
|---|---|---|---|---|
| **R1** | `kSyncTaskTimeoutMs=5000` 恰好 = HarmonyOS `APP_INPUT_BLOCK` 阈值;同步 NAPI 调 `ExecuteSyncTask` 在引擎线程卡顿时阻塞 UI 线程最长 5s → 卡住即 ANR | **高(单点)** | ✅ 是 | 部分(见下) |
| **R2** | 同步存档 `refactoredSaveState/LoadState` 阻塞 UI 线程(序列化大状态 >100ms~秒级) | 中 | ✅ 是(已有 Async 版) | **否**(UI 已用 Async) |
| **R3** | SRAM/Cheat/ResetCore/GetRegion/DiskControl(7) 同步 NAPI 无 Async 版,未来接 UI 即 R1 | 中(latent) | ✅ 是 | **否**(0 ets 调用) |
| **R4** | `refactoredResetEngine()` / `refactoredStopEngine()` 同步版可阻塞 UI 线程 5s(`Reset→Stop`) | 中 | ✅ 是(已有 Async) | 低(恢复路径) |
| **R5** | 加载 ROM/Core 是异步消息 + ArkTS 轮询 `WaitForState`,引擎线程串行处理 LoadCore→retro_init(dlopen 慢核)→ 偶发"慢"(非卡死) | 低 | 半(模拟器无 JIT 固有 + 超时已自适应) | 是 |
| **R6** | 消息队列**无界**(`std::queue` 无容量上限),WindowResized 已 coalesce,但理论上突发 push 可堆积 | 极低 | ✅ 是 | 否(实测无洪泛源) |

**最该动的**:R1(把 active 的同步 NAPI 改异步 / 或把 `kSyncTaskTimeoutMs` 与 UI 调用解耦)。R3 是"现在没事但一接 UI 就炸"的定时炸弹,建议补 Async 版或在 ArkTS 侧统一 taskpool 包装。

---

## Q1. ExecuteSyncTask (libretro_engine.cpp:1001) — 17 caller × 线程 × 热路径

### 机制(libretro_engine.cpp:1001-1025)
```cpp
bool LibretroEngine::ExecuteSyncTask(const std::function<void()> &task, uint32_t timeoutMs) {
  if (!task) return false;
  if (g_engineThreadInstance == this || !running_.load()) { task(); return true; } // ★短路:引擎线程内/未运行→同步直跑,不阻塞
  if (messageQueue_.IsClosed()) { ...; return false; }
  auto syncTask = std::make_shared<EngineSyncTask>(task);
  if (!messageQueue_.Push(MakeSyncTaskMessage(syncTask))) { ...; return false; }
  if (!syncTask->Wait(timeoutMs)) { LOGF(timeout); return false; } // ★调用线程阻塞等引擎线程处理 SyncTask 消息
  return true;
}
```
- `kSyncTaskTimeoutMs = 5000`(libretro_engine.cpp:88)。
- **阻塞条件**:仅当 (调用线程 ≠ 引擎线程) 且 `running_==true` 时,调用线程在 `EngineSyncTask::Wait(5000)` 上**最长阻塞 5 秒**,直到引擎线程 GameLoop 在 `while(messageQueue_.Pop())`(行 1168)中弹出并 `Run()` 该 SyncTask。
- 若引擎线程此刻正卡在**长帧 `retro_run`**(慢核/重场景)或**正在处理 LoadCore/LoadRom**(dlopen + retro_init),SyncTask 排在其后,调用线程一直等 → 卡顿;极端情形等满 5s。
- `EngineSyncTask`(行 47-83)的 Wait/Run 用同一 mutex + `abandoned_` 守卫,**悬挂引用 UB 已封死**(T8-B-F1),超时返回 false 后栈帧安全销毁。这块是对的。

### 17 个引用点(cclsp find_references 结果,全部在 libretro_engine.cpp + .h 声明)
全部是 `LibretroEngine` 成员方法内部调用 `ExecuteSyncTask`,**没有任何引擎线程外的直接调用方绕过 NAPI**(已用 grep `->Method(` 跨 cpp 验证:除引擎自身 lambda 外只有 NAPI wrapper)。逐个映射到 NAPI export + 调用线程 + 是否 active:

| # | 行 | 引擎方法 | NAPI export | NAPI 同步? | ArkTS 调用线程 | 有 Async 版? | active(有 ets 调用)? |
|---|---|---|---|---|---|---|---|
| 1 | 2601 | DiskControlSetEjectState | refactoredDiskControlSetEjectState | 同步 | UI | ✗ | **否** |
| 2 | 2615 | DiskControlGetEjectState | refactoredDiskControlGetEjectState | 同步 | UI | ✗ | **否** |
| 3 | 2627 | DiskControlGetImageIndex | refactoredDiskControlGetImageIndex | 同步 | UI | ✗ | **否** |
| 4 | 2639 | DiskControlSetImageIndex | refactoredDiskControlSetImageIndex | 同步 | UI | ✗ | **否** |
| 5 | 2651 | DiskControlGetNumImages | refactoredDiskControlGetNumImages | 同步 | UI | ✗ | **否** |
| 6 | 2664 | DiskControlReplaceImageIndex | refactoredDiskControlReplaceImageIndex | 同步 | UI | ✗ | **否** |
| 7 | 2678 | DiskControlAddImageIndex | refactoredDiskControlAddImageIndex | 同步 | UI | ✗ | **否** |
| 8 | 2797 | GetSaveStateSize | refactoredGetSaveStateSize | 同步 | UI | ✓(Async) | 否(@deprecated) |
| 9 | 2817 | SaveState | refactoredSaveState | 同步 | UI | ✓(Async) | **否**(UI 用 Async) |
| 10 | 2841 | LoadState | refactoredLoadState | 同步 | UI | ✓(Async) | **否**(UI 用 Async) |
| 11 | 2864 | GetSRAM | refactoredGetSRAM | 同步 | UI | ✗ | **否** |
| 12 | 2888 | SetSRAM | refactoredSetSRAM | 同步 | UI | ✗ | **否** |
| 13 | 2910 | ResetCore | refactoredResetCore | 同步 | UI | ✗ | **否** |
| 14 | 2930 | CheatReset | refactoredCheatReset | 同步 | UI | ✗ | **否** |
| 15 | 2945 | CheatSet | refactoredCheatSet | 同步 | UI | ✗ | **否** |
| 16 | 2960 | SetControllerPortDevice | refactoredSetControllerPortDevice(经 InputManager 回调) | 同步 | UI | ✗ | 间接 |
| 17 | 2983 | GetRegion | refactoredGetRegion | 同步 | UI | ✗ | **否** |

(第 16 项链路:NAPI `SetControllerPortDevice` → `InputManager::SetControllerPortDevice` → `controller_port_device_callback_`(libretro_engine.cpp:274 lambda)→ `LibretroEngine::SetControllerPortDevice` → ExecuteSyncTask。同样在 UI 线程同步触发。)

### Q1 结论
- **没有高频/每帧调 ExecuteSyncTask 的路径**。全是用户手动触发(存档/读档/金手指/换盘/设手柄)= 低频。**所以不会"持续掉帧"**,只会"用户点某个键 → 偶发卡一下 / 最坏 ANR 一次"。
- **核心风险 = 5s 阻塞落在 UI 线程,且阈值恰好撞上 `APP_INPUT_BLOCK`(见外网核实)**。引擎线程一旦在慢核长帧 / LoadCore 中,UI 线程的同步 SyncTask 调用就排队等。
- **缓解现状(重要)**:存档/读档(#8/9/10)是这 17 个里**唯一被 UI 真实使用**的,而 UI 已经走 `refactoredSaveStateAsync/LoadStateAsync`(`RuntimeSaveStateController.ets:25/58`),**绕开了同步阻塞**。其余 14 个(Disk/SRAM/Cheat/ResetCore/GetRegion)**当前 0 个 ArkTS 调用点**(grep `entry/src/main/ets` 确认)→ **active 风险接近 0**。
- **App 可修**:① 把同步版 `refactoredSaveState/LoadState/GetSaveStateSize` 标 deprecated 已做,但 sync export 仍在册,任何新代码误用即触雷;② R3 的 7 个无 Async 版方法,接 UI 前必须补 Async 或 ArkTS 侧 taskpool 包装。
- **判定**:**App 可修**(全部在 NAPI/引擎层,非模拟器固有)。

---

## Q2. SwitchGameAsync / Reset / Stop — 竞态 / 卡死 / 同步点

### 两套切换实现(注意!)
1. **`refactoredSwitchGameAsync`**(`engine_lifecycle_napi.cpp:896`):native 全程在 `napi_async_work` 工作线程跑 `ExecuteSwitchGame`(行 701)。**正确**:不阻塞 UI。
2. **`LibretroSwitchCoordinator.ets`**:ArkTS 侧自己编排 Stop→Start→LoadCore→WaitForState→LoadRom。用 `Promise` 串行队列(`tail`)防并发,且对阻塞操作**全用 Async 版**(`refactoredStopEngineAsync`、`refactoredWaitForStateAsync`)。**基本正确**。

`RuntimeSessionController.ets` 用 (1);`LibretroSwitchCoordinator.ets` 是另一条 ArkTS 编排路径。**两条都存在 = 维护风险**(用户应确认哪条是生产路径,避免双轨语义漂移),但各自内部无竞态。

### single-flight / token 仲裁(engine_lifecycle_napi.cpp)
- 全局 `switch_token`(原子递增)+ `active_switch_token` + `switch_mutex` + `switch_cond`(行 16-25)。
- `AcquireSwitchToken`(582):`while(active_switch_token!=0)` 时 `switch_cond.wait()`,但**每次唤醒先查 `IsLatestSwitchToken`**,stale 立即返回 false → **不会无限等**。`CancelSwitch`(1111)递增 token + notify_all 让所有等待者失效。逻辑自洽。
- `SwitchTokenGuard`(713)RAII 释放 token,异常路径也释放。
- **dedupe**(`ShouldDedupSwitchRequest` 33):800ms 窗口内同 core+rom 且引擎 busy → 视为成功返回(D012 修过的 type-lie:resolve `{success:true}` 而非 boolean)。合理。

### Stop 路径(libretro_engine.cpp:455-526)
- `stopInProgress_.exchange(true)` 防重入。
- Push Stop 消息 + `Close()` 队列 + **释放 controlMutex_ 再做 5s 等待**(T2-F4,行 482)→ **避免持锁阻塞**,这是对的。
- `stopCond_.wait_for(5000, gameLoopExited_)`。超时则强制 `renderThread_->Stop()` + 设 `stopTimedOut_` + 返回 false(**不 join**,避免卡死)。GameLoop 正常退出时(行 1410)`gameLoopExited_.store(true); stopCond_.notify_all()`。
- **潜在慢点**:若引擎线程卡在长帧 `retro_run`,Stop 消息要等当前帧 `ProcessFrame()` 跑完 + 下一轮 `while(Pop())` 才被处理。慢核单帧 >5s 理论上能让 Stop 超时(走强制 renderThread Stop 兜底,不卡死但状态降级)。
- **TransitionTo**(2686):CAS 循环防 TOCTOU + 持 stateMutex_ 再 notify_all(T2-F2 防丢通知)。`WaitForState`(2748)`timeoutMs==0` 时无锁 poll,否则 `stateCond_.wait_for`。正确范式。

### Reset 路径(libretro_engine.cpp:528+)
- 持 `controlMutex_`(recursive),`running_` 时先 `Stop()`(可阻塞 5s),Stop 失败则**放弃破坏性清理**(行 536)避免生命周期重叠。防御到位。
- **风险**:`refactoredResetEngine`(`engine_lifecycle_napi.cpp:1299`)是同步 NAPI → 若在 UI 线程调且引擎 running,`Reset→Stop` 阻塞最长 5s。`LibretroSwitchCoordinator.ets:102` 确实直接调 `refactoredResetEngine()`(同步),但仅在 stop 超时恢复路径,低频。

### failure recovery(engine_lifecycle_napi.cpp:639 RecoverAfterSwitchFailure / 677)
- 全部检查 `IsLatestSwitchToken(token)`,stale 跳过恢复(防旧切换的恢复逻辑踩新切换)。preservedError 保留原始错误。`Stop()` 失败时跳过 Reset 防重叠。设计严谨。

### Q2 结论
- **未发现死锁或竞态 bug**。token/cancel/recovery 都修过多轮,守卫完整。
- **卡死可能性**:仅"引擎线程长帧 → Stop/SyncTask 等待超时",但都有 5s 超时兜底**不会真死**(降级为返回 false + 强制 renderThread Stop)。
- **慢源**:Stop/Switch 需等当前帧跑完;慢核单帧极端时拖到秒级。**这是模拟器固有(无 JIT 慢核)+ App 半可修**(可在 Stop 时给引擎线程一个"打断当前帧"的协作标志,但 retro_run 不可中断是 libretro 契约 → 固有)。
- **App 可修点**:统一生产切换路径(消除双轨)、`refactoredResetEngine` 改异步或挪出 UI 线程。

---

## Q3. RUNNING 态消息队列 — 积压 / 洪泛 / 拖帧

### 队列实现(message_queue.h)
- `ThreadSafeQueue<EngineMessage>`:**`std::queue` 无容量上限(无界)**。`Push` 永不阻塞、永不因满而丢(仅 `closed_` 时丢)。
- `PushCoalesce`(行 43):只合并**队尾**同类消息(WindowResized 用),队中被夹住的旧消息不前向扫描合并(注释已说明限制)。

### RUNNING 态主循环(libretro_engine.cpp:1164-1290)
```cpp
if (currentState == RUNNING) {
  while (messageQueue_.Pop(msg)) {        // ★每帧 drain 所有积压消息
    HandleMessage(msg);
    if (state_.load() != RUNNING) break;  // 状态变更立即跳出
  }
  if (state_ == RUNNING) { ProcessFrame(); ... 节拍 sleep 到 targetFps ... }
}
```
- **每帧开头 drain 全部待处理消息**。如果某帧前堆了 N 条消息,这一帧要先处理 N 条再 retro_run → 该帧变长 → 偶发掉一帧。

### 输入是否洪泛队列?——**否(关键澄清)**
- `refactoredSendInput`/`refactoredSendAnalog`/`refactoredSendSensor`/Pointer → `InputManager::SendInput` 等(input_manager.cpp:97+)→ 写 **`InputSnapshot`**(input_snapshot.h:原子 bitmask + 原子数组,lock-free,`static_assert ATOMIC_*_LOCK_FREE==2`)。
- **完全不进消息队列**。libretro `input_poll/input_state` 回调在引擎线程直接读 snapshot。注释明确:"避免消息队列对高频操作(快速连按)的延迟影响"。
- **键盘事件**(`DispatchKeyboardEvent` libretro_engine.cpp:883)走 SyncTask,但**输入线程 fire-and-forget 不 Wait**(行 918,只 Push 不等)→ 不阻塞输入线程,但**高频键盘会往队列灌 SyncTask**(每次按键 1 条)。键盘通常远低频于游戏手柄连发,实际影响小;但这是队列里**唯一可能随输入增长的消息源**。

### 实际进 RUNNING 态队列的消息有哪些?
- WindowResized(已 coalesce)、WindowCreated(surface 变化,低频)、Pause/Resume/Stop/Cancel(用户操作,低频)、SyncTask(存档/盘/键盘等)。
- **正常游戏运行中,队列几乎空**(输入不进队列)。只有窗口尺寸抖动(分屏/旋转)或用户操作时才有消息。

### Q3 结论
- **无消息洪泛**:高频输入走 lock-free snapshot 不入队;入队消息都是低频用户/窗口事件。**这是设计良好的点**。
- **拖帧风险极低**:每帧 drain 的消息正常为 0;只有窗口抖动 / 突发 SyncTask 时单帧变长,偶发掉 1 帧,不累积。
- **唯一可修点(低优先)**:① 队列无界 → 极端(如窗口疯狂 resize + 队列消费跟不上)理论堆积,可加软上限 + 丢弃策略;② 键盘 SyncTask 每键 1 条,高频外接键盘下可考虑也并入 snapshot 风格。两者都**非当前实测痛点**。
- **判定**:**App 可修但低优先**;当前无 active 不稳。

---

## 外网核实(题目硬要求)

`mcp__web-search__web_search`("HarmonyOS ArkTS NAPI synchronous native call block UI main thread ANR APP_INPUT_BLOCK"):

- **同步 NAPI 在 ArkTS UI/主线程执行 = 阻塞事件循环**,与长 JS 同等,阻断 UI 刷新 + 输入处理。来源:华为官方 appfreeze-guidelines + OpenHarmony docs。
- **`APP_INPUT_BLOCK` 阈值 ≈ 5 秒(5000ms)**:输入事件超时无响应即报此 AppFreeze。
- **`THREAD_BLOCK_6S`**:看门狗线程向主线程投 ping 任务,前台 ~6s 未处理触发主线程超时事件。
- 缓解:任何 >几 ms 的 native 工作必须 `napi_create_async_work` / TSFN / TaskPool / Worker 异步化。
- 来源:developer.huawei.com/consumer/.../appfreeze-guidelines(EN + V5 CN)、gitee OpenHarmony docs、华为开发者博客。

**对本仓的直接含义**:`kSyncTaskTimeoutMs=5000` 与 `APP_INPUT_BLOCK` 阈值**完全重合**——意味着一个在 UI 线程的同步 `ExecuteSyncTask` 一旦真的等满超时,几乎必然同时触发系统 ANR(而非优雅返回 false 后用户无感)。**建议**:UI 线程路径的 SyncTask 超时应**远小于 5s**(如 1-2s)给系统留余量,或干脆异步化。Stop 的 5s 同理。

---

## 结论:App 可修 vs 模拟器固有(最终排序)

### App 可修(按优先级)
1. **[高] R1 — 同步 NAPI × 5s × UI 线程**:`kSyncTaskTimeoutMs=5000` 撞 `APP_INPUT_BLOCK`。建议:(a) UI 线程路径超时降到 1-2s;(b) 把仍在册的同步 export(尤其无 Async 版的 SRAM/Cheat/ResetCore/GetRegion/Disk 7 个)接 UI 前补 Async/taskpool。`libretro_engine.cpp:88`、`engine_state_napi.cpp`、`engine_disk_napi.cpp`、`engine_query_napi.cpp:213`。
2. **[中] R4 — `refactoredResetEngine`/`refactoredStopEngine` 同步版**:`Reset→Stop` 阻塞 5s。`LibretroSwitchCoordinator.ets:102` 在恢复路径同步调 Reset。建议异步化或挪出 UI 线程。`engine_lifecycle_napi.cpp:1159/1299`。
3. **[中] 双切换路径并存**:`refactoredSwitchGameAsync`(native 编排)vs `LibretroSwitchCoordinator.ets`(ArkTS 编排)。建议确认唯一生产路径,消除语义漂移(各自内部都对,但双轨易腐化)。
4. **[低] R6 — 消息队列无界 + 键盘 SyncTask 每键 1 条**:`message_queue.h` 加软上限;键盘考虑并入 snapshot。当前非痛点。

### 模拟器/平台固有(App 难根治)
- **慢核长帧拖慢 Stop/Switch**:`retro_run` 不可中断是 libretro 契约;HarmonyOS 禁 JIT/dynarec → 重核单帧可能很长。App 只能用超时兜底(已做)。
- **LoadCore dlopen + retro_init 慢**:大核加载本身耗时,SwitchGameAsync 已按文件大小自适应超时(`CalculateCoreLoadTimeout` 5/10/15s),这是合理工程缓解,非 bug。

### 诚实声明
- 未发现确定性死锁 / use-after-free / 竞态 bug;切换/生命周期的并发控制是修过多轮的成熟代码。
- R1/R3 的"5s ANR"是**latent 风险**:理论链路成立 + 阈值精确重合,但 active 触达面很小(存档已用 Async,其余 14 个 export 当前 0 ArkTS 调用)。**不是"现在频繁卡死"的解释**,而是"误用一行就炸 / 一接新 UI 就炸"的设计隐患。
- 若用户实测有**确定性偶发卡死**,优先怀疑:① 引擎线程长帧(看 `[AUD][CHAIN] engine_window max_frame_us/max_retro_ms` 日志);② 是否有代码误用了同步存档/同步 Stop。本审计未覆盖渲染线程(RenderThread)/音频线程内部,那是另一角度。
