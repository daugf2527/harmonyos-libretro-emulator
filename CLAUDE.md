# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

- **Open & build/run**: Use DevEco Studio to open the project. Select the `entry` module and execute Build / Run.
- **Test pages**: Navigate to `pages/LibretroGamePage` or `pages/LibretroNewArchTestPage`, select core + ROM, and monitor via `hilog`.
- **Build HAP**: `hvigorw assembleHap` (used in PR CI).
- **CI hygiene checks** (run locally before PR):
  ```bash
  bash scripts/ci/check_repo_hygiene.sh
  bash scripts/ci/check_regression_guards.sh
  ```
- **PR validation**: Triggered automatically via `.github/workflows/harmonyos-pr-ci.yml` (includes HarmonyOS CLI tools, `codelinter`, HAP smoke checks).
- **Release**: Push `v*` tag to trigger `.github/workflows/harmonyos-release.yml` (builds, signs, publishes GitHub Release).

## High-Level Architecture (new_arch)

- **ArkTS/ArkUI layer** (`entry/src/main/ets/`): UI, interaction, page state (`pages/`, `components/`, `common/`, `config/`).
- **C++ native layer** (`entry/src/main/cpp/`): `libentry.so` provides the engine.
  - `app/`: NAPI exports + XComponent bridging (`refactored*` interfaces).
  - `core/`: `LibretroEngine` (state machine, message queue, `retro_run`), `VideoPipeline`, core loader.
  - `platform/`: `AudioBridge`, graphics, resources, sync, XComponent.
- **Key bridges & pipelines**:
  - XComponent + NativeWindow: Video output surface.
  - NAPI: ArkTS ↔ C++ engine.
  - Engine thread: GameLoop + `VideoPipeline` (Hardware/Software/GLES/Vulkan modes, dynamic pixel/geometry negotiation).
  - Audio thread: `AudioBridge` (resampling, DRC, RingBuffer, underrun stats).
  - EventBridge: Input (keys, joysticks, sensors), SaveState/SRAM/Core Options/Cheat/DiskControl.
- **Threading rules** (strictly enforced):
  - Graphics API calls only on Engine thread.
  - NativeBuffer access: `FromNativeWindowBuffer + Map/Unmap` (never `mmap`/`munmap`).
  - Cross-thread state protected by locks.

**Primary documentation** (read first for any changes):
- `docs/plans/2026-02-06-new-arch-technical-whitepaper.md` (LibretroEngine, AudioBridge, VideoPipeline deep dives).

**Key source files** (for quick navigation):
- `entry/src/main/cpp/core/engine/libretro_engine.cpp`
- `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- `entry/src/main/cpp/platform/audio/audio_bridge.cpp`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`

**Constraints**:
- Prioritize official HarmonyOS docs + `libretro.h`.
- Deprecated code lives only in `deprecated/legacy/` (excluded from mainline).
- All changes must pass regression guards (NativeBuffer, LOG_DOMAIN, no hard-coded timeouts, no TODO/FIXME in first-party sources).

This CLAUDE.md is derived directly from the current README.md (updated 2026-02-06), README.en.md, and technical whitepaper.

## ArkTS/ArkUI Performance Anti-Patterns (2026-05 session)

### aboutToAppear lifecycle — DO NOT use setTimeout

**Problem**: Heavy sync work in `aboutToAppear()` blocks page transition animation on the main thread.

**Correct approach by situation**:
1. **Already-async operations**: Just use `void` (fire-and-forget), e.g. `void this.refreshLibraryGames()`. The first `await` inside auto-yields the main thread. NO setTimeout needed.
2. **Lightweight sync calls** (e.g. `listInputDevices()` → map → assign): Keep in `aboutToAppear()` directly — they complete in microseconds.
3. **Heavy sync computation/I/O**: Use `taskpool.execute()` to offload to background thread, then update UI via callback.
4. **Deferred until after transition**: Move to `onPageShow()` lifecycle if data isn't needed for initial render.

**Why NOT setTimeout**: setTimeout doesn't bind to page lifecycle — callback may execute after page destruction, causing use-after-free crashes on `this`.

### @State decorator — when to avoid

- **DO**: Use `@State` only for primitives (string/number/boolean) that are DIRECTLY read in `build()`.
- **AVOID**: Decorating complex objects/arrays with `@State` — each change triggers full re-render.
- **AVOID**: `@State` on derived data — use computed getters cautiously, or better, explicitly assign in the mutation method.
- **Checked pattern**: `private inputSourceOptions: SelectOption[]` assigned in `refreshInputDevices()` alongside its source array — avoids per-access `.map()` allocations and unnecessary re-renders.

### build() method — keep under ~200 lines

- Extract large blocks into `@Builder` methods (e.g. `@Builder ControlPanelOverlay()`).
- `@Builder` methods can access `this` reactive state — no prop drilling needed.
- Improves both incremental render performance and code maintainability.

### ForEach — always provide keyGenerator

- All 46 ForEach in this project have keyGenerator (91.3% at audit time). The few missing ones in SaveStatePage/InputLayoutPage were already fixed.

### Files modified in this session:

| File | Change | Why |
|------|--------|-----|
| `LibraryPage.ets` | `void this.refreshLibraryGames()` | Explicit fire-and-forget async, no setTimeout |
| `LibretroGamePage.ets` | `void this.refreshRomList()` | Same as above |
| `LibretroGamePage.ets` | `inputSourceOptions` @State→private, explicit assign | Avoid per-access re-allocation, reduce re-renders |
| `LibretroGamePage.ets` | `@Builder ControlPanelOverlay()` | First @Builder extraction, ~83 lines out of build() |
| `LibretroGamePage.ets` | Cache `getAvailableRoms()` with reference-equality | Avoids redundant `.filter()` on every call, O(roms) → O(1) after hit |
| `LibretroGamePage.ets` | `getRuntimeHudMetrics()` → reuse `hudMetricsCache` array | Avoids per-render array allocation in build() (60×/sec at 60fps) |

### Files modified in 2026-05-11 session (Canvas optimization):

| File | Change | Why |
|------|--------|-----|
| `EmuAppShell.ets` | Add `GridBackground` component (configurable gridSize/lineColor/lineWidth) | Extracted from `PrecisionGrid(20)` pattern for reuse; replace hardcoded grid in OnboardingPage + ImportTaskOverlayPage |
| `OnboardingPage.ets` | Replace `PrecisionGrid(20)` → `GridBackground({ gridSize: 40 })` and `GridBackground({ gridSize: 20 })` | Avoid constructing range arrays (0..N) on every render; Canvas draws grid directly from parameters |
| `ImportTaskOverlayPage.ets` | Replace `PrecisionGrid(20)` → `GridBackground({ gridSize: 40 })` | Same as above |
| `LibretroGamePage.ets` | Extract `ControlPanelOverlay()` → `@Builder` | Reduce `build()` method size; improve incremental render performance |

**Note**: `EmuPrecisionGridBackdrop` (pre-existing component) and `createIndexRange` (utility in EmuUiTokens.ets) are still used by ImportEntryPage, InputLayoutPage, MultiplayerInputPage, SettingsPage, and LibraryDetailInfoPanel — but no longer by LibraryLaunchOverlay or RuntimeVirtualControllerLayer (migrated to Canvas-based ScanlineBackground).

### Scanline optimization (2026-05-11 session, same branch):

| File | Change | Why |
|------|--------|-----|
| `EmuAppShell.ets` | Add `ScanlineBackground` Canvas component (configurable lineColor/lineSpacing/alternateColor) | Reusable replacement for `ForEach(createIndexRange(N))` decorative scanline patterns |
| `LibraryLaunchOverlay.ets` | Replace `ForEach(createIndexRange(90))` 90-Row scanlines → `ScanlineBackground({ lineColor: '#1400FF41', lineSpacing: 2 })` | Eliminates 90 component creations per render (90 → 1 Canvas) |
| `RuntimeVirtualControllerLayer.ets` | Replace `ForEach(scanlineIndexes)` 160-Row scanlines → `ScanlineBackground({ lineColor: '#1000FF41', lineSpacing: 1, alternateColor: '#10000000' })`; remove `scanlineIndexes` field | Eliminates 160 component creations per render (160 → 1 Canvas) |

### LazyForEach migration (2026-05-11 session, same branch):

| File | Change | Why |
|------|--------|-----|
| `LibraryGameSections.ets` | Add `LibraryDataSource` class (implements `IDataSource`); `ForEach(this.games, ...)` → `LazyForEach(this.allGamesDataSource, ...)` in `AllGamesContent()`; add `@Watch('onGamesChanged')` + `aboutToAppear()` | Eliminates 100-500+ GameCard component creations per render; only visible items are created (lazy loading/recycling). `recentGames` ForEach kept as-is (≤10 items). No changes to `GameCard.ets` or `LibraryPage.ets`. |

## Environment & Tools

### Local development environment (Windows + Git Bash)

**Available tools**:
- **git**: v2.54.0 (in PATH)
- **python3**: v3.8.1 (in PATH at `/c/Users/newwo/bin/python3`)
- **node**: v22.22.0 (at `D:\nodejs`, requires explicit PATH config)
- **npm**: v10.8.2 (at `D:\nodejs`, requires explicit PATH config)
- **PowerShell**: v1.0 (at `C:\Windows\System32\WindowsPowerShell\v1.0`, requires explicit PATH config)
- **DevEco Studio**: `D:\Program Files\DevEco Studio\bin`
- **HarmonyOS CLI**: `D:\hongmeng\command-line-tools\bin`

**PATH configuration issue**:
Claude Code on Windows Git Bash has a bug where `$PATH` is inserted as a literal string instead of being expanded, causing Windows system PATH to be truncated. This breaks access to node/npm/PowerShell and other system tools.

**Fix**: Add required tool paths explicitly in `~/.claude/settings.json`:
```json
{
  "env": {
    "PATH": "/d/nodejs:/c/Windows/System32/WindowsPowerShell/v1.0:${PATH}"
  }
}
```

**Verification**: After modifying settings.json, restart Claude Code session and run `which node && node --version` to verify.

**statusline configuration**: `~/.claude/statusline.sh` uses pure bash JSON parsing (grep + sed) to avoid dependency on node/jq, which may be unavailable due to PATH issues.

## Tool Failure Patterns — Lessons Learned

### WebSearch / firecrawl_search — common failures

| Failure | Symptom | Fix |
|---------|---------|-----|
| **Empty results** | Returns only "REMINDER: You MUST include the sources above..." | WebSearch often returns empty for Chinese queries on developer portals. Switch to English queries or use `site:` operator. |
| **firecrawl_search "insufficient credits"** | All calls fail with credit error | API quota exhausted. Fall back to built-in WebSearch or WebFetch. |
| **firecrawl_search parameter format** | `sources` must be `[{type: "web"}]` array, NOT `"web"` string or `{type: "web"}` object. | Always wrap in `<item><type>web</type></item>`. |
| **WebFetch empty content** | developer.huawei.com pages return only heading text, no body | These pages require JavaScript rendering. Use `firecrawl_scrape` with `waitFor: 5000` instead. |

### General web research strategy for HarmonyOS docs

1. **First try**: `WebSearch` with English queries + `site:developer.huawei.com`
2. **If empty**: `firecrawl_search` with same query (check credits first)
3. **For specific pages**: `firecrawl_scrape` with JSON format + `waitFor` for JS-rendered pages
4. **Last resort**: `firecrawl_agent` for multi-source research (slow but thorough)
5. **For local docs**: Use `firecrawl_parse` to extract from PDFs/DOCX files on disk
