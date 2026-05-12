# Libretro Engine Render Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 `retro_run` 与 GL 渲染/`eglSwapBuffers` 从同一线程串行模型改为解耦模型，降低音频 underrun 和帧时间长尾。

**Architecture:** 使用双线程模型。Engine 线程仅负责 `retro_run`、libretro 回调与音频生产；Render 线程仅负责消费像素帧并执行 `VideoPipeline::Render`（含 GLES/CPU/HW 路径）与 swap。线程间通过“有界最新帧队列”传递软件帧快照，队列满时丢最旧帧。渲染触发由 NativeVSync 驱动；Render 线程不调用 libretro API。

**Tech Stack:** C++14（当前仓库标准）、HarmonyOS NDK (`OHNativeWindow`/`OH_NativeBuffer`/`libnative_vsync.so`)、EGL/GLES、现有 `LibretroEngine`/`VideoPipeline`。

---

## 0. 约束与事实基线（必须满足）

1. libretro 线程边界
- `retro_run` 与 libretro API 调用只留在 Engine 线程。
- Render 线程禁止访问 `CoreLoader`、`EnvState` 的 libretro 回调上下文。

2. 数据生命周期
- `OnVideoRefresh(const void* data, ...)` 的 `data` 不能跨线程直接持有。
- 跨线程必须复制为自有内存（或对象池 buffer）。

3. NativeBuffer 规则
- CPU 渲染路径继续使用 `OH_NativeBuffer_FromNativeWindowBuffer + Map/Unmap`，禁止回退 `mmap/munmap`。

4. 超时与节奏
- 不引入 `SET_TIMEOUT=5ms` 这类激进配置。
- `SET_TIMEOUT` 如需设置，保持默认值或 >= 1 帧周期。

5. 渐进发布
- 任何阶段都保留旧路径回滚开关，不做一次性切换。

---

## 1. 当前代码痛点（对应现状）

1. 当前串行链路
- `LibretroEngine::ProcessFrame` 调用 `retro_run()`。
- `OnVideoRefresh` 直接调用 `videoPipeline_.Render(...)`。
- `Render` 路径内可能执行 `eglSwapBuffers`。
- 结果：渲染阻塞直接拉长 `retro_run`，反压音频生产。

2. 高频诊断开销
- `GLESRenderer::Render` 热路径存在每帧 `glGetError/glGetIntegerv`。

3. VSync 驱动未接入
- 已链接 `libnative_vsync.so`，但尚未接入 `OH_NativeVSync` 节奏。

---

## 2. 目标架构设计

### 2.1 线程模型

1. Engine 线程（现有 GameLoop）
- 执行 `retro_run`。
- 处理 libretro 回调：video/audio/input/environment。
- `OnVideoRefresh` 仅生产 `VideoFramePacket` 并入队，快速返回。

2. Render 线程（新增）
- 独占调用 `videoPipeline_.Render(...)`。
- 独占 EGL/GL 操作（含 `eglSwapBuffers`）。
- 响应窗口事件：created/resized/destroyed。
- 响应 NativeVSync 回调触发的 render tick。

3. VSync 回调线程（系统线程）
- 仅投递“RenderTick”信号。
- 不做 GL 调用，不访问 libretro API。

### 2.2 数据通道

1. `VideoFramePacket`（新增）
- 字段：`frameId`、`timestampUs`、`width`、`height`、`pitch`、`pixelFormat`、`isDupe`、`isNull`、`storage`。
- `storage`：`std::shared_ptr<std::vector<uint8_t>>`（先简单可用，后续可换对象池）。

2. `BoundedLatestFrameQueue`（新增）
- 容量默认 `2`（可配置 `2~3`）。
- Push 满队列时丢弃最旧帧，保证最新帧优先。
- 统计：`pushed`、`popped`、`droppedOldest`、`emptyOnTick`。

3. 控制消息队列（复用/扩展）
- 新增 Render 控制消息：`SetWindow`、`Resize`、`SurfaceDestroy`、`Stop`。

### 2.3 渲染节奏

1. 基线
- Render 线程默认由 NativeVSync 触发消费（每次回调请求下一帧）。

2. 回退
- 若 NativeVSync 初始化失败，回退 `condition_variable + 16ms` 等待策略。

3. DVSync
- 仅在手机/平板且 buffer 充足场景评估，默认关闭。

---

## 3. 分阶段实施（按风险由低到高）

### Task 1: 引入诊断开关，先降低热路径干扰

**Files:**
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.h`
- Modify: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Step 1:** 在 `GLESRenderer` 增加 `diagEnabled` 开关（默认 false）。
- 每帧 `glGetError/glGetIntegerv` 仅在开关开启时执行。
- 错误路径日志保留，不影响故障定位。

**Step 2:** 在 `LibretroEngine` 新增控制接口
- `SetGlesDiagEnabled(bool)`，供 NAPI 透传。

**Step 3:** 验收
- 正常运行日志不再每帧刷 `GLES_DIAG` 查询信息。
- 错误场景仍能打出关键错误日志。

---

### Task 2: 新增帧包和有界最新帧队列

**Files:**
- Create: `entry/src/main/cpp/core/engine/video_frame_packet.h`
- Create: `entry/src/main/cpp/core/engine/bounded_latest_frame_queue.h`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`

**Step 1:** 定义 `VideoFramePacket`
- 软件帧在 `OnVideoRefresh` 内复制到 `storage`。
- 对 `null/dupe` 帧设专门标记，避免无意义复制。

**Step 2:** 实现 `BoundedLatestFrameQueue`
- API: `Push(packet)`、`PopLatest(packet)`、`Clear()`。
- 线程安全：`std::mutex + std::condition_variable`。

**Step 3:** 增加统计结构
- 新增 `queueDroppedOldest`、`queueDepthMax`、`renderTickNoFrame`。

---

### Task 3: 新增 RenderThread 并接管渲染调用

**Files:**
- Create: `entry/src/main/cpp/core/engine/render_thread.h`
- Create: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`

**Step 1:** RenderThread 生命周期
- `Start()`、`Stop()`、`Join()`、`SetWindow(OHNativeWindow*)`、`OnResize(w,h)`。

**Step 2:** RenderThread 主循环
- 等待 `RenderTick` 或控制消息。
- 从 `BoundedLatestFrameQueue` 取最新帧后调用 `videoPipeline_.Render(...)`。

**Step 3:** 改造 `OnVideoRefresh`
- 删除直接 `videoPipeline_.Render(...)`。
- 改为快速 `EnqueueSoftwareFrame(...)`。
- 统计 `enqueue_ok / enqueue_drop`。

**Step 4:** 线程边界保护
- 在 RenderThread 代码注释和接口层明确“禁止调用 libretro API”。

---

### Task 4: 将窗口生命周期转发到 RenderThread

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.h`
- Modify: `entry/src/main/cpp/core/engine/window_state_manager.h`
- Modify: `entry/src/main/cpp/core/engine/window_state_manager.cpp`

**Step 1:** `WindowCreated/Destroyed/Resized` 消息处理
- Engine 线程不再直接触发渲染调用。
- 改为 `renderThread_.PostWindowEvent(...)`。

**Step 2:** 统一锁边界
- 删除/收缩 `renderMutex_` 用途，避免 Engine 与 Render 线程交错持锁。

**Step 3:** Surface 销毁流程
- `WindowDestroyed` 时先停渲染消费，再释放 surface/EGL 资源。

---

### Task 5: 接入 NativeVSync 驱动

**Files:**
- Create: `entry/src/main/cpp/platform/sync/native_vsync_driver.h`
- Create: `entry/src/main/cpp/platform/sync/native_vsync_driver.cpp`
- Modify: `entry/src/main/cpp/core/engine/render_thread.h`
- Modify: `entry/src/main/cpp/core/engine/render_thread.cpp`
- Modify: `entry/src/main/cpp/CMakeLists.txt`

**Step 1:** 封装驱动
- `Create(name)`、`RequestNextFrame()`、`Destroy()`。
- 回调仅做 `NotifyRenderTick()`。

**Step 2:** RenderThread 接入
- 每次处理完一个 tick 后再次 `RequestNextFrame()`。
- 避免 busy loop。

**Step 3:** 回退策略
- `NativeVSync` 失败自动切到定时等待。

---

### Task 6: 调整自动跳帧策略，改为队列丢旧优先

**Files:**
- Modify: `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- Modify: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`

**Step 1:** 降低 `OnVideoRefresh` 内部 skip 复杂度
- 由“渲染慢触发主动 skip”改为“队列容量控制 + 丢最旧帧”。

**Step 2:** 音频策略保持稳定
- 仅观察 underrun 指标，不引入大范围音频逻辑重写。

---

### Task 7: NAPI/ArkTS 开关与指标暴露

**Files:**
- Modify: `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- Modify: `entry/src/main/cpp/types/libentry/index.d.ts`
- Optional Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Step 1:** 新增调试/灰度接口
- `refactoredSetRenderThreadEnabled(boolean)`
- `refactoredSetNativeVSyncEnabled(boolean)`
- `refactoredSetGlesDiagEnabled(boolean)`

**Step 2:** 新增统计接口字段
- `queueDroppedOldest`、`renderThreadFrameMsP95`、`renderTickNoFrame`、`vsyncCallbackJitterMsP95`。

**Step 3:** 默认值
- 新架构默认开、可一键回滚旧架构。

---

## 4. 关键伪代码（落地参考）

### 4.1 OnVideoRefresh（Engine 线程）

```cpp
void LibretroEngine::OnVideoRefresh(const void* data, unsigned w, unsigned h, size_t pitch) {
  if (surface_state_ != SurfaceState::VALID) return;

  VideoFramePacket pkt{};
  pkt.frameId = ++videoFrameSeq_;
  pkt.timestampUs = NowUs();
  pkt.width = w;
  pkt.height = h;
  pkt.pitch = pitch;
  pkt.pixelFormat = videoPipeline_.GetPixelFormat();
  pkt.isNull = (data == nullptr);
  pkt.isDupe = (data == nullptr);

  if (!pkt.isNull) {
    const size_t bytes = pitch * h;
    pkt.storage = framePool_.Acquire(bytes);
    std::memcpy(pkt.storage->data(), data, bytes);
  }

  frameQueue_.Push(std::move(pkt)); // 满队列丢旧帧
}
```

### 4.2 RenderThread Tick（Render 线程）

```cpp
void RenderThread::OnRenderTick() {
  VideoFramePacket pkt;
  if (!frameQueue_.PopLatest(pkt)) {
    stats_.renderTickNoFrame++;
    RequestNextVsync();
    return;
  }

  videoPipeline_.Render(window_,
                        pkt.isNull ? nullptr : pkt.storage->data(),
                        pkt.width,
                        pkt.height,
                        pkt.pitch,
                        &metrics);

  RequestNextVsync();
}
```

---

## 5. 验收标准（以手工日志验收为主）

1. 性能与稳定性
- `retro_run` P95 明显下降并稳定（目标 < 20ms，按 GB/Gambatte 基线）。
- `eglSwapBuffers` 长尾不再直接对应 `Slow retro_run`。
- 音频 `underrun`、`producer gap` 发生频率显著下降。

2. 行为正确性
- 画面持续更新，无明显闪屏/花屏。
- Surface destroy/recreate 后可恢复渲染，不崩溃。
- core 切换、ROM 切换流程不回归。

3. 可观测性
- 可读取队列丢帧、render tick 空转、vsync 抖动等指标。

---

## 6. 风险清单与对策

1. 风险：跨线程复制引入额外内存带宽
- 对策：先容量 2、优先 latest；后续再引入固定块对象池。

2. 风险：窗口销毁竞态导致 EGL 崩溃
- 对策：RenderThread 单点持有/释放 EGL；窗口消息串行化。

3. 风险：NativeVSync 不可用或行为不一致
- 对策：自动回退定时 tick；保留开关。

4. 风险：HW Render 核心路径复杂
- 对策：Phase 1 先稳定软件/GLES，HW 路径后置灰度。

---

## 7. 回滚策略

1. 运行时开关回滚
- `renderThreadEnabled=false` 回到旧同步渲染路径。
- `nativeVsyncEnabled=false` 回退定时唤醒。

2. 代码回滚边界
- 每个 Task 独立提交，保证可按任务粒度回退。

---

## 8. 实施顺序建议（你这边最稳妥）

1. 先做 Task 1（诊断开关）+ Task 2（队列）
2. 再做 Task 3（RenderThread）并保留旧路径开关
3. 之后做 Task 4/5（窗口事件转发 + NativeVSync）
4. 最后 Task 6/7（策略收敛 + 指标/开关完善）

该顺序能保证你每一步都可观测、可回滚，不会一次改太多导致难排障。
