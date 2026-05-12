# Render/Audio/Window 全链路收敛方案 V2（性能强化版）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不做“止血补丁”的前提下，完成可交付重构：三条视频链路（Software/GLES/HW）稳定、音频连续、最小化/小窗/前后台兼容，并建立可量化性能门禁。

**Architecture:** 以 `RenderThread` 为唯一窗口与渲染所有者，所有渲染链路共享 `WindowSession(generation)` 状态机；`LibretroEngine` 只产生命令与帧包；`PluginManager` 只上报事件。新增 “性能控制面” （帧预算、背压、降级/恢复策略）与 “发布门禁”。

**Tech Stack:** HarmonyOS NDK (`OH_NativeWindow`, `OH_NativeBuffer`, `OH_NativeVSync`), libretro callbacks, C++14, RenderThread message queue, AudioBridge/RingBuffer。

---

## 1. 本轮复盘：当前方案/现码的漏洞（含证据）

1. 崩溃主因不是 ROM，而是窗口生产者状态失配。  
证据：`日志.txt` 显示 `SIGSEGV` 落在 `OH_NativeWindow_NativeWindowRequestBuffer` 调用栈。  
参考：[日志.txt:57](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/日志.txt:57)、[日志.txt:65](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/日志.txt:65)、[日志.txt:68](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/日志.txt:68)

2. `forceRebind + 同指针 + software` 分支未做破坏性重建，存在 stale surface 风险。  
参考：[render_thread.cpp:290](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/render_thread.cpp:290)

3. `Resize <= 0` 未把 surface 状态置为不可渲染，最小化/小窗边界不完整。  
参考：[render_thread.cpp:326](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/render_thread.cpp:326)、[libretro_engine.cpp:720](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/libretro_engine.cpp:720)

4. 窗口引用管理仍多点持有（PluginManager + Engine + RenderThread），复杂度偏高。  
参考：[plugin_manager.cpp:382](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/app/framework/plugin_manager.cpp:382)、[libretro_engine.cpp:625](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/libretro_engine.cpp:625)

5. 帧包缺少 generation，旧帧无法与窗口代际严格隔离。  
参考：[video_frame_packet.h:12](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/video_frame_packet.h:12)

6. `FramePacer` 只在 dropped 分支限速，正常渲染未受控；且有 busy-spin。  
参考：[video_pipeline.cpp:1029](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/video_pipeline.cpp:1029)、[frame_pacer.h:52](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/frame_pacer.h:52)

7. Software 路径每帧分配+拷贝一份 `vector`，高分辨率下吞吐成本过高。  
参考：[libretro_engine.cpp:2030](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/libretro_engine.cpp:2030)

8. 音频诊断事件每帧发 JSON，UI/事件桥成本高；中断回调里直接 Pause 存在抖动风险。  
参考：[libretro_engine.cpp:1867](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/core/engine/libretro_engine.cpp:1867)、[audio_player.cpp:810](/mnt/d/windsulf/daugf2527-repos/harmonyos-libretro-emulator/entry/src/main/cpp/platform/audio/audio_player.cpp:810)

---

## 2. V2 主线（稳定性 + 性能同时收敛）

1. **单所有权**：只有 `RenderThread` 持有/释放 `OHNativeWindow*`，其余模块不持有引用。  
2. **代际隔离**：所有 window/surface 事件统一转为 `generation++`，所有帧包携带 generation。  
3. **渲染闸门**：`RequestBuffer/Swap` 前必须满足 `session == READY && width/height > 0 && generation match`。  
4. **性能控制面**：引入帧预算、背压、降级/恢复策略，保证不卡死、不失控。  
5. **音频独立面**：音频状态机不随 window 抖动，回调线程只做轻操作。  

---

## 3. 完整任务拆解（V2）

### Task 1: Window 所有权彻底收口

**Files:**
- Modify: `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/core/engine/engine_messages.h`

**Step 1:** 删除 `PluginManager` 内 `NewArchWindowById` 引用计数持有逻辑，仅上报事件。  
**Step 2:** `LibretroEngine` 仅维护 `WindowEvent` 快照，不做 `NativeObjectReference/Unreference`。  
**Step 3:** 所有 `Created/Changed/Destroyed/Resized` 统一下发到 RenderThread。  

### Task 2: WindowSession + generation（强约束）

**Files:**
- Create: `entry/src/main/cpp/core/engine/window_session.h`
- Create: `entry/src/main/cpp/core/engine/window_session.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.h`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`

**Step 1:** 建立 `WindowSession{sessionId,generation,state,width,height,active}`。  
**Step 2:** `SurfaceChanged`（即便同指针）也强制 generation++。  
**Step 3:** generation 变化时清空帧队列，并禁止旧 generation 渲染。  
**Step 4:** `Resize<=0` 进入 `PAUSED_SURFACE`，恢复到 `READY` 前禁止请求 buffer。  

### Task 3: 三渲染链路统一 gate

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_frame_packet.h`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`

**Step 1:** `VideoFramePacket` 增加 `surfaceGeneration`。  
**Step 2:** 入队写 generation；出队必须比对当前 generation。  
**Step 3:** Software/GLES/HW 三链路共用 `RenderPreflight`。  

### Task 4: Software 性能重构（关键）

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Create: `entry/src/main/cpp/core/engine/frame_buffer_pool.h`
- Create: `entry/src/main/cpp/core/engine/frame_buffer_pool.cpp`

**Step 1:** 移除每帧 `shared_ptr<vector>` 分配，改为固定容量 BufferPool（双/三缓冲）。  
**Step 2:** 只在分辨率变化时重建缩放参数，常态帧复用。  
**Step 3:** 黑边填充改为“尺寸变化时重画”，非每帧全量 `fill`。  
**Step 4:** 对超预算帧引入背压策略（先丢旧帧，不阻塞主循环）。  

### Task 5: FramePacer 与时序预算修正

**Files:**
- Modify: `entry/src/main/cpp/core/engine/frame_pacer.h`
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`

**Step 1:** `EndFrame()` 对 rendered/duped/dropped 全部生效。  
**Step 2:** 移除长 busy-spin，改 sleep+短自旋（<300us）。  
**Step 3:** 配置目标帧预算（60fps: 16.67ms，30fps: 33.3ms）。  

### Task 6: GLES/HW 生命周期与线程边界

**Files:**
- Modify: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`

**Step 1:** `SURFACE_LOST/CONTEXT_LOST` 必须绑定 generation；只在当前代际恢复。  
**Step 2:** `WindowDestroyed/Recreated` 时做受控 teardown/reinit。  
**Step 3:** `SwapBuffers` 前统一检查 session active + generation。  

### Task 7: 音频状态机性能化

**Files:**
- Modify: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- Modify: `entry/src/main/cpp/platform/audio/audio_player.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Step 1:** 引入 `AudioRunState`（INIT/BUFFERING/RUNNING/PAUSED/RECOVERING）。  
**Step 2:** `audio_status` 事件节流到 5Hz（仅异常即时上报）。  
**Step 3:** 中断回调改为轻量标记，Pause/Resume 在安全线程执行。  
**Step 4:** 连续 underrun 达阈值才触发恢复动作，禁止抖动。  

### Task 8: 最小化/小窗/前后台适配

**Files:**
- Modify: `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`（按实际入口替换）

**Step 1:** 生命周期事件映射为统一控制消息（foreground/background/minimized/floating）。  
**Step 2:** `minimized/size=0` 仅停渲染，不销毁 core 与音频状态。  
**Step 3:** 恢复时 generation++，先 ready 再放行渲染。  

### Task 9: 诊断与发布门禁

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Add: `docs/architecture/render_window_audio_state_machine.md`

**Step 1:** 输出统一诊断快照：`sessionId/generation/renderMode/audioState/queueDepth`。  
**Step 2:** 建立崩溃前 3 秒关键指标滚动日志（节流）。  
**Step 3:** 固化发布门禁脚本与回归记录模板（不通过即不交付）。  

---

## 4. 硬性交付标准（V2）

### 4.1 稳定性门禁

1. 三渲染链路各运行 30 分钟，无 crash/native fatal。  
2. 模式切换 `Software<->GLES<->HW` 300 次，无闪退。  
3. 生命周期压力（Created/Changed/Resized/Destroyed）500 次，无崩溃。  
4. 最小化/小窗/前后台各 200 次，无黑屏卡死。  

### 4.2 性能门禁（新增）

1. Software 路径 warmup 后每帧动态分配次数为 0。  
2. 60fps 目标下渲染线程 `frame p95 <= 16.7ms`，`p99 <= 25ms`。  
3. `RequestBuffer` 失败率 < 0.1%，且连续失败具备自恢复。  
4. `audio_status` 事件频率 <= 5Hz（异常除外）。  

### 4.3 音频门禁

1. 前后台/小窗切换过程中无持续爆音或静音锁死。  
2. underrun 发生后 10 秒内回到稳定区间。  
3. 禁止 Stop/Start 风暴（连续重建次数受控）。  

### 4.4 架构门禁

1. NativeWindow queue API 调用仅在 RenderThread。  
2. `PluginManager`/`LibretroEngine` 不再持有 window 引用计数。  
3. generation 防 stale 生效（旧代际帧 100% 丢弃可观测）。  

---

## 5. 进度与风险控制

1. 按 Task 分段提交，每段独立可回退。  
2. 先做 Task 1-4（止住 crash + 建性能底座），再做 5-9。  
3. 任一门禁不通过，不交付、不合并、不发布。  

---

## 6. 关于“绝对不出问题”

工程上不能给数学意义“零缺陷”。  
可执行承诺是：**零门禁例外**。只要稳定性/性能/音频/架构任一条不达标，版本即判定“不交付”。  
