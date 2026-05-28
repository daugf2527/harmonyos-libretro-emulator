# T7 — Input / EventBridge 跨层

## Scope
输入 + 跨语言事件路由(ArkTS hub ↔ C++ bridge ↔ libretro input)。

**Files**:
- `cpp/app/napi/engine_input_napi.cpp`
- `cpp/core/engine/event_bridge.cpp`
- `cpp/core/input/input_snapshot.h`
- `cpp/core/input/input_port_router.cpp`
- `ets/common/LibretroEventHub.ets`
- `ets/common/RuntimeInputCommandBridge.ets`
- `ets/common/RuntimeInputPortController.ets`
- `ets/pages/MultiplayerInputPage.ets`

## Hazards
- input snapshot atomicity — InputSnapshot 多字段更新需原子或外层锁
- 整数溢出 — joystick axis × 32767 / button state bit shift
- TSFN release+abort 顺序 — 必须 abort 后 release,反之 callback 队列残留
- CallJsHandler pending-exception — JS callback 抛错后 C++ 侧没接,继续 retro_run
- 跨层 event 路由 — ArkTS hub event ↔ C++ EventBridge ↔ libretro `input_state`
- engine-ready guard — engine 未就绪期间 ArkTS 侧不应发 input event
- async lifecycle — `replayLatest` catch 反模式 / removeListener 漏调 / Hub singleton destroy
- NAPI error-throw helper 一致性 — 所有 throw helper 都要给 caller pending-exception 信号

## Done criteria 模板(场景驱动)
- [ ] 切核重启场景下 input 不再重发已释放的 TSFN
- [ ] ArkTS 侧 hub 离页后 C++ 侧 listener 自动清理(removeListener 调用证据)
- [ ] joystick / button 极端值(int16 边界、按住所有按键)无溢出 / 无 crash
- [ ] CallJsHandler 抛 JS 异常路径下 retro_run 不继续 / 不上 callback 队列残留
- [ ] `replayLatest` 内 catch 不再吞错,改 propagate 或显式标记 last-error
- [ ] engine 未 RUNNING 时 ArkTS 侧 input 入口短路 + hilog 警告

## 必用 MCP
- `mcp__cclsp__find_references` — engine_input_napi 函数的 ArkTS / C++ 双向 caller
- `mcp__serena__find_referencing_symbols` — LibretroEventHub 跨 .ets 文件引用
- `mcp__cclsp__get_incoming_calls` — TSFN 释放路径调用链
