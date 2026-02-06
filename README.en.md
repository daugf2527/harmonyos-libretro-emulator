# HarmonyOS Libretro Frontend (new_arch)

> This document reflects the current repository state (updated on 2026-02-06).

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
- The repository currently ships many cores (e.g., Gambatte, Nestopia, FCEUmm, Snes9x, mGBA, melonds, FBNeo, MAME2010, PCSX-ReARMed, etc.)
- Actual usability depends on device capability, core behavior, and ROM completeness

### ROM

- Built-in rawfile directory: `entry/src/main/resources/rawfile/roms/`
- Existing subfolders are grouped by platform (e.g., `gb_gbc/`, `gba/`, `nes/`, `snes/`, `md/`, `arcade/`, `nds/`)
- `LibretroGamePage` scans `roms/` and maps available cores using extension rules

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

entry/src/main/resources/
  rawfile/roms/        built-in ROM assets
```

## Known Limitations

- HW render support exists, but stability/performance still varies by core/device combination
- Shipping multiple cores does not imply all are fully playable on every target
- Release readiness still requires device-specific stability validation (switching, background/foreground, rotation, long-run)

---

For implementation details, start with:

- `entry/src/main/cpp/core/engine/libretro_engine.h`
- `entry/src/main/cpp/core/engine/video_pipeline.h`
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `entry/src/main/ets/common/LibretroEventHub.ets`
