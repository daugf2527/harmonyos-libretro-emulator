# Fix Plan — audit-20260525-140000

REAL P1 x11 + REAL P2 x19 = 30 findings to fix.
Excludes: T4-F1 (FALSE_POSITIVE), T3-F8 (FALSE_POSITIVE), T2-F7 (DESIGN).

## NAPI files (must pass napi-boundary-reviewer first)

| Finding | File | Change |
|---|---|---|
| T1-F1 | engine_query_napi.cpp | Add napi_cancelled guard in CompleteWaitForState |
| T1-F2 | engine_state_napi.cpp | Add napi_cancelled guard; change failure path to napi_reject_deferred |
| T1-F3 | engine_state_napi.cpp + engine_query_napi.cpp | Remove ctx->env field from 3 structs |
| T1-F4 | engine_video_napi.cpp | Verify AudioBridge::SetSyncMode thread-safety; add comment or route through queue |
| T1-F5 | engine_napi_common.h | Add napi_throw_type_error in GetArgs/type-getters; cascade callers → return nullptr |
| T1-F6 | core_loader_napi.cpp | Convert TestCoreLoader to napi_async_work |
| T1-F7 | libretro_engine_napi.cpp | Update function count string |
| T1-F8 | engine_state_napi.cpp | Check napi_create_promise return value in SaveStateAsync + LoadStateAsync |

## C++ engine/audio/video files

| Finding | File | Change |
|---|---|---|
| T2-F1 | libretro_engine.cpp | Add STOPPED→LOADING to IsValidTransition STOPPED case |
| T2-F2 | libretro_engine.cpp | Hold stateMutex_ before stateCond_.notify_all() in TransitionTo |
| T2-F3 | libretro_engine.cpp | Remove unnecessary stateMutex_ lock in timeoutMs==0 path; add doc comment |
| T2-F4 | libretro_engine.cpp | Split Stop() lock scope: hold controlMutex_ only for pre-wait setup, release before wait_for |
| T2-F5 | libretro_engine.cpp | Fix stale comment at line 38 |
| T2-F6 | libretro_engine.cpp | Rename 3 local g_engineInstance → engine |
| T3-F3 | audio_bridge.cpp | Capture resample_out_buf_ data/size into local vars before lock.unlock() |
| T3-F4 | audio_player.cpp | Add Cleanup() + return false after SetFrameSizeInCallback failure |
| T3-F5 | audio_player.cpp | Change callback_cond_.wait → wait_for with 2s timeout |
| T3-F6 | ring_buffer.h | Change mutable size_t counters → std::atomic<size_t> |
| T3-F7 | audio_bridge.cpp | Change +8 → +16 in max_out_frames estimate |
| T3-F9 | audio_player.cpp | Change callback log counters to std::atomic<int> |
| T3-F10 | audio_bridge.cpp | Compare sample_rate in Initialize re-entry path; call Reset if different |
| T4-F2+T5-F2 | gles_renderer.cpp + 7 other platform/graphics TUs | Assign unique LOG_DOMAIN to each file |
| T4-F3+T6-F2 | gles_renderer.cpp | Change healthy_=true → false at start of Deinit() |
| T4-F4 | window_state_manager.cpp | Update last_state_ geometry fields independently on success |
| T4-F5 | video_pipeline.h | Add thread ownership comment to pixel_format_ |
| T5-F1 | video_pipeline.cpp | Add OH_NativeBuffer_Unmap before Unreference when Map succeeded (addr==nullptr path) |
| T6-F1 | graphics_context.cpp | Call Destroy() before return false in CreateSurface failure path |

## ArkTS files

| Finding | File | Change |
|---|---|---|
| T6-F3 | SaveStateRepository.ets | Implement tmp+rename atomic write in writeArrayBufferToFile and saveManifest |
| T6-F4 | SaveStateRepository.ets | Reorder: pre-register manifest entry before writing data file (or document orphan risk) |
