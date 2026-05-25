# VideoPipeline 渲染安全审计 — agent-T4

**审计范围**：
- `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- `entry/src/main/cpp/core/engine/video_pipeline.h`
- `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- `entry/src/main/cpp/platform/graphics/gles_renderer.h`
- `entry/src/main/cpp/platform/graphics/graphics_context.cpp`
- `entry/src/main/cpp/platform/graphics/hw_render_presenter.cpp`
- `entry/src/main/cpp/core/engine/window_state_manager.cpp`
- `entry/src/main/cpp/core/engine/libretro_engine.cpp`（仅线程模型验证）

**审计时间**：2026-05-25

---

## F1: FlushBuffer 失败后仍调用 AbortBuffer，buffer 所有权已转移

- severity: P0
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- line: 1321-1335
- evidence_excerpt: |
    ```
    ret =
        OH_NativeWindow_NativeWindowFlushBuffer(window, buffer, fenceFd, region);
    
    if (ret != 0) {
      m->nwFlushBufferFailures++;
      ...
      m->nwAbortBufferCalls++;
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
      OH_NativeBuffer_Unreference(nativeBuffer);
    ```
- claim: HarmonyOS NativeWindow 语义中，`OH_NativeWindow_NativeWindowFlushBuffer` 调用后无论成功与否，buffer 的所有权即移交给 consumer（BufferQueue）。此时再调用 `OH_NativeWindow_NativeWindowAbortBuffer` 是非法操作，相当于将同一个 buffer 归还两次（双重释放）。可能导致 BufferQueue 状态机破坏、consumer 侧 use-after-free，或 GPU sync fence 悬挂，轻则渲染花屏，重则进程崩溃。
- suggested_fix: 删除 FlushBuffer 失败路径中的 `AbortBuffer` 调用及 `nwAbortBufferCalls++`；只保留 `OH_NativeBuffer_Unreference(nativeBuffer)` 和错误日志。FlushBuffer 失败本身说明 buffer 已不被 producer 持有，无需也不应回收。

---

## F2: 所有 platform/graphics 翻译单元与 video_pipeline.cpp 共用相同 LOG_DOMAIN 0xD003

- severity: P2
- file: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`（及 graphics_context.cpp、hw_render_presenter.cpp、pixel_converter_neon.cpp、pixel_converter_scalar.cpp、vulkan_context.cpp、vulkan_loader.cpp、vulkan_presenter.cpp）
- line: gles_renderer.cpp:10-11；video_pipeline.cpp:23-24
- evidence_excerpt: |
    ```
    // gles_renderer.cpp
    #undef LOG_DOMAIN
    #define LOG_DOMAIN 0xD003

    // video_pipeline.cpp
    #undef LOG_DOMAIN
    #define LOG_DOMAIN 0xD003
    ```
- claim: CLAUDE.md 明确要求"Each translation unit should use a unique domain to keep hilog filtering practical"。当前 8 个 .cpp 文件全部使用 `0xD003`，与 `video_pipeline.cpp` 相同，导致无法通过 LOG_DOMAIN 区分各组件日志，线上 hilog 过滤形同虚设。
- suggested_fix: 为 platform/graphics 下各 .cpp 分配独立域值，例如：gles_renderer.cpp → 0xD004，graphics_context.cpp → 0xD005，hw_render_presenter.cpp → 0xD006，vulkan_context.cpp → 0xD007，vulkan_presenter.cpp → 0xD008，vulkan_loader.cpp → 0xD009，pixel_converter → 0xD00A。保持 video_pipeline.cpp 使用 0xD003。

---

## F3: GLESRenderer::Deinit() 开头将 healthy_ 重置为 true，破坏析构期健康状态语义

- severity: P2
- file: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- line: 495-501
- evidence_excerpt: |
    ```
    void GLESRenderer::Deinit() {
      std::lock_guard<std::recursive_mutex> lock(mutex_);
      healthy_ = true;
      last_egl_error_.store(static_cast<int>(EGL_SUCCESS), ...);
      last_swap_failure_kind_.store(static_cast<int>(SwapFailureKind::NONE), ...);
      // ...EGL 清理尚未执行...
    ```
- claim: `Deinit()` 首行即将 `healthy_` 设为 `true`，此时 EGL context/surface 尚未销毁。如果 `Init()` 内部因 `CreateProgram` 失败调用了 `Deinit()`，再次返回后 `healthy_ == true` 被误读为初始化成功。更重要的是：逻辑上 `Deinit` 是销毁操作，应当在最终将对象还原到"初始未初始化状态"后再确认 healthy，而不是一开始就标记 healthy。尽管当前因为是单线程调用不存在数据竞争，但语义混乱会在未来增加并发路径时埋下隐患。
- suggested_fix: 在 `Deinit()` 开头改为 `healthy_ = false`（或直接不设置），在方法末尾清理完毕后再将 `healthy_` 设置为 `true`（表示对象已回到初始可用状态）。同时在 `Deinit` 内也可保持 `healthy_ = false` 直至下次 `Init` 成功。

---

## F4: WindowStateManager::Apply 仅在全部 opt 成功时才更新 last_state_，导致 geometry 已应用但 usage/swap 异常时每帧重试所有 opts

- severity: P2
- file: `entry/src/main/cpp/core/engine/window_state_manager.cpp`
- line: 89-101
- evidence_excerpt: |
    ```
    if (result.geometry_ok && result.usage_ok && result.swap_ok &&
        result.source_ok && result.scaling_ok) {
      last_state_ = state;
      has_state_ = true;
    }
    ```
- claim: 当 `geometry_ok = true` 但 `usage_ok` 或 `swap_ok` 失败时，`last_state_` 不会更新。下一帧检测 `unchanged == false`（因 last_state_ 旧）会重新对 window 设置 `SET_BUFFER_GEOMETRY`。在一些低端 HarmonyOS 设备上，反复调用已生效的 `SET_BUFFER_GEOMETRY` 可能触发 producer 侧重建 BufferQueue slot，导致性能抖动或与正在进行中的 RequestBuffer 发生冲突。
- suggested_fix: 将 `last_state_` 的更新粒度细化：geometry 成功后即更新 `last_state_.width/height`，而不是等待所有 opt 全部成功后才整体更新，避免 geometry 重复配置。

---

## F5: SetPixelFormat 在 retro_load_game 上下文中调用（Engine 线程），但 pixel_format_ 为非原子非互斥保护字段，Render() 同线程读取是安全的，然而该设计缺乏跨线程安全文档

- severity: P2
- file: `entry/src/main/cpp/core/engine/video_pipeline.h`
- line: 93-98
- evidence_excerpt: |
    ```
    void SetPixelFormat(retro_pixel_format format) {
      if (pixel_format_ != format) {
        pixel_format_ = format;
        ClearFrameCache();
        geometry_changed_.store(true);
      }
    }
    ```
- claim: `pixel_format_` 是普通（非 atomic）成员变量，`SetPixelFormat` 和 `Render()` 均在 Engine 线程内调用，当前无数据竞争。但 `SetWindowSize()` 通过 `window_width_.store` / `window_height_.store` 暗示这些字段可跨线程写入；若未来有代码从 NAPI 线程调用 `SetPixelFormat`（视为"窗口配置"的一部分），将产生 data race。缺乏注释说明 `pixel_format_` 的线程所有权。
- suggested_fix: 在 `pixel_format_` 字段旁加注释 `// Must be accessed only on Engine thread`，或将其改为 `std::atomic<int>` + enum cast，与 `scaling_mode_` 的处理方式保持一致，消除潜在的跨线程访问风险。

---

## DONE
