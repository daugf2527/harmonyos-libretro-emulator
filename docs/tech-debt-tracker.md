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
| 备注 | 2026-06-02 收口：静态 grep 确认相关 `.cpp` 调用点不再直接传递 `3001/3010/3020/3022/3031/8001/8002` 给 `MakeErrorResult` 或 `ctx->errorCode`；未编译/未真机。**2026-06-06 三处一致性核对通过**（followup loop）：C++ `EngineErrorCodes`/`NapiErrorCodes` 8 码（3001/3010/3020/3022/3031/3032/8001/8002）↔ ArkTS `ErrorCodes.ets` numericCode ↔ `docs/napi-error-code-mapping.md` 三处**数值+code 字符串名全部语义一致**（如两侧 `CORE_LOAD_FAILED`=3001、`INVALID_ARGUMENT_COUNT`=8001），每码 ArkTS 唯一命中、文档全覆盖。D008 影响项担忧的"errorCode 错乱"风险确认不存在，D010 接通的 errorCode 跨层通道健康。 |

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

### D012 — refactoredSwitchGameAsync 同步早期失败/dedup 路径 resolve boolean 而非 NapiErrorResult（D010 残留）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 api22-diff followup loop · NAPI async 契约一致性核对 |
| 位置 | `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp` SwitchGameAsync 同步早期失败路径（L901/907/913/919/934/952/963/974/986 `MakeResolvedPromise(env,false)`）+ dedup 成功路径（L993 `MakeResolvedPromise(env,true)`）；helper `engine_napi_common.h:199 MakeResolvedPromise(env,bool)` resolve 纯 boolean |
| 影响 | P2 — 声明 `Promise<NapiErrorResult>`，但 dedup 路径 resolve boolean `true` → ArkTS `LibretroGamePage:1048 if(!result.success)` 读 `true.success===undefined` → `!undefined===true` → 误 throw `SwitchGameError`：用户短时间重复切换游戏，第二次请求被去重却报错（首次仍正常切换）。早期失败路径 resolve `false`：throw 结果正确但 `errorCode` 丢失，降级 `formatLastError` 字符串。边缘场景，危害有限但属类型谎言残留 |
| 拟修 | SwitchGameAsync 同步早期失败/dedup 路径 `MakeResolvedPromise(env,bool)` → resolve NapiErrorResult 结构对象（dedup→`{success:true}`；失败→`{success:false,errorCode,message}`）。可加 helper `MakeResolvedErrorPromise(env,success,errorCode,msg)` 或复用 `MakeErrorResult`+`ResolveDeferredChecked` 即时 resolve。**改 app/napi 须 dispatch napi-boundary-reviewer**。未真机 |
| 状态 | fixed |
| 备注 | **2026-06-06 修复**（本会话 loop，分支 fix/api22-audit-followup）：dedup 路径 `MakeResolvedPromise(env,true)` → `MakeResolvedErrorPromise(env,true)`（resolve `{success:true}`）；ROM 加载失败路径 → `MakeResolvedErrorPromise(env,false,ROM_LOAD_FAILED,...)`；新增 helper `engine_napi_common.h MakeResolvedErrorPromise`。8 参数校验路径保持 `MakeResolvedPromise(env,false)`（上游 GetArgs/GetStringArg 等已 napi_throw → pending 守卫使其走 reject，契约违规即抛行为正确）。cxx-build PASS；napi-boundary-reviewer 复核**核心 PASS**（类型映射 `LibretroGamePage:1051 if(!result.success)` 对 `{success:true}` 正确）。未真机。3 个衍生 follow-up 见 D013。memory `feedback_napi_return_type_lie_hides_bug` |

### D013 — D012 review 衍生：NAPI helper deferred-leak + SwitchGameAsync 参数路径混用 + index.d.ts progressCallback drift

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / D012 修复 napi-boundary-reviewer 复核（3 findings，均非 block） |
| 位置 | (a) `engine_napi_common.h` `MakeResolvedPromise`(~L211)+`MakeResolvedErrorPromise`(~L494)：`MakeBool`/`MakeErrorResult` 返回 nullptr 时 deferred 未 settle；(b) `engine_lifecycle_napi.cpp` SwitchGameAsync 8 参数校验路径仍 `MakeResolvedPromise(env,false)`；(c) `entry/src/main/cpp/types/libentry/index.d.ts:47-61` 两 overload 漏第7参 progressCallback |
| 影响 | P3 — (a) deferred leak 仅 JS 引擎 OOM/销毁极端态触发（`MakeErrorResult` 入口已查 pending exception，现实只剩 `napi_create_object` 失败=OOM），实害≈0；(b) 混用为维护陷阱（未来移除某 helper 的 throw / 复制旧 boolean 模式会重新引入 type-lie），今日 behavior-neutral；(c) progressCallback：caller（`RuntimeSessionController:94/103`）传第7参但声明缺，strict mode 不报错但失类型校验 |
| 拟修 | (a) helper 在 `MakeBool`/`MakeErrorResult` 失败时 clear pending + `napi_reject_deferred` + return promise（非 nullptr），模板 `MakeResolvedPromise` 同步；(b) 8 路径统一 `MakeResolvedErrorPromise(env,false,STATE_TRANSITION_FAILED)`（behavior-neutral，闭维护缺口）；(c) `index.d.ts` 两 overload + `AGENTS.md` NAPI Inventory 补 `progressCallback?: (progress:number,message:string)=>void`。改 app/napi 须 dispatch napi-boundary-reviewer |
| 状态 | fixed |
| 备注 | D012 修复 review 衍生；reviewer 判 D012 核心 PASS，3 concerns 均 follow-up 不 block。(a) 为模板 `MakeResolvedPromise` pre-existing 缺陷，新 helper 沿用同模式（一致但同缺陷）；(c) pre-existing drift，与 D006 NAPI Inventory 同步纪律相关。**进展 2026-06-06**：(c) ✅ 已修（index.d.ts 两 overload + AGENTS.md 补 `progressCallback?:(progress,message)=>void`）；(a) → **wontfix**（仅 JS 引擎 OOM 极端态触发，`MakeErrorResult` 入口已查 pending，现实只剩 `napi_create_object` 失败=OOM，实害≈0；且改它需变更 helper 失败语义、与模板不一致，收益不抵风险）；(b) ✅ 已修（SwitchGameAsync 8 参数路径 `MakeResolvedPromise(env,false)` → `MakeResolvedErrorPromise(env,false,INVALID_ARGUMENT_TYPE)`；L901 GetArgs 用 `INVALID_ARGUMENT_COUNT`）。**reviewer 第二轮发现并修正**：L934/L974 两 `napi_typeof` 原生路径**非 behavior-neutral**——原 resolve boolean false 是隐藏 type-lie（声明 NapiErrorResult 却 resolve boolean），改 `MakeResolvedErrorPromise` 反而修正并接通 errorCode（非回归，是改进）；其余 6 helper 路径已 throw→reject，确为 neutral。cxx-build PASS。 |

### D014 — refactoredSaveState(sync) 失败路径 return 结构对象而非声明的 ArrayBuffer|null（类型谎言）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 loop · NAPI 全 export 返回类型三处一致性核对 |
| 位置 | `entry/src/main/cpp/app/napi/engine_state_napi.cpp` SaveState（修前 L116/125 两失败路径 `return MakeErrorResult(env,false,SAVE_STATE_SAVE_FAILED,...)`）；声明 `index.d.ts:114 refactoredSaveState: () => ArrayBuffer \| null` |
| 影响 | P3 — 声明 `ArrayBuffer\|null`，失败却返回 `{success:false,errorCode,message}` 结构对象（truthy）→ ArkTS `if(!buf)`/`buf===null` 漏判失败（D010/D011/D012 同根类型谎言）。**当前无活跃 caller**：`RuntimeSessionController.saveState():56` 透传但全仓 0 上游调用，生产实走 `refactoredSaveStateAsync`（reject 失败，正确）。休眠路径，爆炸半径≈0，但属潜在地雷 |
| 拟修 | 已修：两失败路径 `MakeErrorResult` → `MakeNull(env)`，对齐同文件 GetSRAM L161/166（同为 `ArrayBuffer\|null` sync，失败返回 MakeNull）正范式。errorCode 仍可经 `refactoredGetLastErrorInfo` 查。成功路径 return arrayBuffer 不变 |
| 状态 | fixed |
| 备注 | **2026-06-06 修复**（本会话 loop）：cxx-build PASS；napi-boundary-reviewer 复核 **PASS**（5/5 OK：MakeNull 对齐 GetSRAM、ArkTS 消费 0 依赖旧 struct、RAII 安全、文件级 MakeErrorResult 仅剩注释）。**全文件闭环结论**：reviewer 交叉核对 engine_state_napi.cpp 全部 13 sync export 返回类型现 100% 对齐 index.d.ts 声明。其余 6 async（GetSaveStateSize/SaveState/LoadState/WaitForState/StopEngine/GetRawFileList）resolve 类型本轮亦逐个核实与声明一致，失败均走 reject。memory `feedback_napi_return_type_lie_hides_bug` |

### D015 — EventBridge core_error 死事件类型 + 枚举版 Emit/GetEventName 死代码（需决策）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 loop · EventBridge 事件名 C++↔ArkTS 一致性核对 |
| 位置 | (a) `core/engine/event_bridge.h:39` `CORE_ERROR` enum + `.cpp:42/60` 双向字符串映射；ArkTS `LibretroEventHub.ets` `EventName` union(L11-22)+ `normalizeEventName` switch(L411-426) **均漏 `core_error`**。(b) `event_bridge.h:48` 枚举版 `Emit(EventType,...)` + `GetEventName` 映射表 |
| 影响 | P3（非当前 bug，均"定义未接线"）— (a) **core_error 死事件**：C++ 有 EventType+双向映射但**无 emit callsite**（全仓 `Emit("core_error"` 0 命中）、ArkTS 无监听 → 当前零危害（从不发出）；潜在地雷：未来 `Emit("core_error",...)` 会被 ArkTS `normalizeEventName` 返 null **静默丢弃**（类似类型谎言静默风险）。(b) **枚举版 Emit 死代码**：21 个 emit callsite **全走 deprecated 字符串版 `Emit(string,...)`**（`.h:51`），枚举版 `Emit(EventType,...)`+`GetEventName` **0 使用** → 死代码 + 主路径反用 deprecated 接口 |
| 拟修 | **需决策（非自主）**：(a) core_error 若确定要用（核心错误细分于 core_crash/core_message）→ 两侧接线（C++ 加 `Emit("core_error",...)` callsite + ArkTS 补 union/case/subscribe + UI 行为）；若不用 → 删 C++ 死枚举+映射。(b) 枚举版 Emit 扶正（callsite 改枚举版、删 deprecated 字符串版）or 认字符串版为正、删枚举版+GetEventName。两者均涉架构/产品决策，故记录不自主改 |
| 状态 | open |
| 备注 | **EventBridge 核心功能健康**：本核对证实 12/13 事件接线完整——core_message(emit `libretro_engine:2475` ↔ ArkTS subscribe@218)、core_crash(emit 多处 ↔ ArkTS case@413)、engine_state/fps_update/audio_status/options_update/pixel_format_update/geometry_update/disk_control/rumble/sensor_state 全对齐。**仅 core_error 单事件 + 枚举版 Emit 是死代码**，事件名一致性除此之外全对齐。EventBridge 跨语言边界确认通过 |

### D016 — LibretroGamePage.loadRuntimeRenderSettings async 竞态：await 后写 @State 漏 pageActive 守卫（已修）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 loop · ArkTS 异步生命周期审计 |
| 位置 | `entry/src/main/ets/pages/LibretroGamePage.ets` `loadRuntimeRenderSettings`（L263，由 `aboutToAppear` L205 fire-and-forget 触发）；修前 await `loadRuntimeRenderSettingsProfile` 后直接写 `scalingMode`/`softwareMaxPresetIndex`/`hwRenderAllowed`（均 @State，L132-134） |
| 影响 | P3 — use-after-free 类竞态：aboutToAppear 触发 → await 读配置文件（几 ms 窗口）→ 用户快速退出游戏页（aboutToDisappear 置 `pageActive=false` 并销毁）→ await 回来向已销毁页面写 @State 触发 re-render。ArkUI setState-on-destroyed 通常 warning/静默，极端可 crash。竞态窗口小（需配置读取期间退出），但**违反项目自建范式**——quickSave/quickLoad（L307/321）有 `if(!pageActive)return` 守卫（T8-C-F5），本方法遗漏 |
| 拟修 | 已修：await 后、写 @State 前加 `if(!this.pageActive){return;}`，与 quickSave/quickLoad T8-C-F5 范式一致。**未碰** `loadRuntimeInputLayout`（写 `runtimeInputLayoutButtons` 为 private 非 @State，销毁后赋值无 re-render，无害）、`persistRuntimeRenderSettingsProfile`（写 renderSettingsProfile private，同理）、`startOrSwitchGame`（已有 isCurrentSwitchTask 6 处守卫）、`refreshRomList`（已有 romListRefreshToken 守卫） |
| 状态 | fixed |
| 备注 | **2026-06-06 修复**（本会话 loop）：ArkTS 异步审计换角度挖到（C++/NAPI 边界全健康后转 ArkTS 竞态）。regression guard PASS；**未编译/未真机**（quick_signals 不覆盖 .ets hvigor 编译，需 DevEco 复编验证守卫不破坏布局加载）。同页其余 7 个 async 守卫覆盖经核对完整（startOrSwitch/quickSave/quickLoad/refreshRom 有守卫，loadInputLayout/persist/finalize 写 private 或无 setState 无需守卫）。memory `feedback_arkts_v1v2_no_mixing`(@State 范式) |

### D017 — SettingsPage toggle 方法 await 后写 @State 漏 pageActive 守卫（D016 同类，已修）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 loop · ArkTS 异步生命周期逐方法细查（续 D016 角度） |
| 位置 | `entry/src/main/ets/pages/SettingsPage.ets` `toggleHideVirtualController`（L400，修前 L414）+ `toggleHideUndeclaredKeys`（L420，修前 L434）；二者 inline `await saveRuntimeInputPreferencesProfile` 后直接写 `this.inputPreferences`（@State L139），无守卫；由用户点击触发（L1067/L1075） |
| 影响 | P3 — D016 同类 use-after-free 竞态：用户点 toggle（虚拟手柄显示/隐藏未声明键）→ await 保存配置（IO 窗口）→ 立即退出 Settings 页（aboutToDisappear 置 pageActive=false）→ await 回来写 @State inputPreferences 触发 re-render on destroyed。竞态窗口比 D016 更窄（需用户主动点击+退出双重操作），但同属真竞态。**违反同页范式**：renderProfile 的写都走 persistRenderProfile（有 isCurrentRefresh token 守卫 L375），inputPreferences 的写在 toggle 内 inline 漏守卫 |
| 拟修 | 已修：两 toggle 的 try 内 await 后、写 inputPreferences 前加 `if(!this.pageActive){return}`，与同页 refreshPageData/persistRenderProfile token 守卫范式一致（此处用 pageActive，因 toggle 无 beginRefresh token）。顺手规整 catch 块预存格式瑕疵（`false)    }` → 换行）。**未碰** cycleRenderMode/cycleSoftwareResolutionPreset/toggleHwRenderAllowed（均经 persistRenderProfile 守卫，安全）、refreshPageData（4 处 token 守卫完整） |
| 状态 | fixed |
| 备注 | **2026-06-06 修复**（本会话 loop）：D016 逐方法细查范式扩展到 SettingsPage 挖到。SettingsPage 7 个 async 核对：refreshPageData(token守卫)/persistRenderProfile(token守卫)/cycle×2+toggleHwRender(经persist)安全，仅 2 个 inputPreferences toggle 漏守卫。regression guard PASS；**未编译/未真机**。关联 `[[D016]]`（同类竞态范式） |

### D018 — SaveStatePage.loadSave await 后写 @State 漏守卫 + ArkTS async-@State 守卫【系统性范式不完整】（loadSave 已修，系统性 open）

| Key | 值 |
|---|---|
| 引入 | 2026-06-06 / 本会话 loop · ArkTS 异步逐方法细查（D016/D017 系列第 3 例） |
| 位置 | 已修单点：`entry/src/main/ets/pages/SaveStatePage.ets` `loadSave`（L308，修前 L318 await `refactoredLoadStateAsync` 后直接 `showToastMessage` 写 @State toastMessage/showToast 无守卫）。**系统性面**：全 `entry/src/main/ets/pages/**` 的 async 方法中"await 后写 @State 漏 pageActive/token 守卫"的零散遗漏 |
| 影响 | P3（单点）/ **P2（系统性）** — 单点 loadSave 危害最轻（仅 toast，且 toast 有 setTimeout 自动隐藏+守卫）。**系统性问题**：逐方法细查 3 个页面（LibretroGamePage→D016、SettingsPage→D017、SaveStatePage→D018）**每页都有 1 处同类遗漏**——项目有 pageActive/token 守卫范式但落实不完整，是"整页有守卫、个别方法 inline await 漏守卫"的隐蔽模式。剩余未细查页面（RomManagerPage async=15、LibraryDetailPage、MetadataEditPage、CoreManagerPage 等）大概率仍有零散遗漏 |
| 拟修 | 单点已修：loadSave await 后加 `if(!this.pageActive){return}`（主路径；catch 内 showToast 双重低概率未加）。**系统性需决策**：(a) 人工统一审计剩余页面所有 async 方法补守卫（工作量中等，逐页逐方法）；(b) 建立 async helper 范式（如 `await this.guardedAwait(promise, token)` 封装"await+守卫"）从源头防遗漏；(c) gc 加启发式扫描 pattern（async 方法体内 await 后 `this.<@State字段>=` 且无 pageActive/isCurrent 守卫，human-review，类似 ForEach Pattern 3 的启发式+人工复核）。逐个手修是打地鼠，应统一处理 |
| 状态 | open（loadSave 单点 fixed；系统性范式落实待统一方案） |
| 备注 | **2026-06-06**：本会话逐方法细查挖到 D016/D017/D018 三连同根，证明是系统性而非孤立。已修 3 处代表性单点（覆盖 use-after-free 高风险的 LibretroGamePage 渲染设置 + SettingsPage 偏好 + SaveStatePage toast）。**收口此角度的逐个手修**——边际递减（打地鼠），转为记录系统性 debt 供统一方案决策。regression guard PASS；未编译/未真机。关联 `[[D016]]` `[[D017]]` |

---

## 引用此文件的地方

- `.claude/skills/closed-loop/SKILL.md` Step 8 done-criteria gate（WONT_FIX 标记后追加到这里）
- `.claude/skills/gc/SKILL.md`（待建）— `/gc` 扫到的坏模式人确认后追加到这里
- `docs/audit/audit-*/CORE-REVIEW.md` 里被标 WONT_FIX 的 finding 应同步过来
