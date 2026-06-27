# 代码现状深度审计报告

**审计日期**: 2026-05-31  
**审计方法**: cclsp/serena MCP 工具 + 3 个并行 agent 深挖代码实物  
**对比基准**: Roadmap.md + docs/reference/known-issues.md 的文档描述

---

## 执行摘要

**关键发现**: Roadmap.md 中标记为 P0/P1 的 **5 个问题中有 4 个已修复或描述过时**，文档与代码实现严重脱节。

| 问题 | Roadmap 优先级 | 代码真实状态 | 建议优先级 |
|------|---------------|-------------|-----------|
| Audio RingBuffer 非阻塞写入 | P0 止血级 | ❌ 已修复（SyncMode 双模式，默认阻塞） | 移除或改 P2 |
| Frame Pacing 丢失 | P0 止血级 | ❌ 已实现（软件节拍 + sleep 补齐） | 移除或改 P1 |
| GLES PBO 缺失 | P1 性能级 | ⚠️ 已实现但禁用（驱动兼容性） | P2 优化项 |
| HwRender glGet 冗余 | P1 性能级 | ❌ 不存在（每帧 2 次必要调用） | 删除 |
| Input Mapper 缺失 | P2 功能级 | ✅ 确认存在（硬编码 10 个键位） | P2 |
| Analog 输入未打通 | P2 功能级 | ❌ 已修复（NAPI/ArkTS 链路完整） | 移除 |

---

## 详细审计结果

### 1. Audio RingBuffer "非阻塞写入导致伪快进" (P0)

**Roadmap 描述** (L36):
> RingBuffer 非阻塞写入 (导致伪快进)

**代码真实状态**:
- ✅ `Write()` 和 `WriteWait()` 双接口已实现 (`ring_buffer.cpp:106-225`)
- ✅ `AudioBridge::ProcessAudio` 根据 `SyncMode` 动态选择 (`audio_bridge.cpp:348-356`):
  ```cpp
  bool should_block = (sync_mode_.load() == SyncMode::AUDIO_BLOCKING && !buffering_snapshot);
  if (should_block) {
    success = buffer_ref->WriteWait(out_buf_data, samples_to_write, running_);
  } else {
    success = buffer_ref->Write(out_buf_data, samples_to_write);
  }
  ```
- ✅ 默认模式: `AUDIO_BLOCKING` (`audio_bridge.h:83-84`)

**结论**: ❌ **问题已修复**，Roadmap 描述过时。阻塞写入已实现且默认启用，非阻塞仅在 Fast Forward 或 buffering 时使用。

**建议**: 从 P0 移除，或改为 P2 优化项（DRC 微调策略）。

---

### 2. Frame Pacing "丢失" (P0)

**Roadmap 描述** (L37):
> Frame Pacing 丢失

**代码真实状态**:
- ✅ GameLoop 主循环已实现软件 Frame Pacing (`libretro_engine.cpp:1175-1195`):
  ```cpp
  ProcessFrame();  // 调用 retro_run()
  // 节拍器：兜底 sleep 到目标帧时间
  const double safeTargetFps = (targetFps_ > 0.0) ? targetFps_ : 60.0;
  const int64_t targetFrameUs = static_cast<int64_t>(1000000.0 / safeTargetFps);
  const int64_t elapsedUs = ...;
  if (elapsedUs < targetFrameUs) {
    const int64_t remainingUs = targetFrameUs - elapsedUs;
    if (remainingUs > 200) {
      std::this_thread::sleep_for(std::chrono::microseconds(remainingUs - 100));
    }
  }
  ```
- ✅ 注释明确说明: "若 retro_run 内部未走视频管线节拍，这里兜底 sleep 到目标帧时间，避免 frameCount 飙升到 1000+ FPS"
- ⚠️ 硬件 vsync 存在但未在主路径使用

**结论**: ❌ **问题已修复**，软件 Frame Pacing 已实现。

**建议**: 从 P0 移除，或改为 P1 优化项（硬件 vsync 集成）。

---

### 3. GLES PBO "缺失" (P1)

**Roadmap 描述** (L31):
> GLES PBO 缺失 (同步上传卡顿)

**代码真实状态**:
- ✅ PBO 基础设施已实现:
  - Ring buffer 数据结构 (`gles_renderer.h:144-146`)
  - PBO 管理函数 (`gles_renderer.cpp:87-209`)
  - Fence sync 等待逻辑 (`BeginUploadScratch`, `EndUploadScratch`)
- ⚠️ **已禁用** (`gles_renderer.cpp:1041-1044`):
  ```cpp
  // Driver compatibility path:
  // For some Harmony devices/simulators, PBO upload path can produce noisy
  // driver-side diagnostics. Use direct texture upload for stable behavior.
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  ```
- ✅ 当前使用直接上传 (`glTexSubImage2D`)，稳定可用

**结论**: ⚠️ **已实现但因驱动兼容性禁用**，不是"缺失"。

**建议**: 改为 P2 优化项 "GLES PBO 已实现但因驱动兼容性禁用（性能优化）"。

---

### 4. HwRender glGet "冗余" (P1)

**Roadmap 描述** (L32):
> HwRender 状态保存冗余 (glGet 严重拖慢)

**代码真实状态**:
- ✅ 每帧仅 2 次必要 `glGetIntegerv` (`gles_renderer.cpp:1072-1073`):
  ```cpp
  // Audit T4-F6: always query the current GL unpack state before overwriting it.
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &prevUnpackAlignment);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &prevUnpackRowLength);
  ```
- ✅ 注释明确说明: "Two glGetIntegerv calls per frame are cheap"
- ✅ 这是 Audit T4-F6 修复的正确做法（防止覆盖 HW libretro core 自己的 unpack 设置）
- ⚠️ 诊断模式额外 4-6 次调用，但生产环境默认关闭

**结论**: ❌ **问题不存在**，每帧 2 次 glGetIntegerv 是必要且廉价的。

**建议**: 从 Roadmap 删除。

---

### 5. Input Mapper "缺失" (P2)

**Roadmap 描述** (L29):
> Input Mapper 缺失：无法自定义键位

**代码真实状态**:
- ✅ 硬编码确认存在 (`plugin_manager.cpp:217-256`):
  ```cpp
  static bool MapKeyCodeToJoypad(OH_NativeXComponent_KeyCode code, int &outId) {
    switch (code) {
    case KEY_DPAD_UP:    outId = RETRO_DEVICE_ID_JOYPAD_UP; return true;
    case KEY_Z:          outId = RETRO_DEVICE_ID_JOYPAD_B; return true;
    case KEY_X:          outId = RETRO_DEVICE_ID_JOYPAD_A; return true;
    // ... 共 10 个硬编码映射
    }
  }
  ```
- ❌ 全仓库未找到 `InputMapper` 类或 keymap 配置机制
- ❌ 无法通过配置文件或 UI 自定义键位

**结论**: ✅ **问题确认存在**，优先级合理（P2 功能级）。

**建议**: 保持 P2 优先级。

---

### 6. Analog 输入 "未打通" (P2)

**Roadmap 描述** (L28):
> 输入快照"analog"入口未打通：存在 SetAnalog，但未暴露 SendAnalog/NAPI 接口

**代码真实状态**:
- ✅ `SendAnalog` 已实现 (`input_manager.cpp:105-111`)
- ✅ NAPI 接口已暴露 (`engine_input_napi.cpp:37-72`, 注册为 `refactoredSendAnalog`)
- ✅ ArkTS 已调用 (`RuntimeInputCommandBridge.ets:48-49` + `LibretroNewArchTestPage.ets`)
- ✅ 完整链路: ArkTS → NAPI → InputManager → InputSnapshot

**结论**: ❌ **问题已修复**，Roadmap 描述滞后。

**建议**: 从 Roadmap 移除，或改为 "~~已修复~~"。

---

## 真实功能缺口清单（按优先级）

### P0 止血级
**无** — 原 P0 问题均已修复或不存在。

### P1 性能级
1. **M1 ROM/I-O 治理实施** (Phase 2-3 设计完成但 BLOCKED)
   - Phase 2: C++/ArkTS 跨层改动 (预计 2-3h)
   - Phase 3: 双 Repository 合并 (预计 7.5-10.5h)
2. **M5 HW_RENDER 基础闭环** (进行中，Vulkan 验证待完成)

### P2 功能级
1. **Input Mapper 缺失** ✅ 确认存在
   - 硬编码 10 个键位，无配置化机制
   - 影响用户体验但不阻塞核心功能
2. **M6 内容与配置** (多核心/多 ROM 管理，核心选项持久化)
3. **M7 交互与多形态** (折叠屏布局，虚拟手柄交互)

### P2 优化项（非阻塞）
1. **GLES PBO 启用** (已实现但因驱动兼容性禁用)
2. **硬件 vsync 集成** (软件 Frame Pacing 已足够，硬件 vsync 可进一步优化)
3. **M4 dupe 帧缓存优化** (性能浪费 30-50%，但不影响功能)

---

## 建议行动

### 立即行动
1. **更新 Roadmap.md**:
   - 删除 L36-37 (Audio RingBuffer / Frame Pacing)
   - 删除 L32 (glGet 冗余)
   - 修改 L31 (PBO 缺失 → PBO 已实现但禁用)
   - 修改 L28 (Analog 未打通 → ~~已修复~~)

2. **重新排优先级**:
   - P0: 无（原 P0 问题已修复）
   - P1: M1 Phase 2-3 实施 + M5 Vulkan 验证
   - P2: Input Mapper + M6 + M7

### 下一步规划
按新优先级选择：
- **快速见效** (1-2 周): M1 Phase 2 实施 (2-3h) + Input Mapper 基础框架
- **系统性完善** (2-4 周): M1 Phase 3 双 Repository 合并 + M5 Vulkan 验证
- **功能扩展** (按需): M6 多核心管理 + M7 折叠屏适配

---

## 附录：审计方法

1. **MCP 工具链**:
   - `cclsp`: C++ 符号查找、引用追踪、调用链分析
   - `serena`: 全仓库符号概览、跨语言引用
   - `grep`: 文本模式匹配、代码统计

2. **并行 agent**:
   - Agent 1: Input Mapper + Analog 输入分析
   - Agent 2: Audio RingBuffer + Frame Pacing 分析
   - Agent 3: GLES PBO + glGet 性能分析

3. **验证原则**:
   - 不信任文档描述，直接读代码实物
   - 追踪完整调用链，确认功能是否真正可用
   - 统计调用频率，区分"必要"与"冗余"
