# C++ Native Layer — Engine Constraints

This file documents C++ engine constraints enforced in `entry/src/main/cpp/`. Loaded on demand when Claude works under this directory.

For high-level architecture (engine threads, NAPI bridge, audio/video pipelines), see the root `CLAUDE.md`.

## Threading rules (strictly enforced)

- **Graphics API calls** (`OH_NativeWindow_*`, GLES, Vulkan, EGL) **only on Engine thread**.
- **Audio API calls** only on Audio thread (`AudioBridge`).
- **Cross-thread state** protected by locks. Never access engine state from NAPI callbacks without going through the engine message queue.
- See `core/engine/libretro_engine.cpp` for the state machine and message queue patterns.

## NativeBuffer access pattern

- **Always use** `OH_NativeBuffer_FromNativeWindowBuffer` + `OH_NativeBuffer_Map` / `OH_NativeBuffer_Unmap`.
- **Never use** raw `mmap()` / `munmap()` for NativeWindow pixel access — these bypass the HarmonyOS GPU sync and cause artifacts.
- Every `OH_NativeWindow_RequestBuffer` call **must be paired with** `OH_NativeBuffer_FromNativeWindowBuffer` in the same file.
- Every `OH_NativeBuffer_Map` call **must be paired with** `OH_NativeBuffer_Unmap` in the same file.
- Vendored libretro core code in `core/libretro/**` is exempt from these checks (3rd-party).

## LOG_DOMAIN constraints

- Every `#define LOG_DOMAIN N` **must** be preceded by `#undef LOG_DOMAIN` in the same file.
- `N` must be in range `[0xD000, 0xFFFF]` (hilog reserved domain space).
- Each translation unit should use a unique domain to keep `hilog` filtering practical.

## Banned patterns (first-party C++ only)

- `mmap(...)` / `munmap(...)` — replaced by `OH_NativeBuffer_Map/Unmap`.
- Hard-coded `SET_TIMEOUT = 5` — use configurable timeout instead.
- `TODO` / `FIXME` / `HACK` / `XXX` comments — file an issue or fix it before merge.
- `core/libretro/**` is exempt from all banned-pattern checks (vendored upstream code).

All of the above are enforced by `scripts/ci/check_regression_guards.sh` (also wired as a Stop hook).

## Thread model — quick reference

- **Engine thread**: GameLoop + `VideoPipeline` (Hardware/Software/GLES/Vulkan modes, dynamic pixel/geometry negotiation).
- **Audio thread**: `AudioBridge` (resampling, DRC, RingBuffer, underrun stats).
- **NAPI thread**: ArkTS ↔ C++ message exchange. **Do not block.**
- **EventBridge**: Input (keys, joysticks, sensors), SaveState/SRAM/Core Options/Cheat/DiskControl.

## Key source files

- `core/engine/libretro_engine.cpp` — state machine, message queue, `retro_run`
- `core/engine/video_pipeline.cpp` — video pipeline (modes, negotiation)
- `platform/audio/audio_bridge.cpp` — audio bridge
- `app/napi/libretro_engine_napi.cpp` — NAPI exports
- `core/libretro/` — vendored libretro core sources (exempt from regression guards)
