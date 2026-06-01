# Tech Debt Tracker

记录已识别但未立刻修的技术债。每条 debt 必须**有具体位置 + 拟修动作**，
否则不进这个文件（纯感受/抱怨进 memory）。

## 怎么用

- **新 debt 怎么进**：
  - `/closed-loop` 跑出 `WONT_FIX` / `DEFER` 标记的 finding → 主 Claude 在 commit 前追加到这里
  - `/gc` skill（scan_doc_drift.sh / scan_code_drift.sh）扫到的新坏模式 → 人确认后追加
  - 用户手工补：Edit 这个文件，加新一行
- **修一条 debt**：把 status 改为 `fixed` 不要删除，保留历史可查
- **状态语义**：
  - `open` — 已识别，未排期
  - `scheduled` — 已纳入下个 closed-loop / sprint
  - `fixed` — 已修复（commit hash 在备注）
  - `wontfix` — 决定不修（理由必填）

## 字段格式

每条 debt 用 4 级标题 `### D<NNN> — <一行标题>`，然后字段表：

| Key | 必填 | 说明 |
|---|---|---|
| 引入 | 是 | commit hash 或日期 + 来源（audit dir / memory key / 手工） |
| 位置 | 是 | `<file>:<line>` 或目录 glob |
| 影响 | 是 | P0/P1/P2 + 何时会咬人（一句话） |
| 拟修 | 是 | 具体动作，不是"以后看看" |
| 状态 | 是 | open / scheduled / fixed / wontfix |
| 备注 | 否 | 关联的 audit dir / memory key / 后续 PR / 决策理由 |

---

## Debt list

### D001 — matchesBaseName 前缀匹配永远 0 命中，purge 功能对用户不可用

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/fix-verify-T8C.md` T8C-F3+F7 PARTIAL |
| 位置 | `entry/src/main/ets/common/LibrarySaveFilePurger.ets:71-74` |
| 影响 | P1 — 用户在游戏库页面点"清除存档"，`purgeSaveFilesForBaseName` 始终返回 `deletedCount: 0`，存档文件不被删除 |
| 拟修 | 将 `matchesBaseName` 内的 `indexOf(normalizedBaseName) === 0` 改为 `includes(normalizedBaseName)`；或在函数内先提取 `romFile` 的文件名部分再比较 |
| 状态 | open |
| 备注 | audit-20260527-124137 T8C-F7；fix-verify 评为 PARTIAL，F3 manifest 同步已修，F7 匹配算法未修；`feedback_string_match_trace_inputs.md` 记录了同类教训 |

### D002 — SaveStateRepository 写 .state 文件与更新 manifest 之间存在 orphan 窗口

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/agent-T8C-arkts.md` T8C-F6 |
| 位置 | `entry/src/main/ets/common/SaveStateRepository.ets:37-43` |
| 影响 | P2 — 进程在写完 `.state` 文件但 manifest 尚未更新时崩溃，留下孤立存档文件；代码注释 L41-42 已记录此风险 |
| 拟修 | 将写文件与 manifest 更新合并为原子操作：先写临时文件，manifest 更新成功后再 rename 到目标路径；或在启动时扫描孤立文件并清理 |
| 状态 | open |
| 备注 | audit-20260527-124137 T8C-F6；fix-verify 标记为 SKIP (DESIGN)，主 Claude 判定跳过；代码内已有 `// T6-F4` 注释标记 |

### D003 — engine_lifecycle_napi / core_loader_napi 三处 Complete 函数未处理 napi_cancelled，env teardown 时 UB

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/napi-review-batch2.md` Concern-6 |
| 位置 | `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp:210`（CompleteGetRawFileListAsync）、`engine_lifecycle_napi.cpp:817`（CompleteStopEngineAsync）、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:530`（CompleteTestCoreLoader） |
| 影响 | P1 — 引擎关闭 / JS 环境退出时 napi_cancelled 触发，三处函数仍调用 `napi_create_string_utf8` + `napi_reject_deferred`，对已销毁 env 操作属于 UB |
| 拟修 | 在三处 Complete 函数顶部加 `if (status == napi_cancelled) { napi_delete_async_work(env, ctx->work); delete ctx; return; }` 守卫，与 T8B-F4 已修的三处对齐 |
| 状态 | open |
| 备注 | audit-20260527-124137 napi-review-batch2 Concern-6（范围外旁观）；T8B-F4 已修的三处 Complete 函数是正确范式参考 |

### D004 — engine_state_napi create_promise 失败路径不一致：GetSaveStateSizeAsync / SaveStateAsync 返回 nullptr 而非可 await 的 Promise

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/napi-review-batch2.md` Concern-2 |
| 位置 | `entry/src/main/cpp/app/napi/engine_state_napi.cpp:64-67`（GetSaveStateSizeAsync）、`engine_state_napi.cpp:330-333`（SaveStateAsync） |
| 影响 | P1 — `napi_create_promise` 失败时返回 `nullptr` 给 ArkTS，调用方 `await` 一个非 Promise 值会抛 TypeError；LoadStateAsync（L441）已正确返回 `MakeResolvedPromise`，三处不一致 |
| 拟修 | 将 GetSaveStateSizeAsync 和 SaveStateAsync 的 create_promise 失败路径改为返回 `MakeResolvedInt64Promise(env, 0)` / `MakeResolvedPromise(env, false)`，与 LoadStateAsync 对齐 |
| 状态 | open |
| 备注 | audit-20260527-124137 napi-review-batch2 Concern-2；当前无 ArkTS 调用方，改动安全，优先级低 |

### D005 — SaveStateRepository.writeArrayBufferToFile 同步阻塞主线程（T8C-F1 SKIP）

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/agent-T8C-arkts.md` T8C-F1 |
| 位置 | `entry/src/main/ets/common/SaveStateRepository.ets:43`（`writeArrayBufferToFile` 调用点）、`SaveStateRepository.ets:199-218`（函数实现，内含 `fs.openSync` / `fs.writeSync` / `fs.renameSync`） |
| 影响 | P1 — GBA/GBC 存档数据 128 KB～512 KB，主线程同步写入阻塞帧渲染，可触发 ArkUI 主线程超时警告 |
| 拟修 | 将 `writeArrayBufferToFile` 改为 `async` 函数，内部使用 `fs.write`（Promise 版）替换 `fs.writeSync`；`saveStateData()` 已是 async，直接 `await` 即可 |
| 状态 | open |
| 备注 | audit-20260527-124137 T8C-F1；fix-verify 未列入修复批次（主 Claude 判定 SKIP），需单独排期 |

### D006 — 55 个 refactored* NAPI export 未在 CLAUDE.md / AGENTS.md 任何位置提及（文档化缺口）

| Key | 值 |
|---|---|
| 引入 | 2026-05-28 / `docs/gc-code-drift-20260528-155349.md` Pattern 5 |
| 位置 | `entry/src/main/cpp/app/napi/**`（`engine_lifecycle_napi.cpp` / `engine_state_napi.cpp` / `engine_input_napi.cpp` / `engine_audio_napi.cpp` / `core_loader_napi.cpp` 等;55 个 export 完整清单见 `docs/gc-code-drift-20260528-155349.md` "Pattern 5" 节) |
| 影响 | P1 — ArkTS 端调用 `globalThis.refactoredXxx` 时 agent 找不到该 API 在哪个 .cpp 文件实现 / 参数契约怎么定;ArkTS 侧改动易踩 NAPI 边界坑(memory `feedback_napi_reviewer_no_skip`) |
| 拟修 | 在 `AGENTS.md` 加一节 "NAPI Export Inventory",分组列出(Lifecycle / State / Input / Audio / Cheat / DiskControl / Stats)55 个 export 名 + 实现文件路径 + 参数类型一句话;每加新 export 必须同时更新此节(用 `scan_code_drift.sh` Pattern 5 守) |
| 状态 | open |
| 备注 | `/gc` 2026-05-28 首次扫描发现;`napi-boundary-reviewer` agent 已经覆盖修改路径,但缺文档化的入口让 agent 自助查找;批量补一次性投资,后续靠 Pattern 5 增量守 |

### D007 — 30 处 @State 装饰复杂类型（V1 模式整体替换，V2 迁移时需改为 @ObservedV2+@Trace）

| Key | 值 |
|---|---|
| 引入 | 2026-05-29 / `docs/gc-code-drift-20260529-113336.md` Pattern 1 |
| 位置 | `entry/src/main/ets/pages/**` 和 `entry/src/main/ets/components/**`（30 处完整清单见 `docs/gc-code-drift-20260529-113336.md` L8-37;典型：`CoreLoaderTest.ets:30` / `LibraryPage.ets:101` / `LibretroNewArchTestPage.ets:131-132` / `ImportTaskOverlayPage.ets:95+101`） |
| 影响 | P3 — 风格债;当前使用整体替换模式（`this.arr = newArr`）能正常触发 rerender,不是 bug;但不是 V2 最佳实践（`@ObservedV2`+`@Trace` 可做增量 rerender,性能更优） |
| 拟修 | V1→V2 迁移时批量处理：(1) 将涉及的 model 类改为 `@ObservedV2` 装饰 + 属性加 `@Trace`；(2) 组件内 `@State` 改为 `@Local`（或保持 `@State` 兼容模式）；(3) 实例化用 `new` 构造；参考 2026 官方文档 developer.huawei.com/consumer/en/doc/harmonyos-guides/arkts-new-observedv2-and-trace |
| 状态 | open |
| 备注 | `/gc` 2026-05-29 扫描 + web verify 核实上游规则;抽查 6 个全部用整体替换,无 mutation;项目当前仍在 V1 模式（无 `@ObservedV2`/`@ComponentV2` 关键字）;优先级 P3 = 不影响功能,V2 迁移时统一处理 |

### D008 — NAPI error code 在 C++ 侧全是硬编码 magic number，无 enum/constexpr 定义

| Key | 值 |
|---|---|
| 引入 | 2026-06-01 / 本会话质检 + working tree 未提交改动（M2 error code 落地） |
| 位置 | `entry/src/main/cpp/app/napi/*.cpp`（`3001/3010/3020/3022/3031`/`8001/8002` 字面量散布，实测 3020 出现 4 次）；`entry/src/main/cpp/app/napi/engine_napi_common.h` 零个常量定义 |
| 影响 | P2 — 错误码以裸字面量散落各 .cpp，改一个码需全仓 grep；`docs/napi-error-code-mapping.md`（145 行）定义了码段但 C++ 侧无对应 enum，文档与代码靠人肉同步易 drift；若与 ArkTS `ErrorCodes.ets` 的 numericCode 不一致，用户会看到错误码错乱 |
| 拟修 | 在 `engine_napi_common.h` 加 `namespace EngineErrorCodes`/`NapiErrorCodes` 的 `constexpr int` 定义，替换各 .cpp 字面量。**先确认 SOT 在哪侧**：映射表称对端是 ArkTS `ErrorCodes.ets` 的 numericCode，若 ArkTS 侧已有常量则 C++ 侧 link 之、避免双源 |
| 状态 | open |
| 备注 | 2026-06-01 质检实地核实（读 napi-error-code-mapping.md + grep 字面量散布 + 确认 .h 无常量）；与 working tree 未提交的 M2 改动同源，建议随 M2 收口一起处理 |

### D009 — M3「质量门禁」里程碑标 ✅ 但门禁脚本未落地

| Key | 值 |
|---|---|
| 引入 | 2026-06-01 / 本会话质检 |
| 位置 | `scripts/test/`（缺 matrix/compat 脚本）；设计文档 `docs/design/m3-automated-test-design.md` + `m3-core-compatibility-matrix.md` 已完整 |
| 影响 | P1 — Roadmap 标 M3「✅ 已完成」，但 `scripts/test/` 无任何兼容矩阵/自动化测试脚本，发版前「必跑清单」无可执行产物，门禁名存实亡（"完成"的只有设计图纸） |
| 拟修 | 二选一：(1) 按 `m3-automated-test-design.md` 3 层架构落地 Bash 层兼容矩阵跑测脚本；(2) 据实将 Roadmap M3 状态降级为「⚠️ 设计完成 / 门禁脚本落地 pending」 |
| 状态 | open |
| 备注 | 2026-06-01 质检实地核实（find scripts 无 matrix/compat）；与 Roadmap 账本对齐任务（`docs/plans/2026-06-01-verification-backlog-index.md`）联动 |

---

## 引用此文件的地方

- `.claude/skills/closed-loop/SKILL.md` Step 8 done-criteria gate（WONT_FIX 标记后追加到这里）
- `.claude/skills/gc/SKILL.md`（待建）— `/gc` 扫到的坏模式人确认后追加到这里
- `docs/audit/audit-*/CORE-REVIEW.md` 里被标 WONT_FIX 的 finding 应同步过来
