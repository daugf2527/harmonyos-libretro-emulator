# C++ 架构体系全面审计报告

> 审计日期：2026-03-06  
> 审计范围：`entry/src/main/cpp/` 全部 109 个源文件（~1140 KB）  
> 审计方式：深度优先遍历每个模块，逐文件阅读头文件及关键实现

---

## 目录

- [一、架构总览](#一架构总览)
  - [1.1 分层架构图](#11-分层架构图)
  - [1.2 目录结构与文件统计](#12-目录结构与文件统计)
  - [1.3 命名空间体系](#13-命名空间体系)
  - [1.4 线程模型](#14-线程模型)
- [二、逐层深度分析](#二逐层深度分析)
  - [2.1 App 层（应用框架 + NAPI 绑定）](#21-app-层应用框架--napi-绑定)
  - [2.2 Core 层 — Engine（引擎核心）](#22-core-层--engine引擎核心)
  - [2.3 Core 层 — Libretro（标准封装）](#23-core-层--libretro标准封装)
  - [2.4 Interfaces 层（接口抽象）](#24-interfaces-层接口抽象)
  - [2.5 Platform 层（平台适配）](#25-platform-层平台适配)
  - [2.6 Common 层（公共工具）](#26-common-层公共工具)
  - [2.7 构建系统](#27-构建系统)
- [三、架构问题清单（按严重程度排序）](#三架构问题清单按严重程度排序)
  - [P0 — 结构性缺陷](#p0--结构性缺陷)
  - [P1 — 设计不合理](#p1--设计不合理)
  - [P2 — 技术债务](#p2--技术债务)
  - [P3 — 改进建议](#p3--改进建议)
- [四、关键类关系图](#四关键类关系图)
- [五、重构路线图建议](#五重构路线图建议)

---

## 一、架构总览

### 1.1 分层架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                        ArkTS / UI 层                             │
│  (pages, components, XComponent)                                 │
├──────────────────────────────────────────────────────────────────┤
│                    App 层 (app/)                                 │
│  ┌──────────────────────┐  ┌─────────────────────────────────┐  │
│  │ PluginManager        │  │ NAPI 绑定                        │  │
│  │ (XComponent 回调注册) │  │ module_init.cpp                  │  │
│  │                      │  │ libretro_engine_napi.cpp (1571行) │  │
│  │                      │  │ core_loader_napi.cpp              │  │
│  └──────────────────────┘  └─────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│                    Core 层 (core/)                               │
│  ┌──────────────────────────────────┐ ┌────────────────────────┐│
│  │ Engine (core/engine/)             │ │ Libretro (core/libretro)│
│  │ ├─ LibretroEngine ⭐ (God Class) │ │ ├─ CoreLoader           ││
│  │ ├─ VideoPipeline                  │ │ ├─ EnvDispatcher/State  ││
│  │ ├─ RenderThread                   │ │ ├─ CoreOptionsRegistry  ││
│  │ ├─ InputManager                   │ │ ├─ DiskController       ││
│  │ ├─ InputPortRouter                │ │ └─ libretro.h (官方)    ││
│  │ ├─ EventBridge (TSFN)             │ │                         ││
│  │ ├─ CoreStateManager               │ └────────────────────────┘│
│  │ ├─ CoreQuirksManager              │                           │
│  │ ├─ FrameBufferPool                │                           │
│  │ ├─ BoundedLatestFrameQueue        │                           │
│  │ ├─ WindowSession/Guard/State      │                           │
│  │ ├─ MessageQueue                   │                           │
│  │ └─ FramePacer                     │                           │
│  └──────────────────────────────────┘                            │
├──────────────────────────────────────────────────────────────────┤
│               Interfaces 层 (interfaces/)                        │
│  IAudioSink  IRenderer  IInputManager  ICoreLoader  IConfiguration│
│  IStateManager  ICheatManager  ICoreOptions  IDiskControl         │
│  IEngineStats  ILogger  IResourceManager  IVirtualFileSystem      │
├──────────────────────────────────────────────────────────────────┤
│               Platform 层 (platform/)                            │
│  ┌──────────┐ ┌──────────────────┐ ┌───────────┐ ┌────────────┐│
│  │ Audio    │ │ Graphics         │ │ Resource  │ │ Sync       ││
│  │ Bridge   │ │ GLESRenderer     │ │ RomLoader │ │ NativeVSync││
│  │ Player   │ │ GraphicsContext   │ │ PlatRes   │ │ Driver     ││
│  │ Resampler│ │ HwRenderPresenter│ │ TempFile  │ │            ││
│  │ RingBuf  │ │ PixelConverter   │ │ RawfileRom│ │            ││
│  │          │ │ VulkanContext    │ │           │ │            ││
│  │          │ │ VulkanLoader     │ │           │ │            ││
│  │          │ │ VulkanPresenter  │ │           │ │            ││
│  └──────────┘ └──────────────────┘ └───────────┘ └────────────┘│
├──────────────────────────────────────────────────────────────────┤
│                Common 层 (common/)                               │
│  log_prefix  string_utils  file_utils  file_security  fence_utils│
│  cue_parser  FileConfiguration  LoggerProvider                   │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 目录结构与文件统计

```
entry/src/main/cpp/
├── CMakeLists.txt                    # 唯一构建文件
├── app/                              # 应用层
│   ├── framework/                    #   XComponent 桥接
│   │   ├── plugin_manager.h/cpp      #   509 行
│   └── napi/                         #   NAPI 绑定
│       ├── module_init.cpp           #   81 行
│       ├── core_loader_napi.h/cpp    #   测试用
│       └── libretro_engine_napi.cpp  #   1571 行 ⚠️
├── core/                             # 核心层
│   ├── engine/                       #   引擎核心 (22 文件)
│   │   ├── libretro_engine.h/cpp     #   ~2750 行 ⚠️
│   │   ├── video_pipeline.h/cpp      #   ~1985 行
│   │   ├── render_thread.h/cpp       #   ~400 行
│   │   ├── input_manager.h/cpp       #   ~200 行
│   │   ├── input_port_router.h/cpp   #   ~250 行
│   │   ├── input_snapshot.h          #   207 行
│   │   ├── event_bridge.h/cpp        #   ~300 行
│   │   ├── core_state_manager.h/cpp  #   ~150 行
│   │   ├── core_quirks_manager.h/cpp #   ~100 行
│   │   ├── frame_buffer_pool.h/cpp   #   ~80 行
│   │   ├── bounded_latest_frame_queue.h  93 行
│   │   ├── video_frame_packet.h      #   34 行
│   │   ├── engine_messages.h         #   153 行
│   │   ├── message_queue.h           #   131 行
│   │   ├── frame_pacer.h             #   79 行
│   │   ├── window_session.h/cpp      #   ~50 行
│   │   ├── window_state_manager.h/cpp#   ~100 行
│   │   └── window_guard.h            #   111 行
│   └── libretro/                     #   Libretro 标准封装 (10 文件)
│       ├── libretro.h                #   官方头文件
│       ├── libretro_vulkan.h         #   官方 Vulkan 扩展
│       ├── retro_common.h            #   函数指针 typedef
│       ├── core_loader.h/cpp         #   ~300 行
│       ├── env_dispatcher.h/cpp      #   ~800 行
│       ├── core_options_registry.h/cpp # ~200 行
│       └── disk_controller.h/cpp     #   ~200 行
├── interfaces/                       # 接口层 (13 文件，纯头文件)
│   ├── audio/i_audio_sink.h
│   ├── config/i_configuration.h
│   ├── core/{i_cheat_manager, i_core_loader, i_core_options, i_disk_control}.h
│   ├── diagnostics/{i_engine_stats, i_logger}.h
│   ├── graphics/i_renderer.h
│   ├── input/i_input_manager.h
│   ├── resource/i_resource_manager.h
│   ├── state/i_state_manager.h
│   └── vfs/i_virtual_file_system.h
├── platform/                         # 平台适配层 (24 文件)
│   ├── audio/{audio_bridge, audio_player, audio_resampler, ring_buffer}.h/cpp
│   ├── graphics/{gles_renderer, graphics_context, hw_render_presenter,
│   │             pixel_converter, vulkan_context, vulkan_loader, vulkan_presenter}.h/cpp
│   ├── resource/{platform_resource_manager, rawfile_rom_processor, rom_loader,
│   │             temp_file_manager}.h/cpp
│   └── sync/native_vsync_driver.h/cpp
├── common/                           # 公共工具 (12 文件)
│   ├── log_prefix.h, string_utils.h, file_utils.h, file_security.h/cpp
│   ├── fence_utils.h/cpp, cue_parser.h/cpp, utils.cpp
│   ├── config/file_configuration.h/cpp
│   └── diagnostics/logger_provider.h/cpp
├── include/                          # (空目录，仅用于 include 路径)
├── types/libentry/                   # NAPI 类型声明
└── tests/                            # 测试（已从构建排除）
    ├── integration/test_gambatte_{load,rom}.cpp
    └── unit/core_loader_test.cpp
```

### 1.3 命名空间体系

| 命名空间 | 作用 | 问题 |
|---------|------|------|
| `libretro` | 引擎核心 + 平台层大部分类 | 范围过大，engine/platform/audio 全混在一起 |
| `interfaces` | 抽象接口 | ✅ 合理 |
| `common` | 字符串/文件工具 | ✅ 合理 |
| `security` | 路径验证 | ⚠️ 应归入 `common` |
| `diagnostics` | 日志提供者 | ⚠️ 应归入 `common::diagnostics` |
| `core_options` | 嵌套在 `libretro` 下 | ⚠️ 不一致 |
| **全局命名空间** | `CoreLoader` 类 | ❌ 唯一未在命名空间中的核心类 |
| **全局命名空间** | `PluginManager` 类 | ❌ 同上 |

### 1.4 线程模型

```
┌─────────────────────┐
│   ArkTS / UI 线程    │ ← NAPI 入口点、PluginManager 回调
│                     │ ← SendInput / LoadCore / Start / Stop
└────────┬────────────┘
         │ MessageQueue / atomic
┌────────▼────────────┐
│   Engine 线程        │ ← GameLoop → ProcessFrame → retro_run
│   (LibretroEngine)  │ ← HandleMessage
│                     │ ← 音视频回调 (OnVideoRefresh/OnAudioSampleBatch)
└────────┬────────────┘
         │ BoundedLatestFrameQueue (帧传递)
┌────────▼────────────┐
│   Render 线程        │ ← RenderThread::ThreadMain
│   (RenderThread)    │ ← VSync 驱动 / 帧渲染
└─────────────────────┘

┌─────────────────────┐
│   OHAudio 回调线程   │ ← AudioPlayer::OnWriteDataCallback
│                     │ ← 从 RingBuffer 读取数据
└─────────────────────┘

┌─────────────────────┐
│  XComponent 回调线程  │ ← SurfaceCreated / Changed / Destroyed
│                     │ ← Touch / Key / Mouse
└─────────────────────┘
```

---

## 二、逐层深度分析

### 2.1 App 层（应用框架 + NAPI 绑定）

#### PluginManager (`app/framework/`)

- **职责**：注册 XComponent 生命周期回调（Surface/Touch/Key/Mouse/Focus）
- **设计**：全局单例，回调中直接调用 `LibretroEngine::GetInstance()`
- **评价**：
  - ✅ 职责明确，代码可读
  - ⚠️ 位于全局命名空间，与其他类不一致
  - ⚠️ 输入映射逻辑（`MapKeyCodeToJoypad`、指针归一化）耦合在框架层
  - ⚠️ `NewArchInputStats` 与 `interfaces::InputDebugStats` 字段几乎重复

#### NAPI 绑定 (`app/napi/`)

- `module_init.cpp`：入口注册，结构清晰
- `libretro_engine_napi.cpp`：**1571 行巨型文件**，包含 60+ 个 NAPI 函数
- `core_loader_napi.cpp`：遗留测试接口

### 2.2 Core 层 — Engine（引擎核心）

#### LibretroEngine — 上帝类 ⚠️

| 指标 | 数值 |
|------|------|
| 头文件行数 | 436 行 |
| 实现文件行数 | ~2750 行 |
| 公有方法 | ~55 个 |
| 私有成员变量 | ~75 个 |
| 管理的锁 | 7 个 mutex + 1 个 recursive_mutex |
| 状态枚举 | 2 个（EngineState 10 态 + EnginePhase 7 态） |

**LibretroEngine 承担的职责**（至少 8 个独立关注点）：

1. **生命周期管理**：Start / Stop / Pause / Resume / Reset
2. **核心加载编排**：LoadCore / LoadGame / SetupCallbacks
3. **主循环调度**：GameLoop / ProcessFrame / HandleMessage
4. **输入分发**：7 个输入方法（Button/Analog/Virtual/Keyboard/Pointer/Sensor/Port）
5. **视频配置**：ScalingMode / SwapInterval / SoftwareMaxResolution / AIUpscale
6. **音频配置**：MinimumAudioLatency
7. **存档/金手指**：SaveState / LoadState / SRAM / Cheat
8. **磁盘控制**：7 个磁盘控制方法
9. **窗口管理**：SetNativeWindow / ClearNativeWindow / OnResized
10. **统计收集**：RuntimeStats / FPS / 心跳
11. **事件桥接**：EventBridge 初始化和使用
12. **错误管理**：EngineErrorInfo

#### VideoPipeline — 复杂但设计良好

- 支持三种渲染路径：CPU（软件缩放）、GLES（推荐）、HW Render（Vulkan/GLES 硬件渲染）
- 内嵌 `IRenderBackend` 策略接口
- 包含降级/恢复机制（`RenderModeState`）
- ⚠️ 后端实现（`SoftwareRenderBackend` / `GlesRenderBackend` / `HwRenderBackend`）定义在 `.cpp` 文件中，无法被其他模块复用或测试
- ⚠️ 成员变量过多（~80 个），Reset() 方法需手动重置每一个

#### RenderThread — 独立渲染线程

- 职责明确：接收帧数据、VSync 驱动、窗口管理
- ✅ 控制消息队列设计合理
- ✅ 与 VideoPipeline 解耦良好

#### InputManager + InputPortRouter + InputSnapshot

- ✅ 三层分离设计合理：快照（无锁原子）→ 管理器（业务逻辑）→ 路由器（多设备映射）
- ⚠️ `InputManager` 同时持有静态全局实例（`g_instance`），与单例模式重叠

#### 窗口管理三件套

| 类 | 职责 | 问题 |
|----|------|------|
| `WindowGuard` | RAII 引用计数 + 线程安全获取 | ❌ **未被使用**，LibretroEngine 直接操作裸指针 |
| `WindowSession` | 窗口会话状态机 | ⚠️ 仅 RenderThread 使用 |
| `WindowStateManager` | NativeWindow 参数配置缓存 | ✅ 合理 |

#### 其他 Engine 组件

| 组件 | 评价 |
|------|------|
| `MessageQueue<T>` | ✅ 简洁、正确，支持 Close/Reopen 语义 |
| `FramePacer` | ✅ 轻量，spin-wait 尾部精确 |
| `FrameBufferPool` | ✅ 对象池设计合理，shared_ptr 回收 |
| `BoundedLatestFrameQueue` | ✅ 专为最新帧设计，丢弃旧帧 |
| `VideoFramePacket` | ✅ 值语义，带 generation 防过期帧 |
| `EventBridge` | ✅ TSFN 封装 + 限流机制 |
| `CoreStateManager` | ✅ 职责单一，仅管存档/SRAM/金手指 |
| `CoreQuirksManager` | ✅ 核心兼容性补丁隔离 |
| `EngineMessage` | ⚠️ 非 union 结构体，消息体浪费内存（见问题清单） |

### 2.3 Core 层 — Libretro（标准封装）

| 组件 | 评价 |
|------|------|
| `CoreLoader` | ⚠️ **不在 `libretro` 命名空间中**，getter 方法过多（30+） |
| `EnvState` | ⚠️ 又一个大类（~265 行），混合线程安全与非线程安全字段 |
| `env_dispatcher.cpp` | ✅ `HandleEnvironmentCommand` 集中处理所有 env cmd |
| `CoreOptionsRegistry` | ✅ V1/V2 选项标准化 |
| `DiskController` | ✅ 职责单一 |

### 2.4 Interfaces 层（接口抽象）

**定义了 13 个接口，实际使用情况：**

| 接口 | 有实现类？ | 实际通过接口调用？ |
|------|----------|------------------|
| `ICoreLoader` | ✅ `CoreLoader` | ❌ LibretroEngine 直接持有 `CoreLoader`（具体类） |
| `IAudioSink` | ✅ `AudioBridge` | ❌ 直接用 `AudioBridge::GetInstance()` |
| `IRenderer` | ✅ `EngineRendererAdapter` | ⚠️ 适配器回调回 LibretroEngine，**循环依赖** |
| `IInputManager` | ✅ `InputManager` | ❌ LibretroEngine 直接持有 `InputManager` |
| `IResourceManager` | ✅ `PlatformResourceManager` | ❌ 直接用单例 |
| `IConfiguration` | ✅ `FileConfiguration` | ⚠️ 仅 env_dispatcher 内部使用 |
| `ILogger` | ✅ `LoggerProvider` | ⚠️ 仅 provider 模式，未普及 |
| `IVirtualFileSystem` | ✅ 通过 `IResourceManager` | ⚠️ 间接使用 |
| `IStateManager` | ❌ **无实现** | ❌ |
| `ICheatManager` | ❌ **无实现** | ❌ |
| `ICoreOptions` | ❌ **无实现** | ❌ |
| `IDiskControl` | ❌ **无实现** | ❌ |
| `IEngineStats` | ❌ **无实现** | ❌ |

**结论：接口层形同虚设，依赖倒置原则（DIP）未实际落地。**

### 2.5 Platform 层（平台适配）

#### Audio 子系统

```
AudioBridge (IAudioSink)
├── AudioResampler    ← Hermite 4点插值 + DRC
├── RingBuffer        ← SPSC 无锁环形缓冲 + 阻塞等待
└── AudioPlayer       ← OHAudio 封装
```

- ✅ 音频管线设计成熟，DRC 算法合理
- ✅ RingBuffer 缓存行对齐避免伪共享
- ⚠️ AudioBridge 单例生命周期与 LibretroEngine 不同步
- ⚠️ `AudioPlayer` 同时支持新旧两套 OHAudio 回调 API

#### Graphics 子系统

```
GLESRenderer           ← GLES 3.0 纹理上传 + PBO + XEngine 超分
GraphicsContext        ← EGL 上下文/表面管理
HwRenderPresenter      ← FBO 管理 + 全屏呈现
PixelConverter         ← NEON/Scalar 像素格式转换
VulkanLoader           ← dlsym 加载 Vulkan 函数
VulkanContext          ← VkInstance/Device/Swapchain 管理
VulkanPresenter        ← retro_hw_render_interface_vulkan 实现
```

- ✅ Vulkan 全链路实现完整（Loader → Context → Presenter）
- ✅ GLES 路径含 PBO triple-buffering 优化
- ✅ 像素转换器 NEON/Scalar 自动选择
- ⚠️ `GLESRenderer` 成员变量 30+ 个日志计数器
- ⚠️ `PixelConverter` 自定义 `PixelFormat` 枚举与 `retro_pixel_format` 重复

#### Resource 子系统

- ✅ `RawfileRomProcessor` 处理 CUE/BIN 多文件依赖
- ✅ `TempFileManager` 管理临时文件写入
- ⚠️ `PlatformResourceManager` 单例 + 手动 Initialize

#### Sync 子系统

- ✅ `NativeVSyncDriver` 条件编译兼容无 VSync 环境
- ✅ 接口简洁：Start / Stop / RequestNextFrame

### 2.6 Common 层（公共工具）

| 工具 | 评价 |
|------|------|
| `log_prefix.h` | ✅ 统一日志宏，带 TAG + FLOW |
| `string_utils.h` | ✅ 轻量 trim + JSON 转义 |
| `file_utils.h` | ✅ 目录创建 + 文件写入 |
| `file_security.h` | ✅ 路径验证白名单 |
| `fence_utils.h` | ✅ Sync Fence 等待封装 |
| `cue_parser.h` | ✅ CUE 文件解析 |
| `FileConfiguration` | ✅ 键值对文件读写 |
| `LoggerProvider` | ⚠️ 全局 setter/getter，未广泛使用 |

### 2.7 构建系统

- 单一 `CMakeLists.txt`，所有源文件编译为一个 `entry.so`
- C++ 14 标准
- NEON 优化按架构条件编译
- HMS SDK 路径自动检测
- ⚠️ 无模块化静态库分离
- ⚠️ 测试文件已注释排除，无法独立构建

---

## 三、架构问题清单（按严重程度排序）

### P0 — 结构性缺陷

#### P0-1：LibretroEngine 上帝类

**现状**：单个类承担 10+ 个独立职责，55+ 个公有方法，75+ 个成员变量，2750+ 行实现。

**影响**：
- 无法独立测试任何子功能
- 修改任何功能都可能影响全局
- 新开发者学习曲线极陡

**建议**：拆分为多个协作者对象，LibretroEngine 作为 Facade 仅做编排：
```
LibretroEngine (Facade/Coordinator)
├── LifecycleManager       ← Start/Stop/Pause/Resume/Reset
├── CoreSession            ← LoadCore/LoadGame/Callbacks
├── InputDispatcher        ← 所有输入方法（已有 InputManager，需彻底委托）
├── VideoConfigurator      ← ScalingMode/SwapInterval/etc
├── StateController        ← SaveState/SRAM/Cheat（已有 CoreStateManager）
├── DiskController         ← 磁盘控制（已有，需彻底委托）
├── StatisticsCollector    ← RuntimeStats/FPS
└── WindowCoordinator      ← 窗口生命周期
```

---

#### P0-2：接口层形同虚设

**现状**：定义了 13 个接口，5 个无实现，剩余 8 个有实现但多数未通过接口调用。

**影响**：
- 依赖倒置原则（DIP）名存实亡
- 无法 Mock 测试
- 接口与实现并行维护成本

**建议**：
- 移除所有无实现的接口（`IStateManager`、`ICheatManager`、`ICoreOptions`、`IDiskControl`、`IEngineStats`），或立刻编写实现类
- 对已有实现的接口，修改持有方使用接口指针而非具体类：
  ```cpp
  // Before:
  CoreLoader coreLoader_;
  // After:
  std::unique_ptr<interfaces::ICoreLoader> coreLoader_;
  ```

---

#### P0-3：单例模式泛滥且不一致

**现状**：至少 6 个单例，使用 4 种不同模式：

| 类 | 单例模式 |
|----|---------|
| `LibretroEngine` | `static atomic<LibretroEngine*>` + `GetInstance()` |
| `AudioBridge` | 经典 new + `GetInstance()` / `DestroyInstance()` |
| `PlatformResourceManager` | 同上 |
| `InputManager` | `static atomic<InputManager*> g_instance` |
| `CoreQuirksManager` | Meyers 单例（函数内 static） |
| `PluginManager` | 函数内 `static PluginManager instance` |

**影响**：
- 生命周期管理混乱（谁创建谁销毁？）
- 隐式全局依赖，难以追踪
- Libretro 回调的 C 函数桥接被迫依赖全局指针

**建议**：
- 保留 `LibretroEngine` 单例（因 Libretro C 回调的限制），但统一为 Meyers 单例
- 其他类改为显式依赖注入，由 `LibretroEngine` 或 `EngineBuilder` 创建并持有
- 抽取 `GlobalCallbackRegistry` 集中管理 C 回调桥接所需的全局指针

---

### P1 — 设计不合理

#### P1-1：EngineRendererAdapter 循环依赖

**现状**：`EngineRendererAdapter` 实现 `IRenderer`，但每个方法都回调 `LibretroEngine`，形成 Engine → Adapter → Engine 的循环。

**影响**：接口抽象无意义，增加间接调用成本。

**建议**：移除 `EngineRendererAdapter`，让需要 `IRenderer` 的外部消费者直接使用 `VideoPipeline` + `RenderThread`。

---

#### P1-2：EngineMessage 内存浪费

**现状**：
```cpp
struct EngineMessage {
  MessageType type;
  struct {
    EngineMessageInput input;          // 12 bytes
    EngineMessageLoadPath loadPath;    // 1024+ bytes (固定数组)
    EngineMessageTouch touch;          // 12 bytes
    EngineMessageWindow window;        // 24 bytes
    EngineMessageWindowSize windowSize;// 8 bytes
    EngineMessageVideoFormat videoFormat;// 16 bytes
    EngineMessageSyncTask syncTask;    // 16 bytes (shared_ptr)
  } payload;
};
```

所有 payload 字段同时存在（非 union），每条消息占用 >1100 字节。大量高频消息（如 Input、Pause、Resume）实际只需几个字节。

**建议**：使用 `std::variant`（C++17）或 tagged union + 显式析构：
```cpp
using MessagePayload = std::variant<
  EngineMessageInput,
  EngineMessageLoadPath,
  EngineMessageTouch,
  EngineMessageWindow,
  EngineMessageWindowSize,
  EngineMessageSyncTask
>;
```

---

#### P1-3：WindowGuard 设计良好但从未使用

**现状**：`WindowGuard` 实现了 RAII 引用计数和 `ScopedWindow`，但 LibretroEngine 和 RenderThread 都使用裸 `OHNativeWindow*` + 手动锁。

**建议**：统一采用 `WindowGuard` 管理窗口生命周期，移除手动引用计数代码。

---

#### P1-4：CoreLoader 不在命名空间中

**现状**：`CoreLoader` 在全局命名空间声明，而所有其他核心类在 `libretro::`。

**建议**：移入 `libretro::` 命名空间，修正所有引用。

---

#### P1-5：NAPI 绑定层过于集中

**现状**：`libretro_engine_napi.cpp` 单文件 1571 行，包含 60+ 个独立函数。

**建议**：按功能域拆分：
```
app/napi/
├── engine_lifecycle_napi.cpp    ← Start/Stop/Pause/Resume
├── engine_input_napi.cpp        ← SendInput/Analog/Pointer/Sensor
├── engine_video_napi.cpp        ← ScalingMode/SwapInterval/AIUpscale
├── engine_state_napi.cpp        ← SaveState/LoadState/SRAM/Cheat
├── engine_disk_napi.cpp         ← DiskControl 系列
├── engine_query_napi.cpp        ← GetState/GetStats/GetAVInfo
└── engine_napi_register.cpp     ← RegisterLibretroRefactoredNapi
```

---

### P2 — 技术债务

#### P2-1：统计计数器重复

**现状**：三处独立的统计结构体字段大量重叠：
- `RuntimeStats`（LibretroEngine）：30+ 字段
- `RenderMetrics`（VideoPipeline）：13 字段
- `RenderThreadStats`（RenderThread）：20+ 字段

数据需在 `ProcessFrame` 和 `GetStats` 中手动聚合。

**建议**：设计层级统计系统，各组件维护自己的 Stats，由 `StatsAggregator` 统一采集。

---

#### P2-2：日志节流计数器泛滥

**现状**：
- LibretroEngine：15+ 个 `*LogCount_` 变量
- GLESRenderer：25+ 个日志计数器
- AudioBridge / AudioPlayer：10+ 个

**建议**：引入 `ThrottledLogger` 工具类：
```cpp
class ThrottledLogger {
  void LogEvery(int n, LogLevel level, const char* tag, const char* fmt, ...);
  void LogAtMost(int maxCount, LogLevel level, ...);
};
```

---

#### P2-3：C++14 限制

**现状**：`CMAKE_CXX_STANDARD 14`，但多处代码可受益于 C++17：
- `std::variant` 替代 tagged struct（EngineMessage）
- `std::optional` 替代 `bool has_xxx` + 值的组合模式
- `std::string_view` 减少字符串拷贝
- 结构化绑定简化代码

**建议**：升级到 C++17（HarmonyOS NDK 已支持）。

---

#### P2-4：Include 路径混乱

**现状**：同一项目中存在三种 include 风格：
```cpp
#include "../../platform/graphics/gles_renderer.h"  // 相对路径
#include "platform/graphics/gles_renderer.h"        // 项目根路径
#include "core/libretro/libretro.h"                 // 子目录路径
```

有些文件甚至用 `__has_include` 兼容两种路径：
```cpp
#if defined(__has_include) && __has_include("../../platform/resource/rom_loader.h")
#include "../../platform/resource/rom_loader.h"
#else
#include "platform/resource/rom_loader.h"
#endif
```

**建议**：统一使用基于项目根的路径（CMakeLists 已配置 `include_directories`），移除所有相对路径引用。

---

#### P2-5：EnvState 线程安全不一致

**现状**：`EnvState` 部分字段有 mutex 保护，部分没有：
- 有锁保护：`variables_mutex_`、`core_options_mutex_`、`min_audio_latency_mutex_`、`directory_mutex_`
- 无锁保护：`pixel_format_`、`can_dupe_`、`overscan_`、`supports_no_game_`、`geometry_*`、`in_retro_run_`、`keyboard_callback_`、`hw_render_cb_` 等

**影响**：Engine 线程和 UI 线程可能并发读写这些字段。

**建议**：
- 仅 Engine 线程写、Engine 线程读的字段：不需要锁（但需文档标注）
- 跨线程读写的字段：要么用 `std::atomic`，要么统一在 mutex 下

---

#### P2-6：PixelConverter 重复枚举

**现状**：`PixelConverter::PixelFormat` 自定义了 `RGB0555`、`RGB565`、`XRGB8888` 等值，与 `retro_pixel_format` 的 `RETRO_PIXEL_FORMAT_0RGB1555`、`RETRO_PIXEL_FORMAT_RGB565`、`RETRO_PIXEL_FORMAT_XRGB8888` 完全重复。每次调用都需要显式转换。

**建议**：直接使用 `retro_pixel_format` + 目标格式参数，移除自定义枚举。

---

#### P2-7：构建无模块分离

**现状**：所有 109 个源文件编译为单一 `entry.so`，无法：
- 独立编译测试某一层
- 控制层间可见性
- 并行编译提速

**建议**：拆分为静态库：
```cmake
add_library(libretro_common STATIC ${COMMON_SOURCES})
add_library(libretro_core STATIC ${CORE_SOURCES} ${REFACTORED_ENGINE_SOURCES})
add_library(libretro_platform STATIC ${PLATFORM_*_SOURCES})
add_library(entry SHARED ${APP_*_SOURCES})
target_link_libraries(entry PRIVATE libretro_core libretro_platform libretro_common)
```

---

### P3 — 改进建议

#### P3-1：缺少 DI（依赖注入）容器

**现状**：组件通过单例或直接构造获取依赖。

**建议**：引入简单的 `EngineBuilder` 或工厂模式：
```cpp
class EngineBuilder {
  std::unique_ptr<ICoreLoader> coreLoader_;
  std::unique_ptr<IAudioSink> audioSink_;
  // ...
  LibretroEngine Build();
};
```

---

#### P3-2：错误处理碎片化

**现状**：
- LibretroEngine 有 `EngineErrorInfo`
- CoreLoader 有 `lastErrorStep_` / `lastErrorMessage_`
- 各处使用返回值 `bool`、日志、统计计数器混合报错

**建议**：引入统一的 `Result<T>` 或 `EngineError` 枚举体系：
```cpp
enum class EngineError {
  OK,
  CORE_LOAD_FAILED,
  GAME_LOAD_FAILED,
  AUDIO_INIT_FAILED,
  WINDOW_UNAVAILABLE,
  // ...
};
```

---

#### P3-3：测试基础设施缺失

**现状**：`tests/` 目录有 3 个文件但已从构建排除，无测试框架集成。

**建议**：
- 引入 Google Test 或类似框架
- 利用接口层实现 Mock 测试
- 至少覆盖：MessageQueue、RingBuffer、InputSnapshot、FrameBufferPool

---

#### P3-4：VideoPipeline::Reset() 过长

**现状**：Reset() 方法需手动逐个重置 ~50 个成员变量，容易遗漏新增字段。

**建议**：将相关字段分组为子结构体，利用聚合初始化：
```cpp
struct GlesRenderState {
  GlesState state = GlesState::UNINITIALIZED;
  unsigned swap_fail_count = 0;
  // ...
};
GlesRenderState gles_state_;  // Reset: gles_state_ = {};
```

---

#### P3-5：命名空间细分

**建议**：
```
libretro::engine    ← LibretroEngine, VideoPipeline, RenderThread, etc.
libretro::core      ← CoreLoader, EnvDispatcher, DiskController, etc.
libretro::audio     ← AudioBridge, AudioPlayer, AudioResampler, RingBuffer
libretro::graphics  ← GLESRenderer, GraphicsContext, Vulkan*, PixelConverter
libretro::resource  ← RomLoader, PlatformResourceManager, etc.
libretro::sync      ← NativeVSyncDriver
common::*           ← 保持不变
interfaces::*       ← 保持不变
```

---

## 四、关键类关系图

```
                    ┌─────────────────┐
                    │ PluginManager   │
                    │ (XComponent CB) │
                    └────────┬────────┘
                             │ 注册回调
                    ┌────────▼────────┐
                    │ NAPI 绑定层     │
                    │ (60+ 函数)      │
                    └────────┬────────┘
                             │ 调用
                    ┌────────▼──────────────────────────────────┐
                    │        LibretroEngine (God Class)          │
                    │                                            │
                    │  ┌─────────┐ ┌───────────────┐            │
                    │  │CoreLoader│ │  EnvState     │            │
                    │  │(dlopen) │ │  (env vars)   │            │
                    │  └─────────┘ └───────────────┘            │
                    │                                            │
                    │  ┌──────────────┐ ┌──────────────────┐    │
                    │  │VideoPipeline │ │  RenderThread    │    │
                    │  │┌───────────┐│ │  ┌────────────┐  │    │
                    │  ││GLES      ││ │  │BoundedQueue│  │    │
                    │  ││SW/HW     ││ │  │VSync Driver│  │    │
                    │  │└───────────┘│ │  └────────────┘  │    │
                    │  └──────────────┘ └──────────────────┘    │
                    │                                            │
                    │  ┌─────────────┐ ┌─────────────────────┐  │
                    │  │InputManager │ │  InputPortRouter    │  │
                    │  │(InputSnap) │ │  (多设备→端口映射)   │  │
                    │  └─────────────┘ └─────────────────────┘  │
                    │                                            │
                    │  ┌─────────────┐ ┌─────────────────────┐  │
                    │  │EventBridge  │ │  CoreStateManager   │  │
                    │  │(TSFN→ArkTS)│ │  (存档/SRAM/金手指)  │  │
                    │  └─────────────┘ └─────────────────────┘  │
                    │                                            │
                    │  ┌─────────────────┐ ┌───────────────┐    │
                    │  │AudioBridge ★    │ │DiskController │    │
                    │  │(单例,非Engine持有)│ │               │    │
                    │  └─────────────────┘ └───────────────┘    │
                    └───────────────────────────────────────────┘
                    
                    ★ = 独立单例，不受 Engine 生命周期管理
```

---

## 五、重构路线图建议

### 阶段 1：低风险基础治理（1-2 周）

| 序号 | 任务 | 影响范围 |
|------|------|---------|
| 1 | 将 `CoreLoader` 移入 `libretro::` 命名空间 | core_loader.h/cpp + 引用点 |
| 2 | 统一 include 路径为项目根格式 | 全局 |
| 3 | 移除 5 个无实现的接口 | interfaces/ |
| 4 | 引入 `ThrottledLogger` 替代散布的日志计数器 | common/ + 各使用处 |
| 5 | C++ 标准升级到 17 | CMakeLists.txt |
| 6 | 移除 `PixelConverter` 自定义 PixelFormat 枚举 | platform/graphics/ |

### 阶段 2：结构性拆分（2-4 周）

| 序号 | 任务 | 影响范围 |
|------|------|---------|
| 7 | 拆分 `libretro_engine_napi.cpp` 为 6-7 个文件 | app/napi/ |
| 8 | 从 LibretroEngine 提取 `LifecycleManager` | core/engine/ |
| 9 | 彻底委托输入到 InputManager（移除 Engine 中的输入代码） | core/engine/ |
| 10 | 统一窗口管理到 `WindowGuard` | core/engine/ |
| 11 | CMake 拆分为多个静态库 | CMakeLists.txt |
| 12 | EngineMessage 改用 variant 或 tagged union | core/engine/ |

### 阶段 3：架构完善（4-6 周）

| 序号 | 任务 | 影响范围 |
|------|------|---------|
| 13 | 接口层实际落地：Engine 通过接口持有依赖 | core/ + interfaces/ |
| 14 | 引入 EngineBuilder / 简易 DI | core/engine/ |
| 15 | 统一错误处理体系 | 全局 |
| 16 | EnvState 线程安全审计 + 文档标注 | core/libretro/ |
| 17 | 统计系统重构（层级 Stats + Aggregator） | core/ + platform/ |
| 18 | 集成测试框架 + 核心组件单元测试 | tests/ |

---

> **备注**：本文档基于 2026-03-06 的代码快照分析。架构整体方向正确（分层、接口隔离意图明确），
> 主要问题在于 **God Class 集中控制** 和 **接口层未落地**，导致设计意图与实际执行之间存在显著差距。
> 建议按路线图分阶段治理，每阶段验证后再进入下一阶段。
