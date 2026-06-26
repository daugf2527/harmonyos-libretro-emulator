# Repository Guidelines

## 公共行为准则

<!-- SSOT 提示：本段是 C:/Users/newwo/.cc-switch/agent-policy/COMMON.md 的镜像副本。
     Codex Bot 不支持 @import，故此处内嵌；根 CLAUDE.md 则通过 @import 引用 COMMON.md。
     修改任一条准则时，必须同步 COMMON.md（唯一真值源），避免双轨漂移。 -->

- 默认中文沟通，必要时保留英文术语。
- 先读实物再判断；已知关键词优先用 `rg` / `rg --files`，探索调用链优先 `fast-context`。
- 改动保持最小、可验证；关键改动前说明影响范围。
- 不回滚用户已有改动；遇到不属于当前任务的改动，忽略或绕开。
- 宣称完成、修复、通过前，先运行新鲜的验证命令并阅读输出。
- 禁止破坏性 git 操作，除非用户明确授权；包括 `git reset --hard`、`git checkout --`、强制清理。
- 删除、递归移动、替换全局配置前，先确认路径、备份，并取得明确许可。
- 不打印 secret、token、provider key、raw memory、raw log body；报告只列位置和键名。
- 全局归全局，项目归项目；项目 MCP、项目 skill、业务规则不要塞进全局。
- Windows 远端流程：PowerShell 只做启动器，传 `.sh` 到远端后执行 bash；不要在 PowerShell 内联复杂远端命令。

> **WARNING: TOP PRIORITY**  
> Default to Chinese responses unless the user explicitly asks for another language.

## 强制规则（与仓库规范同级）
- 官方优先：不确定即查华为鸿蒙官方文档与 libretro 官方标准/`libretro.h`，禁止凭经验猜测 API 行为。
- 文档抓取：华为开发者文档为 SPA；需抓取渲染结果时，优先使用当前环境可用的联网/渲染抓取工具，不固定工具名。
- NativeBuffer：访问 NativeWindow buffer 像素内存必须走 `OH_NativeBuffer_FromNativeWindowBuffer` + `OH_NativeBuffer_Map/Unmap` 流程，禁止直接对 BufferHandle 使用 `mmap/munmap`。
- 线程同步：VSync 回调线程与主线程/ArkTS 共享状态必须用 `std::mutex + std::lock_guard` 保护，且同一状态统一锁边界。
- 日志规范：日志域使用 `0xD000-0xFFFF`；重定义前先 `#undef LOG_DOMAIN`；数值日志使用 `%{public}d/%{public}u/%{public}X`。
- ArkTS/NAPI：返回匿名对象必须定义显式 `interface` 类型，避免 `Object/any`；跨语言数值建议 `Number()` 显式转换。
- NativeWindow：避免强制设置 `SET_TIMEOUT=5`；如需设置，使用默认或 >= 1 帧周期。
- Native Core 安全：`dlopen` 仅允许应用打包目录中的 core；用户可写目录中的第三方 core 必须先具备签名/哈希校验与隔离策略，禁止直接加入白名单。
- 交互偏好：不写测试脚本；代理不主动编译/不运行，用户自己执行。代理可做静态检查，并必须明确“未编译/未真机”。
- 交互要求：若当前环境明确提供专用确认工具，则通过该工具询问；否则正常中文询问。
- 约定：旧架构（`deprecated/legacy/`）不参与后续检索与代码编辑（除非用户明确要求）。

## 高效工具使用与全局分析流程
- 先定义任务成功标准：明确要解决的症状、要产出的文件、可接受的验证命令；不清楚时先只读探索，不先改代码。
- 工具优先级：`codegraph`（C/C++ 调用图/影响面）→ `serena`（跨语言符号/引用）→ `ast-grep`（结构化/配对扫描）→ `rg` / `rg --files`（文本与文件定位）→ 批量读文件 → shell 兜底；`fast-context` 仅作语义补盲，不作为主证据；互不依赖的只读操作可并行。
- 证据链优先：判断必须落到源码、SDK、官方文档、运行日志或配置中的可引用证据；报告问题时给出文件路径和行号，不只写结论。
- API 更新流程：先确认当前 `targetSdkVersion`/`compatibleSdkVersion`、本地 SDK `.d.ts/.h` 声明和官方文档；改 native/ArkTS API 时同步 NAPI 注册、`index.d.ts`、本 AGENTS 导出清单和漂移检查脚本。
- 全局质量分析默认只读：排除 `deprecated/legacy/`、`entry/build/`、raw ROM/二进制资源；先跑已有 drift/lint/hygiene 脚本，再用定向搜索补盲区。
- 日志/告警处理先分类：应用自有日志优先，系统框架噪声只作为上下文；不要把平台诊断日志直接误判成业务 bug。
- 修复优先级：P0 崩溃/数据损坏/API 契约漂移；P1 生命周期、线程同步、资源泄漏；P2 性能和可维护性；P3 风格和文档。
- 验证口径：代理默认只做静态验证并报告命令输出；未执行 hvigor/真机时必须明确“未编译/未真机”。

## AI 接手任务标准作业（必须执行）
- 第一步先看上下文：读取 `build-profile.json5`、`entry/src/main/module.json5`、`docs/harmonyos-sdk-target.md`，确认当前 SDK 目标、设备类型、是否已切到 API26。
- 第二步先分层定位：先判断问题属于 ArkTS UI、NAPI 契约、引擎状态机、视频、音频、资源加载、文件安全中的哪一层；不要混着改。
- 第三步先找 3 处以上现有模式：实现前至少找 3 个相邻模块或同类函数作为参照，优先复用现有辅助类、日志风格、错误返回结构和锁边界。
- 第四步再改代码：优先做最小补丁，先修根因，再补接口和文档；不要顺手做无关重构。
- 第五步补齐契约面：凡是改到 NAPI export、ArkTS 调用签名、native 资源生命周期、线程同步边界，必须同步更新相邻契约文件或说明，不允许只改单点。
- 第六步做静态验证：至少运行本仓已有的定向检查或搜索确认修改面；若未编译、未真机、未模拟器验证，结论里必须明确写出。

## 按问题类型定位首查位置
- UI 页面状态 / 交互异常：先看 `entry/src/main/ets/pages/`、`entry/src/main/ets/components/`、`entry/src/main/ets/common/`。
- NAPI 导出 / ArkTS 调 native 签名不一致：先看 `entry/src/main/cpp/app/napi/`、`entry/src/main/cpp/types/libentry/index.d.ts`、`entry/src/main/cpp/app/napi/module_init.cpp`。
- 生命周期 / 状态机 / 卡死 / 切换游戏问题：先看 `entry/src/main/cpp/core/engine/libretro_engine.cpp`、`core_state_manager.cpp`、`event_bridge.cpp`。
- 画面不出 / 花屏 / 分辨率 / XComponent / NativeWindow：先看 `entry/src/main/cpp/core/engine/video_pipeline.*`、`platform/graphics/`、`core/engine/window_*`。
- 音频延迟 / 爆音 / 静音 / underrun：先看 `entry/src/main/cpp/platform/audio/`，重点是 `audio_bridge.cpp`、`audio_player.cpp`、`ring_buffer.*`。
- ROM / rawfile / core 加载 / 文件权限：先看 `entry/src/main/cpp/platform/resource/`、`core/libretro/core_loader.*`、`common/file_security.*`。
- 输入 / 手柄 / 触控 / 键盘：先看 `entry/src/main/cpp/core/engine/input_manager.*`、`input_snapshot.h`、`app/napi/engine_input_napi.cpp` 和 ArkTS 输入页。

## 变更类型与必须同步项
- 改 `app/napi/**` export：同步检查 `module_init.cpp`、`libretro_engine_napi.cpp`、`entry/src/main/cpp/types/libentry/index.d.ts`、本文 `NAPI Export Inventory`、相关 ArkTS 调用点。
- 改 ArkTS 调 native 返回对象：显式定义 `interface`，检查调用侧是否把 number/boolean/string 当成旧类型使用。
- 改 NativeWindow / NativeBuffer 流程：确认 `RequestBuffer -> FromNativeWindowBuffer -> Map -> Unmap -> FlushBuffer` 配对完整，不引入 `mmap/munmap` 回退。
- 改线程共享状态：明确哪个线程写、哪个线程读、锁的拥有者是谁；同一状态不要一半走原子一半走 mutex。
- 改 SDK / target 版本或本机工具链路径：同步更新 `docs/harmonyos-sdk-target.md`、相关脚本路径、CLAUDE.md 环境说明。

## 多设备与系统能力适配边界
- 当前仓库 `entry/src/main/module.json5` 的 `deviceTypes` 仅为 `phone`；除非用户明确要求或模块配置变更，不默认引入多设备分布式能力改造。
- HarmonyOS 新系统能力、API26 新特性、Accessory Kit、多设备协同等内容，默认只作为“未来可接入能力”评估，不应擅自扩大当前任务范围。
- 涉及平台行为差异时，先以官方 API26 文档和本机 SDK header 为准，再决定是否需要抽象扩展点。

## ArkTS 编程规范（华为官方，检查要求）
- 命名：类/枚举/命名空间用 UpperCamelCase；变量/方法/参数用 lowerCamelCase；常量/枚举值全大写+下划线；布尔名避免否定，优先 is/has/can/should 前缀；标识符用清晰英文，避免单字母/非标准缩写/中文拼音。
- 格式：只用空格缩进，禁 Tab；建议 2 空格（续行 4 空格）；行宽≤120；if/for/while 等建议有大括号；switch case/default 缩进一层且语句再缩进。
- 换行与空格：换行时操作符放行末；一行只声明/赋值一个变量；关键字与 ( 之间空格、函数名与 ( 无空格；else/catch 与前 } 同行且有空格；{ 前加空格（对象字面量首参/模板字符串例外）；二元/三元运算符两侧空格；逗号后空格且逗号/分号前不空格；数组 [] 内无空格；避免连续多空格。
- 字面量与块风格：字符串建议单引号；对象字面量属性>4 个需全部换行；大括号与语句同一行。
- 编程实践：类属性建议显式访问修饰符；浮点数小数点前后不省略 0；判断 NaN 必须用 `Number.isNaN()`；数组遍历优先 Array 方法；控制条件中不做赋值；finally 中禁止 return/break/continue/throw；非跨语言场景避免 `ESObject`；数组类型建议用 `T[]`。

## Codebase Overview (High Level)
- Core emulation/libretro engine code is under `entry/src/main/cpp/core/`.
- HarmonyOS platform adapters live under `entry/src/main/cpp/platform/` (audio/graphics/xcomponent/sync).

## 运行链路图（含调用顺序与线程标注）

### 新架构链路（LibretroEngine + VideoPipeline）
```
[ArkTS/UI 线程]
XComponent.onLoad (new_arch*/phase1*) 
  -> libentry.so (NAPI 初始化 + PluginManager::Export)
  -> 注册 XComponent 回调（Surface/Touch/Key/Mouse）

[XComponent 回调线程]
SurfaceCreated/Changed
  -> LibretroEngine::SetNativeWindow
  -> LibretroEngine::OnNativeWindowResized
  -> Engine 消息队列: WindowCreated

[ArkTS/UI 线程]
refactoredStartEngine / refactoredLoadCore / refactoredLoadRom
  -> libretro_engine_napi.cpp
  -> LibretroEngine::Start / LoadCore / LoadGame
  -> Engine 消息队列: Start / LoadCore / LoadRom

[Engine 线程: LibretroEngine::GameLoop]
HandleMessage(LoadCore)
  -> CoreLoader::LoadCore (dlopen/dlsym)
  -> SetupCallbacks (env/video/audio/input)
  -> retro_init / retro_get_system_info
HandleMessage(LoadRom)
  -> retro_load_game
  -> retro_get_system_av_info
  -> AudioBridge::Reset(sample_rate)
  -> TransitionTo(RUNNING)

[Engine 线程]
ProcessFrame
  -> retro_run
  -> retro_video_refresh -> LibretroEngine::OnVideoRefresh
     -> VideoPipeline::Render (CPU/GLES)
  -> retro_audio_sample_batch -> AudioBridge::ProcessAudio

[渲染路径 - CPU/GLES]
CPU: OH_NativeWindow_RequestBuffer -> Map -> PixelConverter -> Flush
GLES: GLESRenderer::Init/Render -> SwapBuffers

[音频线程 / OHAudio 回调线程]
AudioPlayer::OnWriteDataCallback
  -> RingBuffer::Read (不足则静音)

[输入路径]
ArkTS 虚拟手柄 / 键盘 / 触控
  -> refactoredSendInput / PluginManager 指针/键盘回调
  -> InputManager::SendInput/SendPointer
 |
  
  -> Libretro input_poll/input_state 回调读取 InputSnapshot
```

## NAPI Export Inventory

`libentry.so` 通过 `napi_define_properties` 暴露给 ArkTS 的全部 79 个 export。
ArkTS 契约真值源：`entry/src/main/cpp/types/libentry/index.d.ts`（签名以此为准，本表与之同步）。
注册入口：`libretro_engine_napi.cpp` 转发 6 个子注册函数 + `module_init.cpp` 注册 core_loader / input_mapping 两个独立模块。

命名约定：77 个以 `refactored` 前缀标识新架构；2 个例外（`setInputKeyMapping`、`testCoreLoader`）为遗留/专用接口。
改 `app/napi/**` 任何 export（增删/改签名）须同步本表 + `index.d.ts`（`scan_code_drift.sh` Pattern 5 守）。

### 生命周期 (13) — engine_lifecycle_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredStartEngine` | `() => NapiErrorResult` | sync | 启动引擎线程 + 消息循环（**返回结构对象非 boolean**，判定用 `.success`） |
| `refactoredStopEngine` | `() => boolean` | sync | 同步停止引擎 |
| `refactoredStopEngineAsync` | `() => Promise<boolean>` | async | 异步停止引擎（推荐） |
| `refactoredResetEngine` | `() => boolean` | sync | 重置引擎 |
| `refactoredPauseEngine` | `() => boolean` | sync | 暂停游戏循环 |
| `refactoredResumeEngine` | `() => boolean` | sync | 恢复游戏循环 |
| `refactoredLoadCore` | `(corePath: string) => NapiErrorResult` | sync | 加载 libretro 核心 (.so)（**返回结构对象非 boolean**，判定用 `.success`） |
| `refactoredLoadRom` | `(romPath: string, resMgr?: ResourceManager) => NapiErrorResult` | sync | 加载 ROM（支持 rawfile）（**返回结构对象非 boolean**，判定用 `.success`） |
| `refactoredSwitchGameAsync` | `(corePath, romPath, filesDir, [resMgr], [timeoutMs], [token], [progressCallback]) => Promise<NapiErrorResult>` | async | 切换游戏（两个重载，含/不含 resMgr）；返回结构化错误对象 |
| `refactoredCancelSwitch` | `() => boolean` | sync | 取消进行中的切换（token 失效） |
| `refactoredGetRawFileList` | `(resMgr: ResourceManager, dir?: string) => string[]` | sync | 列出 rawfile 目录文件 |
| `refactoredGetRawFileListAsync` | `(resMgr: ResourceManager, dir?: string) => Promise<string[]>` | async | 异步列出 rawfile 目录 |
| `refactoredInitEventBridge` | `(callback: (data: RefactoredEvent) => void) => boolean` | sync | 初始化 EventBridge 事件通道 |

### 状态/存档/SRAM/作弊/选项 (21) — engine_state_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredGetSaveStateSize` | `() => number` | sync | 存档大小（**@deprecated** 阻塞≤5s，用 Async 版） |
| `refactoredGetSaveStateSizeAsync` | `() => Promise<number>` | async | 异步获取存档大小（推荐） |
| `refactoredSaveState` | `() => ArrayBuffer \| null` | sync | 同步保存状态（阻塞） |
| `refactoredLoadState` | `(data: ArrayBuffer) => boolean` | sync | 同步加载状态（阻塞） |
| `refactoredSaveStateAsync` | `() => Promise<ArrayBuffer>` | async | 异步保存状态（推荐；失败 reject，成功只 resolve ArrayBuffer） |
| `refactoredSaveStateBundleAsync` | `() => Promise<{stateData:ArrayBuffer,thumbnailRgba:ArrayBuffer \| null,thumbnailWidth:number,thumbnailHeight:number}>` | async | 异步保存状态并返回当前帧缩略图原始 RGBA（CPU/GLES 最小闭环） |
| `refactoredLoadStateAsync` | `(data: ArrayBuffer) => Promise<boolean>` | async | 异步加载状态（推荐） |
| `refactoredGetSRAM` | `() => ArrayBuffer \| null` | sync | 获取电池备份 SRAM |
| `refactoredSetSRAM` | `(data: ArrayBuffer) => boolean` | sync | 设置电池备份 SRAM |
| `refactoredGetSRAMAsync` | `() => Promise<ArrayBuffer \| null>` | async | 异步获取电池备份 SRAM（避免 UI 线程同步等待） |
| `refactoredSetSRAMAsync` | `(data: ArrayBuffer) => Promise<boolean>` | async | 异步写入电池备份 SRAM（避免 UI 线程同步等待） |
| `refactoredResetCore` | `() => boolean` | sync | retro_reset 重置核心 |
| `refactoredResetCoreAsync` | `() => Promise<boolean>` | async | 异步执行 core soft reset（避免 UI 线程同步等待） |
| `refactoredCheatReset` | `() => boolean` | sync | 重置所有金手指 |
| `refactoredCheatSet` | `(index: number, enabled: boolean, code: string) => boolean` | sync | 设置单条金手指 |
| `refactoredCheatResetAsync` | `() => Promise<boolean>` | async | 异步重置所有金手指（避免 UI 线程同步等待） |
| `refactoredCheatSetAsync` | `(index: number, enabled: boolean, code: string) => Promise<boolean>` | async | 异步设置单条金手指（避免 UI 线程同步等待） |
| `refactoredGetCoreOptions` | `() => string` | sync | 核心选项（JSON 字符串，需 parse） |
| `refactoredGetCoreOptionsAsync` | `() => Promise<string>` | async | 异步读取核心选项 JSON，避免 UI 线程同步等待 |
| `refactoredSetCoreOption` | `(key: string, value: string) => boolean` | sync | 设置单条核心选项 |
| `refactoredSetCoreOptionAsync` | `(key: string, value: string) => Promise<boolean>` | async | 异步设置单条核心选项，避免 UI 线程同步等待 |

### 输入 (10) — engine_input_napi.cpp (9) + input_mapping_napi.cpp (1)

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredSendInput` | `(port: number, id: number, pressed: boolean) => boolean` | sync | 发送数字按键 |
| `refactoredSendAnalog` | `(port: number, index: number, id: number, value: number) => boolean` | sync | 发送模拟摇杆 |
| `refactoredAssignPortSource` | `(port: number, sourceType: number, deviceId?: string) => boolean` | sync | 分配输入源到端口 |
| `refactoredUnassignPort` | `(port: number) => boolean` | sync | 解除端口绑定 |
| `refactoredListInputDevices` | `() => InputDeviceInfo[]` | sync | 列出已注册输入设备 |
| `refactoredSendSensor` | `(port: number, id: number, value: number) => boolean` | sync | 发送传感器事件（**注意 3 参非 5 参**） |
| `refactoredSetControllerPortDevice` | `(port: number, device: number) => boolean` | sync | 设置端口手柄类型；port 0-3，device 为非负 libretro device id（含 subclass），非法值返回 false |
| `refactoredSetControllerPortDeviceAsync` | `(port: number, device: number) => Promise<boolean>` | async | 异步设置端口手柄类型；port 0-3，device 为非负 libretro device id（含 subclass），非法值返回 false |
| `refactoredGetInputDescriptorMask` | `() => number` | sync | 16-bit 输入描述符掩码，0=核心未声明 |
| `setInputKeyMapping` *(无 refactored 前缀)* | `(mappingMap: Record<string, number>) => boolean` | sync | 设置键盘→libretro 映射表 |

### 视频 (5) + 音频 (3) — engine_video_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredSetScalingMode` | `(mode: number) => boolean` | sync | 缩放模式 0=Hardware/1=Software/2=GLES |
| `refactoredSetSwapInterval` | `(interval: number) => boolean` | sync | swap interval 0=禁用 VSync/1=启用 |
| `refactoredSetSoftwareMaxResolution` | `(maxWidth: number, maxHeight: number) => boolean` | sync | 限制软渲染最大分辨率 |
| `refactoredSetAIUpscale` | `(enabled: boolean) => boolean` | sync | AI 超分开关 |
| `refactoredSetHwRenderAllowed` | `(enabled: boolean) => boolean` | sync | 允许/禁止硬件渲染 |
| `refactoredSetMinimumAudioLatency` | `(latencyMs: number) => boolean` | sync | 设置音频最小延迟 (ms)，负数返回 false 并写入 lastErrorInfo |
| `refactoredSetAudioSyncMode` | `(mode: number) => boolean` | sync | 音频同步模式 0=NonBlocking/1=Blocking |
| `refactoredSetAudioVolume` | `(percent: number) => boolean` | sync | 设置主音量百分比 0-100，越界返回 false 并写入 lastErrorInfo |

### 磁盘控制 (12) — engine_disk_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredDiskControlSetEjectState` | `(ejected: boolean) => boolean` | sync | 设置光驱弹出状态 |
| `refactoredDiskControlSetEjectStateAsync` | `(ejected: boolean) => Promise<boolean>` | async | 异步设置光驱弹出状态，避免 UI 线程同步等待 |
| `refactoredDiskControlGetEjectState` | `() => boolean` | sync | 获取光驱弹出状态 |
| `refactoredDiskControlGetImageIndex` | `() => number` | sync | 当前磁盘映像索引 |
| `refactoredDiskControlSetImageIndex` | `(index: number) => boolean` | sync | 设置磁盘映像索引 |
| `refactoredDiskControlSetImageIndexAsync` | `(index: number) => Promise<boolean>` | async | 异步设置磁盘映像索引，避免 UI 线程同步等待 |
| `refactoredDiskControlGetNumImages` | `() => number` | sync | 磁盘映像总数 |
| `refactoredDiskControlGetSnapshotAsync` | `() => Promise<{ejected:boolean,imageIndex:number,imageCount:number}>` | async | 异步读取换盘状态快照，避免 UI 线程串行同步查询 |
| `refactoredDiskControlReplaceImageIndex` | `(index: number, path: string) => boolean` | sync | 替换指定索引映像 |
| `refactoredDiskControlReplaceImageIndexAsync` | `(index: number, path: string) => Promise<boolean>` | async | 异步替换指定索引映像，避免 UI 线程同步等待 |
| `refactoredDiskControlAddImageIndex` | `() => boolean` | sync | 新增磁盘映像槽位 |
| `refactoredDiskControlAddImageIndexAsync` | `() => Promise<boolean>` | async | 异步新增磁盘映像槽位，避免 UI 线程同步等待 |

### 查询/统计/诊断 (14) — engine_query_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `refactoredGetState` | `() => number` | sync | 引擎状态枚举值 |
| `refactoredWaitForState` | `(state: number, timeoutMs?: number) => boolean` | sync | 同步等待状态（阻塞） |
| `refactoredWaitForStateAsync` | `(state: number, timeoutMs?: number) => Promise<boolean>` | async | 异步等待状态（推荐） |
| `refactoredGetLastErrorInfo` | `() => EngineErrorInfo` | sync | 上次错误详情 {reason,step,message} |
| `refactoredClearLastErrorInfo` | `() => boolean` | sync | 清除错误信息 |
| `refactoredSetFilesDir` | `(filesDir: string) => boolean` | sync | 设置引擎文件目录 |
| `refactoredGetStats` | `() => EngineStats` | sync | 运行时统计（**结构化对象非 JSON 串**） |
| `refactoredResetStats` | `() => boolean` | sync | 重置运行时统计 |
| `refactoredGetInputDebugStats` | `() => InputDebugStats` | sync | 输入调试统计（结构化对象） |
| `refactoredGetRegion` | `() => number` | sync | 区域枚举（**number 非 string**，NTSC/PAL） |
| `refactoredGetRegionAsync` | `() => Promise<number>` | async | 异步读取区域枚举，避免 UI 线程同步等待 |
| `refactoredGetAVInfo` | `() => AVInfo` | sync | 音视频信息 {videoWidth,videoHeight,fps,audioSampleRate} |
| `refactoredHasCoreLoaded` | `() => boolean` | sync | 是否已加载核心 |
| `refactoredHasGameLoaded` | `() => boolean` | sync | 是否已加载游戏 |

### 其他 (1) — core_loader_napi.cpp

| Export | 签名 | 类型 | 功能 |
|--------|------|------|------|
| `testCoreLoader` *(无 refactored 前缀)* | `(corePath: string) => Promise<string>` | **async** | 测试核心 dlopen/dlsym，异步返回结果字符串 |

## Project Structure & Module Organization
- `entry/src/main/ets/`: ArkTS UI and routing (pages, abilities, interfaces).
- `entry/src/main/cpp/`: Native C++ implementation (framework, platform, input, NAPI bindings).
- `entry/src/main/cpp/tests/`: Native test helpers for core loading and ROM checks.
- `entry/src/main/resources/`: App resources, assets, and raw files.
- `AppScope/`: App-level resources and configuration.
- `docs/`, `README*.md`, `Roadmap.md`: Design notes and usage references.
- `entry/build/` and `entry/build-profile.json5`: generated outputs; do not edit by hand.

## Commit & Pull Request Guidelines
- Commit history mixes short Chinese summaries and Conventional Commit-style subjects (e.g., `refactor(build): ...`).
- Use a concise, imperative summary; optionally add a `type(scope):` prefix when it helps clarity.
- PRs should include: what changed, what static checks the agent ran, what device/HarmonyOS validation the user reported, and screenshots for UI changes when available.

## Configuration Tips
- Local SDK/NDK paths are machine-specific (see the shell scripts); avoid committing local paths or `entry/build/` artifacts.

## 图形 API 口径（精简版）
- 移动端按 ARM 平台处理，默认优先 GLES / Vulkan 路径；不要假设手机端存在桌面 OpenGL 能力。
- 具体 API 版本、扩展和设备能力必须以华为官方文档、本机 SDK 声明和运行时查询结果为准，不把旧结论写死进代码。
- EGL/GL 操作默认只在 Engine 线程执行；跨线程共享状态必须有明确锁边界。

## 鸿蒙模拟器能力判断（需共识）
- 平台定位：按“移动端 ARM 平台”处理，默认 Egl + OpenGL ES，Vulkan 视设备支持。
- 性能硬约束：系统禁 JIT/dynarec（不是 LLVM 问题），HW_RENDER 只解决“能出画面”，不等于性能可玩。
- 可覆盖范围：8/16 位主机、GB/GBC/GBA、NDS、PS1、街机等可用。
- 不可期待范围：N64/PSP/DC/Saturn 多数只能勉强运行或不可玩；PS2/3DS/GC/Wii 基本不可行（依赖 dynarec）。
- 核心要求：必须具备 GLES/Vulkan 后端，不能只依赖桌面 OpenGL。


## ArkUI / ArkTS UI 开发

做 UI 页面/组件/蓝湖/HTML→ArkUI 落地时，加载 `/skill arkui-design`（progressive disclosure，只在改 `entry/src/main/ets/**/*.ets` 时触发）。

该 skill 包含完整的 ArkUI 设计规范：布局单位/安全区/响应式/容器选型、5 步页面落地流程、HTML→ArkUI 转换规则、组件规范、工程级约束（类型/状态管理/生命周期/路由/SDK 适配）、反模式与禁止事项。
