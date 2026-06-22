#include "engine_napi_common.h"
#include "common/file_security.h"

namespace {

void SetDiskError(const char *reason, const char *step, const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

void EnsureDiskErrorIfEmpty(const char *reason, const char *step,
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

} // namespace

struct DiskControlSnapshotAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  bool ejected = false;
  unsigned imageIndex = 0;
  unsigned imageCount = 0;
};

struct DiskControlSetEjectStateAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  bool ejected = false;
  bool ok = false;
};

struct DiskControlSetImageIndexAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  unsigned index = 0;
  bool ok = false;
};

static napi_value DiskControlSetEjectState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "DiskControlSetEjectState")) {
    return MakeBool(env, false);
  }
  bool ejected = false;
  if (!GetBoolArg(env, args[0], ejected, "DiskControlSetEjectState", "ejected")) {
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->DiskControlSetEjectState(ejected);
  if (!ok) {
    EnsureDiskErrorIfEmpty("disk_set_eject_failed", "DiskControlSetEjectState",
                           "Core rejected the requested eject state");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlGetEjectState(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool ejected = GetEngine()->DiskControlGetEjectState();
  return MakeBool(env, ejected);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlGetImageIndex(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  unsigned index = GetEngine()->DiskControlGetImageIndex();
  return MakeUint32(env, index);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlSetImageIndex(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "DiskControlSetImageIndex")) {
    return MakeBool(env, false);
  }
  int32_t index = 0;
  if (!GetInt32Arg(env, args[0], index, "DiskControlSetImageIndex", "index")) {
    return MakeBool(env, false);
  }
  if (index < 0) {
    SetDiskError("disk_image_index_invalid", "DiskControlSetImageIndex",
                 "Disk image index must be non-negative");
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->DiskControlSetImageIndex(static_cast<unsigned>(index));
  if (!ok) {
    EnsureDiskErrorIfEmpty("disk_set_image_failed", "DiskControlSetImageIndex",
                           "Core rejected the requested disk image index");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlGetNumImages(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  unsigned num = GetEngine()->DiskControlGetNumImages();
  return MakeUint32(env, num);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static void ExecuteDiskControlSetEjectStateAsync(napi_env env, void *data) {
  auto *ctx = static_cast<DiskControlSetEjectStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  ctx->ok = engine->DiskControlSetEjectState(ctx->ejected);
}

static void CompleteDiskControlSetEjectStateAsync(napi_env env, napi_status status,
                                                  void *data) {
  auto *ctx = static_cast<DiskControlSetEjectStateAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] DiskControlSetEjectStateAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetDiskError("disk_set_eject_async_work_failed", "DiskControlSetEjectStateAsync",
                 "Async disk eject-state completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureDiskErrorIfEmpty("disk_set_eject_failed", "DiskControlSetEjectStateAsync",
                             "Core rejected the requested eject state");
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

static napi_value DiskControlSetEjectStateAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "DiskControlSetEjectStateAsync")) {
    return MakeResolvedPromise(env, false);
  }

  bool ejected = false;
  if (!GetBoolArg(env, args[0], ejected, "DiskControlSetEjectStateAsync", "ejected")) {
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new DiskControlSetEjectStateAsyncContext();
  ctx->ejected = ejected;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "DiskControlSetEjectStateAsync");
  if (!resourceName) {
    SetDiskError("disk_set_eject_async_create_failed", "DiskControlSetEjectStateAsync",
                 "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteDiskControlSetEjectStateAsync,
      CompleteDiskControlSetEjectStateAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetDiskError("disk_set_eject_async_create_failed", "DiskControlSetEjectStateAsync",
                 "Failed to create async disk eject-state work item");
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
    SetDiskError("disk_set_eject_async_queue_failed", "DiskControlSetEjectStateAsync",
                 "Failed to queue async disk eject-state work item");
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

static void ExecuteDiskControlSetImageIndexAsync(napi_env env, void *data) {
  auto *ctx = static_cast<DiskControlSetImageIndexAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  ctx->ok = engine->DiskControlSetImageIndex(ctx->index);
}

static void CompleteDiskControlSetImageIndexAsync(napi_env env, napi_status status,
                                                  void *data) {
  auto *ctx = static_cast<DiskControlSetImageIndexAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] DiskControlSetImageIndexAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetDiskError("disk_set_image_async_work_failed", "DiskControlSetImageIndexAsync",
                 "Async disk image-index completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureDiskErrorIfEmpty("disk_set_image_failed", "DiskControlSetImageIndexAsync",
                             "Core rejected the requested disk image index");
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

static napi_value DiskControlSetImageIndexAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "DiskControlSetImageIndexAsync")) {
    return MakeResolvedPromise(env, false);
  }

  int32_t index = 0;
  if (!GetInt32Arg(env, args[0], index, "DiskControlSetImageIndexAsync", "index")) {
    return MakeResolvedPromise(env, false);
  }
  if (index < 0) {
    SetDiskError("disk_image_index_invalid", "DiskControlSetImageIndexAsync",
                 "Disk image index must be non-negative");
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new DiskControlSetImageIndexAsyncContext();
  ctx->index = static_cast<unsigned>(index);

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "DiskControlSetImageIndexAsync");
  if (!resourceName) {
    SetDiskError("disk_set_image_async_create_failed", "DiskControlSetImageIndexAsync",
                 "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteDiskControlSetImageIndexAsync,
      CompleteDiskControlSetImageIndexAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetDiskError("disk_set_image_async_create_failed", "DiskControlSetImageIndexAsync",
                 "Failed to create async disk image-index work item");
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
    SetDiskError("disk_set_image_async_queue_failed", "DiskControlSetImageIndexAsync",
                 "Failed to queue async disk image-index work item");
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

static void ExecuteDiskControlGetSnapshotAsync(napi_env env, void *data) {
  auto *ctx = static_cast<DiskControlSnapshotAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  ctx->imageCount = engine->DiskControlGetNumImages();
  ctx->imageIndex = engine->DiskControlGetImageIndex();
  ctx->ejected = engine->DiskControlGetEjectState();
}

static void CompleteDiskControlGetSnapshotAsync(napi_env env, napi_status status,
                                                void *data) {
  auto *ctx = static_cast<DiskControlSnapshotAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] DiskControlGetSnapshotAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetDiskError("disk_snapshot_async_work_failed", "DiskControlGetSnapshotAsync",
                 "Async disk snapshot completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    napi_value result = MakeObject(env);
    if (result &&
        SetNamedPropertyChecked(env, result, "ejected", MakeBool(env, ctx->ejected)) &&
        SetNamedPropertyChecked(env, result, "imageIndex",
                                MakeUint32(env, ctx->imageIndex)) &&
        SetNamedPropertyChecked(env, result, "imageCount",
                                MakeUint32(env, ctx->imageCount))) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    }
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value DiskControlGetSnapshotAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok || !deferred) {
    SetDiskError("disk_snapshot_async_create_failed", "DiskControlGetSnapshotAsync",
                 "Failed to create promise for async disk snapshot");
    return nullptr;
  }

  auto *ctx = new (std::nothrow) DiskControlSnapshotAsyncContext();
  if (!ctx) {
    SetDiskError("disk_snapshot_async_alloc_failed", "DiskControlGetSnapshotAsync",
                 "Failed to allocate async disk snapshot context");
    napi_value reason = MakeString(env, "DiskControlGetSnapshotAsync alloc failed");
    if (reason) {
      (void)RejectDeferredChecked(env, deferred, reason);
    }
    return promise;
  }
  ctx->deferred = deferred;

  napi_value resourceName = MakeString(env, "DiskControlGetSnapshotAsync");
  if (!resourceName) {
    SetDiskError("disk_snapshot_async_resource_name_failed",
                 "DiskControlGetSnapshotAsync",
                 "Failed to create async resource name");
    delete ctx;
    return nullptr;
  }

  napi_status createStatus =
      napi_create_async_work(env, nullptr, resourceName,
                             ExecuteDiskControlGetSnapshotAsync,
                             CompleteDiskControlGetSnapshotAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetDiskError("disk_snapshot_async_create_failed", "DiskControlGetSnapshotAsync",
                 "Failed to create async work for disk snapshot");
    napi_value reason = MakeString(env, "DiskControlGetSnapshotAsync create failed");
    if (reason) {
      (void)RejectDeferredChecked(env, deferred, reason);
    }
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    SetDiskError("disk_snapshot_async_queue_failed", "DiskControlGetSnapshotAsync",
                 "Failed to queue async work for disk snapshot");
    napi_value reason = MakeString(env, "DiskControlGetSnapshotAsync queue failed");
    if (reason) {
      (void)RejectDeferredChecked(env, deferred, reason);
    }
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlReplaceImageIndex(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "DiskControlReplaceImageIndex")) {
    return MakeBool(env, false);
  }
  int32_t index = 0;
  char path[1024];
  if (!GetInt32Arg(env, args[0], index, "DiskControlReplaceImageIndex", "index") ||
      !GetStringArg(env, args[1], path, sizeof(path), "DiskControlReplaceImageIndex", "path")) {
    return MakeBool(env, false);
  }
  if (index < 0) {
    SetDiskError("disk_image_index_invalid", "DiskControlReplaceImageIndex",
                 "Disk image index must be non-negative");
    return MakeBool(env, false);
  }
  if (!security::ValidateDiskImagePath(path)) {
    GetEngine()->SetLastErrorInfo("disk_image_path_rejected",
                                  "DiskControlReplaceImageIndex",
                                  "Disk image path is outside allowed directories");
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->DiskControlReplaceImageIndex(static_cast<unsigned>(index), path);
  if (!ok) {
    EnsureDiskErrorIfEmpty("disk_replace_image_failed",
                           "DiskControlReplaceImageIndex",
                           "Core rejected the requested disk image replacement");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlAddImageIndex(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool ok = GetEngine()->DiskControlAddImageIndex();
  if (!ok) {
    EnsureDiskErrorIfEmpty("disk_add_image_failed", "DiskControlAddImageIndex",
                           "Core rejected the request to add a disk image slot");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterDiskNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredDiskControlSetEjectState", nullptr, DiskControlSetEjectState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlSetEjectStateAsync", nullptr, DiskControlSetEjectStateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetEjectState", nullptr, DiskControlGetEjectState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetImageIndex", nullptr, DiskControlGetImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlSetImageIndex", nullptr, DiskControlSetImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlSetImageIndexAsync", nullptr, DiskControlSetImageIndexAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetNumImages", nullptr, DiskControlGetNumImages, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetSnapshotAsync", nullptr, DiskControlGetSnapshotAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlReplaceImageIndex", nullptr, DiskControlReplaceImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlAddImageIndex", nullptr, DiskControlAddImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterDiskNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
