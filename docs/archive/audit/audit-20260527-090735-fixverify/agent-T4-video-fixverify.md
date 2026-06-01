# T4 Video Pipeline — Fix Verification Report

**Audit round**: 2026-05-27 (original: `audit-20260527-090735/agent-T4-video.md`)
**Verifier**: static read-only pass — no build, no file modification.
**Files read**: `video_pipeline.cpp`, `video_pipeline.h`, `render_thread.cpp`,
`gles_renderer.cpp`, `pixel_converter_scalar.cpp`

---

## F1: `AbortBuffer` called after `FlushBuffer` failure — double-ownership violation

- verdict: FIXED
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- line: 1327–1341 (FlushBuffer-failure branch)
- evidence_excerpt:
  ```
  // line 1327
  if (ret != 0) {
    m->nwFlushBufferFailures++;
    if (drop_count_ % 60 == 0 || drop_count_ < 5) {
      LOGF(LOG_ERROR, "FlushBuffer failed: ret=%{public}d", ret);
    }
    // Audit T4-F1: do NOT call OH_NativeWindow_NativeWindowAbortBuffer after a failed FlushBuffer.
    // Per external_window.h, both FlushBuffer and AbortBuffer are producer ownership-release
    // operations on the same buffer; HarmonyOS does not document buffer ownership semantics
    // when FlushBuffer fails, so the safest assumption is that the buffer queue has already
    // taken ownership (success or failure of the flush). Calling AbortBuffer afterwards risks
    // double-release / state-machine corruption on the consumer pipeline.
    OH_NativeBuffer_Unreference(nativeBuffer);    // line 1338
    drop_count_++;
    return RenderResult::DROPPED;
  }
  ```
- notes: Both `OH_NativeWindow_NativeWindowAbortBuffer(window, buffer)` and `m->nwAbortBufferCalls++`
  are completely absent from the FlushBuffer-failure branch. The `// Audit T4-F1` comment block
  documents the HarmonyOS contract reasoning. `OH_NativeBuffer_Unreference(nativeBuffer)` is
  retained as required. All other `AbortBuffer` callsites in the same function (lines 1048, 1074,
  1102, 1119, 1142, 1156, 1170, 1193, 1311) occur legitimately *before* `FlushBuffer` is called —
  specifically in the `OH_NativeBuffer_Unmap` failure branch (line 1311) and pre-conversion error
  branches — so those remaining calls are correct.

---

## F2: Same-window generation rebind consumes reference without replacement

- verdict: FALSE_POSITIVE_CONFIRMED
- file: `entry/src/main/cpp/core/engine/render_thread.cpp`
- line: 301–347
- evidence_excerpt:
  ```
  // line 301
  void RenderThread::HandleSetWindow(OHNativeWindow *window, uint64_t generation) {
    static uint32_t windowSessionLogCount = 0;
    const bool generationChanged =
        (generation > 0 && generation != windowSession_.generation);
    if (windowSession_.window == window && generationChanged) {
      // log only, NO early return, NO NativeObjectReference added
      ...
    }
    if (windowSession_.window == window && !generationChanged) {
      if (window) {
        OH_NativeWindow_NativeObjectUnreference(window);
      }
      return;
    }
    // cleanup block:
    OH_NativeWindow_NativeObjectUnreference(windowSession_.window); // line 342
    windowSession_.window = nullptr;
    ...
    windowSession_.window = window;   // line 347 — no new reference added
  ```
- notes: Code at lines 306–347 is **identical** to what the original audit cited. No
  `OH_NativeWindow_NativeObjectReference` has been added in the generation-changed branch. The
  core-review decision (ownership-transfer pattern is intentional) stands. The finding is
  correctly classified as FALSE_POSITIVE; the original ref-count reasoning was incorrect.

---

## F3: Non-atomic `pixel_format_` data race between `SetPixelFormat` and `Render`

- verdict: N/A_MITIGATED
- file: `entry/src/main/cpp/core/engine/video_pipeline.h`
- line: 381–382
- evidence_excerpt:
  ```
  // line 381
  // Audit T4-F5: Engine thread only — SetPixelFormat and Render() must both be
  // called on Engine thread
  retro_pixel_format pixel_format_ = RETRO_PIXEL_FORMAT_0RGB1555;
  ```
- notes: Declaration is unchanged. Still a plain (non-atomic) member with an Engine-thread-only
  comment. No mutex or `std::atomic` conversion was applied; the mitigation decision was to rely
  on single-Engine-thread dispatch policy. No regression introduced.

---

## F4: `GlesState::FATAL` permanent on x86 — renderer never recovers after 5 reinit failures

- verdict: FIXED
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- line: 494–503 (`EnterDegradedMode`)
- evidence_excerpt:
  ```
  // line 494
  void VideoPipeline::EnterDegradedMode(ScalingMode sourceMode,
                                        const char *reason) {
  #if defined(__i386__) || defined(__x86_64__)
    // Audit T4-F4: previously x86 emulator paths refused to degrade to SW from GLES,
    // which made GlesState::FATAL terminal — the renderer stayed permanently black after
    // 5 reinit failures. Allow degradation on x86 too, otherwise dev-mode debugging is
    // impossible. The original "x86 GLES-only" intent (don't fall back unsupervised) is
    // preserved at the gameplay-mode level by upstream policy, not here.
    // (Old behaviour: `if (sourceMode != ScalingMode::SOFTWARE_SCALING) return;`)
  #endif
    if (sourceMode == ScalingMode::SOFTWARE_SCALING) {
      return;
    }
  ```
- notes: The `if (sourceMode != ScalingMode::SOFTWARE_SCALING) return;` guard is gone. The `#if
  defined(__i386__)...#endif` block now contains only the explanatory `// Audit T4-F4` comment
  and the record of the old behaviour — no early-return. The function now falls through to the
  `scaling_mode_` → `SOFTWARE_SCALING` assignment and `SetRenderModeState(DEGRADED_TO_SW)` on
  both ARM and x86. The FATAL state is no longer unrecoverable on x86.

---

## F5: `geometry_changed_` cleared before window configuration succeeds

- verdict: N/A_MITIGATED
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp`
- line: 668–670, 805–812
- evidence_excerpt:
  ```
  // line 668
  const bool needConfigUpdate =
      (base_width_ != width || base_height_ != height ||
       geometry_changed_.exchange(false));   // clears flag atomically
  // ... (line 805)
  const auto result = window_state_manager_.Apply(window, state, LogOptFail);
  geometryOk = result.geometry_ok;
  if (!geometryOk) {
    geometry_changed_.store(true);           // re-arms on failure
    retry_count_++;
    last_retry_time_ = now;
  }
  ```
- notes: Code is unchanged from original audit. No mutex or atomic snapshot was added for
  `geometry_base_width_/height_/aspect_ratio_`. Mitigation stands: single-Engine-thread access
  policy makes the concurrent-write path unreachable in the current dispatch model. No regression
  introduced.

---

## F6: `GL_UNPACK_ALIGNMENT` / `GL_UNPACK_ROW_LENGTH` not queried when `diagEnabled=false`

- verdict: FIXED
- file: `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- line: 1065–1073
- evidence_excerpt:
  ```
  // line 1065
  GLint prevUnpackAlignment = 4;
  GLint prevUnpackRowLength = 0;
  // Audit T4-F6: always query the current GL unpack state before overwriting it.
  // Previously the `if (diagEnabled)` guard left prev* at their stack defaults (4/0),
  // so the restore below would blindly write defaults back — corrupting a HW
  // libretro core's own UNPACK_ALIGNMENT / ROW_LENGTH state if it had set non-defaults
  // before calling retro_video_refresh. Two glGetIntegerv calls per frame are cheap.
  glGetIntegerv(GL_UNPACK_ALIGNMENT, &prevUnpackAlignment);
  glGetIntegerv(GL_UNPACK_ROW_LENGTH, &prevUnpackRowLength);
  ```
- notes: The `if (diagEnabled)` guard wrapping the two `glGetIntegerv` calls has been removed.
  Both calls are now unconditional. A separate `if (diagEnabled && ShouldLog(...))` block at
  line 1077 still gates the verbose diagnostic logging, which is correct and separate from the
  state-save concern.

---

## F7: Function-local `static bool logged` in `SwapHardwareBuffersImpl` survives destroy/reinit

- verdict: FIXED
- file: `entry/src/main/cpp/core/engine/video_pipeline.cpp` (usage: lines 1755–1761),
  `entry/src/main/cpp/core/engine/video_pipeline.h` (declaration: line 390),
  reset in `DestroyHardwareRendererImpl` (line 1652)
- evidence_excerpt:
  ```
  // video_pipeline.h line 387–390
  // Audit T4-F7: per-init "HW render present active" log throttle (replaces a
  // function-local `static bool logged` that survived destroy/reinit and silenced
  // the diagnostic forever after the first activation).
  size_t hw_present_log_count_ = 0;

  // video_pipeline.cpp line 1649–1652 (DestroyHardwareRendererImpl)
  void VideoPipeline::DestroyHardwareRendererImpl(EnvState &env_state) {
    // Audit T4-F7: reset HW-present log throttle so a subsequent InitializeHardwareRendererImpl
    // emits "HW render present active" again on the next presented frame.
    hw_present_log_count_ = 0;

  // video_pipeline.cpp line 1755–1761 (SwapHardwareBuffersImpl)
  // Audit T4-F7: log "HW render present active" via member-counter throttle so the
  // signal re-fires after each destroy/reinit ...
  if (ShouldLog(hw_present_log_count_, 1, 120)) {
    LOGF(LOG_INFO, "HW render present active");
  }
  hw_present_log_count_++;
  ```
- notes: No `static bool logged` variable exists anywhere in the function. Member
  `hw_present_log_count_` is declared in the header with in-class initializer `= 0`. It is reset
  to `0` at the top of `DestroyHardwareRendererImpl`, guaranteeing the diagnostic re-fires on the
  next `InitializeHardwareRendererImpl` cycle. The `ShouldLog(count, 1, 120)` throttle limits
  subsequent repetition to once per 120 frames. All three parts of the fix (header, destroy, usage)
  are present and consistent.

---

## F8: `ConvertAndScaleXRGB8888_Scalar` uses float arithmetic instead of 16.16 fixed-point

- verdict: FIXED
- file: `entry/src/main/cpp/platform/graphics/pixel_converter_scalar.cpp`
- line: 317–353
- evidence_excerpt:
  ```
  // line 318
  // Audit T4-F8: use the same 16.16 fixed-point step+accumulator pattern as the
  // general ConvertAndScaleScalar path. Float scaling here would drift relative to
  // the RGB565 / 0RGB1555 paths at moderate dimensions ...
  const uint32_t xStep = static_cast<uint32_t>(
      (static_cast<uint64_t>(srcWidth) << 16) / static_cast<uint64_t>(destWidth));
  const uint32_t yStep = static_cast<uint32_t>(
      (static_cast<uint64_t>(srcHeight) << 16) / static_cast<uint64_t>(destHeight));

  uint32_t yAcc = 0;
  for (unsigned dstY = 0; dstY < destHeight; dstY++, yAcc += yStep) {
      const unsigned srcY = yAcc >> 16;
      ...
      uint32_t xAcc = 0;
      for (unsigned dstX = 0; dstX < destWidth; dstX++, xAcc += xStep) {
          const unsigned srcX = xAcc >> 16;
  ```
- notes: No `float scaleX`, `float scaleY`, `static_cast<float>(srcWidth) / destWidth`, or
  floating-point coordinate calculation exists in `ConvertAndScaleXRGB8888_Scalar`. The function
  now uses `xStep`/`yStep` 16.16 accumulators matching the general `ConvertAndScaleScalar` path.
  The pattern is identical in structure.

---

## Summary

Out of 8 findings:

- **F1 FIXED** — `AbortBuffer`+counter fully removed from the FlushBuffer-failure branch; `// Audit T4-F1` comment documents the ownership reasoning; `OH_NativeBuffer_Unreference` retained.
- **F2 FALSE_POSITIVE_CONFIRMED** — `render_thread.cpp:306–347` is byte-for-byte identical to the original audit excerpt; no `OH_NativeWindow_NativeObjectReference` was added; the ownership-transfer interpretation in core-review stands.
- **F3 N/A_MITIGATED** — `pixel_format_` remains a plain non-atomic member with the Engine-thread-only comment; no regression.
- **F4 FIXED** — Early-return guard inside `#if defined(__i386__)` is gone; `EnterDegradedMode` now allows software-degradation on x86, eliminating the permanent-black-screen scenario after 5 GLES reinit failures.
- **F5 N/A_MITIGATED** — `geometry_changed_.exchange(false)` / `.store(true)` pattern unchanged; no regression.
- **F6 FIXED** — `if (diagEnabled)` guard around `glGetIntegerv` calls removed; both calls now unconditional.
- **F7 FIXED** — `static bool logged` replaced by member `hw_present_log_count_` (header + reset in `DestroyHardwareRendererImpl` + `ShouldLog` throttle in usage site); diagnostic re-fires correctly after each destroy/reinit cycle.
- **F8 FIXED** — Float `scaleX`/`scaleY` arithmetic replaced by `xStep`/`yStep` 16.16 fixed-point accumulators matching the general scalar path.

All 5 REAL/REAL_LOWER findings confirmed fixed with `// Audit T4-F<N>` comment evidence. Both MITIGATED findings confirmed unchanged. FALSE_POSITIVE (F2) confirmed original code intact.
