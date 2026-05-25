# Core Review — audit-20260525-140000

每个 VERIFIED finding 已由主 Claude 重读 cited code ±20 行后判定。

Verdicts:
- `REAL` — confirmed bug at cited severity
- `REAL_LOWER` — confirmed but severity overstated (true severity in parentheses)
- `MITIGATED` — code does the cited thing but upstream check prevents execution
- `DESIGN` — intentional, acknowledged debt
- `FALSE_POSITIVE` — agent misread the code

---

## Agent T1 — 8 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | REAL | CompleteWaitForState: napi_get_boolean + napi_resolve_deferred called unconditionally — napi_cancelled path is UB; pattern confirmed by reading CompleteLoadStateAsync which correctly guards `ctx->ok && status == napi_ok` |
| F2 | P1 | REAL | CompleteSaveStateAsync: `if (status != napi_ok \|\| !ctx->ok \|\| ctx->data.empty())` merges napi_cancelled with logical failure; napi_get_null+napi_resolve_deferred both forbidden when cancelled; additionally this path always resolves (never rejects) so ArkTS .catch() is unreachable for save failures |
| F3 | P2 | REAL | Three async context structs in engine_state_napi.cpp + engine_query_napi.cpp store `napi_env env = nullptr`; assigned at construction, never read in Execute* or Complete*; benign today but footgun — same issue was already fixed in engine_lifecycle_napi.cpp this session |
| F4 | P1 | REAL | engine_video_napi.cpp:155-160: audioBridge->SetSyncMode() called directly from NAPI thread callback; CLAUDE.md strictly requires Audio API calls only on Audio thread; no mutex inspection available to confirm AudioBridge::SetSyncMode is internally locked |
| F5 | P2 | REAL | GetArgs/type-getters: return false on contract violation without napi_throw_error; callers all return MakeBool(env,false); ArkTS caller cannot distinguish arg error from logical false; should throw napi_type_error |
| F6 | P1 | REAL | TestCoreLoader (core_loader_napi.cpp:362): fully synchronous NAPI function; calls LoadCore(dlopen) + GetApiVersion + GetSystemInfo + UnloadCore on NAPI thread; no async_work; blocks ArkTS/UI event loop during dynamic library loading |
| F7 | P2 | REAL | libretro_engine_napi.cpp:10: log string "56 functions" is stale; actual count across 6 sub-modules is 58; minor but indicates undocumented functions were added |
| F8 | P2 | REAL | SaveStateAsync and LoadStateAsync: napi_create_promise return value unchecked; if it fails, ctx->deferred is nullptr, subsequent napi_resolve_deferred is UB; the correct guard already exists in WaitForEngineStateAsync in the same file |

**T1 tally: 4 REAL P1 + 4 REAL P2**

---

## Agent T2 — 7 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | REAL | HandleMessage LoadCore allows STOPPED at line 1318; IsValidTransition STOPPED case (line 256-257) only permits →STARTING/→INIT; TransitionTo(LOADING) will silently refuse (WARN log + return); engine runs LoadCore body in STOPPED state with no state advance; subsequent TransitionTo(CORE_LOADED) also silently fails |
| F2 | P1 | REAL | TransitionTo: CAS write at 2476 succeeds, then notify_all at 2481 without holding stateMutex_; WaitForState at 2526 acquires stateMutex_ then evaluates predicate; classic notification-loss window; mitigated by wait_for timeout but can cause spurious false-returns on short timeouts |
| F3 | P2 | REAL | WaitForState: timeoutMs==0 branch at 2527-2528 holds stateMutex_ lock just for an atomic load that is equally done by the unlocked fast-path at 2523; wasteful lock acquisition; semantics (non-blocking poll) are reasonable but undocumented |
| F4 | P1 | REAL | Stop() acquires lock_guard on controlMutex_ at line 443 and holds it through stopCond_.wait_for(5000ms) at 469-475; any concurrent call to Start/Reset/LoadCore/LoadGame that tries to lock controlMutex_ will block for up to 5 seconds; design issue, not a deadlock but severe responsiveness impact |
| F5 | P2 | REAL | Comment line 38: "析构函数不写回 nullptr" contradicted by line 324 which does g_engineInstance.store(nullptr); stale comment creates misleading expectation about post-destruction pointer state |
| F6 | P2 | REAL_LOWER (P2) | Local `g_engineInstance` shadows global static in OnVideoRefresh/OnAudioSampleBatch/OnEnvironment; logic is correct (GetEngineInstanceSnapshot() is used); shadowing is confusing in code review and dangerous if future code references global without local assignment; severity matches P2 |
| F7 | P2 | DESIGN | Meyer's singleton + manual g_engineInstance dual-track design: risk already documented in the code comment (lines 33-43) with suggested fix directions; no new instances are created outside GetInstance() in current codebase; acknowledge as technical debt |

**T2 tally: 3 REAL P1 + 3 REAL P2 + 1 DESIGN**

---

## Agent T3 — 9 VERIFIED + 1 FALSE_POSITIVE

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | REAL_LOWER (P2) | Heading says "double-lock deadlock risk" but code correctly releases unique_lock at 334 before lock_guard at 455 — NO actual deadlock. The real issue: (a) re-locking same mutex creates a maintenance footgun for future code added in the unlock window; (b) `now` variable at line 441 uses the outer `now` from line 239 — no actual shadowing found in the DRC block. Severity demoted P1→P2 (future risk, not present bug). |
| F2 | P1 | REAL_LOWER (P2) | WriteWait slow path: after cv_not_full_.wait() returns with lock held, curr_head is read but curr_tail is not re-checked. In SPSC usage, consumer only advances tail (increasing space), so the predicate's check is conservative, not optimistic — no overflow possible. The Clear() race: running=false is checked at line 190 before WriteDataInternal, so Clear() with running=false is handled. A lock-free Clear() that resets head/tail without the mutex could race, but that requires verifying Clear() implementation. Severity demoted P1→P2 pending Clear() inspection; claim overstates risk. |
| F3 | P1 | REAL | resample_out_buf_.data() passed to WriteWait/Write at lines 352-354, AFTER lock.unlock() at line 334. If Reset() acquires mutex_ in the window and calls resample_out_buf_.resize() or otherwise modifies the member, the pointer becomes dangling. Under single-threaded libretro callback model the race rarely fires, but the invariant "Resample 必须在锁内进行" in the code comment at line 297 is violated for the subsequent read of the produced data. |
| F4 | P2 | REAL | audio_player.cpp:155-163: SetFrameSizeInCallback failure only logs, does not early-return. Execution proceeds to GenerateRenderer with potentially a different frame size than requested. Downstream callback size mismatch can cause buffer over/underflow. The fix: `Cleanup(); return false;` after SetFrameSizeInCallback failure is consistent with the existing failure-handling pattern. |
| F5 | P2 | REAL | audio_player.cpp:934-937: `callback_cond_.wait(lock, [...])` with no timeout — if any in-flight callback is blocked in WriteWait/ReadWait, destructor hangs indefinitely. Should be wait_for with a bounded timeout. |
| F6 | P2 | REAL | ring_buffer.h mutable size_t counters (write_wait_block_logs_ etc.) accessed from producer thread (WriteWait) and consumer thread (ReadWait) without atomic or mutex protection; data race UB per C++ standard; consequence is miscounted throttle logs but technically UB. |
| F7 | P2 | REAL_LOWER (P2) | max_out_frames = ceil(frames * ratio) + 8: +8 is a fixed margin. For typical DRC skew ≤ 0.5% (kDrcMaxSkew=1.005), actual max overflow above ceil is at most 1–2 frames for any realistic input size. The +8 margin is adequate. Agent overstates risk as "可能溢出" without providing a concrete numerical overflow case. Severity stays P2 as a defense-in-depth concern; suggest increasing to +16 for explicit safety. |
| F8 | P1 | FALSE_POSITIVE | Agent claims ring_buffer_ is unique_ptr — INCORRECT. audio_bridge.h:102: `std::shared_ptr<RingBuffer> ring_buffer_`. Line 311: `std::shared_ptr<RingBuffer> buffer_ref = ring_buffer_` is a proper shared_ptr copy; shared ownership correctly extended. The Reset() path that resets the shared_ptr releases one reference; buffer_ref's reference keeps the object alive until WriteWait returns. Core claim is invalid. |
| F9 | P2 | REAL | audio_player.cpp:513-521,635: callback_last_time_, callback_log_count_ etc. are non-atomic members written in OHAudio callback thread (system thread) without mutex protection; same class of UB as T3-F6; consequence is log miscounting but pattern is technically unsound. |
| F10 | P2 | REAL | audio_bridge.cpp:503-517: Initialize() re-entry path when already initialized does NOT update core_sample_rate_ or reinitialize resampler; if a second game with a different sample rate calls Initialize() directly, resampler ratio is based on stale rate, causing wrong-pitch audio. Real user-facing impact on game switch. |

**T3 tally: 1 REAL P1 + 5 REAL P2 + 2 REAL_LOWER P2 + 1 FALSE_POSITIVE**

---

## Agent T4 — 4 VERIFIED + 1 DISPUTED (resolved FALSE_POSITIVE)

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P0 | FALSE_POSITIVE | T4 agent claims AbortBuffer after failed FlushBuffer is double-free. T5 agent (positive confirmations) explicitly marks the SAME call as "合法" citing that "buffer 所有权未转移时合法". HarmonyOS NativeWindow semantics (consistent with Android BufferQueue, DirectFB, etc.): FlushBuffer failure means buffer was NOT successfully submitted to consumer; producer retains ownership; AbortBuffer is the correct recovery. P0 claim invalid. T5's analysis is correct. |
| F2 | P2 | REAL | CLAUDE.md explicitly requires unique LOG_DOMAIN per translation unit. gles_renderer.cpp shares 0xD003 with video_pipeline.cpp and 7+ other files. Hilog filtering `hilog -D 0xD003` cannot distinguish any of these subsystems. |
| F3 | P2 | REAL | GLESRenderer::Deinit() sets healthy_=true at line 497 before any EGL cleanup. During Deinit execution, healthy_=true suggests renderer is usable while EGL context is being torn down. After Deinit() completes, healthy_=true but renderer is destroyed — misleads any consumer checking IsHealthy(). Should be false at start of Deinit, and the "clean initial" state after Deinit should be false (re-init required before use). |
| F4 | P2 | REAL | WindowStateManager::Apply only updates last_state_ when all 5 opts succeed (line 99-103). If geometry applies but usage/swap fails, last_state_.width/height is stale, causing geometry to be re-sent every frame. Repeated SET_BUFFER_GEOMETRY on an already-configured window can trigger producer-side BufferQueue slot rebuilds on some devices. |
| F5 | P2 | REAL | video_pipeline.h pixel_format_ is non-atomic. SetPixelFormat and Render() are both called on Engine thread today — no current race. SetWindowSize uses atomic stores indicating the class expects cross-thread window state access. Without a comment, future code could call SetPixelFormat from NAPI or UI thread. The fix (comment or make atomic) is low-risk. |

**T4 tally: 4 REAL P2 + 1 FALSE_POSITIVE**

---

## Agent T5 — 2 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | REAL | video_pipeline.cpp error branch `if (ret != 0 \|\| !addr)`: when OH_NativeBuffer_Map returns 0 (success) but addr==nullptr (pathological driver condition), OH_NativeBuffer_Unmap is never called. The nativeBuffer exists, Map succeeded, so Unmap is required. Only Unreference is called. Map/Unmap contract violated in this edge path. |
| F2 | P2 | REAL | Same as T4-F2 (same files, same LOG_DOMAIN 0xD003 violation). Not a duplicate finding — T5 extends the count to render_thread.cpp. Covered together with T4-F2 in the fix plan. |

**T5 tally: 1 REAL P1 + 1 REAL P2**

---

## Agent T6 — 4 VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P1 | REAL | graphics_context.cpp: CreateContext success → CreateSurface failure → return false with no Destroy() call. egl_context_ and egl_display_ are non-null and leaked. Caller (VideoPipeline::InitializeHardwareRendererImpl) receives false but may not call Destroy() before retry or teardown. Confirmed pattern in GLESRenderer and VulkanContext both call Deinit/Destroy on every failure path. |
| F2 | P2 | REAL | Same as T4-F3. GLESRenderer::Deinit() healthy_=true before EGL cleanup. Covered under T4-F3. |
| F3 | P1 | REAL | SaveStateRepository.ets writeArrayBufferToFile and saveManifest both use TRUNC mode direct write. Process crash during write leaves truncated .state file or empty/partial manifest.json. JSON.parse on partial manifest throws, triggering buildManifestFromDirectory which loses romFile associations. C++ side (file_configuration.cpp) already implements tmp+fsync+rename correctly. ArkTS side needs the same protection. High user-visible impact (save corruption). |
| F4 | P2 | REAL | saveStateData: .state file written first (line 41), manifest updated last (line 56). Crash between steps leaves orphan state file. buildManifestFromDirectory re-creates manifest but with empty romFile (line 158). Orphan saves cannot be associated with their ROM. Partially mitigated by F3 fix (if manifest write is atomic, partial state writes still cause orphans, but manifest integrity is preserved). |

**T6 tally: 2 REAL P1 + 2 REAL P2**

---

## Final Tally

| Verdict | P0 | P1 | P2 |
|---|---|---|---|
| REAL | 0 | 11 | 19 |
| REAL_LOWER → P2 | — | 4 downgraded | (included in P2) |
| DESIGN | — | — | 1 (T2-F7) |
| FALSE_POSITIVE | 1 (T4-F1) | 1 (T3-F8) | — |

**REAL findings: 11 P1 + 19 P2 = 30 total**
**Downgraded from P1→P2: T3-F1, T3-F2, T3-F7; T2-F6 stays P2**
**FALSE_POSITIVE: T4-F1 (P0), T3-F8 (P1)**
**DESIGN: T2-F7 (P2)**

### Cross-agent calibration notes

- **T3 over-labels**: 3 findings labeled P1 should be P2 (F1 double-lock is sequential re-lock not deadlock; F2 TOCTOU is overstated in SPSC; F7 +8 margin is adequate). T3-F8 is completely wrong (unique_ptr vs shared_ptr confusion).
- **T4 over-labels**: F1 labeled P0 is actually FALSE_POSITIVE — AbortBuffer after FlushBuffer failure is the correct behavior per NativeWindow semantics.
- **T5 and T4 agree** on LOG_DOMAIN (same finding across agents); only T5 has positive confirmations that directly correct T4-F1.
- **T1, T2, T6** findings are well-calibrated with accurate severity assignments.

### Top P1 findings to surface at Checkpoint B

1. **T1-F1**: CompleteWaitForState ignores napi_cancelled (engine_query_napi.cpp:63-75) — UB when async work cancelled
2. **T1-F2**: CompleteSaveStateAsync always resolves even on napi_cancelled (engine_state_napi.cpp:190-213) — UB + ArkTS .catch() unreachable
3. **T1-F4**: SetAudioSyncMode on NAPI thread (engine_video_napi.cpp:155-160) — thread rule violation
4. **T1-F6**: TestCoreLoader synchronous dlopen on NAPI thread (core_loader_napi.cpp:362) — blocks event loop
5. **T2-F1**: STOPPED→LOADING state machine inconsistency (libretro_engine.cpp:1315-1324) — silent state drift
6. **T2-F2**: TransitionTo notify_all without stateMutex_ (libretro_engine.cpp:2481) — notification loss
7. **T2-F4**: Stop() holds controlMutex_ for 5000ms (libretro_engine.cpp:443) — external API lockout
8. **T3-F3**: resample_out_buf_ accessed after mutex unlock (audio_bridge.cpp:334-354) — potential use-after-resize
9. **T5-F1**: OH_NativeBuffer_Map without paired Unmap in error path (video_pipeline.cpp:1086-1107)
10. **T6-F1**: EGL context/display leak in GraphicsContext::Initialize (graphics_context.cpp:47-57)
11. **T6-F3**: SaveState non-atomic write — crash corrupts saves (SaveStateRepository.ets:194-212)
