# T8 — SaveState / SRAM / Disk I/O 持久化

## Scope
SaveState + SRAM + Disk Control 全链路 I/O。

**Files**:
- `cpp/core/engine/core_state_manager.*`
- `cpp/core/engine/libretro_engine.cpp` (SaveState/SRAM/Disk 路径)
- `cpp/core/libretro/disk_controller.*`
- `cpp/app/napi/engine_state_napi.cpp`
- `cpp/app/napi/engine_disk_napi.cpp`
- `ets/common/SaveStateRepository.ets`
- `ets/common/LibrarySaveFilePurger.ets`
- `ets/common/RuntimeSaveStateController.ets`
- `ets/pages/SaveStatePage.ets`
- `ets/pages/LibretroGamePage.ets` (quick save/load 路径)

## Hazards
- state-machine guard — SaveState 必须 GAME_LOADED 才能调
- retro_serialize + retro_get_memory_data 线程模型 — 只在 Engine thread + ExecuteSyncTask
- DiskController callbacks_ 在 core unload 时悬空
- EngineSyncTask 超时栈悬挂 TOCTOU
- NAPI async_work + napi_cancelled guard — async work 在 callback 跑前被 cancel 的处理
- ArkTS 文件 I/O 原子写 — tmp + rename + manifest 一致性
- async file I/O 不阻塞主线程
- unlink ENOENT 容忍语义 — 删一个不存在的 SaveState 不是错
- purge 按 manifest.romFile 过滤 vs 文件名前缀 — 不能用前缀匹配误删别 ROM 的 save

## Done criteria 模板(场景驱动)
- [ ] Quick save / load 在 not-GAME_LOADED 状态下提示 + 拒绝,不走 retro_serialize
- [ ] retro_serialize / get_memory_data 全部 ExecuteSyncTask 包装,不在 NAPI thread 直跑
- [ ] DiskController 在 core unload 路径下显式清理 callbacks_
- [ ] EngineSyncTask 超时路径下不留半完成状态(promise / mutex / cv 一致清理,见 `feedback_condition_variable_lock_invariant`)
- [ ] SaveState file 写入全部 tmp + rename;manifest 与 file 一致(crash 后启动能恢复)
- [ ] purge 时按 manifest.romFile 精确匹配,不按文件名前缀(防误删)
- [ ] unlink ENOENT 不报错(已删 → 幂等)

## 必用 MCP
- `mcp__cclsp__find_references` — retro_serialize / retro_get_memory_data caller
- `mcp__serena__find_referencing_symbols` — SaveStateRepository / SaveStatePage 引用
