# 最近问题复盘（2026-02）

本文梳理近期主干分支集中修复的问题，重点回答三件事：
- 这些问题大概怎么修复的
- 为什么会产生
- 以后怎么避免

## 1. Vulkan 同步与队列使用问题

### 问题现象
- 渲染路径存在偶发卡死、帧提交异常、呈现不稳定。
- `presenter` 中存在解锁后继续使用 `FrameState*` 的风险。
- `wait_sync_index` 的等待语义不严格，可能提前返回，破坏与 core 的同步契约。
- 图形队列与呈现队列在部分设备上不是同一队列，导致 present 行为不可靠。

### 修复方式（大概）
- 在 `Present()` 中保持 `FrameState` 生命周期受锁保护，避免解锁后悬空访问。
- `wait_sync_index` 改为严格等待 frame 彻底 retire（使用完整 fence 等待语义）。
- `queue_present_khr` 改为使用 `present_queue`，并补齐 family index 初始化和日志。
- 初始化和销毁路径补齐 `present_queue` 相关状态复位。

### 根因分析
- 对并发访问边界定义不清晰，`state` 对象所有权与锁粒度不一致。
- 对 Vulkan 同步契约理解不完整，把“超时返回”当作可接受分支。
- 默认假设图形队列可用于 present，缺少“多队列设备”兼容意识。

### 后续避免措施
- 代码评审时强制检查：`unlock` 后是否还使用锁内对象指针/引用。
- 明确约定：和 libretro core 的同步接口必须满足“语义正确优先于超时兜底”。
- Vulkan 初始化阶段必须记录并验证 `gfx queue` 与 `present queue`，禁止隐式假设。

## 2. 生命周期 stop 超时后无法恢复

### 问题现象
- `Stop` 超时后引擎可能进入不可恢复状态，后续 `Start` 被阻塞。
- 切换流程中出现“停不干净 -> 不能再启动”的连锁失败。

### 修复方式（大概）
- 在 `Stop` 超时时记录结构化错误信息（phase、duration 等）。
- 在 `Start` 前增加 stop-timeout 阻塞检查，并返回可诊断错误。
- 在 ArkTS 协调层增加 `refactoredResetEngine()` 恢复路径：超时后触发 reset，并等待回到 `INIT`。

### 根因分析
- 生命周期状态机缺少“失败后恢复通道”，只覆盖理想路径。
- 上层编排默认 `stop` 必定成功，未设计超时后的补救动作。

### 后续避免措施
- 状态机设计时必须包含 `timeout/error -> recovery` 分支。
- 所有跨线程生命周期接口统一输出错误码与上下文，便于上层决策。
- 切换流程统一走“停机完成判定 + 失败恢复”模板，不允许散落实现。

## 3. 全局实例发布与回调并发竞态

### 问题现象
- 回调线程与析构/重建并发时，存在读取到过期实例指针的风险。
- 输入、引擎、磁盘控制等模块在多线程下可能出现状态竞争。

### 修复方式（大概）
- `LibretroEngine`、`InputManager` 的静态实例从裸指针改为原子发布/快照读取。
- `DiskController` 的回调注册与状态访问统一加锁。
- 插件层指针状态从全局单例布尔值改为按 `xcomponent id` 隔离，并加互斥保护。

### 根因分析
- 历史实现偏单实例假设，后续扩展到多线程/多组件后未同步升级并发模型。
- 回调是 C 风格入口，天然弱类型、弱生命周期约束，容易跨线程踩边界。

### 后续避免措施
- 建立“回调桥接并发模板”：原子发布 + 快照读取 + 明确销毁时序。
- 禁止共享可变状态无锁跨线程读写；共享状态必须定义唯一锁边界。
- 多 XComponent 场景一律按 `id` 维度隔离输入/指针/焦点状态。

## 4. 输入路由错误（触控固定到 port0）

### 问题现象
- 触控事件被固定路由到 `port0`，多端口/多设备映射失效。

### 修复方式（大概）
- 在插件输入路径中按设备/上下文动态解析 port，而不是硬编码 `port0`。

### 根因分析
- 早期快速打通阶段使用了硬编码，后续未及时抽象成通用映射逻辑。

### 后续避免措施
- 禁止在输入路由链路硬编码 port/device id。
- 新增评审项：输入事件处理必须展示“来源 -> 映射 -> 目标端口”链路。

## 5. 资源访问与加载安全性问题

### 问题现象
- 资源管理存在陈旧 manager 使用风险。
- `rawfile` 读取在并发场景下缺少统一锁保护。
- 核心加载路径中 `ELF NEEDED` 解析边界防护不足，路径容量边界不一致。

### 修复方式（大概）
- 资源管理器访问路径补充有效性检查并统一加锁。
- `rom/rawfile` 访问过程串行化关键区，避免并发竞态。
- 加固 `ELF NEEDED` 解析边界校验；对齐 NAPI 与引擎消息的路径容量约束。

### 根因分析
- 历史代码在“可用性优先”阶段留下边界处理缺口。
- 模块间约束（例如路径长度）没有形成统一常量与统一校验入口。

### 后续避免措施
- 所有跨模块边界参数（路径长度、缓冲区大小）必须单一来源定义。
- 二进制解析代码默认按“不可信输入”处理，先校验边界再访问。
- 资源访问建立统一线程安全策略，禁止各处自定义锁语义。

## 6. 模拟器场景性能与诊断噪声问题

### 问题现象
- 默认 VSync 在模拟器上导致吞吐受限，掉帧后容易形成背压。
- 自动跳帧触发条件偏粗糙，诊断日志过密，影响问题定位与实时性。

### 修复方式（大概）
- 模拟器架构下默认 `swapInterval=0`，并支持 NAPI 动态设置。
- 跳帧策略从单一音频低水位扩展为“音频低水位 + 渲染背压”联合判定。
- 诊断日志改为突发+间隔采样，减少日志洪泛。

### 根因分析
- 默认策略偏向真实设备，未区分模拟器与设备运行特征。
- 诊断点初期为排查方便而高频输出，后续没有收敛节流策略。

### 后续避免措施
- 运行时策略按平台/架构分层配置（模拟器 vs 真机）。
- 性能诊断日志必须带采样节流规则，禁止持续高频打印。
- 关键性能策略（swap、skip、buffer）需要可配置并可观测。

## 7. EGL_BAD_SURFACE 持续刷错导致“有声音没画面”

### 问题现象
- 日志持续出现 `eglSwapBuffers failed: 0x300d (EGL_BAD_SURFACE)`。
- 音频链路继续正常生产/播放，但视频长期黑屏或只偶发恢复。
- 失败后没有进入有效恢复路径，形成“错误风暴 + 无画面”。

### 修复方式（大概）
- 在 `GLESRenderer` 中新增 swap 失败分类：
  - `RECOVERABLE_SURFACE`（如 `EGL_BAD_SURFACE/BAD_NATIVE_WINDOW/BAD_MATCH`）
  - `CONTEXT_LOST`
  - `FATAL`
- 在 `VideoPipeline` 引入 GLES 恢复状态机：
  - `UNINITIALIZED/READY/SURFACE_LOST/CONTEXT_LOST/WAIT_WINDOW/FATAL`
  - `SURFACE_LOST -> RecreateSurface`
  - 连续失败升级为 `Deinit + Init` 全量重建
  - 退避重试（100/300/1000ms）
  - 连续全量失败后自动降级 `SOFTWARE_SCALING`
- 对 swap 失败日志做突发+间隔限流，避免刷屏。

### 根因分析
- 旧路径把 swap 失败视为“临时异常”，但缺少明确恢复状态机。
- 没有区分“可恢复 surface 失效”和“上下文丢失”。
- 渲染错误处理与窗口生命周期变化之间缺少闭环。

### 后续避免措施
- 图形链路必须有显式故障状态机，不允许只靠“失败后继续尝试”。
- EGL 错误码处理必须分类分级，禁止统一兜底。
- 恢复策略要有退避与上限，避免错误风暴拖垮系统。

## 8. SurfaceChanged 但窗口句柄不变，导致渲染未重绑

### 问题现象
- `OnSurfaceChanged` 触发时，`OHNativeWindow*` 指针可能保持不变。
- 旧逻辑仅按指针变化判定是否重建，导致 render/surface 语义变化被忽略。
- 结果是资源仍绑定旧 surface，上层看起来“引擎还在跑、但不出画面”。

### 修复方式（大概）
- 引擎消息新增 `WindowRebind`，并给 `Window` 消息增加 `force_rebind` 标记。
- 插件层 `OnSurfaceChanged` 统一调用 `SetNativeWindow(..., true)` 强制重绑。
- `RenderThread::SetWindow` 支持 `forceRebind`，即使同指针也执行销毁+重建流程。

### 根因分析
- 将“窗口对象身份”等同于“surface 可用性语义”，这是不成立的。
- 生命周期设计偏向对象地址比较，缺少语义事件（rebind）建模。

### 后续避免措施
- 窗口/Surface 处理禁止只依赖指针相等判断。
- 生命周期消息中必须区分：`created/destroyed/resized/rebind`。
- 评审时明确检查 “same pointer + changed surface” 分支。

## 9. 渲染阻塞主循环与可观测缺口

### 问题现象
- 视频渲染与 `retro_run` 主循环耦合，swap 阻塞会直接反压核心线程。
- 压测场景下音频继续跑，但视频链路卡顿、恢复不稳定。
- 原统计对队列丢帧、vsync 请求失败、渲染线程空转不可见。

### 修复方式（大概）
- 引入 `RenderThread` + `BoundedLatestFrameQueue`（容量 2，保最新帧）。
- `OnVideoRefresh` 改为投递帧包（软件像素或 hw-swap 信号）到渲染线程。
- 新增 `NativeVSyncDriver`；请求失败自动降级 timer tick 回退。
- `GetStats` 合并 RenderThread 指标，并从 NAPI 导出：
  - `queue*`、`renderThread*`、`vsync*` 等字段。

### 根因分析
- 早期实现以“简单直连”优先，未对 swap 阻塞进行线程隔离。
- 诊断模型未覆盖新渲染路径，导致问题出现后难以定位。

### 后续避免措施
- Core 线程与呈现线程必须解耦，避免单线程承载所有耗时路径。
- 队列策略优先“低延迟+可丢旧帧”，而非无限堆积。
- 新架构上线前必须同步补齐指标与 NAPI 可观测面。

## 10. 回归编译错误：日志计数器类型不匹配

### 问题现象
- `BuildNativeWithNinja` 在 `video_pipeline.cpp` 失败：
  - `no matching function for call to 'ShouldLog'`
  - `render_log_count_` 是 `uint32_t`，而 `ShouldLog` 仅接收 `size_t&`

### 修复方式（大概）
- 为 `ShouldLog` 增加 `uint32_t` 重载，保持与现有计数器字段类型一致。

### 根因分析
- 辅助函数签名过窄，新增调用点未统一计数器类型。

### 后续避免措施
- 公共 helper 优先支持项目内主流计数类型（`uint32_t/size_t`）。
- 涉及基础类型改动时，必须跑一次完整 native 编译链路（含 x86_64 变体）。

## 11. 软件路径仍闪退：窗口生命周期竞态与重配抖动叠加

### 问题现象
- 软件渲染模式下仍出现 `SIGSEGV(SEGV_MAPERR)`，崩溃线程在渲染线程（`ingtoxcomponent`）。
- 崩溃栈顶落在 `libsurface.z.so::ProducerSurface::FlushBuffer(...)`。
- 崩溃前可见 `Slow RenderCPU` 与高频 UI 交互（菜单/前后台切换）叠加。

### 修复方式（大概）
- 修复窗口快照生命周期竞态：
  - `HandleMessage(WindowCreated/WindowRebind)` 在 `windowMutex_` 锁内先对 `window_` 做一次 `NativeObjectReference`，
    再交给 `RenderThread::SetWindow`，调用后再 `Unreference` 临时引用，避免“解锁后对象被并发释放”。
- 窗口变更时丢弃陈旧帧：
  - `RenderThread::HandleSetWindow` 在窗口切换/重绑时清空 `frameQueue_`，避免旧 surface 语义帧继续提交。
- 收敛失败后的重配风暴：
  - `RenderCPU` 在 `RequestBuffer/Fence/Map/Unmap/Flush` 等失败分支不再每次都强制 `geometry_changed_`，
    降低每帧 `HandleOpt` 重试导致的 surface producer 抖动。

### 根因分析
- 代码曾默认“锁外快照指针仍有效”，但窗口对象生命周期由其他线程推进，存在释放竞态窗口。
- 窗口语义变更时，队列里陈旧帧未被及时淘汰，增加了失效 surface 上提交的概率。
- 失败即强制重配的策略在模拟器慢路径上会放大抖动，形成“失败 -> 重配 -> 再失败”的循环。

### 后续避免措施
- 任何跨线程传递 `OHNativeWindow*` 的路径，必须先在锁内完成引用计数保活。
- `created/rebind/destroyed` 事件发生时，明确处理“队列内陈旧帧”策略（至少丢弃一次）。
- 失败重试策略必须有节流/退避，禁止每帧强制 reconfigure。

## 通用预防清单（建议纳入评审）

- 并发与生命周期
  - 所有全局实例发布必须原子化；回调读取使用快照。
  - 共享可变状态必须有统一 mutex 边界，不允许“部分字段无锁”。
  - 状态机必须包含失败恢复路径，尤其是 `timeout` 场景。
- 图形链路
  - Vulkan 必须区分并验证 `graphics/present queue`。
  - 同步接口遵守契约语义，禁止用“超时即继续”掩盖未完成同步。
- 输入链路
  - 禁止硬编码端口与设备映射；必须基于上下文动态决策。
  - 多组件场景状态按 `xcomponent id` 隔离。
- 资源与安全
  - 二进制解析先边界校验后访问。
  - 跨模块边界常量（长度/容量）统一定义、统一校验。
- 可观测性与性能
  - 日志默认采样输出，关键路径避免洪泛。
  - 性能策略可配置、可回读（便于线上诊断）。

## 参考提交（按时间近到远）
- `7b88bbc` perf: 模拟器默认 swapInterval=0 并优化掉帧诊断路径
- `c9ccd2e` fix(vulkan): enforce wait sync semantics and use present queue
- `829a9a0` fix(vulkan): avoid frame state pointer use after unlock in presenter
- `ae55a69` fix(lifecycle): recover from stop timeout via reset path
- `3c13e70` fix(plugin): isolate pointer state by xcomponent id
- `527ca54` fix(engine): publish callback bridge instance via atomic snapshot
- `195454c` fix(input): make callback bridge instance publication atomic
- `638f73a` fix(disk): 修复 DiskController 回调与状态并发竞争
- `0a6e762` fix(input): 修复 touch 事件固定 port0 路由
- `45ab8d3` fix(resource): avoid stale native manager usage and lock rawfile access
- `0159789` fix(core-loader): 加固 ELF NEEDED 解析边界校验
- `63964b1` fix(engine): align load message path capacity with NAPI
- （当前工作区，待提交）fix(video): add EGL failure state-machine recovery and auto degrade path
- （当前工作区，待提交）fix(surface): add WindowRebind/force_rebind to handle same-pointer surface changes
- （当前工作区，待提交）refactor(render): decouple present from engine loop via RenderThread + bounded latest queue
- （当前工作区，待提交）feat(stats): export render-thread queue/vsync metrics to NAPI GetStats
- （当前工作区，待提交）fix(build): add `ShouldLog(uint32_t&)` overload for native compile
- （当前工作区，待提交）fix(window-lifecycle): keep window snapshot alive across render-thread handoff
- （当前工作区，待提交）fix(render): drop stale queued frames on window lifecycle mutation
- （当前工作区，待提交）fix(video): avoid per-frame geometry reconfigure storm on transient CPU-path failures
