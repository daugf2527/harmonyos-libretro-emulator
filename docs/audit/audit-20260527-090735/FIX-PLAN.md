# Fix Plan — audit-20260527-090735

**用户决策**: 修全部 9 项 REAL findings（3 P1 + 6 P2）。

## 修复顺序（按文件分组以最小化 Edit）

### 阶段 1: 前置研究

- **T4-F1 API 契约核查**: WebSearch + 读 NativeWindow header 注释，确认 `OH_NativeWindow_NativeWindowAbortBuffer` 在 `FlushBuffer` 失败后调用是否真为 UB。

### 阶段 2: 单文件批改

| 文件 | Finding | 修复 |
|---|---|---|
| `platform/audio/audio_bridge.cpp` | T3-F2 | `Reset()` 内清零 `drc_last_update_ = {}` 让 DRC 首次更新不被延迟 |
| `platform/audio/audio_player.cpp` | T3-F5 | API 12+ 守卫双 callback 注册：legacy 路径只在 API < 12 编译 |
| `platform/audio/audio_resampler.cpp` | T3-F8 | history init `in[1]` → `fetch_channel(...)` 走统一边界保护 |
| `core/engine/video_pipeline.cpp` | T4-F1 | FlushBuffer 失败分支去 AbortBuffer，仅 Unreference |
| `core/engine/video_pipeline.cpp` | T4-F4 | EnterDegradedMode 去 sourceMode 过滤，x86 允许 SW 降级 |
| `core/engine/video_pipeline.cpp` | T4-F7 | `static bool logged` → 成员 counter + ShouldLog 节流 |
| `core/engine/render_thread.cpp` | T4-F2 | ~~补 NativeObjectReference~~ → **修复阶段重审发现 FALSE_POSITIVE，不修**（详见 CORE-REVIEW.md 修订条） |
| `platform/graphics/gles_renderer.cpp` | T4-F6 | 去 `diagEnabled` 守卫，无条件 `glGetIntegerv` |
| `platform/graphics/pixel_converter_scalar.cpp` | T4-F8 | XRGB8888 scalar 改 16.16 定点累加器，与通用路径一致 |

### 阶段 3: Rebuild + verify
- `bash scripts/check/quick_signals.sh`

### 约束
- 每个 fix 加 `// Audit T<N>-F<M>: <one-line>` 注释
- 不 refactor 周边，不修 MITIGATED 项
- 不动 NAPI 文件 → 不需要 napi-boundary-reviewer
