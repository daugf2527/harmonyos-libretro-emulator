# NAPI Boundary Audit - T1
Date: 2026-05-25
Scope: entry/src/main/cpp/app/napi/ (all files except engine_lifecycle_napi.cpp)
Verdict: concerns

---

## F1: CompleteWaitForState ignores napi_status - resolves even when async work is cancelled

- severity: P1
- file: entry/src/main/cpp/app/napi/engine_query_napi.cpp
- line: 63-75
- evidence_excerpt: |
    static void CompleteWaitForState(napi_env env, napi_status status, void *data) {
      napi_value result;
      napi_get_boolean(env, ctx->result, &result);  // no status guard
      napi_resolve_deferred(env, ctx->deferred, result);  // no status guard
      napi_delete_async_work(env, ctx->work);
      delete ctx;
    }
- claim: The NAPI contract mandates that when status == napi_cancelled the complete callback must call ONLY napi_delete_async_work. CompleteWaitForState ignores status and unconditionally calls napi_get_boolean and napi_resolve_deferred. If the work is cancelled during engine teardown or JS env exit, those calls operate on an env that may already be torn down - undefined behaviour. The deferred is resolved with the last-seen ctx->result rather than being rejected, so the ArkTS Promise chain does not learn the operation was aborted. CompleteSaveStateAsync (engine_state_napi.cpp:196) checks status != napi_ok before branching; CompleteLoadStateAsync (engine_state_napi.cpp:285) gates get_boolean on ctx->ok && status == napi_ok. CompleteWaitForState has neither guard.
- suggested_fix: Insert at the top: if (status != napi_ok) { napi_delete_async_work(env, ctx->work); delete ctx; return; }. Only call napi_get_boolean and napi_resolve_deferred in the napi_ok branch.
---

## F2: SaveStateAsync failure path calls napi_get_null and napi_resolve_deferred when cancelled - UB

- severity: P1
- file: entry/src/main/cpp/app/napi/engine_state_napi.cpp
- line: 190-213
- evidence_excerpt: |
    if (status != napi_ok || !ctx->ok || ctx->data.empty()) {
      napi_value result;
      napi_get_null(env, &result);   // forbidden when napi_cancelled
      napi_resolve_deferred(env, ctx->deferred, result); // forbidden when napi_cancelled
    }
- claim: The failure branch merges napi_cancelled (status != napi_ok) and logical failure (ctx->ok == false) into one path. When status == napi_cancelled, napi_get_null and napi_resolve_deferred are both forbidden by the NAPI spec. Beyond the UB, the promise always fulfills (resolves with null) rather than rejecting on failure, meaning ArkTS .catch() handlers are never invoked for SaveState failures. The caller RuntimeSessionController.ets:59 uses await nativeApi.refactoredSaveStateAsync() and must null-check the result to detect failure; if that check is absent, null is silently passed downstream.
- suggested_fix: Add a cancellation guard as the first action: if (status != napi_ok) { napi_delete_async_work(env, ctx->work); delete ctx; return; }. For logical failures when status == napi_ok, use napi_reject_deferred with a constructed Error object so ArkTS .catch() receives the rejection.

---

## F3: ctx->env stored in three async context structs but never read - dead field invites future misuse

- severity: P2
- file: entry/src/main/cpp/app/napi/engine_state_napi.cpp, entry/src/main/cpp/app/napi/engine_query_napi.cpp
- line: engine_state_napi.cpp:175+226+263+316; engine_query_napi.cpp:47+104
- evidence_excerpt: |
    struct SaveStateAsyncContext {
      napi_env env = nullptr;   // written at line 226, never subsequently read
      napi_deferred deferred = nullptr;
      napi_async_work work = nullptr;
      std::vector<uint8_t> data;
      bool ok = false;
    };
    ctx->env = env;  // line 226
- claim: Three async context structs (SaveStateAsyncContext, LoadStateAsyncContext, WaitForStateAsyncContext) each store a napi_env member and assign it at creation time. The Execute* worker-thread callbacks do not use ctx->env. The Complete* callbacks receive env as a fresh parameter from the NAPI runtime. The stored field is never read. It is benign today but is a footgun: code added inside Execute* that reaches for ctx->env would use a captured NAPI-thread env from a worker thread - an immediate use-after-env-teardown bug.
- suggested_fix: Remove the napi_env env field from all three structs and remove the ctx->env = env assignments. The env parameter is correctly supplied by the NAPI runtime at Complete* invocation time.
---

## F4: SetAudioSyncMode calls AudioBridge directly from NAPI thread - unverified thread safety

- severity: P1
- file: entry/src/main/cpp/app/napi/engine_video_napi.cpp
- line: 155-160
- evidence_excerpt: |
    auto *audioBridge = libretro::AudioBridge::GetInstance();
    if (audioBridge) {
      auto syncMode = (mode == 0) ? libretro::AudioBridge::SyncMode::NON_BLOCKING
                                  : libretro::AudioBridge::SyncMode::AUDIO_BLOCKING;
      audioBridge->SetSyncMode(syncMode);
    }
- claim: SetAudioSyncMode is a NAPI callback executing on the NAPI thread. It calls audioBridge->SetSyncMode() directly on the AudioBridge singleton. Per the project threading model, AudioBridge is owned by the Audio thread. Calling a mutating method on it from the NAPI thread is a data race unless AudioBridge::SetSyncMode is internally mutex-protected. GetStats in engine_query_napi.cpp:290-296 similarly calls audioBridge->GetBufferUsage() and audioBridge->GetBufferStats() from the NAPI thread. Unlike engine state changes which go through messageQueue_, these AudioBridge calls bypass any queuing mechanism. If AudioBridge does not provide its own thread-safe wrappers for these methods, this is a race condition that can corrupt audio pipeline state.
- suggested_fix: Verify that AudioBridge::SetSyncMode, GetBufferUsage, and GetBufferStats are internally mutex-protected. If not, route SetSyncMode through the engine message queue. Add a comment at each NAPI call site citing the specific AudioBridge thread-safety guarantee being relied upon.

---

## F5: GetArgs and type-getter helpers return false without napi_throw_error - ArkTS sees silent false

- severity: P2
- file: entry/src/main/cpp/app/napi/engine_napi_common.h
- line: 56-71 (GetArgs), 136-145 (GetInt32Arg), 147-156 (GetBoolArg), 158-167 (GetDoubleArg)
- evidence_excerpt: |
    if (status != napi_ok || argc < minArgs) {
      LOGF(LOG_ERROR, "[NEW] %s requires at least %zu argument(s)", func, minArgs);
      return false;   // no napi_throw_error called
    }
- claim: When GetArgs detects wrong argument count or napi_get_cb_info failure, it returns false. All callers then return MakeBool(env, false) - a resolved boolean false to ArkTS. No napi_throw_error is called. A NAPI function that detects a programming error (wrong argument count, wrong type) should call napi_throw_type_error so ArkTS code can catch it in a try/catch block. Returning false silently means ArkTS code treats an API contract violation as a logical failure, masking misuse. The same problem applies to GetInt32Arg, GetBoolArg, GetDoubleArg, and GetStringArg.
- suggested_fix: In GetArgs, after detecting argc < minArgs or status != napi_ok, call napi_throw_type_error with a descriptive message before returning false. Callers must then return nullptr (not MakeBool false) so the pending JS exception propagates. Apply the same fix to type-getter helpers for type mismatch errors.
---

## F6: TestCoreLoader calls dlopen/dlsym/dlclose synchronously on NAPI thread - blocks event loop

- severity: P1
- file: entry/src/main/cpp/app/napi/core_loader_napi.cpp
- line: 362-616
- evidence_excerpt: |
    static napi_value TestCoreLoader(napi_env env, napi_callback_info info) {
      CoreLoader loader;
      if (!loader.LoadCore(corePath)) {    // dlopen here, can block 100ms+
        ...
      } else {
        unsigned apiVersion = loader.GetApiVersion()();
        loader.GetSystemInfo()(&sysInfo);
        loader.UnloadCore();              // dlclose here
      }
      napi_create_string_utf8(env, resultMessage.c_str(), NAPI_AUTO_LENGTH, &result);
      return result;   // fully synchronous, no async_work
    }
- claim: TestCoreLoader is a synchronous NAPI callback with no async_work or Promise. It calls LoadCore (dlopen), retro_api_version(), retro_get_system_info(), and UnloadCore (dlclose) all on the NAPI thread. dlopen on HarmonyOS can block for tens to hundreds of milliseconds while the linker resolves relocations and the OS performs security validation. This violates the HARD invariant that NAPI thread functions must not block. The ArkTS caller at CoreLoaderTest.ets:363 calls this synchronously: let result = nativeApi.testCoreLoader(this.corePath). During dlopen the entire ArkTS/UI event loop is frozen.
- suggested_fix: Convert TestCoreLoader to use napi_async_work. The Execute callback (worker thread) performs dlopen/retro_api_version/retro_get_system_info/dlclose and stores the result string in a context struct. The Complete callback (NAPI thread) creates the string napi_value and resolves the deferred. Update the ArkTS caller to await the resulting Promise.

---

## F7: Function count comment claims 56, actual count across the 6 engine sub-modules is 58

- severity: P2
- file: entry/src/main/cpp/app/napi/libretro_engine_napi.cpp
- line: 10
- evidence_excerpt: |
    LOGF(LOG_INFO, " [NEW] LibretroRefactored NAPI registered (56 functions, 6 modules)");
- claim: Counting napi_property_descriptor entries registered across the six engine_*_napi.cpp files: engine_input_napi.cpp:7, engine_disk_napi.cpp:7, engine_query_napi.cpp:13, engine_lifecycle_napi.cpp:12, engine_state_napi.cpp:12, engine_video_napi.cpp:7 - total 58. The comment says 56. Including testCoreLoader from core_loader_napi.cpp (registered in the same libentry.so Init via RegisterCoreLoaderNapi) brings the whole-module total to 59. The count is stale by at least 2 within the 6 sub-modules, indicating functions were added without updating the comment.
- suggested_fix: Recount all registered NAPI functions and update the log string. If core_loader_napi is intentionally excluded from this aggregator count, the sub-module count alone is 58.

---

## F8: SaveStateAsync and LoadStateAsync do not check napi_create_promise return value

- severity: P2
- file: entry/src/main/cpp/app/napi/engine_state_napi.cpp
- line: SaveStateAsync:223-229, LoadStateAsync:301-321
- evidence_excerpt: |
    auto *ctx = new SaveStateAsyncContext();
    ctx->env = env;
    napi_value promise;
    napi_create_promise(env, &ctx->deferred, &promise);  // return NOT checked
    ...
    if (createStatus != napi_ok || !ctx->work) {
      napi_resolve_deferred(env, ctx->deferred, nullVal); // ctx->deferred may be nullptr
      delete ctx;
      return promise;  // promise may be uninitialized napi_value
    }
- claim: napi_create_promise is called without checking its return status for both SaveStateAsync (line 229) and LoadStateAsync (line 321). If it fails, ctx->deferred remains nullptr and promise is an uninitialized napi_value. The subsequent error-handling branch then calls napi_resolve_deferred with a nullptr deferred (UB) and returns the uninitialized napi_value to ArkTS. WaitForEngineStateAsync (engine_query_napi.cpp:110) correctly checks napi_create_promise and falls back to MakeResolvedPromise on failure, demonstrating the correct pattern.
- suggested_fix: After napi_create_promise, check the return value. If it fails, call napi_throw_error, delete ctx, and return nullptr. This is the pattern already used in WaitForEngineStateAsync.

## DONE