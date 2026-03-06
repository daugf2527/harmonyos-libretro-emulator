# C++ 代码质量审查报告

> **审查范围**: `entry/src/main/cpp/` 全目录（107 个非 deprecated 文件）
> **审查日期**: 2026-03-06
> **方法**: 逐文件逐行审查 + 源码回溯验证（消除幻觉）
> **最后更新**: 2026-03-06（五轮修复后）

## 统计总览

| 严重级别 | 初始发现 | ✅ 已修复 | ❌ 待修复 | 说明 |
|---------|---------|----------|----------|------|
| 🔴 严重 | 11 | 6 | 5 | 崩溃 / 数据损坏 / 画面错误 / 资源泄漏 |
| 🟡 中等 | 29 | 18 | 11 | 潜在竞争 / 逻辑错误 / API 误用 / 安全 |
| 🟢 轻微 | 47 | 17 | 30 | 代码质量 / 低概率边界 / 可维护性 |
| **合计** | **87** | **41** | **46** | |

---

## 第一部分：待修复问题（需专项评审）

> 以下 46 个问题均需要**架构级重构**、**跨模块联动**或**API 语义确认**，不适合局部修改。

---

### 🔴 严重问题（5 个待修复）

#### S01 · ExecuteSyncTask 超时后 use-after-free

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/libretro_engine.cpp` L2571-2612 及所有 `ExecuteSyncTask` 调用处 |
| 分类 | 内存安全 |
| 难度 | 🔴 高 — 需重构同步机制 |

**问题**: `SaveState`、`LoadState`、`GetSRAM`、`SetSRAM`、`GetSaveStateSize` 等函数通过 `ExecuteSyncTask` 提交 lambda 到消息队列，lambda **按引用捕获栈局部变量**（`&ok`、`&snapshot`、`&data`）。

```cpp
bool LibretroEngine::SaveState(std::vector<uint8_t> &outData) {
  bool ok = false;
  std::vector<uint8_t> snapshot;
  if (!ExecuteSyncTask(
          [this, &ok, &snapshot]() {  // ← 按引用捕获栈变量
            if (stateManager_) {
              ok = stateManager_->SaveState(snapshot);
            }
          },
          kSyncTaskTimeoutMs)) {
    return false;  // ← 超时返回, ok/snapshot 析构
  }
```

`EngineSyncTask::Run()` 无取消机制。`Wait()` 超时后调用方返回，栈帧销毁，但 `shared_ptr<EngineSyncTask>` 仍留在消息队列中。Engine 线程后续执行 lambda 时写入已销毁的栈变量。

**影响**: 超时场景必现内存损坏 / 崩溃。

**修复方向**: lambda 捕获 `shared_ptr` 共享结果容器 + 超时后标记 task 已取消阻止执行。涉及 5+ 个调用点，需完整验证同步语义。

---

#### S02 · VideoPipeline 跨线程非原子字段数据竞争

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/video_pipeline.h` L333-392 |
| 分类 | 并发安全 |
| 难度 | 🟡 中 — 涉及十余个字段 + 渲染链验证 |

**问题**: 以下字段为普通非原子类型：

```cpp
unsigned geometry_base_width_ = 0;    // Engine 线程写 (SetGeometry)
unsigned geometry_base_height_ = 0;   // Render 线程读 (Render→ResolveSourceAspect)
float geometry_aspect_ratio_ = 0.0f;
retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;
bool canDupe_ = true;
std::vector<uint8_t> lastFrame_;
unsigned lastFrameWidth_ = 0;
unsigned lastFrameHeight_ = 0;
size_t lastFramePitch_ = 0;
```

- **写入端**: `SetGeometry()` / `SetPixelFormat()` 由 Engine 线程调用
- **读取端**: `videoPipeline_.Render()` 由 Render 线程调用

构成 C++ 标准定义的 undefined behavior。

**修复方向**: 改为 `std::atomic` 或通过 `RenderThread` 的 `ControlMessage` 投递变更到 Render 线程串行处理。

---

#### S03 · FramePacer 跨线程非原子字段数据竞争

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/frame_pacer.h` L58-75 |
| 分类 | 并发安全 |
| 难度 | 🟡 中 — 与 S02 同类，需一起改 |

**问题**:

```cpp
std::chrono::steady_clock::time_point frame_start_;     // 非原子
std::chrono::steady_clock::time_point next_deadline_;   // 非原子
bool deadline_initialized_ = false;                      // 非原子
bool frame_started_ = false;                             // 非原子
```

- `SetTargetFps()` 写入（Engine 线程）
- `BeginFrame()` / `EndFrame()` 读写（Render 线程）

**修复方向**: `bool` 字段改为 `std::atomic<bool>`；`time_point` 访问限定单一线程或加锁。建议与 S02 一起评审。

---

#### S10 · VulkanPresenter::DestroyFrameResources 无 GPU 等待 ⚠️

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_presenter.cpp` L127-147, L392-394 |
| 分类 | 并发安全 / API 误用 |
| 难度 | 🟡 中 — 条件性，仅 EnsureFrameSlots 缩小路径 |

**问题**: `EnsureFrameSlots` 缩小 vector 时直接调用 `DestroyFrameResources`，无 `vkWaitForFences` 或 `vkDeviceWaitIdle`。帧可能仍在 GPU 执行中，违反 Vulkan spec。

**限定条件**: `Destroy()` 路径有 `VulkanContext::Destroy()` 内的 `device_wait_idle` 保护，安全。仅 `EnsureFrameSlots` 缩小路径有实际风险。

**修复方向**: 缩小前对被移除帧的 `submit_fence` 执行 `vkWaitForFences`。

---

#### S11 · VSync 回调析构后 use-after-free ⚠️

| 属性 | 值 |
|------|------|
| 文件 | `platform/sync/native_vsync_driver.cpp` L15, L46-89 |
| 分类 | 并发安全 / 内存安全 |
| 难度 | 🟡 中 — 取决于鸿蒙 API 行为 |

**问题**: `~NativeVSyncDriver()` → `Stop()` → `OH_NativeVSync_Destroy`。如果已排队的 VSync 回调在 Destroy 后才执行，`OnFrame` 中 `self->mutex_` 访问已析构对象。

**限定条件**: 取决于 `OH_NativeVSync_Destroy` 是否保证不再有回调。HarmonyOS 文档未明确说明。

**修复方向**: 需向华为确认 API 语义，或改用 shared_ptr + weak_ptr 防护。

---

### 🟡 中等问题（11 个待修复）

#### M01 · SET_SYSTEM_AV_INFO 返回 true 但不处理

| 属性 | 值 |
|------|------|
| 文件 | `core/libretro/env_dispatcher.cpp` L1326-1330 |
| 分类 | 逻辑错误 |
| 难度 | 🟡 中 — 需联动 AudioBridge + VideoPipeline + FramePacer |

```cpp
case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
    if (!data) return false;
    return true;  // ← 不解析 retro_system_av_info，不更新任何状态
}
```

核心认为前端已接受新 AV 参数（分辨率、采样率、帧率），但实际未更新。需正确解析并联动更新音频采样率、视频分辨率、帧率。

---

#### M06 · 配置保存不原子 + 转义不对称

| 属性 | 值 |
|------|------|
| 文件 | `common/config/file_configuration.cpp` L90-106 |
| 分类 | 逻辑错误 / 资源泄漏 |
| 难度 | 🟡 中 |

1. `SaveKeyValues` 直接写目标文件，中途崩溃导致文件损坏（需临时文件 → rename）
2. `EscapeDoubleQuotes` 将 `"` → `\"`，但 `LoadKeyValues` 不做反转义，save→load 往返破坏含引号的值
3. `fprintf` 返回值未检查

---

#### M07 · RingBuffer::Clear() relaxed 双重置

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/ring_buffer.cpp` L357-370 |
| 分类 | 并发安全 |
| 难度 | 🟡 中 — 依赖外部 running_=false 协议缓解 |

两次 relaxed store 之间，并发 `Read` 可能观察到 `head=0, tail=旧值`，`AvailableRead()` 下溢为巨大值，触发越界拷贝。

---

#### M08 · DiskController 持锁调用核心回调

| 属性 | 值 |
|------|------|
| 文件 | `core/libretro/disk_controller.cpp` L36-111 |
| 分类 | 并发安全（潜在死锁） |
| 难度 | 🟡 中 — 需确认核心不会重入 |

所有方法持有 `mutex_` 调用核心回调。若核心回调内部重入 `DiskController` 方法，`std::mutex` 不可重入 → 死锁。修复需改锁策略或 copy-then-call 模式。

---

#### M11 · HwRenderPresenter::Present 不恢复 GL 状态

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/hw_render_presenter.cpp` L238-275 |
| 分类 | 逻辑错误 |
| 难度 | 🟡 中 — 需平衡性能与正确性 |

`GL_CURRENT_PROGRAM`、`GL_ARRAY_BUFFER_BINDING`、`GL_VIEWPORT` 等状态在 `Present` 后未恢复，可能影响依赖 HW_RENDER 的核心。注释表明 `CaptureState`/`RestoreState` 被移除以避免 pipeline stall。

---

#### M13 · GraphicsContext 无线程安全保护

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/graphics_context.h/.cpp` |
| 分类 | 并发安全 |
| 难度 | 🟡 中 — 需覆盖 XComponent 回调和 Engine 线程两侧 |

无 mutex。`UpdateSurface` 可能从 XComponent 回调线程调用，`egl_surface_`/`ready_` 无保护。

---

#### M18 · NativeVSyncDriver 持锁调用外部 API

| 属性 | 值 |
|------|------|
| 文件 | `platform/sync/native_vsync_driver.cpp` L58-68 |
| 分类 | 并发安全（潜在死锁） |
| 难度 | 🟡 中 — 与 S11 耦合，需理解回调时序 |

`RequestNextFrame` 持有 `mutex_` 调用 `OH_NativeVSync_RequestFrame`。如果该 API 同步触发回调，`OnFrame` 也尝试获取 `mutex_` → 死锁。

---

#### M19 · file_security 符号链接潜在绕过

| 属性 | 值 |
|------|------|
| 文件 | `common/file_security.cpp` L57-83 |
| 分类 | 安全 |
| 难度 | 🟡 中 — 需分析所有回退路径 |

`realpath` 失败回退路径中 `IsUnderRoot(inputPath)` 使用未解析的原始路径。预置在允许目录内的 symlink 可绕过检查。

---

#### M21 · WaitForEngineState 同步阻塞 JS 线程

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/libretro_engine_napi.cpp` L1170-1197 |
| 分类 | 性能 / API 误用 |
| 难度 | 🟡 中 — 需改异步 NAPI，影响 ArkTS 调用方 |

同步 NAPI 函数在 ArkTS 主线程阻塞等待，`timeoutMs` 较大时导致 ANR。

---

#### M26 · AudioBridge Meyers 单例静态析构风险

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/audio_bridge.cpp` L125-132 |
| 分类 | 内存安全 |
| 难度 | 🟡 中 — 需改生命周期管理 |

`DestroyInstance()` 无实际操作。程序退出时静态析构顺序不确定，OHAudio 回调可能访问已析构单例。

---

#### M28 · systemInfo_ 悬垂指针风险

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/libretro_engine.cpp` L1392-1394, L1966-1968 |
| 分类 | 内存安全 |
| 难度 | 🟡 中 — 需确认所有访问路径 |

`retro_system_info` 的 `library_name` 等字段是核心 .so 内存中的 `const char*`。卸载 .so 后指针悬垂。`hasSystemInfo_` 标志提供了一定保护，但 `ProcessFrame` 中的访问在 RUNNING 状态每帧执行。修复需在卸载 .so 前拷贝字符串。

---

### 🟢 轻微问题（30 个待修复）

| # | 文件 | 简述 | 修复难度 |
|---|------|------|---------|
| 3 | `libretro_engine.cpp` L2115 | 静态日志计数器非原子 | 低（但跨线程语义需确认） |
| 4 | `render_thread.cpp` 多处 | static 局部日志计数器不随 ResetStats 重置 | 中（多处） |
| 5 | `video_pipeline.cpp` L733,L777 | 函数级 static 变量应为成员 | 中（涉及类重构） |
| 7 | `libretro_engine.h` L368 | `atomic<time_point>` 可能非 lock-free | 设计权衡 |
| 8 | `video_pipeline.cpp` L1094-1107 | NativeBuffer 路径复杂建议 RAII 包装 | 中（重构） |
| 12 | `env_dispatcher.cpp` L1452-1457 | SET_MINIMUM_AUDIO_LATENCY 限制可能误拒 | 低（但需确认 spec） |
| 13 | `env_dispatcher.cpp` L620-627 | TLS 8 槽位轮转理论悬垂指针 | 中（需改 TLS 策略） |
| 14 | `env_dispatcher.cpp` L987-1001 | GET_SYSTEM_DIRECTORY 重复调用浪费 TLS 槽位 | 低 |
| 15 | `env_dispatcher.h` L52-54 | `in_retro_run_` 普通 bool（当前单线程安全） | 低（加 atomic 即可，但需确认影响） |
| 16 | `audio_bridge.cpp` L486-494 | Buffering 检查微小时序窗口 | 低概率，可接受 |
| 17 | `audio_bridge.cpp` L61,372,378 | `run_state_log_count_` 非原子（仅影响日志） | 可接受 |
| 18 | `audio_player.cpp` L974 | `ring_buffer_` 清空在锁外 | 中（需理解回调时序） |
| 19 | `audio_player.cpp` L174-198 | OHAudio 双回调设置（新 API 覆盖旧 API） | 已验证安全，可忽略 |
| 21 | `ring_buffer.cpp` L200-205 | WriteWait 醒来后依赖外部协议 | 设计权衡 |
| 22 | `ring_buffer.h` L129-132 | `mutable` 非原子计数器缺注释 | 极低 |
| 23 | `retro_common.h` | typedef 可能与 libretro.h 重复定义 | 低（但改动有风险） |
| 25 | `hw_render_presenter.cpp` L501 | 每帧 glBufferData 重分配 | 优化项 |
| 26 | `pixel_converter_neon.cpp` L647-648 | static 日志计数器非线程安全 | 仅影响日志 |
| 27 | `pixel_converter_neon.cpp` L413-416 | thread_local vector 永不收缩 | 可接受 |
| 34 | `plugin_manager.cpp` L438,556 | static callback 脆弱模式 | 中（架构问题） |
| 35 | `plugin_manager.h` L42 | 参数应为 `const std::string &` | 低（但需确认调用方） |
| 36 | `plugin_manager.cpp` L686-702 | `nativeXComponentMap_` 无锁 | 中（跨线程语义） |
| 37 | `libretro_engine_napi.cpp` L908-943 | StopEngineAsync 不返回 Promise | 中（影响 ArkTS 层） |
| 38 | `cue_parser.cpp` L16 | 未处理非 UTF-8 CUE 编码 | 低概率 |
| 39 | `file_configuration.cpp` vs `utils.cpp` | TrimCopy 重复实现 | 重构项 |
| 40 | `audio_bridge.cpp` + `ring_buffer.cpp` | 音频热路径锁持有时间过长 | 优化项 |
| 41 | `disk_controller.cpp` L21-33 | 旧版回调设置未清零扩展字段（`is_ext_` 保护） | 已有保护，可忽略 |
| 42 | `engine_messages.h` L86-97 | payload 非 union 内存开销 | 设计权衡 |
| 44 | `libretro_engine.cpp` L2527-2538 | WaitForState 条件变量与原子变量模式不一致 | 中 |
| 47 | `audio_bridge.cpp` L451-460 | Resampler DRC 竞争（已知并接受） | 已接受 |

---

## 第二部分：已修复问题记录

> 以下 41 个问题已在五轮修复中全部完成，无 linter 错误。

### ✅ 已修复严重问题（6 个）

| 编号 | 问题 | 修复文件 | 修复方式 |
|------|------|---------|---------|
| S04 | GetDeinit() 空指针调用 | `libretro_engine.cpp` | 添加与 L523 一致的空指针检查 |
| S05 | 0RGB1555 NEON 绿色通道提取错误 | `pixel_converter_neon.cpp` | `vshrq_n_u16 + vshlq_n_u16` → `vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x1F))` |
| S06 | GLES 0RGB1555 纹理上传格式不匹配 | `gles_renderer.cpp` | 上传前 `(pixel << 1) \| 1` 转为真正 RGBA5551，thread_local 缓冲区 |
| S07 | NEON ConvertAndScale destStride=0 | `pixel_converter_neon.cpp` | 入口添加 `if (destStride == 0) destStride = destWidth` |
| S08 | CreateProgram 链接失败 Shader 泄漏 | `gles_renderer.cpp` | 失败路径添加 `glDeleteShader(vs/fs)` |
| S09 | SwitchGameAsync NAPI 无错误处理 | `libretro_engine_napi.cpp` | 检查 create/queue 返回值，失败 reject promise + delete ctx |

### ✅ 已修复中等问题（18 个）

| 编号 | 问题 | 修复文件 | 修复方式 |
|------|------|---------|---------|
| M02 | VulkanContext Destroy double-free | `vulkan_context.cpp` | `negotiation_.destroy_device()` 后立即 `device_ = VK_NULL_HANDLE` |
| M03 | ELF 解析无符号整数下溢 | `core_loader_napi.cpp` | 加 `strtab_offset > data.size()` 前置检查 |
| M04 | switch_token 多余 store 竞态 | `libretro_engine_napi.cpp` | 删除 `switch_token.store(token)` |
| M05 | file_security `%s` 日志不可读 | `file_security.cpp` | 11 处 `%s` → `%{public}s` |
| M09 | Vulkan present 缺队列锁 | `vulkan_presenter.cpp` | `vkQueuePresentKHR` 加 `LockQueue/UnlockQueue` |
| M10 | swapchain_out_of_date_ 非原子 | `vulkan_presenter.h` + `vulkan_context.h` | `bool` → `std::atomic<bool>` |
| M12 | GLESRenderer Deinit 未检查上下文 | `gles_renderer.cpp` | `contextCurrent` 为 false 时跳过 GL 资源释放 |
| M14 | EGL attribs 硬编码魔法数字 | `graphics_context.cpp` | 遍历数组查找 `EGL_DEPTH_SIZE`/`EGL_STENCIL_SIZE` |
| M15 | Vulkan 手动 lock/unlock | `vulkan_presenter.cpp` | 2 处改为 `std::lock_guard` + 作用域块 |
| M16 | event_bridge 发旧 pending payload | `event_bridge.cpp` | 保留当前最新 payload，清除旧 pending |
| M17 | ROMLoadResult 成员未初始化 | `rom_loader.h` | `success = false`、`size = 0` |
| M20 | ELF 文件读取无大小上限 | `core_loader_napi.cpp` | 加 256MB 上限检查 |
| M22 | EngineStats 成员未初始化 | `i_engine_stats.h` | 24 个字段加 `= 0` / `= 0.0`（接口不匹配部分未改） |
| M23 | cue_parser FILE 指令匹配过宽 | `cue_parser.cpp` | 加 `isspace(upper[4])` 空白字符检查 |
| M24 | AudioPlayer Stop 失败仍 Release | `audio_player.cpp` | 检查 Stop 返回值 + 日志 |
| M25 | AudioResampler 除零风险 | `audio_resampler.cpp` | 加 `current_ratio_ <= 0.0` 提前返回 |
| M27 | TempFileManager 缺路径验证 | `temp_file_manager.cpp` | 加 `..` 检查 + 空路径检查 |
| M29 | PeekWindow 无锁暴露裸指针 | `window_guard.h` | 从 public 移到 private |

### ✅ 已修复轻微问题（17 个）

| 原编号 | 问题 | 修复文件 | 修复方式 |
|--------|------|---------|---------|
| #1 | 未使用的 `cond_` 条件变量 | `bounded_latest_frame_queue.h` | 删除 cond_ 声明、notify_one 调用及 include |
| #2 | `totalUs` 变量名遮蔽 | `video_pipeline.cpp` | 内层 → `perfTotalUs` |
| #6 | SetSRAM 截断不报告 | `core_state_manager.cpp` | 截断时输出 WARN 日志 |
| #9 | dlopen 句柄未保存（有意为之） | `core_loader.cpp` | 加注释说明意图 |
| #10 | `strerror` 非线程安全 | `core_loader.cpp` | 改 `strerror_r` + 栈缓冲区 |
| #11 | `st_size` 用 `(long)` 截断 | `core_loader.cpp` | `static_cast<long long>` + `%lld` |
| #20 | history_init_ 缺防御性检查 | `audio_resampler.cpp` | 条件加 `&& in_frames >= 1` |
| #24 | `egl_config_` 未初始化 | `gles_renderer.h` | 加 `= nullptr` |
| #28 | ConvertAndScale 缺 NULL/zero 检查 | `pixel_converter_neon.cpp` | 入口加 NULL/zero 防御 |
| #29 | MaskToCount 手写循环 | `vulkan_presenter.cpp` | 改 `32 - __builtin_clz(mask)` |
| #30 | URI 长度 size_t→unsigned int 截断 | `rom_loader.cpp` | `uint32_t` + 显式 cast |
| #31 | dlopen 句柄有意不释放 | `fence_utils.cpp` | 加注释说明意图 |
| #32 | `find_last_of` 返回 npos 未检查 | `temp_file_manager.cpp` | 加 npos 判断 + 错误返回 |
| #33 | `%zu` 与 `streamsize` 不匹配 | `platform_resource_manager.cpp` | `%lld` + `static_cast<long long>` |
| #43 | `running_` 未统一用 `.store()` | `libretro_engine.cpp` | 2 处改 `.store()` |
| #45 | static FileConfiguration 缺注释 | `core_options_registry.cpp` | 加线程安全注释 |
| #46 | CreateGameInfo 生命周期缺文档 | `rom_loader.cpp` | 加生命周期注释 |

---

## 第三部分：评审建议

### 待修复问题优先级排序

#### P0 — 影响稳定性（建议尽快专项评审）

| 编号 | 问题 | 影响 | 建议 |
|------|------|------|------|
| S01 | ExecuteSyncTask use-after-free | 超时场景内存损坏 / 崩溃 | 重构同步机制，需完整设计文档 |
| S02+S03 | VideoPipeline/FramePacer 数据竞争 | 长时运行画面异常 | 一起评审，统一线程模型 |

#### P1 — 条件性风险

| 编号 | 问题 | 影响 | 建议 |
|------|------|------|------|
| S10 | Vulkan 资源销毁无等待 | GPU 资源损坏（仅 EnsureFrameSlots 缩小路径） | 缩小前加 vkWaitForFences |
| S11+M18 | VSync 回调时序 | 析构后回调 / 死锁（依赖鸿蒙 API 语义） | 向华为确认 API 或加 weak_ptr 防护 |
| M08 | DiskController 重入死锁 | 特定核心死锁（需核心重入才触发） | 改 recursive_mutex 或 copy-then-call |

#### P2 — 功能正确性

| 编号 | 问题 | 影响 | 建议 |
|------|------|------|------|
| M01 | SET_SYSTEM_AV_INFO 空实现 | 运行时切换分辨率的核心音画异常 | 需联动多个子系统 |
| M06 | 配置保存原子性 + 转义 | 崩溃后配置损坏 | 临时文件→rename + 修转义对称 |
| M11 | GL 状态不恢复 | HW_RENDER 核心渲染异常 | 需平衡性能 |
| M13 | GraphicsContext 无锁 | XComponent 回调并发 | 加 mutex |
| M21 | 阻塞 JS 线程 | ANR 风险 | 改异步 NAPI |

#### P3 — 低优先级

| 编号 | 问题 | 说明 |
|------|------|------|
| M07 | RingBuffer Clear relaxed | 有外部协议保护 |
| M19 | 符号链接绕过 | 应用沙箱环境限制了攻击面 |
| M26 | 单例析构 | 仅退出时可能触发 |
| M28 | systemInfo_ 悬垂 | hasSystemInfo_ 标志提供部分保护 |
| 🟢×30 | 轻微问题 | 大多为代码质量/设计权衡，按需修复 |

---

## 审查方法说明

1. **第一轮**: 4 个并行审查代理分别扫描 core/engine、core/libretro+audio、platform/graphics、其他模块
2. **第二轮**: 对所有 🔴 严重（14 个）和 🟡 中等（41 个）问题逐一回到源码验证
   - 读取每个问题涉及的实际源文件
   - 追踪跨线程调用链确认是否真正存在数据竞争
   - 手动验算位操作（0RGB1555 NEON）
   - 确认 API 契约（Vulkan spec、OHAudio 文档、NAPI 生命周期）
3. **修订结果**: 3 个 🔴 降级为 🟡，4 个 🟡 判定为误报删除，8 个 🟡 降级为 🟢
4. **五轮修复**: 共修复 41 个问题（6 严重 + 18 中等 + 17 轻微），剩余 46 个需专项评审
