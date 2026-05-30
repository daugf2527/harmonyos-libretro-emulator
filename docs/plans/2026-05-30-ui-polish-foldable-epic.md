# UI Polish & 折叠屏适配 Epic (B)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 收口 2026-05-04 静态扫描剩余高风险项 + 把 `FoldableLayouts.ets` 接入 LibraryPage / LibretroGamePage 主流程,完成 Roadmap.md M7(折叠屏交互)。

**Architecture:** 不做全仓重构。B1 按 5-04 报告定点修复 3 个高风险项;B2 把 FoldableLayouts 三折态组件接入 LibraryPage(双折态左右分栏)和 LibretroGamePage(单/双/三折态切换);B3 visual regression sweep 确认主流程页面在小窗口/横竖屏/折叠态下无遮挡/溢出。

**Tech Stack:** HarmonyOS ArkTS / ArkUI,`FoldableLayouts.ets` 已有 SingleModeLayout / DualModeLayout / TripleModeLayout 三个组件,`display` API 查询折叠态。

---

## 执行边界

- 默认中文沟通。
- 不主动编译、不真机、不跑测试脚本;用户自己做运行态验证(但 B3 需要用户提供小窗口/横竖屏/折叠态截图反馈)。
- 不处理 `deprecated/legacy/`。
- 不使用 `git add .`;提交前只显式 stage 本轮相关文件。
- 每个 task 完成后 `git diff --check` 验证无 trailing whitespace。

## Task B1: 收口 5-04 静态扫描高风险项

**Files:**
- Modify: `entry/src/main/ets/pages/InputLayoutPage.ets`
- Modify: `entry/src/main/ets/components/VirtualController.ets`
- Modify: `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
- Modify: `docs/2026-05-04-arkts-ui-static-scan.md`

**Scope:**

按 5-04 报告"重点复查清单"第 2/3/4 项:

1. **InputLayoutPage.ets** — `EditableButton()` 的 `.position()` 业务坐标
   - 当前:外层已有 `aspectRatio`,内层用百分比换算
   - 风险:触控热区、横竖屏缩放
   - 改法:保留 `.position()` 业务坐标,但在 `EditableButton` 加 `.hitTestBehavior(HitTestMode.Default)` 确保触控命中;在 `onAreaChange` 回调中 log 实际渲染尺寸,方便真机调试

2. **VirtualController.ets** — 摇杆 knob / ABXY 方位 `.position()` + `.translate()`
   - 当前:控件内部逻辑坐标
   - 风险:该组件命名像通用旧虚拟手柄,不确定是否仍在主流程
   - 改法:先 `rg "VirtualController" entry/src/main/ets/pages` 确认引用;若只在 `FoldableLayouts.ets` / 测试页,标记"仅供 FoldableLayouts 使用";若在 `LibretroGamePage` / `RuntimeVirtualControllerLayer`,保留并在注释说明"控件内部坐标,外层由 Stack 对齐"

3. **RuntimeVirtualControllerLayer.ets** — Movement / Action / Quick Save / Select Start 固定尺寸
   - 当前:Quick Save rail 已移除固定 `top: 164`,改 `.align(Alignment.End)`
   - 风险:右侧居中位置在横竖屏/小窗口下与底部 Select/Start 间距
   - 改法:给 Quick Save rail 外层 Stack 加 `.margin({ bottom: 80 })` 确保与底部 Select/Start 区域留白;Movement / Action 保留固定尺寸(触控 token)

**Acceptance:**
- 3 个高风险项全部有明确改法或保留理由
- `docs/2026-05-04-arkts-ui-static-scan.md` 追加"B1 收口记录"段,记录改动和剩余真机验证项
- `git diff --check` 无输出

## Task B2: FoldableLayouts 接入主流程

**Files:**
- Modify: `entry/src/main/ets/pages/LibraryPage.ets`
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`
- Modify: `entry/src/main/ets/components/FoldableLayouts.ets`
- Maybe create: `entry/src/main/ets/common/FoldableStateDetector.ets`

**Scope:**

1. **LibraryPage 双折态左右分栏**
   - 单折态(默认):当前 Column 布局不变
   - 双折态:左侧 40% 显示 PlatformChipBar + RecentGames,右侧 60% 显示 AllGames grid
   - 三折态:暂不处理(留后续 epic)
   - 实现:
     - 用 `display.getDefaultDisplaySync().foldStatus` 查询折叠态
     - 双折态时用 `Row` 替代 `Column`,左右两个 `Column` 分栏
     - 保持现有 `LibraryGameSections` / `GameCard` 组件不变

2. **LibretroGamePage 单/双/三折态切换**
   - 单折态:用 `FoldableLayouts.ets` 的 `SingleModeLayout`(游戏画面 + 下方虚拟手柄)
   - 双折态:用 `DualModeLayout`(左侧游戏画面,右侧虚拟手柄)
   - 三折态:用 `TripleModeLayout`(中间游戏画面,左右两侧虚拟手柄 + 系统控制)
   - 实现:
     - 在 `aboutToAppear` 查询 `foldStatus`,存到 `@State currentFoldMode: string`
     - 监听 `display.on('foldStatusChange')`,动态切换布局
     - 把现有 `RuntimeVirtualControllerLayer` 的虚拟手柄逻辑迁移到 `FoldableLayouts` 的三个 Layout 组件
     - 保持 XComponent / engine 交互不变

3. **FoldableLayouts.ets 补全**
   - `DualModeLayout` / `TripleModeLayout` 当前只有骨架,需要补全:
     - 接受 `xComponentId` / `screenAspectRatio` / `onKeyPress` / `onReset` / `onStop` props
     - 内部用 `DPadControl` / `ABXYControl` / `StartSelectControl` / `SystemControl`(从 VirtualController.ets import)
     - 布局按华为折叠屏适配指南:双折态左右 5:3,三折态中间 4:3 左右各 2:3

**Acceptance:**
- LibraryPage 在双折态下左右分栏显示
- LibretroGamePage 在单/双/三折态下自动切换布局
- `FoldableLayouts.ets` 三个组件全部可用
- 不破坏现有单折态(默认)体验

## Task B3: Visual Regression Sweep

**Files:**
- Read: 用户提供的小窗口/横竖屏/折叠态截图
- Modify: 按截图反馈定点修复遮挡/溢出/间距问题
- Modify: `docs/2026-05-04-arkts-ui-static-scan.md` 追加"B3 真机验证记录"

**Scope:**

用户需要提供以下场景截图(每个场景 1-2 张代表页面):
1. 小窗口(宽度 < 600vp)— LibraryPage / SettingsPage
2. 横屏 — LibretroGamePage / LibraryDetailPage
3. 双折态 — LibraryPage / LibretroGamePage
4. 三折态 — LibretroGamePage

Claude 按截图反馈:
- 遮挡:文字被控件盖住 → 调整 z-index / margin
- 溢出:内容超出容器 → 加 `.constraintSize()` / 改 layoutWeight
- 间距:控件贴边/重叠 → 调整 margin / padding
- 断点:某个尺寸下布局崩溃 → 加 breakpoint 或 `@ohos.mediaquery`

每个修复:
- 只改最小范围(单个组件/页面)
- 不引入新 `.position()` 固定坐标
- 修复后在 `docs/2026-05-04-arkts-ui-static-scan.md` 记录"B3-FIX-N: <页面> <问题> → <改法>"

**Acceptance:**
- 用户确认主流程页面在 4 个场景下无明显遮挡/溢出
- 不要求像素级完美,只要求"可用、不挡字、不越界"
- B3 是迭代式任务:用户提供截图 → Claude 修复 → 用户验证 → 循环直到可接受

## 不做事项

- 不新增测试文件
- 不跑 `hvigorw`(用户自己编译)
- 不真机(用户提供截图)
- 不提交 Git(除非用户明确要求)
- 不处理 `_12` menu / `_7` 虚拟手柄完整视觉重构 / `_9` 暂停页扩展能力(留后续 epic)
- 不处理多 core 切换 UI / Input Mapper(留 epic C/D)

## Done Criteria

- [ ] B1: 3 个高风险项全部有改法或保留理由 + 5-04 报告追加"B1 收口记录"
- [ ] B2: LibraryPage 双折态左右分栏 + LibretroGamePage 单/双/三折态切换 + FoldableLayouts 三个组件可用
- [ ] B3: 用户确认主流程页面在小窗口/横竖屏/双折态/三折态下可用(不挡字、不越界)
- [ ] `git diff --check` 全程无 trailing whitespace
- [ ] `bash scripts/check/quick_signals.sh` ALL PASS(commit 前跑)

## 推荐执行顺序

1. B1(定点修复,1-2 commits)
2. B2(FoldableLayouts 接入,2-3 commits)
3. B3(迭代式,用户提供截图后再做,N commits)

B3 是开放式任务,可能需要多轮;B1/B2 是确定性任务,可以先做完。

---

**Plan approved by:** (待用户 review)
**Kickoff date:** (用户批准后填)
**Target completion:** 无固定 deadline,按"节奏自定但要主线"原则推进
