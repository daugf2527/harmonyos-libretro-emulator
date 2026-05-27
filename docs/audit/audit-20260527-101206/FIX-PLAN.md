# FIX-PLAN — T7 Input/EventBridge (2026-05-27)

Selected: all 14 REAL findings (P1×7 + P2×7)

## Batch 1 — C++ non-NAPI

| Finding | File | Fix shape |
|---|---|---|
| A-F4 | event_bridge.cpp:79 | `napi_tsfn_release` → `abort` then `release` |
| A-F5 | event_bridge.cpp:219 | 检查 `napi_call_function` 返回值，clear pending exception |
| A-F2 | input_snapshot.h:84 | GetAnalog 加 `index >= 16 \|\| id >= 2` 防乘法溢出 |
| A-F7 | input_port_router.cpp:188 | auto-bind 前加 `deviceToPort_.count(deviceId)==0` 防双绑 |
| A-F8 | input_snapshot.h | 加 `static_assert` 验证 lock-free 假设 |

## Batch 2 — NAPI (需 napi-boundary-reviewer 预审后才 Edit)

| Finding | File | Fix shape |
|---|---|---|
| B-F1 | engine_napi_common.h:133 | size>=outSize 时加 `napi_throw_range_error` |
| B-F2 | engine_input_napi.cpp:138 | napi_create_* 全部检查返回值，失败时 throw+return nullptr |
| B-F3 | engine_input_napi.cpp:232 | 检查 napi_define_properties 返回值 |

## Batch 3 — ArkTS

| Finding | File | Fix shape |
|---|---|---|
| C-F2 | LibretroEventHub.ets + EntryAbility.ets | 加 `static destroy()` 重置单例；onDestroy 调用 |
| C-F8 | LibretroEventHub.ets:307-309 | replay catch 块删 removeListener，仅 logCallbackError |
| C-F1 | RuntimeInputCommandBridge.ets:36 | X 轴结果存变量，两轴 && 后返回 |
| C-F4 | RuntimeInputPortController.ets | NAPI 调前加 engine-ready 守卫 |
| C-F5 | MultiplayerInputPage.ets:100 | refreshDevices 加 async + 首行 await，调用改 void fire-and-forget |
| C-F6 | InputPortRouting.ts:85 | findPortAssignment 找不到时加 warn log |
