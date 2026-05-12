# HarmonyOS UI Translation Roadmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Stitch 导出的 4 个核心产品页面落地为 HarmonyOS ArkTS/ArkUI 页面，替换当前研发入口菜单，形成“导入入口 -> 游戏库 -> 详情启动 -> 正式设置”的原生主链路。

**Architecture:** 先抽离公共视觉壳层与 token，再按页面顺序逐个实现。页面以 ArkUI 原生布局为主，HTML 只作为结构和视觉参考；与引擎、路由、权限、XComponent 交互的部分全部落在 ArkTS 中。

**Tech Stack:** HarmonyOS ArkUI / ArkTS, Nav/router, existing `libentry.so` NAPI bridge, existing UI pages/components in `entry/src/main/ets/`.

---

## Scope

本计划覆盖以下 4 个 Stitch 设计稿的原生化：

- `stitch_game_emulator_design_plan/_13/code.html` -> 导入入口页
- `stitch_game_emulator_design_plan/_11/code.html` -> 游戏库页
- `stitch_game_emulator_design_plan/_10/code.html` -> 详情启动页
- `stitch_game_emulator_design_plan/_4/code.html` -> 正式设置页

不在本次范围内：

- `_12` 游戏库变体菜单
- `_7` 虚拟手柄完整视觉重构
- `_9` 暂停页
- 任何 C++ / engine / audio / graphics 层修改

## Existing Files To Reuse

- Existing: `entry/src/main/ets/pages/OnboardingPage.ets`
- Existing: `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`
- Existing: `entry/src/main/ets/pages/LibretroGamePage.ets`
- Existing: `entry/src/main/ets/components/VirtualController.ets`
- Existing: `entry/src/main/ets/common/LogHelper.ets`

## Task 1: 抽公共 UI Token 与 Shell

**Files:**
- Create: `entry/src/main/ets/common/EmuUiTokens.ets`
- Create: `entry/src/main/ets/components/EmuAppShell.ets`
- Create: `entry/src/main/ets/components/EmuBottomNav.ets`
- Modify: `entry/src/main/ets/pages/OnboardingPage.ets`
- Modify: `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`

**Purpose:**
先把目前散落在 `OnboardingPage`、`ImportTaskOverlayPage` 中的黑绿终端风视觉常量收敛，避免后续 4 个页面复制样式。

**Create `EmuUiTokens.ets`:**
- Export `interface EmuColorTokens`
- Export `interface EmuSpacingTokens`
- Export `interface EmuRadiusTokens`
- Export `const EmuColors`
- Export `const EmuSpacing`
- Export `const EmuRadius`
- Export helper constants for:
  - top header height
  - bottom nav height
  - default content max width
  - grid line color
  - default panel border color

**Create `EmuAppShell.ets`:**
- Export `@Component struct EmuAppShell`
- Responsibility:
  - full-screen background
  - safe area handling
  - optional precision grid background
  - top header slot
  - content slot
  - optional footer slot
- No business logic inside shell

**Create `EmuBottomNav.ets`:**
- Export `interface EmuBottomNavItem`
- Export `@Component struct EmuBottomNav`
- Support active item highlighting
- Support 3-4 nav items
- Match current Stitch 黑底 + 细描边 + monospace label style

**Modify `OnboardingPage.ets`:**
- Replace duplicated color token block with imports from `EmuUiTokens.ets`
- If simple enough, replace header/footer shell with `EmuAppShell`
- Keep current Step1/Step2 behavior unchanged

**Modify `ImportTaskOverlayPage.ets`:**
- Replace duplicated color token block with imports from `EmuUiTokens.ets`
- Replace current bottom nav local builder with `EmuBottomNav`
- Keep current overlay state machine unchanged

**Acceptance:**
- New shared shell can serve all new pages
- No new page introduces a new ad-hoc token system
- `OnboardingPage` and `ImportTaskOverlayPage` still compile conceptually with the shared imports

## Task 2: 导入入口页 `ImportEntryPage`

**Files:**
- Create: `entry/src/main/ets/pages/ImportEntryPage.ets`
- Create: `entry/src/main/ets/components/ImportEmptyStateHero.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/ets/pages/Index.ets`

**Design Source:**
- `stitch_game_emulator_design_plan/_13/code.html`

**Page Responsibility:**
- 当游戏库为空时展示空状态
- 提供“选择游戏文件导入”的主入口
- 支持简化扫描进度视觉，不实现真实文件导入逻辑

**Create `ImportEmptyStateHero.ets`:**
- Encapsulate:
  - empty slot illustration
  - title
  - subtitle
  - primary import button
  - optional scan progress section

**Create `ImportEntryPage.ets`:**
- Use `EmuAppShell`
- Use `EmuBottomNav`
- Use `ImportEmptyStateHero`
- Define local explicit state:
  - `@State isScanning: boolean`
  - `@State scanProgress: number`
  - `@State hasGames: boolean`
- If `hasGames === true`, this page should route to `LibraryPage` instead of staying as empty-state home
- Temporary button action:
  - show lightweight scanning progress animation
  - then route to `pages/ImportTaskOverlayPage`

**Modify `main_pages.json`:**
- Register `pages/ImportEntryPage`
- Keep existing pages intact

**Modify `Index.ets`:**
- Add one direct entry button to `ImportEntryPage`
- Keep existing debug buttons for now, but clearly separate product path from debug path in later cleanup

**Acceptance:**
- Page is reachable through router
- Visual hierarchy matches Stitch empty library/import-entry design
- Does not depend on WebView

## Task 3: 游戏库页 `LibraryPage`

**Files:**
- Create: `entry/src/main/ets/pages/LibraryPage.ets`
- Create: `entry/src/main/ets/components/PlatformChipBar.ets`
- Create: `entry/src/main/ets/components/GameCard.ets`
- Create: `entry/src/main/ets/components/LibrarySection.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/ets/pages/ImportEntryPage.ets`
- Modify: `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`

**Design Source:**
- Primary: `stitch_game_emulator_design_plan/_11/code.html`
- Defer variant controls from: `stitch_game_emulator_design_plan/_12/code.html`

**Page Responsibility:**
- 展示平台筛选
- 展示“最近运行”
- 展示“全部游戏”
- 允许点击卡片进入详情页

**Create `PlatformChipBar.ets`:**
- Render platform filter chips
- Props:
  - `items: string[]`
  - `selected: string`
  - `onChange`

**Create `GameCard.ets`:**
- Props:
  - `gameId`
  - `title`
  - `subtitle`
  - `cover`
  - `platform`
  - `lastPlayedText?`
  - `onClick`
- Must support at least two visual modes:
  - recent item card
  - library grid/list card

**Create `LibrarySection.ets`:**
- Reusable titled section block for:
  - `最近运行`
  - `全部游戏`

**Create `LibraryPage.ets`:**
- Use `EmuAppShell`
- Use `EmuBottomNav`
- Use `PlatformChipBar`
- Use `LibrarySection`
- Use `List` / `LazyForEach` for larger data
- Define local mock data with explicit interfaces:
  - `interface LibraryGameItem`
  - `interface RecentGameItem`
- State:
  - `@State selectedPlatform: string`
  - `@State recentGames: RecentGameItem[]`
  - `@State allGames: LibraryGameItem[]`

**Modify `ImportEntryPage.ets`:**
- Successful empty-state path should eventually route to `LibraryPage`

**Modify `ImportTaskOverlayPage.ets`:**
- On success action, route to `LibraryPage` instead of cycling back to importing state

**Modify `main_pages.json`:**
- Register `pages/LibraryPage`

**Acceptance:**
- Empty-state import flow can land in library page
- Library page has a stable scroll container
- Cards are data-driven, not hard-coded repeated rows

## Task 4: 详情启动页 `GameDetailPage`

**Files:**
- Create: `entry/src/main/ets/pages/GameDetailPage.ets`
- Create: `entry/src/main/ets/components/GameMetadataPanel.ets`
- Create: `entry/src/main/ets/components/LaunchActionPanel.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/ets/pages/LibraryPage.ets`
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Design Source:**
- `stitch_game_emulator_design_plan/_10/code.html`

**Page Responsibility:**
- 展示游戏封面、描述、平台、核心信息
- 允许选择或展示默认核心
- 点击 CTA 启动原生 `LibretroGamePage`

**Create `GameMetadataPanel.ets`:**
- Show title, platform, core label, metadata rows
- Support "expand more" action for extended metadata

**Create `LaunchActionPanel.ets`:**
- Main launch CTA
- Secondary actions:
  - change core
  - open settings
  - optional favorite/library action

**Create `GameDetailPage.ets`:**
- Use `EmuAppShell`
- Use `EmuBottomNav`
- Use `GameMetadataPanel`
- Use `LaunchActionPanel`
- Local state:
  - `@State gameId: string`
  - `@State selectedCoreId: string`
  - `@State isLaunching: boolean`
  - `@State showExtendedMetadata: boolean`
- Read router params from selected game card
- Keep mock-detail fallback if params missing

**Modify `LibraryPage.ets`:**
- On card click, route to `pages/GameDetailPage`
- Pass explicit typed params

**Modify `LibretroGamePage.ets`:**
- Add lightweight support for receiving startup params from router:
  - selected core id
  - rom path / rom name
- Do not refactor current engine logic here beyond parameter ingestion

**Modify `main_pages.json`:**
- Register `pages/GameDetailPage`

**Acceptance:**
- User can move Library -> Detail -> Game runtime
- Detail page is distinct from runtime page
- Runtime page no longer needs to serve as a pseudo-detail page

## Task 5: 正式设置页 `SettingsPage`

**Files:**
- Create: `entry/src/main/ets/pages/SettingsPage.ets`
- Create: `entry/src/main/ets/components/SettingsSection.ets`
- Create: `entry/src/main/ets/components/SettingsValueRow.ets`
- Create: `entry/src/main/ets/components/SettingsTabHeader.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/ets/pages/GameDetailPage.ets`
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Design Source:**
- `stitch_game_emulator_design_plan/_4/code.html`

**Page Responsibility:**
- 承担正式用户设置，而不是工程调试控制台
- Basic / Advanced 分栏
- 覆盖画面、输入、音频、系统信息

**Create `SettingsSection.ets`:**
- Shared section container with title + code label

**Create `SettingsValueRow.ets`:**
- Shared row for:
  - text + current value
  - text + switch
  - text + segmented choice

**Create `SettingsTabHeader.ets`:**
- Tabs for `基础设置` / `高级设置`

**Create `SettingsPage.ets`:**
- Use `EmuAppShell`
- State:
  - `@State activeTab: string`
  - `@State aspectMode: string`
  - `@State volume: number`
  - `@State hwRenderAllowed: boolean`
  - `@State inputMode: string`
- Map to existing engine/UI config where possible
- Use explicit interfaces for settings options

**Modify `GameDetailPage.ets`:**
- Secondary action "设置" routes to `pages/SettingsPage`

**Modify `LibretroGamePage.ets`:**
- Split current control drawer into:
  - user-facing runtime actions kept in drawer
  - engineering-only actions kept behind a debug section or separate test page
- Remove these from formal user menu path:
  - core symbol validation
  - soak test
  - raw debug text sections
  - `XComponentId`
- Keep these accessible elsewhere if still needed for dev:
  - existing `LibretroNewArchTestPage`
  - existing `TestGambatte`

**Modify `main_pages.json`:**
- Register `pages/SettingsPage`

**Acceptance:**
- Product settings page exists independently of runtime overlay
- Runtime menu becomes simpler and user-facing
- Engineering controls are no longer mixed into the normal product path

## Task 6: 产品路径收口

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

**Purpose:**
在 4 个页面具备最小可用后，把入口从研发目录式菜单逐步收口到产品主链路。

**Modify `Index.ets`:**
- Replace current all-buttons-centered layout with grouped layout:
  - product path group
  - debug tools group
- Eventually product default button should point to `ImportEntryPage` or `LibraryPage`

**Modify `EntryAbility.ets`:**
- Phase 1:
  - keep `pages/Index` as load target
- Phase 2:
  - once product path stabilizes, switch to `pages/ImportEntryPage` or `pages/LibraryPage`

**Acceptance:**
- App launch no longer feels like a test launcher once final switch happens

## Delivery Order

1. `EmuUiTokens.ets`
2. `EmuAppShell.ets`
3. `EmuBottomNav.ets`
4. `ImportEntryPage.ets`
5. `LibraryPage.ets`
6. `GameDetailPage.ets`
7. `SettingsPage.ets`
8. Runtime menu cleanup in `LibretroGamePage.ets`
9. Product-path entry cleanup in `Index.ets` / `EntryAbility.ets`

## Verification Notes

按仓库约定，本计划不要求新增测试脚本，也不要求在计划阶段编译运行。实现时应以以下人工验证为主：

- 路由可达
- 安全区正确
- 页面之间参数传递正确
- 不再依赖 WebView 作为主链路页面
- 游戏中菜单不再暴露工程调试控件给普通用户

## Open Decisions

- `LibraryPage` 是否作为首页，取决于是否已有已导入游戏数据
- `GameDetailPage` 是否允许直接切换核心，取决于当前 ROM/core 绑定策略
- `SettingsPage` 是否需要全局设置与游戏内设置分离，当前计划先做单页承接

Plan complete and saved to `docs/plans/2026-04-08-ui-translation-roadmap.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
