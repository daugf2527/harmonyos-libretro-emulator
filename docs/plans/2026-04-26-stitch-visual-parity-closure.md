# Stitch Visual Parity Closure Implementation Plan

> 状态：已被 2026-04-30 两份验收文档取代，仅作历史计划参考。
> 后续不要再按该旧计划继续执行 `_12 menu`、随机扫描进度、旧 import simulation 等条目；以 `docs/2026-04-30-design-page-acceptance-matrix.md` 和 `docs/2026-04-30-design-page-artifact-gap-audit.md` 为准。

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the largest visual gaps between the Stitch emulator screens and native ArkTS pages without weakening the real runtime/data-state boundaries.

**Architecture:** Keep the current native ETS product path and shared `EmuUiTokens` / `EmuBottomNav` / `EmuAppShell` components. Add missing user-facing screens and overlay builders instead of moving engine logic or copying HTML absolute positioning. Runtime state remains owned by `LibretroGamePage` and repository data remains owned by `LibraryRepository`.

**Tech Stack:** HarmonyOS ArkUI / ArkTS, shared emulator UI tokens, router pages in `main_pages.json`, existing `libentry.so` NAPI bridge.

---

## Web Research Notes

- Huawei's ArkUI overview positions ArkUI as the declarative UI framework for HarmonyOS app interfaces, so this implementation keeps state-driven ArkTS components rather than porting DOM scripts directly.
- Huawei's design documentation emphasizes consistent component architecture and cross-device user experience; this matches the current repo rules against screenshot-only absolute positioning.
- The official document center exposes ArkTS, ArkUI, design, components, and UX standards as the relevant source families for this work.

## Task 1: Add Formal Settings Page for `_4`

**Files:**
- Create: `entry/src/main/ets/pages/SettingsPage.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `entry/src/main/ets/pages/LibraryPage.ets`
- Modify: `entry/src/main/ets/pages/LibraryDetailPage.ets`
- Modify: `entry/src/main/ets/pages/ImportEntryPage.ets`

**Steps:**
1. Build a `SettingsPage` matching `_4`: top HUD, Basic/Advanced tabs, video settings, input device card, audio slider, system telemetry.
2. Use explicit interfaces for sections and telemetry bars.
3. Register the page in `main_pages.json`.
4. Route bottom-nav `SYSTEM` actions to `pages/SettingsPage` instead of onboarding.

**Acceptance:**
- A product settings route exists.
- The `_4` visual gap is no longer a missing-page gap.

## Task 2: Re-skin Runtime HUD for `_7`

**Files:**
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Steps:**
1. Replace the visible debug-style FPS panel with a compact top telemetry HUD.
2. Keep debug strings hidden from the default user-facing screen.
3. Restyle virtual controller controls with dark panels, green accents, and fixed button clusters.
4. Keep existing input event bindings intact.

**Acceptance:**
- Running game screen reads like `_7`, not a debug console.
- Touch mappings are unchanged.

## Task 3: Add Pause Overlay for `_9`

**Files:**
- Modify: `entry/src/main/ets/pages/LibretroGamePage.ets`

**Steps:**
1. Add a full-screen pause overlay shown when `gamePaused` is true.
2. Include resume, quick save/load placeholders, input mapping, visual filters, terminate session, and subsystem telemetry.
3. Wire resume to existing `resumeGame()` and terminate to existing `stopGame()`.
4. Keep unsupported actions as explicit no-op UI placeholders, not fake engine operations.

**Acceptance:**
- Paused runtime has a product-style surface matching `_9`.
- No fake save/filter action is written as real behavior.

## Task 4: Tighten Library Menu and Import Flow

**Files:**
- Modify: `entry/src/main/ets/pages/LibraryPage.ets`
- Modify: `entry/src/main/ets/pages/ImportEntryPage.ets`
- Modify: `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`

**Steps:**
1. Increase context action sheet width and spacing to better match `_12`.
2. Remove unused import simulation functions from `ImportTaskOverlayPage`.
3. Stop using random pre-picker scan progress in `ImportEntryPage`; use honest picker handoff state.

**Acceptance:**
- `_12` menu feels less compressed.
- Import path no longer contains demo-only progress helpers.

## Verification

Per project instruction, do not run compile or device validation in this pass unless explicitly requested. Static checks only:

- `rg` for removed simulation helpers.
- `git diff` review for touched files.
- User can run `hvigorw assembleApp` and device screenshots after this pass.
