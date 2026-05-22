#include "engine_napi_common.h"
#include "platform/audio/audio_bridge.h"
#include "app/framework/plugin_manager.h"

static napi_value GetEngineState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  libretro::EngineState state = GetEngine()->GetState();
  int32_t stateValue = static_cast<int32_t>(state);

  napi_value result;
  napi_create_int32(env, stateValue, &result);
  return result;
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
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct WaitForStateAsyncContext {
  napi_env env = nullptr;
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

  napi_value result;
  napi_get_boolean(env, ctx->result, &result);
  napi_resolve_deferred(env, ctx->deferred, result);

  napi_delete_async_work(env, ctx->work);
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
  ctx->env = env;
  ctx->target = static_cast<libretro::EngineState>(stateValue);
  ctx->timeoutMs = static_cast<uint32_t>(timeoutMs);
  ctx->work = nullptr;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return MakeResolvedPromise(env, false);
  }

  napi_value resourceName;
  if (napi_create_string_utf8(env, "WaitForEngineStateAsync", NAPI_AUTO_LENGTH,
                              &resourceName) != napi_ok) {
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  if (napi_create_async_work(env, nullptr, resourceName, ExecuteWaitForState,
                             CompleteWaitForState, ctx, &ctx->work) != napi_ok) {
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }
  if (napi_queue_async_work(env, ctx->work) != napi_ok) {
    napi_delete_async_work(env, ctx->work);
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetLastErrorInfo(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  const auto err = GetEngine()->GetLastErrorInfo();
  napi_value result;
  napi_create_object(env, &result);

  napi_value reason;
  napi_create_string_utf8(env, err.reason.c_str(), NAPI_AUTO_LENGTH, &reason);
  napi_set_named_property(env, result, "reason", reason);

  napi_value step;
  napi_create_string_utf8(env, err.step.c_str(), NAPI_AUTO_LENGTH, &step);
  napi_set_named_property(env, result, "step", step);

  napi_value message;
  napi_create_string_utf8(env, err.message.c_str(), NAPI_AUTO_LENGTH, &message);
  napi_set_named_property(env, result, "message", message);

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

  LOGF(LOG_INFO, " [NEW] SetFilesDir: %{public}s", path);
  const bool ok = GetEngine()->SetFilesDir(path);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value HasCoreLoaded(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool loaded = GetEngine()->HasCoreLoaded();
  napi_value result;
  napi_get_boolean(env, loaded, &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value HasGameLoaded(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool loaded = GetEngine()->HasGameLoaded();
  napi_value result;
  napi_get_boolean(env, loaded, &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetRegion(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  unsigned region = GetEngine()->GetRegion();
  napi_value result;
  napi_create_uint32(env, region, &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetAVInfo(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *engine = GetEngine();

  napi_value obj;
  napi_create_object(env, &obj);

  napi_value val;
  napi_create_uint32(env, engine->GetVideoWidth(), &val);
  napi_set_named_property(env, obj, "videoWidth", val);

  napi_create_uint32(env, engine->GetVideoHeight(), &val);
  napi_set_named_property(env, obj, "videoHeight", val);

  napi_create_double(env, engine->GetFps(), &val);
  napi_set_named_property(env, obj, "fps", val);

  napi_create_double(env, engine->GetAudioSampleRate(), &val);
  napi_set_named_property(env, obj, "audioSampleRate", val);

  return obj;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetStats(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto stats = GetEngine()->GetStats();

  napi_value obj;
  napi_create_object(env, &obj);

  napi_value val;
  #define SET_STAT(name) \
    napi_create_int64(env, static_cast<int64_t>(stats.name), &val); \
    napi_set_named_property(env, obj, #name, val)

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
    napi_create_double(env, audioBridge->GetBufferUsage(), &val);
    napi_set_named_property(env, obj, "audioBufferUsage", val);

    size_t underruns = 0, overruns = 0;
    audioBridge->GetBufferStats(underruns, overruns);
    napi_create_int64(env, static_cast<int64_t>(underruns), &val);
    napi_set_named_property(env, obj, "audioUnderruns", val);
    napi_create_int64(env, static_cast<int64_t>(overruns), &val);
    napi_set_named_property(env, obj, "audioOverruns", val);
  } else {
    napi_create_double(env, 0.0, &val);
    napi_set_named_property(env, obj, "audioBufferUsage", val);
    napi_create_int64(env, 0, &val);
    napi_set_named_property(env, obj, "audioUnderruns", val);
    napi_set_named_property(env, obj, "audioOverruns", val);
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

  napi_value obj;
  napi_create_object(env, &obj);

  napi_value val;
  napi_create_int64(env, static_cast<int64_t>(stats.touchCount), &val);
  napi_set_named_property(env, obj, "touchCount", val);
  napi_create_int64(env, static_cast<int64_t>(stats.mouseCount), &val);
  napi_set_named_property(env, obj, "mouseCount", val);
  napi_create_int64(env, static_cast<int64_t>(stats.keyCount), &val);
  napi_set_named_property(env, obj, "keyCount", val);

  napi_get_boolean(env, stats.hasFocus, &val);
  napi_set_named_property(env, obj, "hasFocus", val);
  napi_get_boolean(env, stats.mouseDown, &val);
  napi_set_named_property(env, obj, "mouseDown", val);

  napi_create_int32(env, stats.lastTouchType, &val);
  napi_set_named_property(env, obj, "lastTouchType", val);
  napi_create_int32(env, stats.lastMouseAction, &val);
  napi_set_named_property(env, obj, "lastMouseAction", val);
  napi_create_int32(env, stats.lastKeyAction, &val);
  napi_set_named_property(env, obj, "lastKeyAction", val);

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
      {"refactoredGetAVInfo", nullptr, GetAVInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredHasCoreLoaded", nullptr, HasCoreLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredHasGameLoaded", nullptr, HasGameLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
