# napi-boundary-reviewer learnings

Accumulated project-specific knowledge across review sessions. v2.1.33+
Claude Code auto-loads this when the agent is dispatched; older clients
should Read it manually before invoking the reviewer.

Append findings at the bottom under `## Review session log` — do not
overwrite earlier entries.

## Project-specific NAPI invariants

- **56 functions / 6 modules** — `libretro_engine_napi.cpp:10` carries the
  inventory comment. After any new function add, recount via:
  `grep -c 'DECLARE_NAPI_FUNCTION\|napi_define_properties' entry/src/main/cpp/app/napi/engine_*_napi.cpp core_loader_napi.cpp`
  (macro names may differ — check `engine_napi_common.h`).
- **4 thread classes** — NAPI / Engine / Audio / EventBridge.
  - Engine thread owns `OH_NativeWindow_*` / GLES / Vulkan / EGL **exclusively**.
  - NAPI thread MUST NOT block; calls into engine go through `messageQueue_`.
- **TSFN canonical wrapper**: `core/engine/event_bridge.cpp` `EventBridge::Emit`
  is the project's only legal cross-thread → ArkTS callback path. Direct
  `napi_call_function` from `GameLoop` / audio callbacks / `OnVideoRefresh`
  is a HARD block-level violation.
- **`napi_env` is NAPI-thread-only for the current call** — storing for
  cross-thread use later is use-after-free.

## Common mistakes (review priors)

- `napi_get_value_int32` on a value ArkTS sends as float — silently truncates.
- `napi_get_value_string_utf8` missing the size-then-write pattern (two calls:
  first with `nullptr` to get size, then allocate, then write).
- `ArrayBuffer` data pointer kept after the ArkTS object goes out of scope —
  must copy if the C++ side wants to retain it.
- NAPI function silently returns `undefined` / `false` on failure without
  `napi_throw_error` — hides bugs on the ArkTS side.
- `napi_create_reference` not paired with `napi_delete_reference` in
  `Reset()` / `Stop()` — engine restart leaks refs from the previous lifecycle.
- New NAPI function added but `libretro_engine_napi.cpp:10` "56 functions"
  comment not updated.

## Patterns to flag in diffs

- `napi_env env_ = ...;` member field — confirm only re-touched on NAPI thread.
- `engine->ProcessFrame()` / direct engine method call from a NAPI function —
  must go through `messageQueue_`, not direct.
- `engine_->WaitForState(..., timeoutMs)` from NAPI thread without a timeout
  argument — never block indefinitely on the NAPI thread.

## Review session log

<!-- Append per-session findings here. Format:
     ### YYYY-MM-DD topic
     - [HIGH/MEDIUM/LOW] file:line — finding summary
       Suggested fix: ...
-->
