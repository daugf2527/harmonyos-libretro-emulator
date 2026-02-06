剩余问题清单（按严重度）

高
- 渲染管线职责分裂 (Schizophrenic Rendering Path) - **进行中（阶段一/二已完成，验证未完成）**
  - 根因：HW Render 核心（EGL/Vulkan）由 `LibretroEngine` 直接管理，而 SW Render 核心由 `VideoPipeline` 管理。导致 `LibretroEngine` 代码膨胀，且两套渲染逻辑的上下文管理代码高度重复却又物理分离，维护成本极高。
  - 已完成：HW Render 上下文管理下沉至 `VideoPipeline`；引入 `IRenderBackend` 统一渲染抽象；`WindowStateManager` 统一窗口状态设置路径。
  - 待解决：架构级验证（Vulkan 实机验证/窗口复用场景验证）；接口抽象缺失仍独立问题。
  - 证据：`entry/src/main/cpp/core/engine/video_pipeline.h`，`entry/src/main/cpp/core/engine/video_pipeline.cpp`，`entry/src/main/cpp/core/engine/window_state_manager.h`



中
- GetVariable 接口重入风险 - **已修复（待验证）**
  - 根因：`EnvState::GetVariable` 使用 `static thread_local` 字符串缓冲区来存储返回值。若核心开发者在同一行代码中多次调用该接口（如 `printf("%s %s", get("A"), get("B"))`），所有返回值都会指向同一个缓冲区，导致内容被覆盖。
  - 解决：改为 TLS 多槽位缓存，避免同一行多次调用覆盖。
  - 证据：`entry/src/main/cpp/core/libretro/env_dispatcher.cpp`（TLS 多槽位）。
- CanSendVirtual 逻辑仅检查 inputPortRouter_ 存在性，未校验具体的 Port 映射状态
  - 根因：`LibretroEngine::CanSendVirtual` 实现过于简单，未能真实反映该端口是否支持虚拟按键输入。
  - 待解决：完善 `InputPortRouter` 校验逻辑。
  - 证据：`entry/src/main/cpp/core/engine/libretro_engine.cpp:660`
- Vulkan Swapchain Resize 频繁重建风险 - **已修复（待验证）**
  - 根因：`OnNativeWindowResized` 中同步触发 `RecreateSwapchain`，在分屏/窗口拖拽等连续 Resize 场景下可能导致 Swapchain 频繁销毁重建，引发闪烁或驱动崩溃。
  - 解决：引入 200ms 去抖动重建策略（Vulkan swapchain recreate 节流）。
  - 证据：`entry/src/main/cpp/core/engine/video_pipeline.cpp`（`RecreateVulkanSwapchain` 去抖）。
- 接口定义严重缺失 (Severe Lack of Interface Abstractions) - **进行中（核心接口已落地，渲染绑定待完善）**
  - 根因：`interfaces` 目录虽然存在，但核心抽象严重不足。缺少 Input, VFS, Logger, Configuration 等关键抽象。
    - **Input**: `interfaces/input` 目录为空。无法抽象手柄、触摸屏或物理键盘，`InputManager` 高度耦合。
    - **VFS**: 缺乏 `IVirtualFileSystem`，直接依赖具体文件路径，无法支持高级 ROM 加载（如 Zip/7z 或网络流）。
    - **Logger**: 缺乏 `ILogger`，直接依赖 `hilog`，无法灵活切换日志后端。
    - **Config**: 缺乏 `IConfiguration`，配置分散在各个类中。
    - **Renderer**: `interfaces/graphics/i_renderer.h` 存在但未被使用（GLES 渲染器直接作为具体类嵌入），属于 Dead Code。
  - 后果：代码耦合度极高，单元测试困难（无法 Mock I/O），跨平台移植成本巨大（需要修改大量具体实现文件）。
  - 已完成：新增 Logger/VFS/Configuration 接口与默认实现；CoreOptionsRegistry 走配置接口；PlatformResourceManager 落地 VFS 读取；InputManager 实现 IInputManager 且 NAPI 走接口；IRenderer 适配层落地并由 NAPI 调用。
  - 待解决：IRenderer 的渲染生命周期尚未与引擎渲染线程绑定（Initialize/Render/OnSurfaceChanged 为占位适配）；`i_renderer.h` 是否保留需确认。
  - 证据：`entry/src/main/cpp/interfaces/diagnostics/i_logger.h`、`entry/src/main/cpp/interfaces/vfs/i_virtual_file_system.h`、`entry/src/main/cpp/interfaces/config/i_configuration.h`。
- ROMLoader 的内存拷贝风暴 (Memory Copy Storm)
  - 根因：`ROMLoader::LoadFromRawFile` 使用 C 风格的 `OH_ResourceManager_ReadRawFile` 读取到 `std::vector`，可以避免一次拷贝。但在 `libretro_engine_napi.cpp` 中，为了将数据传给 `LoadGame`，又进行了一次 `shared_ptr` 的封装和潜在的数据移动。如果在 JS 层传递 ArrayBuffer，可能涉及更多次跨语言边界的拷贝。
  - 待解决：优化数据流，支持 Zero-Copy 传递（若 NAPI 允许）或减少不必要的 `vector` 构造。
  - 证据：[已验证] entry/src/main/cpp/app/napi/libretro_engine_napi.cpp:166 - 存在 vector 到 shared_ptr 的不必要封装和潜在拷贝。
- PluginManager 输入映射硬编码 (Hardcoded Input Mapping)
  - 根因：`plugin_manager.cpp` 中的 `MapKeyCodeToJoypad` 和 `DispatchTouchEvent` 将 HarmonyOS 的键值/触控直接硬编码映射到 Retropad 按钮。
  - 后果：用户无法自定义按键布局，无法支持不同的手柄通过蓝牙连接（除非映射碰巧一致）。不仅丧失了模拟器的灵活性，也无法适配不同操作习惯的用户。
  - 待解决：实现可配置的 Input Mapper，从 ArkTS 传递键位配置表到 C++ 层。
  - 证据：[已验证] entry/src/main/cpp/app/framework/plugin_manager.cpp:140 - MapKeyCodeToJoypad 使用硬编码 Switch-Case 映射键值。
- PluginManager 滥用静态局部变量存储状态 (Abuse of Static Local Variables)
  - 根因：`NewArchMouseDown`, `NewArchHasFocus` 等状态是通过 `static std::atomic<bool>* v = new ...` 这种奇怪的单例模式实现的。
  - 后果：这种“隐形全局变量”导致 `PluginManager` 实际上不可重入，且生命周期管理模糊（虽有 delete 但写得很怪）。如果未来有多个 XComponent 实例（如多窗口并发），这些状态会冲突。
  - 待解决：将这些状态移入 `PluginManager` 类成员变量，或者每个 `XComponent` 实例关联一个 `InputContext`。
  - 证据：`entry/src/main/cpp/app/framework/plugin_manager.cpp:37` (Static atomic allocation).
- CoreOptionsRegistry 手动解析 Config (Manual Config Parsing in CoreOptionsRegistry)
  - 根因：`LoadCoreOptionsConfig` 内部手写了一个简易的 Key-Value 解析器，处理引号、空格和转义字符。
  - 后果：手写解析器通常脆弱，无法处理复杂情况（如值中包含等号、注释嵌套等），且维护成本高。为何不复用 `libretro-common` 的 `config_file` 实现？
  - 待解决：引入标准的 `.opt` 或 `.cfg` 解析库，或复用 RetroArch 的 `config_file.c`。
  - 证据：`entry/src/main/cpp/core/libretro/core_options_registry.cpp:51` (LoadCoreOptionsConfig implementation).
- PlatformResourceManager 职责重叠 (Responsibility Overlap in PlatformResourceManager)
  - 根因：`PlatformResourceManager` 和 `ROMLoader` 都在做 "LoadRawFile" 和 "FileExists" 的事情。且 `ROMLoader` 内部通过 NAPI 传进来的 `NativeResourceManager` 操作，而 `PlatformResourceManager` 又保存了一个全局的 `native_resource_manager_` 指针。
  - 后果：双重实现，逻辑割裂。`ROMLoader` 作为一个“工具类”却承担了过多的资源管理职责，而本该做资源管理的 `PlatformResourceManager` 却被边缘化。
  - 待解决：合并资源加载逻辑。所有 RawFile/FS 操作统一由 `PlatformResourceManager` 负责，`ROMLoader` 只负责校验 ROM 完整性和格式。
  - 证据：`entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:58` vs `entry/src/main/cpp/platform/resource/rom_loader.cpp:68`.

低
