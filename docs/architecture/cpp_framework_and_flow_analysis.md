# HarmonyOS Libretro Emulator C++ 框架与链路深度分析（entry/src/main/cpp）

## 1. 范围与结论
- 分析范围：`entry/src/main/cpp`（排除 `deprecated/legacy/`）。
- 方法：静态代码阅读与跨模块链路追踪（不含运行时性能剖析）。
- 结论：当前架构属于“控制面与数据面分离、稳定性优先”的实现，核心能力完整，重点复杂度集中在状态机分支与跨线程协同。

## 2. 对比旧版文档的更新点
1. 模块初始化链路补全
- 新增明确记录：`module_init.cpp` 实际注册三部分能力：`PluginManager::Export`、`RegisterCoreLoaderNapi`、`RegisterLibretroRefactoredNapi`。

2. 启动与主循环行为更正
- 明确 `LibretroEngine::Start()` 启动 GameLoop 与 RenderThread，并在 RUNNING 态先排空控制消息再执行帧逻辑。

3. 切游链路细化
- 补充 `SwitchGameAsync` 的 800ms 去重窗口、token 抢占（仅最新请求生效）及失败兜底（Stop + Reset）。

4. 渲染链路关键保护补全
- 增补 `surfaceGeneration` 代际校验、`BoundedLatestFrameQueue` 仅保留最新帧、VSync 失败降级 timer tick。

5. 音频链路补全
- 增补 `AudioBridge` 48k 输出重采样、动态微调（DRC skew）、`RingBuffer` 与 OHAudio 回调协同状态机。

6. 资源链路补全
- 增补 `RawfileRomProcessor` 对 CUE 依赖文件复制与临时目录处理细节。

### 2.1 事实准则（本次校准）
1. `源码事实`
- 仅记录可在当前仓库直接定位的函数、状态、调用关系与常量。

2. `工程推断`
- 涉及“优缺点/风险/建议”归类为工程推断，不当作代码事实。

3. `证据要求`
- 每条关键链路至少有一个源码锚点（文件 + 行号区间）可回查。

## 3. 分层架构（职责视图）
1. 接入层（NAPI + XComponent）
- 目录：`app/napi`、`app/framework`
- 责任：ArkTS API 出口、XComponent Surface/Input 回调桥接。
- 关键文件：`module_init.cpp`、`libretro_engine_napi.cpp`、`plugin_manager.cpp`

2. 引擎编排层（Engine）
- 目录：`core/engine`
- 责任：状态机、消息队列、GameLoop、RenderThread 协同、同步任务执行。
- 关键文件：`libretro_engine.cpp`、`engine_messages.h`、`message_queue.h`、`render_thread.cpp`、`video_pipeline.cpp`

3. Libretro 适配层
- 目录：`core/libretro`
- 责任：core 动态加载、libretro 回调绑定、environment 命令分发、VFS 适配。
- 关键文件：`core_loader.cpp`、`env_dispatcher.cpp`、`core_options_registry.cpp`、`disk_controller.cpp`

4. 平台能力层（HarmonyOS）
- 目录：`platform/graphics`、`platform/audio`、`platform/sync`
- 责任：CPU/GLES/Vulkan 渲染、音频播放、VSync 驱动。
- 关键文件：`audio_bridge.cpp`、`audio_player.cpp`、`ring_buffer.cpp`、`native_vsync_driver.cpp`

5. 资源与安全层
- 目录：`platform/resource`、`common`
- 责任：ROM/rawfile/URI 加载、临时文件、路径安全与资源抽象。
- 关键文件：`rawfile_rom_processor.cpp`、`rom_loader.cpp`、`platform_resource_manager.cpp`、`file_security.cpp`

## 4. 线程模型与锁边界
1. ArkTS/UI 线程
- 发起控制调用（Start/LoadCore/LoadRom/Stop/输入设置等）。

2. XComponent 回调线程
- 处理 Surface 生命周期与 Touch/Mouse/Key 回调。
- 共享输入/焦点状态通过 `std::mutex + std::lock_guard` 保护。

3. Engine 线程（GameLoop）
- 核心状态机线程，执行 `retro_run`、处理 `EngineMessage`。

4. RenderThread
- 视频数据面线程，消费帧包与控制消息，驱动 `VideoPipeline`。

5. OHAudio 回调线程
- 从 `RingBuffer` 拉取 PCM，欠载补静音并持续输出。

6. NAPI 异步 worker 线程
- 承载 `SwitchGameAsync`、`WaitForStateAsync`、`StopAsync` 等异步流程。

## 5. 关键数据结构与并发机制
1. 控制消息队列
- `ThreadSafeQueue<EngineMessage>` 支持 `PushCoalesce`（如 resize 合并）、`Close/Reopen`。

2. 帧队列（最新帧策略）
- `BoundedLatestFrameQueue` 丢弃陈旧帧，仅保留最新，降低延迟累积。

3. Surface 代际保护
- `surface_generation_` 与 `WindowSession.generation` 对齐，不匹配帧直接丢弃。

4. 输入快照
- `InputSnapshot` 以原子字段保存按钮/轴/指针/传感器，`input_state` 直接读取。

5. 音频环形缓冲
- `RingBuffer` 用于 core 音频生产与 OHAudio 消费解耦，记录 underrun/overrun 统计。

## 6. 状态机（系统骨架）
### 6.1 引擎状态机
`INIT -> STARTING -> LOADING -> CORE_LOADED -> GAME_LOADED -> RUNNING -> PAUSED -> STOPPING -> STOPPED/ERROR`

### 6.2 视频状态机（GLES/HW 子路径）
- `UNINITIALIZED -> READY -> SURFACE_LOST/CONTEXT_LOST -> FATAL`
- 支持失败计数、重建与软件路径降级恢复。

### 6.3 音频状态机
- `INIT -> BUFFERING -> RUNNING -> PAUSED/RECOVERING`
- 由 RingBuffer 水位、中断事件、回调表现共同驱动。

## 7. 端到端链路流程（按时序）
### 7.1 模块初始化链路
1. `module_init.cpp` 注册 NAPI 模块。
2. 导出 `PluginManager::Export`（XComponent 桥接）。
3. 导出 `RegisterCoreLoaderNapi`（core loader 能力）。
4. 导出 `RegisterLibretroRefactoredNapi`（引擎控制接口）。

### 7.2 启动链路
1. ArkTS 调 `refactoredStartEngine`。
2. `LibretroEngine::Start()` 做 `Reset()` 与状态迁移。
3. 启动 GameLoop 线程。
4. 启动 RenderThread，并尝试恢复窗口快照。

### 7.3 Surface 生命周期链路
1. `PluginManager` 接收 `SurfaceCreated/Changed/Destroyed`。
2. 调用 `SetNativeWindow`、`OnNativeWindowResized`、`ClearNativeWindowIfMatch`。
3. Engine 投递 `WindowCreated/Resized/Destroyed` 控制消息。
4. RenderThread 更新 `WindowSession`，并在必要时重建上下文。

### 7.4 Core 加载链路
1. ArkTS 调 `refactoredLoadCore`。
2. Engine 线程处理 `LoadCore` 消息。
3. `CoreLoader::LoadCore` 进行路径校验、`dlopen + dlsym`、API 版本核验。
4. 绑定 environment/video/audio/input 回调。
5. 调 `retro_init` 与 `retro_get_system_info`，状态迁移到 `CORE_LOADED`。

### 7.5 ROM 加载链路
1. ArkTS 调 `refactoredLoadRom` 或 `refactoredSwitchGameAsync`。
2. rawfile 场景走 `RawfileRomProcessor`，`.cue` 同步复制依赖数据文件。
3. Engine 线程处理 `LoadRom`，执行路径安全校验与 fullpath/no-game 分支。
4. `retro_load_game` 成功后更新 AVInfo，`AudioBridge::Reset(sample_rate)`。
5. 状态切换为 `RUNNING`。

### 7.6 每帧运行链路（Engine 数据生产）
1. RUNNING 态：先处理待决控制消息，再进入 `ProcessFrame()`。
2. 调 `retro_run()`。
3. `retro_video_refresh -> OnVideoRefresh` 产出 `VideoFramePacket`。
4. `retro_audio_sample_batch -> OnAudioSampleBatch` 推送音频。
5. 按需处理 core options 更新、事件桥回传。

### 7.7 视频渲染链路（RenderThread 数据消费）
1. `RenderThread::HandleTick` 拉取最新帧包。
2. 校验窗口状态与 `surfaceGeneration`。
3. `VideoPipeline::Render` 按后端执行：
- Software：`RequestBuffer -> OH_NativeBuffer_FromNativeWindowBuffer -> Map/Unmap -> Flush`
- GLES：EGL 上下文 + 纹理提交 + SwapBuffers
- HW/Vulkan：presenter/swapchain 路径
4. VSync 驱动失败时降级 timer tick。

### 7.8 音频链路
1. `AudioBridge::ProcessAudio` 接收 core 音频块。
2. 重采样到 48k，动态比率微调，写入 `RingBuffer`。
3. OHAudio `OnWriteDataCallback` 消费数据，不足补静音；无效参数或停止态会返回 `INVALID`。
4. 依据缓冲与中断事件在 BUFFERING/RUNNING/RECOVERING 间切换。

### 7.9 输入链路
1. ArkTS/NAPI 或 XComponent 事件进入 `InputManager`。
2. 更新 `InputSnapshot` 与端口映射（`InputPortRouter`）。
3. core 通过 `input_poll/input_state` 拉取当前快照。

### 7.10 切游链路（SwitchGameAsync）
1. NAPI 层执行请求去重（800ms）。
2. token 抢占：仅最新请求可继续。
3. 顺序执行：`Stop -> Start -> SetFilesDir -> LoadCore -> Wait(CORE_LOADED) -> LoadGame -> Wait(RUNNING)`。
4. 失败时执行 `Stop + Reset`，避免引擎停留在半初始化态。

### 7.11 停机链路
1. `Stop()` 投递 Stop 消息并 `Close` 队列。
2. 等待 GameLoop 退出（带超时保护）。
3. 清理渲染、音频、core 句柄、状态统计并进入 `STOPPED`。

### 7.12 关键证据索引（可回查）
1. 模块注册三入口
- `entry/src/main/cpp/app/napi/module_init.cpp:42-48,57-58,78`

2. Start/Stop 与消息队列关闭重开
- `entry/src/main/cpp/core/engine/libretro_engine.cpp:368-379,435-443,515-517`

3. GameLoop 运行态先清空消息再跑帧
- `entry/src/main/cpp/core/engine/libretro_engine.cpp:1178-1198`

4. 视频生产链的 Surface 有效态检查与 frame packet 代际标记
- `entry/src/main/cpp/core/engine/libretro_engine.cpp:2010-2039,2042-2047,2080`

5. RenderThread 代际丢帧与 VSync 失败降级
- `entry/src/main/cpp/core/engine/render_thread.cpp:491-514,619-627`

6. SwitchGameAsync 去重窗口、token 抢占、失败恢复
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:44,52-80,563-576,610-621,646-707,804-814`

7. Rawfile + CUE 依赖展开
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:94-112`
- `entry/src/main/cpp/platform/resource/rawfile_rom_processor.cpp:108-123,133-163`

8. AudioBridge 重采样/DRC 与回调返回语义
- `entry/src/main/cpp/platform/audio/audio_bridge.h:89-94`
- `entry/src/main/cpp/platform/audio/audio_player.cpp:420-436,467,523-525,661`

9. Software 渲染必须走 NativeBuffer Map/Unmap
- `entry/src/main/cpp/core/engine/video_pipeline.cpp:1086-1089,1117,1304`

## 8. 架构优点
1. 分层边界清晰，模块职责聚焦。
2. 控制面（消息）与数据面（帧/音频）分离，实时性更好。
3. Surface 代际与最新帧策略降低窗口切换风险与时延。
4. 视频后端具备降级恢复机制，稳定性优先。
5. 输入快照直读路径延迟低，适配高频输入。
6. 音频生产消费解耦，欠载可控，回放稳定。

## 9. 主要风险与维护成本
1. 单例与静态回调耦合偏高，多实例/隔离测试成本高。
2. 状态机分支较多（状态、phase、异步 token、恢复路径），排障门槛高。
3. 控制消息无优先级，极端负载下关键消息时延可变。
4. 资源策略分散在多个组件，长期一致性依赖人工约束。
5. 音频“静音兜底”增强稳定性，但可能掩盖根因定位。

## 10. 建议（按优先级）
1. 短期
- 为关键控制（Stop/Window）增加优先通道或优先级策略。
- 将 RenderThread 控制队列深度、丢帧原因、代际丢弃计数纳入统一统计输出。

2. 中期
- 收敛状态迁移入口并统一 transition 审计日志（状态、phase、队列深度、token）。
- 合并 rawfile/temp/VFS 路径策略为单一 ResourcePolicy。

3. 长期
- 逐步降单例耦合，支持实例化上下文与并行验证场景。
- 维护固定“链路回归清单”（手工即可），覆盖启动/切游/停机/窗口切换。

## 11. 总结
当前 C++ 框架已具备完整的启动、加载、渲染、音频、输入、切游与停机闭环；链路完整度高，稳定性策略成熟。后续优化核心不在“补功能”，而在“降复杂度与提可维护性”，尤其是状态机收敛、控制消息优先级和资源策略统一。
