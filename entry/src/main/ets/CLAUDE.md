# ArkTS / ArkUI Performance Anti-Patterns

This file documents ArkTS/ArkUI-specific patterns enforced in `entry/src/main/ets/`. Loaded on demand when Claude works under this directory.

For cross-layer architecture see the root `CLAUDE.md`.

## aboutToAppear lifecycle — DO NOT use setTimeout

**Problem**: Heavy sync work in `aboutToAppear()` blocks page transition animation on the main thread.

**Correct approach by situation**:
1. **Already-async operations**: Use `void` fire-and-forget, e.g. `void this.refreshLibraryGames()`. The first `await` inside auto-yields the main thread. NO setTimeout needed.
2. **Lightweight sync calls** (e.g. `listInputDevices()` → map → assign): Keep in `aboutToAppear()` directly — they complete in microseconds.
3. **Heavy sync computation/I/O**: Use `taskpool.execute()` to offload to background thread, then update UI via callback.
4. **Deferred until after transition**: Move to `onPageShow()` lifecycle if data isn't needed for initial render.

**Why NOT setTimeout**: setTimeout doesn't bind to page lifecycle — callback may execute after page destruction, causing use-after-free crashes on `this`.

## @State decorator — when to avoid

- **DO**: Use `@State` only for primitives (string/number/boolean) that are DIRECTLY read in `build()`.
- **AVOID**: Decorating complex objects/arrays with `@State` — each change triggers full re-render.
- **AVOID**: `@State` on derived data — use computed getters cautiously, or better, explicitly assign in the mutation method.
- **Checked pattern**: `private inputSourceOptions: SelectOption[]` assigned in `refreshInputDevices()` alongside its source array — avoids per-access `.map()` allocations and unnecessary re-renders.

## build() method — keep under ~200 lines

- Extract large blocks into `@Builder` methods (e.g. `@Builder ControlPanelOverlay()`).
- `@Builder` methods can access `this` reactive state — no prop drilling needed.
- Improves both incremental render performance and code maintainability.

## ForEach — always provide keyGenerator

- All 46 ForEach in this project have keyGenerator (91.3% at audit time). Missing ones in SaveStatePage/InputLayoutPage were fixed.

## Canvas-based decoration (replaces ForEach range patterns)

- **GridBackground** (in `EmuAppShell.ets`): configurable `gridSize` / `lineColor` / `lineWidth`. Replaces `PrecisionGrid(N)` patterns that built range arrays per render.
- **ScanlineBackground** (in `EmuAppShell.ets`): configurable `lineColor` / `lineSpacing` / `alternateColor`. Replaces `ForEach(createIndexRange(N))` decorative scanline patterns.
- `EmuPrecisionGridBackdrop` + `createIndexRange` (utility in `EmuUiTokens.ets`) are still used by ImportEntryPage / InputLayoutPage / MultiplayerInputPage / SettingsPage / LibraryDetailInfoPanel — migrated away in LibraryLaunchOverlay and RuntimeVirtualControllerLayer.

## LazyForEach migration (for large lists)

- `LibraryDataSource` class implements `IDataSource`; used in `AllGamesContent()` to avoid creating 100-500+ GameCard components per render. Only visible items are created (lazy loading/recycling).
- `recentGames` ForEach kept as-is — ≤10 items, no benefit from lazy loading.

## Historical fix log (reference for "we already did this")

### 2026-05 perf pass:

| File | Change | Why |
|------|--------|-----|
| `LibraryPage.ets` | `void this.refreshLibraryGames()` | Explicit fire-and-forget async, no setTimeout |
| `LibretroGamePage.ets` | `void this.refreshRomList()` | Same as above |
| `LibretroGamePage.ets` | `inputSourceOptions` @State→private, explicit assign | Avoid per-access re-allocation, reduce re-renders |
| `LibretroGamePage.ets` | `@Builder ControlPanelOverlay()` | First @Builder extraction, ~83 lines out of build() |
| `LibretroGamePage.ets` | Cache `getAvailableRoms()` with reference-equality | O(roms) → O(1) after hit |
| `LibretroGamePage.ets` | `getRuntimeHudMetrics()` reuses `hudMetricsCache` array | Avoids per-render array allocation (60×/sec at 60fps) |

### 2026-05-11 Canvas/scanline/LazyForEach session:

| File | Change |
|------|--------|
| `OnboardingPage.ets` / `ImportTaskOverlayPage.ets` | `PrecisionGrid(20)` → `GridBackground` |
| `LibraryLaunchOverlay.ets` | 90-Row scanlines → `ScanlineBackground` (90 components → 1 Canvas) |
| `RuntimeVirtualControllerLayer.ets` | 160-Row scanlines → `ScanlineBackground` (160 → 1 Canvas) + removed `scanlineIndexes` |
| `LibraryGameSections.ets` | `ForEach` → `LazyForEach(allGamesDataSource)` in `AllGamesContent()` |
