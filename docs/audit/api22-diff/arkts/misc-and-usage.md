# ArkTS 杂项小 Kit 三源差异 + 用法兼容坑专项审计 (API 22)

> 目标 SDK = 6.0.2(22) = API 22（`entry/build-profile.json5`: compatibleSdkVersion=6.0.2(22) / targetSdkVersion=6.0.2(22) / runtimeOS=HarmonyOS）
> 源 A 本地代码: `entry/src/main/ets/`（Grep/Read 精确 callsite 文件:行号）
> 源 B 本机 SDK .d.ts (apiVersion=22, version=6.0.2.130):
>   - Kit 聚合: `…/openharmony/ets/kits/@kit.{BasicServices,Localization,PerformanceAnalysis,SensorService}Kit.d.ts`
>   - 真实声明: `…/openharmony/ets/api/@ohos.{base,deviceInfo,resourceManager,hilog,vibrator}.d.ts`
>   - 基底: `D:\Program Files\DevEco Studio\sdk\default\openharmony\ets\api\`
> 源 C 官方 API22 文档: developer.huawei.com（仅 deprecated/高 since 交叉验证；本次 .d.ts 即权威，未触发 web 调用）
>
> 审计日期: 2026-06-05 · 状态: 完成

---

## 第一部分：4 个小 Kit 鸿蒙 API 三源差异

### 结论速览（第一部分）

- **本地实际用到 5 个符号**（跨 4 个 Kit）：`deviceInfo.abiList` / `BusinessError` / `resourceManager.ResourceManager`(仅作类型) / `hilog.{info,warn,error}` / `vibrator.startVibration`。
- **全部 5 个在 API22 .d.ts 中存在、签名一致、since ≤ 22 全覆盖、0 deprecated 命中**。**0 个真实 bug / 0 缺失 / 0 签名不匹配。**
- **任务下发清单勘误 2 处**（不影响代码正确性，记录如下）：
  1. 清单称 `deviceInfo` 用于「取设备型号/SDK版本/品牌（sdkApiVersion 等）」—— **事实不符**。全仓 grep `deviceInfo.` 仅命中 `abiList` 一个字段（5 文件 import，4 文件实际取值），**完全没有** `deviceModel` / `sdkApiVersion` / `brand` 的访问。`abiList` since 10、crossplatform、API22 存在。
  2. 清单称 `BasicServicesKit` 6 文件 / `LocalizationKit` 6 文件 / `resourceManager` 7 文件 —— 实际 import 数与之略有出入（见各表「本地用法摘要」列），且 `MultiplayerInputPage`/`SettingsPage` 命中的是本地类型 `InputDeviceInfo`（来自 `../common/InputPortRouting`），**不是** `deviceInfo` 命名空间。
- **`vibrator.startVibration` 需 `ohos.permission.VIBRATE`** —— 已在 `entry/src/main/module.json5` L15 声明，**合规**（非缺陷，本可成为坑但已规避）。
- **`hilog` domain 范围 0x0–0xFFFF**（.d.ts 注释口径，比 C++ 侧 0xD000–0xFFFF 更宽）；本地用 0xD003/0xD004 均在范围内。**`%{public}` 占位符是 C++ `OH_LOG_*` 的概念，ArkTS `hilog` 用模板字符串拼接，无需 `%{public}`** —— 本地正确未使用。
- **`resourceManager` 在 ArkTS 侧只当类型用**（`resourceManager.ResourceManager` 标注 NAPI 参数 `resMgr`），**ArkTS 侧零实例方法调用**；`getRawFileContent` 等取资源动作发生在 C++/native 侧。.d.ts 中 `getRawFileContent`/`getRawFileContentSync` **未** deprecated（since 10/11），任务清单「getRawFileContent 等是否 deprecated」的疑问 → 答案是**未弃用**。

### BasicServicesKit — @ohos.base.d.ts (BusinessError) + @ohos.deviceInfo.d.ts (deviceInfo)

| 符号 | 类型 | 本地用法摘要（文件:行号） | 本机 .d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|------|------|------------------------|-----------------------------------------------|-----------|----------|
| `deviceInfo.abiList` | `const: string` | 取设备 ABI 列表判 arm64/x86_64 选核：`RuntimePathResolver.ets:25,49` / `CoreLoaderTest.ets:230` / `LibretroNewArchTestPage.ets:721` / `TestGambatte.ets:1239`（全为 `String(deviceInfo.abiList ?? '').toLowerCase()`，做了 null 合并 + 多 ABI 子串判定，未做全等） | 存在；`const abiList: string;`(`@ohos.deviceInfo.d.ts` L308)；**since 10**、`@crossplatform`；无 deprecated | 一致 | **一致** |
| `BusinessError` | `interface<T=void> extends Error` | 类型断言错误对象 + 取 `.message`：`LibraryRepository.ets:553-554`(`err as BusinessError` → `businessError.message`) / `RomImportService.ets:224`(`err as BusinessError`) | 存在；`export interface BusinessError<T = void> extends Error { code: number; data?: T; }`(`@ohos.base.d.ts` L225)；since 6/10/11/12（多版本 doc）；无 deprecated | 一致 | **一致**（仅断言 + 读 `.message`，类型安全） |

> import 实证：`deviceInfo` from `@kit.BasicServicesKit` 在 `CoreLoaderTest.ets:8` / `LibretroNewArchTestPage.ets:7` / `RuntimePathResolver.ets:1` / `TestGambatte.ets:16`（4 文件 import + 实际取值）。`BusinessError` from `@kit.BasicServicesKit` 在 `LibraryRepository.ets:2` / `RomImportService.ets:2`（2 文件）。
> 勘误：未发现任何 `deviceInfo.deviceModel` / `deviceInfo.sdkApiVersion` / `deviceInfo.brand` 调用 → 任务清单「取设备型号/SDK版本/品牌」描述与实物不符，实际只用 `abiList`。

### LocalizationKit — @ohos.resourceManager.d.ts (resourceManager)

| 符号 | 类型 | 本地用法摘要（文件:行号） | 本机 .d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|------|------|------------------------|-----------------------------------------------|-----------|----------|
| `resourceManager.ResourceManager` | `interface`（**仅作类型**） | 标注 NAPI 入参 `resMgr` / `context.resourceManager` 类型，传入 C++ 侧取 rawfile：`RuntimeRomSourceScanner.ets:10`(签名 `refactoredGetRawFileListAsync(resMgr: resourceManager.ResourceManager, …)`) / `RuntimeSessionController.ets:14,44` / `LibretroSwitchCoordinator.ets:15,33` / `RuntimePathResolver.ets:32` / `LibretroNewArchTestPage.ets:52` / `TestGambatte.ets:30,34`。**ArkTS 侧无任何实例方法调用** | 存在；`export interface ResourceManager`(`@ohos.resourceManager.d.ts` L841)；since 6/11；无 deprecated | 一致 | **一致**（类型契约，运行期取值在 native） |
| *(参考)* `ResourceManager.getRawFileContent` | 实例方法 | ArkTS **未直接调用**（native 侧用）；列出以回应任务「是否 deprecated」 | 存在；`getRawFileContent(path: string): Promise<Uint8Array>`(L3478) / `getRawFileContentSync(path): Uint8Array`(L4199)；since 10/11；**未 deprecated** | 一致 | **未弃用**（澄清） |

> import 实证：`resourceManager` from `@kit.LocalizationKit` 在 `LibretroNewArchTestPage.ets:9` / `RuntimePathResolver.ets:2` / `RuntimeSessionController.ets:2`（值导入）+ `LibretroSwitchCoordinator.ets:2` / `RuntimeRomSourceScanner.ets:3`（`import type`，仅类型）+ `TestGambatte.ets:18`。共 6 文件，全部仅用 `resourceManager.ResourceManager` 这个类型，无 `.getString`/`.getRawFd`/`.getRawFileList` 等实例调用。
> 注：`@ohos.resourceManager.d.ts` 内确有大量 `@deprecated since 20` 条目（如 `getSystemResourceManager()`→`getSysResourceManager`、`getString(resId)` 等旧重载），但**本地一个都没用到**，故不构成差异。

### PerformanceAnalysisKit — @ohos.hilog.d.ts (hilog)

| 符号 | 类型 | 本地用法摘要（文件:行号） | 本机 .d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|------|------|------------------------|-----------------------------------------------|-----------|----------|
| `hilog.info` | function | `LogHelper.ets:5` `hilog.info(domain, tag, \`…\`)`，domain 默认 `0xD003` | 存在；`function info(domain: number, tag: string, format: string, ...args: any[]): void`(L117)；since 7/10/11；无 deprecated | 一致 | **一致** |
| `hilog.warn` | function | `LogHelper.ets:9`，domain 默认 `0xD003` | 存在；`function warn(domain, tag, format, ...args): void`(L154)；since 7/10/11；无 deprecated | 一致 | **一致** |
| `hilog.error` | function | `LogHelper.ets:13`，domain 默认 `0xD003`；调用方另传 `0xD004`（`VirtualController.ets:41,45`） | 存在；`function error(domain, tag, format, ...args): void`(L191 区段)；since 7/10/11；无 deprecated | 一致 | **一致** |

> domain 范围：.d.ts 注释「a hexadecimal integer ranging from 0x0 to 0xFFFF」（L47 等）。本地 0xD003 / 0xD004 均在范围内 ✅。
> `%{public}` 占位符：属 C++ `OH_LOG_Print` 体系；ArkTS `hilog` 直接用模板字符串拼好再传 `format`，本地正确**未**使用 `%{public}d/u/X`，无需此约束。

### SensorServiceKit — @ohos.vibrator.d.ts (vibrator)

| 符号 | 类型 | 本地用法摘要（文件:行号） | 本机 .d.ts(API22): 存在/签名/since/deprecated/权限 | 官方API22 | 差异结论 |
|------|------|------------------------|-----------------------------------------------------|-----------|----------|
| `vibrator.startVibration` | function（callback 重载） | `VirtualController.ets:34` 触觉反馈：`startVibration({type:'time', duration}, {usage:'touch'}, (error)=>{…})` | 存在；`function startVibration(effect: VibrateEffect, attribute: VibrateAttribute, callback: AsyncCallback<void>): void`(L141)；since 8（API22 重新标注 since 22）；无 deprecated；**@permission ohos.permission.VIBRATE** | 一致 | **一致**（含权限合规，见下） |
| └ 参数 `VibrateTime` | `interface` | `{type:'time', duration:number}` | 存在；`interface VibrateTime { type: 'time'; duration: number; }`(L887/911/935)；since 9 | 一致 | **一致** |
| └ 参数 `VibrateAttribute` | `interface` | `{usage:'touch'}` | 存在；`interface VibrateAttribute { usage: Usage; id?: number; deviceId?: number; }`(L753/821)；since 9 | 一致 | **一致** |

> **权限合规实证**：`startVibration` 需 `ohos.permission.VIBRATE`，已在 `entry/src/main/module.json5` L15 `requestPermissions` 声明（reason=`$string:vibrate_reason`）。**非缺陷** —— 本可成为「调用需权限但未声明」的运行期失败坑，但已正确规避。
> import 实证：`vibrator` from `@kit.SensorServiceKit` 在 `VirtualController.ets:13`（1 文件，与任务清单一致）。
> 健壮性：`triggerHaptic` 用 try/catch 包裹 + callback `error` 分支记日志（`VirtualController.ets:39-46`），振动失败不影响输入主流程。

### 第一部分统计

- **本地用到的小 Kit 符号总数：5**（deviceInfo.abiList / BusinessError / resourceManager.ResourceManager / hilog ×3 / vibrator.startVibration；hilog 的 info/warn/error 合记为 3，符号去重后 5 类）。
- **一致：5 / 5（100%）**。全部 API22 .d.ts 存在、签名一致、since ≤ 22 覆盖、本地用法合规。
- **有差异（代码层面）：0** ｜ **缺失：0** ｜ **签名不匹配：0**。
- **deprecated 命中：0**（resourceManager 内的 since-20 弃用项本地全未触及；getRawFileContent 未弃用）。
- **权限相关：1 处需权限**（vibrator → VIBRATE），**已声明，合规**。
- **审计输入勘误：2 处**（deviceInfo 实际只用 abiList 非 model/sdkVersion/brand；部分文件数与清单略有出入 + InputDeviceInfo 误计）。
- **since 覆盖**：本地最高 since=11（resourceManager.ResourceManager 的 11 版 doc / VibrateTime since 9 / vibrator callback 重载本体 since 8）；compatibleSdkVersion=targetSdkVersion=22，全覆盖，无低版本 dlsym 风险。

落盘路径: `docs/audit/api22-diff/arkts/misc-and-usage.md`（第一部分完成；第二部分见下）

---

## 第二部分：ArkTS 用法兼容坑专项扫描

> 扫描范围: `entry/src/main/ets/` 全量 `.ets`（排除 deprecated/legacy）。每条反模式给「命中文件:行号」或「0命中 ✅」。
> 判定基准: ArkTS 严格模式（HarmonyOS NEXT / API22 cookbook `arkts-no-*` 规则）+ 本仓历史 memory（`feedback_arkts_v1v2_no_mixing` / `feedback_arkts_no_func_apply_call` / `feedback_arkts_edit_safety` / `feedback_napi_return_type_lie_hides_bug`）。
> `arkts-no-spread` 已 web 交叉验证仍为 error（API12/NEXT/API22，2026-06-05 grok web_search 命中 openharmony docs gitee）。

### 结论速览（第二部分）

- **6 条反模式：5 条 0 命中 / 干净，1 条命中真坑（坑4 对象 spread）+ 1 条衍生出独立高危 finding（坑6 类型契约反向漂移）。**
- **最严重：坑6 衍生 — `index.d.ts` 把 `refactoredStartEngine`/`refactoredLoadCore`/`refactoredLoadRom` 声明为 `() => boolean`，但 C++ 实际 `MakeErrorResult` 返回结构对象 `NapiErrorResult{success,...}`。** 这是 `feedback_napi_return_type_lie_hides_bug` 的**反向**实例：SSOT 撒谎说 boolean，真值（C++ + 测试页消费侧）是对象。当前生产页 `LibretroGamePage` 走的是 `switchGame`（用 `result.success` 正确），未直接调这三个；但任何**新 caller 信 `index.d.ts` 写 `if(!ok)`** 会对 `{success:false}` 恒 false → **失败假报成功**。HIGH 风险。
- **坑4 命中：`LibraryMetadataMigration.ets:167-173` 对象 spread `{...record, …}`** —— ArkTS `arkts-no-spread`(error) 编译阻断。所在文件 live（非 deprecated），但其唯一导出 `migrateGameMetadataToLibrary` **当前全仓无外部 caller**（orphan），故尚未触发构建失败；一旦接线进页面或跑全量严格编译即炸。MEDIUM-HIGH（潜伏编译炸弹）。
- **坑1（V2 装饰器）/ 坑3（.call/.apply）/ 坑5（any/unknown/ESObject）：均 0 命中 ✅。** 本仓是纯 V1 项目、无 func-apply-call、无 any —— 三条历史 memory 已被代码内化。
- **坑2（Number.isFinite/isNaN 窄化）：30+ 命中，全部安全 ✅。** 所有命中点要么先 `typeof x === 'number'` 窄化、要么显式 `x === undefined ||` 前置判定、要么作用于非可选 `number` 字段 —— 无一裸用 `Number.isFinite(opt) ? opt : fb` 把 `number|undefined` 当 `number` 用。`feedback_arkts_v1v2_no_mixing` 的窄化教训已落地。

### 用法坑专项表

| # | 反模式 | grep 结果（命中文件:行号 / 0命中） | 风险等级 | 结论 |
|---|--------|----------------------------------|----------|------|
| 1 | **V1/V2 状态装饰器混用**（@ObservedV2/@Trace/@ComponentV2/@Local/@Param/@Monitor/@Provider/@Consumer/@Once/@Event/@ReusableV2） | **0 命中 ✅**（case-sensitive；早期 14 个 `@param` 命中均为 JSDoc 注释 `* @param`，非装饰器，已排除） | — | **干净**。纯 V1 项目，无任何 V2 装饰器，无编译 OOM 风险 |
| 2 | **`Number.isFinite`/`isNaN` 不窄化类型** | **31 命中**（EmuTelemetryPanel:15 / GameMetadataRepository:137 / InputLayoutPage:171,337 / InputLayoutRepository:210,228 / LibraryRuntimeTelemetryPresenter:90,122 / LibretroEventHub:593,597 / LibretroGamePage:362,431,451,459,472,503 / LibretroNewArchTestPage:641,682-687 / MetadataEditPage:125 / RomImportService:742 / RuntimeInputCommandBridge:23 / RuntimeInputDebugTracker:104 / RuntimeLibrarySessionTracker:42 / RuntimeVirtualControllerLayer:452 / SaveStateRepository:339 / TestGambatte:381） | **低（已规避）** | **全部安全**。逐点核：(a) `LibretroEventHub:592-593` 先 `typeof==='number'` 窄化；(b) `InputLayoutRepository:210,228` 显式 `value===undefined \|\|`；(c) `InputLayoutPage:171` 的 `button.retroButtonId` 类型为非可选 `number`（`InputLayoutRepository.ets:13`）；(d) `RuntimeInputCommandBridge:23`/`RuntimeInputDebugTracker:104` 作用于非可选 `number`/`Number()` 结果。无 `number\|undefined` 裸用 |
| 3 | **`.call(` / `.apply(`** | **0 命中 ✅** | — | **干净**。无 `arkts-no-func-apply-call` 触发 |
| 4 | **对象 spread `{...obj}`** | **1 命中 🔴 `LibraryMetadataMigration.ets:167-173`**（`return { ...record, releaseYear:…, publisher:…, updatedAt:… }`）。其余 `...` 全为数组 spread `[...arr]`（LibraryPagePresenter:46 / LibretroNewArchTestPage:471 等，合法）或字符串 ellipsis（`'测试中...'`，误报） | **中-高（潜伏编译炸弹）** | **真坑**。`arkts-no-spread`(error) 禁对象 spread（web 已验证 API22 仍生效）。文件 live 非 deprecated，但导出 `migrateGameMetadataToLibrary` 当前 orphan（无 caller，`L92` 仅内部调用）→ 尚未触发构建失败。修法：手动逐字段赋值 / `Object.assign`。**本审计不改代码** |
| 5 | **`any`/`unknown`/`ESObject`/`as any`** | **0 命中 ✅**（pattern: `: any` / `<any>` / `as any` / `: unknown` / `as unknown` / `ESObject` / `any[]` / `Array<any>` / `Record<string,any>`） | — | **干净**。无 `arkts-no-any-unknown` 触发 |
| 6 | **NAPI 返回类型谎言** | **`refactoredSwitchGameAsync` 消费侧正确 ✅** —— `LibretroGamePage.ets:1051` 用 `if(!result.success)` 读结构字段，非 `if(!result)`。**但衍生出独立高危：见下 🔴** | **高（衍生 finding）** | **见衍生 finding：`index.d.ts` StartEngine/LoadCore/LoadRom 类型契约反向漂移** |

### 坑6 衍生 — `index.d.ts` 三个 export 返回类型反向漂移（HIGH）

| 维度 | 真值 | 出处 |
|------|------|------|
| C++ 实际返回 | `NapiErrorResult{success,errorCode?,message?}`（结构对象） | `engine_lifecycle_napi.cpp` StartEngine L353-369 / LoadCore L373-405 / LoadRom L409-457 全 `return MakeErrorResult(env, …)`；`MakeErrorResult` 建 object 带 `"success"` 属性（`engine_napi_common.h:444-472`） |
| SSOT `index.d.ts` 声明 | ❌ `() => boolean` | `types/libentry/index.d.ts` L36(`refactoredStartEngine`) / L42(`refactoredLoadCore`) / L43-46(`refactoredLoadRom`) |
| `AGENTS.md` NAPI Inventory | ❌ 列为 `boolean / sync` | AGENTS.md「生命周期(13)」表 refactoredStartEngine/LoadCore/LoadRom 三行 |
| 测试页消费侧 | ✅ 声明 `NapiErrorResult` + 读 `.success`（与 C++ 一致） | `TestGambatte.ets:24,27,28` + `:757,767,781,918,940,966`；`LibretroNewArchTestPage.ets:46,49,50` + `:244-245,264-265,281-282` |

- **本质**：`feedback_napi_return_type_lie_hides_bug` 的**反向**形态 —— 通常是「TS 声明 Promise<boolean> 但 C++ resolve 对象」；这里是「TS 声明 `boolean` 但 C++ 同步返回对象」，且 SSOT(`index.d.ts`) 与 Inventory 两处都撒谎，只有测试页（非 SSOT）说真话。
- **当前是否爆炸**：否。生产路径 `LibretroGamePage` 改走 `refactoredSwitchGameAsync`（`switchGame` 封装）而非直调这三个；测试页 `.success` 读法恰好与真实 object 对齐。
- **未来风险（HIGH）**：任何新 caller 信 `index.d.ts` 写 `const ok = refactoredStartEngine(); if (!ok) {…}` —— `ok` 是 object `{success:…}`，`!object` 恒 `false` → **失败永远静默假报成功**，与三处 memory 反复警示的同类 bug。
- **建议（不在本审计执行）**：把 `index.d.ts` L36/L42/L43-46 + AGENTS.md 三行从 `boolean` 改为 `NapiErrorResult`，与 C++ 实物 + 测试页对齐；`scan_code_drift.sh` Pattern 5 应能守住后续漂移。**ROLE 边界：本审计只记录，不改业务代码 / 不改 SSOT。**

### 第二部分统计

- **扫描反模式：6 条** ｜ **0命中/干净：4 条**（坑1 V2装饰器 / 坑3 .call.apply / 坑5 any / 坑2 实质安全）｜ **命中真坑：1 条**（坑4 对象 spread）｜ **衍生高危 finding：1 条**（坑6 → index.d.ts 类型反向漂移）。
- **按风险**：HIGH 1（index.d.ts StartEngine/LoadCore/LoadRom 返回类型谎言）｜ MEDIUM-HIGH 1（坑4 对象 spread 潜伏编译炸弹）｜ LOW/已规避 1（坑2 窄化，30+ 点全安全）｜ 干净 3（坑1/坑3/坑5）。
- **本仓历史 memory 落地验证**：`feedback_arkts_no_func_apply_call`（坑3 0命中）✅ / `feedback_arkts_v1v2_no_mixing`（坑1 0命中 + 坑2 全窄化安全）✅ / `feedback_arkts_edit_safety` 对象 spread 禁令（坑4 命中 1 处待清）⚠️ / `feedback_napi_return_type_lie_hides_bug`（坑6 消费侧正确，但 SSOT 声明侧反向漂移）⚠️。

---

## 全局 Top3（跨两部分）

1. **[HIGH] `index.d.ts` 三个 export 返回类型反向漂移**（坑6 衍生）：`refactoredStartEngine`/`refactoredLoadCore`/`refactoredLoadRom` 声明 `() => boolean`，C++ 实际返回 `NapiErrorResult` 对象。当前生产路径绕开未爆，但新 caller 信 SSOT 写 `if(!ok)` 会失败假报成功。需同步 `index.d.ts` + AGENTS.md → `NapiErrorResult`。
2. **[MEDIUM-HIGH] 对象 spread 潜伏编译炸弹**（坑4）：`LibraryMetadataMigration.ets:167-173` `{...record, …}` 触发 `arkts-no-spread`(error)；导出函数当前 orphan 暂未触发构建失败，接线即炸。改手动赋值 / `Object.assign`。
3. **[低/记录] 审计输入勘误**（第一部分）：清单称 `deviceInfo` 取「设备型号/SDK版本/品牌」，实物只用 `deviceInfo.abiList`（选核判 ABI）；`getRawFileContent` 未弃用（清单疑问澄清）；`vibrator` 需 VIBRATE 权限已在 `module.json5:15` 声明合规。

## 全局统计

- **第一部分（4 小 Kit）**：本地用 5 符号 → 一致 5 / 差异 0 / 缺失 0 / deprecated 命中 0；权限 1 处（VIBRATE）已声明合规；审计输入勘误 2 处。
- **第二部分（6 用法坑）**：0命中/干净 4 条、命中真坑 1 条（坑4）、衍生高危 1 条（坑6→index.d.ts）；风险分布 HIGH 1 / MED-HIGH 1 / LOW 1 / 干净 3。
- **最高优先级 1 条**：`index.d.ts` 把 StartEngine/LoadCore/LoadRom 谎报为 `boolean`（C++ 实为 `NapiErrorResult` 对象），新 caller 易踩「失败假报成功」。

落盘路径: `docs/audit/api22-diff/arkts/misc-and-usage.md`
