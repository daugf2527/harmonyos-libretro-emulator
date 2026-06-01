#ifndef ENGINE_NAPI_COMMON_H
#define ENGINE_NAPI_COMMON_H

#include "core/engine/libretro_engine.h"
#include "napi/native_api.h"
#include <hilog/log.h>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD002
#undef LOG_TAG
#define LOG_TAG "LibretroRefactoredNAPI"
#undef LOG_FLOW
#define LOG_FLOW "NAPI"
#include "common/log_prefix.h"

using namespace libretro;

inline LibretroEngine *GetEngine() { return LibretroEngine::GetInstance(); }

#define NAPI_TRY_CATCH_BEGIN try {
#define NAPI_TRY_CATCH_END(env, defaultReturn) \
  } catch (const std::exception &e) { \
    LOGF(LOG_ERROR, "[NEW] NAPI exception: %{public}s", e.what()); \
    napi_throw_error(env, nullptr, e.what()); \
    return defaultReturn; \
  } catch (...) { \
    LOGF(LOG_ERROR, "[NEW] NAPI unknown exception"); \
    napi_throw_error(env, nullptr, "Unknown native exception"); \
    return defaultReturn; \
  }

// Audit T1-F5: returns nullptr if a pending exception exists (set by GetArgs/type-getters),
// so callers don't need per-site nullptr returns after helper failures.
inline napi_value MakeBool(napi_env env, bool value) {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
    return nullptr;
  }
  napi_value result = nullptr;
  if (napi_get_boolean(env, value, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create boolean value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeUndefined(napi_env env) {
  napi_value result = nullptr;
  if (napi_get_undefined(env, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create undefined value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeNull(napi_env env) {
  napi_value result = nullptr;
  if (napi_get_null(env, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create null value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeInt32(napi_env env, int32_t value) {
  napi_value result = nullptr;
  if (napi_create_int32(env, value, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create int32 value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeUint32(napi_env env, uint32_t value) {
  napi_value result = nullptr;
  if (napi_create_uint32(env, value, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create uint32 value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeInt64(napi_env env, int64_t value) {
  napi_value result = nullptr;
  if (napi_create_int64(env, value, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create int64 value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeDouble(napi_env env, double value) {
  napi_value result = nullptr;
  if (napi_create_double(env, value, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create double value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeString(napi_env env, const std::string &value) {
  napi_value result = nullptr;
  if (napi_create_string_utf8(env, value.c_str(), NAPI_AUTO_LENGTH, &result) !=
      napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create string value");
    return nullptr;
  }
  return result;
}

inline napi_value MakeString(napi_env env, const char *value) {
  return MakeString(env, std::string(value ? value : ""));
}

inline napi_value MakeObject(napi_env env) {
  napi_value result = nullptr;
  if (napi_create_object(env, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create object");
    return nullptr;
  }
  return result;
}

inline napi_value MakeArrayBufferFromBytes(napi_env env, const uint8_t *data,
                                           size_t size) {
  if (!data || size == 0) {
    napi_throw_error(env, nullptr, "Invalid ArrayBuffer source");
    return nullptr;
  }
  void *bufferData = nullptr;
  napi_value arrayBuffer = nullptr;
  if (napi_create_arraybuffer(env, size, &bufferData, &arrayBuffer) !=
          napi_ok ||
      !bufferData) {
    napi_throw_error(env, nullptr, "Failed to create ArrayBuffer");
    return nullptr;
  }
  std::memcpy(bufferData, data, size);
  return arrayBuffer;
}

inline bool SetNamedPropertyChecked(napi_env env, napi_value object,
                                    const char *name, napi_value value) {
  if (!object || !name || !value) {
    napi_throw_error(env, nullptr, "Invalid object property");
    return false;
  }
  if (napi_set_named_property(env, object, name, value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to set object property");
    return false;
  }
  return true;
}

inline bool SetElementChecked(napi_env env, napi_value array, uint32_t index,
                              napi_value value) {
  if (!array || !value) {
    napi_throw_error(env, nullptr, "Invalid array element");
    return false;
  }
  if (napi_set_element(env, array, index, value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to set array element");
    return false;
  }
  return true;
}

inline bool ResolveDeferredChecked(napi_env env, napi_deferred deferred,
                                   napi_value value) {
  if (!deferred || !value) {
    napi_throw_error(env, nullptr, "Invalid promise resolution value");
    return false;
  }
  if (napi_resolve_deferred(env, deferred, value) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to resolve promise");
    return false;
  }
  return true;
}

inline bool RejectDeferredChecked(napi_env env, napi_deferred deferred,
                                  napi_value reason) {
  if (!deferred || !reason) {
    napi_throw_error(env, nullptr, "Invalid promise rejection reason");
    return false;
  }
  if (napi_reject_deferred(env, deferred, reason) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to reject promise");
    return false;
  }
  return true;
}

inline napi_value MakeResolvedPromise(napi_env env, bool value) {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
    return nullptr;
  }
  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok || !deferred) {
    napi_throw_error(env, nullptr, "Failed to create promise");
    return nullptr;
  }
  napi_value result = MakeBool(env, value);
  if (!result) {
    return nullptr;
  }
  if (!ResolveDeferredChecked(env, deferred, result)) {
    return nullptr;
  }
  return promise;
}

inline bool GetArgs(napi_env env, napi_callback_info info, size_t minArgs,
                    size_t maxArgs, napi_value *args, size_t *argcOut,
                    const char *func) {
  size_t argc = maxArgs;
  napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (status != napi_ok || argc < minArgs) {
    LOGF(LOG_ERROR,
                 "[NEW] %s requires at least %{public}zu argument(s)",
                 func, minArgs);
    // Audit T1-F5: throw so ArkTS distinguishes contract violations from logical false
    napi_throw_type_error(env, nullptr, "Wrong number of arguments");
    return false;
  }
  if (argcOut) {
    *argcOut = argc;
  }
  return true;
}

inline bool GetStringArg(napi_env env, napi_value arg, char *out,
                         size_t outSize, const char *func,
                         const char *argName) {
  if (!out || outSize == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid string buffer: %{public}s", func, argName);
    return false;
  }
  size_t size = 0;
  napi_status status =
      napi_get_value_string_utf8(env, arg, nullptr, 0, &size);
  if (status != napi_ok || size == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid string arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected string argument"); // Audit T1-F5
    return false;
  }
  if (size >= outSize) {
    LOGF(LOG_ERROR,
                 "[NEW] %s string arg too long: %{public}s", func, argName);
    napi_throw_range_error(env, nullptr, "String argument exceeds maximum length");  // Audit B-F1
    return false;
  }
  status = napi_get_value_string_utf8(env, arg, out, outSize, &size);
  if (status != napi_ok || size == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid string arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected string argument"); // Audit T1-F5
    return false;
  }
  return true;
}

inline bool GetStringArgAllowEmpty(napi_env env, napi_value arg, char *out,
                                   size_t outSize, const char *func,
                                   const char *argName) {
  if (!out || outSize == 0) {
    LOGF(LOG_ERROR,
         "[NEW] %s invalid string buffer: %{public}s", func, argName);
    return false;
  }
  size_t size = 0;
  napi_status status =
      napi_get_value_string_utf8(env, arg, nullptr, 0, &size);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
         "[NEW] %s invalid string arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected string argument");  // Audit B-F1
    return false;
  }
  if (size >= outSize) {
    LOGF(LOG_ERROR,
         "[NEW] %s string arg too long: %{public}s", func, argName);
    napi_throw_range_error(env, nullptr, "String argument exceeds maximum length");  // Audit B-F1
    return false;
  }
  status = napi_get_value_string_utf8(env, arg, out, outSize, &size);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
         "[NEW] %s invalid string arg: %{public}s", func, argName);
    return false;
  }
  if (size == 0) {
    out[0] = '\0';
  }
  return true;
}

inline bool GetInt32Arg(napi_env env, napi_value arg, int32_t &out,
                        const char *func, const char *argName) {
  napi_status status = napi_get_value_int32(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid int32 arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected number argument"); // Audit T1-F5
    return false;
  }
  return true;
}

inline bool GetBoolArg(napi_env env, napi_value arg, bool &out,
                       const char *func, const char *argName) {
  napi_status status = napi_get_value_bool(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid bool arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected boolean argument"); // Audit T1-F5
    return false;
  }
  return true;
}

inline bool GetDoubleArg(napi_env env, napi_value arg, double &out,
                         const char *func, const char *argName) {
  napi_status status = napi_get_value_double(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid double arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected number argument"); // Audit T1-F5
    return false;
  }
  return true;
}

inline bool GetArrayBufferArg(napi_env env, napi_value arg, void **data,
                              size_t *length, const char *func,
                              const char *argName) {
  napi_status status = napi_get_arraybuffer_info(env, arg, data, length);
  if (status != napi_ok || !data || !length || !*data || *length == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid arraybuffer arg: %{public}s", func, argName);
    napi_throw_type_error(env, nullptr, "Expected ArrayBuffer argument"); // Audit T1-F5
    return false;
  }
  return true;
}

inline napi_value BuildStringArray(napi_env env,
                                   const std::vector<std::string> &files) {
  napi_value list = nullptr;
  if (napi_create_array_with_length(env, files.size(), &list) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create string array");
    return nullptr;
  }
  for (size_t i = 0; i < files.size(); ++i) {
    napi_value jsName = MakeString(env, files[i]);
    if (!SetElementChecked(env, list, static_cast<uint32_t>(i), jsName)) {
      return nullptr;
    }
  }
  return list;
}

inline napi_value MakeResolvedStringArrayPromise(
    napi_env env, const std::vector<std::string> &files) {
  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  if (napi_create_promise(env, &deferred, &promise) != napi_ok || !deferred) {
    napi_throw_error(env, nullptr, "Failed to create promise");
    return nullptr;
  }
  napi_value result = BuildStringArray(env, files);
  if (!result) {
    return nullptr;
  }
  if (!ResolveDeferredChecked(env, deferred, result)) {
    return nullptr;
  }
  return promise;
}

/**
 * 创建结构化错误响应对象
 *
 * 返回格式：
 * {
 *   success: boolean,
 *   errorCode?: number,  // 对应 ErrorCodes.ets 的 numericCode
 *   message?: string     // 错误描述
 * }
 *
 * 错误码映射到 entry/src/main/ets/common/ErrorCodes.ets：
 * - 3001: CORE_LOAD_FAILED (核心加载失败)
 * - 3010: ROM_LOAD_FAILED (ROM 加载失败)
 * - 3020: ENGINE_START_FAILED (引擎启动失败)
 * - 3031: SAVE_STATE_SAVE_FAILED (存档保存失败)
 * - 3032: SRAM_LOAD_FAILED (SRAM 加载失败)
 *
 * @param env NAPI 环境
 * @param success 操作是否成功
 * @param errorCode 错误码（0 表示成功，无错误码）
 * @param message 错误消息（可选）
 * @return napi_value 结构化对象
 */
inline napi_value MakeErrorResult(napi_env env, bool success, int errorCode = 0,
                                   const char *message = nullptr) {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
    return nullptr;
  }

  napi_value result = MakeObject(env);
  if (!result) {
    return nullptr;
  }

  napi_value successValue = MakeBool(env, success);
  if (!SetNamedPropertyChecked(env, result, "success", successValue)) {
    return nullptr;
  }

  // 失败时添加 errorCode 和 message
  if (!success) {
    if (errorCode != 0) {
      napi_value errorCodeValue = MakeInt32(env, errorCode);
      if (!SetNamedPropertyChecked(env, result, "errorCode",
                                   errorCodeValue)) {
        return nullptr;
      }
    }

    if (message && message[0] != '\0') {
      napi_value messageValue = MakeString(env, message);
      if (!SetNamedPropertyChecked(env, result, "message", messageValue)) {
        return nullptr;
      }
    }
  }

  return result;
}

void RegisterLifecycleNapi(napi_env env, napi_value exports);
void RegisterInputNapi(napi_env env, napi_value exports);
void RegisterVideoAudioNapi(napi_env env, napi_value exports);
void RegisterStateNapi(napi_env env, napi_value exports);
void RegisterDiskNapi(napi_env env, napi_value exports);
void RegisterQueryNapi(napi_env env, napi_value exports);

#endif // ENGINE_NAPI_COMMON_H
