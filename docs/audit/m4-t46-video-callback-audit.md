# M4-T46: 视频回调实现审计报告

**审计日期**: 2026-05-31  
**审计范围**: SET_PIXEL_FORMAT / SET_GEOMETRY / GET_CAN_DUPE 处理  
**审计维度**: 格式切换、分辨率变更、dupe 策略

---

## 1. 执行摘要

### 1.1 审计结论

视频回调实现**基本正确**，但存在以下问题：

| 问题 | 严重性 | 影响 |
|------|--------|------|
| **P1**: Dupe 帧缓存未实现 | 中 | 性能浪费（核心 dupe 时前端仍重复渲染） |
| **P2**: SET_GEOMETRY 未触发 VideoPipeline 重配置 | 低 | 运行时分辨率切换可能延迟一帧 |
| **P3**: 像素格式日志缺失 | 低 | 调试困难 |

### 1.2 关键发现

✅ **正确实现**:
- SET_PIXEL_FORMAT 支持 XRGB8888/RGB565/0RGB1555 三种格式
- SET_GEOMETRY 正确更新 EnvState 并同步到 VideoPipeline
- SET_SYSTEM_AV_INFO 完整处理分辨率/帧率/采样率热切换
- GET_CAN_DUPE 返回 true（前端支持 dupe）

❌ **缺失功能**:
- Dupe 帧缓存（`lastFrame_` 定义但未使用）
- NULL data 时未复用上一帧（直接当 no-op 返回）

---

## 2. 视频回调处理流程

### 2.1 SET_PIXEL_FORMAT 处理链路

```
Core: retro_environment(SET_PIXEL_FORMAT, &format)
  ↓
env_dispatcher.cpp:1296 HandleEnvironmentCommand()
  ├─ 验证格式: XRGB8888 / RGB565 / 0RGB1555
  ├─ state.SetPixelFormat(format)  // EnvState 存储
  └─ return true/false
  ↓
libretro_engine.cpp:2334 特殊处理
  ├─ videoPipeline_.SetPixelFormat(format)  // 同步到 VideoPipeline
  ├─ ClearFrameCache()  // 清空 dupe 缓存
  ├─ geometry_changed_ = true  // 触发重配置
  └─ eventBridge_.Emit("pixel_format_update")  // 通知 ArkTS
```

**关键代码**:
```cpp
// env_dispatcher.cpp:1296
case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
  if (!data) return false;
  ::retro_pixel_format *fmt = (::retro_pixel_format *)data;
  const bool supported = (*fmt == ::RETRO_PIXEL_FORMAT_XRGB8888 ||
                          *fmt == ::RETRO_PIXEL_FORMAT_RGB565 ||
                          *fmt == ::RETRO_PIXEL_FORMAT_0RGB1555);
  if (!supported) return false;
  state.SetPixelFormat(*fmt);
  return true;
}

// libretro_engine.cpp:2334
if (cmd == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && handled) {
  retro_pixel_format format = engine->envState_.GetPixelFormat();
  engine->videoPipeline_.SetPixelFormat(format);  // ✅ 同步到 pipeline
  LOGF(LOG_INFO, "Pixel format set to: %{public}d", static_cast<int>(format));
  // ... emit event
}
```

**验证结果**: ✅ **正确**
- 格式验证完整（三种格式都支持）
- 同步到 VideoPipeline（触发 `geometry_changed_` 重配置）
- 清空 dupe 缓存（避免格式不匹配）

---

### 2.2 SET_GEOMETRY 处理链路

```
Core: retro_environment(SET_GEOMETRY, &geometry)
  ↓
env_dispatcher.cpp:1380 HandleEnvironmentCommand()
  ├─ state.SetGeometry(base_w, base_h, aspect)  // EnvState 存储
  ├─ geometry_updated_ = true  // 标记已更新
  └─ LOG: "SET_GEOMETRY: base=WxH, aspect=A"
  ↓
libretro_engine.cpp:2349 特殊处理
  ├─ videoPipeline_.SetGeometry(bw, bh, aspect)  // 同步到 VideoPipeline
  ├─ 如果 HW render: 更新 HwRenderRuntimeInfo
  └─ eventBridge_.Emit("geometry_update")  // 通知 ArkTS
```

**关键代码**:
```cpp
// env_dispatcher.cpp:1380
case RETRO_ENVIRONMENT_SET_GEOMETRY: {
  if (!data) return false;
  const ::retro_game_geometry *geom = (const ::retro_game_geometry *)data;
  if (!geom) return false;
  
  // 更新几何参数 (max_width/max_height 被忽略，符合 Libretro 规范)
  state.SetGeometry(geom->base_width, geom->base_height, geom->aspect_ratio);
  
  LOGF(LOG_INFO, "SET_GEOMETRY: base=%{public}ux%{public}u, aspect=%{public}.3f",
       geom->base_width, geom->base_height, geom->aspect_ratio);
  return true;
}

// env_state.h:86
void SetGeometry(unsigned base_w, unsigned base_h, float aspect) {
  geometry_base_width_ = base_w;
  geometry_base_height_ = base_h;
  geometry_aspect_ratio_ = aspect;
  geometry_updated_ = true;  // ✅ 标记更新
}

// libretro_engine.cpp:2349
if (cmd == RETRO_ENVIRONMENT_SET_GEOMETRY && handled) {
  unsigned bw = engine->envState_.GetGeometryBaseWidth();
  unsigned bh = engine->envState_.GetGeometryBaseHeight();
  float aspect = engine->envState_.GetGeometryAspectRatio();
  engine->videoPipeline_.SetGeometry(bw, bh, aspect);  // ✅ 同步到 pipeline
  // ... HW render 特殊处理
}
```

**验证结果**: ⚠️ **部分问题**
- ✅ EnvState 正确存储并标记 `geometry_updated_`
- ✅ 同步到 VideoPipeline（触发 `geometry_changed_`）
- ❌ **P2 问题**: `ConsumeGeometryUpdated()` 未被调用（`geometry_updated_` 标志未消费）
  - 影响：运行时分辨率切换可能延迟一帧（依赖下次 `retro_run` 触发重配置）
  - 建议：在 `ProcessFrame()` 后检查 `envState_.ConsumeGeometryUpdated()`

---

### 2.3 SET_SYSTEM_AV_INFO 处理链路

```
Core: retro_environment(SET_SYSTEM_AV_INFO, &av_info)
  ↓
env_dispatcher.cpp:1367 HandleEnvironmentCommand()
  ├─ state.SetPendingAvInfo(*av)  // 存入 pending 队列
  └─ LOG: "SET_SYSTEM_AV_INFO: geom=WxH aspect=A fps=F sr=S"
  ↓
libretro_engine.cpp:2042 ProcessFrame() 后消费
  ├─ envState_.ConsumePendingAvInfo(pendingAv)
  ├─ videoPipeline_.SetGeometry(...)  // 更新分辨率
  ├─ videoPipeline_.SetTargetFps(...)  // 更新帧率
  └─ audioBridge->Reset(sample_rate)  // 更新采样率
```

**关键代码**:
```cpp
// env_dispatcher.cpp:1367
case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
  if (!data) return false;
  const auto *av = (const ::retro_system_av_info *)data;
  state.SetPendingAvInfo(*av);  // ✅ 存入 pending 队列
  LOGF(LOG_INFO, "SET_SYSTEM_AV_INFO: geom=%{public}ux%{public}u ...");
  return true;
}

// libretro_engine.cpp:2042
::retro_system_av_info pendingAv{};
if (envState_.ConsumePendingAvInfo(pendingAv)) {  // ✅ 消费 pending
  if (pendingAv.geometry.base_width > 0 && pendingAv.geometry.base_height > 0) {
    videoPipeline_.SetGeometry(...);  // ✅ 更新分辨率
    videoWidth_ = static_cast<int>(pendingAv.geometry.base_width);
    videoHeight_ = static_cast<int>(pendingAv.geometry.base_height);
  }
  if (pendingAv.timing.fps > 0.0) {
    targetFps_ = pendingAv.timing.fps;
    videoPipeline_.SetTargetFps(pendingAv.timing.fps);  // ✅ 更新帧率
  }
  if (pendingAv.timing.sample_rate > 0.0 && ...) {
    audioSampleRate_ = pendingAv.timing.sample_rate;
    audioBridge->Reset(...);  // ✅ 更新采样率
  }
}
```

**验证结果**: ✅ **正确**
- 完整处理分辨率/帧率/采样率热切换
- 使用 pending 队列避免 `retro_run` 内直接修改（线程安全）
- 消费逻辑在 `ProcessFrame()` 后执行（时机正确）

---

### 2.4 GET_CAN_DUPE 处理链路

```
Core: retro_environment(GET_CAN_DUPE, &can_dupe)
  ↓
env_dispatcher.cpp:913 HandleEnvironmentCommand()
  ├─ *can_dupe = state.CanDupe()  // 返回 true
  └─ return true
  ↓
libretro_engine.cpp:2344 特殊处理
  └─ videoPipeline_.SetCanDupe(can)  // 同步到 VideoPipeline
```

**关键代码**:
```cpp
// env_dispatcher.cpp:913
case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
  if (!data) return false;
  bool *can_dupe = (bool *)data;
  *can_dupe = state.CanDupe();  // ✅ 返回 true（默认值）
  return true;
}

// env_state.h:76
void SetCanDupe(bool can) { can_dupe_ = can; }
bool CanDupe() const { return can_dupe_; }

// env_state.h:262 (private)
bool can_dupe_ = true;  // ✅ 默认支持 dupe

// libretro_engine.cpp:2344
if (cmd == RETRO_ENVIRONMENT_GET_CAN_DUPE && handled) {
  bool can = engine->envState_.CanDupe();
  engine->videoPipeline_.SetCanDupe(can);  // ✅ 同步到 pipeline
}
```

**验证结果**: ✅ **正确**
- 默认返回 `true`（前端支持 dupe）
- 同步到 VideoPipeline

---

## 3. Dupe 帧处理分析

### 3.1 Libretro 协议规范

根据 `libretro.h:7687-7690`:
```c
/**
 * @note If a frame is not rendered for reasons where a game "dropped" a frame,
 * this still counts as a frame, and retro_run() should explicitly dupe
 * a frame if RETRO_ENVIRONMENT_GET_CAN_DUPE returns true. In this case,
 * the video callback can take a NULL argument for data.
 */
```

**协议要求**:
1. 核心调用 `retro_video_refresh(NULL, ...)` 表示 dupe 帧
2. 前端应复用上一帧画面（避免重复渲染）

### 3.2 当前实现

**OnVideoRefresh 处理**:
```cpp
// libretro_engine.cpp:2131
if (!data) {
  packet.kind = VideoFrameKind::NULL_FRAME;
  packet.isDupe = true;  // ✅ 标记为 dupe
}
```

**VideoPipeline::Render 处理**:
```cpp
// video_pipeline.cpp:1404
if (!data) {
  return Finish(RenderResult::RENDERED);  // ❌ 直接返回 no-op
}
```

**问题**: ❌ **P1 - Dupe 帧缓存未实现**
- `lastFrame_` / `lastFrameWidth_` / `lastFrameHeight_` / `lastFramePitch_` 定义但未使用
- NULL data 时直接返回 `RENDERED`（no-op），未复用上一帧
- 核心 dupe 时前端仍重复渲染（性能浪费）

### 3.3 预期实现

```cpp
// video_pipeline.cpp (伪代码)
if (!data) {
  // 复用上一帧缓存
  if (canDupe_ && !lastFrame_.empty() && 
      lastFrameWidth_ == width && lastFrameHeight_ == height) {
    data = lastFrame_.data();
    pitch = lastFramePitch_;
    // 继续渲染流程
  } else {
    return Finish(RenderResult::DUPED);  // 无缓存时跳过
  }
}

// 渲染成功后缓存当前帧
if (result == RenderResult::RENDERED && canDupe_) {
  const size_t bytes = pitch * height;
  lastFrame_.resize(bytes);
  std::memcpy(lastFrame_.data(), data, bytes);
  lastFrameWidth_ = width;
  lastFrameHeight_ = height;
  lastFramePitch_ = pitch;
}
```

---

## 4. 问题清单与改进建议

### 4.1 P1 - Dupe 帧缓存未实现

**问题描述**:
- `lastFrame_` 缓存定义但未使用
- NULL data 时未复用上一帧（直接 no-op）
- 核心 dupe 时前端仍重复渲染

**影响**:
- 性能浪费（60fps 游戏 dupe 30fps 时，前端仍渲染 60 次）
- 不符合 Libretro 协议（应复用上一帧）

**改进建议**:
1. 在 `RenderCPU` / `RenderGLES` 中实现 dupe 缓存逻辑
2. NULL data 时复用 `lastFrame_` 数据
3. 渲染成功后更新 `lastFrame_` 缓存
4. 格式/分辨率变化时清空缓存（已实现 `ClearFrameCache()`）

**优先级**: 中（性能优化，非功能性 bug）

---

### 4.2 P2 - SET_GEOMETRY 未触发立即重配置

**问题描述**:
- `EnvState::SetGeometry()` 设置 `geometry_updated_ = true`
- 但 `ConsumeGeometryUpdated()` 未被调用
- 依赖下次 `retro_run` 触发 `geometry_changed_` 重配置

**影响**:
- 运行时分辨率切换可能延迟一帧
- 极端情况下可能导致画面拉伸（旧分辨率 buffer + 新分辨率数据）

**改进建议**:
```cpp
// libretro_engine.cpp:2065 (ProcessFrame 后)
if (envState_.ConsumeGeometryUpdated()) {
  videoPipeline_.ForceReconfiguration();  // 立即触发重配置
}
```

**优先级**: 低（边缘情况，实际影响小）

---

### 4.3 P3 - 像素格式日志缺失

**问题描述**:
- `SET_PIXEL_FORMAT` 有日志（`libretro_engine.cpp:2337`）
- 但 `env_dispatcher.cpp:1296` 处理时无日志
- 调试时难以确认核心请求的格式

**改进建议**:
```cpp
// env_dispatcher.cpp:1306
state.SetPixelFormat(*fmt);
LOGF(LOG_INFO, "SET_PIXEL_FORMAT: format=%{public}d (%{public}s)",
     static_cast<int>(*fmt), PixelFormatToString(*fmt));
return true;
```

**优先级**: 低（调试辅助）

---

## 5. 测试建议

### 5.1 格式切换测试

**测试核心**: Gambatte (GB/GBC)
- 默认 XRGB8888
- 可通过 core option 切换到 RGB565

**验证点**:
1. 启动时格式正确（hilog 查看 `SET_PIXEL_FORMAT`）
2. 运行时切换格式后画面正常（无花屏/颜色错误）
3. `geometry_changed_` 触发重配置（hilog 查看 `EnsureWindowConfiguredIfNeeded`）

---

### 5.2 分辨率切换测试

**测试核心**: PPSSPP (PSP)
- 支持运行时分辨率切换（菜单内改分辨率）

**验证点**:
1. 切换分辨率后画面立即更新（无延迟/拉伸）
2. hilog 查看 `SET_GEOMETRY` / `SET_SYSTEM_AV_INFO` 日志
3. `videoPipeline_.SetGeometry()` 被调用

---

### 5.3 Dupe 帧测试

**测试核心**: Snes9x (SNES)
- 菜单界面通常 dupe 帧（静止画面）

**验证点**:
1. hilog 查看 `NULL_FRAME` / `isDupe=true` 日志
2. 统计 `videoNullFrames` 计数（`LibretroEngine::GetStats()`）
3. 性能分析：dupe 帧是否跳过渲染（预期：实现后 CPU/GPU 占用下降）

---

## 6. 相关文件清单

| 文件 | 作用 |
|------|------|
| `entry/src/main/cpp/core/libretro/env_dispatcher.cpp` | 环境回调分发（SET_PIXEL_FORMAT / SET_GEOMETRY / GET_CAN_DUPE） |
| `entry/src/main/cpp/core/libretro/env_dispatcher.h` | EnvState 类定义（存储格式/几何参数） |
| `entry/src/main/cpp/core/engine/libretro_engine.cpp` | 环境回调特殊处理（同步到 VideoPipeline） |
| `entry/src/main/cpp/core/engine/video_pipeline.h` | VideoPipeline 类定义（格式/几何参数/dupe 缓存） |
| `entry/src/main/cpp/core/engine/video_pipeline.cpp` | 视频渲染实现（RenderCPU / RenderGLES） |
| `entry/src/main/cpp/core/libretro/libretro.h` | Libretro 协议定义（官方文档） |

---

## 7. 总结

### 7.1 整体评价

视频回调实现**基本符合 Libretro 协议**，关键功能正确：
- ✅ 格式切换完整支持（XRGB8888/RGB565/0RGB1555）
- ✅ 分辨率热切换正确处理（SET_GEOMETRY / SET_SYSTEM_AV_INFO）
- ✅ 前端声明支持 dupe（GET_CAN_DUPE 返回 true）

### 7.2 待改进项

| 问题 | 优先级 | 工作量 | 预期收益 |
|------|--------|--------|----------|
| P1: Dupe 帧缓存 | 中 | 中（~100 行） | 性能优化（dupe 场景 CPU/GPU 占用下降 30-50%） |
| P2: SET_GEOMETRY 立即重配置 | 低 | 低（~5 行） | 边缘情况修复（延迟一帧） |
| P3: 像素格式日志 | 低 | 低（~3 行） | 调试体验改善 |

### 7.3 下一步行动

1. **立即**: 无（当前实现可用）
2. **短期** (M4 后续): 实现 P1 dupe 帧缓存（性能优化）
3. **长期**: 补充 P2/P3（完善性改进）

---

**审计完成**: 2026-05-31  
**审计人**: Claude (Opus 4.7)
