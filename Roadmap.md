# HarmonyOS Libretro Frontend Roadmap

## 当前阶段

- **集成验证期（Alpha）**：核心加载、音视频、输入、事件回传已跑通，重点转向稳定性/一致性/可恢复。
- **稳定性优先**：切换链路单飞 + 可取消 + 失败恢复为 P0。
- **资源治理优先**：内置/下载 ROM 统一沙盒路径与缓存策略为 P0。
- **渲染策略**：GLES 作为主用路径，Vulkan 保持 Transfer-only 基线并持续验证。

## 已实现（代码落地，未完成全量验证）

- new_arch 引擎线程 + 消息队列驱动
- XComponent 回调桥接（NativeXComponent 模式）
- VideoPipeline 三种缩放模式（Hardware/Software/GLES）
- AudioBridge（OHAudio + 重采样 + DRC）
- 输入快照（joypad/pointer/analog/sensor）
- EventHub 事件回传（fps/audio/geometry/core_crash 等）
- HW_RENDER 线程安全模型（Render/Window 生命周期锁边界）
- Vulkan loader + negotiation 注入 + swapchain 生命周期
- Vulkan Transfer-only 呈现（blit/copy 兜底）
- Vulkan swapchain out-of-date 重建与错误码节流

## 缺口清单（代码层）

> **注意**: 详细问题与修复建议已迁移至 `问题.md`。

### 输入
- 输入快照“analog”入口未打通：存在 SetAnalog，但未暴露 SendAnalog/NAPI 接口
- Input Mapper 缺失：无法自定义键位

### 渲染
- GLES PBO 缺失 (同步上传卡顿)
- HwRender 状态保存冗余 (glGet 严重拖慢)
- Vulkan Sync Stubbed

### 音频
- RingBuffer 非阻塞写入 (导致伪快进)
- Frame Pacing 丢失

## 近期里程碑（P0 / P1）

### M0 切换链路稳定化（P0）
- 状态：进行中
- 目标：Switch 单飞 + 可取消 + 失败恢复，UI 仅发起一次切换请求。
- 验收：高频切换无崩溃、无状态错乱，失败后可自动回到 INIT 并处理最新请求。

### M1 ROM/I-O 治理（P0）
- 状态：部分完成 (Phase 1 完成，Phase 2-3 设计完成但实施 BLOCKED)
- 目标：内置 ROM 按需解包到沙盒；下载 ROM 统一拷贝到沙盒并校验；CUE/多文件依赖稳定。
- 验收：need_fullpath/no-game/大 ROM/CUE 场景可稳定启动且不阻塞 UI 线程。
- 完成内容：
  - ✅ Phase 1: UI 优化与代码收口 (GameCard 性能优化、文档过滤、布局修正)
  - ✅ Phase 2 设计: ROM 沙盒统一策略 (builtin/imported/temp 目录结构)
  - ✅ Phase 3 审计: Library metadata 双 Repository 架构分析
- 待完成：
  - ⚠️ Phase 2 实施: C++/ArkTS 跨层改动 (预计 2-3h，建议作为 M1.2 epic)
  - ⚠️ Phase 3 实施: 双 Repository 合并 (预计 7.5-10.5h，建议作为 M1.3 epic)
- 详见：`docs/plans/2026-05-31-m1-rom-io-closure.md`

### M2 可观测性与错误治理（P0）
- 状态：未开始
- 目标：统一错误分类、步骤码、耗时统计与关键日志上报。
- 验收：每次启动/切换能定位失败阶段与原因，关键耗时可追踪。

### M3 质量保障门禁（P0/P1）
- 状态：未开始
- 目标：核心兼容矩阵 + ROM 类型矩阵 + 长时稳定性跑测。
- 验收：发布前必跑清单与通过门槛明确。

### M4 视频一致性（P1）
- 状态：进行中（代码已实现，需系统验证）
- 目标：`SET_PIXEL_FORMAT/SET_GEOMETRY/GET_CAN_DUPE` 全链路一致。
- 验收：切 core / 切缩放模式后画面与比例正确，dupe 帧策略稳定。

### M5 HW_RENDER 基础闭环（P1）
- 状态：进行中（GLES 稳定性验证中；Vulkan Transfer-only 作为可用兜底）
- 目标：GLES/Vulkan 最小链路稳定，出画可回退。
- 验收：至少 1 个 GLES 核心 + 1 个 Vulkan 核心可稳定出画；swapchain 失效可重建。

### M6 内容与配置（P1）
- 状态：未完成（当前仅 Gambatte + 少量内置 ROM）
- 目标：多核心/多 ROM 管理，核心选项持久化。
- 验收：切换流程稳定，异常可回退，配置可复用。

### M7 交互与多形态（P2）
- 状态：未完成（折叠屏布局组件未接入主页面）
- 目标：折叠屏布局与虚拟手柄交互收敛。
- 验收：单/双/三折态可用，输入稳定。

## 中期与长期（P2+）

- Vulkan 后端与平台特性接入（按需）
- Vulkan 全屏渲染管线（SPIR-V + RenderPass/Pipeline）
- Graphics Accelerate / XEngine 画质增强（按设备能力门控）
- 更完整的核心生态与性能剖析

## 已知限制与风险

- 鸿蒙禁 JIT：3D/高负载核心性能天花板明显，Vulkan 只能解决“出画”，不保证可玩帧率。
- Vulkan 走 Transfer-only：缺少后处理/滤镜能力，画质优化需引入 SPIR-V 管线。
- 资源使用约束：core image 需支持 `TRANSFER_SRC`，swapchain image 需支持 `TRANSFER_DST`。
- 生命周期压力：前后台切换/旋转频繁触发 swapchain 重建，需持续验证稳定性。
- UI 主线程阻塞风险：任何同步 Stop/大 ROM 读取都可能触发卡顿，需要统一异步化与超时治理。
- 多文件依赖风险：CUE/分卷/外部依赖文件若未统一落地到沙盒路径会导致加载失败。

## 参考

- 技术白皮书与官方摘录已迁移至 `鸿蒙开发文档.txt`。

## 代码深度评估报告 (Code Depth Evaluation Report)

### 总体评价
这段代码实现了一个 **"Headless Backend" (无头后端)** 架构：
- **优点**：非常适应 HarmonyOS 的应用开发模式。界面由于高性能的 ArkTS/ArkUI 接管，C++ 层只需要专注于跑核心（Engine）和渲染（Render）。这比 RetroArch 作为一个 "Full OS" 强行接管 UI 要现代化得多。
- **缺点**：**"胶水层" (Glue Layer) 质量堪忧**。`libretro_engine_napi` 和 `plugin_manager` 充斥着临时性的代码、硬编码逻辑和反模式的设计。如果不重构，未来扩展新功能（如蓝牙手柄自定义、多存档槽、金手指UI）会举步维艰。

### 详细对比 (vs RetroArch)

| 维度 | 本项目 (HarmonyOS NAPI) | RetroArch (Libretro Frontend) | 评价 |
| :--- | :--- | :--- | :--- |
| **架构** | **分层清晰但实现潦草**。<br>UI (ArkTS) -> NAPI -> Engine -> Core。<br>思路对，但 NAPI 层成了大杂烩。 | **单体巨石 (Monolithic)**。<br>所有驱动 (Video/Input/Menu) 都在一个大循环里。 | 本项目架构潜力更大，但目前实现只能打 50 分。 |
| **输入 (Input)** | **硬编码 (Hardcoded)**。<br>`plugin_manager.cpp` 直接把键盘 Z/X 映射为 A/B。完全无法通过界面修改。 | **高度可配置 (Autoconf)**。<br>支持成百上千种手柄的自动映射文件 (`.cfg`)。 | **这是目前最大的痛点**。必须引入 Input Mapper。 |
| **状态管理** | **静态变量滥用 (Static Abuse)**。<br>`PluginManager` 里用 `static atomic*` 存鼠标状态，这是 C++ 单例模式的错误示范。 | **结构体传递**。<br>虽然 RA 全局变量也多，但核心状态通常封装在 `rarch_state` 结构体中。 | **差评**。不可重入，多实例会炸。 |
| **异步/并发** | **有设计感**。<br>`SwitchGameAsync` 用 Token 机制处理并发，防止用户狂点导致 Crash。逻辑虽然复杂但很健壮。 | **单线程主导**。<br>切换游戏通常会卡死主界面直到加载完成。 | **好评**。这一点比 RA 处理得优雅。 |
| **扩展性** | **弱**。<br>新增一个功能（如录屏）需要改 NAPI、Framework、Engine 三层代码。 | **强 (插件化)**。<br>通过 Driver 接口扩展。 | 需要引入更多的 Interface 来解耦。 |

### 下一步建议
**修复路线图建议：**
1.  **Stop Bleeding (止血)**: 修复 **Audio RingBuffer (致命)** 和 **Frame Pacing (致命)**。这俩不修，模拟器就是个倍速播放器。
2.  **Performance (性能)**: 修复 **GLES PBO (卡顿)** 和 **HwRender glGet (严重卡顿)**。
3.  **Stability (稳定)**: 重构 NAPI 的 "God Function" 和静态变量滥用。
4.  **Feature (功能)**: 实现 Input Mapper (解决按键硬编码)。
