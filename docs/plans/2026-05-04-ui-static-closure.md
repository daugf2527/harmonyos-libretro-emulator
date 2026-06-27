# UI Static Closure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 基于 2026-05-04 截图索引和 ArkTS 固定布局扫描，按低上下文、可中断的方式推进 UI 静态收口。

**Architecture:** 不做全仓重构，不编译、不真机、不跑测试脚本。每个任务只围绕一个页面或一个组件，先读 `screen.png + code.html + 当前 ETS`，再做最小改动，最后用固定布局扫描和 `git diff --check` 记录静态证据。

**Tech Stack:** HarmonyOS ArkTS / ArkUI，PowerShell，`rg`，`git diff --check`。

---

## 执行边界

- 默认中文沟通。
- 不主动编译、不真机、不跑测试脚本；用户自己做运行态验证。
- 不处理 `deprecated/legacy/`。
- 不使用 `git add .`；提交前只显式 stage 本轮相关文件。
- 当前工作区已有两个 ETS 修改和多个未跟踪目录，执行前必须先 `git status --short` 重新确认。
- 若用户只要求规划，不执行代码；若用户说“继续执行”，按下面任务顺序推进。

## 参考入口

- 截图索引：`docs/verification/runtime-screenshots-2026-05-04/README.md`
- 静态扫描报告：`docs/2026-05-04-arkts-ui-static-scan.md`
- 设计矩阵：`docs/2026-04-30-design-page-acceptance-matrix.md`
- 设计目录：`docs/design/stitch-game-emulator-plan/_1` 到 `_15`

## Task 1: 回写截图验收到设计矩阵

**Files:**
- Modify: `docs/2026-04-30-design-page-acceptance-matrix.md`
- Read: `docs/verification/runtime-screenshots-2026-05-04/README.md`

**Step 1: 重新核对截图索引**

Run:

```powershell
Get-Content -LiteralPath .\截图验证\README.md
```

Expected:

- 11 张截图均有页面 / 状态 / 设计目录 / 验收用途。
- 不修改截图文件。

**Step 2: 精读矩阵相关行**

Read only these design rows:

- `_2 Multiplayer Input`
- `_4 Settings`
- `_12 Library Home`
- `_13 Import Entry`
- `_14 Import Task Overlay`
- `_15 Onboarding`

Expected:

- 明确截图只补充 2026-05-04 运行态 evidence，不把矩阵状态升级成“运行态完成”。

**Step 3: 更新矩阵证据描述**

Minimal edit:

- 在相关行的 `下一步` 或 `运行态缺口` 中补充“已有 2026-05-04 截图索引，仍需用户真机 / 编译验证”。
- 不改变 `已完成` 列，除非用户明确要求重新评级。

**Step 4: 验证**

Run:

```powershell
git diff --check
git diff -- docs/2026-04-30-design-page-acceptance-matrix.md
```

Expected:

- `git diff --check` 无输出，退出码 0。
- diff 只包含矩阵证据补充，不混入代码。

## Task 2: 复查 `ImportEntryPage` 粒子定位

**Files:**
- Read: `docs/design/stitch-game-emulator-plan/_13/screen.png`
- Read: `docs/design/stitch-game-emulator-plan/_13/code.html`
- Modify: `entry/src/main/ets/pages/ImportEntryPage.ets`
- Maybe modify: `entry/src/main/ets/components/ImportEmptyStateHero.ets`

**Step 1: 定位当前命中**

Run:

```powershell
rg -n "ParticleOverlay|position\(|particles|ImportEmptyStateHero" entry/src/main/ets/pages/ImportEntryPage.ets entry/src/main/ets/components/ImportEmptyStateHero.ets
```

Expected:

- 找到 `ParticleOverlay()` 的 `.position()`。
- 确认主结构不是由粒子定位撑开。

**Step 2: 判断是否需要改**

If particle layer only decorates background and does not affect CTA/text:

- 不改代码，只在 `docs/2026-05-04-arkts-ui-static-scan.md` 追加“复查结论”。

If particle layer can cover text/CTA or uses fixed design coordinates:

- 把粒子容器限制为背景装饰层。
- 保持 `ImportEmptyStateHero` 由 `Column/Stack` 自适应承载。

**Step 3: 验证**

Run:

```powershell
rg -n "ParticleOverlay|position\(" entry/src/main/ets/pages/ImportEntryPage.ets
git diff --check
```

Expected:

- 若未改代码，报告中记录结论。
- 若改代码，主结构仍无截图补丁式 fixed top/left。

## Task 3: 复查 `RuntimeVirtualControllerLayer` Quick Save rail

**Files:**
- Read: `docs/design/stitch-game-emulator-plan/_7/screen.png`
- Read: `docs/design/stitch-game-emulator-plan/_7/code.html`
- Modify: `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
- Maybe modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Step 1: 定位 Quick Save rail**

Run:

```powershell
rg -n "QuickSave|quickSave|buildQuickSaveRail|margin\(|width\(57\)|height\(157\)" entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets entry/src/main/ets/pages/LibretroGamePage.ets
```

Expected:

- 找到 `.width(57)`、`.height(157)` 和 `.margin({ right: 22, top: 164 })`。

**Step 2: 最小改造策略**

Preferred implementation:

- 保留 rail 的固定触控宽高作为控件 token。
- 移除依赖单张截图的固定 `top: 164`，改成由外层 `Stack` 对齐和底部 / 顶部相对 spacing 控制。
- 不改变 `onQuickSave` 行为。

**Step 3: 静态验证**

Run:

```powershell
rg -n "buildQuickSaveRail|margin\(|align\(" entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets
git diff --check
```

Expected:

- Quick Save rail 不再靠固定 top margin 硬贴截图。
- 不引入新 `.position()`。

## Task 4: 复查 `ShaderPreviewPage` 固定宽度

**Files:**
- Read: `docs/design/stitch-game-emulator-plan/_3/screen.png`
- Read: `docs/design/stitch-game-emulator-plan/_3/code.html`
- Modify: `entry/src/main/ets/pages/ShaderPreviewPage.ets`

**Step 1: 定位固定宽度**

Run:

```powershell
rg -n "width\(250\)|ShaderPreview|Split|Preview|Parameter" entry/src/main/ets/pages/ShaderPreviewPage.ets
```

Expected:

- 找到 `.width(250)` 的具体 UI 语义。

**Step 2: 判断改法**

If it is a compact control token:

- 保留，报告记录“允许的固定格式控件宽度”。

If it is a panel/container width:

- 改为 `.width('100%')` + `.constraintSize({ maxWidth: ... })` 或由父容器 grid/row 分配。

**Step 3: 验证**

Run:

```powershell
rg -n "width\(250\)|constraintSize|width\('100%'\)" entry/src/main/ets/pages/ShaderPreviewPage.ets
git diff --check
```

Expected:

- 如果改动，面板宽度不再硬编码为单张截图宽度。

## Task 5: 汇总静态复查结果

**Files:**
- Modify: `docs/2026-05-04-arkts-ui-static-scan.md`
- Maybe modify: `docs/2026-04-30-design-page-acceptance-matrix.md`

**Step 1: 更新扫描报告**

Add a `复查记录` section:

- `ImportEntryPage`: 改了什么 / 为什么不改。
- `RuntimeVirtualControllerLayer`: 改了什么 / 剩余真机风险。
- `ShaderPreviewPage`: 改了什么 / 为什么不改。

**Step 2: 跑固定布局扫描**

Run:

```powershell
rg -n "\.position\(|\.markAnchor\(|\.translate\(|\.offset\(|\.width\('[0-9]+vp'\)|\.height\('[0-9]+vp'\)|\.width\([0-9]{2,}\)|\.height\([0-9]{2,}\)" entry/src/main/ets/pages entry/src/main/ets/components -g "*.ets" -g "!deprecated/**" -g "!legacy/**"
```

Expected:

- 命中可以仍然存在，但报告必须解释新增 / 消除的高风险项。

**Step 3: 最终验证**

Run:

```powershell
git diff --check
git status --short
```

Expected:

- `git diff --check` 无输出，退出码 0。
- `git status --short` 明确显示本轮改动和既有脏改动。

## 推荐执行顺序

1. 先做 Task 1，把截图 evidence 接入矩阵。
2. 再做 Task 3，收益最高：Quick Save rail 是最明显的固定 top margin 风险。
3. Task 2 和 Task 4 视用户是否要继续 UI 收口再做。
4. 最后做 Task 5 汇总，不要每改一个点就大范围重写报告。

## 不做事项

- 不新增测试文件。
- 不跑 `hvigor`。
- 不真机。
- 不提交 Git，除非用户明确要求。
- 不清理 `.appanalyzer/`、`.claude/`、`.codex`、`.firecrawl/` 等未跟踪工具目录。
