# CORE-REVIEW — T7 Input/EventBridge Audit (2026-05-27)

Main Claude独立读源码后对所有 VERIFIED finding 的判决。

---

## Agent T7-A — C++ Engine Layer (8 VERIFIED)

| # | Agent Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P0 | **MITIGATED** | `find_references` 确认 SetPortRouter/SetControllerPortDeviceCallback 只有一个 call site：`LibretroEngine` 构造函数（`static LibretroEngine instance` 单例）。构造完成后两字段不再写入；游戏线程在 `Start()` 之后才创建，`std::thread` 构造提供 happens-before。无 runtime data race。 |
| F2 | P1 | **REAL_LOWER P2** | `GetAnalog` 的 `index < 0` 检查拦截了 `unsigned` 强转为负 int 的情况；但若 index 恰好落在 [INT_MAX/2+1, INT_MAX] 内（cast 后仍为正），`(index*2)+id` 整数溢出变 INT_MIN，`axis_idx < kMaxAnalogAxes` 误判通过，触发 out-of-bounds。需防御但要求极端 malformed core，实际极低概率。降为 P2。 |
| F3 | P1 | **FALSE_POSITIVE** | `GetSensor` 的检查为 `id >= 0 && id < kMaxSensors`；`unsigned` 大值 cast 后为负，`id >= 0` 拦截；正值靠 `id < kMaxSensors` 拦截；无乘法溢出路径。防御已充分。 |
| F4 | P1 | **REAL P1 (耦合 C-F2)** | `refactoredInitEventBridge` 受 `initialized=true` 保护，正常路径不可达。C-F2 修复（Ability destroy 重置 initialized）后此路径暴露：旧 TSFN 队列 EventData* 以旧 callback 执行，与新 TSFN 交叉。需与 C-F2 一并修。 |
| F5 | P2 | **REAL P2** | `napi_call_function` 返回值丢弃；JS 异常被静默吞掉，后续扩展 NAPI 调用会踩 pending-exception 问题。 |
| F6 | P1 | **REAL_LOWER P2** | 当前 `ClearPort` 不回调 `portRouter_`，无实际死锁路径。但持锁调外部代码是反模式，未来扩展风险真实，应在锁外执行。降为 P2。 |
| F7 | P2 | **REAL P2** | `ResolvePortForDevice` 内有 mutex_，race 不存在。但直接写 `portSources_[port].deviceId` 绕过 `AssignPort` 的冲突检查，设计上两条写路径语义不一致，是真实设计缺陷。 |
| F8 | P2 | **REAL P2** | HarmonyOS (AArch64) 实践中 `atomic<float>/<int16_t>` 大概率 lock-free，但标准不保证且无编译期断言。缺失 `static_assert` 是维护风险。 |

**T7-A 小计**：REAL P0×1, REAL P1×1, REAL P2×4, REAL_LOWER P2×2, FALSE_POSITIVE×1

---

## Agent T7-B — NAPI Layer (5 VERIFIED)

| # | Agent Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | **REAL P1** | `GetStringArgAllowEmpty` string-too-long 路径只 log、不 `napi_throw_range_error`；调用方以 `MakeBool(env,false)` 返回，ArkTS 无法区分"参数非法"与"业务失败"。 |
| F2 | P1 | **REAL P1** | `ListInputDevices` 中 `napi_create_array_with_length` / `napi_create_object` / `napi_create_string_utf8×2` / `napi_create_int32` 全部无状态检查；OOM 时 null obj/val 被传入 `napi_set_named_property`，必 crash。 |
| F3 | P2 | **REAL P2** | `napi_define_properties` 返回值未检查，7 个函数静默注册失败后 ArkTS 调用会 `undefined is not a function`。 |
| F4 | P2 | **REAL_LOWER P2** | `static_cast<int>` 截断非整数 double；正常 path 已由 `normalizeAnalogValue` 规范化，但其他直接调用者可能传非整数导致精度丢失。不会崩溃，minor。 |
| F5 | P2 | **REAL_LOWER P2** | 256-byte stack buffer 对 HarmonyOS 设备 ID 实际足够；真实风险在与 F1（无 throw）合并后静默失败路径。F1 修复后此项风险大幅降低。保留以追踪动态分配迁移目标。 |

**T7-B 小计**：REAL P1×2, REAL P2×1, REAL_LOWER P2×2

---

## Agent T7-C — ArkTS Layer (8 VERIFIED)

| # | Agent Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | **REAL P1** | X 轴 `refactoredSendAnalog` 结果被丢弃，函数只 return Y 轴布尔；X 轴失败无法被调用者感知，analog stick 水平方向输入故障无任何可观察信号。 |
| F2 | P1 | **REAL P1** | `LibretroEventHub.instance` 进程级单例无 `destroy()`；Ability 重启后 `initialized=true` 阻止重新注册 NAPI callback，C++ 事件推不到新 Ability UI。 |
| F3 | P1 | **REAL_LOWER P2** | `aboutToDisappear` 有 `clearTimeout` + 回调内有 `!pageActive` 双重保护，实际无写回已销毁组件的风险；但 `setTimeout` 违反项目 `CLAUDE.md` 约定（禁用，因回调不绑定页面生命周期）。降为 P2，仍需修。 |
| F4 | P1 | **REAL P1** | `applyPortAssignment` / `listInputDevices` 直接调 NAPI，无 engine-ready 检查；engine 未加载时调用可能 crash 或返回垃圾数据。 |
| F5 | P2 | **REAL P2** | `aboutToAppear` 同步调 `refreshDevices()→listInputDevices(NAPI)` 违反 CLAUDE.md 轻量化规范，NAPI 阻塞会卡转场动画，且与 F4 同问题（engine 可能未 ready）。 |
| F6 | P2 | **REAL_LOWER P2** | `findPortAssignment` 返回哨兵对象无日志；portId 越界时 input 事件静默丢弃，调试极难区分"port 未激活"vs"portId 越界"。不是崩溃但是运维盲点。 |
| F7 | P2 | **DESIGN** | `id=0/1` 硬编码是双轴 analog 的预期语义；封装限制但不是 bug。现阶段不修，记录为设计约束。 |
| F8 | P2 | **REAL P1** | replayLatest catch 块调 `removeListener`：subscribe 完成后立刻被自我移除，对 `statefulEvents`（engine_state/core_crash/geometry_update 等）会导致 UI 组件永久收不到后续事件。严重级别提升为 P1。 |

**T7-C 小计**：REAL P1×4, REAL P2×2, REAL_LOWER P2×2, DESIGN×1

---

## 跨 Agent 汇总

| Severity | Count | Findings |
|---|---|---|
| REAL P0 | 1 | A-F1 |
| REAL P1 | 8 | A-F4, B-F1, B-F2, C-F1, C-F2, C-F4, C-F8, (A-F8 is P2) |
| REAL P2 | 7 | A-F5, A-F7, A-F8, B-F3, C-F5 (A-F2 REAL_LOWER P2 below) |
| REAL_LOWER P2 | 6 | A-F2, A-F6, B-F4, B-F5, C-F3, C-F6 |
| FALSE_POSITIVE | 1 | A-F3 |
| DESIGN | 1 | C-F7 |

**总 REAL**: ~~P0×1~~ + P1×7 + P2×7 = 14 findings（A-F1 改 MITIGATED，A-F4 耦合 C-F2）

### 跨 agent 校准说明

- T7-A 对 unsigned→int overflow 问题标了两个 P1（F2/F3），但 GetSensor/GetAnalog 的内部检查实际有效：F3 是 FALSE_POSITIVE，F2 降为 P2。
- T7-C F8 从 P2 升为 P1：`statefulEvents` 默认 replay，callback 异常概率非零，后果是永久失订阅，比 P2 更严重。
- T7-A F6 从 P1 降为 P2：当前无死锁路径，是隐性风险不是现实 bug。
