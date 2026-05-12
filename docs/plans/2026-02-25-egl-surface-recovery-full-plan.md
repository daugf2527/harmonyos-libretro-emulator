# EGL Surface 恢复完整方案（有声无画问题）

## 1. 背景与现象

### 1.1 现象
- 运行过程中音频持续正常输出，但视频黑屏。
- 日志出现大量连续错误：`eglSwapBuffers failed: 0x300d`（`EGL_BAD_SURFACE`）。
- 典型时间段：`2026-02-25 20:47:43` 之后连续报错，且未自动恢复画面。

### 1.2 关键事实
- `0x300d` 对应 `EGL_BAD_SURFACE`，含义是当前 `EGLSurface` 已无效。
- 当前代码路径中，渲染错误被检测到了，但“失败升级和强制重绑”不完整，导致进入反复掉帧但不恢复的状态。

## 2. 目标与非目标

### 2.1 目标
- 在 Surface 失效、窗口重建、上下文丢失等场景下实现自动恢复。
- 消除“有声无画”的长时间卡死态。
- 保持 EGL/GL 操作严格在渲染线程。
- 提供可观测指标，便于线上定位恢复是否生效。

### 2.2 非目标
- 不改动核心模拟逻辑（`retro_run`、音频重采样算法）。
- 不引入 UI 层复杂交互，仅通过现有事件与状态机制恢复。

## 3. 本地代码根因分析（结合当前实现）

## 3.1 恢复状态机路径单一
- 文件：`entry/src/main/cpp/core/engine/video_pipeline.cpp`
- 关键区段：`RenderGLES()`（约 513 行起）
- 问题：
  - `SURFACE_LOST` 状态仅执行 `RecreateSurface(window)`。
  - 重建失败只会 `drop`，缺少“失败升级到完整 `Deinit + Init`”的路径。
  - 缺少退避策略，容易形成快速重试循环。

## 3.2 窗口句柄同值时不触发重绑
- 文件：`entry/src/main/cpp/core/engine/libretro_engine.cpp`
- 关键区段：`SetNativeWindow()`（约 614 行起）
- 问题：
  - 仅当 `window_ != window` 或 `xcomponentId` 变化时，才发送窗口消息。
  - 系统侧 Surface 重建时，`OHNativeWindow*` 可能不变，导致渲染线程收不到重建信号。

## 3.3 RenderThread 同指针短路
- 文件：`entry/src/main/cpp/core/engine/render_thread.cpp`
- 关键区段：`HandleSetWindow()`（约 239 行起）
- 问题：
  - `window_ == window` 直接返回。
  - 即使需要强制重绑，也无法触发 `videoPipeline_.Reset()/Reinit`。

## 3.4 引擎 Surface 状态与 EGL 健康状态割裂
- 文件：`entry/src/main/cpp/core/engine/libretro_engine.cpp`
- 关键区段：`OnVideoRefresh()`（约 1869 行起）
- 问题：
  - `surface_state_` 只由 XComponent 生命周期驱动，不能反映 EGL 内部真实失效状态。
  - EGL 失效后，帧仍持续入队，造成失败刷屏。

## 3.5 GLES 层错误识别有了，但上层闭环未打通
- 文件：`entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- 关键区段：`Render()` 的 `eglSwapBuffers` 失败分支（约 1100 行起）
- 现状：
  - 已区分 recoverable error 与 context lost（方向正确）。
  - 但上层未完成“状态升级 + 强制重绑 + 失败退避”链路。

## 4. 完整方案设计

## 4.1 统一渲染恢复状态机（VideoPipeline）

### 新状态定义
- `UNINITIALIZED`
- `READY`
- `SURFACE_LOST`
- `CONTEXT_LOST`
- `WAIT_WINDOW`
- `FATAL`（可选，用于达到失败上限）

### 状态转移原则
- `READY`:
  - `EGL_BAD_SURFACE/BAD_NATIVE_WINDOW/BAD_MATCH` -> `SURFACE_LOST`
  - `EGL_CONTEXT_LOST` -> `CONTEXT_LOST`
- `SURFACE_LOST`:
  - 优先 `RecreateSurface(window)`。
  - 连续失败达到阈值后升级为 `UNINITIALIZED`（完整 `Deinit + Init`）。
- `CONTEXT_LOST`:
  - 直接走完整上下文重建（`Deinit + Init` + GL 资源重建）。
- 无可用窗口时 -> `WAIT_WINDOW`。
- 长时间不可恢复 -> `FATAL` 或降级到 CPU 路径。

## 4.2 引入“强制重绑窗口”通道（Engine -> RenderThread）

### 设计
- 在引擎消息层新增 `WindowRebind`（或在 `WindowCreated` 上增加 `force` 标记）。
- `OnSurfaceChanged` 场景即使指针未变，也发 `WindowRebind`。
- `RenderThread::HandleSetWindow` 支持 `forceRebind=true`：
  - 执行旧 surface 清理 -> pipeline reset -> 重新绑定同一窗口。

### 目的
- 解决“指针不变但 surface 已变”的恢复盲区。

## 4.3 将 EGL 健康状态回传引擎层

### 设计
- `VideoPipeline/GLESRenderer` 在进入 `SURFACE_LOST/CONTEXT_LOST` 时通知 `LibretroEngine`：
  - 将 `surface_state_` 从 `VALID` 降级到 `CREATED`。
- 恢复成功后再置回 `VALID`。

### 目的
- 在恢复窗口期主动丢帧，避免向坏 surface 持续提交渲染。

## 4.4 恢复重试与退避策略

### 策略
- 失败计数分层：
  - `surface_recreate_fail_count`
  - `context_reinit_fail_count`
- 时间退避：
  - 100ms -> 300ms -> 1000ms（上限）
- 升级策略：
  - `RecreateSurface` 连续失败 `N` 次（建议 3）后触发完整重建。
  - 完整重建连续失败 `M` 次（建议 5）后触发降级或 `FATAL`。

## 4.5 降级策略（防长期黑屏）

### 可选开关（建议默认开启）
- 当 GLES 恢复失败超过阈值，自动切到 `SOFTWARE_SCALING`。
- 发出事件通知 ArkTS：`video_recovery_degraded`，便于 UI 提示。
- 后续可在空闲时尝试回切 GLES（可选二期）。

## 4.6 观测与日志

### 新增统计项
- `eglRecoverableErrors`
- `eglContextLostCount`
- `surfaceRecreateAttempts/success/fail`
- `fullReinitAttempts/success/fail`
- `forcedWindowRebindCount`
- `degradeToCpuCount`

### 日志策略
- 错误日志采样（突发 + 间隔），禁止毫秒级连续刷屏。
- 每次状态切换打印一次结构化日志（含状态、计数、窗口尺寸、耗时）。

## 5. 分文件改造清单

## 5.1 `entry/src/main/cpp/core/engine/video_pipeline.h/.cpp`
- 扩展 `GlesState` 与恢复计数器、退避时间戳。
- `RenderGLES()` 重构为显式状态机处理函数。
- 新增恢复结果枚举（区分 `recoverable-surface`、`context-lost`、`fatal`）。
- 增加通知引擎 surface 有效性的接口（回调或注入函数）。

## 5.2 `entry/src/main/cpp/platform/graphics/gles_renderer.h/.cpp`
- 提供最近一次 EGL 错误类型查询接口（避免上层只看 bool）。
- `Render()` 在 swap 失败时输出分类错误并标记健康状态。
- 保持 `RecreateSurface()` 仅处理 surface 级恢复，不承担状态机调度。

## 5.3 `entry/src/main/cpp/core/engine/engine_messages.h`
- 增加 `WindowRebind` 消息（或扩展 WindowCreated 负载结构）。

## 5.4 `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- `SetNativeWindow()` 增加 force-rebind 触发逻辑。
- `OnSurfaceChanged` 路径显式触发重绑消息（即便窗口指针不变）。
- 接收并应用 pipeline 回传的 surface 健康状态，驱动 `surface_state_`。

## 5.5 `entry/src/main/cpp/core/engine/render_thread.cpp`
- `HandleSetWindow()` 支持强制重绑，不再仅按指针比较短路。
- 在重绑时保证顺序：停用旧 surface -> reset pipeline -> bind 新 surface。

## 5.6 `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- `OnSurfaceChanged` 调用中明确传递“窗口重绑语义”（新接口）。

## 6. 执行阶段计划

## 阶段 A：状态机与错误分类打通
- 完成 `VideoPipeline` 状态机重构。
- 接入 `GLESRenderer` 错误分类输出。
- 验收：出现 `EGL_BAD_SURFACE` 时不再无限刷同一错误，进入可见恢复过程日志。

## 阶段 B：窗口强制重绑链路
- 增加 `WindowRebind` 消息并贯通 `Engine -> RenderThread -> Pipeline`。
- 验收：同指针 SurfaceChanged 也能触发有效重建。

## 阶段 C：退避、降级、观测
- 加退避和降级策略，补齐统计上报。
- 验收：连续异常时不会长期黑屏，至少能自动降级恢复画面。

## 7. 验收标准

- 场景 1：旋转/前后台切换后画面自动恢复，音视频持续。
- 场景 2：主动触发 surface destroy/create，恢复时间可控（目标 < 2s）。
- 场景 3：模拟 context lost（或驱动重建）后可自动完整恢复。
- 场景 4：恢复失败时可自动降级到 CPU 渲染而非一直黑屏。
- 场景 5：日志中恢复状态切换清晰，且无错误洪泛。

## 8. 风险与回滚

### 风险
- 状态机改造涉及多线程边界，若锁边界不一致可能引入竞态。
- 强制重绑若顺序不当可能触发资源双释放。

### 回滚策略
- 通过编译开关保留旧恢复路径（例如 `ENABLE_GLES_FULL_RECOVERY`）。
- 出现不稳定时可快速回落到原渲染路径或直接强制 CPU 模式。

## 9. 需要确认的实现选择

- 是否默认开启“自动降级到 CPU”。
- 降级后是否自动尝试回切 GLES（建议二期实现）。
- `WindowRebind` 采用独立消息还是扩展已有 `WindowCreated` 负载。

## 10. 参考（官方语义）
- EGL 规范（错误码与恢复语义）：`EGL_BAD_SURFACE`、`EGL_CONTEXT_LOST`
  - https://registry.khronos.org/EGL/specs/eglspec.1.5.pdf
- OpenHarmony NativeWindow / XComponent 生命周期
  - https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/graphics/native-window-guidelines.md?skip_mobile=true

