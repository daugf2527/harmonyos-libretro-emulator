# Agent C — 音频/视频/线程对抗式审计（最近 5 天）

**审计日期**: 2026-06-08
**审计性质**: 静态分析，未编译 / 未真机
**重点**: 挑战"平台非代码"叙事 + 并发正确性

---

## Q1 — 音频 dual-profile 正确性 + 叙事自洽

> 核：(a) 真机/模拟器 profile 选择逻辑；(b) 断 underrun 重缓冲死循环；(c) 缓冲延迟设置 vs 平台缺实时调度叙事自洽性

### 关键事实核对（数学全部重算，capacity 含 power-of-2 修正）

- RingBuffer capacity = `NextPowerOf2(48000*2)` = **131072 samples** = 65536 frames = 1365ms 总容量（`ring_buffer.cpp:58-60`）。
- `GetUsage() = AvailableRead()/capacity_`（samples/samples，含 131072 修正）→ DRC band 注释里的 ms 值**算对了**：
  - device band 6%-11% → 81.9ms-150.0ms ✓（注释 ~82-150ms）
  - emulator band 12%-28% → 163.8ms-382.0ms ✓
- profile 选择时序：`SetRtSchedulingAvailable(qosRet==0)` 在 `libretro_engine.cpp:1142` GameLoop 入口（线程启动即调），早于游戏加载触发的 `Initialize`。**时序正确**（与 2026-06-07 audit 一致，独立复核确认）。

### (a) profile 选择逻辑 — 正确，但判定基准单一【P2】

- 判定"是否模拟器"= `OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE) == 0`（`libretro_engine.cpp:1140-1145`）。**这不是直接探测"模拟器"，而是探测"QoS 调度可用性"**——语义上更准（真机若某机型 QoS 也失败，会自动走深缓冲档，是合理 fallback）。
- **误判后果**：若真机 QoS 偶发失败（驱动/权限）→ 误判为模拟器 → 走 250ms 深缓冲 + 12-28% DRC 带 → 真机被强加 ~164ms+ 起播延迟，手感损失但**不崩**。反向（模拟器 QoS 意外成功）→ 走 100ms 浅缓冲 → 退回 underrun。**误判是性能/手感退化，非正确性 bug**。可接受。
- **单点默认值风险**：`rt_scheduling_available_{false}` 默认（`audio_bridge.h:142`）。若未来出现"首次 Initialize 早于 GameLoop QoS 注入"的代码路径，会锁死模拟器深缓冲档。当前路径时序 OK，记为防御性 note。

### (b) 断 underrun 重缓冲死循环 — 修复逻辑成立，无新死循环【裁决：真修复】

- **原死循环**（D020 之前）：`ProcessAudio`（引擎线程）检测 `underruns > last_rebuffer_underruns && available < min` → 调 `audio_player_->Pause()` + 后续 `Start()`（`audio_bridge.cpp:478-495` + `579-602`）。这两个走 `OH_AudioRenderer_Pause/Start` HAL 调用；模拟器无 RT 时耗 95-231ms，**阻塞 `retro_run`（同在引擎线程）→ 帧时间暴涨 → 生产断流 → 更多 underrun → 再次触发重缓冲**。死循环成立。
- **修复**：rebuffer 入口加 `rt_scheduling_available_.load()` 门控（`audio_bridge.cpp:478`）。模拟器（flag=false）**完全跳过** Pause/Start，改 ride-through（消费回调 `audio_player.cpp:589-599` memset 静音补齐 + 返回 VALID）。**能真正断死循环**：模拟器路径不再在引擎线程做 HAL 状态切换。✓
- **有无新死循环/无限重缓冲**：
  - rebuffer 触发受 `last_rebuffer_underruns_` 单调推进保护（`:483` 每次触发后 `store(underruns)`）→ 同一 underruns 值不会重复触发，必须 underruns **继续增长**才再触发。非无限循环。
  - 真机路径仍会 Pause/Start，但真机这俩廉价（µs 级），不会阻塞 retro_run 到断流。**真机路径理论上仍可能重缓冲振荡**（buffering→fill→underrun→buffering），但每次 HAL 廉价，不构成卡死。记为 P3 理论风险。
  - **未发现新死循环**。✓

### (c) 缓冲延迟设置 vs "平台非代码"叙事 —— 【裁决：部分自洽，且 D019 设置实际为 DEAD CODE】

**这是本审计最强的叙事张力点，结论：D019 的"可调缓冲延迟根治 underrun"叙事不成立，该设置在 D020 之后是死设置。**

**证据链（`audio_bridge.cpp:77-103` SetMinimumLatencyMs）**：
1. D019（`70945e4`）加 production 路径 `setMinimumAudioLatency(48)`，预设档 [16/48/96]ms，commit message 称"根治模拟器 underrun""生产游戏不再 latency=0"。
2. D020（`8b818c5`，10 小时后）把 `default_min_buffer_frames_` 基线从 200ms 改成 **device 100ms / emulator 250ms**（`:654-658`）。
3. `SetMinimumLatencyMs(latency_ms)` 逻辑：`target = rate*latency/1000`；**若 `target < default_frames` 则 `target = default_frames`（:92-94，向上钳到 profile 地板）**；且 latency≠0 时仅当 `target > current` 才生效（:100）。
4. **数学**（rate=48000）：
   | 预设 | target frames | device floor (100ms=4800) | emulator floor (250ms=12000) |
   |---|---|---|---|
   | 16ms | 768 | 钳到 4800，不 >current → **无效** | 钳到 12000 → **无效** |
   | 48ms（默认） | 2304 | 钳到 4800 → **无效** | 钳到 12000 → **无效** |
   | 96ms | 4608 | 钳到 4800（4608<4800）→ **无效** | 钳到 12000 → **无效** |
5. **结论：D019 的全部三个档位（16/48/96ms）都 < D020 两个 profile 地板，永远被钳掉，对 min_buffer_frames_ 零影响。** 尤其在**模拟器**（地板 250ms）——恰恰是 underrun 发生的平台——三档全死。SettingsPage 的 "Audio Latency" 行用户怎么调都不改变实际缓冲水位（只改 `minimum_latency_ms_` 这个被记录但不起作用的字段 + 日志）。

**叙事裁决**：
- "underrun 是 API22 模拟器缺实时调度的平台问题"——**自洽且基本成立**：QoS/workgroup 被系统拒（6800301/-1）是日志实证的客观事实，3-4 月 API17 模拟器正常→平台跳版引入，这部分叙事可信。
- 但 D019 "加可调缓冲延迟设置去根治"——**与平台叙事自相矛盾，且实现为 dead code**：
  - 若真是纯平台 RT 问题，"加缓冲"本就是**治标**（深缓冲只是吸收抖动，不恢复实时性）——D020 commit 自己也承认残留 underrun 主因已移到视频 swap。
  - 更糟：D019 这个"治标"手段**根本没接通**（被 D020 地板钳死），是 placebo UI。真正起作用的是 D020 的 profile 地板（100/250ms）+ DRC 带，**与 D019 的用户可调档无关**。
- **真正"根治"缓冲深度的是 D020 的 hardcoded profile 地板**，不是 D019 的可调设置。D019 commit 标题"根治模拟器 underrun"夸大且已被自己后续 commit 架空。

**修法/验证建议**：
- 要么删掉 SettingsPage 的 Audio Latency 行（避免误导：用户调了没反应）；
- 要么让 `SetMinimumLatencyMs` 语义改为"在 profile 地板**之上**叠加"且允许向下（如真机想要 16ms 低延迟就该能压到 16ms，但当前 device 地板 100ms 也压不下去）——当前"只能往上、且三档都够不到地板"使其完全失效。
- 真机验证：抓 `SetMinimumLatencyMs: min_frames=` 日志，确认调档后 min_frames 是否变化（预测：不变，证实 dead）。

---

## Q2 — 并发正确性

> 核：(a) 77c224b 线程 QoS 副作用；(b) busy_wait_allowed_ memory_order；(c) D024 state_mutex_ 优先级反转 + defer 风险

### (a) 77c224b 线程 QoS 副作用 — 无线程安全问题【裁决：安全】

- `OH_QoS_SetThreadQoS(QOS_USER_INTERACTIVE)` 在各自线程入口调用：GameLoop 入口（`libretro_engine.cpp:1140`）、RenderThread `ThreadMain` 入口（`render_thread.cpp:181`）。**作用对象是调用线程自身**（设当前线程 QoS），无共享状态写、无跨线程参数 → 天然线程安全。
- 唯一副作用是 GameLoop 入口顺带 `AudioBridge::SetRtSchedulingAvailable(qosRet==0)`（原子 store），无害。
- ArkTS 侧 `setWindowKeepScreenOn` 走 UI 线程 + 生命周期配对（aboutToAppear/Disappear、pause/resume），与 C++ 线程无交叉。✓

### (b) busy_wait_allowed_ memory_order —— 【裁决：relaxed 充分，prior audit 把它描述成跨线程是不准确的】

**独立核实线程归属（决定性）**：
- 写：`SetBusyWaitAllowed` 经 `VideoPipeline::SetFramePacerBusyWaitAllowed`，**唯一调用点 `render_thread.cpp:188`，在 `ThreadMain()` 内、while 循环之前** → 跑在 **RenderThread**。
- 读：`busy_wait_allowed_.load()` 在 `FramePacer::EndFrame`（`frame_pacer.h:58`）；`EndFrame` 只被 `VideoPipeline::Render`（`video_pipeline.cpp:1385`）调，`Render` 只被 `RenderThread::HandleTick`（`render_thread.cpp:560`）调 → 也跑在 **RenderThread**。
- **结论：写和读是同一线程（RenderThread），写在 while 循环前一次性发生、读在每帧。单线程 program order 保证 write happens-before 所有 read，`memory_order_relaxed` 完全充分，无跨线程可见性问题。** 任务设问"render_thread 写、EndFrame 读跨线程"前提不成立——二者同线程。即便它是 `atomic<bool>` 也只是防撕裂的保险，实际无并发访问。✓

### (c) D024 state_mutex_ —— 【裁决：prior audit F1 成立且已正确描述；独立复核确认仅 workgroup_disabled_==false 才持锁，但补充一个 prior audit 未点的真机加重项】

**独立核实"仅模拟器短路"**：
- 回调内三处 `state_mutex_`（`audio_player.cpp:464` AddCurrentThread / `:506` Workgroup_Start / `:637` Workgroup_Stop）**均包在 `if (!workgroup_disabled_.load())` 内**。模拟器 workgroup Start 首次失败（6800301）→ CAS `workgroup_disabled_=true`（`:531`）→ 此后回调全跳过这三处锁。**"模拟器仅 startup 持锁一次、之后零持锁"描述准确**。✓
- 真机 workgroup 正常 → 回调**每帧**取 `state_mutex_` 围绕 Start/Stop。

**优先级反转风险 — prior audit 描述基本正确，但我补充一个它低估的点【P2，真机相关，静态分析未真机】**：
- prior audit 说"锁很短，severity 低"。**但 `:506-538` 与 `:637-650` 是在持 `state_mutex_` 的情况下调 `OH_AudioWorkgroup_Start/Stop` 这两个 HAL 调用**（不是纯内存操作）。若该 HAL 在某些机型/负载下耗时不可忽略，则**音频实时线程持锁跨 HAL 调用**，而引擎线程 rebuffer 路径要拿同一 `state_mutex_`（经 `audio_player_->IsPlaying()`@`audio_bridge.cpp:481` 与 `Pause()`@`audio_player.cpp:309`）→ 引擎线程被音频线程持锁阻塞 = 优先级反转。两线程都是 USER_INTERACTIVE，但音频线程仍可能因 workgroup HAL 抖动拖住引擎。severity 比"纯标志位短锁"高一档。
- **缓解现状**：`Pause()/Start()` 已把 HAL 调用移出锁外（`audio_player.cpp:322`/`285` 在锁释放后调 `OH_AudioRenderer_Pause/Start`），所以引擎侧持锁极短；风险集中在**音频回调侧持锁调 workgroup HAL**。
- **defer 决定是否埋真机隐患**：是，埋了一个**真机专属**的潜在 PI（模拟器因 workgroup_disabled 反而免疫）。defer 在"模拟器当前症状"语境下合理（模拟器不走这条），但 commit/memory 说"真机预期 RT 恢复即顺"**掩盖了"真机才是这个 PI 唯一受害者"**——叙事方向反了：模拟器免疫、真机暴露。建议 D024 修复优先级应**按真机**评估而非按"模拟器不是症状所以低优先"。

**无死锁**（独立核实锁序）：回调线程（state_mutex_）与中断回调（state_mutex_）**从不反向去取 `AudioBridge::mutex_`**；只有引擎 `ProcessAudio` 单向 `mutex_`→`state_mutex_`（`audio_bridge.cpp:253`持 mutex_ 时于 `:276`调 IsPlaying 取 state_mutex_）。无 AB-BA 环 → 无经典死锁。✓

### Q2 其他发现：FramePacer 非原子成员的跨线程数据竞争【P2，预存非本窗口引入，但帧率撤销链正好踩它】

- `FramePacer::SetTargetFps`（`frame_pacer.h:82-88`）写**非原子** `deadline_initialized_=false` + `frame_started_=false`（除原子 `target_frame_time_us_` 外）。
- `SetTargetFps` 经 `VideoPipeline::SetTargetFps` 被 `libretro_engine.cpp` 调：`:600`(Reset)、`:1729`(HandleMessage AV 变更)、`:2147`(ProcessFrame) → **跑在 GameLoop/Engine 线程**。
- 而 `BeginFrame`/`EndFrame` 读写同一批非原子成员（`deadline_initialized_` `frame_started_` `next_deadline_` `frame_start_`）→ **跑在 RenderThread**。
- **→ Engine 线程写 / Render 线程读写 `deadline_initialized_`、`frame_started_` 两个非原子 bool，无锁、无原子 = 数据竞争（formally UB）**。实际危害：撕裂/陈旧读导致某帧 deadline 重置时序错乱 → 偶发一帧节拍抖动，不崩。
- **与帧率撤销链的关系**：撤销链（Q3）的核心机制就是 `SetTargetFps`；`target_frame_time_us_` 是原子的（有人意识到跨线程），但同函数顺带写的两个 bool 漏了。撤销 commit `60e3538` 改了 `EffectivePeriodUs` 紧邻代码却没碰这个 race（race 自 `0493afc init` 起就在）。
- **修法**：`deadline_initialized_`/`frame_started_` 改 `std::atomic<bool>`；或更稳妥——`SetTargetFps` 不直接动 pacer 内部状态，改为 set 一个 `atomic pending_fps_`，由 RenderThread 在 BeginFrame 开头消费并自行 reset deadline（把 FramePacer 状态机收敛到 RenderThread 单线程所有）。后者根治。

### Q2 其他发现：targetFps_ 跨线程读（plain double）【P3，预存】

- `targetFps_` 是 `double`（`libretro_engine.h:381`），Engine 线程写（HandleMessage/ProcessFrame）；`GetFps()`（`:201`）被 `engine_query_napi.cpp:228` 读 → **NAPI 线程**。8 字节对齐 double 在 aarch64 上读写实际原子，但 formally data race。低危，记录备案。

## Q3 — 帧率撤销链行为一致性

> 核：14b4759→60e3538 撤销后节拍统一 60fps；busy_wait gate 与帧率解耦；残留 30fps 假设

### 撤销干净 + 解耦正确【裁决：一致，无残留】

- **撤销外科级精准**（`git show 60e3538`）：仅从 `EffectivePeriodUs()` 删除 `busy_wait_allowed_`-gated 的 30fps cap（`kEmulatorRenderMinFrameUs=33333`），现 `EffectivePeriodUs(){ return target_frame_time_us_.load(); }`。与主 AI 已验证一致。
- **busy_wait gate 与帧率完全解耦**：`busy_wait_allowed_` 现在**只**在 `EndFrame`（`frame_pacer.h:58`）门控"纯 sleep vs 末尾 hybrid 自旋"，**不再参与 period 计算**。撤销只动帧率、不动忙等策略 ✓——模拟器仍 `busy_wait_allowed_=false`（纯 sleep 不烧核），但 period 恢复 60fps。这正是 commit 声称的解耦，核实属实。
- **两条 pacing 路径都统一到 60（或 core fps），无 30fps 残留**：
  - RenderThread FramePacer：`target_frame_time_us_` ← `SetTargetFps(targetFps_)`，`targetFps_` 源自 `avInfo.timing.fps`（`libretro_engine.cpp:1611/1728/2146`），默认 60。
  - GameLoop 自身 pacing（独立于 FramePacer，`libretro_engine.cpp:1190-1192`）：`safeTargetFps = targetFps_>0 ? targetFps_ : 60`，`targetFrameUs = 1e6/safeTargetFps`。**同一 `targetFps_` 源**，无 emulator 分支降频。
- **全仓 grep 残留 30fps 假设**：`grep 33333|30fps|kEmulator|MinFrame|降频|frame_skip` 跨 `core/`+`platform/` → 仅命中 frame_pacer.h 的撤销说明注释 + 无关常量（`cooldownMs`、GameLoop `frameInterval` 用 targetFrameUs）。**无遗留 30fps 硬编码 / emulator-gated 降频。** ✓

### Q3 附带：撤销代价被 commit 诚实标注

- `60e3538` 明确写"代价:模拟器音频 underrun 会比降频时更频繁(真机无影响)"——撤销恢复跟手度但放弃了 30fps 对模拟器 underrun 的缓解。这与 D020 的深缓冲/ride-through 是互补关系（30fps 没了，靠深缓冲扛）。叙事自洽，未隐藏代价。✓

---

## 裁决汇总

### Findings 一览（severity + 真 bug vs 理论风险）

| # | 严重度 | 类型 | 一句话 | 位置 |
|---|---|---|---|---|
| F1 | **P1** | 死设置 + 误导 UI | D019 音频延迟设置（16/48/96ms，UI 最大 200ms）全部 < D020 profile 地板（device 100ms / emulator 250ms），被 `SetMinimumLatencyMs` 向上钳死 → **对缓冲深度零影响**；模拟器上**任何 UI 可产出的值都不生效**，但 SettingsPage 仍向用户承诺"调大抗 underrun" | `audio_bridge.cpp:77-103` + `RuntimeAudioSettingsRepository.ets:17,19` + `SettingsPage.ets:487-491,1163` |
| F2 | **P2** | 优先级反转（真机专属） | 音频实时回调持 `state_mutex_` 跨 `OH_AudioWorkgroup_Start/Stop` HAL 调用；真机 workgroup 正常 → 每帧持锁，与引擎 rebuffer 路径竞争同锁。模拟器因 `workgroup_disabled_` 反而免疫 → **defer 决定埋的是真机隐患，叙事"真机预期即顺"方向反了** | `audio_player.cpp:506-538,637-650` |
| F3 | **P2** | 数据竞争（预存，撤销链踩中） | `FramePacer::SetTargetFps`（Engine 线程）写非原子 `deadline_initialized_`/`frame_started_`，而 BeginFrame/EndFrame（RenderThread）读写同成员 → 跨线程非原子 bool race。`target_frame_time_us_` 已原子化说明有人意识到跨线程，但漏了这两个 bool | `frame_pacer.h:82-88` ↔ `12-29,43-80` |
| F4 | P3 | 数据竞争（预存） | `targetFps_`（plain double）Engine 线程写 / NAPI 线程 `GetFps()` 读，formally UB（aarch64 实际原子） | `libretro_engine.h:201,381` |
| F5 | P3 | 理论振荡 | 真机 rebuffer 路径仍可 Pause/Start 振荡（HAL 廉价不卡死），非死循环 | `audio_bridge.cpp:478-495` |

### 对"平台非代码"叙事的明确裁决

**裁决：部分自洽 —— 平台诊断成立，但被用来给一个"治标且实际未接通"的代码改动背书。**

1. **"underrun 根因是 API22 模拟器缺实时调度"——自洽、可信**：`OH_AudioWorkgroup_Start` 返 6800301 / `OH_QoS_SetThreadQoS` 返 -1 是日志实证客观事实；API17/5.0.5 模拟器正常 → 平台跳版引入。这部分叙事**成立**，不是甩锅。

2. **但"加可调缓冲延迟设置去根治 underrun"（D019）——叙事与平台诊断自相矛盾，且实现为 dead code（F1）**：
   - 逻辑矛盾：若纯平台 RT 问题，深缓冲只能**吸收抖动（治标）**，无法恢复实时调度。D019 commit 标题"根治"夸大；D020 commit 自己也承认"残留 underrun 主因已移出音频（视频 swap）"——即缓冲根本没"根治"。
   - 实现落空：D019 的设置被 D020 地板钳死，**真正改变缓冲深度的是 D020 的 hardcoded profile（100/250ms）+ DRC 带，与 D019 的用户可调档完全无关**。用户在 Settings 调延迟 = placebo。

3. **真正起作用的代码改动是有效的**，叙事问题不影响它们的正确性：
   - D020 dual-profile + 模拟器 ride-through（断重缓冲死循环）= **真修复**，逻辑成立无新死循环。
   - `05dc30b` FramePacer 模拟器禁忙等 = 合理（外网坐实 VM 忙等反模式），commit 诚实标注"次级加重因素非唯一主因"。
   - `60e3538` 撤销 30fps = 干净解耦，诚实标注代价。

4. **叙事掩盖的真问题**：把 underrun 归给"平台"后，D024 真机 PI（F2）被降级 defer，理由是"模拟器不是症状"。但 F2 恰恰是**真机专属**风险（模拟器免疫）——"平台非代码"叙事在这里**反而掩盖了一个真机代码隐患**。

### 各问题无 finding 的明确说明
- Q1(a) profile 选择逻辑、Q1(b) 断死循环：**无 bug**（profile 误判仅性能退化；死循环确实被门控断开）。
- Q2(a) QoS 副作用、Q2(b) busy_wait memory_order：**无 bug**（QoS 作用于本线程；busy_wait 同线程读写，relaxed 充分——纠正 prior audit 的"跨线程"措辞）。
- Q2 无死锁：锁序单向 `mutex_`→`state_mutex_`，无 AB-BA 环。
- Q3：撤销链**完全一致**，无残留 30fps，busy_wait 与帧率正确解耦。**无 finding**。

### 静态分析声明
以上全部为**静态分析，未编译 / 未真机 / 未模拟器**。F1 的 dead-code 判定基于数学（采样率 48000 × 延迟 ms / 1000 vs profile 地板 frames）+ 代码路径，建议真机抓 `SetMinimumLatencyMs: min_frames=` 日志验证调档后 min_frames 是否恒定不变（预测：不变）。F2/F3/F4 为并发正确性推理，需 TSan / 真机压测坐实。
