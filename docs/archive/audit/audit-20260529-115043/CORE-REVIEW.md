# Core Review — audit-20260529-115043

Review completed: 2026-05-29 11:57

## Agent T8 — 1 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | **REAL_LOWER P2** | SaveStatePage.loadSave() 使用同步 NAPI 调用。原 claim "游戏未运行时 5s 冻结"是误判（line 2666 立即返回 false）。实际问题：游戏运行时同步调用可能阻塞 UI 线程，但正常情况下毫秒级完成。主要是代码一致性问题：quickSave() 已改用 async (line 250)，loadSave() 应保持一致。 |

## Verdict 判定依据

### F1 — REAL (P1)

**MCP 验证**:
- ✅ 确认 `refactoredLoadState` (同步) 和 `refactoredLoadStateAsync` (异步) 都存在
- ✅ 同步版本调用 `GetEngine()->LoadState()` → `ExecuteSyncTask` → 最长阻塞 5s (kSyncTaskTimeoutMs)
- ✅ SaveStatePage.quickSave() 已改用 async 版本 (line 250: `refactoredSaveStateAsync`)
- ✅ RuntimeSaveStateController.quickLoad() 也使用 async 版本 (line 58: `loadStateAsync`)

**代码证据**:
```cpp
// engine_state_napi.cpp:136
bool ok = GetEngine()->LoadState(stateData);  // 同步调用，阻塞 NAPI 线程
```

```typescript
// SaveStatePage.ets:250 (quickSave 已修复)
const stateData = await nativeApi.refactoredSaveStateAsync()  // ✅ async

// SaveStatePage.ets:282 (loadSave 未修复)
const loaded = nativeApi.refactoredLoadState(stateData)  // ❌ sync
```

**严重性判定 — P2 (降级自 P1)**:
- 原 claim 误判：游戏未运行时 `IsGameLoadedState()` 立即返回 false (line 2666)，**不会等待 5s**
- 实际问题：游戏运行时同步调用可能阻塞 UI 线程最长 5s
  - 但正常情况下 `retro_unserialize` 毫秒级完成
  - 只有极端情况（core 卡死）才会真的等 5s
- 主要是代码一致性问题：
  - quickSave() 已改用 async (line 250)
  - loadSave() 应保持一致
  - 不是严重的用户体验问题，降级为 P2

**Web verify**: 不适用 (非 rule-based finding，是代码实现不一致问题)

## Final Tally

- **Total REAL**: 0
- **Total REAL_LOWER**: 1 (P1 → P2)
- **Total MITIGATED**: 0
- **Total DESIGN**: 0
- **Total FALSE_POSITIVE**: 0

## Cross-agent Calibration Notes

T8 审计质量高：
- 8 个 hazards 全部系统性验证
- Finding 有明确的 evidence_excerpt 和 suggested_fix
- 使用了 MCP 工具 (find_references) 验证影响面
- 没有过度标记 P0 (正确判断为 P1)

建议修复 F1 以保持代码一致性和用户体验。
