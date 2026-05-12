# Render/Audio/Window 完全体交付方案 V3

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 交付一个可发布版本：三条视频渲染链路（Software/GLES/HW）稳定可切换，音频连续，最小化/小窗/前后台/旋转兼容，且具备可验证的性能与稳定性门禁。

**Architecture:** `RenderThread` 为唯一渲染与窗口所有者；`LibretroEngine` 只负责核心运行与消息编排；`PluginManager` 只负责事件上报。使用统一 `WindowSession(generation)` 状态机做三链路闸门，配套 `AudioRunState` 与故障降级控制面（degrade/recover）。

**Tech Stack:** HarmonyOS NDK (`OH_NativeWindow`, `OH_NativeBuffer`, `OH_NativeVSync`), libretro callback pipeline, C++14, RenderThread message queue, AudioBridge/RingBuffer。

---

## 0. 先给结论（本质问题）

1. 当前闪退本质不是“代码多”本身，而是“生命周期所有权分裂 + 状态机不闭环”。
2. 崩溃点在 `OH_NativeWindow_NativeWindowRequestBuffer`，说明进入了无效/过期 surface producer 路径。
3. 性能问题本质是“热路径动态分配 + 不完整节流 + 诊断噪声过高”，导致抖动加剧并放大竞态窗口。

---

## 1. 非谈判架构约束（必须 100% 落地）

1. `OH_NativeWindow_Request/Flush/Abort/HandleOpt` 只允许在 `RenderThread` 调用。
2. `PluginManager` 与 `LibretroEngine` 不持有 `OHNativeWindow` 引用计数，不做引用生命周期。
3. `SurfaceChanged` 无论指针是否相同，必须 `generation++`。
4. 所有待渲染帧必须携带 `surfaceGeneration`，渲染前做一致性校验，不一致直接丢弃。
5. `width<=0 || height<=0` 必须进入 `PAUSED_SURFACE`，禁止任何 `RequestBuffer/Swap`。
6. 音频状态机独立于窗口事件，窗口抖动不能触发音频 Stop/Start 风暴。

---

## 2. 统一状态机设计

### 2.1 WindowSessionState

1. `DETACHED`: 无窗口。
2. `ATTACHED_PENDING_SIZE`: 有窗口但尺寸未就绪。
3. `READY`: 可渲染。
4. `PAUSED_SURFACE`: 最小化/小窗尺寸为 0/后台不可见。
5. `DESTROYED`: 销毁等待下一次 attach。

状态迁移规则：
1. `Created -> ATTACHED_PENDING_SIZE (generation++)`
2. `Resized(valid) -> READY`
3. `Resized(invalid) -> PAUSED_SURFACE`
4. `Changed -> ATTACHED_PENDING_SIZE (generation++)`
5. `Destroyed -> DESTROYED (generation++)`

### 2.2 RenderModeState

1. `SW_READY`
2. `GLES_READY`
3. `HW_READY`
4. `DEGRADED_TO_SW`（GLES/HW 异常降级）
5. `RECOVERING`（冷却后恢复尝试）

### 2.3 AudioRunState

1. `INIT`
2. `BUFFERING`
3. `RUNNING`
4. `PAUSED`
5. `RECOVERING`

---

## 3. 完整任务拆解（可交付版）

### Task 1: 所有权单点化（窗口）

**Files:**
- Modify: `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`

**Steps:**
1. 删除 `PluginManager` 的窗口 map 引用持有逻辑，只保留事件转发。
2. `LibretroEngine` 去掉 `NativeObjectReference/Unreference` 路径。
3. 统一事件消息：`WindowCreated/Changed/Resized/Destroyed`。

### Task 2: WindowSession + generation 硬闸门

**Files:**
- Create: `entry/src/main/cpp/core/engine/window_session.h`
- Create: `entry/src/main/cpp/core/engine/window_session.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.h`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Modify: `entry/src/main/cpp/core/engine/video_frame_packet.h`

**Steps:**
1. 引入 `WindowSession` 数据结构（sessionId/generation/state/size/active）。
2. `RenderThread` 处理所有窗口消息并维护唯一真值状态机。
3. 帧包增加 `surfaceGeneration` 字段，出队渲染前强校验。
4. generation 切换时原子清空队列，丢弃旧代际帧。

### Task 3: 三链路统一渲染闸门

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.h`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`

**Steps:**
1. 抽取 `RenderPreflight(session,mode,frame)`。
2. Software/GLES/HW 共享同一 preflight 失败策略（drop + reason）。
3. `forceRebind` 改为显式 generation 更新，不走隐式重绑分支。

### Task 4: Software 热路径性能重构

**Files:**
- Create: `entry/src/main/cpp/core/engine/frame_buffer_pool.h`
- Create: `entry/src/main/cpp/core/engine/frame_buffer_pool.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`

**Steps:**
1. 去除每帧 `shared_ptr<vector>` 分配，改固定池（2-3 槽）复用。
2. 缩放参数与黑边区域只在尺寸变化时重算。
3. 长耗时帧触发背压：优先丢旧帧，禁止阻塞核心线程。
4. 记录每帧 CPU 渲染分段耗时（request/fence/map/convert/unmap/flush）。

### Task 5: FramePacer 与调度一致性

**Files:**
- Modify: `entry/src/main/cpp/core/engine/frame_pacer.h`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`

**Steps:**
1. `EndFrame()` 对 rendered/duped/dropped 全生效。
2. 限制 busy-spin（仅保留短尾 <300us）。
3. 与 native vsync/fallback tick 协同，避免双节流冲突。

### Task 6: GLES/HW 故障闭环（降级+恢复）

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.h`

**Steps:**
1. 连续 `surface/context/swap` 失败达到阈值后自动降级 `DEGRADED_TO_SW`。
2. 降级后进入冷却窗口（如 3-5 秒）再尝试 `RECOVERING`。
3. 恢复失败有上限，超过上限保持 software，避免反复抖动。
4. 全过程只允许在 `RenderThread` 执行。

### Task 7: 音频连续性保证

**Files:**
- Modify: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- Modify: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Steps:**
1. 落地 `AudioRunState` 并统一触发点。
2. 音频中断回调只做标记，实际 Pause/Resume 切到安全线程执行。
3. `audio_status` 上报节流（5Hz），异常事件即时。
4. underrun 连续阈值触发恢复，杜绝 Stop/Start 频繁振荡。

### Task 8: 最小化/小窗/前后台兼容

**Files:**
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`（按实际入口替换）
- Modify: `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Steps:**
1. ArkTS 生命周期映射为统一控制消息，禁止直接跨线程操作渲染对象。
2. 最小化/小窗仅改变 surface active，不销毁 core 与音频状态。
3. 恢复时强制 generation++ 并先完成 READY 再放行帧。

### Task 9: 可观测性与交付文档

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Add: `docs/architecture/render_audio_window_state_machine.md`
- Add: `docs/verification/render_audio_delivery_gate.md`

**Steps:**
1. 输出统一状态快照：`sessionId/generation/windowState/renderMode/audioState`。
2. 增加崩溃前关键窗口日志（滚动、节流）。
3. 形成最终交付文档：状态机图、兼容矩阵、故障策略、门禁结果。

---

## 4. 性能预算（发布级）

1. Software: `frame p95 <= 16.7ms`, `p99 <= 25ms`（60fps目标）。
2. GLES/HW: swap 失败率 < 0.1%，连续失败自动降级有效。
3. 每帧动态内存分配（render hot path）= 0（warmup 后）。
4. `audio_status` 普通上报 <= 5Hz。
5. 回调线程无阻塞重操作（音频中断回调中不做重状态切换）。

---

## 5. 交付门禁（不通过即不交付）

1. 稳定性门禁：三链路分别 30 分钟稳定，无 crash/native fatal。
2. 切换门禁：`Software<->GLES<->HW` 循环 300 次无闪退。
3. 生命周期门禁：`Created/Changed/Resized/Destroyed` 压测 500 次无崩溃。
4. 状态门禁：最小化/小窗/前后台/旋转各 200 次无黑屏卡死。
5. 音频门禁：无持续爆音/静音锁死，underrun 可恢复。
6. 架构门禁：NativeWindow queue API 调用点只在 RenderThread。

---

## 6. 风险与兜底

1. 风险：一次性改动面大。  
兜底：按 Task 分段提交，每段可回退，不跨任务混改。

2. 风险：模拟器与真机驱动行为差异。  
兜底：两端都跑门禁；降级策略默认开启。

3. 风险：极端窗口事件顺序乱序。  
兜底：以 `generation + session state` 为最终真值，不信 UI 事件顺序。

---

## 7. 里程碑（建议）

1. M1（Day1-Day2）: Task1-3，完成崩溃根因封堵与状态机骨架。
2. M2（Day3-Day4）: Task4-6，完成性能重构与三链路故障闭环。
3. M3（Day5-Day6）: Task7-9，完成音频稳定、状态兼容、文档与门禁收口。

---

## 8. 关于“绝对不出问题”

工程上无法数学证明零缺陷。  
本方案给的是“发布级零例外门禁承诺”：任一门禁不过，版本一律不交付。
