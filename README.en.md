# HarmonyOS Libretro Emulator

> A Libretro frontend project for HarmonyOS phones, built on the `new_arch` runtime.
> This README reflects the current repository state as of `2026-06-28`.

## What This Project Is

This repository is a real HarmonyOS Libretro frontend that connects `ArkTS/ArkUI`, `XComponent`, `NativeWindow`, `NAPI`, and Libretro cores into one working product foundation.

It is not just:

- a UI shell
- a rendering demo
- a one-off core loading experiment

The current mainline tries to achieve three things:

- bring Libretro frontend capability to HarmonyOS phones
- keep engine, rendering, audio, input, and switching flows observable and recoverable
- evolve toward a maintainable product codebase instead of a pile of temporary test pages and scripts

## What It Looks Like Today

| Onboarding | Input Center | Settings |
| --- | --- | --- |
| ![Onboarding](docs/verification/runtime-screenshots-2026-05-04/02_boot_welcome_quick_start.png) | ![Input Center](docs/verification/runtime-screenshots-2026-05-04/08_input_netplay_center.png) | ![Settings](docs/verification/runtime-screenshots-2026-05-04/09_system_basic_settings.png) |

More screenshots and UI evidence:

- `docs/verification/runtime-screenshots-2026-05-04/`
- `docs/2026-04-30-design-page-acceptance-matrix.md`
- `docs/archive/misc/2026-05-04-artifact-to-runtime-gap-audit.md`

## Current Mainline Capabilities

### 1. Engine and Lifecycle

- dedicated `LibretroEngine` thread
- explicit state machine and message queue
- `refactoredSwitchGameAsync(...)` with cancellation, single-flight protection, and recovery
- last-error info, state waiting, and runtime stats

### 2. Rendering

- `VideoPipeline` with `Hardware / Software / GLES` paths
- `XComponent + NativeWindow` video hosting
- core video negotiation paths such as `SET_PIXEL_FORMAT`, `SET_GEOMETRY`, and dupe/null-frame handling
- GLES and Vulkan HW-render baseline support

### 3. Audio

- `AudioBridge` with resampling, DRC, RingBuffer, and runtime metrics
- OHAudio playback path
- minimum-audio-latency control and sync mode handling

### 4. Input and Runtime Control

- digital buttons, analog sticks, sensors, and port binding
- virtual controller and input-layout pages
- Save State, SRAM, Core Options, Cheat, and DiskControl support

### 5. Product Pages

- onboarding
- import entry and import task overlay
- library, detail page, settings, save state, help page
- input center, shader preview, runtime control overlays

## Repository Layout

```text
entry/src/main/cpp/
  app/                 NAPI exports and XComponent bridge
  core/                LibretroEngine, VideoPipeline, core loader, env
  platform/            audio / graphics / resource / sync / xcomponent

entry/src/main/ets/
  pages/               product pages and test pages
  components/          runtime controls, detail widgets, nav components
  common/              EventHub, repositories, presenters, coordinators

docs/
  architecture/        stable architecture references
  design/              design assets and UI references
  plans/               roadmaps and implementation plans
  verification/        screenshots and validation material
  archive/             archived historical material

deprecated/legacy/
  retired experiments and old one-off kits
```

## Architecture Overview

```text
[ArkTS/UI thread]
page state / routing / interaction
  -> refactored* NAPI
  -> libentry.so

[XComponent callback thread]
surface and input callbacks
  -> PluginManager
  -> LibretroEngine::SetNativeWindow / OnNativeWindowResized

[Engine thread]
GameLoop + MessageQueue + StateMachine
  -> retro_run
  -> VideoPipeline::Render
  -> AudioBridge::ProcessAudio

[Audio callback thread]
OHAudio reads from RingBuffer and plays samples

[Event bridge]
EventBridge (C++)
  -> LibretroEventHub (ArkTS)
```

## Why This Is Not Just Another Frontend Shell

Unlike a UI-only wrapper, this repository deals with the hardest HarmonyOS-specific emulator frontend problems:

- `XComponent / NativeWindow` lifecycle handling
- Libretro core loading, switching, failure recovery
- thread boundaries across video and audio paths
- NAPI contracts between ArkTS and C++
- product-page state versus runtime engine state

That is why the repository contains all of the following at once:

- ArkTS pages and product UI
- substantial C++ engine and platform code
- design, audit, verification, and release documentation

## Quick Start

### Environment

- DevEco Studio
- HarmonyOS SDK / Command Line Tools
- a HarmonyOS device or emulator

### Run Locally

1. Open the project in DevEco Studio.
2. Build and run the `entry` module.
3. Enter the import flow or one of the test/runtime pages.
4. Import ROM files you have legal rights to use, then select the appropriate core.

### Local Static Checks

```bash
bash scripts/ci/check_repo_hygiene.sh
bash scripts/ci/check_regression_guards.sh
```

## Documentation Entry Points

- Docs index: `docs/README.md`
- Contributing guide: `CONTRIBUTING.md`
- Security policy: `SECURITY.md`
- Support guide: `SUPPORT.md`

Recommended reading order:

1. this README
2. `docs/README.md`
3. `docs/plans/2026-02-06-new-arch-technical-whitepaper.md`
4. `docs/architecture/`
5. `docs/2026-04-30-design-page-acceptance-matrix.md`

## Main Repository Constraints

- use HarmonyOS official documentation and `libretro.h` as the source of truth
- `deprecated/legacy/` does not participate in mainline evolution
- NativeBuffer pixel access must go through `FromNativeWindowBuffer + Map/Unmap`
- graphics API calls should stay on the engine/render thread
- store builds must not ship bundled ROM samples or risky cover assets

## CI and Release

Current workflows include:

- `ci.yml`: lightweight static guards
- `harmonyos-pr-ci.yml`: PR build gate
- `harmonyos-release.yml`: release flow for `v*` tags
- `harmonyos-device-deploy.yml`: manual deploy flow

## Current Status

This project is no longer at the “only the native core path works” stage, but it is also not at the “every core, every device, every page is fully production-closed” stage.

The most accurate summary today is:

- the native/runtime mainline is strong enough for continued iteration
- the product-layer pages are already present and have runtime screenshot evidence
- compatibility coverage, device validation, long-run stability, and performance are still being tightened

If you want the clearest picture of remaining gaps, start here:

- `Roadmap.md`
- `docs/reference/known-issues.md`
- `docs/2026-04-30-design-page-acceptance-matrix.md`

## License

- repository license: `LICENSE`
- ROMs, cores, artwork, and third-party assets must only be used when the user has the legal right to use them
