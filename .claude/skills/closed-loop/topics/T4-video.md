# T4 — VideoPipeline

## Scope
VideoPipeline 模式协商 + 渲染。

**Files**: `entry/src/main/cpp/core/engine/video_pipeline.*` + 各 renderer

## Hazards
- pixel format negotiation — RGB565 / XRGB8888 / RGB1555 切换时的旧 buffer 残留
- geometry resize — 中途 base_width / max_width 变化,buffer 重分配 vs sticky
- Hardware/Software/GLES/Vulkan switch — 模式切换时 NativeWindow buffer 队列清空
- NativeBuffer dequeue/queue — RequestBuffer / FlushBuffer 异常路径泄漏
- VSync 回调线程与主线程的状态共享 — 必须 `std::mutex + std::lock_guard`

## Done criteria 模板(场景驱动)
- [ ] 像素格式切换不留旧 buffer / 不触发尺寸 mismatch crash
- [ ] geometry resize 路径下,renderer 重建期间 retro_video_refresh 不写无效 buffer
- [ ] 模式切换(Software → GLES → Vulkan)前 buffer 队列已清空
- [ ] 所有 RequestBuffer / FromNativeWindowBuffer / Map / Unmap / Flush 配对(用 ast-grep 扫)
- [ ] VSync 回调与 main thread 共享状态全部加锁(`AGENTS.md` 强制规则)

## 必用 MCP
`mcp__ast-grep__find_code` — 扫所有 `OH_NativeBuffer_*` / `OH_NativeWindow_*` callsite 配对。
