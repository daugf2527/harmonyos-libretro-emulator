# Fix Static Issues Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复事件名映射、音频 bypass 返回值、传感器精度、ROM 大小限制与 CUE 解析稳健性问题。

**Architecture:** 在不改动整体架构的前提下，局部修复 EventBridge 事件映射、AudioBridge 写入流程、输入传感器类型与资源管理器文件大小检查，并增强 CUE 解析的大小写与字符处理。

**Tech Stack:** C++17, HarmonyOS NAPI/NativeWindow, libretro

---

### Task 1: 修复 EventBridge 事件名映射

**Files:**
- Modify: `entry/src/main/cpp/core/engine/event_bridge.h`
- Modify: `entry/src/main/cpp/core/engine/event_bridge.cpp`

**Step 1: 手动复现并记录现状（不写测试脚本）**

触发一次 `core_crash/engine_state/rumble` 等事件，记录 JS 侧事件名是否变为 `"unknown"`。

**Step 2: 修改枚举与映射（最小变更）**

在 `EventType` 中补全当前使用的事件名，并在 `GetEventName/GetEventType` 中补全映射：

```cpp
enum class EventType {
  FPS_UPDATE,
  AUDIO_STATUS,
  GEOMETRY_UPDATE,
  OPTIONS_UPDATE,
  PIXEL_FORMAT_UPDATE,
  CORE_MESSAGE,
  CORE_ERROR,
  CORE_CRASH,
  ENGINE_STATE,
  DISK_CONTROL,
  RUMBLE,
  SENSOR_STATE,
  UNKNOWN
};
```

```cpp
case EventBridge::EventType::CORE_CRASH: return "core_crash";
case EventBridge::EventType::ENGINE_STATE: return "engine_state";
case EventBridge::EventType::DISK_CONTROL: return "disk_control";
case EventBridge::EventType::RUMBLE: return "rumble";
case EventBridge::EventType::SENSOR_STATE: return "sensor_state";
```

```cpp
if (event == "core_crash") return EventBridge::EventType::CORE_CRASH;
if (event == "engine_state") return EventBridge::EventType::ENGINE_STATE;
if (event == "disk_control") return EventBridge::EventType::DISK_CONTROL;
if (event == "rumble") return EventBridge::EventType::RUMBLE;
if (event == "sensor_state") return EventBridge::EventType::SENSOR_STATE;
```

**Step 3: 手动验证**

再次触发事件，确认 JS 收到原始事件名，不再是 `"unknown"`。

**Step 4: Commit（可选）**

```bash
git add entry/src/main/cpp/core/engine/event_bridge.h \
       entry/src/main/cpp/core/engine/event_bridge.cpp
git commit -m "fix(event): restore event name mapping"
```

---

### Task 2: 修复 AudioBridge bypass 返回值与状态更新

**Files:**
- Modify: `entry/src/main/cpp/platform/audio/audio_bridge.cpp`

**Step 1: 手动复现并记录现状（不写测试脚本）**

在输入/输出采样率一致的场景，观察缓冲是否能从 buffering 状态切换到播放（日志或 UI）。

**Step 2: 统一写入路径（避免 bypass 早退）**

将 bypass 分支调整为设置 `out_frames = frames` 并复用统一写入逻辑；写入失败时返回 `0`，写入成功时返回 `frames`：

```cpp
bool bypass = (resampler_.GetRatio() == 1.0);
size_t out_frames = 0;
if (bypass) {
  // 拷贝 data -> resample_out_buf_
  out_frames = frames;
} else {
  out_frames = resampler_.Resample(...);
  if (out_frames == 0) { return 0; }
}
// 统一写入 ring buffer + 日志 + buffering 检查
return success ? frames : 0;
```

**Step 3: 手动验证**

确认 bypass 场景下写入失败不会返回 `out_frames`，且 buffering 能正常结束。

**Step 4: Commit（可选）**

```bash
git add entry/src/main/cpp/platform/audio/audio_bridge.cpp
git commit -m "fix(audio): unify bypass write path"
```

---

### Task 3: 修复传感器值精度丢失

**Files:**
- Modify: `entry/src/main/cpp/interfaces/input/i_input_manager.h`
- Modify: `entry/src/main/cpp/core/engine/input_manager.h`
- Modify: `entry/src/main/cpp/core/engine/input_manager.cpp`
- Modify: `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`

**Step 1: 手动复现并记录现状（不写测试脚本）**

通过 ArkTS 发送非整数传感器值，确认当前值被截断。

**Step 2: 调整接口类型为 float**

```cpp
// i_input_manager.h
virtual bool SendSensor(int port, int id, float value) = 0;

// input_manager.h/.cpp
bool SendSensor(int port, int id, float value) override;
inputSnapshot_.SetSensor(port, id, value);

// libretro_engine_napi.cpp
const bool ok = input->SendSensor(port, id, static_cast<float>(value));
```

**Step 3: 手动验证**

确认 JS 侧传入的浮点值能保持小数精度。

**Step 4: Commit（可选）**

```bash
git add entry/src/main/cpp/interfaces/input/i_input_manager.h \
       entry/src/main/cpp/core/engine/input_manager.h \
       entry/src/main/cpp/core/engine/input_manager.cpp \
       entry/src/main/cpp/app/napi/libretro_engine_napi.cpp
git commit -m "fix(input): keep sensor float precision"
```

---

### Task 4: 恢复 ROM 大小上限检查

**Files:**
- Modify: `entry/src/main/cpp/platform/resource/platform_resource_manager.cpp`

**Step 1: 手动复现并记录现状（不写测试脚本）**

尝试加载异常大的 ROM，确认当前无文件大小限制。

**Step 2: 添加文件大小限制**

```cpp
constexpr size_t kMaxSize = 512ULL * 1024ULL * 1024ULL;
if (size <= 0 || static_cast<size_t>(size) > kMaxSize) {
  LOGF(LOG_ERROR, "ROM file too large or invalid size: ...");
  return false;
}
```

**Step 3: 手动验证**

确认超过上限的文件被拒绝加载。

**Step 4: Commit（可选）**

```bash
git add entry/src/main/cpp/platform/resource/platform_resource_manager.cpp
git commit -m "fix(resource): restore rom size guard"
```

---

### Task 5: CUE 解析大小写与字符稳健性

**Files:**
- Modify: `entry/src/main/cpp/common/cue_parser.cpp`

**Step 1: 手动复现并记录现状（不写测试脚本）**

使用包含 `File`/`file` 行的 CUE，确认解析结果是否缺失。

**Step 2: 大小写无关匹配 + 安全 isspace**

```cpp
std::string upper = trimmed;
std::transform(upper.begin(), upper.end(), upper.begin(),
               [](unsigned char c){ return static_cast<char>(std::toupper(c)); });
if (upper.rfind("FILE", 0) == 0) { ... }

while (pos < trimmed.size() && std::isspace(static_cast<unsigned char>(trimmed[pos]))) {
  pos++;
}
```

**Step 3: 手动验证**

确认不同大小写 `FILE` 均可识别。

**Step 4: Commit（可选）**

```bash
git add entry/src/main/cpp/common/cue_parser.cpp
git commit -m "fix(cue): case-insensitive file parsing"
```

---

# Execution Options

Plan complete and saved to `docs/plans/2026-01-29-fix-static-issues.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration
2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
