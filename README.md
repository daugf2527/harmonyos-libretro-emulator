# HarmonyOS Libretro 前端（new_arch）

> 以仓库代码现状为准（更新日期：2026-02-06）。

## 1. 项目定位

本项目是一个面向 HarmonyOS 手机端的 Libretro 前端，主线架构为 `new_arch`：

- ArkTS/ArkUI：UI、交互、页面状态
- C++ `libentry.so`：引擎、渲染、音频、输入与事件桥
- XComponent + NativeWindow：视频输出承载
- NAPI `refactored*` 接口：ArkTS 与引擎桥接层

目标不是“只跑起来”，而是形成可扩展、可诊断、可恢复的移动端前端工程骨架。

## 2. 文档导航（先读这里）

- 深度白皮书（主文档）：`docs/plans/2026-02-06-new-arch-technical-whitepaper.md`
- 核心模块深链：
  - `LibretroEngine`：`docs/plans/2026-02-06-new-arch-technical-whitepaper.md#libretroengine`
  - `AudioBridge`：`docs/plans/2026-02-06-new-arch-technical-whitepaper.md#audiobridge`
  - `VideoPipeline`：`docs/plans/2026-02-06-new-arch-technical-whitepaper.md#videopipeline`

建议阅读顺序：README（全局） -> 白皮书 `1/2/3`（架构与链路） -> 白皮书 `4`（模块深度）。

## 3. 架构总览（简版）

```text
[ArkTS/UI 线程]
调用 refactored* NAPI
  -> libentry.so

[XComponent 回调线程]
Surface/输入事件
  -> PluginManager
  -> LibretroEngine::SetNativeWindow / OnNativeWindowResized

[Engine 线程]
GameLoop + MessageQueue + StateMachine
  -> retro_run
  -> VideoPipeline::Render
  -> AudioBridge::ProcessAudio

[Audio 回调线程]
OHAudio 从 RingBuffer 读样本播放

[事件回传]
EventBridge (C++) -> LibretroEventHub (ArkTS)
```

## 4. 当前能力（主线）

1. 生命周期与切换
- 独立引擎线程 + 状态机
- `refactoredSwitchGameAsync(...)` 单飞与恢复链路
- 最近错误可查询/清理

2. 渲染
- `VideoPipeline` 三模式（Hardware/Software/GLES）
- PixelFormat/Geometry 动态协商
- GLES 与 Vulkan HW Render 路径

3. 音频
- `AudioBridge` 重采样 + DRC + RingBuffer
- underrun/overrun 统计回传
- 最小音频延迟协商（受 libretro 调用时序约束）

4. 输入与控制
- 按键/模拟摇杆/传感器
- 端口绑定与设备枚举
- SaveState/SRAM/Core Options/Cheat/DiskControl

## 5. 与同类前端的差异（工程视角）

1. 优势
- 前端引擎化：`LibretroEngine` 明确状态机与消息语义，便于恢复与诊断
- 平台适配拆层：`VideoPipeline`、`AudioBridge`、`EventBridge` 职责清晰
- 可观测性较完整：状态、错误、音频、FPS、几何更新都有事件出口

2. 当前短板
- 兼容矩阵仍在收敛：不同 core/设备/HW Render 组合差异明显
- 高负载平台受移动端性能和系统策略约束，难与桌面前端体验等同
- 自动化验证体系仍偏“工程内调试工具”，系统化回归能力需加强

## 6. 快速运行

1. 用 DevEco Studio 打开工程。
2. 选择 `entry` 模块执行 Build / Run。
3. 从 `pages/LibretroGamePage` 或 `pages/LibretroNewArchTestPage` 进入。
4. 选择 core + ROM，观察事件与日志（`hilog`）确认状态。

## 7. 目录速览

```text
entry/src/main/cpp/
  app/                 NAPI 导出、XComponent 桥接
  core/                LibretroEngine、VideoPipeline、env/core loader
  platform/            audio/graphics/resource/sync/xcomponent
  tests/               C++ 集成辅助

entry/src/main/ets/
  pages/               页面入口（Index/Test/LibretroGamePage）
  components/          虚拟手柄、折叠屏布局等
  common/              事件总线、日志、切换协调器
  config/              核心与平台配置
```

## 8. 关键约束（必须遵守）

- 官方优先：不确定行为先查 HarmonyOS 官方文档与 `libretro.h`
- NativeBuffer 像素访问必须 `FromNativeWindowBuffer + Map/Unmap`
- 图形 API 调用只在 Engine 线程执行
- 跨线程共享状态统一锁边界
- `deprecated/legacy/` 不参与主线演进

## 9. 关键代码索引

- `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`
