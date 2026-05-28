# T2 — Engine 状态机

## Scope
LibretroEngine 状态机、消息队列、`retro_run` 调度。

**Files**: `entry/src/main/cpp/core/engine/libretro_engine.*`

## Hazards
- state transitions — INIT → RUNNING / PAUSED / STOPPED 的非法跳转
- message queue races — 发消息与 GameLoop 处理消息的并发
- retro_run reentrancy — frame callback 中再次进入 retro_run / 切核期间 retro_run 仍在跑
- cleanup ordering — UnloadGame 与 RetroDeinit 的顺序、回调清空与最后一次 retro_run 冲突
- transition guard — LoadCore 时仍处于 RUNNING、Stop 时仍在 LoadRom

## Done criteria 模板(场景驱动)
- [ ] 所有非法 state transition 在 message handler 入口被拒,带 hilog 警告
- [ ] retro_run 正在执行时,Stop / LoadCore 走 message queue 不直接打断
- [ ] 切核流程下 cleanup 顺序固定: Pause → UnloadGame → RetroDeinit → CoreUnload
- [ ] enum / struct 跨文件改动通过 `find_workspace_symbols` 清完所有引用

## 必用 MCP
`mcp__cclsp__find_workspace_symbols` — 跨文件 enum / struct 引用。
