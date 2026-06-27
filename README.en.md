# HarmonyOS Libretro Emulator Frontend (new_arch)

> This document reflects the current repository state (updated on 2026-02-06).

## GitHub Search Keywords

- `harmonyos libretro emulator`
- `openharmony libretro frontend`
- `harmonyos xcomponent emulator`
- `arkts libretro`
- `retroarch harmonyos`
- `harmonyos vulkan gles`

## Project Positioning

This project has evolved from an early Drawing + XComponent double-buffer demo into a practical **Libretro frontend on HarmonyOS**:

- ArkTS/ArkUI handles UI and interaction
- C++ `libentry.so` handles engine, rendering, audio, and input bridging
- XComponent + NativeWindow is used for video output
- NAPI exposes `refactored*` APIs to ArkTS

The active architecture is `new_arch (LibretroEngine + VideoPipeline)`.

## Architecture Overview (Threads + Call Flow)

```text
[ArkTS/UI thread]
Page calls refactoredStartEngine/refactoredLoadCore/refactoredLoadRom
  -> NAPI (entry/src/main/cpp/app/napi/libretro_engine_napi.cpp)
  -> LibretroEngine message queue

[XComponent callback thread]
Surface Created/Changed
  -> PluginManager forwards to LibretroEngine::SetNativeWindow / OnNativeWindowResized

[Engine thread]
LibretroEngine::GameLoop
  -> HandleMessage(Start/LoadCore/LoadRom/...)
  -> core_loader loads the core and binds libretro callbacks
  -> retro_run loop
  -> OnVideoRefresh -> VideoPipeline::Render (CPU/GLES/HW)
  -> audio_sample_batch -> AudioBridge

[Audio callback thread]
OHAudio callback reads from RingBuffer; fills silence on underrun

[Event bridge]
C++ EventBridge -> ArkTS LibretroEventHub
Events include core_crash/fps_update/audio_status/geometry_update/engine_state
```

## Implemented Capabilities

### 1) Engine and Lifecycle

- Dedicated engine thread + message-queue state machine (INIT/LOADING/RUNNING/PAUSED/ERROR, etc.)
- Sync/async stop (`refactoredStopEngine` / `refactoredStopEngineAsync`)
- `refactoredSwitchGameAsync(...)` with token-based debouncing and concurrent-switch protection
- Last-error query/clear (`refactoredGetLastErrorInfo` / `refactoredClearLastErrorInfo`)

### 2) Video Rendering

- `VideoPipeline` modes:
  - `0` Hardware Scaling
  - `1` Software Scaling
  - `2` GLES Scaling (default)
- Handles `SET_PIXEL_FORMAT`, `SET_GEOMETRY`, and dupe/null frames
- HW render negotiation paths:
  - OpenGL ES HW context
  - Vulkan negotiation/interface (including swapchain recreate and out-of-date handling)
- Runtime controls in ArkTS: scaling mode, software max resolution, HW render allowance

### 3) Audio Pipeline

- `AudioBridge` + OHAudio low-latency playback
- Resampling, buffer-usage metrics, underrun/overrun stats
- Minimum audio latency configuration (core-side request in `retro_run` context)
- `audio_status` events sent back to ArkTS

### 4) Input System

- Digital input: `refactoredSendInput`
- Analog sticks: `refactoredSendAnalog`
- Sensors: `refactoredSendSensor`
- Port mapping: `refactoredAssignPortSource` / `refactoredUnassignPort`
- Device listing and input debug stats: `refactoredListInputDevices` / `refactoredGetInputDebugStats`

### 5) State and Core Control

- Save State: `refactoredGetSaveStateSize` / `refactoredSaveState` / `refactoredLoadState`
- SRAM: `refactoredGetSRAM` / `refactoredSetSRAM`
- Core Options: `refactoredGetCoreOptions` / `refactoredSetCoreOption`
- Cheat, Disk Control, Region, AVInfo, and Runtime Stats are exposed

## UI Pages and Scenarios

Current pages in `entry/src/main/resources/base/profile/main_pages.json`:

- `pages/Index`: main entry
- `pages/CoreLoaderTest`: core loading test
- `pages/TestGambatte`: Gambatte test page
- `pages/LibretroGamePage`: general multi-core gameplay page (primary)
- `pages/LibretroNewArchTestPage`: new-architecture debug/validation page

`LibretroGamePage` already includes a built-in multi-core list, automatic ROM matching rules, soak test entry, and core symbol validation.

## Core and ROM Asset Status

### Core `.so`

- Directory: `entry/libs/arm64-v8a/`
- The current development repository contains multiple bundled core binaries for bring-up and compatibility work.
- Any store-release build should review those binaries individually for redistribution rights, required notices, and product-scope fit before shipping.

### ROM

- Store-release builds should rely on user-imported ROM files stored in the app sandbox.
- Bundled rawfile ROM samples and bundled cover-art placeholders have been removed from the repository's release path, and `scripts/ci/check_release_readiness.sh` blocks them from being reintroduced into the working tree.
- Production use should rely on ROM files imported by the user, with the user responsible for having legal rights to that content.

## Quick Start

1. Open the project in DevEco Studio.
2. Build/Run the `entry` module (`module.json5` currently targets `phone`).
3. From `Index`, start with `LibretroGamePage` or `LibretroNewArchTestPage`.
4. Select core + ROM, then observe runtime state via events/logs.

## Critical Contributor Constraints

- Official docs first: when in doubt, check HarmonyOS official docs and `libretro.h`
- NativeBuffer pixel access must follow `OH_NativeBuffer_FromNativeWindowBuffer + Map/Unmap`
- Cross-thread shared state must be guarded explicitly (`std::mutex + std::lock_guard`)
- Legacy architecture is archived under `deprecated/legacy/` and is not the default evolution path

## Directory Map

```text
entry/src/main/cpp/
  app/                 NAPI exports, XComponent callback bridge
  core/                LibretroEngine, VideoPipeline, env/core loader
  platform/            audio/graphics/resource/sync/xcomponent adapters
  interfaces/          abstract interfaces
  tests/               C++ integration/unit helpers (not a standalone auto test framework)
  types/libentry/      ArkTS typings (index.d.ts)

entry/src/main/ets/
  pages/               home, test pages, general game page
  components/          virtual controller, foldable layout components
  common/              EventHub, logging, switch coordinator
  config/              emulator metadata config

build/
  test-roms/           optional local-only ROM fixtures for M3 manifest generation (gitignored; never shipped)
```

## Known Limitations

- HW render support exists, but stability/performance still varies by core/device combination
- Shipping multiple cores does not imply all are fully playable on every target
- Release readiness still requires device-specific stability validation (switching, background/foreground, rotation, long-run)
- Store release readiness also requires copyright clearance for bundled assets, hosted privacy-policy pages, end-user legal documents, final screenshots, and audited store metadata. See `docs/release/`.

---

For implementation details, start with:

- `entry/src/main/cpp/core/engine/libretro_engine.h`
- `entry/src/main/cpp/core/engine/video_pipeline.h`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`

## CI and Automated Regression

The repository now uses two CI layers:

- Lightweight static guards: `.github/workflows/ci.yml` (`push`/`pull_request`)
- PR build gate: `.github/workflows/harmonyos-pr-ci.yml` (`pull_request`)

`ci.yml` runs:

- `scripts/ci/check_repo_hygiene.sh`
  - merge conflict marker scan
  - tracked build/cache output scan
  - shell script syntax validation
- `scripts/ci/check_regression_guards.sh`
  - NativeBuffer safety guards (forbid `mmap/munmap`, require `FromNativeWindowBuffer + Map/Unmap`)
  - `LOG_DOMAIN` compliance (`#undef LOG_DOMAIN` present and value in `0xD000-0xFFFF`)
  - forbid hard-coded `SET_TIMEOUT=5`
  - TODO/FIXME/HACK/XXX marker scan in first-party source

`harmonyos-pr-ci.yml` adds:

- HarmonyOS Command Line Tools setup
- codelinter quality gate
- `hvigorw assembleHap` build
- HAP smoke checks (`module.json` / `ets/modules.abc` / `libentry.so`)
- PR artifact upload and codelinter report upload

Run locally:

```bash
bash scripts/ci/check_repo_hygiene.sh
bash scripts/ci/check_regression_guards.sh
```

## Release and Deploy Pipelines (HarmonyOS)

Release and deploy are split into three workflows:

- `harmonyos-pr-ci.yml`: PR quality gates
- `harmonyos-release.yml`: automatic build/sign/release for `v*` tags
- `harmonyos-device-deploy.yml`: manual deploy to self-hosted devices from a selected run

Legacy compatibility:

- `harmonyos-full-ci.yml`: manual-only legacy full pipeline

### Triggers

- PR gate: open/update a pull request
- Auto release: push a `v*` tag
- Manual device deploy: run `harmonyos-device-deploy.yml` via `workflow_dispatch`

### Required variable (configure at least one)

- `secrets.HARMONY_COMMANDLINE_TOOLS_URL` or `vars.HARMONY_COMMANDLINE_TOOLS_URL`

Optional checksum:

- `secrets.HARMONY_COMMANDLINE_TOOLS_SHA256` or `vars.HARMONY_COMMANDLINE_TOOLS_SHA256`

### Private Download Authentication (Optional)

If your Command Line Tools are hosted in a private location (for example, private GitHub Release assets or private object storage), configure:

- `HARMONY_COMMANDLINE_TOOLS_AUTH_TOKEN` (recommended)
- `HARMONY_COMMANDLINE_TOOLS_AUTH_SCHEME` (default: `Bearer`)
- `HARMONY_COMMANDLINE_TOOLS_AUTH_HEADER` (use this when you already have a full header, e.g. `Authorization: token xxx`)
- `HARMONY_COMMANDLINE_TOOLS_AUTH_ACCEPT` (optional, e.g. `application/octet-stream`)

For private GitHub Release assets, prefer the API asset URL:

`https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}`

The script will automatically add `Accept: application/octet-stream` and use your configured token/header.
If no `AUTH_*` value is configured and the URL is under `api.github.com`, the workflow falls back to `GITHUB_TOKEN` automatically (recommended for same-repo assets).

### Signing secrets (required by `harmonyos-release.yml`)

- `HARMONY_SIGN_KEYSTORE_B64` (base64 of `.p12`)
- `HARMONY_SIGN_CERT_B64` (base64 of `.cer`)
- `HARMONY_SIGN_PROFILE_B64` (base64 of `.p7b`)
- `HARMONY_SIGN_KEY_ALIAS`
- `HARMONY_SIGN_KEY_PWD`
- `HARMONY_SIGN_KEYSTORE_PWD`

### Production Approval and Notifications (Optional)

- `harmonyos-release.yml` uses `environment: production`
  - If `production` has required reviewers configured, release waits for manual approval
- Optional release webhook:
  - `secrets.RELEASE_NOTIFY_WEBHOOK_URL` or `vars.RELEASE_NOTIFY_WEBHOOK_URL`
  - On success, the workflow sends JSON with `tag/release_url/run_url/commit`

### Manual Device Deploy Inputs (`harmonyos-device-deploy.yml`)

- `source_run_id` (required): run id containing HAP artifacts
- `artifact_name` (default: `harmonyos-hap`)
- `hap_glob` (default: `*-signed.hap`)
- `app_bundle_name` / `app_ability_name` / `app_module_name`
