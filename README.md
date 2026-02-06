# HarmonyOS Libretro 前端（new_arch）

## 简介

本仓库已从“Drawing + XComponent 双缓冲示例”演进为 **HarmonyOS 上的 Libretro 前端**。
当前主线为 **new_arch（LibretroEngine + VideoPipeline）**，通过 XComponent 获取 NativeWindow，完成核心加载、音视频输出、输入与事件回传。

## 当前能力（以代码为准）

- 引擎主线：`LibretroEngine` + `VideoPipeline`（独立线程驱动、消息队列调度）
- 渲染路径：CPU / GLES 缩放三模式（Hardware/Software/GLES）
- 音频：`AudioBridge` + OHAudio 低时延播放 + 重采样 + DRC
- 输入：虚拟手柄 / 键盘 / 触控 / 指针映射到 Libretro 输入
- 事件回传：fps/geometry/audio_status/core_crash 等事件统一回传 ArkTS
- 调试/验证：Soak 测试、运行时统计、核心选项读取/设置

## 当前已验证内容

- 核心：Gambatte（`libgambatte_libretro.so`）
- ROM：`entry/src/main/resources/rawfile/roms/` 内置 ROM
- 入口页面：`pages/LibretroGamePage`、`pages/LibretroNewArchTestPage`

## 运行方式

- 使用 DevEco Studio 对 `entry` 模块执行 **Build / Run**。
- 核心 `.so` 放置位置：`entry/libs/arm64-v8a/`（设备侧路径由系统打包处理）。
- ROM 可来自：
  - rawfile（`roms/...`）
  - 沙箱路径（需满足 `file_security` 白名单）

## 工程目录（与当前代码一致）

```
├──entry/src/main/cpp
│  ├──app                      // NAPI 导出与 XComponent 回调
│  ├──core                     // libretro 核心与 new_arch 引擎
│  ├──platform                 // 音频/图形/资源适配
│  ├──common                   // 通用工具与安全校验
│  ├──interfaces               // 接口抽象
│  ├──tests                    // 集成/单元测试（当前未纳入构建）
│  └──types/libentry           // NAPI 类型定义
├──entry/src/main/ets
│  ├──pages                    // 入口页/测试页/游戏页
│  ├──components               // 虚拟手柄与折叠屏布局
│  ├──common                   // 日志/EventHub/切换协调器
│  └──config                   // 模拟器配置（机型参数）
├──entry/src/main/resources
│  └──rawfile/roms             // 内置 ROM
└──Roadmap.md                  // 里程碑与规划
```

## 已知限制

- HW_RENDER 接口链路尚未完整（`GET_HW_RENDER_INTERFACE` 仍返回 false）。
- 3D 硬件核心尚未宣称可用；目前以软件核心为主。
- 多核心与 ROM 管理仍在扩展中。

## 其他说明

- 旧架构已归档到 `deprecated/legacy/`，不再作为主线维护目标。
- 本仓库遵循鸿蒙官方文档与 libretro 标准规范。
