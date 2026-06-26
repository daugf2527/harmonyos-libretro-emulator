#include "engine_napi_common.h"
#include <cstring>

namespace {

constexpr int32_t kMaxCheatIndex = 1023;
constexpr size_t kMaxCheatCodeLength = 240;

void SetStateError(const char *reason, const char *step, const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

void EnsureStateErrorIfEmpty(const char *reason, const char *step,
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

bool IsValidCheatCode(const char *code) {
  if (!code) {
    return false;
  }

  const size_t length = std::strlen(code);
  if (length == 0 || length > kMaxCheatCodeLength) {
    return false;
  }

  for (size_t i = 0; i < length; ++i) {
    const auto ch = static_cast<unsigned char>(code[i]);
    if (ch < 0x20 || ch > 0x7E) {
      return false;
    }
  }

  return true;
}

} // namespace

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
    SetStateError("save_state_size_async_work_failed", "GetSaveStateSizeAsync",
                  "Async save-state-size completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = MakeInt64(env, static_cast<int64_t>(ctx->size));
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("save_state_size_result_alloc_failed", "GetSaveStateSizeAsync",
                    "Failed to allocate async save-state-size result value");
      napi_value reason = MakeString(env, "GetSaveStateSizeAsync result alloc failed");
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
    SetStateError("save_state_size_async_create_failed", "GetSaveStateSizeAsync",
                  "Failed to create async resource name");
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
    SetStateError("save_state_size_async_create_failed", "GetSaveStateSizeAsync",
                  "Failed to create async save-state-size work item");
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
    SetStateError("save_state_size_async_queue_failed", "GetSaveStateSizeAsync",
                  "Failed to queue async save-state-size work item");
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
  if (!ok) {
    EnsureStateErrorIfEmpty("load_state_failed", "LoadState",
                            "LoadState returned false");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetSRAM(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  std::vector<uint8_t> data;
  bool ok = GetEngine()->GetSRAM(data);
  if (!ok || data.empty()) {
    EnsureStateErrorIfEmpty("get_sram_failed", "GetSRAM",
                            "SRAM snapshot is unavailable in current core state");
    return MakeNull(env);
  }
  napi_value arrayBuffer =
      MakeArrayBufferFromBytes(env, data.data(), data.size());
  if (!arrayBuffer) {
    LOGF(LOG_ERROR, "[NEW] GetSRAM failed to allocate ArrayBuffer");
    SetStateError("get_sram_alloc_failed", "GetSRAM",
                  "Failed to allocate ArrayBuffer for SRAM snapshot");
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
  if (!ok) {
    EnsureStateErrorIfEmpty("set_sram_failed", "SetSRAM",
                            "Core rejected the provided SRAM data");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct GetSRAMAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::vector<uint8_t> data;
  bool ok = false;
};

static void ExecuteGetSRAMAsync(napi_env env, void *data) {
  auto *ctx = static_cast<GetSRAMAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->GetSRAM(ctx->data);
}

static void CompleteGetSRAMAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<GetSRAMAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] GetSRAMAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("get_sram_async_work_failed", "GetSRAMAsync",
                  "Async get-sram completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else if (!ctx->ok || ctx->data.empty()) {
    EnsureStateErrorIfEmpty("get_sram_failed", "GetSRAMAsync",
                            "SRAM snapshot is unavailable in current core state");
    napi_value result = MakeNull(env);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("get_sram_null_result_alloc_failed", "GetSRAMAsync",
                    "Failed to allocate async get-sram null result value");
      napi_value reason = MakeString(env, "GetSRAMAsync null result alloc failed");
      if (reason) {
        (void)RejectDeferredChecked(env, ctx->deferred, reason);
      }
    }
  } else {
    napi_value arrayBuffer =
        MakeArrayBufferFromBytes(env, ctx->data.data(), ctx->data.size());
    if (arrayBuffer) {
      (void)ResolveDeferredChecked(env, ctx->deferred, arrayBuffer);
    } else {
      LOGF(LOG_ERROR, "[NEW] GetSRAMAsync failed to allocate ArrayBuffer");
      SetStateError("get_sram_alloc_failed", "GetSRAMAsync",
                    "Failed to allocate ArrayBuffer for SRAM snapshot");
      napi_value reason = MakeString(env, "GetSRAM ArrayBuffer alloc failed");
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

static napi_value GetSRAMAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new GetSRAMAsyncContext();

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "GetSRAMAsync");
  if (!resourceName) {
    SetStateError("get_sram_async_create_failed", "GetSRAMAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteGetSRAMAsync,
      CompleteGetSRAMAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("get_sram_async_create_failed", "GetSRAMAsync",
                  "Failed to create async get-sram work item");
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
    SetStateError("get_sram_async_queue_failed", "GetSRAMAsync",
                  "Failed to queue async get-sram work item");
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

struct SetSRAMAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::vector<uint8_t> data;
  bool ok = false;
};

static void ExecuteSetSRAMAsync(napi_env env, void *data) {
  auto *ctx = static_cast<SetSRAMAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->SetSRAM(ctx->data);
}

static void CompleteSetSRAMAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<SetSRAMAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] SetSRAMAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("set_sram_async_work_failed", "SetSRAMAsync",
                  "Async set-sram completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureStateErrorIfEmpty("set_sram_failed", "SetSRAMAsync",
                              "Core rejected the provided SRAM data");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("set_sram_result_alloc_failed", "SetSRAMAsync",
                    "Failed to allocate async set-sram result value");
      napi_value reason = MakeString(env, "SetSRAMAsync result alloc failed");
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

static napi_value SetSRAMAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetSRAMAsync")) {
    return MakeResolvedPromise(env, false);
  }

  void *data = nullptr;
  size_t length = 0;
  if (!GetArrayBufferArg(env, args[0], &data, &length, "SetSRAMAsync", "sram")) {
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new SetSRAMAsyncContext();
  ctx->data.assign(static_cast<uint8_t *>(data),
                   static_cast<uint8_t *>(data) + length);

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "SetSRAMAsync");
  if (!resourceName) {
    SetStateError("set_sram_async_create_failed", "SetSRAMAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSetSRAMAsync,
      CompleteSetSRAMAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("set_sram_async_create_failed", "SetSRAMAsync",
                  "Failed to create async set-sram work item");
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
    SetStateError("set_sram_async_queue_failed", "SetSRAMAsync",
                  "Failed to queue async set-sram work item");
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

static napi_value ResetCore(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] ResetCore called");
  const bool ok = GetEngine()->ResetCore();
  if (!ok) {
    EnsureStateErrorIfEmpty("reset_core_failed", "ResetCore",
                            "ResetCore returned false");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct ResetCoreAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  bool ok = false;
};

static void ExecuteResetCoreAsync(napi_env env, void *data) {
  auto *ctx = static_cast<ResetCoreAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->ResetCore();
}

static void CompleteResetCoreAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<ResetCoreAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] ResetCoreAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("reset_core_async_work_failed", "ResetCoreAsync",
                  "Async reset-core completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureStateErrorIfEmpty("reset_core_failed", "ResetCoreAsync",
                              "ResetCore returned false");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("reset_core_result_alloc_failed", "ResetCoreAsync",
                    "Failed to allocate async reset-core result value");
      napi_value reason = MakeString(env, "ResetCoreAsync result alloc failed");
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

static napi_value ResetCoreAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new ResetCoreAsyncContext();

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "ResetCoreAsync");
  if (!resourceName) {
    SetStateError("reset_core_async_create_failed", "ResetCoreAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteResetCoreAsync,
      CompleteResetCoreAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("reset_core_async_create_failed", "ResetCoreAsync",
                  "Failed to create async reset-core work item");
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
    SetStateError("reset_core_async_queue_failed", "ResetCoreAsync",
                  "Failed to queue async reset-core work item");
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

static napi_value CheatReset(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  const bool ok = GetEngine()->CheatReset();
  if (!ok) {
    EnsureStateErrorIfEmpty("cheat_reset_failed", "CheatReset",
                            "CheatReset returned false");
  }
  return MakeBool(env, ok);
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
  if (index < 0 || index > kMaxCheatIndex) {
    LOGF(LOG_ERROR, "[NEW] CheatSet invalid index: %{public}d", index);
    GetEngine()->SetLastErrorInfo("cheat_index_invalid", "CheatSet",
                                  "Cheat index is outside supported range");
    return MakeBool(env, false);
  }
  if (!IsValidCheatCode(code)) {
    LOGF(LOG_ERROR, "[NEW] CheatSet invalid code format");
    GetEngine()->SetLastErrorInfo("cheat_code_invalid", "CheatSet",
                                  "Cheat code format is invalid");
    return MakeBool(env, false);
  }

  bool ok = GetEngine()->CheatSet(static_cast<unsigned>(index), enabled, code);
  if (!ok) {
    EnsureStateErrorIfEmpty("cheat_set_failed", "CheatSet",
                            "CheatSet returned false");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct CheatResetAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  bool ok = false;
};

static void ExecuteCheatResetAsync(napi_env env, void *data) {
  auto *ctx = static_cast<CheatResetAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->CheatReset();
}

static void CompleteCheatResetAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<CheatResetAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] CheatResetAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("cheat_reset_async_work_failed", "CheatResetAsync",
                  "Async cheat-reset completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureStateErrorIfEmpty("cheat_reset_failed", "CheatResetAsync",
                              "CheatReset returned false");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("cheat_reset_result_alloc_failed", "CheatResetAsync",
                    "Failed to allocate async cheat-reset result value");
      napi_value reason = MakeString(env, "CheatResetAsync result alloc failed");
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

static napi_value CheatResetAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new CheatResetAsyncContext();

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "CheatResetAsync");
  if (!resourceName) {
    SetStateError("cheat_reset_async_create_failed", "CheatResetAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteCheatResetAsync,
      CompleteCheatResetAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("cheat_reset_async_create_failed", "CheatResetAsync",
                  "Failed to create async cheat-reset work item");
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
    SetStateError("cheat_reset_async_queue_failed", "CheatResetAsync",
                  "Failed to queue async cheat-reset work item");
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

struct CheatSetAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  unsigned index = 0;
  bool enabled = false;
  std::string code;
  bool ok = false;
};

static void ExecuteCheatSetAsync(napi_env env, void *data) {
  auto *ctx = static_cast<CheatSetAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->CheatSet(ctx->index, ctx->enabled, ctx->code);
}

static void CompleteCheatSetAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<CheatSetAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] CheatSetAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("cheat_set_async_work_failed", "CheatSetAsync",
                  "Async cheat-set completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureStateErrorIfEmpty("cheat_set_failed", "CheatSetAsync",
                              "CheatSet returned false");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("cheat_set_result_alloc_failed", "CheatSetAsync",
                    "Failed to allocate async cheat-set result value");
      napi_value reason = MakeString(env, "CheatSetAsync result alloc failed");
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

static napi_value CheatSetAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "CheatSetAsync")) {
    return MakeResolvedPromise(env, false);
  }

  int32_t index = 0;
  bool enabled = false;
  char code[256];
  if (!GetInt32Arg(env, args[0], index, "CheatSetAsync", "index") ||
      !GetBoolArg(env, args[1], enabled, "CheatSetAsync", "enabled") ||
      !GetStringArg(env, args[2], code, sizeof(code), "CheatSetAsync", "code")) {
    return MakeResolvedPromise(env, false);
  }
  if (index < 0 || index > kMaxCheatIndex) {
    LOGF(LOG_ERROR, "[NEW] CheatSetAsync invalid index: %{public}d", index);
    GetEngine()->SetLastErrorInfo("cheat_index_invalid", "CheatSetAsync",
                                  "Cheat index is outside supported range");
    return MakeResolvedPromise(env, false);
  }
  if (!IsValidCheatCode(code)) {
    LOGF(LOG_ERROR, "[NEW] CheatSetAsync invalid code format");
    GetEngine()->SetLastErrorInfo("cheat_code_invalid", "CheatSetAsync",
                                  "Cheat code format is invalid");
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new CheatSetAsyncContext();
  ctx->index = static_cast<unsigned>(index);
  ctx->enabled = enabled;
  ctx->code = code;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "CheatSetAsync");
  if (!resourceName) {
    SetStateError("cheat_set_async_create_failed", "CheatSetAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteCheatSetAsync,
      CompleteCheatSetAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("cheat_set_async_create_failed", "CheatSetAsync",
                  "Failed to create async cheat-set work item");
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
    SetStateError("cheat_set_async_queue_failed", "CheatSetAsync",
                  "Failed to queue async cheat-set work item");
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
  if (!ok) {
    EnsureStateErrorIfEmpty("core_option_set_failed", "SetCoreOption",
                            "Core rejected the requested option update");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct GetCoreOptionsAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::string json;
};

static void ExecuteGetCoreOptionsAsync(napi_env env, void *data) {
  auto *ctx = static_cast<GetCoreOptionsAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->json = GetEngine()->GetCoreOptionsJson();
}

static void CompleteGetCoreOptionsAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<GetCoreOptionsAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] GetCoreOptionsAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("core_options_async_work_failed", "GetCoreOptionsAsync",
                  "Async core-options completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = MakeString(env, ctx->json);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("core_options_result_alloc_failed", "GetCoreOptionsAsync",
                    "Failed to allocate async core-options result string");
      napi_value reason = MakeString(env, "GetCoreOptionsAsync result alloc failed");
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

static napi_value GetCoreOptionsAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *ctx = new GetCoreOptionsAsyncContext();

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "GetCoreOptionsAsync");
  if (!resourceName) {
    SetStateError("core_options_async_create_failed", "GetCoreOptionsAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteGetCoreOptionsAsync,
      CompleteGetCoreOptionsAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("core_options_async_create_failed", "GetCoreOptionsAsync",
                  "Failed to create async core-options work item");
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
    SetStateError("core_options_async_queue_failed", "GetCoreOptionsAsync",
                  "Failed to queue async core-options work item");
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

struct SetCoreOptionAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::string key;
  std::string value;
  bool ok = false;
};

static void ExecuteSetCoreOptionAsync(napi_env env, void *data) {
  auto *ctx = static_cast<SetCoreOptionAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->ok = GetEngine()->SetCoreOption(ctx->key, ctx->value);
}

static void CompleteSetCoreOptionAsync(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<SetCoreOptionAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN, "[NEW] SetCoreOptionAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetStateError("core_option_set_async_work_failed", "SetCoreOptionAsync",
                  "Async core-option completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureStateErrorIfEmpty("core_option_set_failed", "SetCoreOptionAsync",
                              "Core rejected the requested option update");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("core_option_set_result_alloc_failed", "SetCoreOptionAsync",
                    "Failed to allocate async core-option result value");
      napi_value reason = MakeString(env, "SetCoreOptionAsync result alloc failed");
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

static napi_value SetCoreOptionAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetCoreOptionAsync")) {
    return MakeResolvedPromise(env, false);
  }
  char key[256];
  char val[256];
  if (!GetStringArg(env, args[0], key, sizeof(key), "SetCoreOptionAsync", "key") ||
      !GetStringArg(env, args[1], val, sizeof(val), "SetCoreOptionAsync", "value")) {
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new SetCoreOptionAsyncContext();
  ctx->key = key;
  ctx->value = val;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "SetCoreOptionAsync");
  if (!resourceName) {
    SetStateError("core_option_set_async_create_failed", "SetCoreOptionAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSetCoreOptionAsync,
      CompleteSetCoreOptionAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetStateError("core_option_set_async_create_failed", "SetCoreOptionAsync",
                  "Failed to create async core-option work item");
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
    SetStateError("core_option_set_async_queue_failed", "SetCoreOptionAsync",
                  "Failed to queue async core-option work item");
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
    SetStateError("save_state_async_work_failed", "SaveStateAsync",
                  "Async save-state completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else if (!ctx->ok || ctx->data.empty()) {
    EnsureStateErrorIfEmpty("save_state_failed", "SaveStateAsync",
                            "Save-state serialization returned no data");
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
      SetStateError("save_state_alloc_failed", "SaveStateAsync",
                    "Failed to allocate ArrayBuffer for save-state data");
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
    SetStateError("save_state_async_create_failed", "SaveStateAsync",
                  "Failed to create async resource name");
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
    SetStateError("save_state_async_create_failed", "SaveStateAsync",
                  "Failed to create async save-state work item");
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
    SetStateError("save_state_async_queue_failed", "SaveStateAsync",
                  "Failed to queue async save-state work item");
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
    SetStateError("save_state_bundle_async_work_failed",
                  "SaveStateBundleAsync",
                  "Async save-state-bundle completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else if (!ctx->ok || ctx->bundle.stateData.empty()) {
    EnsureStateErrorIfEmpty("save_state_bundle_failed",
                            "SaveStateBundleAsync",
                            "Save-state bundle capture returned no state data");
    napi_value reason = MakeString(env, "SaveStateBundle failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = BuildSaveStateBundleResult(env, ctx->bundle);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("save_state_bundle_alloc_failed", "SaveStateBundleAsync",
                    "Failed to allocate save-state bundle result object");
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
    SetStateError("save_state_bundle_async_create_failed",
                  "SaveStateBundleAsync",
                  "Failed to create async resource name");
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
    SetStateError("save_state_bundle_async_create_failed",
                  "SaveStateBundleAsync",
                  "Failed to create async save-state-bundle work item");
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
    SetStateError("save_state_bundle_async_queue_failed",
                  "SaveStateBundleAsync",
                  "Failed to queue async save-state-bundle work item");
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
    SetStateError("load_state_async_work_failed", "LoadStateAsync",
                  "Async load-state completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      LOGF(LOG_WARN, "[NEW] LoadStateAsync completed with failure: ok=false");
      EnsureStateErrorIfEmpty("load_state_failed", "LoadStateAsync",
                              "Core rejected the provided save-state data");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    } else {
      SetStateError("load_state_result_alloc_failed", "LoadStateAsync",
                    "Failed to allocate async load-state result value");
      napi_value reason = MakeString(env, "LoadStateAsync result alloc failed");
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
    SetStateError("load_state_async_create_failed", "LoadStateAsync",
                  "Failed to create async resource name");
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
    SetStateError("load_state_async_create_failed", "LoadStateAsync",
                  "Failed to create async load-state work item");
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
    SetStateError("load_state_async_queue_failed", "LoadStateAsync",
                  "Failed to queue async load-state work item");
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
      {"refactoredGetSRAMAsync", nullptr, GetSRAMAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetSRAMAsync", nullptr, SetSRAMAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetCore", nullptr, ResetCore, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetCoreAsync", nullptr, ResetCoreAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatReset", nullptr, CheatReset, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatSet", nullptr, CheatSet, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatResetAsync", nullptr, CheatResetAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatSetAsync", nullptr, CheatSetAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetCoreOptions", nullptr, GetCoreOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetCoreOptionsAsync", nullptr, GetCoreOptionsAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetCoreOption", nullptr, SetCoreOption, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetCoreOptionAsync", nullptr, SetCoreOptionAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterStateNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
