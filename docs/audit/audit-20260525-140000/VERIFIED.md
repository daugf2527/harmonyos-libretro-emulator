# Citation Verification Table — audit-20260525-140000

Verification method: For each finding, `Read` the cited file at the cited line range and compare to `evidence_excerpt`.

Statuses:
- **VERIFIED** — bytes match (allow trivial whitespace drift)
- **CITATION_DRIFT** — same code exists but line range off
- **FALSE_POSITIVE** — citation matches but claim demonstrably wrong from reading the code
- **DISPUTED** — citation matches; two agents give contradictory interpretations

---

## T1 — NAPI 边界 (8 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P1 | engine_query_napi.cpp | 63-75 | VERIFIED | CompleteWaitForState: no status guard before napi_get_boolean/napi_resolve_deferred |
| F2 | P1 | engine_state_napi.cpp | 190-213 | VERIFIED | CompleteSaveStateAsync: napi_cancelled merged with logic failure; always resolves |
| F3 | P2 | engine_state_napi.cpp + engine_query_napi.cpp | 175,226,263,316,47,104 | VERIFIED | napi_env env field in SaveStateAsyncContext/LoadStateAsyncContext/WaitForStateAsyncContext; assigned but never read |
| F4 | P1 | engine_video_napi.cpp | 155-160 | VERIFIED | SetAudioSyncMode calls audioBridge->SetSyncMode() directly on NAPI thread |
| F5 | P2 | engine_napi_common.h | 56-71,136-167 | VERIFIED | GetArgs/GetInt32Arg/GetBoolArg/GetDoubleArg return false without napi_throw_error |
| F6 | P1 | core_loader_napi.cpp | 362+ | VERIFIED | TestCoreLoader is synchronous NAPI callback; no async_work; calls dlopen inline |
| F7 | P2 | libretro_engine_napi.cpp | 10 | VERIFIED | Log string says "56 functions", actual count is 58+ |
| F8 | P2 | engine_state_napi.cpp | 223-229,301-321 | VERIFIED | napi_create_promise return value not checked in SaveStateAsync and LoadStateAsync |

**T1 summary: 8 VERIFIED / 0 CITATION_DRIFT / 0 FILE_MISSING**

---

## T2 — Engine 状态机 (7 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P1 | libretro_engine.cpp | 1315-1324, 256-257 | VERIFIED | HandleMessage allows STOPPED→LoadCore, IsValidTransition STOPPED case excludes LOADING |
| F2 | P1 | libretro_engine.cpp | 2476-2481 | VERIFIED | TransitionTo calls stateCond_.notify_all() after CAS, without holding stateMutex_ |
| F3 | P2 | libretro_engine.cpp | 2527-2528 | VERIFIED | timeoutMs==0 branch holds stateMutex_ for a trivial atomic load; semantics undocumented |
| F4 | P1 | libretro_engine.cpp | 442-475 | VERIFIED | Stop() holds controlMutex_ (lock_guard) during entire 5000ms stopCond_.wait_for |
| F5 | P2 | libretro_engine.cpp | 38, 324 | VERIFIED | Comment line 38 says "析构函数不写回 nullptr"; line 324 stores nullptr |
| F6 | P2 | libretro_engine.cpp | 2001,2118,2206 | VERIFIED | Local variable g_engineInstance shadows global static of same name |
| F7 | P2 | libretro_engine.cpp | 33-44, 305-309 | VERIFIED | Meyer's singleton + manual g_engineInstance dual-track; comment documents the risk |

**T2 summary: 7 VERIFIED / 0 CITATION_DRIFT / 0 FILE_MISSING**

---

## T3 — Audio bridge (10 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P1 | audio_bridge.cpp | 251,334,455 | VERIFIED | Code matches: unique_lock acquired at 251, unlock at 334, lock_guard re-lock at 455. "double-lock" label is misleading — it's sequential re-lock after explicit unlock. Claim interpretation needs Step 3 review. |
| F2 | P1 | ring_buffer.cpp | 162-224 | VERIFIED | cv_not_full_.wait predicate structure and WriteDataInternal-without-re-check matches. TOCTOU claim under SPSC semantics is debatable — Step 3 review needed. |
| F3 | P1 | audio_bridge.cpp | 334,352-354 | VERIFIED | lock.unlock() at 334; WriteWait/Write called with resample_out_buf_.data() at 352-354 (after unlock) |
| F4 | P2 | audio_player.cpp | 116-208 | VERIFIED | SetFrameSizeInCallback failure logs but does NOT return; execution continues to GenerateRenderer |
| F5 | P2 | audio_player.cpp | 912-937 | VERIFIED | callback_cond_.wait(lock, ...) at line 936 — no timeout, can block forever |
| F6 | P2 | ring_buffer.h | 129-132 | VERIFIED | mutable size_t write_wait_block_logs_ etc.; non-atomic, accessed by both producer and consumer threads |
| F7 | P2 | audio_bridge.cpp + audio_resampler.cpp | 299-303, 92-119 | VERIFIED | ceil(frames*ratio)+8 estimate; Resample uses phase_ as starting position |
| F8 | P1 | audio_bridge.cpp | 571-615 | FALSE_POSITIVE | Agent claims ring_buffer_ is unique_ptr — WRONG. audio_bridge.h:102 declares ring_buffer_ as std::shared_ptr<RingBuffer>. buffer_ref copy at line 311 IS a proper shared_ptr copy that extends lifetime. The core claim is invalid. |
| F9 | P2 | audio_player.cpp | 513-521, 635 | VERIFIED | callback_last_time_, callback_log_count_ etc. are non-atomic members accessed in audio callback thread |
| F10 | P2 | audio_bridge.cpp | 500-518 | VERIFIED | Initialize() re-entry path returns true without updating core_sample_rate_ or reinitializing resampler |

**T3 summary: 9 VERIFIED / 0 CITATION_DRIFT / 1 FALSE_POSITIVE (F8)**

---

## T4 — VideoPipeline 渲染 (5 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P0 | video_pipeline.cpp | 1321-1335 | DISPUTED | Code at cited lines matches. BUT T5 agent's positive-confirmation section explicitly marks this AbortBuffer call as "合法" (correct), citing buffer ownership semantics. T4 agent says flush failure keeps ownership; T5 agent agrees. The claim may be wrong — needs HarmonyOS NativeWindow API spec verification in Step 3. |
| F2 | P2 | gles_renderer.cpp | 10-11 | VERIFIED | LOG_DOMAIN 0xD003 confirmed; same as video_pipeline.cpp |
| F3 | P2 | gles_renderer.cpp | 495-501 | VERIFIED | Deinit() sets healthy_=true at line 497 before EGL cleanup |
| F4 | P2 | window_state_manager.cpp | 89-101 | VERIFIED | last_state_ only updated when all 5 opts succeed (lines 99-103) |
| F5 | P2 | video_pipeline.h | 93-98 | VERIFIED | pixel_format_ is non-atomic member; SetPixelFormat accesses without atomic |

**T4 summary: 4 VERIFIED / 1 DISPUTED (F1) / 0 FILE_MISSING**

---

## T5 — NativeBuffer 用法 (2 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P1 | video_pipeline.cpp | 1086-1107 | VERIFIED | Error branch `if (ret != 0 \|\| !addr)` calls Unreference but not Unmap when Map succeeded (ret==0) but addr==nullptr |
| F2 | P2 | video_pipeline.cpp + render_thread.cpp | 23-24, 8-9 | VERIFIED | Both define LOG_DOMAIN 0xD003 |

**T5 summary: 2 VERIFIED / 0 CITATION_DRIFT / 0 FILE_MISSING**

---

## T6 — 资源生命周期 (4 findings)

| # | Severity | File | Lines | Status | Notes |
|---|---|---|---|---|---|
| F1 | P1 | graphics_context.cpp | 47-57 | VERIFIED | CreateSurface failure returns false without calling Destroy(); egl_context_/egl_display_ leaked |
| F2 | P2 | gles_renderer.cpp | 495-501 | VERIFIED | Same as T4-F3: healthy_=true before EGL destruction in Deinit() |
| F3 | P1 | SaveStateRepository.ets | 194-212 | VERIFIED | TRUNC mode direct-write to target path; no tmp+rename atomic pattern |
| F4 | P2 | SaveStateRepository.ets | 37-61 | VERIFIED | Write .state file first (line 41), then update manifest (line 56) — two-step non-atomic |

**T6 summary: 4 VERIFIED / 0 CITATION_DRIFT / 0 FILE_MISSING**

---

## Overall Totals

| Status | Count |
|---|---|
| VERIFIED | 33 |
| DISPUTED | 1 (T4-F1) |
| FALSE_POSITIVE | 1 (T3-F8) |
| CITATION_DRIFT | 0 |
| FILE_MISSING | 0 |
| FORMAT_ERROR | 0 |
| **Total findings** | **36** |

Note: T4-F1 and T5-F2 (positive confirmations) directly contradict each other regarding AbortBuffer semantics — T5's positive section says the AbortBuffer call after FlushBuffer failure is correct because ownership is NOT transferred on failure. This is the central dispute in T4-F1 and must be resolved with HarmonyOS API documentation in Step 3.
