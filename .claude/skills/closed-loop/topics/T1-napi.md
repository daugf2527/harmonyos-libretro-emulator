# T1 — NAPI 边界

## Scope
ArkTS ↔ C++ 互调的 NAPI 层。

**Files**: `entry/src/main/cpp/app/napi/`

## Hazards
- env lifetime — `napi_env` 跨线程访问 / TSFN 已 release 仍被 callback
- TSFN thread — abort 顺序、callback 队列残留、aborted 状态后还 acquire
- ArkTS↔C++ type — Number 隐式转换、anonymous interface 漏类型、ESObject 滥用
- error-throw — `napi_throw_error` 后 caller 没接 pending exception → 函数照常返回
- ref + buffer lifecycle — `napi_create_reference` / `napi_delete_reference` 配对、ArrayBuffer detach

## Done criteria 模板(场景驱动)
- [ ] 切核 / 退出场景下,所有 TSFN 已 abort 且无 callback 残留
- [ ] 任意 NAPI helper 抛错后,**所有** caller 都识别 pending exception 并提前返回
- [ ] napi_ref 创建与删除 1:1 配对,无 leak
- [ ] ArrayBuffer 跨语言传递时,生命周期所有权清楚(detach 后 C++ 侧不再访问)
- [ ] `napi-boundary-reviewer` agent 对每个 fix verdict ≠ block

## 必用 MCP
`mcp__cclsp__find_references` / `mcp__cclsp__get_incoming_calls` —
NAPI 改动**禁止**只用 Grep,会漏 ArkTS 侧 EventBridge / TSFN 引用。
