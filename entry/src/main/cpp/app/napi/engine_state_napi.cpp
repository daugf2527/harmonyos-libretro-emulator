#include "engine_napi_common.h"

static napi_value GetSaveStateSize(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t size = GetEngine()->GetSaveStateSize();
  napi_value result;
  napi_create_int64(env, static_cast<int64_t>(size), &result);
  return result;
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

void RegisterStateNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredGetSaveStateSize", nullptr, GetSaveStateSize, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSaveState", nullptr, SaveState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadState", nullptr, LoadState, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetSRAM", nullptr, GetSRAM, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetSRAM", nullptr, SetSRAM, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetCore", nullptr, ResetCore, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatReset", nullptr, CheatReset, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCheatSet", nullptr, CheatSet, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetCoreOptions", nullptr, GetCoreOptions, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetCoreOption", nullptr, SetCoreOption, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
