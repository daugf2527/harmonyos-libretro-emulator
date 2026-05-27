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
  napi_value result;
  napi_get_boolean(env, value, &result);
  return result;
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
  napi_value result;
  napi_get_boolean(env, value, &result);
  napi_resolve_deferred(env, deferred, result);
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
  napi_value list;
  napi_create_array_with_length(env, files.size(), &list);
  for (size_t i = 0; i < files.size(); ++i) {
    napi_value jsName;
    napi_create_string_utf8(env, files[i].c_str(), NAPI_AUTO_LENGTH, &jsName);
    napi_set_element(env, list, i, jsName);
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
  napi_resolve_deferred(env, deferred, result);
  return promise;
}

void RegisterLifecycleNapi(napi_env env, napi_value exports);
void RegisterInputNapi(napi_env env, napi_value exports);
void RegisterVideoAudioNapi(napi_env env, napi_value exports);
void RegisterStateNapi(napi_env env, napi_value exports);
void RegisterDiskNapi(napi_env env, napi_value exports);
void RegisterQueryNapi(napi_env env, napi_value exports);

#endif // ENGINE_NAPI_COMMON_H
