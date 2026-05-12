# Render/Audio Delivery Gate

## 1. 目标

交付前必须证明：

1. 三条视频链路（Software/GLES/HW）稳定。
2. 音频在窗口抖动、前后台切换下连续可恢复。
3. 最小化/小窗/恢复/旋转场景不出现 crash 或长时间黑屏。

## 2. 门禁项

### Gate A: 稳定性

1. `Software` 30 分钟：无 crash / native fatal。
2. `GLES` 30 分钟：无 crash / native fatal。
3. `HW` 30 分钟：无 crash / native fatal。

### Gate B: 切换

1. `Software <-> GLES <-> HW` 循环 300 次。
2. 期间无闪退、无卡死、无持续黑屏。

### Gate C: 生命周期

1. `Created/Changed/Resized/Destroyed` 压测 500 次。
2. `Resize 0x0 -> valid` 必须先完成 rebind + ready 再放行渲染。

### Gate D: 状态兼容

1. 最小化/小窗/前后台/旋转各 200 次。
2. 音频不出现长期静音锁死；underrun 可恢复。

### Gate E: 架构约束

1. `OH_NativeWindow_RequestBuffer/Flush/Abort` 仅在 `RenderThread` 路径可达。
2. 旧 generation 帧 100% 被丢弃（可观测）。
3. 快照日志持续输出 `sid/gen/window/render/audio`。
4. 代际错帧日志可见：`Drop stale frame: frame_gen=... session_gen=...`。

## 3. 观测指标

1. `RequestBuffer` 失败率、`FlushBuffer` 失败率。
2. `RenderCPU` 分段耗时（Req/Fence/Map/Conv/Unmap/Flush）。
3. `audio_status` 事件：`state/occupancy/underruns/overruns`。
4. 状态快照日志：
   `[Snapshot] sid=... gen=... engine_window=... render_window=... active=... size=... render=... audio=...`。

## 4. 结果记录模板

| Gate | Result | Evidence |
|---|---|---|
| A | TODO | log/session link |
| B | TODO | log/session link |
| C | TODO | log/session link |
| D | TODO | log/session link |
| E | TODO | code ref + log |

> 任一 Gate 不通过，版本不交付。
