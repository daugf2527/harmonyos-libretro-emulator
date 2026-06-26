#include "engine_napi_common.h"
#include "platform/audio/audio_bridge.h"
#include "app/framework/plugin_manager.h"
#include "common/file_security.h"

namespace {

void SetQueryError(const char *reason, const char *step, const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

void EnsureQueryErrorIfEmpty(const char *reason, const char *step,
                             const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  auto err = engine->GetLastErrorInfo();
  if (!err.reason.empty()) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

bool IsValidEngineStateValue(int32_t stateValue) {
  return stateValue >= static_cast<int32_t>(libretro::EngineState::INIT) &&
         stateValue <= static_cast<int32_t>(libretro::EngineState::ERROR);
}

bool IsValidRegionValue(unsigned region) {
  return region == 0 || region == 1;
}

} // namespace

static napi_value GetEngineState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  libretro::EngineState state = GetEngine()->GetState();
  int32_t stateValue = static_cast<int32_t>(state);
  return MakeInt32(env, stateValue);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value WaitForEngineState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 1, 2, args, &argc, "WaitForEngineState")) {
    return MakeBool(env, false);
  }

  int32_t stateValue = 0;
  if (!GetInt32Arg(env, args[0], stateValue, "WaitForEngineState", "state")) {
    return MakeBool(env, false);
  }
  if (!IsValidEngineStateValue(stateValue)) {
    SetQueryError("wait_state_invalid", "WaitForEngineState",
                  "Requested engine state is outside supported range");
    return MakeBool(env, false);
  }

  int32_t timeoutMs = 0;
  if (argc >= 2) {
    if (!GetInt32Arg(env, args[1], timeoutMs, "WaitForEngineState", "timeoutMs")) {
      return MakeBool(env, false);
    }
    if (timeoutMs < 0) {
      timeoutMs = 0;
    }
  }

  const bool ok = GetEngine()->WaitForState(
      static_cast<libretro::EngineState>(stateValue),
      static_cast<uint32_t>(timeoutMs));
  if (!ok) {
    EnsureQueryErrorIfEmpty("wait_for_state_failed", "WaitForEngineState",
                            "Engine did not reach the requested state before timeout");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct WaitForStateAsyncContext {
  // Audit T1-F3: removed unused napi_env env field (env lifetime unsafe to store in async ctx)
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  libretro::EngineState target = libretro::EngineState::INIT;
  uint32_t timeoutMs = 0;
  bool result = false;
};

static void ExecuteWaitForState(napi_env env, void *data) {
  auto *ctx = static_cast<WaitForStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->result = GetEngine()->WaitForState(ctx->target, ctx->timeoutMs);
}

static void CompleteWaitForState(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<WaitForStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] WaitForEngineStateAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetQueryError("wait_for_state_async_work_failed", "WaitForEngineStateAsync",
                  "Async wait completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->result) {
      EnsureQueryErrorIfEmpty("wait_for_state_failed",
                              "WaitForEngineStateAsync",
                              "Engine did not reach the requested state before timeout");
    }
    napi_value result = MakeBool(env, ctx->result);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetQueryError("wait_for_state_result_alloc_failed", "WaitForEngineStateAsync",
                    "Failed to allocate async wait-for-state result value");
      napi_value reason = MakeString(env, "WaitForEngineStateAsync result alloc failed");
      if (reason) {
        (void)RejectDeferredChecked(env, ctx->deferred, reason);
      }
    }
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value WaitForEngineStateAsync(napi_env env,
                                          napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 1, 2, args, &argc, "WaitForEngineStateAsync")) {
    return MakeResolvedPromise(env, false);
  }

  int32_t stateValue = 0;
  if (!GetInt32Arg(env, args[0], stateValue, "WaitForEngineStateAsync",
                   "state")) {
    return MakeResolvedPromise(env, false);
  }
  if (!IsValidEngineStateValue(stateValue)) {
    SetQueryError("wait_state_invalid", "WaitForEngineStateAsync",
                  "Requested engine state is outside supported range");
    return MakeResolvedPromise(env, false);
  }

  int32_t timeoutMs = 0;
  if (argc >= 2) {
    if (!GetInt32Arg(env, args[1], timeoutMs, "WaitForEngineStateAsync",
                     "timeoutMs")) {
      return MakeResolvedPromise(env, false);
    }
    if (timeoutMs < 0) {
      timeoutMs = 0;
    }
  }

  auto *ctx = new WaitForStateAsyncContext();
  // Audit T1-F3: env field removed from ctx, no assignment needed
  ctx->target = static_cast<libretro::EngineState>(stateValue);
  ctx->timeoutMs = static_cast<uint32_t>(timeoutMs);
  ctx->work = nullptr;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return MakeResolvedPromise(env, false);
  }

  napi_value resourceName = MakeString(env, "WaitForEngineStateAsync");
  if (!resourceName) {
    SetQueryError("wait_for_state_async_create_failed",
                  "WaitForEngineStateAsync",
                  "Failed to create async resource name");
    napi_value falseVal = MakeBool(env, false);
    if (falseVal) {
      (void)ResolveDeferredChecked(env, ctx->deferred, falseVal);
    }
    delete ctx;
    return promise;
  }

  if (napi_create_async_work(env, nullptr, resourceName, ExecuteWaitForState,
                             CompleteWaitForState, ctx, &ctx->work) != napi_ok) {
    SetQueryError("wait_for_state_async_create_failed",
                  "WaitForEngineStateAsync",
                  "Failed to create async wait work item");
    napi_value falseVal = MakeBool(env, false);
    if (falseVal) {
      (void)ResolveDeferredChecked(env, ctx->deferred, falseVal);
    }
    delete ctx;
    return promise;
  }
  if (napi_queue_async_work(env, ctx->work) != napi_ok) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    SetQueryError("wait_for_state_async_queue_failed",
                  "WaitForEngineStateAsync",
                  "Failed to queue async wait work item");
    napi_value falseVal = MakeBool(env, false);
    if (falseVal) {
      (void)ResolveDeferredChecked(env, ctx->deferred, falseVal);
    }
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetLastErrorInfo(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  const auto err = GetEngine()->GetLastErrorInfo();
  napi_value result = MakeObject(env);
  if (!SetNamedPropertyChecked(env, result, "reason",
                               MakeString(env, err.reason)) ||
      !SetNamedPropertyChecked(env, result, "step",
                               MakeString(env, err.step)) ||
      !SetNamedPropertyChecked(env, result, "message",
                               MakeString(env, err.message))) {
    return nullptr;
  }

  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ClearLastErrorInfo(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  GetEngine()->ClearLastErrorInfo();
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetFilesDir(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetFilesDir")) {
    return MakeBool(env, false);
  }

  char path[1024];
  if (!GetStringArg(env, args[0], path, sizeof(path), "SetFilesDir", "filesDir")) {
    return MakeBool(env, false);
  }

  LOGF(LOG_INFO, " [NEW] SetFilesDir: %{public}s",
       security::DescribePathForLog(path).c_str());
  if (!security::ValidateFilesDir(path)) {
    GetEngine()->SetLastErrorInfo("files_dir_rejected", "SetFilesDir",
                                  "filesDir is outside allowed directories");
    return MakeBool(env, false);
  }
  const bool ok = GetEngine()->SetFilesDir(path);
  if (!ok) {
    EnsureQueryErrorIfEmpty("files_dir_set_failed", "SetFilesDir",
                            "SetFilesDir returned false");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value HasCoreLoaded(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool loaded = GetEngine()->HasCoreLoaded();
  return MakeBool(env, loaded);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value HasGameLoaded(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool loaded = GetEngine()->HasGameLoaded();
  return MakeBool(env, loaded);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetRegion(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  unsigned region = GetEngine()->GetRegion();
  if (!IsValidRegionValue(region)) {
    EnsureQueryErrorIfEmpty("region_unavailable", "GetRegion",
                            "Region query callback is unavailable");
    region = 0;
  }
  return MakeUint32(env, region);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct GetRegionAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  unsigned region = std::numeric_limits<unsigned>::max();
};

static void ExecuteGetRegionAsync(napi_env env, void *data) {
  auto *ctx = static_cast<GetRegionAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->region = GetEngine()->GetRegion();
}

static void CompleteGetRegionAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<GetRegionAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] GetRegionAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetQueryError("get_region_async_work_failed", "GetRegionAsync",
                  "Async region query completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    unsigned region = ctx->region;
    if (!IsValidRegionValue(region)) {
      EnsureQueryErrorIfEmpty("region_unavailable", "GetRegionAsync",
                              "Region query callback is unavailable");
      region = 0;
    }
    napi_value result = MakeUint32(env, region);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetQueryError("get_region_result_alloc_failed", "GetRegionAsync",
                    "Failed to allocate async region result value");
      napi_value reason = MakeString(env, "GetRegionAsync result alloc failed");
      if (reason) {
        (void)RejectDeferredChecked(env, ctx->deferred, reason);
      }
    }
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value GetRegionAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new GetRegionAsyncContext();

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "GetRegionAsync");
  if (!resourceName) {
    SetQueryError("get_region_async_create_failed", "GetRegionAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteGetRegionAsync,
      CompleteGetRegionAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetQueryError("get_region_async_create_failed", "GetRegionAsync",
                  "Failed to create async region query work item");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    SetQueryError("get_region_async_queue_failed", "GetRegionAsync",
                  "Failed to queue async region query work item");
    napi_value reason = MakeString(env, "async_work_queue_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetAVInfo(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *engine = GetEngine();

  napi_value obj = MakeObject(env);
  if (!SetNamedPropertyChecked(env, obj, "videoWidth",
                               MakeUint32(env, engine->GetVideoWidth())) ||
      !SetNamedPropertyChecked(env, obj, "videoHeight",
                               MakeUint32(env, engine->GetVideoHeight())) ||
      !SetNamedPropertyChecked(env, obj, "fps",
                               MakeDouble(env, engine->GetFps())) ||
      !SetNamedPropertyChecked(env, obj, "audioSampleRate",
                               MakeDouble(env, engine->GetAudioSampleRate()))) {
    return nullptr;
  }

  return obj;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetStats(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto stats = GetEngine()->GetStats();

  napi_value obj = MakeObject(env);

  #define SET_STAT(name)                                                   \
    if (!SetNamedPropertyChecked(env, obj, #name,                           \
                                 MakeInt64(env, static_cast<int64_t>(       \
                                                    stats.name)))) {        \
      return nullptr;                                                       \
    }

  SET_STAT(videoRefreshCalls);
  SET_STAT(videoNullFrames);
  SET_STAT(videoDupeFrames);
  SET_STAT(videoDroppedFrames);
  SET_STAT(audioBatchCalls);
  SET_STAT(audioFramesIn);
  SET_STAT(nwRequestBufferCalls);
  SET_STAT(nwRequestBufferFailures);
  SET_STAT(nwFlushBufferCalls);
  SET_STAT(nwFlushBufferFailures);
  SET_STAT(nwAbortBufferCalls);
  SET_STAT(nbFromWindowBufferFailures);
  SET_STAT(nbMapFailures);
  SET_STAT(nbUnmapFailures);
  SET_STAT(fenceWaitCalls);
  SET_STAT(fenceWaitFailures);
  SET_STAT(fenceTimeoutCount);
  SET_STAT(frameCount);
  SET_STAT(frameTimeMin);
  SET_STAT(frameTimeMax);
  SET_STAT(frameTimeSum);
  SET_STAT(queuePushed);
  SET_STAT(queuePopped);
  SET_STAT(queueDroppedOldest);
  SET_STAT(queueDroppedStaleOnPop);
  SET_STAT(queueDepthMax);
  SET_STAT(renderTickNoFrame);
  SET_STAT(renderThreadRenderedFrames);
  SET_STAT(renderThreadDroppedFrames);
  SET_STAT(vsyncCallbacks);
  SET_STAT(vsyncFallbackTicks);
  SET_STAT(vsyncRequestFailures);

  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    if (!SetNamedPropertyChecked(env, obj, "audioBufferUsage",
                                 MakeDouble(env,
                                            audioBridge->GetBufferUsage()))) {
      return nullptr;
    }

    size_t underruns = 0, overruns = 0;
    audioBridge->GetBufferStats(underruns, overruns);
    if (!SetNamedPropertyChecked(env, obj, "audioUnderruns",
                                 MakeInt64(env,
                                           static_cast<int64_t>(underruns))) ||
        !SetNamedPropertyChecked(env, obj, "audioOverruns",
                                 MakeInt64(env,
                                           static_cast<int64_t>(overruns)))) {
      return nullptr;
    }
  } else {
    if (!SetNamedPropertyChecked(env, obj, "audioBufferUsage",
                                 MakeDouble(env, 0.0)) ||
        !SetNamedPropertyChecked(env, obj, "audioUnderruns",
                                 MakeInt64(env, 0)) ||
        !SetNamedPropertyChecked(env, obj, "audioOverruns",
                                 MakeInt64(env, 0))) {
      return nullptr;
    }
  }

  #undef SET_STAT

  return obj;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ResetStats(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  GetEngine()->ResetStats();
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetInputDebugStats(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  (void)info;
  NewArchInputStats stats;
  PluginManager::GetInstance()->GetNewArchInputStats(stats);

  napi_value obj = MakeObject(env);
  if (!SetNamedPropertyChecked(env, obj, "touchCount",
                               MakeInt64(env, static_cast<int64_t>(
                                                  stats.touchCount))) ||
      !SetNamedPropertyChecked(env, obj, "mouseCount",
                               MakeInt64(env, static_cast<int64_t>(
                                                  stats.mouseCount))) ||
      !SetNamedPropertyChecked(env, obj, "keyCount",
                               MakeInt64(env, static_cast<int64_t>(
                                                  stats.keyCount))) ||
      !SetNamedPropertyChecked(env, obj, "hasFocus",
                               MakeBool(env, stats.hasFocus)) ||
      !SetNamedPropertyChecked(env, obj, "mouseDown",
                               MakeBool(env, stats.mouseDown)) ||
      !SetNamedPropertyChecked(env, obj, "lastTouchType",
                               MakeInt32(env, stats.lastTouchType)) ||
      !SetNamedPropertyChecked(env, obj, "lastMouseAction",
                               MakeInt32(env, stats.lastMouseAction)) ||
      !SetNamedPropertyChecked(env, obj, "lastKeyAction",
                               MakeInt32(env, stats.lastKeyAction))) {
    return nullptr;
  }

  return obj;
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterQueryNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredGetState", nullptr, GetEngineState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredWaitForState", nullptr, WaitForEngineState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredWaitForStateAsync", nullptr, WaitForEngineStateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetLastErrorInfo", nullptr, GetLastErrorInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredClearLastErrorInfo", nullptr, ClearLastErrorInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetFilesDir", nullptr, SetFilesDir, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetStats", nullptr, GetStats, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetStats", nullptr, ResetStats, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetInputDebugStats", nullptr, GetInputDebugStats, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetRegion", nullptr, GetRegion, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetRegionAsync", nullptr, GetRegionAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetAVInfo", nullptr, GetAVInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredHasCoreLoaded", nullptr, HasCoreLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredHasGameLoaded", nullptr, HasGameLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterQueryNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
