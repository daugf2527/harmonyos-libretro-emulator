# Render/Audio/Window State Machine

## 1. Window Session

单一真值由 `RenderThread::windowSession_` 维护，字段：

- `sessionId`
- `generation`
- `state` (`DETACHED/ATTACHED_PENDING_SIZE/READY/PAUSED_SURFACE/DESTROYED`)
- `width/height`
- `active`
- `window`

迁移规则：

1. `SetWindow(new)`:
   - `frameQueue.Clear()`
   - `generation++`（或使用上层传入 generation）
   - `sessionId++`
   - `window=null -> DESTROYED`
   - `window!=null 且 size无效 -> ATTACHED_PENDING_SIZE`
   - `window!=null 且 size有效 -> READY`
2. `Resize(w,h)`:
   - `w/h<=0 -> PAUSED_SURFACE`
   - `w/h>0 且有 window -> READY`
   - `w/h>0 且无 window -> DETACHED`

渲染放行条件：

- `windowSession.IsRenderable() == true`
- 帧 `surfaceGeneration == windowSession.generation`（或帧 generation 为 0）

## 2. Render Mode

`VideoPipeline::RenderModeState`：

- `SW_READY`
- `GLES_READY`
- `HW_READY`
- `DEGRADED_TO_SW`
- `RECOVERING`

关键策略：

1. GLES 连续重建失败触发 `EnterDegradedMode()`，切换到 software。
2. 进入 `DEGRADED_TO_SW` 后等待冷却窗口（默认 3s 起步）再尝试 `RECOVERING`。
3. 恢复失败计数达到阈值后保持 software，避免抖动。

## 3. Audio Run State

`AudioBridge::AudioRunState`：

- `INIT`
- `BUFFERING`
- `RUNNING`
- `PAUSED`
- `RECOVERING`

迁移触发点：

1. `Initialize/Reset -> INIT`
2. `Start` 且数据不足 -> `BUFFERING`
3. `Buffering complete + player started -> RUNNING`
4. `Pause/Stop -> PAUSED`
5. 连续写入失败或恢复异常 -> `RECOVERING`

中断线程约束：

- `AudioPlayer::OnInterruptEvent` 只打标记，不直接做重操作。
- 由 `AudioBridge::ProcessAudio` 中的 `ProcessPendingInterruptActions()` 在安全线程处理。

## 4. Unified Snapshot

每秒输出状态快照（见 `LibretroEngine` stats 周期日志）：

- `sid`（surface session id）
- `gen`（surface generation）
- `engine_window`（Engine surface state）
- `render_window`（RenderThread WindowSession state）
- `active/size`（RenderThread window active 与尺寸）
- `render`（render mode state）
- `audio`（audio run state）

用于崩溃前最后状态回溯与门禁验收。
