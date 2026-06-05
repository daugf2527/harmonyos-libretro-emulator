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
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/fix-verify-T8C.md` T8C-F3+F7 |
| 位置 | `entry/src/main/ets/common/LibrarySaveFilePurger.ets:71-93`（matchesBaseName / extractRomStem / normalizeContentKey） |
| 影响 | P1 — 用户在游戏库页面点"清除存档"，`purgeSaveFilesForBaseName` 始终返回 `deletedCount: 0`，存档文件不被删除 |
| 拟修 | 将 `matchesBaseName` 内的 `indexOf(normalizedBaseName) === 0` 改为精确比较——先 `extractRomStem`(取 basename+去扩展名)→`normalizeContentKey`(小写+去特殊字符)→`===` 比较。同时处理路径前缀("roms/")、扩展名差异(".nes" vs 无扩展名)、宽松匹配误删边界 |
| 状态 | fixed |
| 备注 | **2026-06-05 实物核查发现早已修复**（tracker drift）：`588a824`(05-27 T8-C-F7) 已将 `matchesBaseName` 全重写为现在三函数结构——`extractRomStem` 取 basename+去扩展名 → `normalizeContentKey` 小写去特殊字符 → `===` 精确比较。旧 `indexOf === 0` 逻辑完全不在了。同 commit 还加了 purge 后 `pruneManifestForFileNames` 同步 manifest（T8-C-F3），解决"已删存档 SaveStatePage 仍显示"的第二个问题。`normalizeContentKey` 内部先调 `extractRomStem` 再去扩展名 → normalize，`matchesBaseName` 再调一次 `extractRomStem` 是冗余但**无害**（二次调在已剥过的 stem 上 no-op），改掉可视为微优化但非 bug。 |

### D002 — SaveStateRepository 写 .state 文件与更新 manifest 之间存在 orphan 窗口

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/agent-T8C-arkts.md` T8C-F6 |
| 位置 | `entry/src/main/ets/common/SaveStateRepository.ets:189-227`（reconcileManifestItems） |
| 影响 | P2 — 进程在写完 `.state` 文件但 manifest 尚未更新时崩溃，留下孤立存档文件；代码注释 L41-42 已记录此风险 |
| 拟修 | 在 `loadManifest` 成功路径加 `reconcileManifestItems` 对账：(a) manifest 有条目但文件不存在→裁剪；(b) 磁盘有 .state 但 manifest 无→补充（romFile=''）。**刻意不改写入顺序**——当前 .state 先写保证崩溃时数据在磁盘可恢复，反转则 save 可能丢失。 |
| 状态 | fixed |
| 备注 | **2026-06-05 修复**（commit b719eb5）：复用 `buildManifestFromDirectory` 既有扫描模式；`.tmp` 半写文件后缀不匹配不被拾取；三处调用方（list/save/delete）经 loadManifest 统一覆盖。未编译/未真机（ArkTS quick_signals 不覆盖，需 DevEco 复编）。原 fix-verify 标 SKIP (DESIGN)，本次实做。 |

### D003 — engine_lifecycle_napi / core_loader_napi 三处 Complete 函数未处理 napi_cancelled，env teardown 时 UB

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/napi-review-batch2.md` Concern-6 |
| 位置 | `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp:206`（CompleteGetRawFileListAsync）、`engine_lifecycle_napi.cpp:1173`（CompleteStopEngineAsync）、`entry/src/main/cpp/app/napi/core_loader_napi.cpp:587`（CompleteTestCoreLoader） |
| 影响 | P1 — 引擎关闭 / JS 环境退出时 napi_cancelled 触发，函数仍调用 `MakeString` + `napi_reject_deferred`，对已销毁 env 操作属于 UB |
| 拟修 | 在三处 Complete 函数顶部加 `if (status == napi_cancelled) { 释放 work + 原生资源; delete ctx; return; }` 守卫，与 T8B-F4 已修的三处对齐 |
| 状态 | fixed |
| 备注 | **2026-06-05 收口**（实物核查发现 tracker drift）：三处中 `CompleteTestCoreLoader` 早在 `0bb99ce`(05-25 T1-F6) 已有 guard；本次修 lifecycle 两处（`CompleteGetRawFileListAsync`+`CompleteStopEngineAsync`），cancelled 分支只释放 work/mgr + delete ctx，不碰任何 napi_*，对齐 `engine_state_napi.cpp:33/286/403` 正范式。napi-boundary-reviewer 复核 PASS（资源释放完整 / `napi_delete_async_work` 在 teardown 安全 / `stop_in_progress` 卡锁仅 env teardown 无实害 / 范式一致）。当前 HEAD 1e55809 之后的 working tree 改动；未编译/未真机。 |

### D004 — engine_state_napi create_promise 失败路径不一致：GetSaveStateSizeAsync / SaveStateAsync 返回 nullptr 而非可 await 的 Promise

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/napi-review-batch2.md` Concern-2 |
| 位置 | `entry/src/main/cpp/app/napi/engine_state_napi.cpp:64-67`（GetSaveStateSizeAsync）、`engine_state_napi.cpp:330-333`（SaveStateAsync） |
| 影响 | P1 — `napi_create_promise` 失败时返回 `nullptr` 给 ArkTS，调用方 `await` 一个非 Promise 值会抛 TypeError |
| 拟修 | ~~将 GetSaveStateSizeAsync 和 SaveStateAsync 的 create_promise 失败路径改为返回 MakeResolvedPromise，与 LoadStateAsync 对齐~~（依据已证伪，见备注） |
| 状态 | wontfix |
| 备注 | **2026-06-05 实物核查证伪**：tracker 原描述称 LoadStateAsync「已正确返回 MakeResolvedPromise」是错的——实物三处（`GetSaveStateSizeAsync:64-67`、`SaveStateAsync:334-337`、`LoadStateAsync:456-459`）的 `napi_create_promise` 失败路径**全部是 `return nullptr`，本就一致**，不存在「两处错一处对」。且 `napi_create_promise` 失败 = JS 引擎已 OOM/销毁的极端态，此时无有效 deferred 可 resolve，`MakeResolvedPromise` 内部同样会 `napi_create_promise` 再失败一次。三处 callsite 均在 env teardown 路径，返回 nullptr 可接受。判定非真 bug，不修。 |

### D005 — SaveStateRepository.writeArrayBufferToFile 同步阻塞主线程（T8C-F1 SKIP）

| Key | 值 |
|---|---|
| 引入 | 2026-05-27 / `docs/audit/audit-20260527-124137/agent-T8C-arkts.md` T8C-F1 |
| 位置 | `entry/src/main/ets/common/SaveStateRepository.ets:44`（`writeArrayBufferToFile` 调用点）、`SaveStateRepository.ets:235-256`（函数实现） |
| 影响 | P1 — GBA/GBC 存档数据 128 KB～512 KB，主线程同步写入阻塞帧渲染，可触发 ArkUI 主线程超时警告 |
| 拟修 | 将 `writeArrayBufferToFile` 改为 `async` 函数，内部使用 `fs.write`（Promise 版）替换 `fs.writeSync`；`saveStateData()` 已是 async，直接 `await` 即可 |
| 状态 | fixed |
| 备注 | **2026-06-05 实物核查发现早已修复**（tracker drift）：`writeArrayBufferToFile`（`SaveStateRepository.ets:235`）已是 `async function ... Promise<void>`，内部全 `await fs.open/write/close/rename`，并实现 tmp+rename 原子写（T6-F3）。修复在 `588a824`(05-27 17:28) — 与 debt 录入同一 commit，即录入时其实已修，状态误标 open。`saveStateData` L44 正确 `await`。未编译/未真机。 |

### D006 — 63 个 refactored* NAPI export 未在 CLAUDE.md / AGENTS.md 任何位置提及（文档化缺口）

| Key | 值 |
|---|---|
| 引入 | 2026-05-28 / `docs/gc-code-drift-20260528-155349.md` Pattern 5 |
| 位置 | `entry/src/main/cpp/app/napi/**`（`engine_lifecycle_napi.cpp` / `engine_state_napi.cpp` / `engine_input_napi.cpp` / `engine_audio_napi.cpp` / `core_loader_napi.cpp` 等;55 个 export 完整清单见 `docs/gc-code-drift-20260528-155349.md` "Pattern 5" 节) |
| 影响 | P1 — ArkTS 端调用 `globalThis.refactoredXxx` 时 agent 找不到该 API 在哪个 .cpp 文件实现 / 参数契约怎么定;ArkTS 侧改动易踩 NAPI 边界坑(memory `feedback_napi_reviewer_no_skip`) |
| 拟修 | 在 `AGENTS.md` 加一节 "NAPI Export Inventory",分组列出(生命周期/状态/输入/视频音频/磁盘/查询/其他)63 个 export 名 + 实现文件路径 + 签名一句话;每加新 export 必须同时更新此节(用 `scan_code_drift.sh` Pattern 5 守) |
| 状态 | fixed |
| 备注 | **2026-06-05 修复**（commit 0bb1aee）：实物 grep 实证为 **63 个**（非标题的 55；旧 gc 计数漏 input_mapping/core_loader 两独立模块 + 后续新增）。AGENTS.md 运行链路图节后加 NAPI Export Inventory，7 域表格，签名全部取自真值源 `index.d.ts`，修正 5 处此前二手描述偏差（testCoreLoader 同步 string / sendSensor 3 参 / getRegion·getStats·getAVInfo 返回 number·结构化对象）。`/gc` 2026-05-28 首次发现；后续靠 Pattern 5 增量守。 |

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
| 位置 | `entry/src/main/cpp/app/napi/*.cpp`（原 `3001/3010/3020/3022/3031`/`8001/8002` 字面量散布）；`entry/src/main/cpp/app/napi/engine_napi_common.h` |
| 影响 | P2 — 错误码以裸字面量散落各 .cpp，改一个码需全仓 grep；`docs/napi-error-code-mapping.md`（145 行）定义了码段但 C++ 侧无对应 enum，文档与代码靠人肉同步易 drift；若与 ArkTS `ErrorCodes.ets` 的 numericCode 不一致，用户会看到错误码错乱 |
| 拟修 | 已在 `engine_napi_common.h` 加 `namespace EngineErrorCodes`/`NapiErrorCodes` 的 `constexpr int` 定义，替换 `engine_lifecycle_napi.cpp` / `engine_state_napi.cpp` 调用点裸数字；ArkTS `ErrorCodes.ets` 仍是用户可见错误定义 SOT，C++ 常量作为 native 侧映射锚点。 |
| 状态 | closed |
| 备注 | 2026-06-02 收口：静态 grep 确认相关 `.cpp` 调用点不再直接传递 `3001/3010/3020/3022/3031/8001/8002` 给 `MakeErrorResult` 或 `ctx->errorCode`；未编译/未真机。 |

### D009 — M3「质量门禁」里程碑标 ✅ 但门禁脚本未落地

| Key | 值 |
|---|---|
| 引入 | 2026-06-01 / 本会话质检 |
| 位置 | `scripts/test/`（缺 matrix/compat 脚本）；设计文档 `docs/design/m3-automated-test-design.md` + `m3-core-compatibility-matrix.md` 已完整 |
| 影响 | P1 — Roadmap 标 M3「✅ 已完成」，但 `scripts/test/` 无任何兼容矩阵/自动化测试脚本，发版前「必跑清单」无可执行产物，门禁名存实亡（"完成"的只有设计图纸） |
| 拟修 | 按 `m3-automated-test-design.md` Layer 1（Bash 脚本扫描 .so+ROM→test-manifest.json）+ quick_signals 集成 + CI artifact 上传。Layer 2 (ArkTS 真机测试) 和 Layer 3 (手工验证矩阵) 后续单独排期（需真机）。 |
| 状态 | fixed |
| 备注 | **2026-06-05 Layer1 落地**（commit b1c0838）：新建 `scripts/test/check_core_compatibility.sh`（30 cores + 35 roms = 65 entries；逐行 printf 构 JSON 无 jq 依赖；目录缺失不 FAIL）；`quick_signals.sh` 加 core-compat check(skip_check 模式仿 cxx-build)；`harmonyos-pr-ci.yml` Build HAP 后加 M3 manifest + artifact 上传；`.gitignore` 补根级 `build/`。**未做**：Layer 2 ArkTS (CoreCompatibilityTest.ets/TestPage.ets)、Layer 3 手工模板、Roadmap 状态改标。D009 按 Layer1 范围 fixed，Layer 2/3 记录为 follow-up。 |

### D010 — refactoredSwitchGameAsync 类型谎言掩盖 switch 失败误判 bug（已修）

| Key | 值 |
|---|---|
| 引入 | 2026-06-04 / 本会话质检 ARCH-1 测绘发现 |
| 位置 | `entry/src/main/ets/pages/LibretroGamePage.ets:1013`（修前）；C++ 真值 `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp:864` |
| 影响 | P0 — C++ `CompleteSwitchGame` resolve 结构对象 `{success,errorCode,message}`，但 TS 声明谎报 `Promise<boolean>`，ArkTS `if(!ok)` 对 `{success:false}` 恒 false → 切换游戏**失败时 UI 假报成功（黑屏，引擎未启动）**；仅失败路径显现，故长期未被发现 |
| 拟修 | 已修：接通 errorCode 跨层通道——新增 `NapiErrorResult` interface（ErrorCodes.ets + index.d.ts），`refactoredSwitchGameAsync`/`switchGame()` 返回类型改 `Promise<NapiErrorResult>`，`if(!ok)`→`if(!result.success)`，catch 改读 `result.errorCode`→`findByNumericCode`（字符串嗅探降级兜底） |
| 状态 | fixed |
| 备注 | 用户决策 ARCH-1 (a) 接通方案；详见 `docs/audit-report-2026-06-04.md` ARCH-1 接通实施段；**需 DevEco 真机验证**（坏 core/ROM 应正确报错而非黑屏）；ArkTS 自定义 Error 范式参照 `RomImportService.ets` 的 `ImportCanceledError` |

### D011 — 同步 StartEngine/LoadCore/LoadRom 同类类型谎言致测试页假通过（已修）

| Key | 值 |
|---|---|
| 引入 | 2026-06-04 / D010 延伸排查发现 |
| 位置 | `entry/src/main/ets/pages/TestGambatte.ets`（6 消费点）+ `LibretroNewArchTestPage.ets`（3 消费点）；C++ 真值 engine_lifecycle_napi.cpp:349-441 |
| 影响 | P1 — 同步 `refactoredStartEngine/LoadCore/LoadRom` C++ 全 return `MakeErrorResult` 结构对象，但测试页局部 interface 声明 `boolean`，`if(!startOk)` 对 `{success:false}` 恒 false → **核心兼容性测试页无法检测引擎/core/rom 加载失败，测试假通过**（误导兼容性判断）。危害面限测试/诊断页，无生产用户路径（生产走已修的 switchGame） |
| 拟修 | 已修：两测试页 interface 3 接口返回类型 `boolean`→`NapiErrorResult` + import；9 个消费点 `if(!xxOk)`→`if(!xxResult.success)`，log 打印同步改 `.success`。**未碰** dead code `LibretroSwitchCoordinator.ets`（无调用者）。**未碰** PauseEngine/ResumeEngine/SetFilesDir/SetScalingMode 等（C++ 侧实测为 `MakeBool` 真 boolean，`: boolean` 标注正确） |
| 状态 | fixed |
| 备注 | D010 同根（类型谎言）；边界经实物核对 `MakeErrorResult`(结构对象,3个) vs `MakeBool`(真boolean,其余)；同需 DevEco 真机验证；memory `feedback_napi_return_type_lie_hides_bug` |

---

## 引用此文件的地方

- `.claude/skills/closed-loop/SKILL.md` Step 8 done-criteria gate（WONT_FIX 标记后追加到这里）
- `.claude/skills/gc/SKILL.md`（待建）— `/gc` 扫到的坏模式人确认后追加到这里
- `docs/audit/audit-*/CORE-REVIEW.md` 里被标 WONT_FIX 的 finding 应同步过来
