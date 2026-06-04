# HarmonyOS Libretro Emulator — 全方位质检计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 对 `fcacd2d` 提交以来的 17 个变更文件进行多维度并行审计，输出 findings + 风险等级

**Architecture:** 按独立维度分 2 批 3-agent 并行；Batch 1 覆盖 NAPI/音频/核心引擎；Batch 2 覆盖文档/ArkTS 侧对齐/综合；最终合并为报告

**Tech Stack:** C++17、HarmonyOS API22、NAPI、OHAudio API20+、RawFile64 API

---

## 变更范围（本次 HEAD 未提交）

| 文件 | 变更量 | 类别 |
|------|--------|------|
| `engine_napi_common.h` | +27 | NAPI 错误码命名常量 |
| `engine_lifecycle_napi.cpp` | +43/-43 | NAPI 错误码引用替换 |
| `engine_state_napi.cpp` | +8/-6 | NAPI 错误码引用替换 |
| `audio_player.cpp` | +55 | OHAudio 设备变化/错误回调 |
| `audio_player.h` | +18 | 新回调声明 |
| `platform_resource_manager.cpp` | +30/-28 | RawFile → RawFile64 迁移 |
| `CMakeLists.txt` | +7 | 测试目标链接库 |
| `video_pipeline.cpp` | -9 | 删除 fallback define |
| `window_state_manager.cpp` | -9 | 删除 fallback define |
| `test_gambatte_rom.cpp` | +42/-12 | RawFile64 迁移 + 健壮性 |
| `CLAUDE.md` | +344/-244 | 添加 COMMON.md @import |
| `AGENTS.md` | +13 | 添加公共行为准则 |
| `docs/harmonyos-sdk-target.md` | +25 | API22 目标更新 |
| `docs/napi-error-code-mapping.md` | +16 | 错误码映射表更新 |
| `docs/tech-debt-tracker.md` | +8 | 技术债跟踪更新 |

---

## Batch 1（三路并行 opus agents）

### Task A: NAPI 边界审计

**Agent type:** napi-boundary-reviewer  
**Files:**
- `entry/src/main/cpp/app/napi/engine_napi_common.h`
- `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp`
- `entry/src/main/cpp/app/napi/engine_state_napi.cpp`
- `entry/src/main/ets/common/ErrorCodes.ets`（对齐验证）

**检查项:**
1. `EngineErrorCodes` + `NapiErrorCodes` namespace 覆盖是否完整（有无遗漏魔数）
2. `SRAM_LOAD_FAILED=3032` 定义了但 engine_state_napi.cpp 里 LoadSram 是否还用魔数
3. ArkTS `ErrorCodes.ets` 与 C++ namespace 数值是否完全对齐
4. 是否有 napi_env lifetime / pending-exception 风险

### Task B: 音频 + 资源 + 构建审计

**Agent type:** general-purpose  
**Files:**
- `entry/src/main/cpp/platform/audio/audio_player.cpp`
- `entry/src/main/cpp/platform/audio/audio_player.h`
- `entry/src/main/cpp/platform/resource/platform_resource_manager.cpp`
- `entry/src/main/cpp/CMakeLists.txt`
- `entry/src/main/cpp/tests/integration/test_gambatte_rom.cpp`

**检查项:**
1. `OnRendererError` 设置 `pending_interrupt_stop_.store(true)` — 消费端是否正确检查此标志
2. `OnOutputDeviceChange` 仅日志无行动 — 是否足够？需要触发重采样吗？
3. `CallbackGuard` 在两个新回调里的正确性
4. `RawFile64` 迁移：`raw_file.h` 头文件是否提供 `RawFile64` 类型（vs `raw_file_manager.h`）
5. CMakeLists 新增 `libace_napi.z.so` + `librawfile.z.so` — API22 这些库名是否正确
6. Test 里的 `kMaxRomSize = 512MB` 和 `platform_resource_manager.cpp` 里的同值是否保持一致

### Task C: 核心引擎 + 文档一致性审计

**Agent type:** general-purpose  
**Files:**
- `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- `entry/src/main/cpp/core/engine/window_state_manager.cpp`
- `CLAUDE.md`, `AGENTS.md`
- `docs/harmonyos-sdk-target.md`
- `docs/napi-error-code-mapping.md`
- `docs/tech-debt-tracker.md`

**检查项:**
1. `SET_BUFFER_GEOMETRY` 和 `SET_SWAP_INTERVAL` 的 fallback define 被删除 — API22 SDK 是否真的提供这些宏？
2. `CLAUDE.md` 新增 `@C:/Users/newwo/.cc-switch/agent-policy/COMMON.md` — 是否导致与 AGENTS.md 内容双轨重复
3. `AGENTS.md` 新增"公共行为准则" — 与 COMMON.md 关系是否清晰
4. docs/napi-error-code-mapping.md 里的错误码表是否与新 namespace 常量对齐
5. docs/harmonyos-sdk-target.md 的 API22 目标描述是否准确

---

## Batch 2（Batch 1 完成后）

### Task D: ArkTS 侧 + 交叉验证

**检查项:**
1. ArkTS `ErrorCodes.ets` 完整对照验证
2. 跨层调用链完整性（C++ namespace → NAPI → ArkTS EventHub）
3. 有无 Batch 1 遗漏的跨维度风险

### Task E: 综合报告合成

将所有 findings 合并为 `docs/audit-report-2026-06-04.md`

---

## Done Criteria

- [ ] Batch 1 三个 agent 返回 findings
- [ ] Batch 2 交叉验证完成
- [ ] 最终报告写入 `docs/audit-report-2026-06-04.md`
- [ ] 报告包含：问题清单（P0/P1/P2）+ 各维度 PASS/FAIL + 建议动作
