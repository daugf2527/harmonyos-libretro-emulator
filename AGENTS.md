# Repository Guidelines

> **WARNING: TOP PRIORITY**  
> Default to Chinese responses unless the user explicitly asks for another language.

## 强制规则（与仓库规范同级）
- 官方优先：不确定即查华为鸿蒙官方文档与 libretro 官方标准/`libretro.h`，禁止凭经验猜测 API 行为。
- 文档抓取：华为开发者文档为 SPA，需抓取渲染结果时使用 `firecrawl_scrape`。
- NativeBuffer：访问 NativeWindow buffer 像素内存必须走 `OH_NativeBuffer_FromNativeWindowBuffer` + `OH_NativeBuffer_Map/Unmap` 流程，禁止直接对 BufferHandle 使用 `mmap/munmap`。
- 线程同步：VSync 回调线程与主线程/ArkTS 共享状态必须用 `std::mutex + std::lock_guard` 保护，且同一状态统一锁边界。
- 日志规范：日志域使用 `0xD000-0xFFFF`；重定义前先 `#undef LOG_DOMAIN`；数值日志使用 `%{public}d/%{public}u/%{public}X`。
- ArkTS/NAPI：返回匿名对象必须定义显式 `interface` 类型，避免 `Object/any`；跨语言数值建议 `Number()` 显式转换。
- NativeWindow：避免强制设置 `SET_TIMEOUT=5`；如需设置，使用默认或 >= 1 帧周期。
- 交互偏好：不写测试脚本；不编译/不运行（用户自己执行）。
- 交互要求：若环境提供三术 `mcp4_zhi` 工具，则所有询问/确认通过该工具进行。
- 约定：旧架构（`deprecated/legacy/`）不参与后续检索与代码编辑（除非用户明确要求）。

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
  -> Libretro input_poll/input_state 回调读取 InputSnapshot
```

## Project Structure & Module Organization
- `entry/src/main/ets/`: ArkTS UI and routing (pages, abilities, interfaces).
- `entry/src/main/cpp/`: Native C++ implementation (framework, platform, input, NAPI bindings).
- `entry/src/main/cpp/tests/`: Native test helpers for core loading and ROM checks.
- `entry/src/main/resources/`: App resources, assets, and raw files.
- `AppScope/`: App-level resources and configuration.
- `docs/`, `README*.md`, `Roadmap.md`: Design notes and usage references.
- `entry/build/` and `entry/build-profile.json5`: generated outputs; do not edit by hand.

## Build, Test, and Development Commands
- DevEco Studio: use **Build** / **Run** on the `entry` module to build and deploy the HAP.
- Native library scripts (optional):
  - `./compile_libretro_for_harmonyos.sh`: builds libretro cores using the HarmonyOS NDK path in the script.
  - `./compile_2048_optimized.sh`: builds the 2048 native assets used by the demo.

## Coding Style & Naming Conventions
- Indentation: 2 spaces in both ArkTS and C++ sources.
- C++: prefer `.cpp/.h` with lower_snake filenames (existing convention) and `CamelCase` for types.
- ArkTS: `PascalCase` components, `camelCase` members, and consistent `@Entry`/`@Component` usage.
- No enforced formatter or linter config in repo; match surrounding style and keep logging tags consistent.

## Testing Guidelines
- Tests live under `entry/src/main/cpp/tests/`.
- These are integration helpers invoked from the app or NAPI (not an automated runner).
- Name tests with `test_*.cpp` or `*_test.cpp` and document how to trigger them from the UI or native entry points.

## Commit & Pull Request Guidelines
- Commit history mixes short Chinese summaries and Conventional Commit-style subjects (e.g., `refactor(build): ...`).
- Use a concise, imperative summary; optionally add a `type(scope):` prefix when it helps clarity.
- PRs should include: what changed, how it was validated (device + HarmonyOS version), and screenshots for UI changes.

## Configuration Tips
- Local SDK/NDK paths are machine-specific (see the shell scripts); avoid committing local paths or `entry/build/` artifacts.

## 图形 API 现状（官方文档要点，精简版）
- Vulkan：SDK 支持 v1.4.309，具体可用版本依赖 GPU 驱动；OHOS 扩展支持 OHNativeWindow/OH_NativeBuffer 互操作。
- OpenGL（桌面）：API version 20 支持 OpenGL 3.0，API version 22 支持 OpenGL 4.2；仅明确 PC/部分 Tablet，需 OH_Graphics_QueryGL 判断。
- OpenGL ES：HarmonyOS 支持 OpenGL ES 3.2；扩展需在上下文初始化后通过 glGetString 查询。
- 手机端：OH_Graphics_QueryGL 返回空，不能假设有桌面 OpenGL 3.x，应默认 GLES/Vulkan 路径。
**“所有 EGL/GL 操作只在 Engine 线程执行”**原则，这是移动端图形开发的金科玉律。只要守住这条线，90% 的崩溃都能避免

## 鸿蒙模拟器能力判断（需共识）
- 平台定位：按“移动端 ARM 平台”处理，默认 Egl + OpenGL ES，Vulkan 视设备支持。
- 性能硬约束：系统禁 JIT/dynarec（不是 LLVM 问题），HW_RENDER 只解决“能出画面”，不等于性能可玩。
- 可覆盖范围：8/16 位主机、GB/GBC/GBA、NDS、PS1、街机等可用。
- 不可期待范围：N64/PSP/DC/Saturn 多数只能勉强运行或不可玩；PS2/3DS/GC/Wii 基本不可行（依赖 dynarec）。
- 核心要求：必须具备 GLES/Vulkan 后端，不能只依赖桌面 OpenGL。
