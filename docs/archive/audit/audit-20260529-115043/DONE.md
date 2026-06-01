# Done criteria — audit-20260529-115043 (topic: T8)

## 边界(必明确,防 scope drift)

**Scope in**:
- SaveState / SRAM / Disk Control 全链路 I/O
- 文件范围:
  - `entry/src/main/cpp/core/engine/core_state_manager.*`
  - `entry/src/main/cpp/core/engine/libretro_engine.cpp` (SaveState/SRAM/Disk 路径)
  - `entry/src/main/cpp/core/libretro/disk_controller.*`
  - `entry/src/main/cpp/app/napi/engine_state_napi.cpp`
  - `entry/src/main/cpp/app/napi/engine_disk_napi.cpp`
  - `entry/src/main/ets/common/SaveStateRepository.ets`
  - `entry/src/main/ets/common/LibrarySaveFilePurger.ets`
  - `entry/src/main/ets/common/RuntimeSaveStateController.ets`
  - `entry/src/main/ets/pages/SaveStatePage.ets`
  - `entry/src/main/ets/pages/LibretroGamePage.ets` (quick save/load 路径)

**Scope out**:
- 其他 topic 的跨层交互（T1 NAPI 通用边界、T2 Engine 状态机通用逻辑、T7 Input 层）
- UI 层纯展示逻辑（SaveStatePage 的列表渲染、样式）
- 非 SaveState/SRAM/Disk 的其他持久化（配置文件、ROM 库）

## 完成条件(场景驱动,逐条 checkbox,fix 完逐条勾选)

- [ ] 所有 P0 finding 已 fix 或显式标记 WONT_FIX(理由必填)
- [ ] 所有 fix 通过 Step 5/6 verify(verify agent 报 FIXED + 主 Claude citation 确认)
- [ ] Step 7 quick_signals 全 PASS
- [ ] 业务侧"会踩坑的真实场景"逐条验证:
  - [ ] **场景 1**: Quick save/load 在 not-GAME_LOADED 状态下提示 + 拒绝,不走 retro_serialize
  - [ ] **场景 2**: retro_serialize / retro_get_memory_data 全部 ExecuteSyncTask 包装,不在 NAPI thread 直跑
  - [ ] **场景 3**: DiskController 在 core unload 路径下显式清理 callbacks_
  - [ ] **场景 4**: EngineSyncTask 超时路径下不留半完成状态(promise / mutex / cv 一致清理)
  - [ ] **场景 5**: SaveState file 写入全部 tmp + rename;manifest 与 file 一致(crash 后启动能恢复)
  - [ ] **场景 6**: purge 时按 manifest.romFile 精确匹配,不按文件名前缀(防误删)
  - [ ] **场景 7**: unlink ENOENT 不报错(已删 → 幂等)
- [ ] napi-boundary-reviewer(若 fix 涉及 NAPI)verdict ≠ block
- [ ] audit-evaluator(若有)drift ≤ 20%

## 不在本次范围(显式 defer)

- ROM 库元数据持久化 — 属于 Library 层,不属于 SaveState/SRAM I/O
- 配置文件读写 — 属于 Settings 层
- 网络同步 SaveState — 当前版本无此功能
