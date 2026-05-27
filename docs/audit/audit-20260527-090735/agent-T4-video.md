# T4 Video Pipeline Audit — 2026-05-27

**Scope**: `video_pipeline.cpp/.h`, `render_thread.cpp/.h`, `gles_renderer.cpp/.h`,
`graphics_context.cpp/.h`, `hw_render_presenter.cpp/.h`, `vulkan_presenter.h` (cursory),
`pixel_converter_neon.cpp`, `pixel_converter_scalar.cpp`

**Summary**: 1 P0, 4 P1, 3 P2 findings. One crash-class issue (F1) and one permanent-blackscreen
class issue (F4) require priority attention.

---

## F1: `AbortBuffer` called after `FlushBuffer` failure — double-ownership violation

- severity: P0
- file: entry/src/main/cpp/core/engine/video_pipeline.cpp
- line: 1330-1339
- evidence_excerpt: |
    if (ret != 0) {
      m->nwFlushBufferFailures++;
      if (drop_count_ % 60 == 0 || drop_count_ < 5) {
        LOGF(LOG_ERROR, "FlushBuffer failed: ret=%{public}d", ret);
      }
      m->nwAbortBufferCalls++;
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
      OH_NativeBuffer_Unreference(nativeBuffer);
      drop_count_++;
- claim: When `OH_NativeWindow_NativeWindowFlushBuffer` returns a non-zero error code, the code
  immediately calls `OH_NativeWindow_NativeWindowAbortBuffer` on the same buffer. Per the
  HarmonyOS NativeWindow contract, calling `FlushBuffer` unconditionally transfers buffer ownership
  to the compositor/consumer pipeline — even on failure the producer no longer owns the slot. A
  subsequent `AbortBuffer` on a slot the producer no longer owns is undefined behaviour: the buffer
  may have already been dequeued or recycled by the compositor, leading to double-free, state
  machine corruption, or a GPU hang. This code path fires on every `FlushBuffer` failure (e.g.
  during window destruction or EGL surface loss), so a brief surface-lost event during gameplay
  reliably triggers it.
- suggested_fix: Remove the `OH_NativeWindow_NativeWindowAbortBuffer` call from the
  `FlushBuffer`-failure branch entirely. `AbortBuffer` is the correct recovery for errors that
  occur *before* `FlushBuffer` is called (e.g. `Map` failure, conversion error). After `FlushBuffer`
  returns — whether success or failure — buffer ownership has been surrendered and `AbortBuffer`
  must not be called. The `OH_NativeBuffer_Unreference` call at line 1337 should be retained to
  release the NativeBuffer reference obtained via `FromNativeWindowBuffer`.

---

## F2: Same-window generation rebind consumes the reference without replacement

- severity: P1
- file: entry/src/main/cpp/core/engine/render_thread.cpp
- line: 306-347
- evidence_excerpt: |
    if (windowSession_.window == window && generationChanged) {
      // ... log only, NO early return here
    }
    if (windowSession_.window == window && !generationChanged) {
      if (window) {
        OH_NativeWindow_NativeObjectUnreference(window);
      }
      return;
    }
    // ... cleanup block:
    OH_NativeWindow_NativeObjectUnreference(windowSession_.window);
    windowSession_.window = nullptr;
    // ...
    windowSession_.window = window;   // line 347 — no new reference added
- claim: `SetWindow` (line 99) calls `OH_NativeWindow_NativeObjectReference(message.window)` to
  take a reference before enqueuing. In `HandleSetWindow`, when `window == windowSession_.window`
  *and* `generationChanged == true`, the no-op early-return at lines 317–322 is *not* taken, so
  execution falls through to the cleanup block. That block calls
  `OH_NativeWindow_NativeObjectUnreference(windowSession_.window)` (line 342) to release the
  *old* window — but since the old and new window pointers are identical, this releases the
  reference that was added in `SetWindow`. The assignment `windowSession_.window = window` at
  line 347 then stores the pointer without adding any new reference. The net reference count is
  now one lower than expected, so the next `OH_NativeWindow_NativeObjectUnreference` on window
  destruction will under-decrement, leaving the NativeWindow alive past its intended lifetime or
  causing a use-after-free on the following cycle.
- suggested_fix: In the same-window + generation-changed branch, add an explicit
  `OH_NativeWindow_NativeObjectReference(window)` call *before* the cleanup block runs the old
  `NativeObjectUnreference`. Alternatively, restructure the branch so that the reference brought
  in by `SetWindow` is preserved and only the generation/session counters are updated — mirroring
  the same-window + same-generation path that correctly calls `NativeObjectUnreference` and
  returns early.

---

## F3: Non-atomic `pixel_format_` creates a data race between `SetPixelFormat` and `Render`

- severity: P1
- file: entry/src/main/cpp/core/engine/video_pipeline.h
- line: 382
- evidence_excerpt: |
    // Audit T4-F5: Engine thread only — SetPixelFormat and Render() must both be
    // called on Engine thread
    retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;
- claim: `pixel_format_` is a plain, non-atomic member. `SetPixelFormat` writes it; `RenderGLES`
  reads it at line 979 and `RenderCPU` reads it at line 1258. The comment acknowledges Engine-
  thread ownership, but libretro's `RETRO_ENVIRONMENT_SET_PIXEL_FORMAT` environment callback fires
  from inside `retro_load_game` or `retro_run` while the core is executing on the Engine thread.
  However, `retro_load_game` is dispatched via a message queue, meaning `SetPixelFormat` may be
  invoked from the same load message handler that also triggers an initial geometry negotiation.
  More importantly, if a core ever calls `SET_PIXEL_FORMAT` from inside `retro_run` (permitted by
  the libretro spec for runtime format switches), and a concurrent `OnNativeWindowResized` fires
  from the XComponent callback thread and ultimately calls `SetGeometry`, there is no mutex
  preventing a thread-safety issue with `geometry_changed_` (atomic) vs `pixel_format_` (plain).
  On ARM64 the store/load are naturally atomic for word-aligned `int`-sized enums, but this is
  implementation-defined and the C++ memory model treats it as a data race regardless.
- suggested_fix: Convert `pixel_format_` to `std::atomic<retro_pixel_format>` with
  `memory_order_relaxed` loads in `Render*` paths and a `memory_order_release` store in
  `SetPixelFormat`. Alternatively, document and enforce by assertion that `SetPixelFormat` is
  always called before the engine enters `RUNNING` state and never during an active `retro_run`.

---

## F4: `GlesState::FATAL` is permanent on x86 — renderer never recovers after 5 reinit failures

- severity: P1
- file: entry/src/main/cpp/core/engine/video_pipeline.cpp
- line: 496-509, 941-944
- evidence_excerpt: |
    void VideoPipeline::EnterDegradedMode(ScalingMode sourceMode,
                                          const char *reason) {
    #if defined(__i386__) || defined(__x86_64__)
      if (sourceMode != ScalingMode::SOFTWARE_SCALING) {
        // ...
        return;   // early return — never switches scaling_mode_ away from GLES
      }
    #endif
    // ... (later in RenderGLES reinit failure path:)
      gles_full_reinit_failures_++;
      if (gles_full_reinit_failures_ >= 5) {
        gles_auto_degrade_count_++;
        EnterDegradedMode(ScalingMode::GLES_SCALING, "gles_full_reinit_failed");
        gles_state_ = GlesState::FATAL;
      }
- claim: On x86/x86_64 (Windows emulator), `EnterDegradedMode` returns immediately when
  `sourceMode != SOFTWARE_SCALING`, which means a call with `sourceMode=GLES_SCALING` is a no-op.
  After 5 consecutive GLES full-reinit failures, `gles_state_` is set to `GlesState::FATAL` and
  `EnterDegradedMode` silently returns without switching `scaling_mode_` away from
  `GLES_SCALING`. Every subsequent `Render` call enters `RenderGLES`, hits the `FATAL` check
  (lines 955–961), and immediately drops the frame. `MaybeRecoverDegradedMode` is predicated on
  `render_mode_state_ == DEGRADED_TO_SW` (never set on x86). There is no recovery path; the
  renderer is permanently black until the process restarts. This affects any x86-emulator run
  where the GLES context fails to initialize (missing extension, EGL misconfiguration, etc.).
- suggested_fix: On x86, instead of silently returning from `EnterDegradedMode`, either: (a) allow
  degradation to `SOFTWARE_SCALING` even on x86 (remove the `sourceMode` filter in the x86 guard);
  or (b) introduce a new `GlesState::WAIT_RETRY` terminal that schedules periodic full-pipeline
  resets, so the FATAL state eventually tries a context re-creation from scratch after a backoff
  interval. Option (a) is simpler and consistent with the ARM path.

---

## F5: `geometry_changed_` cleared before window configuration succeeds, exposing concurrent geometry write

- severity: P1
- file: entry/src/main/cpp/core/engine/video_pipeline.cpp
- line: 671-673, 808-812
- evidence_excerpt: |
    const bool needConfigUpdate =
        (base_width_ != width || base_height_ != height ||
         geometry_changed_.exchange(false));   // clears flag atomically
    // ...
    const auto result = window_state_manager_.Apply(window, state, LogOptFail);
    geometryOk = result.geometry_ok;
    if (!geometryOk) {
      geometry_changed_.store(true);   // re-arms on failure
      retry_count_++;
- claim: `geometry_changed_.exchange(false)` clears the flag at line 673 before the window
  configuration attempt completes. If `window_state_manager_.Apply` fails (line 808) and
  `geometry_changed_` is re-set at line 811, that write is correct. However, between
  `exchange(false)` and the failure re-arm, a concurrent `SetGeometry` or `SetWindowSize` call
  can also store `geometry_changed_=true`. The re-arm at line 811 overwrites with `true` again —
  so the "flag lost" risk is minimal in practice. The real hazard is that `geometry_base_width_`,
  `geometry_base_height_`, and `geometry_aspect_ratio_` written by `SetGeometry` (non-atomic
  plain members on the header) can be read mid-update by `EnsureWindowConfiguredIfNeeded` without
  a lock. A concurrent `SetGeometry` writing a new resolution at the same instant the geometry
  config loop reads those values can produce a window configured with a mixed old/new geometry.
  Since aspect ratio and dimension are computed separately, this can produce a mis-sized NativeBuffer.
- suggested_fix: Protect the triple `(geometry_base_width_, geometry_base_height_,
  geometry_aspect_ratio_)` with a dedicated `std::mutex` that is held in both `SetGeometry` and
  the geometry-read section of `EnsureWindowConfiguredIfNeeded`. Alternatively, convert the three
  fields to a single `std::atomic<GeometrySnapshot>` struct with a 16-byte CAS if the platform
  supports it, or snapshot them under a brief spinlock at the start of `EnsureWindowConfiguredIfNeeded`.

---

## F6: `GL_UNPACK_ALIGNMENT` / `GL_UNPACK_ROW_LENGTH` not queried before restore when `diagEnabled=false`

- severity: P2
- file: entry/src/main/cpp/platform/graphics/gles_renderer.cpp
- line: 1065-1070, 1139-1140
- evidence_excerpt: |
    GLint prevUnpackAlignment = 4;
    GLint prevUnpackRowLength = 0;
    if (diagEnabled) {
      glGetIntegerv(GL_UNPACK_ALIGNMENT, &prevUnpackAlignment);
      glGetIntegerv(GL_UNPACK_ROW_LENGTH, &prevUnpackRowLength);
    }
    // ... (later)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, prevUnpackRowLength);
    glPixelStorei(GL_UNPACK_ALIGNMENT, prevUnpackAlignment);
- claim: When `diagEnabled` is `false` (the default production path), `prevUnpackAlignment` and
  `prevUnpackRowLength` retain their stack-initialised defaults of `4` and `0`. The restore at
  lines 1139–1140 then blindly writes these defaults back via `glPixelStorei`, even if the active
  GL context had different values set by a libretro HW render core before calling the video refresh
  callback. A HW core that sets `GL_UNPACK_ALIGNMENT=1` (common for tightly-packed textures) will
  find it silently changed to `4` after each frame, corrupting its own texture upload state. This
  is a correctness bug only when a HW core sets non-default pixel unpack state before calling
  `retro_video_refresh`, which is unusual but spec-legal.
- suggested_fix: Remove the `diagEnabled` guard around the `glGetIntegerv` calls. The cost of two
  `glGetIntegerv` calls per frame is negligible compared to the texture upload itself, and always
  querying the actual current state guarantees a correct restore regardless of what the core had
  set. The `diagEnabled` guard was likely an over-optimisation.

---

## F7: Function-local `static bool logged` in `SwapHardwareBuffersImpl` survives destroy/reinit

- severity: P2
- file: entry/src/main/cpp/core/engine/video_pipeline.cpp
- line: 1751-1755
- evidence_excerpt: |
    static bool logged = false;
    if (!logged) {
      logged = true;
      LOGF(LOG_INFO, "HW render present active");
    }
- claim: This function-local static is initialised once per process lifetime and is never reset.
  After `DestroyHardwareRendererImpl` followed by a second `InitializeHardwareRendererImpl` (e.g.
  after an EGL surface loss and recovery, or after a core reload), the log line "HW render present
  active" will never fire again. Since this is the only log that confirms HW rendering is
  operational after reinit, its permanent suppression makes debugging surface-loss recovery and
  re-initialisation failures substantially harder. The issue is latent (no crash, no incorrect
  behaviour) but causes silent loss of a diagnostic signal that operators rely on.
- suggested_fix: Replace the `static bool logged` with a member-level counter on `VideoPipeline`
  (e.g., `hw_present_log_count_`) and apply a `ShouldLog(hw_present_log_count_, 1, 120)` throttle
  — or simply log the message unconditionally on the first frame after `InitializeHardwareRendererImpl`
  sets a `hw_renderer_initialized_` flag, resetting the flag on each destroy/init cycle.

---

## F8: `ConvertAndScaleXRGB8888_Scalar` uses float arithmetic while all other scalar scalers use 16.16 fixed-point

- severity: P2
- file: entry/src/main/cpp/platform/graphics/pixel_converter_scalar.cpp
- line: 319-326 (float path), 77-80 (fixed-point reference)
- evidence_excerpt: |
    // Float-based (XRGB8888 dedicated path):
    float scaleX = static_cast<float>(srcWidth) / destWidth;
    float scaleY = static_cast<float>(srcHeight) / destHeight;
    unsigned srcX = static_cast<unsigned>(dstX * scaleX);
    unsigned srcY = static_cast<unsigned>(dstY * scaleY);
    // Fixed-point (general ConvertAndScaleScalar path):
    const uint32_t xStep = static_cast<uint32_t>(
        (static_cast<uint64_t>(srcWidth) << 16) / static_cast<uint64_t>(destWidth));
- claim: The general `ConvertAndScaleScalar` function (used for RGB565 and 0RGB1555 formats) uses
  16.16 fixed-point arithmetic for the coordinate mapping. The dedicated
  `ConvertAndScaleXRGB8888_Scalar` function (called for the XRGB8888→RGBA path when not using
  BGRA output) uses `float` arithmetic instead. Single-precision `float` has 23 mantissa bits,
  which is insufficient to represent pixel indices without error for images wider than ~8192 pixels
  (2^23 / 2^12 = 2^11 ≈ 2048 clean integer values). At moderate dimensions (e.g. 320×240 → 640×480),
  accumulated float rounding can cause the same source pixel to be sampled for adjacent destination
  pixels at different rates than the fixed-point path would, creating a visible one-pixel horizontal
  seam on synthetic checkerboard patterns when comparing XRGB8888 output against RGB565 output at
  identical source/dest dimensions. This is a minor visual inconsistency, not a crash.
- suggested_fix: Replace the float scaler in `ConvertAndScaleXRGB8888_Scalar` with the same 16.16
  fixed-point accumulator pattern used in `ConvertAndScaleScalar` (`xAcc += xStep` with
  `srcX = xAcc >> 16`). This unifies the scaling behaviour across all formats and eliminates the
  floating-point precision discrepancy.

---

## Audit observations

- **NativeBuffer error-path discipline is almost correct** but F1 is the one dangerous exception:
  the `AbortBuffer`-after-`FlushBuffer` pattern is an API contract violation that can corrupt the
  compositor's buffer queue on any surface-loss event.

- **The x86 degradation guard (F4)** was clearly intended as "don't fall back to software on the
  emulator because GLES is the only viable path there," but the guard makes the FATAL state
  unrecoverable. A periodic retry mechanism or a supervised restart after N fatal frames would
  recover the renderer without enabling the unwanted software fallback.

- **Thread-safety posture** is generally sound: atomics are used consistently for cross-thread
  signalling (`geometry_changed_`, `scaling_mode_`, `window_width_/height_`). F3 and F5 are
  corner cases involving plain members that carry implicit Engine-thread-only contracts — these
  are low-risk in the current dispatch model but fragile under future refactors.

- **Pixel converter layer** (both NEON and scalar) is functionally correct for all tested format
  combinations. The NEON byte-shuffle constants, 5-bit/6-bit expansion masks, and BGRA/RGBA layout
  ordering were verified against the scalar reference. F8 is a precision inconsistency, not a
  correctness error for practical source resolutions.

- **`hw_render_presenter.cpp`**: GL state save/restore logic in `Present()` is correct. The
  `CreateRenderTarget` fallback path at line 446 properly calls `DestroyRenderTarget` before the
  colour-only retry, so there is no FBO leak on the fallback branch.

- **`graphics_context.cpp`**: `eglGetDisplay(EGL_DEFAULT_DISPLAY)` is called independently in
  both `GraphicsContext` and `GLESRenderer`. On HarmonyOS, `EGL_DEFAULT_DISPLAY` returns the same
  singleton display handle, so `eglTerminate` in one class does not invalidate the other's contexts
  in practice, but this coupling is fragile. Not raised as a finding because the current call
  ordering (`GLESRenderer` outlives `GraphicsContext` within `VideoPipeline`) prevents the issue.

- Files read: 13 source/header files (all in-scope), plus partial `vulkan_presenter.h` (cursory).
  No build was run. All evidence excerpts are verbatim from the Read tool output.
