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
      {"refactoredDiskControlGetEjectState", nullptr, DiskControlGetEjectState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetImageIndex", nullptr, DiskControlGetImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlSetImageIndex", nullptr, DiskControlSetImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlGetNumImages", nullptr, DiskControlGetNumImages, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlReplaceImageIndex", nullptr, DiskControlReplaceImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredDiskControlAddImageIndex", nullptr, DiskControlAddImageIndex, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterDiskNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
