# HarmonyOS Libretro Emulator C++ 框架与链路分析（entry/src/main/cpp）

## 1. 范围与目标
- 分析范围：`entry/src/main/cpp`
- 分析目标：梳理当前 C++ 框架分层、线程与消息模型、核心运行链路，并评估当前架构优缺点。
- 说明：本报告基于代码静态阅读，不包含运行时 profiling 数据。

## 2. 框架分层（按职责）
1. 应用接入层（NAPI + XComponent）
- 目录：`app/napi`、`app/framework`
- 作用：暴露 ArkTS 调用接口，接入 XComponent 生命周期与输入事件。
- 关键文件：`module_init.cpp`、`libretro_engine_napi.cpp`、`plugin_manager.cpp`

2. 引擎编排层（Engine）
- 目录：`core/engine`
- 作用：状态机、消息调度、GameLoop 主循环、渲染线程协同、事件回传。
- 关键文件：`libretro_engine.cpp`、`render_thread.cpp`、`engine_messages.h`、`message_queue.h`

3. Libretro 协议适配层
- 目录：`core/libretro`
- 作用：核心动态加载、环境命令分发、VFS 与 libretro 回调协议适配。
- 关键文件：`core_loader.cpp`、`env_dispatcher.cpp`

4. 平台能力层（HarmonyOS）
- 目录：`platform/graphics`、`platform/audio`、`platform/sync`
- 作用：视频渲染（CPU/GLES/HW/Vulkan）、音频播放、NativeVSync 驱动。
- 关键文件：`video_pipeline.cpp`、`audio_bridge.cpp`、`audio_player.cpp`、`native_vsync_driver.cpp`

5. 资源与安全层
- 目录：`platform/resource`、`common`
- 作用：ROM/rawfile 加载、CUE 依赖展开、临时文件管理、路径安全校验。
- 关键文件：`rawfile_rom_processor.cpp`、`rom_loader.cpp`、`platform_resource_manager.cpp`、`file_security.cpp`

## 3. 线程模型与并发边界
1. UI/NAPI 线程
- 发起启动/加载/控制调用。
- 不直接执行 EGL/GL 操作。

2. XComponent 回调线程
- 处理 Surface Created/Changed/Destroyed。
- 处理 Touch/Mouse/Key 事件并转发到引擎输入接口。

3. Engine 线程（GameLoop）
- 消费 EngineMessage。
- 运行 `retro_run`。
- 处理状态切换和核心级逻辑。

4. RenderThread
- 独立消费视频帧队列。
- 管理窗口会话状态、渲染提交、VSync 驱动节拍。

5. 音频回调线程（OHAudio）
- `AudioPlayer::OnWriteDataCallback` 从 RingBuffer 读 PCM，提交系统音频。

6. NAPI async work 线程
- 执行 `SwitchGameAsync`、`StopEngineAsync`、`WaitForStateAsync` 等异步流程。

## 4. 关键并发结构
1. 控制消息队列
- `ThreadSafeQueue<EngineMessage>` 负责跨线程控制消息。
- 支持 `PushCoalesce`（窗口 resize 合并）与 `Close/Reopen`（停机重启）。

2. 视频帧队列
- `BoundedLatestFrameQueue(cap=2)`：保留最新帧，主动丢弃陈旧帧，降低渲染延迟累积。

3. 输入快照
- `InputSnapshot` 原子结构：按钮位图、模拟轴、指针、传感器。
- libretro `input_state` 直接读取，避免高频输入排队。

4. Surface 代际（generation/session）
- `surface_generation_` + `WindowSession.generation`。
- 旧代帧在 RenderThread 丢弃，降低 Surface 切换抖动导致的越界渲染风险。

## 5. 主链路流程

### 5.1 模块初始化链路
1. `module_init.cpp` 注册 NAPI 模块。
2. 注册 `PluginManager::Export`（XComponent 接口）。
3. 注册 `RegisterLibretroRefactoredNapi`（引擎控制接口）。

### 5.2 启动链路（Start）
1. ArkTS 调 `refactoredStartEngine`。
2. `LibretroEngine::Start()` 执行统一 `Reset()`，切到 `STARTING`。
3. 启动 `GameLoop` 线程。
4. 启动 RenderThread（统一渲染管线要求 RenderThread 始终启用）。

### 5.3 Surface 生命周期链路
1. XComponent `OnSurfaceCreated/Changed/Destroyed` 在 `plugin_manager.cpp` 触发。
2. 调 `SetNativeWindow` / `OnNativeWindowResized` / `ClearNativeWindowIfMatch`。
3. 引擎推送 `WindowCreated/WindowResized/WindowDestroyed` 消息（附 generation）。
4. RenderThread 更新 `WindowSession`，并在必要时重建硬件渲染上下文。

### 5.4 Core 加载链路
1. ArkTS 调 `refactoredLoadCore`。
2. 引擎线程处理 `MessageType::LoadCore`。
3. `CoreLoader::LoadCore` 走 `dlopen+dlsym`，校验 libretro 必需符号。
4. `SetupCallbacks` 绑定 environment/video/audio/input 回调。
5. 调 `retro_init`，读取 system_info，检测 core quirks，状态切为 `CORE_LOADED`。

### 5.5 ROM 加载链路
1. ArkTS 调 `refactoredLoadRom` 或 `refactoredSwitchGameAsync`。
2. 如为 rawfile（`roms/...`），先经 `RawfileRomProcessor` 读取与落盘，CUE 场景补齐依赖文件。
3. 引擎线程处理 `MessageType::LoadRom`，做路径安全校验。
4. 根据 core 特性走 fullpath 或内存数据加载。
5. `retro_load_game` 成功后读取 AVInfo，更新视频参数，`AudioBridge::Reset(sample_rate)`，状态切到 `RUNNING`。

### 5.6 每帧执行链路（Engine 主循环）
1. `ProcessFrame` 进入 `retro_run` 上下文。
2. 执行 frame-time/audio-status 回调。
3. 调 `retro_run()`。
4. `OnVideoRefresh` 将帧封包入 RenderThread 队列。
5. `OnAudioSampleBatch` 推送音频到 `AudioBridge`。
6. 处理变量更新事件（`options_update`）。

### 5.7 视频渲染链路
1. RenderThread `HandleTick` 弹出最新 `VideoFramePacket`。
2. 校验窗口是否可渲染 + generation 是否匹配。
3. 交由 `VideoPipeline::Render` 按模式执行：
- CPU 路径：`RequestBuffer -> OH_NativeBuffer_FromNativeWindowBuffer -> Map/Unmap -> Flush`
- GLES 路径：EGL + 纹理上传 + Swap，含 surface/context 丢失恢复
- HW 路径：EGL FBO 或 Vulkan swapchain 呈现
4. 记录 RenderMetrics 并更新统计。

### 5.8 音频链路
1. 核心音频回调进入 `AudioBridge::ProcessAudio`。
2. 可选重采样到 48k，带轻量 DRC（动态比率微调）。
3. 写入 `RingBuffer`（阻塞或非阻塞模式）。
4. OHAudio 回调读 RingBuffer，不足部分补静音，最终返回 `VALID`。

### 5.9 输入链路
1. Touch/Mouse/Key 在 `PluginManager` 归一化与端口解析。
2. 写入 `InputManager -> InputSnapshot`。
3. 核心 `retro_input_state` 由 `InputManager::OnInputState` 直接读取快照。

### 5.10 状态/存档/磁盘链路
1. SaveState/SRAM/Cheat/Controller 等调用通过 `ExecuteSyncTask` 进入 Engine 线程执行。
2. Disk control 回调由 `DiskController` 适配 legacy/ext 接口。

## 6. 当前架构优点
1. 职责分层清晰
- NAPI、Engine、Libretro、Platform、Resource 分层明确，边界可维护性较好。

2. 线程模型合理
- GL/EGL 渲染统一放在 RenderThread，避免 UI 线程误触图形上下文。

3. 窗口生命周期健壮
- generation/session 机制有效抑制旧窗口/旧帧误渲染。

4. 视频降级与恢复机制完善
- GLES/HW/Vulkan 都有失败计数、重建和降级逻辑，稳定性优先。

5. 输入路径低延迟
- 原子快照直读，避免高频输入走消息队列造成堆积。

6. 音频容错较强
- RingBuffer + 回调线程解耦，欠载补静音，支持同步模式切换。

7. 安全与资源处理到位
- 核心/ROM 路径白名单，rawfile 与 CUE 依赖处理完整。

8. 可观测性较好
- 统计项与事件回传丰富，便于线上问题定位。

## 7. 当前架构缺点与风险
1. Engine 单例耦合较重
- 全局单例 + 静态回调让多实例与测试隔离能力受限。

2. 状态机复杂度高
- 状态、phase、消息、异步 token 并存，学习与排障门槛高。

3. MessageQueue 无优先级
- Stop/关键控制和普通消息共用队列，极端压力下响应时延可能受影响。

4. RenderThread 控制队列为手工 deque
- 当前可用，但缺少统一抽象和背压指标，后续扩展复杂。

5. 音频回调策略偏保守
- 回调几乎总返回 `VALID`，会以静音掩盖问题，利于稳定但不利于暴露根因。

6. 资源路径与临时文件策略分散
- rawfile、temp_rom、VFS 与安全策略分布在多个模块，策略一致性依赖人工约束。

7. 错误恢复路径较多
- Stop timeout、switch token、渲染降级重试等分支多，维护时容易引入状态回归。

8. 文档与代码同步风险
- 链路复杂且演进快，若无持续文档更新机制，知识易失真。

## 8. 建议的演进方向（按优先级）
1. 短期（稳定性）
- 给 EngineMessage 增加“关键消息优先级”或独立控制通道（Stop/Window 生命周期优先）。
- 为 RenderThread 控制队列增加深度指标与丢弃统计，纳入 `GetStats`。

2. 中期（可维护性）
- 收敛状态机入口，统一 Transition 审计日志（状态 + phase + 当前队列深度）。
- 将 rawfile/temp/VFS 策略整合到单一 ResourcePolicy 组件。

3. 长期（架构能力）
- 逐步降低单例耦合（Engine 实例化上下文），为多实例/并行测试做准备。
- 建立“链路回归清单”（不要求自动化脚本）用于人工验证关键状态迁移。

## 9. 总结
当前架构整体偏“稳定性优先”的工程化实现：线程边界清晰、渲染与音频容错充分、链路覆盖完整。主要挑战在于系统复杂度与状态分支增长带来的维护成本。后续优化重点应放在：控制路径优先级、状态机收敛、资源策略统一、单例解耦。

