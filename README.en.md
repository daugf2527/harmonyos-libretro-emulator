# HarmonyOS Libretro Frontend (new_arch)

## Overview

This repository has evolved from a Drawing + XComponent double-buffering sample into a **Libretro frontend on HarmonyOS**.
The current mainline is **new_arch (LibretroEngine + VideoPipeline)**, using XComponent to obtain a NativeWindow and drive core loading, audio/video output, input, and event callbacks.

## Current Capabilities (Code-Based)

- Engine mainline: `LibretroEngine` + `VideoPipeline` (dedicated thread + message queue)
- Rendering paths: CPU / GLES scaling modes (Hardware/Software/GLES)
- Audio: `AudioBridge` + OHAudio low-latency playback + resampling + DRC
- Input: virtual controller / keyboard / touch / pointer mapped to Libretro input
- Event bridge: fps/geometry/audio_status/core_crash events sent back to ArkTS
- Debugging/validation: soak test, runtime stats, core options read/write

## Currently Verified Content

- Core: Gambatte (`libgambatte_libretro.so`)
- ROMs: built-in rawfiles under `entry/src/main/resources/rawfile/roms/`
- Entry pages: `pages/LibretroGamePage`, `pages/LibretroNewArchTestPage`

## How to Run

- Use DevEco Studio to **Build / Run** the `entry` module.
- Place core `.so` files under `entry/libs/arm64-v8a/` (packaged by the system).
- ROM sources:
  - rawfile paths (`roms/...`)
  - sandbox paths (must pass `file_security` whitelist)

## Project Structure (Actual)

```
├──entry/src/main/cpp
│  ├──app                      // NAPI exports and XComponent callbacks
│  ├──core                     // libretro core and new_arch engine
│  ├──platform                 // audio/graphics/resource adapters
│  ├──common                   // shared utils and security checks
│  ├──interfaces               // interfaces
│  ├──tests                    // integration/unit helpers (not built by default)
│  └──types/libentry           // NAPI typings
├──entry/src/main/ets
│  ├──pages                    // entry/test/game pages
│  ├──components               // virtual controller + foldable layouts
│  ├──common                   // logger/EventHub/switch coordinator
│  └──config                   // emulator config data
├──entry/src/main/resources
│  └──rawfile/roms             // bundled ROMs
└──Roadmap.md                  // milestones and planning
```

## Known Limitations

- HW_RENDER interface is not complete (`GET_HW_RENDER_INTERFACE` still returns false).
- 3D hardware cores are not declared supported yet; software cores are the focus.
- Multi-core/ROM management is still in progress.

## Notes

- Legacy architecture is archived under `deprecated/legacy/`.
- This repo follows HarmonyOS official docs and the Libretro standard.
