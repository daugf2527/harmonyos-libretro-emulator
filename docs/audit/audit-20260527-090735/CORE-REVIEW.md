# Core-Review — audit-20260527-090735

**方法**: 对每个 VERIFIED finding，Read ±20 行上下文 + cross-reference 调用方/线程模型，给出 verdict。

**Trust rule applied**: 没有依赖 agent 自我宣称的并发场景；逐项查实际 caller / 线程 ownership。

---

## Agent T3 (audio_bridge) — 8 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | **MITIGATED** | `AudioBridge::Reset` 和 `ProcessAudio` 均在 Engine thread 调（libretro_engine.cpp:1461/1609/1984 GameLoop 内 vs ProcessAudio 是 retro_audio_sample_batch 同步回调）。同线程无并发，`out_buf_data` 在 unlock 后到 WriteWait 之间没有第二个 Reset 入口。Agent 假设的"两线程"在当前模型下不成立。仍可作为防御性 P2 留 backlog。 |
| F2 | P1 | **REAL_LOWER P2** | 单线程下非原子 read/write 在 ARM64 上是 word-aligned naturally atomic，agent 自承"data race does not manifest"。但 **Reset 未清零 `drc_last_update_`** 是真 functional bug：重置后首次 DRC 更新被延迟 50ms。降级到 P2，只修"Reset 清零"部分，不改 atomic。 |
| F3 | P2 | **MITIGATED** | Same as F1: `recover_streak_` 只在 engine thread 读写（ProcessAudio post-unlock + Reset/Pause/Stop/Start 持锁内）。同线程 sequential 无 UB。 |
| F4 | P2 | **MITIGATED** | `callback_last_time_` 只在 OHAudio 回调线程访问。API12 wins (见 F5)，单一 callback 线程，无并发。 |
| F5 | P1 | **REAL P1** | 双 callback unconditionally 注册确实 fragile：HarmonyOS API 12 当前 wins，但代码意图错误（应按版本互斥注册）。API 行为变更（OS 升级）可能导致 silent double-drain 半幅音频。修复成本低（一个 #if API_VERSION 守卫）。 |
| F6 | P2 | **MITIGATED** | SPSC 单 producer 契约下 relaxed load 慢路径 benign。可加注释强调 SPSC，但不必改 memory ordering。 |
| F7 | P1 | **MITIGATED** | Write fast path 和 Clear 都在 engine thread sequential（ProcessAudio 必 return 才能进入下一个 message 含 Stop/Pause/Reset；AudioPlayer::Stop 也是 engine thread 调）。SPSC + 同线程双重保证，无 race。 |
| F8 | P2 | **REAL P2** | 当前 caller 安全（stereo 2-elem 数组），但 `Resample(in, in_frames)` 的 in 数组大小契约未在签名表达。未来若 caller 传 mono / 单元素数组，`in[1]` 越界。改用 `fetch_channel` 助手或加 assert。 |

**T3 小结**: lock discipline 已较扎实。8 项 finding 中只 2 项是真要修的（F5 callback 双注册、F8 resampler bounds）。F2 拆分出 1 个小 functional fix（Reset 清零 drc_last_update_）。其余 5 项是 single-thread 模型下 MITIGATED — 当前不修，但应在 audio_bridge.h 顶部记录"thread ownership: producer = Engine thread; consumer = OHAudio callback thread" 防未来误用。

---

## Agent T4 (video_pipeline) — 8 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P0 | **REAL_LOWER P1** | "FlushBuffer 失败后调 AbortBuffer 违反 ownership 契约"是 HarmonyOS NativeWindow API 契约层面的 claim。未在本会话查证官方文档；保守降到 P1（agent 没引用文档）。**修复方向是对的**：删 AbortBuffer 调用，仅 Unreference。但应先核对 `OH_NativeWindow_NativeWindowAbortBuffer` 官方语义后再改（待 user 确认是否本次修）。 |
| F2 | P1 | **FALSE_POSITIVE (revised 2026-05-27 mid-fix)** | 修复阶段细查 ownership 流转：line 99 `SetWindow` 显式 `Reference(message.window)` 把 1 ref 跟 message 转移过来；HandleSetWindow 是 ownership-transfer pattern。Line 342 Unref 释放 windowSession_ 原本持的旧 ref，line 347 assign 把 message 携带的 ref 接给 windowSession_，净持 1 ref（正确 swap）。Agent 误把 "ref count 是对象级别的，line 342 减的是 windowSession_ 那份" 推论成 "释放了 SetWindow 加的 ref"——但 ref pool 是对象总池，逻辑 ownership 由代码语义决定。所以 case 2 (same-window-diff-gen) 跟 case 3 (diff-window) 是同一个 transfer 流程，不是 leak。**不修。** |
| F3 | P1 | **MITIGATED** | T4-F5 audit 已加注释 "Engine thread only — SetPixelFormat and Render() must both be called on Engine thread"。这是 explicit documented contract；non-atomic 字段是有意设计。Agent 未读到这条注释（在 evidence_excerpt 里），verdict 应是 MITIGATED 而非 P1。 |
| F4 | P1 | **REAL_LOWER P2** | x86 emulator only 场景（`#if defined(__i386__) \|\| defined(__x86_64__)`）。用户实际跑 ARM64 设备，无此问题。开发期影响 debug 体验，但非用户场景，降到 P2。修复方向 a（允许 x86 也降级到 SW）最简单。 |
| F5 | P1 | **MITIGATED** | `SetGeometry` 是 inline header function 只从 retro 回调（engine thread）调；`EnsureWindowConfiguredIfNeeded` 在 `Render()`（engine thread）内调。同线程 sequential，三字段 `geometry_base_width_/height_/aspect_ratio_` 不存在 cross-thread read。Agent 的"OnNativeWindowResized 也写这三字段"假设错误（OnNativeWindowResized 调 SetWindowSize，写 atomic `window_width_/height_`，不写 geometry_base_*）。 |
| F6 | P2 | **REAL P2** | `diagEnabled=false` 时 prev unpack state 保持栈默认 4/0，restore 写回 default 会踩坏 HW core 自身的 unpack 状态（如果 HW core 设了 ALIGNMENT=1）。当前 HW core 罕见用 non-default unpack，但 spec-legal。修复：去掉 `diagEnabled` 守卫，永远 query。 |
| F7 | P2 | **REAL P2** | `static bool logged` 跨 init/destroy 不重置，HW 重新初始化后丢失日志。影响 debug，非功能。修复：改 member counter + ShouldLog 节流。 |
| F8 | P2 | **REAL P2** | `ConvertAndScaleXRGB8888_Scalar` 用 float vs 通用路径用 16.16 定点。视觉细微差（理论几 px 边缘漂移），cosmetic。一致化为定点更稳。 |

**T4 小结**: 8 项中 2 项 REAL P1 + 3 项 REAL P2 + 3 项 MITIGATED/REAL_LOWER。F1 需要 user 决定是否信任 agent 的 API 契约 claim（建议查文档后再改）；F2 是确定的 ref leak。

---

## 最终 verdict 计数

| 严重度 | REAL | MITIGATED | 总 |
|---|---|---|---|
| P1 | **2** (T3-F5, T4-F1 lowered from P0) | 0 | 2 |
| P2 | **6** (T3-F2 lowered, T3-F8, T4-F4 lowered, T4-F6, T4-F7, T4-F8) | 0 | 6 |
| 总 REAL | 8 | 7 (MITIGATED) + 1 (FALSE_POSITIVE) | 16 |

**FALSE_POSITIVE 1 项**: T4-F2 修复阶段重审发现 agent 把 ownership-transfer pattern 误读成 ref leak（详见上表）。

**MITIGATED 7 项**: T3-F1/F3/F4/F6/F7 (single-thread engine 保证) + T4-F3 (T4-F5 注释已 documented) + T4-F5 (same-thread access).

## 跨主题校准

- T3 的 5 个并发类 finding (F1/F3/F4/F6/F7) 全部 MITIGATED — agent 把"理论 UB"按 P1/P2 标，没核实实际 caller 线程。这不算 agent 误判，是 audit 阶段的合理 over-flagging；core-review 阶段澄清掉是设计目的。
- T4 的 F3/F5 同样是 over-flagging；F1 的 P0 是缺少官方文档支撑 — 降级到 P1 等 user 确认要不要查文档再改。

## 推荐修复批次（供 CHECKPOINT B 决策）

**最小批 (3 项 P1)**:
- T3-F5: 双 callback 注册改 #if 守卫
- T4-F2: SetWindow generation-changed 分支补 Reference
- T4-F1: 删 AbortBuffer（**前置**: 用户决定是否信任 agent 的 API 契约 claim / 是否要先查官方文档）

**扩展批 (再加 6 项 P2)**:
- T3-F2: Reset() 内 `drc_last_update_ = {}`
- T3-F8: Resampler in[1] → fetch_channel
- T4-F4: x86 降级到 SW（去 sourceMode 过滤）
- T4-F6: 去 diagEnabled 守卫，永远 query unpack state
- T4-F7: static bool logged → member counter + ShouldLog
- T4-F8: XRGB8888 scalar 改 16.16 定点

**防御性建议 (不入 fix scope，写 follow-up backlog)**:
- audio_bridge.h 顶部加 "thread ownership contract" 注释
- ring_buffer.h 顶部加 "SPSC 单 producer 单 consumer 契约" 注释
- T4-F1 待官方文档查证后再纳入下一轮修复

⏸ CHECKPOINT B: 等待用户决定修复 scope。
