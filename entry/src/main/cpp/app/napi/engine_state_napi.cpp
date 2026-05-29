#include "engine_napi_common.h"

static napi_value GetSaveStateSize(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t size = GetEngine()->GetSaveStateSize();
  napi_value result;
  napi_create_int64(env, static_cast<int64_t>(size), &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- GetSaveStateSizeAsync (T8-B-F3) ---
// 同步版会阻塞 NAPI/UI 主线程最长 5s (kSyncTaskTimeoutMs)。
// 新调用方应使用 Async 变体;同步版保留兼容性,但 LibretroEngine::GetSaveStateSize 已加 state guard。
struct GetSaveStateSizeAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  size_t size = 0;
};

static void ExecuteGetSaveStateSizeAsync(napi_env env, void *data) {
  auto *ctx = static_cast<GetSaveStateSizeAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->size = GetEngine()->GetSaveStateSize();
}

static void CompleteGetSaveStateSizeAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<GetSaveStateSizeAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  // T8-B-F4: cancel guard.
  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] GetSaveStateSizeAsync cancelled; skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }
  if (status != napi_ok) {
    napi_value reason;
    napi_get_undefined(env, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
  } else {
    napi_value result;
    napi_create_int64(env, static_cast<int64_t>(ctx->size), &result);
    napi_resolve_deferred(env, ctx->deferred, result);
  }
  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value GetSaveStateSizeAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new GetSaveStateSizeAsyncContext();
  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }
  napi_value resourceName;
  napi_create_string_utf8(env, "GetSaveStateSizeAsync", NAPI_AUTO_LENGTH, &resourceName);
  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteGetSaveStateSizeAsync,
      CompleteGetSaveStateSizeAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] GetSaveStateSizeAsync create work failed");
    napi_value reason;
    napi_create_string_utf8(env, "async_work_create_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }
  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] GetSaveStateSizeAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value reason;
    napi_create_string_utf8(env, "async_work_queue_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }
  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SaveState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  std::vector<uint8_t> data;
  bool ok = GetEngine()->SaveState(data);
  if (!ok || data.empty()) {
    napi_value result;
    napi_get_null(env, &result);
    return result;
  }
  void *bufferData = nullptr;
  napi_value arrayBuffer;
  if (napi_create_arraybuffer(env, data.size(), &bufferData, &arrayBuffer) !=
          napi_ok ||
      !bufferData) {
    LOGF(LOG_ERROR, "[NEW] SaveState failed to allocate ArrayBuffer");
    napi_value result;
    napi_get_null(env, &result);
    return result;
  }
  std::memcpy(bufferData, data.data(), data.size());
  return arrayBuffer;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value LoadState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "LoadState")) {
    return MakeBool(env, false);
  }

  void *data = nullptr;
  size_t length = 0;
  if (!GetArrayBufferArg(env, args[0], &data, &length, "LoadState", "state")) {
    return MakeBool(env, false);
  }

  std::vector<uint8_t> stateData(static_cast<uint8_t *>(data),
                                  static_cast<uint8_t *>(data) + length);
  bool ok = GetEngine()->LoadState(stateData);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetSRAM(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  std::vector<uint8_t> data;
  bool ok = GetEngine()->GetSRAM(data);
  if (!ok || data.empty()) {
    napi_value result;
    napi_get_null(env, &result);
    return result;
  }
  void *bufferData = nullptr;
  napi_value arrayBuffer;
  if (napi_create_arraybuffer(env, data.size(), &bufferData, &arrayBuffer) !=
          napi_ok ||
      !bufferData) {
    LOGF(LOG_ERROR, "[NEW] GetSRAM failed to allocate ArrayBuffer");
    napi_value result;
    napi_get_null(env, &result);
    return result;
  }
  std::memcpy(bufferData, data.data(), data.size());
  return arrayBuffer;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetSRAM(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetSRAM")) {
    return MakeBool(env, false);
  }

  void *data = nullptr;
  size_t length = 0;
  if (!GetArrayBufferArg(env, args[0], &data, &length, "SetSRAM", "sram")) {
    return MakeBool(env, false);
  }

  std::vector<uint8_t> sramData(static_cast<uint8_t *>(data),
                                 static_cast<uint8_t *>(data) + length);
  bool ok = GetEngine()->SetSRAM(sramData);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ResetCore(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] ResetCore called");
  GetEngine()->ResetCore();
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value CheatReset(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  GetEngine()->CheatReset();
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value CheatSet(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "CheatSet")) {
    return MakeBool(env, false);
  }

  int32_t index = 0;
  bool enabled = false;
  char code[256];
  if (!GetInt32Arg(env, args[0], index, "CheatSet", "index") ||
      !GetBoolArg(env, args[1], enabled, "CheatSet", "enabled") ||
      !GetStringArg(env, args[2], code, sizeof(code), "CheatSet", "code")) {
    return MakeBool(env, false);
  }
  if (index < 0) {
    LOGF(LOG_ERROR, "[NEW] CheatSet invalid index: %{public}d", index);
    return MakeBool(env, false);
  }

  bool ok = GetEngine()->CheatSet(static_cast<unsigned>(index), enabled, code);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetCoreOptions(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  std::string j = GetEngine()->GetCoreOptionsJson();
  napi_value result;
  napi_create_string_utf8(env, j.c_str(), NAPI_AUTO_LENGTH, &result);
  return result;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetCoreOption(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetCoreOption")) {
    return MakeBool(env, false);
  }
  char key[256];
  char val[256];
  if (!GetStringArg(env, args[0], key, sizeof(key), "SetCoreOption", "key") ||
      !GetStringArg(env, args[1], val, sizeof(val), "SetCoreOption", "value")) {
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->SetCoreOption(key, val);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- SaveStateAsync (napi_async_work) ---
struct SaveStateAsyncContext {
  // Audit T1-F3: removed unused napi_env env field
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::vector<uint8_t> data;
  bool ok = false;
};

static void ExecuteSaveStateAsync(napi_env env, void *data) {
  auto *ctx = static_cast<SaveStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->SaveState(ctx->data);
}

static void CompleteSaveStateAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<SaveStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  // T8-B-F4: env teardown 时 status == napi_cancelled,任何 napi_* 调用都是 UB。
  // 必须先单独处理 cancel,不能与 napi_ok 之外的"逻辑失败"混在同一分支。
  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] SaveStateAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  // Audit T1-F2: cancel guard first; logical failures reject so ArkTS .catch() is reachable
  if (status != napi_ok) {
    napi_value reason;
    napi_get_undefined(env, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
  } else if (!ctx->ok || ctx->data.empty()) {
    napi_value reason;
    napi_create_string_utf8(env, "SaveState failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
  } else {
    void *bufferData = nullptr;
    napi_value arrayBuffer;
    if (napi_create_arraybuffer(env, ctx->data.size(), &bufferData, &arrayBuffer) ==
            napi_ok &&
        bufferData) {
      std::memcpy(bufferData, ctx->data.data(), ctx->data.size());
      napi_resolve_deferred(env, ctx->deferred, arrayBuffer);
    } else {
      LOGF(LOG_ERROR, "[NEW] SaveStateAsync failed to allocate ArrayBuffer");
      napi_value reason;
      napi_create_string_utf8(env, "SaveState ArrayBuffer alloc failed", NAPI_AUTO_LENGTH, &reason);
      napi_reject_deferred(env, ctx->deferred, reason);
    }
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value SaveStateAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new SaveStateAsyncContext();
  // Audit T1-F3: env field removed from ctx

  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) { // Audit T1-F8: check create_promise
    delete ctx;
    return nullptr;
  }

  napi_value resourceName;
  napi_create_string_utf8(env, "SaveStateAsync", NAPI_AUTO_LENGTH, &resourceName);

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSaveStateAsync,
      CompleteSaveStateAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] SaveStateAsync create work failed");
    napi_value reason;
    napi_create_string_utf8(env, "async_work_create_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] SaveStateAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value reason;
    napi_create_string_utf8(env, "async_work_queue_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- LoadStateAsync (napi_async_work) ---
struct LoadStateAsyncContext {
  // Audit T1-F3: removed unused napi_env env field
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::vector<uint8_t> stateData;
  bool ok = false;
};

static void ExecuteLoadStateAsync(napi_env env, void *data) {
  auto *ctx = static_cast<LoadStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->LoadState(ctx->stateData);
}

static void CompleteLoadStateAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<LoadStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  // T8-B-F4: env teardown 时 status == napi_cancelled,必须先单独处理。
  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] LoadStateAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  // Audit T1-F2: guard against napi_cancelled; napi_get_boolean/napi_resolve_deferred on cancelled env is UB
  if (status != napi_ok) {
    napi_value reason;
    napi_get_undefined(env, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
  } else {
    if (!ctx->ok) {
      LOGF(LOG_WARN, "[NEW] LoadStateAsync completed with failure: ok=false");
    }
    napi_value result;
    napi_get_boolean(env, ctx->ok, &result);
    napi_resolve_deferred(env, ctx->deferred, result);
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value LoadStateAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "LoadStateAsync")) {
    return MakeResolvedPromise(env, false);
  }

  void *data = nullptr;
  size_t length = 0;
  if (!GetArrayBufferArg(env, args[0], &data, &length, "LoadStateAsync", "state")) {
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new LoadStateAsyncContext();
  // Audit T1-F3: env field removed from ctx
  ctx->stateData.assign(static_cast<uint8_t *>(data),
                        static_cast<uint8_t *>(data) + length);

  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) { // Audit T1-F8: check create_promise
    delete ctx;
    return nullptr;
  }

  napi_value resourceName;
  napi_create_string_utf8(env, "LoadStateAsync", NAPI_AUTO_LENGTH, &resourceName);

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteLoadStateAsync,
      CompleteLoadStateAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] LoadStateAsync create work failed");
    napi_value reason;
    napi_create_string_utf8(env, "async_work_create_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] LoadStateAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value reason;
    napi_create_string_utf8(env, "async_work_queue_failed", NAPI_AUTO_LENGTH, &reason);
    napi_reject_deferred(env, ctx->deferred, reason);
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterStateNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredGetSaveStateSize", nullptr, GetSaveStateSize, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetSaveStateSizeAsync", nullptr, GetSaveStateSizeAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveState", nullptr, SaveState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadState", nullptr, LoadState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveStateAsync", nullptr, SaveStateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadStateAsync", nullptr, LoadStateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetSRAM", nullptr, GetSRAM, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetSRAM", nullptr, SetSRAM, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetCore", nullptr, ResetCore, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatReset", nullptr, CheatReset, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatSet", nullptr, CheatSet, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetCoreOptions", nullptr, GetCoreOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetCoreOption", nullptr, SetCoreOption, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterStateNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
