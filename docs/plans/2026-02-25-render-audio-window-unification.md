# Render/Audio/Window 全链路收敛实施方案

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将当前渲染与窗口生命周期从“多点管理”收敛为“单线程单所有权”，确保三条视频渲染链路（Hardware/Software/GLES）与音频链路在最小化、小窗、前后台切换、旋转/尺寸变化场景下稳定运行。

**Architecture:** 采用 `RenderThread` 作为唯一 NativeWindow owner；`PluginManager` 仅上报生命周期事件，不直接管理 window 引用；`LibretroEngine` 仅负责仿真逻辑与帧/控制消息投递。通过统一 `WindowSession + generation` 机制，避免 stale window/surface 进入 RequestBuffer/Swap 路径。音频维持独立回调线程，新增状态机与漂移观测，保障不卡音、不断音、不反复重置。

**Tech Stack:** HarmonyOS NDK (`OH_NativeWindow`, `OH_NativeBuffer`, `OH_NativeVSync`), libretro callback pipeline, C++14, RenderThread + message queue, AudioBridge/RingBuffer。

---

## 0. 非谈判约束（主线）

1. 单窗口不等于单管理点。必须保证“同一个窗口句柄”只有一个线程执行 `RequestBuffer/FlushBuffer/AbortBuffer/HandleOpt`。
2. 所有 EGL/GL/Vulkan/NativeWindow buffer queue 操作只允许在 `RenderThread`。
3. `PluginManager` 不持有 window 引用计数，不做 window 生命周期决策。
4. `LibretroEngine` 不直接调用 NativeWindow queue API，仅投递控制消息到 `RenderThread`。
5. 软件渲染、GLES 渲染、HW 回调渲染三条链路必须共享同一套 window session 状态机。
6. 音频线程独立，不因渲染链路切换导致 `AudioBridge` 反复 Stop/Start 抖动。

---

## 1. 现状问题归因（用于对齐）

1. 目前窗口生命周期在 `PluginManager`、`LibretroEngine`、`RenderThread` 多处管理，引用与重绑路径交织。
2. 软件渲染崩溃点已落在 `RequestBuffer`，说明是 surface producer 状态不一致/失配，而非核心 ROM 逻辑。
3. `SurfaceChanged` + forceRebind + 异步渲染并发，易形成 stale session。
4. 当前代码存在大量“防御性补丁式分支”，增加状态空间，降低可验证性。

---

## 2. 目标架构（抓主线）

### 2.1 单一所有权模型

1. `RenderThread`：唯一 window owner（持有引用、处理生命周期、执行三条视频链路）。
2. `LibretroEngine`：产生 `VideoFramePacket` + `ControlMessage`，不触碰 NativeWindow queue。
3. `PluginManager`：只发 `SurfaceCreated/Changed/Destroyed/Resized` 事件到 `LibretroEngine`。

### 2.2 WindowSession + Generation

1. 引入 `WindowSessionId` 与 `SurfaceGeneration`。
2. 每次 `Created/Recreated` 生成新 generation；旧 generation 帧直接丢弃。
3. `RenderThread` 内部在处理控制消息时切换 session，并原子清空旧帧队列。

### 2.3 三条视频链路统一入口

1. `VideoPipeline::Render()` 仅由 `RenderThread` 调用。
2. `SOFTWARE`: `RequestBuffer -> Map -> Convert -> Unmap -> Flush`。
3. `GLES`: 上下文/Surface 生命周期完全绑定 session generation。
4. `HW`: `HW_SWAP/HW_NULL` 仅在 active session 执行，禁止跨 session Swap。

### 2.4 音频链路稳定策略

1. `AudioBridge` 生命周期只受 Engine state 驱动，不受 window 事件直接影响。
2. 模式切换/窗口变化时禁止音频硬重置，仅更新统计与节流策略。
3. 引入 “audio continuity guard”：连续 underrun 超阈值才触发恢复动作。

---

## 3. 功能拆解（按工作流）

### Task 1: Window 生命周期收口

**Files:**
- Modify: `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/engine_messages.h`

**Step 1:** 定义统一消息语义，仅保留 `Created/Changed(语义重建)/Resized/Destroyed`。  
**Step 2:** `PluginManager` 移除 window map 持有引用逻辑（保留 xcomponent id 与事件上报）。  
**Step 3:** `LibretroEngine` 接收事件后只转发到 `RenderThread`，不再执行 NativeWindow 引用管理。  
**Step 4:** 清理旧 rebind 分支，避免双路路径并存。

### Task 2: RenderThread 成为唯一 Window Owner

**Files:**
- Modify: `entry/src/main/cpp/core/engine/render_thread.h`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Create: `entry/src/main/cpp/core/engine/window_session.h`
- Create: `entry/src/main/cpp/core/engine/window_session.cpp`

**Step 1:** 增加 `WindowSession`（window ptr + generation + width/height + active flags）。  
**Step 2:** 在 `HandleSetWindow/HandleResize/HandleDestroy` 内维护 session 状态机。  
**Step 3:** 在 session 切换时清空 frame queue，并标记旧 generation 失效。  
**Step 4:** 确保 `RequestBuffer/FlushBuffer/Swap` 前验证 generation 一致。

### Task 3: VideoPipeline 三链路统一 session gate

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.h`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/core/engine/video_frame_packet.h`

**Step 1:** 给 `VideoFramePacket` 增加 `surfaceGeneration` 字段。  
**Step 2:** `RenderThread` 入队时带 generation；出队渲染前校验 generation。  
**Step 3:** 软件链路补齐 preflight 校验（window valid/size valid/mode valid）。  
**Step 4:** GLES/HW 链路在 generation 变化时执行受控 teardown/reinit。

### Task 4: 软件渲染路径稳态化

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/core/engine/window_state_manager.cpp`

**Step 1:** 将 `HandleOpt` 重试策略改为“事件驱动重配”而非“失败即每帧重配”。  
**Step 2:** 增加 `RequestBuffer` 前状态快照日志（节流）。  
**Step 3:** 明确 `fenceFd` 生命周期，保证 single-close。  
**Step 4:** 将 flush region 固定为有效全屏 dirty rect（避免 null region 驱动兼容性问题）。

### Task 5: GLES/HW 生命周期对齐

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.h`

**Step 1:** 将 `SURFACE_LOST/CONTEXT_LOST/FATAL` 转移条件绑定 session generation。  
**Step 2:** `SurfaceChanged` 不做无条件强制全重建，仅在 generation 变更后重建。  
**Step 3:** HW 路径 `SwapBuffers` 前统一检查 session active。  
**Step 4:** GLES 与 HW 的窗口销毁处理只在 `RenderThread` 执行。

### Task 6: 音频连续性与状态机收敛

**Files:**
- Modify: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- Modify: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Step 1:** 定义 `AudioRunState`（INIT/BUFFERING/RUNNING/PAUSED/RECOVERING）。  
**Step 2:** 去除窗口事件对音频的直接控制耦合。  
**Step 3:** 统一 pause/resume 时机，避免切前后台时反复硬停。  
**Step 4:** 增加 underrun/overrun 连续窗口统计，触发阈值后再恢复。

### Task 7: 最小化/小窗/前后台兼容

**Files:**
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`（若实际入口不同按真实页面替换）
- Modify: `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Step 1:** 明确 ArkTS 生命周期事件到 Engine 控制消息映射。  
**Step 2:** 最小化/小窗状态仅改变 surface active，不销毁核心状态。  
**Step 3:** 前台恢复时按 session generation 拉起渲染，不重置音频/核心。  
**Step 4:** 添加 NAPI 诊断接口输出当前 session/audio/render 状态快照。

### Task 8: 清理冗余与可维护性交付

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- Modify: `docs/`（新增架构说明）

**Step 1:** 删除已失效的双轨分支与重复引用计数代码。  
**Step 2:** 统一日志前缀与错误码语义，减少噪声日志。  
**Step 3:** 输出状态机文档与时序图（Created/Resized/Destroyed + 三渲染链路 + 音频）。  
**Step 4:** 形成最终交付说明（兼容矩阵、回归清单、已知限制）。

---

## 4. 交付标准（硬性验收）

## 4.1 稳定性标准

1. 三渲染链路分别连续运行 30 分钟，无 crash、无 native fatal。
2. 模式切换压力测试（`Hardware <-> Software <-> GLES`）100 次，无闪退。
3. `SurfaceChanged/Resized/Destroyed/Recreated` 压力测试 200 次，无崩溃。
4. 最小化->恢复、小窗->全屏、前台->后台->前台各 100 次，无黑屏卡死。

## 4.2 音频标准

1. 前后台切换与窗口状态变化过程中无持续性爆音/静音锁死。
2. `underrun` 峰值可观测且可恢复，恢复后 10 秒内回到稳定区间。
3. 模式切换不触发音频线程重建风暴（连续 Stop/Start 次数受控）。

## 4.3 架构标准

1. NativeWindow queue API 调用点仅存在于 `RenderThread/VideoPipeline` 渲染线程上下文。
2. `PluginManager` 不再持有 window 引用计数。
3. `LibretroEngine` 不再直接调用 `RequestBuffer/FlushBuffer/AbortBuffer`。
4. Session generation 防 stale 生效：旧 generation 帧全部丢弃且可观测。

## 4.4 代码质量标准

1. 删除或合并重复生命周期分支，window 管理入口从多处收敛到单处。
2. 日志可用于定位：每次 crash 前可追踪 session id/generation/mode/audio state。
3. 文档齐备：状态机、时序图、回归矩阵、运维诊断指引。

---

## 5. 回归矩阵（必须覆盖）

1. 三渲染链路 x 3 核心（纯软件核心、GLES核心、HW核心）。
2. 分辨率与方向变化：竖屏、横屏、旋转中切模式。
3. 生命周期：Created/Changed/Resized/Destroyed 高频组合。
4. 应用状态：前台、后台、锁屏、最小化、小窗。
5. 音频场景：静音、恢复、蓝牙切换（若设备支持）、不同 sample rate 核心。

---

## 6. 风险与兜底

1. 风险：一次性重构过大。  
兜底：按 Task 分段提交，每段可回滚，不跨任务混改。

2. 风险：GLES/HW 依赖机型驱动差异。  
兜底：保留 software fallback，但 fallback 逻辑必须在 RenderThread 内实现。

3. 风险：最小化/小窗行为设备差异。  
兜底：session 状态机以“surface validity”而非“UI 事件顺序”作为最终真值。

---

## 7. 关于“绝对不出问题”的工程承诺边界

“零缺陷”在工程上不能做数学保证，但可以做“可验证的发布门禁保证”。  
本方案把“不能出问题”落到强制验收门槛：只要任一门槛不通过，就不交付、不合并、不发布。

---

## 8. 实施节奏建议

1. 第 1 天：Task 1-2（窗口所有权收敛 + session 基础）
2. 第 2 天：Task 3-4（三链路 session gate + 软件路径稳态）
3. 第 3 天：Task 5-6（GLES/HW 对齐 + 音频连续性）
4. 第 4 天：Task 7-8（小窗/最小化兼容 + 冗余清理 + 文档与验收）

