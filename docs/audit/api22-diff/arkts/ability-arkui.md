# ArkTS — AbilityKit + ArkUI Kit 鸿蒙 API 三源差异审计 (API 22)

> 目标 SDK = 6.0.2(22) = API 22（`build-profile.json5`: compatibleSdkVersion=6.0.2(22) / targetSdkVersion=6.0.2(22)）
>
> **源 A 本地代码**：`entry/src/main/ets/`（Grep 精确 callsite，文件:行号见下）
> **源 B 本机 SDK .d.ts（API22 权威，version 6.0.2.130）**：
>   - Kit 聚合：`…/openharmony/ets/kits/@kit.AbilityKit.d.ts` / `@kit.ArkUI.d.ts`
>   - 符号真值：`…/openharmony/ets/api/@ohos.app.ability.{UIAbility,Want,AbilityConstant,common}.d.ts` / `@ohos.display.d.ts` / `@ohos.window.d.ts`
> **源 C 官方 API22 文档**：`mcp__web-search__web_search` 交叉验证 1 次（window getLastWindow/setWindowKeepScreenOn deprecated 链路），其余以 .d.ts 为准。
>
> **关键事实**：本机 .d.ts 即 API22。`@since N` JSDoc = since 真值，`@deprecated` 注释 = deprecated 真值。.d.ts 真实性佐证：`common.d.ts` 最新增量 `FormEditExtensionContext`/`LiveFormExtensionContext` 标 `@since 22`（L244/255），本项目未用。
>
> 审计日期: 2026-06-05 · 状态: 完成 · ROLE: 只审计填表，未改任何 .ets/.cpp/.h

---

## 结论速览

- **本地用到 7 个 Kit 顶层符号**：AbilityKit 5（`common` / `UIAbility` / `Want` / `AbilityConstant` / `MemoryLevel`）+ ArkUI 2（`display` / `window`）；展开为 **18 个具体 API/类型/枚举值**（见差异表）。
- **全部存在于 API22 .d.ts，签名一致，本地全部用符号常量（无硬编码枚举数值）**——**0 个缺失 / 0 个签名不匹配 / 0 个 bug**。
- **deprecated 误用命中：0**。本审计重点核查 `display` / `window` 两大「鸿蒙演进高频废弃模块」：
  - `window`：本地用 `getLastWindow`（since 12，**非** deprecated 的 `getTopWindow` since 9）+ `setWindowKeepScreenOn`（since 9+，**非** deprecated 的 `setKeepScreenOn` since 9）→ **两处都已用新接口**，正确。
  - `display`：本地用 `getFoldStatus`/`getFoldDisplayMode`/`on/off('foldStatusChange'|'foldDisplayModeChange')`，**均非 deprecated**。.d.ts 中 deprecated 的 `getDefaultDisplay`/`getAllDisplays`（since 7→deprecated 9）**本地完全未用**（grep 0 命中）。
- **since 覆盖**：本地最高 since=12（`getLastWindow` / `Want`(11) / `getFoldDisplayMode`(10) 等），全部 ≤ 22 → **无低版本 dlsym/符号缺失风险**。
- **context 获取方式**：本地统一 `this.getUIContext().getHostContext() as common.UIAbilityContext`（UI 组件内，58 文件）+ `this.context`（UIAbility 内）→ **符合 API22 推荐用法**，无 deprecated `getContext(this)` 全局函数残留。
- **真实差异 M=0**；**用法层零坑**。唯一可记录项是「增强清单」（API22 有、本地未用，非缺陷）。

---

## 差异表

> since 标注=本机 .d.ts JSDoc `@since N` 真值（多段 JSDoc 取**首段** initial since；后续段为能力扩展如 atomicservice/crossplatform 标注）。
> 本地行号见各 callsite 列。所有 .d.ts 行号基于上列 `@ohos.*.d.ts`。

### AbilityKit

| API | 类型 | 本地用法摘要 (文件:行号) | 本机.d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------------------|----------------------------------------------|-----------|----------|
| `common` (namespace) | 命名空间 | `@kit.AbilityKit` import，58 文件 | 存在; `@ohos.app.ability.common` namespace; since 9 (L66); 无 deprecated | 一致 | **一致** |
| `common.UIAbilityContext` | type 别名 | 全仓库类型注解（`as common.UIAbilityContext`，~90 callsite，如 `LibretroGamePage.ets:1159`/`LibraryRepository.ets:119`） | 存在; `export type UIAbilityContext = _UIAbilityContext.default`(common.d.ts L92); since 9; 无 deprecated | 一致 | **一致** |
| `UIAbility` | class | `EntryAbility.ets:31` `extends UIAbility` | 存在; `declare class UIAbility extends Ability`(UIAbility.d.ts L274); since 9; 无 deprecated | 一致 | **一致** |
| `UIAbility.context` | 属性 | `EntryAbility.ets:43` `this.context` 传入 InputMappingService | 存在; `context: UIAbilityContext`(UIAbility.d.ts L302); since 9 | 一致 | **一致** |
| `UIAbility.onCreate` | 方法 | `EntryAbility.ets:32` `onCreate(want, launchParam)` | 存在; `onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void`(L381); since 9 | 一致 | **一致**（签名逐参匹配） |
| `UIAbility.onWindowStageCreate` | 方法 | `EntryAbility.ets:55` `(windowStage: window.WindowStage)` | 存在; `onWindowStageCreate(windowStage: window.WindowStage): void`(L409); since 9 | 一致 | **一致** |
| `UIAbility.onWindowStageDestroy` | 方法 | `EntryAbility.ets:71` | 存在; `onWindowStageDestroy(): void`(L437 区段); since 9 | 一致 | **一致** |
| `UIAbility.onDestroy` | 方法 | `EntryAbility.ets:50` | 存在; `onDestroy(): void \| Promise<void>`(L498); since 9 | 一致 | **一致**（本地用 `void` 返回，合法子集） |
| `UIAbility.onForeground` / `onBackground` | 方法 | `EntryAbility.ets:76` / `:84` | 存在; `onForeground(): void`(L530) / `onBackground(): void`(L575); since 9 | 一致 | **一致** |
| `UIAbility.onMemoryLevel` | 方法 | `EntryAbility.ets:92` `onMemoryLevel(level: MemoryLevel)` | 存在; 继承自 `Ability`; 参数 `MemoryLevel`; since 9 | 一致 | **一致** |
| `Want` | interface | `EntryAbility.ets:15` import + `:32` `onCreate(want: Want, …)` 参数类型 | 存在; `declare interface Want`(Want.d.ts，首段 since 9 区，L23); 无 deprecated | 一致 | **一致**（仅作类型注解，未访问字段） |
| `AbilityConstant` (namespace) | 命名空间 | `EntryAbility.ets:15` import | 存在; `declare namespace AbilityConstant`(AbilityConstant.d.ts L48); since 9 | 一致 | **一致** |
| `AbilityConstant.LaunchParam` | interface | `EntryAbility.ets:32` `launchParam: AbilityConstant.LaunchParam` 参数类型 | 存在; `export interface LaunchParam`(L88); since 9; 无 deprecated | 一致 | **一致**（仅类型注解，未读字段） |
| `MemoryLevel` (enum) | enum 类型 | `EntryAbility.ets:15` import + `:92` `onMemoryLevel(level: MemoryLevel)` 参数类型 | 存在; `export enum MemoryLevel`(AbilityConstant.d.ts L744); since 9（首段，L732）; 无 deprecated | 一致 | **一致**（值 MODERATE=0/LOW=1/CRITICAL=… 全在；本地仅作类型未取值） |

> 说明：`MemoryLevel` 在 `@kit.AbilityKit` 顶层导出（聚合文件 export 列含 `AbilityConstant`），真实声明在 `AbilityConstant.d.ts` 内作为 `AbilityConstant.MemoryLevel`；通过 `import { MemoryLevel }` 取顶层别名，与 .d.ts 一致。

### ArkUI — display (11 文件)

| API | 类型 | 本地用法摘要 (文件:行号) | 本机.d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------------------|----------------------------------------------|-----------|----------|
| `display` (namespace) | 命名空间 | `@kit.ArkUI` import，11 文件（如 `SettingsPage.ets:2`） | 存在; `declare namespace display`(display.d.ts L46); since 11（namespace 级，crossplatform/atomicservice） | 一致 | **一致** |
| `display.getFoldStatus` | 函数 | `SettingsPage.ets:254` / `InputLayoutPage.ets:134` / `SaveStatePage.ets:107` / `MultiplayerInputPage.ets:117` | 存在; `function getFoldStatus(): FoldStatus`(L311); since 10（首段 L290）; **无 deprecated** | 一致 | **一致** |
| `display.getFoldDisplayMode` | 函数 | `CoreManagerPage.ets:65` / `ImportEntryPage.ets:114` / `OnboardingPage.ets:93` / `InputLayoutPage.ets:135` / `SaveStatePage.ets:108` / `MultiplayerInputPage.ets:118` | 存在; `function getFoldDisplayMode(): FoldDisplayMode`(L501); since 10（首段 L480）; **无 deprecated** | 一致 | **一致** |
| `display.on('foldStatusChange', cb)` | 函数(事件) | `CoreManagerPage.ets:53` / `InputLayoutPage.ets:100` / `OnboardingPage.ets:82` / `SaveStatePage.ets:65` / `SettingsPage.ets:242` / `MultiplayerInputPage.ets:119` | 存在; `function on(type: 'foldStatusChange', callback: Callback<FoldStatus>): void`(L348); since 10; 无 deprecated | 一致 | **一致** |
| `display.off('foldStatusChange', cb)` | 函数(事件) | 上述页面对应 `aboutToDisappear`（如 `CoreManagerPage.ets:60`） | 存在; `function off(type: 'foldStatusChange', callback?: Callback<FoldStatus>): void`(L385); since 10 | 一致 | **一致** |
| `display.on('foldDisplayModeChange', cb)` | 函数(事件) | `ImportEntryPage.ets:118` / `MultiplayerInputPage.ets:120` | 存在; `function on(type: 'foldDisplayModeChange', callback: Callback<FoldDisplayMode>): void`(L538); since 10 | 一致 | **一致** |
| `display.off('foldDisplayModeChange', cb)` | 函数(事件) | `ImportEntryPage.ets:129` / `MultiplayerInputPage.ets:129` | 存在; `function off(type: 'foldDisplayModeChange', callback?: Callback<FoldDisplayMode>): void`(L575); since 10 | 一致 | **一致** |
| `display.FoldStatus` (enum) | enum | 类型注解 + 比较（`SettingsPage.ets:262`，值 FOLD_STATUS_EXPANDED/FOLDED/HALF_FOLDED/UNKNOWN） | 存在; `enum FoldStatus`(L821); since 10（首段）; 无 deprecated; 值 UNKNOWN=0/EXPANDED=1/FOLDED=2/HALF_FOLDED=3 | 一致 | **一致**（本地用到的 4 值全在；本地用常量非裸数值） |
| `display.FoldDisplayMode` (enum) | enum | 类型注解 + 比较（`OnboardingPage.ets:279` 等，值 FULL/MAIN/SUB/UNKNOWN） | 存在; `enum FoldDisplayMode`(L981); since 10（首段）; 无 deprecated; 值 UNKNOWN=0/FULL=1/MAIN=2/SUB=3/COORDINATION | 一致 | **一致**（本地用到的 4 值全在；用常量） |

### ArkUI — window (2 文件)

| API | 类型 | 本地用法摘要 (文件:行号) | 本机.d.ts(API22): 存在/签名/since/deprecated | 官方API22 | 差异结论 |
|-----|------|------------------------|----------------------------------------------|-----------|----------|
| `window` (namespace) | 命名空间 | `@kit.ArkUI` import（`EntryAbility.ets:16` / `LibretroGamePage.ets:8`） | 存在; `@ohos.window` namespace; 无 deprecated | 一致 | **一致** |
| `window.WindowStage` | interface | `EntryAbility.ets:55` `onWindowStageCreate(windowStage: window.WindowStage)` + `:62` `windowStage.loadContent(...)` | 存在; `interface WindowStage`(window.d.ts L8585); since 9（首段 L8564） | 一致 | **一致** |
| `window.Window` | interface | `LibretroGamePage.ets:1160` `(win: window.Window)` 类型注解 | 存在; `interface Window`(window.d.ts L3438); since 6/7（首段 L3425） | 一致 | **一致** |
| `window.getLastWindow(ctx)` | 函数 | `LibretroGamePage.ets:1160` `window.getLastWindow(ctx).then((win) => …)` | 存在; `function getLastWindow(ctx: BaseContext): Promise<Window>`(L2518); since 12; **无 deprecated** | 一致 | **一致**（✅ 用新接口，非 deprecated `getTopWindow`） |
| `Window.setWindowKeepScreenOn` | 方法 | `LibretroGamePage.ets:1161` `win.setWindowKeepScreenOn(on)` | 存在; `setWindowKeepScreenOn(isKeepScreenOn: boolean): Promise<void>`(L6574); since 9; **无 deprecated** | 一致 | **一致**（✅ 用新接口，非 deprecated `setKeepScreenOn`） |

---

## deprecated 专项核查（本审计重点）

> `display` 与 `window` 是鸿蒙演进中废弃过较多老 API 的两个模块。逐条核对本地是否踩 .d.ts 标 `@deprecated` 的老接口：

| .d.ts deprecated 老接口 | @deprecated | @useinstead | 本地是否使用 | 结论 |
|------------------------|-------------|-------------|--------------|------|
| `window.getTopWindow(...)`（4 重载） | since 9 (window.d.ts L2400/2411) | `ohos.window#getLastWindow` | **未用**（grep `getTopWindow` 0 命中；本地用 `getLastWindow`，`LibretroGamePage.ets:1160`） | ✅ 已避开 |
| `Window.setKeepScreenOn(...)`（2 重载） | since 9 (window.d.ts L6520/6531) | `ohos.window.Window#setWindowKeepScreenOn` | **未用**（grep `setKeepScreenOn(` 仅命中 `setWindowKeepScreenOn`；本地 `LibretroGamePage.ets:1161` 用新版） | ✅ 已避开 |
| `display.getDefaultDisplay(...)` | since 9 (display.d.ts L53/63) | `ohos.display#getDefaultDisplaySync` | **未用**（grep 0 命中） | ✅ 已避开 |
| `display.getAllDisplays(...)` | since 9 (display.d.ts L128/138) | `ohos.display#getAllDisplaysSync` | **未用**（grep 0 命中） | ✅ 已避开 |

**结论：deprecated 命中 = 0。** 本地所有 display/window 调用均为 API22 现行非废弃接口。Web 交叉验证（源 C，1 次查询）确认 `window.getLastWindow(this.getUIContext().getHostContext())` + `setWindowKeepScreenOn` 正是 API12+ 官方/社区现行标准用法，旧全局 `getTopWindow`/`setKeepScreenOn` 自 API9 起废弃——与 .d.ts `@deprecated since 9` 完全一致。

### MemoryLevel / onMemoryLevel 专项（审计维度 3）

- 回调签名：本地 `onMemoryLevel(level: MemoryLevel): void`（`EntryAbility.ets:92`）== `UIAbility`(继承自 `Ability`) 的 API22 契约，**一致**。
- 枚举：`MemoryLevel`（AbilityConstant.d.ts L744）值 `MEMORY_LEVEL_MODERATE=0` / `MEMORY_LEVEL_LOW=1` / `MEMORY_LEVEL_CRITICAL=2`，since 9，无 deprecated。本地仅将 `level` 透传日志（`onMemoryLevel: ${level}`），**未取具体枚举值**——无误用面。
- 备注：本地回调当前仅记日志（注释已说明未来可释放 shader 缓存/降音频缓冲），属业务设计，非 API 差异。

### context 获取方式专项（审计维度 4）

- UI 组件内：统一 `this.getUIContext().getHostContext() as common.UIAbilityContext`（~90 callsite，如 `LibretroGamePage.ets:1159`/`SettingsPage.ets:290`）——API22 推荐的 UIContext 关联 context 取法，**无 deprecated 全局 `getContext(this)` 残留**（grep `getContext(` 仅命中本地自定义私有方法 `getContext()`，非系统 API）。
- UIAbility 内：`this.context`（`EntryAbility.ets:43`）——UIAbility.context 属性（since 9），**正确**。
- 结论：context 取法全仓库统一且符合 API22 推荐，**无差异**。

---

## API22 有、本地未用（增强清单，非缺陷）

> 以下为 API22 .d.ts 提供、本地未接入的相关能力，仅作未来可选增强参考，**不构成差异/缺陷**：

| API | since | 模块 | 说明 |
|-----|-------|------|------|
| `display.isFoldable()` | 10 (display.d.ts L283) | display | 折叠设备能力查询；本地直接读 fold 状态，未先查 isFoldable（非折叠设备上 getFoldStatus 返回 UNKNOWN，已被本地逻辑覆盖） |
| `display.getDefaultDisplaySync()` | 9 | display | 取默认屏物理尺寸/密度/方向；本地折叠态走 FoldDisplayMode 推断布局，未读屏物理像素 |
| `display.on('foldAngleChange', cb)` | (高 since) | display | 折叠角度连续回调；本地只用离散 fold 状态，无需角度 |
| `display.on('captureStatusChange', cb)` | (高 since) | display | 录屏/投屏状态回调；当前无防录屏需求 |
| `Window.setWindowLayoutFullScreen` / `getWindowAvoidArea` / `setWindowSystemBarEnable` | 9/9 | window | 沉浸式全屏/避让区/系统栏控制；本游戏页当前仅用 keepScreenOn，未做沉浸式全屏（若后续要隐藏状态栏可接入） |
| `WindowStage.getMainWindow()` | 9 | window | 取主窗口（Web 检索提到的等价替代）；本地用 `getLastWindow(ctx)` 已满足，两者皆现行非废弃 |
| `AbilityConstant.LaunchReason` 等枚举 | 9+ | AbilityConstant | 启动原因/上次退出原因；本地 onCreate 未读 launchParam 字段，未用 |

---

## 最高优先级差异 top3

> 本审计 **真实 API 差异 = 0**。以下 top3 为「值得记录的观察点」（均非缺陷，按重要性排序）：

1. **[deprecated 规避 / 正向确认 · 信息]** 本地在 `window` 模块**主动用新接口避开了两处历史废弃陷阱**：`getLastWindow`（替代 deprecated-since-9 的 `getTopWindow`）+ `setWindowKeepScreenOn`（替代 deprecated-since-9 的 `setKeepScreenOn`），`LibretroGamePage.ets:1160-1161`。这是本仓 ArkTS 侧对 HarmonyOS API 演进跟进到位的正面证据，**无需任何改动**。

2. **[since 边界 / 低 · 已安全]** 本地 ArkTS 侧最高 since 符号为 `window.getLastWindow`（since 12）；其余多在 since 9-11（`Want` 11、fold 系列 10、display namespace 11）。全部 ≤ compatibleSdkVersion 22 → **无低版本符号缺失/dlsym 风险**。仅在未来 minCompatibleSdkVersion 下探 < 12 时需重评 `getLastWindow`（届时可回退 `WindowStage.getMainWindow`，since 9）。

3. **[增强机会 / 低 · 非缺陷]** `onMemoryLevel`（`EntryAbility.ets:92`）当前仅记日志、未在内存压力下释放任何资源；`display.isFoldable()`（since 10）也未用于先验判断折叠能力。两者均为**可选增强点**，不影响 API22 兼容性与现有功能正确性。

---

## 统计

- **本地用到 Kit 顶层符号：7**（AbilityKit 5 + ArkUI 2）。
- **展开具体 API/类型/枚举行：18**（AbilityKit 14 + display 9 + window 5，去重后差异表 28 行含重复枚举/方法细分；按「独立符号」口径 18）。
  - AbilityKit：`common` namespace + `UIAbilityContext` type + `UIAbility` class（含 context/onCreate/onWindowStageCreate/onWindowStageDestroy/onDestroy/onForeground/onBackground/onMemoryLevel）+ `Want` + `AbilityConstant`(+ `LaunchParam`) + `MemoryLevel`。
  - display：namespace + `getFoldStatus` + `getFoldDisplayMode` + `on/off('foldStatusChange')` + `on/off('foldDisplayModeChange')` + `FoldStatus` enum + `FoldDisplayMode` enum。
  - window：namespace + `WindowStage` + `Window` + `getLastWindow` + `setWindowKeepScreenOn`。
- **状态计数：**
  - **一致：全部**（每个 import 符号都在 API22 .d.ts 存在、签名一致、本地用符号常量）。
  - **真实差异（代码层）：0**。
  - **deprecated 命中：0**（4 个 .d.ts 标 deprecated 的老接口 getTopWindow/setKeepScreenOn/getDefaultDisplay/getAllDisplays 本地全部未用）。
  - **签名不匹配：0**；**缺失符号：0**。
- **since 覆盖：** 本地最高 since=12（`getLastWindow`），全 ≤ 22，全覆盖无风险。
- **用法层（ArkTS 专项）：** deprecated 规避正确、context 取法统一合规、MemoryLevel 回调签名匹配——**用法坑 0**。

落盘路径: `docs/audit/api22-diff/arkts/ability-arkui.md`
