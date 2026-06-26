# Agent A — ArkTS/ArkUI V2 迁移对抗式静态审计

> 范围：commit `ddb9ad7`（2026-06-07 V1→V2 全量迁移，64 组件/91 文件）+ 06-08 B 档死代码删除。
> 方法：**纯静态分析，未编译 / 未真机**。
> 仓库：`D:\windsulf\daugf2527-repos\harmonyos-libretro-emulator`

---

## Q1 — V2 静默反应性 bug（对象/数组 @Local/@Param 字段就地 mutate 但类未 @ObservedV2+@Trace）

> 静态分析，未编译 / 未真机。

### 扫描方法
全仓 `*.ets` grep `this\.\w+\.\w+\s*(=|++|--|+=|-=)`（字段就地 mutate）+ `this\.arr[i].field=`（数组元素就地 mutate）。
全仓命中**仅 12 处，分布 2 个文件**；数组元素就地 mutate **0 处**。逐一对照持有它的 @Local/@Param 类型是否 @ObservedV2+@Trace。

| 文件 | 字段 | 类型 | 类型定义 | @ObservedV2? | 判定 |
|---|---|---|---|---|---|
| LibretroGamePage.ets:464/465/490/500 | `perfDisplay` | `PerfDisplayState` | LibretroGamePage.ets:109 | ✅ 是（5 @Trace） | 安全（已知正确，排除） |
| LibretroNewArchTestPage.ets:739/740/744/748/751/754 | `coreCheck` | `CoreCheckState` | LibretroNewArchTestPage.ets:131 `interface` | ❌ 否 | **🔴 bug → A-Q1-1** |
| LibretroNewArchTestPage.ets:772/773/774 | `soakState` | `RuntimeSoakState` | RuntimeSoakTestController.ets:16 `interface` | ❌ 否 | **🔴 bug → A-Q1-2** |

`audioStatus`(AudioStatusPayload, interface) / `stats`(RuntimeStatsDTO, interface) 虽也是裸 interface，但全部 mutate 走**整体替换** `this.x = {...}`（行 320/340/371/376/433）—— @Local 追踪引用替换，整体替换会触发刷新 → **安全**，不计 finding。

---

### 🔴 A-Q1-1 [P1] `coreCheck` 字段就地 mutate，UI 静默不刷新
**位置**：`pages/LibretroNewArchTestPage.ets:131`（类型定义）+ `:739-754`（mutate）+ `:1558-1567`（消费）

**证据链**：
- `:131` `interface CoreCheckState { running: boolean; text: string; }` —— **裸 interface，非 @ObservedV2，字段无 @Trace**。
- `:186` `@Local coreCheck: CoreCheckState = { running: false, text: '' };` —— @Local 持有。
- `:739-754` `runCoreCheck()` 全程**字段就地 mutate**：
  ```
  this.coreCheck.running = true;
  this.coreCheck.text = '正在验证核心符号...';
  ...
  this.coreCheck.text = result;
  this.coreCheck.running = false;
  ```
- `:1558-1567` build() 把字段值传给子组件：
  ```
  DevDiagnosticsBlock({ coreCheckRunning: this.coreCheck.running, coreCheckText: this.coreCheck.text, ... })
  ```
- 子组件 `components/DevDiagnosticsBlock.ets:8-9` `@Param coreCheckRunning/coreCheckText` 接收，build() 据此切换按钮 spinner / 文案 / 结果文字。

**为何是真 bug**：V2 的 `@Local` 只追踪**引用本身被替换**，不深层追踪 interface 字段。`this.coreCheck.running = true` 改的是字段、引用没变 → 父组件 `LibretroNewArchTestPage.build()` 不重算 → `DevDiagnosticsBlock(...)` 构造调用不重新求值 → 传入子组件的 @Param 永远停在初始值。实际表现：点"验证核心符号"按钮，spinner 不出现、文案不变"验证中...""、`testCoreLoader` 结果文字永不显示。功能静默失效，无崩溃 → **P1**。
（V1 时代 `@State` 对象也是浅追踪，但 V1 模板对 `this.x.field` 的读会建立依赖，行为与 V2 不同；这正是"迁移后才暴露"的典型回归。）

**建议修法**（任选一）：
1. 给 `CoreCheckState` 改成 `@ObservedV2 class` + 两字段加 `@Trace`（与 PerfDisplayState 同范式，最贴合本次迁移意图）。
2. 或改为**整体替换**：`this.coreCheck = { running: true, text: '...' };`（与 audioStatus/stats 同范式，最小改动）。

---

### 🔴 A-Q1-2 [P1] `soakState` 字段就地 mutate，UI 静默不刷新
**位置**：`common/RuntimeSoakTestController.ets:16`（类型定义）+ `pages/LibretroNewArchTestPage.ets:771-774`（mutate）+ `:1561-1563`（消费）

**证据链**：
- `RuntimeSoakTestController.ets:16` `export interface RuntimeSoakState { running...; secondsLeft...; summaryText...; }` —— **裸 interface，非 @ObservedV2**。
- `:187` `@Local soakState: RuntimeSoakState = { running: false, secondsLeft: 0, summaryText: '' };`
- `:771-774` `applySoakState()` **字段就地 mutate**：
  ```
  this.soakState.running = state.running;
  this.soakState.secondsLeft = state.secondsLeft;
  this.soakState.summaryText = state.summaryText;
  ```
  该方法是 soak 控制器每秒 tick 回调（`:760-768` start/stop 注册），即倒计时本应每秒驱动 UI。
- `:1561-1563` 传给 `DevDiagnosticsBlock` 的 `soakRunning/soakSecondsLeft/soakSummaryText` @Param。
- 子组件 `DevDiagnosticsBlock.ets:72-101` 据此显示 spinner、`压力测试中 ${soakSecondsLeft}s` 倒计时、summary。

**为何是真 bug**：同 A-Q1-1，@Local 浅追踪 + 字段就地 mutate → 父 build() 不重算 → 子组件 @Param 不更新。表现：点"压力测试"后按钮不进入运行态、`${soakSecondsLeft}s` 倒计时**完全不动**、10 分钟结束后 summary 不显示。P1。

**建议修法**：同 A-Q1-1（@ObservedV2+@Trace 改 `RuntimeSoakState` 为 class，或 `applySoakState` 改整体替换 `this.soakState = { ... }`）。

> 备注：本页是 dev-only 诊断页（`:3` 注释 "DEV DIAGNOSTIC ONLY，不注册到产品 main_pages.json"），不影响产品路由用户路径，故定 P1 不升 P0；但页面本身的诊断功能确实失效。

---

## Q2 — @Param 只读违规 + @Monitor 正确性

> 静态分析，未编译 / 未真机。

### 2a. @Param 只读违规 — **0 finding（迁移在此点干净）**

**扫描方法**：grep 全仓 181 个 @Param 声明拿字段名 + grep 全仓 `^\s*this\.\w+\s*(=|+=|-=|++|--)` 顶层字段赋值清单（约 400 行，已分页读全到底）。逐一交叉比对"赋值目标名 ∈ 该 struct 的 @Param 名"。

**结论**：所有"@Param 名被 `this.x=` 赋值"的疑似命中，经核验**全部是同名字段分属不同作用域**，无一是对自身 @Param 赋值：

| 疑似命中 | 真相 | 判定 |
|---|---|---|
| `LibraryDetailPage.ets:609 this.showExtendedDetails=` | `AnimatedDetailBody:64` 是 @Param（只读传递不赋值）；赋值发生在 `LibraryDetailPage:160 @Local private showExtendedDetails` | ✅ 父@Local / 子@Param 同名 |
| `LibraryGameSections.ets:12 this.games=` | 在 `class LibraryDataSource:8`（普通 class private 字段）；`struct:51 @Param games` 是另一个 | ✅ class 字段 ≠ struct @Param |
| `ImportEntryPage.ets:51 this.particleBoosted=` 等 | `ImportEntryPage:88-92` 全是 `@Local private`；`ImportEmptyStateHero` 的同名才是 @Param | ✅ |
| `LibraryDetailPage.ets:90 this.heroScale=` 等 | `:78-80 @Local private`；子 panel 用 @Param 接收 | ✅ |
| `LibraryPage` searchKeyword/searchBusy/selectedPlatform/highlightedRecentGameId/bottomLoaderActive 赋值 | 均为 LibraryPage 的 @Local（父持真状态）；LibrarySearchPanel/LibraryGameSections 的同名 @Param 是子组件接收端 | ✅ |
| `TestGambatte.ets:1255 this.coreCheckRunning=` | `:125 @Local`（独立页面）；DevDiagnosticsBlock 的同名才是 @Param | ✅ |
| SettingsPage/ShaderPreviewPage slider 子 struct 的 @Param value/min/max | 主页赋的是自己的 @Local（scanlineIntensity/masterVolume…），子 slider @Param 未被赋值 | ✅ |

> **反向佐证 A-Q1-1**：TestGambatte 用 `@Local coreCheckRunning: boolean`（基本类型）直接持有 + 就地赋值 → 正确刷新；LibretroNewArchTestPage 把同类状态包进 `CoreCheckState` interface 对象再就地改字段 → 就是 A-Q1-1 的静默 bug。同一语义两种写法，结果分野，印证 Q1 判断。

### 2b. @Monitor 正确性 — **0 finding（5/5 全部正确）**

| # | 位置 | 监控字段 | 装饰方法收 IMonitor? | 字段真实存在? | 依赖"初始化触发"? | 判定 |
|---|---|---|---|---|---|---|
| 1 | GameCard.ets:31 `@Monitor('isHighlighted')` | isHighlighted (@Param:15) | ✅ `onHighlightChanged(monitor: IMonitor)` | ✅ | 否——`aboutToAppear():23` 已显式 `syncScannerLoop()` 初始化 | ✅ |
| 2 | LibraryGameSections.ets:245 `@Monitor('games')` | games (@Param:51) | ✅ `onGamesChanged(monitor: IMonitor)` | ✅ | 否——`aboutToAppear():63` 已显式 `updateGames(this.games)` | ✅ |
| 3 | PlatformChipBar.ets:22 `@Monitor('selected')` | selected (@Param:6) | ✅ `onSelectedChange(monitor: IMonitor)` | ✅ | 否——纯滚动副作用，初始位置由 build 决定 | ✅ |
| 4 | LibraryPage.ets:56 `@Monitor('active')` (SpinnerLine) | active (@Param:52) | ✅ `onActiveChange(monitor: IMonitor)` | ✅ | 否——`aboutToAppear():72` 已显式 `syncSpinner()` | ✅ |
| 5 | RomManagerPage.ets:53 `@Monitor('active')` (SpinnerLine) | active (@Param:49) | ✅ `onActiveChange(monitor: IMonitor)` | ✅ | 否——`aboutToAppear():69` 已显式 `syncSpinner()` | ✅ |

**关键正确点**：5 处全部在 `aboutToAppear()` 显式做了首帧初始化，没有任何一处依赖"@Monitor 初始化时触发"（V2 @Monitor 仅在值变化时触发，不在初始化触发）。这正是迁移做对的地方——若漏掉 aboutToAppear 初始化会导致首帧状态错误，但本次没有。

---

## Q3 — 语法 / 结构完整性

> 静态分析，未编译 / 未真机。

### 扫描方法与结果

| 检测项 | 手段 | 结果 |
|---|---|---|
| `} {` 块拼接破坏（bf52592 类） | grep `\}\s*\{` 全仓 | **0 处** —— 该类破坏已不存在 |
| 花括号/圆括号平衡 | PowerShell 逐文件计数 `{}()` | 全仓唯一失衡 `common/LibraryDetailPresenter.ets`(parens 127/128) 经查是 `:212` 正则字面量 `/[\(\[]([^\)\]]+)[\)\]]/g` 的转义括号计数误差，**结构完整**，且该文件是纯函数模块、不在 V2 迁移范围 → 非 finding |
| @ComponentV2 缺 build() | grep 全部 @ComponentV2 / struct / build() 配对核对 | **0 处** —— 65 个 @ComponentV2 全部配对 build()（含 EmuAppShell×5 / VirtualController×5 / ImportTaskOverlayPage×4 / FoldableLayouts×3 / OnboardingPage×3 等多-struct 文件逐一点验） |
| 孤儿语句 / 残留（`,,` / 悬空 else / 孤立链式） | grep 复合可疑模式 | **0 处** |
| import 已删符号（编译失败级） | 5 高 churn 文件 import × 源模块导出核对 | **0 处**（见下 SingleModeLayout 分析：源符号仍在） |
| 未使用 import（孤儿 import） | PowerShell 统计 5 高 churn 文件具名 import 在正文出现次数 | **2 处（P3）**，见 A-Q3-1 |

> **结论**：本次迁移 + 06-08 B 档删除**没有引入任何编译失败级的结构残缺**。全仓括号平衡（唯一例外是正则字面量误差），无 `} {`，无 @ComponentV2 缺 build()。bf52592 那次 `} {` 破坏是孤立事件，已不复现。

---

### 🟡 A-Q3-1 [P3] LibretroGamePage 两个未使用 import（疑似 B 档删码残留）
**位置**：`pages/LibretroGamePage.ets:12` + `:66`

**证据**：
- `:12` `import { SingleModeLayout, DualModeLayout, TripleModeLayout } from '../components/FoldableLayouts';`
  正文仅用 `DualModeLayout`(:651) / `TripleModeLayout`(:666)，**`SingleModeLayout` 全文件 0 调用**。
- `:66` `import { runtimeRenderSettingsController } from '../common/RuntimeRenderSettingsController'`
  正文 0 引用（import 后再无出现）。

**为何不是 P1**：`FoldableLayouts.ets:13 export struct SingleModeLayout` **仍然存在**（源符号未删）→ 不是"import 已删符号"，编译器解析得到，**不会因符号缺失而失败**。`CoreManagerPage.ets:340/372` 的同名 `SingleModeLayout` 是该页私有 @Builder，与本 import 无关。

**严重度说明**：未使用 import 在标准 hvigor/ArkTS 配置下是 **warning，不阻断 build**；仅当显式开启严格未用检查（如 codelinter 对应规则置为 error）才会失败。鉴于本仓 `quick_signals.sh` 不编译 .ets（见 CLAUDE.md / memory `feedback_quick_signals_not_arkts_compile`），**建议 DevEco 实编一次确认本仓 codelinter 是否把未用 import 升级为 error**——若是则升 P1。静态层面定 **P3（死代码残留）**。

**建议修法**：从 `:12` import 列表移除 `SingleModeLayout`；删除 `:66` 整行 `runtimeRenderSettingsController` import。（不影响功能，纯清理。）

> 备注：本扫描仅覆盖 5 个高 churn 文件的孤儿 import。其余 86 文件未做同等深度的未用-import 扫描；若需全仓清零，建议交给 codelinter 跑一次 `--fix`。

---

## Summary

> 全部为静态分析，未编译 / 未真机。共 **3 个 finding（2×P1 + 1×P3）**。

| ID | 严重度 | file:line | 一句话 |
|---|---|---|---|
| A-Q1-1 | **P1** | pages/LibretroNewArchTestPage.ets:186 + :739-754 | `@Local coreCheck: CoreCheckState`(裸 interface)字段就地 mutate `this.coreCheck.running=`，V2 @Local 不深追踪 → 父 build 不重算 → 子组件 DevDiagnosticsBlock 的 @Param 永停初值 → "验证核心符号"按钮静默不刷新 |
| A-Q1-2 | **P1** | pages/LibretroNewArchTestPage.ets:187 + :771-774 | `@Local soakState: RuntimeSoakState`(裸 interface)字段就地 mutate `this.soakState.running=`，同理 → 压力测试倒计时/状态/summary 静默不刷新 |
| A-Q3-1 | P3 | pages/LibretroGamePage.ets:12 + :66 | 两个未使用 import（SingleModeLayout、runtimeRenderSettingsController），疑 B 档删码残留；源符号仍在故非编译失败，标准配置下仅 warning（需 DevEco 实编确认 codelinter 是否升 error） |

### 各问题硬结论
- **Q1（最高优先）**：**2 个 P1 静默 bug**，均在 dev-only 诊断页 `LibretroNewArchTestPage`，均为"对象包裹的状态用裸 interface + 字段就地 mutate"。修法二选一：① 类改 `@ObservedV2 class`+字段 `@Trace`（贴合迁移意图，对标 PerfDisplayState）；② mutate 改整体替换 `this.x={...}`（对标本页 audioStatus/stats，最小改动）。`audioStatus`/`stats` 虽同为裸 interface 但走整体替换 → 安全，不计 finding。产品主路径页 `LibretroGamePage` 的 `perfDisplay`(PerfDisplayState) 已正确用 @ObservedV2+@Trace。
- **Q2（@Param 只读违规）**：**无 finding**。全仓 181 个 @Param 交叉比对赋值清单，所有疑似命中都是"父@Local / 子@Param / 普通 class 字段"同名，无一对自身 @Param 赋值。迁移在此点干净。
- **Q2（@Monitor 正确性）**：**无 finding**。5/5 全部正确：装饰方法均收 IMonitor、监控字段名均真实存在、且 5 处全部在 `aboutToAppear()` 显式做了首帧初始化（不依赖"@Monitor 初始化不触发"的陷阱）。
- **Q3（结构完整性）**：**无编译失败级残缺**。`} {`=0、@ComponentV2 缺 build()=0、全仓括号平衡（唯一失衡是正则字面量误差）、孤儿语句=0。bf52592 的 `} {` 破坏已不复现。仅 2 处未使用 import（P3，见 A-Q3-1）。

### 验证盲区提示
- 本审计纯静态。A-Q1-1/A-Q1-2 的"静默不刷新"需真机点按"验证核心符号"/"压力测试"按钮确认（spinner 不出、倒计时不动 = 复现）。
- A-Q3-1 的严重度（P3 vs P1）取决于本仓 codelinter 对未用 import 的等级，需 DevEco/codelinter 实跑确认。
- 未用-import 全仓清零未做（仅 5 高 churn 文件），建议 codelinter `--fix` 兜底。
