#include "engine_napi_common.h"

static napi_value GetSaveStateSize(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t size = GetEngine()->GetSaveStateSize();
  return MakeInt64(env, static_cast<int64_t>(size));
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
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = MakeInt64(env, static_cast<int64_t>(ctx->size));
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    }
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
  napi_value resourceName = MakeString(env, "GetSaveStateSizeAsync");
  if (!resourceName) {
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }
  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteGetSaveStateSizeAsync,
      CompleteGetSaveStateSizeAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] GetSaveStateSizeAsync create work failed");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }
  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] GetSaveStateSizeAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
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

static napi_value SaveState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  std::vector<uint8_t> data;
  bool ok = GetEngine()->SaveState(data);
  if (!ok || data.empty()) {
    auto errorInfo = GetEngine()->GetLastErrorInfo();
    const char *message = errorInfo.message.empty()
        ? "Save state failed"
        : errorInfo.message.c_str();

    LOGF(LOG_ERROR, "[NEW] SaveState failed: %{public}s", message);
    // D014: 声明 `() => ArrayBuffer | null`,失败须返回 null(对齐同文件 GetSRAM
    // L161/166 范式),此前返回 MakeErrorResult 结构对象 → ArkTS `if(!buf)` 对
    // truthy 结构对象漏判失败(D010/D011/D012 同类型谎言)。errorCode 经
    // refactoredGetLastErrorInfo 仍可查;推荐用 refactoredSaveStateAsync(reject)。
    return MakeNull(env);
  }

  // 成功时返回 ArrayBuffer（保持向后兼容）
  napi_value arrayBuffer =
      MakeArrayBufferFromBytes(env, data.data(), data.size());
  if (!arrayBuffer) {
    LOGF(LOG_ERROR, "[NEW] SaveState failed to allocate ArrayBuffer");
    return MakeNull(env);
  }
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
    return MakeNull(env);
  }
  napi_value arrayBuffer =
      MakeArrayBufferFromBytes(env, data.data(), data.size());
  if (!arrayBuffer) {
    LOGF(LOG_ERROR, "[NEW] GetSRAM failed to allocate ArrayBuffer");
    return MakeNull(env);
  }
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
  return MakeString(env, j);
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
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else if (!ctx->ok || ctx->data.empty()) {
    napi_value reason = MakeString(env, "SaveState failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value arrayBuffer =
        MakeArrayBufferFromBytes(env, ctx->data.data(), ctx->data.size());
    if (arrayBuffer) {
      (void)ResolveDeferredChecked(env, ctx->deferred, arrayBuffer);
    } else {
      LOGF(LOG_ERROR, "[NEW] SaveStateAsync failed to allocate ArrayBuffer");
      napi_value reason = MakeString(env, "SaveState ArrayBuffer alloc failed");
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

static napi_value SaveStateAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new SaveStateAsyncContext();
  // Audit T1-F3: env field removed from ctx

  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) { // Audit T1-F8: check create_promise
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "SaveStateAsync");
  if (!resourceName) {
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSaveStateAsync,
      CompleteSaveStateAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] SaveStateAsync create work failed");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] SaveStateAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
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

static napi_value BuildSaveStateBundleResult(napi_env env,
                                             const SaveStateCaptureBundle &bundle) {
  napi_value result = MakeObject(env);
  if (!result) {
    return nullptr;
  }

  napi_value stateData =
      MakeArrayBufferFromBytes(env, bundle.stateData.data(),
                               bundle.stateData.size());
  if (!stateData ||
      !SetNamedPropertyChecked(env, result, "stateData", stateData)) {
    return nullptr;
  }

  napi_value thumbnailData = MakeNull(env);
  if (!bundle.thumbnail.rgba.empty() && bundle.thumbnail.width > 0 &&
      bundle.thumbnail.height > 0) {
    thumbnailData = MakeArrayBufferFromBytes(env, bundle.thumbnail.rgba.data(),
                                             bundle.thumbnail.rgba.size());
  }
  if (!thumbnailData ||
      !SetNamedPropertyChecked(env, result, "thumbnailRgba", thumbnailData) ||
      !SetNamedPropertyChecked(env, result, "thumbnailWidth",
                               MakeUint32(env, bundle.thumbnail.width)) ||
      !SetNamedPropertyChecked(env, result, "thumbnailHeight",
                               MakeUint32(env, bundle.thumbnail.height))) {
    return nullptr;
  }
  return result;
}

struct SaveStateBundleAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  SaveStateCaptureBundle bundle;
  bool ok = false;
};

static void ExecuteSaveStateBundleAsync(napi_env env, void *data) {
  auto *ctx = static_cast<SaveStateBundleAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->CaptureSaveStateBundle(ctx->bundle);
}

static void CompleteSaveStateBundleAsync(napi_env env, napi_status status,
                                         void *data) {
  auto *ctx = static_cast<SaveStateBundleAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] SaveStateBundleAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else if (!ctx->ok || ctx->bundle.stateData.empty()) {
    napi_value reason = MakeString(env, "SaveStateBundle failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = BuildSaveStateBundleResult(env, ctx->bundle);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      napi_value reason = MakeString(env, "SaveStateBundle result alloc failed");
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

static napi_value SaveStateBundleAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new SaveStateBundleAsyncContext();

  napi_value promise;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "SaveStateBundleAsync");
  if (!resourceName) {
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus =
      napi_create_async_work(env, nullptr, resourceName,
                             ExecuteSaveStateBundleAsync,
                             CompleteSaveStateBundleAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] SaveStateBundleAsync create work failed");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] SaveStateBundleAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
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
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      LOGF(LOG_WARN, "[NEW] LoadStateAsync completed with failure: ok=false");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    }
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

  napi_value resourceName = MakeString(env, "LoadStateAsync");
  if (!resourceName) {
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteLoadStateAsync,
      CompleteLoadStateAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] LoadStateAsync create work failed");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] LoadStateAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
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

void RegisterStateNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredGetSaveStateSize", nullptr, GetSaveStateSize, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetSaveStateSizeAsync", nullptr, GetSaveStateSizeAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveState", nullptr, SaveState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadState", nullptr, LoadState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveStateAsync", nullptr, SaveStateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveStateBundleAsync", nullptr, SaveStateBundleAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
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
