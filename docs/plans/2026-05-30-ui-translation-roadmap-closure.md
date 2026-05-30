# UI Translation Roadmap — Closure Report

**Closes:** `docs/plans/2026-04-08-ui-translation-roadmap.md`
**Closure date:** 2026-05-30
**Status:** **DONE**(主体 6 task 全部落地 + 长尾增强已收口)

---

## 1. 为什么写这份 closure

最近 2 周连续 commit T3-T11 + 5 个零散 feat/refactor 给人"东一块西一块"的感觉,但 audit 后发现这些**全部是 2026-04-08 plan 的长尾收口**,只是没显式打"epic done"的旗子。

这次正式宣告该 epic 关闭,后续 UI 工作走 `docs/plans/2026-05-30-ui-polish-foldable-epic.md`(epic B)。

---

## 2. 6 个 Task 完成证据

| Task | 计划交付 | 实际落地文件 | 主要 commit |
|------|---------|--------------|-------------|
| **T1** 公共 UI Token + Shell | `EmuUiTokens` / `EmuAppShell` / `EmuBottomNav` | 三个文件均已建,3-tab IA 终态收敛 | `8b1b6f7 refactor(nav): remove ENGINE bottom-nav tab, route to 3-tab IA` |
| **T2** 导入入口页 | `ImportEntryPage` / `ImportEmptyStateHero` | 均建,粒子层、空状态、扫描进度逻辑齐备 | (历史 commits,perf 已优化) `8fed179 perf(ui)` |
| **T3** 游戏库页 | `LibraryPage` / `PlatformChipBar` / `GameCard` / `LibrarySection` | 全建 + 长尾增强:`LibraryGameSections` / `LibrarySearchPanel` / `LibraryContextMenuOverlay` / `LibraryLaunchOverlay` | `694753c feat(library): add last-played chip on LibraryPage, gate telemetry on data` |
| **T4** 详情启动页 | `GameDetailPage`(实际改名为 `LibraryDetailPage`)/ `GameMetadataPanel`(改为 `LibraryDetailInfoPanel`)/ `LaunchActionPanel`(改为 `LibraryDetailActionMenu` + `LibraryDetailHeroPanel`) | 命名重构后全建,LibretroGamePage 已接受路由参数 | `8fed179 perf(ui): unify replaceUrl + suspend before route + extract heavy children` |
| **T5** 正式设置页 | `SettingsPage` + `SettingsSection` + `SettingsValueRow` + `SettingsTabHeader` + LibretroGamePage 拆 dev/user | SettingsPage 全建,LibretroGamePage 工程控件(core-check/soak)迁出到 NewArchTestPage | `efd0150 refactor(ui): move core-check/soak diagnostics to NewArchTestPage (T3)` `c71ee90 refactor(ui): remove dead core-check/soak state (T6)` `081b00a feat(runtime): remove RuntimeControlPanel drawer (T5)` `adc065d feat(settings): migrate hideVirtualController toggle (T8)` `464582a feat(settings): add hide-undeclared-keys toggle (T10)` |
| **T6** 产品路径收口 | Index.ets 分组 + EntryAbility 切默认入口 | **部分完成**:Index.ets 已加产品入口按钮(`产品入口:导入主页`);EntryAbility 默认 `loadContent('pages/Index')` **未切**——本 closure 同批补完(commit 见下) | A2 同批 commit(本次会话) |

---

## 3. 计划外的长尾增强(同主线,值得一起收口)

这些不在 2026-04-08 plan 原文,但**逻辑上属于这条 epic 的延伸**:

| 增强 | 落地 commit | 归属 task |
|------|-------------|-----------|
| LibretroGamePage idle empty-state(defense-in-depth) | `5692442` | T5 延伸(运行态防御) |
| RuntimePauseOverlay restart action | `78032b2 (T4)` | T5 延伸(暂停页能力) |
| MENU button 暂停态图标切换 | `f533c7e (T7)` | T5 延伸 |
| RuntimeControlPanel drawer 移除 | `081b00a (T5)` | T5 收口(简化运行态菜单) |
| RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS mask 暴露 | `e2c20fd` | T5 延伸(运行态输入展示) |
| DevDiagnosticsBlock 单页面收敛 | `a22a96a (T11)` | T5 延伸 |
| arkts Function.call → optional method | `1006048` | 兼容性 hotfix |

---

## 4. 已废弃 / 被取代的中间产物

- `docs/plans/2026-04-26-stitch-visual-parity-closure.md` — 文档头部已标记"已被 2026-04-30 验收文档取代,仅作历史计划参考"
- `docs/plans/2026-05-04-ui-static-closure.md` — Task 1/3 已落,Task 2/4/5 剩余项收入 **epic B**
- `RuntimeControlPanel.ets` — 已移除(`081b00a`)

---

## 5. 不在本 epic 范围、留给 epic B 或更后

- `_12` 游戏库 variant menu(LibraryContextMenuOverlay 已有基础,polish 留 epic B)
- `_7` 虚拟手柄完整视觉重构(基础已迁入 `RuntimeVirtualControllerLayer`,Quick Save rail polish 留 epic B)
- `_9` 暂停页扩展能力(restart 已加,quick save/filter UI placeholder 留 epic B/D)
- FoldableLayouts 接 LibraryPage / LibretroGamePage(Roadmap.md M7,留 epic B)
- 多 core 切换 UI(Roadmap.md M6,留 epic C)
- Input Mapper(Roadmap.md M3 P0 痛点,留 epic D)

---

## 6. Closure 验证(本次提交前必跑)

- [x] `git log` 确认 T1-T11 全部 merge
- [x] `entry/src/main/resources/base/profile/main_pages.json` 包含 ImportEntryPage / LibraryPage / LibraryDetailPage / SettingsPage(verified line 5-8)
- [ ] EntryAbility 默认入口切换(本 closure 同批 commit,见 A2)
- [ ] `bash scripts/check/quick_signals.sh` ALL PASS(commit 前跑)

---

## 7. 给未来 Claude / 用户的提醒

1. **下次 UI 工作走 epic B**:`docs/plans/2026-05-30-ui-polish-foldable-epic.md`
2. **不要再往 4-08 plan 上加 task** — 已 closed,新需求开新 plan
3. **零散 feat commit 出现时**先看是否属于某个 active epic,属于就在 commit message 里打 epic 标签(如 `[epic-B/B2]`),不属于就先停下问"这是新 epic 还是技术债?"

---

**Closure approved by:** (待用户 review 后填)
**Next epic kickoff:** epic B "UI Polish & 折叠屏",需 plan 文档 review 通过后启动。
