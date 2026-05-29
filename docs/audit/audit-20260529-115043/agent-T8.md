# T8 Audit — SaveState / SRAM / Disk I/O 持久化

Audit started: 2026-05-29 11:50:43
Audit completed: 2026-05-29 11:52:00

## Scope
- SaveState + SRAM + Disk Control 全链路 I/O
- 8 hazards: state-machine guard, threading model, callback lifecycle, sync task timeout, NAPI cancellation, atomic file I/O, async non-blocking, unlink ENOENT tolerance, purge filtering

## Files Audited
- `entry/src/main/cpp/core/engine/core_state_manager.cpp`
- `entry/src/main/cpp/core/engine/libretro_engine.cpp` (SaveState/SRAM/Disk paths)
- `entry/src/main/cpp/core/libretro/disk_controller.cpp`
- `entry/src/main/cpp/app/napi/engine_state_napi.cpp`
- `entry/src/main/cpp/app/napi/engine_disk_napi.cpp`
- `entry/src/main/ets/common/SaveStateRepository.ets`
- `entry/src/main/ets/common/LibrarySaveFilePurger.ets`
- `entry/src/main/ets/common/RuntimeSaveStateController.ets`
- `entry/src/main/ets/pages/SaveStatePage.ets`

## Summary

**Total findings: 1**

All 8 hazards have been systematically checked:

1. ✅ **State-machine guard** — `IsGameLoadedState()` guard present in all SaveState/LoadState/GetSRAM/SetSRAM entry points
2. ✅ **Threading model** — All `retro_serialize` / `retro_get_memory_data` calls wrapped in `ExecuteSyncTask`
3. ✅ **DiskController callbacks lifecycle** — `ClearCallbacks()` called before core unload
4. ✅ **EngineSyncTask timeout TOCTOU** — `abandoned_` flag + mutex protection prevents stack dangling
5. ✅ **NAPI async_work cancellation** — `napi_cancelled` guard present in all async completion callbacks
6. ✅ **Atomic file I/O** — tmp + rename pattern used for both manifest and .state files
7. ✅ **Async non-blocking I/O** — All file I/O uses async `fs.*` APIs
8. ⚠️ **Purge filtering** — Uses manifest.romFile matching, but has one edge case issue (see F1)

## Findings

## F1: SaveStatePage.loadSave uses sync NAPI call without state guard

- severity: P1
- file: entry/src/main/ets/pages/SaveStatePage.ets
- line: 282
- evidence_excerpt: |
    try {
      const stateData = readSaveStateData(context, fileName)
      const loaded = nativeApi.refactoredLoadState(stateData)
      this.showToastMessage(loaded ? 'SAVE_STATE_LOADED' : 'LOAD_STATE_REJECTED')
    } catch (err) {
- claim: SaveStatePage.loadSave() 调用同步版本 `refactoredLoadState` 而非 async 版本。虽然 C++ 层有 `IsGameLoadedState()` guard 会拒绝非法调用,但同步调用会阻塞 UI 主线程最长 5s (kSyncTaskTimeoutMs)。对比 quickSave() 已改用 `refactoredSaveStateAsync()` (line 250),loadSave() 应保持一致使用 async 版本避免 UI 冻结。此外,SaveStatePage 没有 `gameRunning` 状态检查,完全依赖 C++ 层 guard,用户在游戏未运行时点击"读档"会触发 5s 同步等待后才返回 rejected。
- suggested_fix: 将 line 282 改为 `const loaded = await nativeApi.refactoredLoadStateAsync(stateData)`,并在函数签名加 async。参考 RuntimeSaveStateController.quickLoad() 的实现模式 (entry/src/main/ets/common/RuntimeSaveStateController.ets:58)。

---

## Verification Notes

### Hazard 1: State-machine guard
- ✅ `LibretroEngine::GetSaveStateSize()` — line 2624 checks `IsGameLoadedState()`
- ✅ `LibretroEngine::SaveState()` — line 2641 checks `IsGameLoadedState()`
- ✅ `LibretroEngine::LoadState()` — line 2666 checks `IsGameLoadedState()`
- ✅ `LibretroEngine::GetSRAM()` — line 2688 checks `IsGameLoadedState()`
- ✅ `LibretroEngine::SetSRAM()` — line 2713 checks `IsGameLoadedState()`

### Hazard 2: Threading model
- ✅ All `CoreStateManager` methods called only via `LibretroEngine::ExecuteSyncTask()`
- ✅ `retro_serialize` / `retro_unserialize` / `retro_get_memory_data` never called directly on NAPI thread

### Hazard 3: DiskController callbacks lifecycle
- ✅ `DiskController::ClearCallbacks()` exists (disk_controller.cpp:36)
- ✅ Called in `LibretroEngine::LoadCore()` before `coreLoader_.UnloadCore()` (libretro_engine.cpp:1335)

### Hazard 4: EngineSyncTask timeout TOCTOU
- ✅ `EngineSyncTask::Run()` checks `abandoned_` under mutex before executing `task_()` (libretro_engine.cpp:56)
- ✅ `EngineSyncTask::Wait()` sets `abandoned_` under mutex on timeout (libretro_engine.cpp:71)
- ✅ Follows `feedback_condition_variable_lock_invariant` pattern

### Hazard 5: NAPI async_work cancellation
- ✅ `CompleteSaveStateAsync()` — line 282 checks `napi_cancelled` first
- ✅ `CompleteLoadStateAsync()` — line 390 checks `napi_cancelled` first
- ✅ `CompleteGetSaveStateSizeAsync()` — line 35 checks `napi_cancelled` first

### Hazard 6: Atomic file I/O
- ✅ `saveManifest()` — tmp + rename (SaveStateRepository.ets:218-225)
- ✅ `writeArrayBufferToFile()` — tmp + rename (SaveStateRepository.ets:238-248)

### Hazard 7: Async non-blocking I/O
- ✅ All file operations use `await fs.*` async APIs
- ✅ `writeArrayBufferToFile()` is async (SaveStateRepository.ets:235)
- ✅ `saveStateData()` awaits writeArrayBufferToFile (SaveStateRepository.ets:44)

### Hazard 8: Purge filtering + ENOENT tolerance
- ✅ `purgeSaveFilesForBaseName()` filters by `manifest.romFile` via `matchesBaseName()` (LibrarySaveFilePurger.ets:34)
- ✅ `matchesBaseName()` extracts ROM stem and normalizes (LibrarySaveFilePurger.ets:71-79)
- ✅ ENOENT tolerance in `deleteSaveStateItem()` (SaveStateRepository.ets:116)
- ✅ ENOENT tolerance in `purgeSaveFilesForBaseName()` (LibrarySaveFilePurger.ets:52)
