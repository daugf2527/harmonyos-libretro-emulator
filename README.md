# HarmonyOS Libretro 前端（new_arch）

> 以仓库代码现状为准（更新日期：2026-02-06）。

## 项目定位

本项目已经从最初的 Drawing + XComponent 双缓冲示例，演进为一个可运行在 HarmonyOS 手机上的 **Libretro Frontend**：

- ArkTS/ArkUI 负责 UI 与交互
- C++ `libentry.so` 负责引擎、渲染、音频、输入桥接
- 通过 XComponent + NativeWindow 承载视频输出
- 通过 NAPI 暴露 `refactored*` 系列接口给 ArkTS

当前主线架构是 `new_arch (LibretroEngine + VideoPipeline)`。

## 架构总览（线程与调用链）

```text
[ArkTS/UI 线程]
页面调用 refactoredStartEngine/refactoredLoadCore/refactoredLoadRom
  -> NAPI (entry/src/main/cpp/app/napi/libretro_engine_napi.cpp)
  -> LibretroEngine 消息队列

[XComponent 回调线程]
Surface Created/Changed
  -> PluginManager 回调到 LibretroEngine::SetNativeWindow / OnNativeWindowResized

[Engine 线程]
LibretroEngine::GameLoop
  -> HandleMessage(Start/LoadCore/LoadRom/...)
  -> core_loader 装载 core 并绑定 libretro 回调
  -> retro_run 循环
  -> OnVideoRefresh -> VideoPipeline::Render (CPU/GLES/HW)
  -> audio_sample_batch -> AudioBridge

[音频回调线程]
OHAudio 回调从 RingBuffer 读数据，不足时补静音

[事件回传]
C++ EventBridge -> ArkTS LibretroEventHub
事件包括 core_crash/fps_update/audio_status/geometry_update/engine_state
```

## 目前已落地能力

### 1) 引擎与生命周期

- 独立引擎线程 + 消息队列状态机（INIT/LOADING/RUNNING/PAUSED/ERROR 等）
- 同步/异步停机（`refactoredStopEngine` / `refactoredStopEngineAsync`）
- 游戏切换接口 `refactoredSwitchGameAsync(...)`，支持 token 防抖与并发切换保护
- 最近错误查询与清理（`refactoredGetLastErrorInfo` / `refactoredClearLastErrorInfo`）

### 2) 视频渲染

- `VideoPipeline` 三模式：
  - `0` Hardware Scaling
  - `1` Software Scaling
  - `2` GLES Scaling（默认）
- 支持 `SET_PIXEL_FORMAT`、`SET_GEOMETRY`、dupe/null frame 处理
- HW Render 环境协商能力：
  - OpenGL ES HW context
  - Vulkan negotiation/interface（含 swapchain 重建与 out-of-date 处理）
- ArkTS 可动态切换：缩放模式、软件缩放最大分辨率、是否允许 HW Render

### 3) 音频链路

- `AudioBridge` + OHAudio 低时延播放
- 音频重采样/缓冲占用统计/underrun-overrun 指标
- 最小音频延迟配置（core 在 `retro_run` 上下文可请求）
- `audio_status` 事件回传到 ArkTS

### 4) 输入系统

- 数字按键：`refactoredSendInput`
- 模拟摇杆：`refactoredSendAnalog`
- 传感器：`refactoredSendSensor`
- 端口映射：`refactoredAssignPortSource` / `refactoredUnassignPort`
- 输入设备枚举与调试统计：`refactoredListInputDevices` / `refactoredGetInputDebugStats`

### 5) 状态与核心控制

- Save State：`refactoredGetSaveStateSize` / `refactoredSaveState` / `refactoredLoadState`
- SRAM：`refactoredGetSRAM` / `refactoredSetSRAM`
- Core Option：`refactoredGetCoreOptions` / `refactoredSetCoreOption`
- Cheat、Disk Control、Region、AVInfo、Runtime Stats 均已暴露

## UI 页面与使用场景

`entry/src/main/resources/base/profile/main_pages.json` 当前包含：

- `pages/Index`：主页入口
- `pages/CoreLoaderTest`：核心加载测试
- `pages/TestGambatte`：Gambatte 测试页面
- `pages/LibretroGamePage`：通用多核心游戏页面（主使用页面）
- `pages/LibretroNewArchTestPage`：新架构调试/验证页面

其中 `LibretroGamePage` 已内置多核心列表、ROM 自动匹配规则、压测（Soak）与核心符号验证入口。

## 核心与 ROM 资源现状

### Core `.so`

- 目录：`entry/libs/arm64-v8a/`
- 仓库中已包含多种 core（如 Gambatte、Nestopia、FCEUmm、Snes9x、mGBA、melonds、FBNeo、MAME2010、PCSX-ReARMed 等）
- 实际可用性依赖设备能力、core 本身、ROM 资源完整性

### ROM

- 内置 rawfile 目录：`entry/src/main/resources/rawfile/roms/`
- 现有子目录按平台分组（如 `gb_gbc/`、`gba/`、`nes/`、`snes/`、`md/`、`arcade/`、`nds/`）
- `LibretroGamePage` 会扫描 `roms/` 并按扩展名规则自动映射可用核心

## 快速运行

1. 使用 DevEco Studio 打开工程。
2. 对 `entry` 模块执行 Build / Run（`module.json5` 当前 deviceTypes 为 `phone`）。
3. 进入 `Index` 页面，优先从 `LibretroGamePage` 或 `LibretroNewArchTestPage` 开始。
4. 选择核心与 ROM，启动后通过事件面板/日志观察运行状态。

## 对开发者的重要约束

- 官方优先：不确定行为时，以 HarmonyOS 官方文档与 `libretro.h` 为准
- NativeBuffer 像素访问需走 `OH_NativeBuffer_FromNativeWindowBuffer + Map/Unmap` 流程
- 跨线程共享状态必须显式加锁（`std::mutex + std::lock_guard`）
- 旧架构已归档到 `deprecated/legacy/`，默认不参与新功能演进

## 目录速览

```text
entry/src/main/cpp/
  app/                 NAPI 导出、XComponent 回调桥接
  core/                LibretroEngine、VideoPipeline、env/core loader
  platform/            audio/graphics/resource/sync/xcomponent 适配
  interfaces/          抽象接口定义
  tests/               C++ 集成/单元辅助（非独立自动测试框架）
  types/libentry/      ArkTS 类型声明（index.d.ts）

entry/src/main/ets/
  pages/               主页、测试页、通用游戏页
  components/          虚拟手柄、折叠屏布局组件
  common/              EventHub、日志、切换协调器
  config/              模拟器元配置

entry/src/main/resources/
  rawfile/roms/        内置 ROM 资源
```

## 已知限制

- HW Render 相关能力已接入，但不同 core/设备组合的稳定性和性能差异仍较大
- 多核心不等于全部“可玩”，高负载平台受设备能力与系统限制影响明显
- 发布前仍需按目标设备做专项稳定性验证（切换、后台前台、旋转、长时运行）

---

如需查看实现细节，优先阅读：

- `entry/src/main/cpp/core/engine/libretro_engine.h`
- `entry/src/main/cpp/core/engine/video_pipeline.h`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`
