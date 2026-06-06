# ArkTS/ArkUI 侧 UI 线程 jank 审计 — 游戏页卡顿/按键迟钝

> 调查日期: 2026-06-07
> 范围: **只读** ArkTS/ArkUI 前端侧。C++ 引擎侧由主 AI 另查,本文不涉及。
> 症状: 游戏中按键迟钝、界面卡顿(尤其在模拟器上)。
> 目标文件: `pages/LibretroGamePage.ets`(1239 行)、`components/RuntimeVirtualControllerLayer.ets`(493 行)、`components/VirtualController.ets`(371 行)。

工具说明: serena 仅配置 cpp LSP,无 ArkTS/ets language server(项目无该 LSP)→ ets 符号用 Read + Grep + ast-grep(CLAUDE.md 决策树允许 "LSP 不可用 fallback")。ArkUI 重渲染机制已 web-search 两轮联网核实(见末节)。

## 联网核实结论(先行,后续判决依此)

1. **V1 中给 `@State` 整体赋新对象 = reliable trigger**,必触发 owning component 的 `build()` 重执行。粒度 object-level(coarse)。
2. **但 `build()` 重执行 ≠ 整树重建**:ArkUI 用脏节点标记 + 细粒度依赖追踪,只更新真正依赖该 @State 的 UI 节点;子组件 @Prop 引用/值不变则**跳过 reconcile**。
3. 因此关键不在 "build() 被触发几次",而在 **(a) 触发频率 × (b) build() 函数体本身重执行成本 × (c) 是否有节点真正依赖该 @State**。
4. XComponent 是重组件,反复 reconcile/重建代价极高 → 必须只依赖稳定 @Prop。本项目 XComponent 的依赖项(`xComponentId` 常量、`gameAspectRatio`)稳定,**未发现 XComponent 被高频 reconcile**(见问 3)。

来源: developer.huawei.com 状态管理最佳实践、arkts-state-management-overview、infoq/腾讯云框架原理文(脏节点机制)、ts-basic-components-xcomponent。

---

## 问 1: 游戏运行时 UI 线程高频做了什么重活?

### 重大发现 — 1 个常驻 2Hz 的"空转 build()"负载(App 可修)

**`RuntimeInputDebugTracker` 调试定时器在游戏全程常驻,每 500ms 触发整页 `build()` 重执行,但产出无任何 UI 消费。**

- `LibretroGamePage.aboutToAppear()` L209 调 `this.startInputDebug()` → `RuntimeInputDebugTracker.start()`。
- `RuntimeInputDebugTracker.ets:60-62`: `setInterval(() => onChange(this.readState()), 500)` —— **无条件常驻,不随 gameRunning/gamePaused 暂停**,只在 `aboutToDisappear` 才 stop。
- 每个 500ms tick 做 3 件事(全在 UI 线程):
  1. `readState()` 调 NAPI 同步接口 `refactoredGetInputDebugStats()`(`RuntimeInputDebugTracker.ets:74`)——跨语言往返;
  2. 拼 3 个调试字符串;
  3. `onChange` → `LibretroGamePage.applyInputDebugTextState()`(`LibretroGamePage.ets:559-563`)**整体写 3 个 @State**:`inputDebugText` / `inputFocusText` / `uiInputDebugText`。
- 这 3 个 @State **在 `build()` 里完全没有被读取**(Grep 全文件:L560-562 是唯一写入点,build() 及所有 @Builder 无任何读取)→ 它们是**纯死状态**,但每次写入仍触发 `LibretroGamePage.build()`(1239 行 struct)函数体重执行。
- 净效果: 游戏全程 **2Hz 无意义的 NAPI 调用 + 3×setState + 整页 build() 重执行**,UI 上零产出。脏节点机制虽让 diff 后无节点更新,但 build() 函数体重执行(Stack/if-else 分支 + @Builder 调用判断)+ NAPI 往返,在低端机/模拟器累积即可见主线程占用。

**判决 1(主): 是,App 可修的 UI jank 源(轻-中度,常驻)。**
- 位置: `entry/src/main/ets/pages/LibretroGamePage.ets:209`(启动)+ `entry/src/main/ets/common/RuntimeInputDebugTracker.ets:60-62`(定时器)+ `LibretroGamePage.ets:135-137,559-563`(死 @State)。
- 修法方向(任一):
  1. **最优**: 该调试 tracker 仅 dev/debug 用,生产路径直接不启动(`startInputDebug` 加 debug-build 开关 / 去掉)。
  2. 次优: 把 3 个 `@State` 改为 `private`(非响应式)——若仍需值但不需渲染,立即消除 build() 触发;
  3. 若 debug 文本将来要显示,把它抽成独立子组件用局部 @State,别挂在 1239 行的页面级 struct 上。

### 1a. 引擎事件 handler 整体替换 `@State perfDisplay` 是否触发整页 build() 重渲染?

**触发 build() 重执行: 是;但稳态下基本是"低频空转",非显著 jank。**

- `handleFpsUpdate`(`LibretroGamePage.ets:478-484`)、`handleAudioStatus`(`511-517`)、`handleGeometryUpdate`(`527-533`)各自**整体替换 `this.perfDisplay`** 对象(注释明确写 "整体替换触发 @State 刷新,V1 不支持字段级 mutate 观测,ArkTS 禁对象 spread")。这是 V1 下的**正确写法**(对象 @State 只能整体换),不是反模式。
- 频率上限(C++ EventBridge 侧节流给定): fps ~2Hz、audio ~5Hz、geometry 稳态≈0(仅分辨率变化时发)。**ArkTS 侧 `LibretroEventHub` 自身无任何节流**(`LibretroEventHub.ets:361-395` `handleEvent` 收到即 dispatch)——节流全靠 C++ 侧。稳态合计 ≤7Hz 的 build() 重执行。
- `perfDisplay` 在 build() 里**只有 1 处直读**: `LibretroGamePage.ets:742` `TripleModeLayout({ fps: this.perfDisplay.coreFps })`(**仅三折态**)。**单折态(`SingleFoldLayout`,最常见竖屏手机)的 build() 完全不读 perfDisplay** → diff 后零节点更新,只是 build() 函数体空跑。
- 量级判断: ≤7Hz 的 build() 空跑,对比 C++ 60fps 画面渲染(XComponent surface,独立于 ArkUI 树),压力极小,**不是"按键迟钝"的量级**。

**判决 1a: 否(单折态)/ 轻微(三折态)。** 设计基本合理,不是症状根因。三折态因 fps @Prop 每 2Hz 变化会 reconcile TripleModeLayout,但 2Hz 可接受。无需改写,但可作为"锦上添花"与下方 hudMetricsCache 一起清理。

### 1b. build() 是否过重(>200 行 / 未拆 @Builder)?

**build() 本身已拆 @Builder,主体不过重;但页面 struct 总量偏大。**

- `build()` 主体(`LibretroGamePage.ets:716-853`)约 137 行,**已合理拆出** `@Builder SingleFoldLayout()` / `IdleEmptyState()`,dual/triple 走独立组件。主体含一个 `if/else if/else`(折叠态分支)+ MENU 按钮 + switching 进度浮层 + PauseOverlay + IdleEmptyState 的条件渲染。**符合 ets/CLAUDE.md "<200 行" 要求**。
- 隐患不在行数而在: 整个 `LibretroGamePage` struct 1239 行、**32 个 @State**(下条),任一 @State 变化都重执行这个大 build() 函数体。配合上面的 2Hz debug 定时器,放大了空转成本。

**判决 1b: 否(build 已拆 @Builder 达标)。** 不是独立 jank 源,但与"页面级 @State 过多 + 高频触发"叠加放大。

### 1c. LibretroGamePage 有多少 @State?是否有对象/数组 @State?

- **共 32 处 `@State`**(Grep count;含注释行,实际声明 ~24 个,集中在 `LibretroGamePage.ets:122-154`)。
- **对象 @State: 1 个** — `perfDisplay: PerfDisplayState`(L134)。整体替换写法正确(见 1a),非反模式。
- **数组 @State: 0 个**。注意 `portAssignments: PortAssignState[]`(L133)、`runtimeInputLayoutButtons: InputLayoutButton[]`(L151)、`hudMetricsCache: RuntimeHudMetric[]`(L182)等数组**都是 `private`(非 @State)**——这是**正确的、已优化过的**(ets/CLAUDE.md 历史修复日志印证)。
- **死 @State: 3 个** — `inputDebugText`/`inputFocusText`/`uiInputDebugText`(见问 1 主发现,build 不读却被 2Hz 写)。
- **附带死代码**: `hudMetricsCache` + `refreshHudMetricsCache()`(`LibretroGamePage.ets:682-690`)——`refreshHudMetricsCache()` 在 `handleEngineState`/`handleFpsUpdate`/`startOrSwitchGame` 多处被调用(每次 fps 更新都跑),但其唯一 getter `getRuntimeHudMetrics()` **在 build() 里无人调用**(Grep 确认)→ **死代码,每次 fps 事件白算 3 个字符串**。轻微浪费,建议删。

**判决 1c: 对象 @State 写法正确不致命;真问题是 3 个死 @State 被 2Hz 写(并入判决 1 主)+ hudMetricsCache 死代码。**

---

## 问 2: 虚拟手柄/HUD overlay 是否高频重绘?@State 反模式残留?ForEach keyGenerator?

**判决 2: 否。虚拟手柄/HUD 设计良好,无高频重绘、无 @State 反模式、ForEach 均有 keyGenerator。这不是卡顿源。**

### 2a. Canvas/ForEach/scanline/grid 高频重绘
- `RuntimeVirtualControllerLayer.ets`: **无 scanline/grid/Canvas/setInterval/常驻动画**(ets/CLAUDE.md 记录的 160-Row scanline 已于 2026-05-11 迁走,核实属实——全文件无 `createIndexRange`/`ScanlineBackground` 残留)。
- 唯一动画是 `RuntimeKeyButton` 的 `.animation({duration: EmuMotion.stateChangeMs=200ms})`(`RuntimeVirtualControllerLayer.ets:88-91`)——**状态驱动的按下过渡**,仅按下/松开瞬间触发,非常驻。
- `FoldableLayouts.ets`(dual/triple 布局): Grep 确认**无 setInterval/animateTo/animation/ForEach/scanline/grid/@State**,干净。
- `RuntimePauseOverlay` / `RuntimeTopHudBar`: 无 setInterval/animateTo;且 PauseOverlay 仅 `gamePaused` 时渲染、IdleEmptyState 仅未运行时渲染——**游戏运行中都不在树上**,不抢 UI。

### 2b. @State 反模式残留(对照 ets/CLAUDE.md)
- 按钮状态设计**正确**: 每个 `RuntimeKeyButton` 是独立 `@Component`,自持 `@State pressed`(`RuntimeVirtualControllerLayer.ets:20`)→ 按下只重渲染该单个按钮(局部刷新),不波及兄弟键或父页面。
- D-pad 用 **4 个独立 boolean @State**(`dpadUpPressed` 等,L125-129)而非 object,注释明确 "确保单字段变更触发 re-render"——**刻意避开了对象 @State 反模式**。
- `RuntimeKeyButton` 的 `@Prop button: InputLayoutButton`(对象): 父层 ForEach 传入,但 `buttons` 源数组(`runtimeInputLayoutButtons`)是 private 引用稳定 → @Prop 浅比较跳过,无冗余刷新。

### 2c. ForEach keyGenerator
- `RuntimeVirtualControllerLayer.ets:176` 与 `:237` 两处 ForEach **均有 keyGenerator** `(button) => button.id`。✓
- 与 ets/CLAUDE.md "46 ForEach 全有 keyGenerator" 记录一致。

---

## 问 3: XComponent 容器 + 持续动画是否在游戏页常驻抢 UI 线程?

**判决 3: XComponent 稳定无高频 reconcile(好);持续动画方面——唯一常驻负载是问 1 的 debug `setInterval(500ms)`(已在问 1 定性,App 可修)。无 animateTo/粒子/呼吸灯常驻。**

- **XComponent**(`LibretroGamePage.ets:907-941`,单折态): 依赖项 `id=xComponentId`(常量 string)、`.aspectRatio(gameAspectRatio)`。`gameAspectRatio` 仅在分辨率变化时更新(`handleGeometryUpdate` L537 有 `Math.abs(ratio - this.gameAspectRatio) > 0.005` 守卫,稳态不写)→ **XComponent 节点稳定,不被高频 reconcile/重建**。符合官方 "XComponent 只依赖稳定 @Prop" 要求。✓
  - 注: 外层 `Stack.layoutWeight`(L944)依赖 `gameRunning/gamePaused/hideVirtualController`,仅状态切换时变,非高频。
- **持续动画/定时器盘点**(游戏运行期间常驻在树上的):
  - `setInterval`: 仅 `RuntimeInputDebugTracker` 500ms 一处(问 1 主发现)。全 ets 无其他游戏页常驻 setInterval。
  - `animateTo` / 呼吸灯 / 粒子: 游戏页**无**(animateTo 全仓未在本页路径出现;`.animation()` 仅状态驱动按键过渡)。
  - `build()` 的 `.onAreaChange`(L843-852): 布局尺寸变化才触发 `detectFoldMode`,稳态不变,非高频。
- **回调引用稳定性核实**(防"箭头函数破坏 @Prop 跳过"): `LibretroGamePage.ets:950-961` 给 `RuntimeVirtualControllerLayer` 传的 `onButtonChange`/`onAnalogChange` 是每次 build 新建的箭头函数,但它们是**普通回调属性(非 @Prop/@State 装饰)**,ArkUI 不对其做 diff 触发;真正的 @Prop(`buttons` 引用稳定、`inputDescriptorMask` number、`layoutWidth/Height` const)在 perfDisplay/debug 刷新时均不变 → 虚拟手柄子树**会被正确跳过 reconcile**。✓

---

## 按键迟钝路径专项(诚实定位)

ArkTS 侧按键路径: `RuntimeKeyButton.onTouch(Down)`(`RuntimeVirtualControllerLayer.ets:94-105`)→ 本地 `pressed=true` + `onPressChange(true)` → 冒泡 `LibretroGamePage.setButton()`(L972)→ `sendRuntimeButton()` → NAPI `refactoredSendInput`(**同步直达,无 await / 无节流 / 无排队**)。

- **ArkTS 侧输入链路本身干净**: 同步直达 NAPI,不引入逻辑延迟;按键 @State 局部化(每按钮独立),不会被 perfDisplay/debug 刷新阻塞。
- 唯一"手感"项: `RuntimeKeyButton` 的 200ms 按下过渡动画(`EmuMotion.stateChangeMs`)——视觉反馈偏软,但不阻塞输入逻辑(onPressChange 先于动画同步触发)。**非逻辑迟钝**,如嫌手感软可调小到 ~80-120ms。
- **结论**: "按键迟钝" 的根因**大概率在 C++ 侧**(input_poll/input_state 时序、GameLoop 与渲染争用、或音频 underrun 拖累帧 pacing)——属主 AI 调查域。**ArkTS 输入路径未发现引入或放大迟钝的结构性 bug。** 但上面 2Hz debug 空转会周期性占用 UI 线程,在低端机/模拟器上可能让 touch 事件分发/动画偶发抖动——清理后对整体跟手度有正面帮助。

---

## 总结: UI 侧 App 可修卡顿源(按收益排序)

| # | 发现 | 严重度 | file:line | 修法 |
|---|------|--------|-----------|------|
| **1** | **debug `setInterval(500ms)` 常驻**: 每 500ms NAPI 往返 + 3×setState(死 @State,build 不读)+ 整页 build() 空转。游戏全程不停。 | **中(唯一常驻负载,模拟器累积可见)** | `LibretroGamePage.ets:209` + `RuntimeInputDebugTracker.ets:60-62` + `LibretroGamePage.ets:135-137,559-563` | 生产路径不启动该 tracker(debug 开关);或 3 个 @State 改 private | 
| 2 | `hudMetricsCache` 死代码: `refreshHudMetricsCache()` 每次 fps 事件(~2Hz)白算,getter 无人调用 | 低(轻微浪费) | `LibretroGamePage.ets:682-690` + 各调用点 | 删除 cache + 所有 `refreshHudMetricsCache()` 调用 |
| 3 | 三折态 `perfDisplay.coreFps` 每 2Hz reconcile TripleModeLayout | 极低(仅三折态,2Hz 可接受) | `LibretroGamePage.ets:742` | 可选: fps 单独拆 number @State,或忽略 |
| 4 | 按键过渡动画 200ms 偏软(手感,非逻辑) | 极低(体验) | `RuntimeVirtualControllerLayer.ets:89` / `EmuUiTokens` stateChangeMs | 可选: 调到 80-120ms 提升跟手感 |

**底线回答**: ArkTS/ArkUI 侧确实**存在 1 个 App 可修的常驻卡顿源**(#1 debug 定时器空转),量级为"中-轻"(模拟器/低端机累积可见,旗舰机几乎无感)。其余皆设计良好或轻微浪费。**"按键迟钝" 的主因不在 ArkTS 输入路径(该路径同步干净),更可能在 C++ 侧** —— 但清理 #1 能减少 UI 线程周期性占用,对整体跟手度有正面边际改善。诚实结论: UI 侧不是卡顿的"主战场",但 #1 值得修(低风险、纯删/降级,无功能影响)。
