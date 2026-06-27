# ArkTS UI 固定布局静态扫描

> 日期：2026-05-04
> 范围：`entry/src/main/ets/pages` 与 `entry/src/main/ets/components`，排除 `deprecated/legacy`。
> 边界：本报告只记录静态扫描快照，不代表编译通过、预览通过或真机通过。本轮未编译、未真机验证。

## 扫描命令

```powershell
rg -n "\.position\(|\.markAnchor\(|\.translate\(|\.offset\(|\.width\('[0-9]+vp'\)|\.height\('[0-9]+vp'\)|\.width\([0-9]{2,}\)|\.height\([0-9]{2,}\)" entry/src/main/ets/pages entry/src/main/ets/components -g "*.ets" -g "!deprecated/**" -g "!legacy/**"
```

## 当前命中概览

本轮命中不是统一缺陷。按 AGENTS 口径，需要区分 token 级固定尺寸、业务逻辑坐标和截图补丁式风险：

| 分类 | 代表命中 | 当前判断 | 后续处理 |
| --- | --- | --- | --- |
| 允许的 token 尺寸 | `AboutHelpPage.ets`、`CoreManagerPage.ets`、`LibraryDetailPage.ets`、`SettingsPage.ets` 中的图标、按钮、分割条、telemetry 柱状条高度 | 多数属于图标尺寸、按钮高度、状态块高度或视觉 token；不直接判错。 | 只在真机出现溢出、遮挡或断点问题时再复查。 |
| 弹层 / 卡片内部尺寸 | `ImportTaskOverlayPage.ets`、`LibraryContextMenuOverlay.ets`、`LibraryLaunchOverlay.ets`、`RuntimePauseOverlay.ets` | 多数是弹层按钮、slot、缩略图、操作行高度；属于固定格式 UI 内部尺寸。 | 保留，但后续验收要看小窗口和横竖屏是否被固定高度挤压。 |
| 业务热区 / 逻辑坐标 | `InputLayoutPage.ets:598`、`VirtualController.ets:145/225/232/239/246`、`RuntimeVirtualControllerLayer.ets` | 输入布局和虚拟手柄有业务坐标语义；其中 `InputLayoutPage` 外层已有 `aspectRatio(this.editorLayoutWidth / this.editorLayoutHeight)`，定位来自布局 profile 百分比换算。 | 可接受为业务热区，但需要真机验证触控命中和横竖屏缩放。 |
| 装饰动效 / 滑动状态 | `EmuCoverArt.ets`、`GameCard.ets`、`OnboardingPage.ets`、`LibraryDetailInfoPanel.ets`、`SaveStatePage.ets` | `.translate()` 多数用于 cover 偏移、扫描线、按钮按压、滑动露出或 telemetry 动效，不是页面主结构定位。 | 保留静态记录；若后续出现文本遮挡或动效越界，再按组件逐项调整。 |
| 已复查的截图补丁风险 | `ImportEntryPage.ets:199` 的粒子 `.position()`、`RuntimeVirtualControllerLayer.ets:206/207` 的 Quick Save rail 固定宽高、`ShaderPreviewPage.ets` 的 GPU stats overlay 宽度 | `ImportEntryPage` 粒子为背景装饰层；Quick Save rail 已移除固定 `top: 164`；Shader stats overlay 已从 `.width(250)` 改为百分比宽度加最大宽度约束。 | 保留静态记录；仍需用户真机/编译确认小窗口、横竖屏、触控命中和遮挡。 |
| 历史 / 测试页命中 | `CoreLoaderTest.ets`、`TestGambatte.ets`、`Index.ets`、`FoldableLayouts.ets` | 命中来自测试入口、开发入口或旧演示式组件；本轮计划不处理。 | 若要 native ETS only 收口，后续单独决定是否清理或下线入口。 |

## 重点复查清单

1. `entry/src/main/ets/pages/ImportEntryPage.ets`
   - `ParticleOverlay()` 使用 `.position({ x, y })` 放置装饰粒子。
   - 当前判断：装饰层命中，风险低于主结构固定坐标；但需要确认粒子不会在小窗口盖住 CTA 或正文。

2. `entry/src/main/ets/pages/InputLayoutPage.ets`
   - `EditableButton()` 使用 `.position({ x: this.getEditorPercentX(button.x), y: this.getEditorPercentY(button.y) })`。
   - 当前判断：这是输入布局编辑器的业务坐标，不是截图补偿；外层用 `aspectRatio` 承载逻辑画布。
   - 剩余风险：触控热区、保存后的 runtime 使用、横竖屏缩放仍需真机验证。

3. `entry/src/main/ets/components/VirtualController.ets`
   - 摇杆 knob 和 ABXY 方位使用 `.position()` + `.translate()`。
   - 当前判断：属于控件内部逻辑坐标；但该组件命名上仍像通用旧虚拟手柄，需要后续确认是否仍在主流程使用。

4. `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
   - Movement / Action / Quick Save / Select Start 多处固定尺寸。
   - 当前判断：多数是固定格式手柄控件尺寸；`Quick Save` rail 的 `57 x 157` 保留为竖向触控 token，固定 `top: 164` 已移除，改由 Stack 右侧对齐承载。

5. `entry/src/main/ets/pages/SaveStatePage.ets`
   - `translate({ x: item.isActive ? -184 : 0 })` 用于滑动露出操作区。
   - 当前判断：这是交互状态偏移，不是主结构布局；后续验收需看长文件名和 action 宽度。

## 复查记录

### 2026-05-04 UI 静态收口

- `docs/2026-04-30-design-page-acceptance-matrix.md`
  - 已把 `docs/verification/runtime-screenshots-2026-05-04/README.md` 中 11 张 2026-05-04 截图 evidence 回写到 `_2`、`_4`、`_12`、`_13`、`_14`、`_15` 的矩阵行。
  - 未改变 `已完成` 列；截图只作为可见状态 evidence，不升级为运行态完成。

- `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
  - `buildQuickSaveRail()` 保留 `.width(57)` / `.height(157)` 作为竖向即时存档触控 token。
  - 已移除 `.margin({ right: 22, top: 164 })` 中依赖单张截图的固定 `top` 补偿，改为 `.align(Alignment.End)` + `.margin({ right: 22 })`。
  - 未改变 `onQuickSave` 回调；剩余风险是右侧居中位置在真机横竖屏、小窗口和底部 Select/Start 区域间距仍需用户验证。

- `entry/src/main/ets/pages/ImportEntryPage.ets`
  - `ParticleOverlay()` 的 `.position()` 命中保留。
  - 复查结论：粒子只绘制 2vp 装饰点，主 CTA、标题、说明、进度和底部导航均由 `Column` / `Stack` 自适应承载，不靠粒子定位撑开页面结构。
  - 剩余风险是粒子动效强度和极小窗口下是否干扰视觉层级，需真机/预览确认。

- `entry/src/main/ets/pages/ShaderPreviewPage.ets`
  - `PreviewStatsOverlay()` 原 `.width(250)` 为浮层面板固定宽度，已改为 `.width('72%')` + `.constraintSize({ maxWidth: 250 })`。
  - 保留 `maxWidth: 250` 作为面板上限 token，避免宽屏过宽；小窗口下由父容器百分比收缩。
  - 剩余风险是 `GPU LOAD / NOT_CONFIGURED` 与 `LATENCY / PREVIEW_ONLY` 在更窄窗口下的换行/截断，需要真机或预览确认。

### 2026-05-30 B1 收口记录(epic B Task 1)

按 `docs/plans/2026-05-30-ui-polish-foldable-epic.md` Task B1 落地:

- `entry/src/main/ets/pages/InputLayoutPage.ets:674-679`
  - 在 `@Builder private EditableButton(button, isSelected)` 上方追加注释,说明 `.position(getEditorPercentX/Y)` 是业务坐标(布局 profile 百分比换算),外层 `EditableButtonLayer` 已用 `aspectRatio` 承载逻辑画布。
  - 不改代码逻辑,只标注剩余真机验证项:触控热区精度、保存后 runtime 使用一致性、横竖屏缩放命中。

- `entry/src/main/ets/components/VirtualController.ets:1-13`
  - 文件头部 docstring 追加用途说明:供 `FoldableLayouts.ets` 的 SingleModeLayout / DualModeLayout / TripleModeLayout 使用,**不直接在 LibretroGamePage 主流程使用**(主流程用 `RuntimeVirtualControllerLayer`)。
  - 标注 `.position()` + `.translate()` 是控件内部坐标,外层由 Stack 对齐,不是截图补丁式固定坐标。

- `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
  - 5-04 报告原计划修复的 `Quick Save rail` 固定 `top: 164` margin 在本次 grep 中**未找到任何匹配**(`buildQuickSaveRail` / `Quick Save` / `quickSave` / `.width(57)` / `.height(157)` 全无命中)。
  - 推断:已在历史 commit 中移除或重构,无需本轮再修。该文件当前主结构是 dpad bbox + floating function buttons,坐标全部来自 `InputLayoutButton` 业务数据,不是截图补丁。

### B1 剩余风险

- `InputLayoutPage` 编辑器画布在小窗口(<600vp)下的触控命中精度需要真机验证。
- `VirtualController` 仅供 FoldableLayouts 使用,接入主流程后(epic B Task 2)需要再次扫描固定坐标是否在折叠态下正常。
- 5-04 报告其他保留命中(图标尺寸 / 按钮高度 / telemetry 柱状条)按 token 处理,不在 B1 范围。



- 复扫命中仍较多，主要集中在图标、按钮、telemetry 条、虚拟手柄、弹层内部控件和状态动效。
- 本轮明确消除的高风险项：
  - `RuntimeVirtualControllerLayer.ets` 不再存在 Quick Save rail 的固定 `top: 164` margin。
  - `ShaderPreviewPage.ets` 不再存在 GPU stats overlay 的 `.width(250)`。
- 本轮保留并解释的命中：
  - `ImportEntryPage.ets:199` 粒子 `.position()`：背景装饰层，不参与主结构布局。
  - `RuntimeVirtualControllerLayer.ets:206/207` 的 `.width(57)` / `.height(157)`：竖向触控控件 token。
  - `InputLayoutPage.ets` 和 `VirtualController.ets` 的 `.position()`：业务热区/控件内部逻辑坐标，仍需真机验证触控和缩放。

## 结论

- 扫描已建立静态 evidence：命中多，但大部分是 token 尺寸、控件内尺寸、业务热区或状态动效。
- 本轮已做 ArkTS 定点静态收口和文档回写，但不能据此宣布运行态完成。
- 本轮未编译、未预览、未真机验证；最终显示、交互命中和横竖屏稳定性仍以用户运行态验证为准。
