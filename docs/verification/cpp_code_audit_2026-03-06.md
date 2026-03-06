# C++ 代码质量审查报告

> **审查范围**: `entry/src/main/cpp/` 全目录（107 个非 deprecated 文件）
> **审查日期**: 2026-03-06
> **方法**: 逐文件逐行审查 + 源码回溯验证（消除幻觉）

## 统计总览

| 严重级别 | 数量 | 说明 |
|---------|------|------|
| 🔴 严重 | 9 确认 + 2 条件性 | 崩溃 / 数据损坏 / 画面错误 / 资源泄漏 |
| 🟡 中等 | 29 确认 | 潜在竞争 / 逻辑错误 / API 误用 / 安全 |
| 🟢 轻微 | 47 | 代码质量 / 低概率边界 / 可维护性 |

---

## 🔴 严重问题（11 个）

### S01 · ExecuteSyncTask 超时后 use-after-free

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/libretro_engine.cpp` L2571-2612 及所有 `ExecuteSyncTask` 调用处 |
| 分类 | 内存安全 |
| 状态 | ✅ 源码确认 |

**问题**: `SaveState`、`LoadState`、`GetSRAM`、`SetSRAM`、`GetSaveStateSize` 等函数通过 `ExecuteSyncTask` 提交 lambda 到消息队列，lambda **按引用捕获栈局部变量**（`&ok`、`&snapshot`、`&data`）。

```cpp
// libretro_engine.cpp L2581-2590
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

`EngineSyncTask::Run()`（L39-47）无取消机制。`Wait()` 超时后调用方返回，栈帧销毁，但 `shared_ptr<EngineSyncTask>` 仍留在消息队列中。Engine 线程后续执行 lambda 时写入已销毁的栈变量。

**影响**: 超时场景必现内存损坏 / 崩溃。

**建议修复**: lambda 捕获 `shared_ptr` 共享结果容器，超时后标记 task 已取消阻止执行。

---

### S02 · VideoPipeline 跨线程非原子字段数据竞争

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/video_pipeline.h` L333-392 |
| 分类 | 并发安全 |
| 状态 | ✅ 源码确认 |

**问题**: 以下字段为普通非原子类型：

```cpp
// video_pipeline.h L333-392
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

已验证调用链：

- **写入端**: `SetGeometry()` / `SetPixelFormat()` 由 Engine 线程（env 回调）调用
- **读取端**: `videoPipeline_.Render()` 由 Render 线程调用（`render_thread.cpp:550`）

构成 C++ 标准定义的 undefined behavior。

**建议修复**: 改为 `std::atomic` 或通过 `RenderThread` 的 `ControlMessage` 投递变更到 Render 线程串行处理。

---

### S03 · FramePacer 跨线程非原子字段数据竞争

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/frame_pacer.h` L58-75 |
| 分类 | 并发安全 |
| 状态 | ✅ 源码确认 |

**问题**:

```cpp
// frame_pacer.h L70-75
std::chrono::steady_clock::time_point frame_start_;     // 非原子
std::chrono::steady_clock::time_point next_deadline_;   // 非原子
bool deadline_initialized_ = false;                      // 非原子
bool frame_started_ = false;                             // 非原子
std::atomic<int64_t> target_frame_time_us_{16667};       // ← 这个是原子的
```

- `SetTargetFps()` 写 `deadline_initialized_=false` / `frame_started_=false`（Engine 线程）
- `BeginFrame()` / `EndFrame()` 读写这些字段（Render 线程，经 `video_pipeline.cpp:1379`）

**建议修复**: `bool` 字段改为 `std::atomic<bool>`；`time_point` 访问限定单一线程或加锁。

---

### S04 · 核心卸载时 GetDeinit() 空指针调用

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/libretro_engine.cpp` L1363 |
| 分类 | 错误处理 |
| 状态 | ✅ 源码确认 |

**问题**:

```cpp
// L1363 - 无空检查
coreLoader_.GetDeinit()();

// 对比 L523-525 - 有空检查
if (coreLoader_.GetDeinit()) {
  coreLoader_.GetDeinit()();
}
```

`retro_deinit_` 默认为 `nullptr`（`core_loader.h:99`）。

**建议修复**: 添加与 L523 一致的空指针检查。

---

### S05 · 0RGB1555 NEON 绿色通道提取错误

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/pixel_converter_neon.cpp` L195, L283 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 源码确认 + 手动验算 |

**问题**:

```cpp
// pixel_converter_neon.cpp L283 (RGBA) 和 L195 (BGRA)
uint16x8_t g5 = vshrq_n_u16(vshlq_n_u16(pixels, 5), 11);
```

0RGB1555 格式中 G 占 bits[9:5]。验算：

| 操作 | 位排列 (16-bit) |
|------|-----------------|
| 原始 | `0_RRRRR_GGGGG_BBBBB` |
| `<<5` | `R0_G4G3G2G1G0_B4B3B2B1B0_00000` |
| `>>11` | `00000000000_R0_G4G3G2G1` |

**结果**: 提取到 `R0,G4,G3,G2,G1`，**混入 R 最低位、丢失 G0**。

| 测试像素 | 期望 G | 实际 G | 是否正确 |
|----------|--------|--------|---------|
| `0x03E0`（纯绿 G=31） | 31 | 15 | ❌ |
| `0x7C00`（纯红 R=31, G=0） | 0 | 16 | ❌ |

标量回退路径用 `(pixel >> 5) & 0x1F` 是正确的。

**影响**: 所有使用 0RGB1555 默认格式 + NEON 路径（ARM 设备）的 libretro 核心**画面颜色全部错乱**。

**建议修复**:

```cpp
uint16x8_t g5 = vandq_u16(vshrq_n_u16(pixels, 5), vdupq_n_u16(0x1F));
```

---

### S06 · GLES 0RGB1555 纹理上传格式不匹配

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/gles_renderer.cpp` L908-912 |
| 分类 | 逻辑错误 / API 误用 |
| 状态 | ✅ 源码确认 |

**问题**:

```cpp
case RETRO_PIXEL_FORMAT_0RGB1555:
    alignment = 2;
    internalFormat = GL_RGB5_A1;
    pixelFormat = GL_RGBA;
    pixelType = GL_UNSIGNED_SHORT_5_5_5_1;
```

| | `GL_UNSIGNED_SHORT_5_5_5_1 + GL_RGBA` | Libretro 0RGB1555 |
|---|---|---|
| 位布局 | `RRRRR_GGGGG_BBBBB_A` (bits 15-11=R) | `0_RRRRR_GGGGG_BBBBB` (bit15=0, 14-10=R) |

每个通道偏移 1 bit。GL 看到的 R = `{0,R4,R3,R2,R1}`，G = `{R0,G4,G3,G2,G1}`，A = `B0`。

**影响**: 使用 0RGB1555 + GLES 渲染路径的核心画面颜色全部错乱（与 S05 是同一根源的不同路径表现）。

**建议修复**: 在上传前将 0RGB1555 转换为 XRGB8888（通过已有的 PixelConverter），或使用 `(pixel << 1) | 1` 转换为真正的 RGBA5551。

---

### S07 · NEON ConvertAndScale 未处理 destStride=0

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/pixel_converter_neon.cpp` L642-733 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 源码确认 |

**问题**: 头文件声明 `unsigned destStride = 0` 为默认参数（`pixel_converter.h:75`）。标量版有保护：

```cpp
// pixel_converter_scalar.cpp L66-68
if (destStride == 0) {
    destStride = destWidth;
}
```

NEON 版无此保护。内部 `destData + dstY * destStride` 当 `destStride=0` 时每行都写到 offset 0，只保留最后一行数据。

**影响**: CPU 软渲染路径画面只剩一行（调用方使用默认参数时触发）。

**建议修复**: NEON 版入口添加相同的默认值处理。

---

### S08 · CreateProgram 链接失败时 Shader 泄漏

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/gles_renderer.cpp` L747-782 |
| 分类 | 资源泄漏 |
| 状态 | ✅ 源码确认 |

**问题**:

```cpp
// L754-761: 链接失败路径
if (!status) {
    glDeleteProgram(p);
    return false;  // ← vs, fs 未删除
}
// L781-782: 成功路径
glDeleteShader(vs);
glDeleteShader(fs);
```

编译失败路径（L740-744）正确删除了 vs/fs。链接失败路径遗漏。

**建议修复**: 失败路径添加 `glDeleteShader(vs); glDeleteShader(fs);`。

---

### S09 · SwitchGameAsync NAPI 无错误处理

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/libretro_engine_napi.cpp` L831-833 |
| 分类 | 资源泄漏 / NAPI 误用 |
| 状态 | ✅ 源码确认 |

**问题**:

```cpp
napi_create_async_work(env, nullptr, resourceName, ExecuteSwitchGame,
                       CompleteSwitchGame, ctx, &ctx->work);  // 返回值未检查
napi_queue_async_work(env, ctx->work);                         // 返回值未检查
```

同文件 `GetRawFileListAsync`（~L456-484）有完整错误处理。此处失败时 `ctx` 泄漏、Promise 永不 resolve/reject。

**建议修复**: 检查返回值，失败时 reject promise 并 `delete ctx`。

---

### S10 · VulkanPresenter::DestroyFrameResources 无 GPU 等待 ⚠️

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_presenter.cpp` L127-147, L392-394 |
| 分类 | 并发安全 / API 误用 |
| 状态 | ⚠️ 条件性确认 |

**问题**: `Destroy()` 和 `EnsureFrameSlots`（缩小 vector 时）直接调用 `DestroyFrameResources`，无 `vkWaitForFences` 或 `vkDeviceWaitIdle`。

- `Destroy()`: `VulkanContext::Destroy()` 内有 `device_wait_idle`（L134），如果先调用则安全
- `EnsureFrameSlots` 缩小: 无任何等待，帧可能仍在 GPU 执行中 → **确认违反 Vulkan spec**

**限定条件**: 仅 `EnsureFrameSlots` 缩小路径有实际风险。

---

### S11 · VSync 回调析构后 use-after-free ⚠️

| 属性 | 值 |
|------|------|
| 文件 | `platform/sync/native_vsync_driver.cpp` L15, L46-89 |
| 分类 | 并发安全 / 内存安全 |
| 状态 | ⚠️ 条件性确认 |

**问题**: `~NativeVSyncDriver()` 调用 `Stop()`，`Stop()` 持锁调用 `OH_NativeVSync_Destroy`。如果已排队的 VSync 回调在 Destroy 后才执行，`OnFrame` 中 `self->mutex_` 访问已析构对象。

**限定条件**: 取决于 `OH_NativeVSync_Destroy` 是否保证不再有回调。HarmonyOS 文档未明确说明。`OnFrame` 有 `data != nullptr` 检查但无法检测悬垂指针。

---

## 🟡 中等问题（29 个）

### M01 · SET_SYSTEM_AV_INFO 返回 true 但不处理

| 属性 | 值 |
|------|------|
| 文件 | `core/libretro/env_dispatcher.cpp` L1326-1330 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

```cpp
case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
    if (!data) return false;
    return true;  // ← 不解析 retro_system_av_info，不更新任何状态
}
```

核心认为前端已接受新 AV 参数（分辨率、采样率、帧率），但实际未更新。可能导致运行时切换分辨率的核心出现音画异常。

---

### M02 · VulkanContext::Destroy 可能 double-free Device

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_context.cpp` L139-145 |
| 分类 | API 误用 |
| 状态 | ✅ 确认 |

```cpp
if (has_negotiation_ && negotiation_.destroy_device) {
    negotiation_.destroy_device();     // 核心可能已销毁 device
}
if (device_ && loader_.GetApi().destroy_device) {
    loader_.GetApi().destroy_device(device_, nullptr);  // 再次销毁
}
device_ = VK_NULL_HANDLE;
```

当核心通过 `create_device2` 创建 VkDevice 时，`negotiation_.destroy_device()` 会销毁它。随后前端再次调用 `vkDestroyDevice` 构成 double-free。

**建议修复**: `negotiation_.destroy_device()` 后立即 `device_ = VK_NULL_HANDLE`。

---

### M03 · ELF 解析无符号整数下溢

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/core_loader_napi.cpp` L239, L323 |
| 分类 | 内存安全 |
| 状态 | ✅ 确认 |

```cpp
if (needed_offset > data.size() - strtab_offset) {  // ← unsigned 减法下溢
```

当 `strtab_offset > data.size()` 时，右侧下溢为 `SIZE_MAX - x`，条件必然为 false，后续 `name_offset = strtab_offset + needed_offset` 越界。

**建议修复**: `if (strtab_offset > data.size() || needed_offset > data.size() - strtab_offset)`。

---

### M04 · switch_token fetch_add 后多余 store 竞态

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/libretro_engine_napi.cpp` L811-814 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

```cpp
token = switch_token.fetch_add(1) + 1;  // 原子递增，token=新值
switch_token.store(token);               // 多余且有害
```

`fetch_add(1)` 已原子地将 `switch_token` 从 N 递增到 N+1。随后 `store(token)` 可能覆盖另一线程的 `fetch_add` 结果。例如：线程 A token=6，线程 B token=7，线程 A 的 `store(6)` 覆盖 7。

**建议修复**: 删除 `switch_token.store(token);`。

---

### M05 · file_security.cpp 日志使用 `%s` 而非 `%{public}s`

| 属性 | 值 |
|------|------|
| 文件 | `common/file_security.cpp` L30, L56, L75, L79-81, L91, L113, L119, L135, L139, L152, L158 |
| 分类 | 安全 / 日志规范 |
| 状态 | ✅ 确认 |

HiLog 生产环境中 `%s` 显示为 `<private>`，导致路径遍历检测等安全审计日志完全不可读。

---

### M06 · 配置保存不原子 + 转义不对称

| 属性 | 值 |
|------|------|
| 文件 | `common/config/file_configuration.cpp` L90-106 |
| 分类 | 逻辑错误 / 资源泄漏 |
| 状态 | ✅ 确认 |

1. `SaveKeyValues` 直接写目标文件，中途崩溃导致文件损坏
2. `EscapeDoubleQuotes` 将 `"` → `\"`，但 `LoadKeyValues` 的 `StripQuotes` 不做反转义，save→load 往返破坏含引号的值
3. `fprintf` 返回值未检查

---

### M07 · RingBuffer::Clear() relaxed 双重置

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/ring_buffer.cpp` L357-370 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

```cpp
head_.v.store(0, std::memory_order_relaxed);  // 步骤1
tail_.v.store(0, std::memory_order_relaxed);  // 步骤2
```

两次 relaxed store 之间，并发 `Read` 可能观察到 `head=0, tail=旧值`，`AvailableRead()` 返回 `0 - 旧值` 下溢为巨大值，触发越界拷贝。依赖外部 `running_=false` 协议缓解。

---

### M08 · DiskController 持锁调用核心回调

| 属性 | 值 |
|------|------|
| 文件 | `core/libretro/disk_controller.cpp` L36-111 |
| 分类 | 并发安全（潜在死锁） |
| 状态 | ✅ 确认 |

所有方法持有 `mutex_` 状态下调用核心回调（如 `callbacks_.set_eject_state`）。若核心回调内部重入 `DiskController` 方法，`std::mutex` 不可重入 → 死锁。

---

### M09 · Vulkan present 操作缺少队列锁

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_presenter.cpp` L499 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

```cpp
LockQueue();
api_.queue_submit(queue_, 1, &submit, state.submit_fence);
UnlockQueue();
// ...
const VkResult present_res = api_.queue_present_khr(present_queue_, &present);  // ← 无锁
```

当 `present_queue_ == queue_` 时（大多数设备），`vkQueuePresentKHR` 也需要在 `queue_mutex_` 保护下执行。

---

### M10 · swapchain_out_of_date_ 非原子跨线程

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_presenter.h` L124 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

```cpp
bool swapchain_out_of_date_ = false;  // 普通 bool
```

`Present()` 写入（L506），`ShouldRecreateSwapchain()` 读取，可能跨线程。

---

### M11 · HwRenderPresenter::Present 不恢复 GL 状态

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/hw_render_presenter.cpp` L238-275 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

注释表明 `CaptureState` / `RestoreState` 被移除以避免 pipeline stall。但 `GL_CURRENT_PROGRAM`、`GL_ARRAY_BUFFER_BINDING`、`GL_VIEWPORT` 等状态在 `Present` 后未恢复，可能影响依赖 HW_RENDER 的核心。

---

### M12 · GLESRenderer::Deinit contextCurrent 未检查

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/gles_renderer.cpp` L516-524 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

```cpp
bool contextCurrent = false;
// ...
contextCurrent = eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, egl_context_);
// ← contextCurrent 赋值后从未检查
```

`eglMakeCurrent` 失败时后续 GL 删除操作无当前上下文，GPU 资源泄漏。

---

### M13 · GraphicsContext 无线程安全保护

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/graphics_context.h/.cpp` |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

无 mutex。`UpdateSurface` 可能从 XComponent 回调线程调用，`egl_surface_`/`ready_` 无保护。

---

### M14 · EGL attribs 硬编码魔法数字索引

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/graphics_context.cpp` L93-94 |
| 分类 | 逻辑错误（可维护性） |
| 状态 | ✅ 确认 |

```cpp
attribs[13] = 0;
attribs[15] = 0;
```

依赖 `attribs[]` 数组声明顺序的硬编码索引，数组变更时静默指向错误属性。

---

### M15 · VulkanPresenter::SubmitFrame 手动 lock/unlock

| 属性 | 值 |
|------|------|
| 文件 | `platform/graphics/vulkan_presenter.cpp` L480-483 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

```cpp
LockQueue();
const VkResult submit_res = api_.queue_submit(queue_, 1, &submit, state.submit_fence);
UnlockQueue();
```

非 RAII 风格，如果中间有信号中断或未来修改引入提前 return，unlock 被跳过 → 死锁。

---

### M16 · event_bridge pending payload 发送旧数据

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/event_bridge.cpp` L146-151 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

限流间隔到期时，如果有 pending payload，代码用旧的 pending 替换当前传入的最新 payload：

```cpp
auto pending_it = pending_payload_.find(eventKey);
if (pending_it != pending_payload_.end()) {
    payload_to_send = pending_it->second;  // ← 旧数据覆盖新数据
}
```

---

### M17 · ROMLoadResult 成员未默认初始化

| 属性 | 值 |
|------|------|
| 文件 | `platform/resource/rom_loader.h` L19, L23 |
| 分类 | 内存安全 |
| 状态 | ✅ 确认 |

`success` 和 `size` 无默认初始化器。默认构造时值未定义。

---

### M18 · NativeVSyncDriver 持锁调用外部 API

| 属性 | 值 |
|------|------|
| 文件 | `platform/sync/native_vsync_driver.cpp` L58-68 |
| 分类 | 并发安全（潜在死锁） |
| 状态 | ✅ 确认 |

`RequestNextFrame` 持有 `mutex_` 调用 `OH_NativeVSync_RequestFrame`。如果该 API 同步触发回调，`OnFrame` 也尝试获取 `mutex_` → 死锁。

---

### M19 · file_security 符号链接潜在绕过

| 属性 | 值 |
|------|------|
| 文件 | `common/file_security.cpp` L57-83 |
| 分类 | 安全 |
| 状态 | ✅ 条件性确认 |

`realpath` 失败回退路径中 `IsUnderRoot(inputPath)` 使用未解析的原始路径。预置在允许目录内的 symlink 可绕过检查。

---

### M20 · ELF 文件读取无大小上限

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/core_loader_napi.cpp` L49 |
| 分类 | 安全 / 内存安全 |
| 状态 | ✅ 确认 |

`data.resize(static_cast<size_t>(st.st_size))` 无上限检查。超大 `.so` 文件可耗尽内存。

---

### M21 · WaitForEngineState 同步阻塞 JS 线程

| 属性 | 值 |
|------|------|
| 文件 | `app/napi/libretro_engine_napi.cpp` L1170-1197 |
| 分类 | 性能 / API 误用 |
| 状态 | ✅ 确认 |

同步 NAPI 函数在 ArkTS 主线程阻塞等待，`timeoutMs` 较大时导致 ANR。

---

### M22 · EngineStats 成员未初始化 + 接口与 NAPI 不匹配

| 属性 | 值 |
|------|------|
| 文件 | `interfaces/diagnostics/i_engine_stats.h` L12-37 + `libretro_engine_napi.cpp` L1522-1553 |
| 分类 | 内存安全 / 接口一致性 |
| 状态 | ✅ 确认 |

`EngineStats` 所有 `int64_t`/`double` 成员无初始化器。NAPI 层使用了多个接口中不存在的字段名。

---

### M23 · cue_parser FILE 指令匹配过宽

| 属性 | 值 |
|------|------|
| 文件 | `common/cue_parser.cpp` L33 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

`upper.rfind("FILE", 0) == 0` 匹配所有以 "FILE" 开头的行（含 `FILENAME` 等），未检查后续是否为空白。

---

### M24 · AudioPlayer Cleanup 中 Stop 失败后仍 Release

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/audio_player.cpp` L912-981 |
| 分类 | 资源泄漏 / 错误处理 |
| 状态 | ✅ 确认 |

`OH_AudioRenderer_Stop` 失败后仍调用 `OH_AudioRenderer_Release`，渲染器未停止状态下 Release 可能导致未定义行为。

---

### M25 · AudioResampler 除零风险

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/audio_resampler.cpp` L93 |
| 分类 | 逻辑错误 |
| 状态 | ✅ 确认 |

`const double step = 1.0 / current_ratio_`。如果 `current_ratio_` 为 0，产生 `inf`。`Init` 有 `> 0` 检查但 `UpdateRatio` 路径理论上可达。

---

### M26 · AudioBridge Meyers 单例静态析构风险

| 属性 | 值 |
|------|------|
| 文件 | `platform/audio/audio_bridge.cpp` L125-132 |
| 分类 | 内存安全 |
| 状态 | ✅ 确认 |

`DestroyInstance()` 无实际操作。程序退出时静态析构顺序不确定，OHAudio 回调可能访问已析构单例。

---

### M27 · TempFileManager WriteDependencyFile 缺路径验证

| 属性 | 值 |
|------|------|
| 文件 | `platform/resource/temp_file_manager.cpp` L56-77 |
| 分类 | 安全 |
| 状态 | ✅ 确认 |

`relativePath` 直接拼接到 `parentTempDir`，无 `..` 或绝对路径检查。

---

### M28 · systemInfo_ 悬垂指针风险

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/libretro_engine.cpp` L1392-1394, L1966-1968 |
| 分类 | 内存安全 |
| 状态 | ✅ 确认 |

`retro_system_info` 的 `library_name` 等字段是核心 .so 内存中的 `const char*`。卸载 .so 后指针悬垂。`hasSystemInfo_` 标志提供了一定保护，但 `ProcessFrame` 中的访问在 RUNNING 状态每帧执行。

---

### M29 · window_guard PeekWindow 无锁返回裸指针

| 属性 | 值 |
|------|------|
| 文件 | `core/engine/window_guard.h` L97-99 |
| 分类 | 并发安全 |
| 状态 | ✅ 确认 |

`PeekWindow()` 直接返回 `window_` 裸指针，不加锁不增引用计数。标记为 Deprecated 但仍存在。

---

## 🟢 轻微问题（47 个，概要列表）

| # | 文件 | 简述 |
|---|------|------|
| 1 | `bounded_latest_frame_queue.h` L88 | 未使用的 `cond_` 条件变量 |
| 2 | `video_pipeline.cpp` L1340/L1363 | 变量名重复遮蔽（内外层同名 `totalUs`） |
| 3 | `libretro_engine.cpp` L2115 | 静态日志计数器非原子 |
| 4 | `render_thread.cpp` 多处 | static 局部日志计数器不随 ResetStats 重置 |
| 5 | `video_pipeline.cpp` L733,L777 | 函数级 static 变量应为成员 |
| 6 | `core_state_manager.cpp` L92-108 | SetSRAM 截断不报告 |
| 7 | `libretro_engine.h` L368 | `atomic<time_point>` 可能非 lock-free |
| 8 | `video_pipeline.cpp` L1094-1107 | NativeBuffer 路径复杂建议 RAII 包装 |
| 9 | `core_loader.cpp` L30-31 | PreloadGraphicsLibs dlopen 句柄未保存（有意为之） |
| 10 | `core_loader.cpp` L106 | `strerror` 非线程安全 |
| 11 | `core_loader.cpp` L111 | `st_size` 用 `(long)` 可能截断 |
| 12 | `env_dispatcher.cpp` L1452-1457 | SET_MINIMUM_AUDIO_LATENCY 限制可能误拒 |
| 13 | `env_dispatcher.cpp` L620-627 | TLS 8 槽位轮转理论悬垂指针 |
| 14 | `env_dispatcher.cpp` L987-1001 | GET_SYSTEM_DIRECTORY 重复调用浪费 TLS 槽位 |
| 15 | `env_dispatcher.h` L52-54 | `in_retro_run_` 普通 bool（当前单线程安全） |
| 16 | `audio_bridge.cpp` L486-494 | Buffering 检查微小时序窗口 |
| 17 | `audio_bridge.cpp` L61,372,378 | `run_state_log_count_` 非原子（仅影响日志） |
| 18 | `audio_player.cpp` L974 | `ring_buffer_` 清空在锁外 |
| 19 | `audio_player.cpp` L174-198 | OHAudio 双回调设置（新 API 覆盖旧 API） |
| 20 | `audio_resampler.cpp` L86-90 | `history_init_` 块缺防御性检查 |
| 21 | `ring_buffer.cpp` L200-205 | WriteWait 醒来后依赖外部协议 |
| 22 | `ring_buffer.h` L129-132 | `mutable` 非原子计数器缺注释 |
| 23 | `retro_common.h` | typedef 可能与 libretro.h 重复定义 |
| 24 | `gles_renderer.h` L119 | `egl_config_` 未初始化 |
| 25 | `hw_render_presenter.cpp` L501 | 每帧 glBufferData 重分配 |
| 26 | `pixel_converter_neon.cpp` L647-648 | static 日志计数器非线程安全 |
| 27 | `pixel_converter_neon.cpp` L413-416 | thread_local vector 永不收缩 |
| 28 | `pixel_converter_neon.cpp` L642-693 | 缺 NULL/zero 参数检查 |
| 29 | `vulkan_presenter.cpp` L19-29 | MaskToCount 非 popcount |
| 30 | `rom_loader.cpp` L189 | URI 长度 size_t→unsigned int 截断 |
| 31 | `fence_utils.cpp` L38-56 | dlopen 句柄有意不释放但未注释 |
| 32 | `temp_file_manager.cpp` L64 | `find_last_of` 返回 `npos` 边界 |
| 33 | `platform_resource_manager.cpp` L86 | `%zu` 格式与 `std::streamsize` 不匹配 |
| 34 | `plugin_manager.cpp` L438,556 | static callback 脆弱模式 |
| 35 | `plugin_manager.h` L42 | 参数应为 `const std::string &` |
| 36 | `plugin_manager.cpp` L686-702 | `nativeXComponentMap_` 无锁 |
| 37 | `libretro_engine_napi.cpp` L908-943 | StopEngineAsync 不返回 Promise |
| 38 | `cue_parser.cpp` L16 | 未处理非 UTF-8 CUE 编码 |
| 39 | `file_configuration.cpp` vs `utils.cpp` | TrimCopy 重复实现 |
| 40 | `audio_bridge.cpp` + `ring_buffer.cpp` | 音频热路径锁持有时间过长 |
| 41 | `disk_controller.cpp` L21-33 | 旧版回调设置未清零扩展字段（`is_ext_` 保护） |
| 42 | `engine_messages.h` L86-97 | payload 非 union 内存开销（设计权衡） |
| 43 | `libretro_engine.cpp` L373,478 | `running_` 赋值未统一使用 `.store()` |
| 44 | `libretro_engine.cpp` L2527-2538 | WaitForState 条件变量与原子变量模式不一致 |
| 45 | `core_options_registry.cpp` L14-17 | static `FileConfiguration` 缺线程安全注释 |
| 46 | `rom_loader.cpp` L85-107 | `CreateGameInfo` 返回指针依赖 result 生命周期（缺文档） |
| 47 | `audio_bridge.cpp` L451-460 | Resampler DRC 竞争（已知并接受） |

---

## 优先修复建议

### P0 — 立即修复（影响用户可见功能）

| 序号 | 问题 | 影响 | 预估改动量 |
|------|------|------|-----------|
| S05+S06 | 0RGB1555 颜色错乱（NEON + GLES） | 所有默认像素格式核心画面颜色全错 | 小（各几行） |
| S07 | NEON destStride=0 | CPU 渲染路径画面只剩一行 | 极小（1 行） |

### P1 — 尽快修复（崩溃 / 内存安全）

| 序号 | 问题 | 影响 | 预估改动量 |
|------|------|------|-----------|
| S01 | ExecuteSyncTask use-after-free | 超时场景内存损坏 / 崩溃 | 中（需重构同步机制） |
| S02+S03 | VideoPipeline/FramePacer 数据竞争 | 长时运行画面异常 / 崩溃 | 中（原子化或消息投递） |
| S08 | GL Shader 泄漏 | 反复失败累积 GPU 内存 | 极小（2 行） |
| S09 | SwitchGameAsync 无错误处理 | Promise 挂起 | 小 |
| M03 | ELF 解析整数下溢 | 恶意 .so 越界读 | 极小（1 行保护） |
| M04 | switch_token 竞态 | 切换游戏 token 覆盖 | 极小（删 1 行） |

### P2 — 计划修复

| 序号 | 问题 | 预估改动量 |
|------|------|-----------|
| S04 | GetDeinit 空指针 | 极小 |
| S10 | Vulkan 资源销毁安全 | 中 |
| M01 | SET_SYSTEM_AV_INFO 空实现 | 中 |
| M02 | VulkanContext double-free | 小 |
| M05 | file_security 日志格式 | 小（批量替换） |
| M06 | 配置保存原子性 + 转义 | 中 |
| M08 | DiskController 死锁 | 中 |

---

## 审查方法说明

1. **第一轮**: 4 个并行审查代理分别扫描 core/engine、core/libretro+audio、platform/graphics、其他模块
2. **第二轮**: 对所有 🔴 严重（14 个）和 🟡 中等（41 个）问题逐一回到源码验证
   - 读取每个问题涉及的实际源文件
   - 追踪跨线程调用链确认是否真正存在数据竞争
   - 手动验算位操作（0RGB1555 NEON）
   - 确认 API 契约（Vulkan spec、OHAudio 文档、NAPI 生命周期）
3. **修订结果**: 3 个 🔴 降级为 🟡，4 个 🟡 判定为误报删除，8 个 🟡 降级为 🟢
