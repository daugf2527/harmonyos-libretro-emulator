#include "core/engine/libretro_engine.h"
#include "interfaces/graphics/i_renderer.h"
#include "interfaces/input/i_input_manager.h"
#include "platform/audio/audio_bridge.h"
#include "platform/resource/rawfile_rom_processor.h"
#include "napi/native_api.h"
#include <hilog/log.h>
#include <exception>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <rawfile/raw_dir.h>
#include <rawfile/raw_file_manager.h>
#include <string>
#include <vector>
#include <thread>
#include <fstream>
#include <cstdio>
#include <iostream>
#include <sstream>
#include "app/framework/plugin_manager.h"

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "LibretroRefactoredNAPI"
#undef LOG_FLOW
#define LOG_FLOW "NAPI"
#include "common/log_prefix.h"

using namespace libretro;

static LibretroEngine *GetEngine() { return LibretroEngine::GetInstance(); }
static std::atomic<bool> stop_in_progress{false};
static std::atomic<uint64_t> switch_token{0};
static std::mutex switch_mutex;
static std::condition_variable switch_cond;
static uint64_t active_switch_token = 0;

static bool LoadRomDataFromRawfileIfNeeded(
    napi_env env,
    const std::string &inputPath,
    napi_value resMgrValue,
    const std::string &filesDirOverride,
    std::string &outRomPath,
    std::shared_ptr<std::vector<uint8_t>> &outRomData) {
  outRomPath = inputPath;
  outRomData.reset();
  if (inputPath.empty()) {
    return true;
  }
  if (inputPath.rfind("roms/", 0) != 0) {
    return true;
  }
  if (!resMgrValue) {
    LOGF(LOG_ERROR, "[NEW] ResourceManager missing for rawfile ROM");
    return false;
  }

  NativeResourceManager *mng =
      OH_ResourceManager_InitNativeResourceManager(env, resMgrValue);
  if (!mng) {
    LOGF(LOG_WARN, "[NEW] Failed to init ResourceManager for rawfile ROM");
    return false;
  }

  std::string filesDir = filesDirOverride.empty() ? GetEngine()->GetFilesDir()
                                                  : filesDirOverride;
  auto result = RawfileRomProcessor::Process(inputPath, mng, filesDir);
  if (!result.success) {
    LOGF(LOG_ERROR,
         "[NEW] ROM rawfile load failed: %{public}s",
         result.error_message.c_str());
    OH_ResourceManager_ReleaseNativeResourceManager(mng);
    return false;
  }

  if (result.data) {
    outRomData = result.data;
    LOGF(LOG_INFO, "[NEW] ROM loaded from rawfile: %{public}zu bytes",
         outRomData->size());
  }
  if (!result.output_path.empty()) {
    outRomPath = result.output_path;
  }

  OH_ResourceManager_ReleaseNativeResourceManager(mng);
  return true;
}

// NAPI 异常保护宏 - 防止 C++ 异常导致 App 崩溃
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

static napi_value MakeResolvedPromise(napi_env env, bool value);

static napi_value MakeBool(napi_env env, bool value) {
  napi_value result;
  napi_get_boolean(env, value, &result);
  return result;
}

static bool GetArgs(napi_env env, napi_callback_info info, size_t minArgs,
                    size_t maxArgs, napi_value *args, size_t *argcOut,
                    const char *func) {
  size_t argc = maxArgs;
  napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (status != napi_ok || argc < minArgs) {
    LOGF(LOG_ERROR,
                 "[NEW] %s requires at least %{public}zu argument(s)",
                 func, minArgs);
    return false;
  }
  if (argcOut) {
    *argcOut = argc;
  }
  return true;
}

static bool GetStringArg(napi_env env, napi_value arg, char *out,
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
    return false;
  }
  if (size >= outSize) {
    LOGF(LOG_ERROR,
                 "[NEW] %s string arg too long: %{public}s", func, argName);
    return false;
  }
  status = napi_get_value_string_utf8(env, arg, out, outSize, &size);
  if (status != napi_ok || size == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid string arg: %{public}s", func, argName);
    return false;
  }
  return true;
}

static bool GetStringArgAllowEmpty(napi_env env, napi_value arg, char *out,
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
    return false;
  }
  if (size >= outSize) {
    LOGF(LOG_ERROR,
         "[NEW] %s string arg too long: %{public}s", func, argName);
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

static bool GetInt32Arg(napi_env env, napi_value arg, int32_t &out,
                        const char *func, const char *argName) {
  napi_status status = napi_get_value_int32(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid int32 arg: %{public}s", func, argName);
    return false;
  }
  return true;
}

static bool GetBoolArg(napi_env env, napi_value arg, bool &out,
                       const char *func, const char *argName) {
  napi_status status = napi_get_value_bool(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid bool arg: %{public}s", func, argName);
    return false;
  }
  return true;
}

static bool GetDoubleArg(napi_env env, napi_value arg, double &out,
                         const char *func, const char *argName) {
  napi_status status = napi_get_value_double(env, arg, &out);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid double arg: %{public}s", func, argName);
    return false;
  }
  return true;
}

static bool GetArrayBufferArg(napi_env env, napi_value arg, void **data,
                              size_t *length, const char *func,
                              const char *argName) {
  napi_status status = napi_get_arraybuffer_info(env, arg, data, length);
  if (status != napi_ok || !data || !length || !*data || *length == 0) {
    LOGF(LOG_ERROR,
                 "[NEW] %s invalid arraybuffer arg: %{public}s", func, argName);
    return false;
  }
  return true;
}

static void ScanRawDirRecursive(napi_env env, NativeResourceManager *mgr,
                                const std::string &rootDir,
                                const std::string &currentSubDir,
                                napi_value list, int &outIndex) {
  std::string fullPath = rootDir;
  if (!currentSubDir.empty()) {
    fullPath += "/" + currentSubDir;
  }

  RawDir *rawDir = OH_ResourceManager_OpenRawDir(mgr, fullPath.c_str());
  if (!rawDir) {
    return;
  }

  int count = OH_ResourceManager_GetRawFileCount(rawDir);
  for (int i = 0; i < count; ++i) {
    const char *name = OH_ResourceManager_GetRawFileName(rawDir, i);
    if (!name || !*name) {
      continue;
    }

    std::string relativePath =
        currentSubDir.empty() ? name : (currentSubDir + "/" + name);
    std::string absolutePath = rootDir + "/" + relativePath;

    // 尝试打开为目录
    RawDir *subDir = OH_ResourceManager_OpenRawDir(mgr, absolutePath.c_str());
    if (subDir) {
      // 如果成功打开，说明是目录，递归扫描
      OH_ResourceManager_CloseRawDir(subDir);
      ScanRawDirRecursive(env, mgr, rootDir, relativePath, list, outIndex);
    } else {
      // 无法打开为目录，则视为文件
      napi_value jsName;
      napi_create_string_utf8(env, relativePath.c_str(), NAPI_AUTO_LENGTH,
                              &jsName);
      napi_set_element(env, list, outIndex++, jsName);
    }
  }
  OH_ResourceManager_CloseRawDir(rawDir);
}

static napi_value GetRawFileList(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 1, 2, args, &argc, "GetRawFileList")) {
    napi_value empty;
    napi_create_array(env, &empty);
    return empty;
  }

  char dir[256] = "roms";
  if (argc >= 2) {
    if (!GetStringArg(env, args[1], dir, sizeof(dir), "GetRawFileList",
                      "dir")) {
      napi_value empty;
      napi_create_array(env, &empty);
      return empty;
    }
  }

  NativeResourceManager *mgr =
      OH_ResourceManager_InitNativeResourceManager(env, args[0]);
  if (!mgr) {
    LOGF(LOG_ERROR, "[NEW] GetRawFileList: init resource manager failed");
    napi_value empty;
    napi_create_array(env, &empty);
    return empty;
  }

  napi_value list;
  napi_create_array(env, &list);
  int outIndex = 0;

  // 使用递归扫描替代原来的单层扫描
  ScanRawDirRecursive(env, mgr, dir, "", list, outIndex);

  OH_ResourceManager_ReleaseNativeResourceManager(mgr);
  return list;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value StartEngine(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] StartEngine called");
  bool success = GetEngine()->Start();
  return MakeBool(env, success);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value LoadCore(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "LoadCore")) {
    return MakeBool(env, false);
  }

  char path[1024];
  if (!GetStringArg(env, args[0], path, sizeof(path), "LoadCore", "path")) {
    return MakeBool(env, false);
  }

  LOGF(LOG_INFO, " [NEW] LoadCore: %{public}s", path);
  const bool ok = GetEngine()->LoadCore(path);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value LoadRom(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 1, 2, args, &argc, "LoadRom")) {
    return MakeBool(env, false);
  }

  char path[1024];
  if (!GetStringArgAllowEmpty(env, args[0], path, sizeof(path), "LoadRom",
                              "path")) {
    return MakeBool(env, false);
  }
  std::string romPath(path);

  LOGF(LOG_INFO, " [NEW] LoadRom: %{public}s", romPath.c_str());

  std::shared_ptr<std::vector<uint8_t>> romData = nullptr;
  if (!LoadRomDataFromRawfileIfNeeded(env, romPath, (argc >= 2) ? args[1] : nullptr,
                                      std::string(), romPath, romData)) {
    return MakeBool(env, false);
  }

  const bool ok = GetEngine()->LoadGame(romPath, romData);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct SwitchGameAsyncContext {
  napi_env env = nullptr;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::string corePath;
  std::string romPath;
  std::string filesDir;
  std::shared_ptr<std::vector<uint8_t>> romData;
  uint32_t timeoutMs = 0;
  uint64_t token = 0;
  bool result = false;
};

static bool IsLatestSwitchToken(uint64_t token) {
  return switch_token.load() == token;
}

static bool AcquireSwitchToken(uint64_t token) {
  std::unique_lock<std::mutex> lock(switch_mutex);
  while (active_switch_token != 0) {
    if (!IsLatestSwitchToken(token)) {
      return false;
    }
    switch_cond.wait(lock);
  }
  if (!IsLatestSwitchToken(token)) {
    return false;
  }
  active_switch_token = token;
  return true;
}

static void ReleaseSwitchToken(uint64_t token) {
  std::lock_guard<std::mutex> lock(switch_mutex);
  if (active_switch_token == token) {
    active_switch_token = 0;
    switch_cond.notify_all();
  }
}

static bool WaitForStateWithToken(EngineState target, uint32_t timeoutMs,
                                  uint64_t token) {
  if (!IsLatestSwitchToken(token)) {
    return false;
  }
  if (GetEngine()->WaitForState(target, 0)) {
    return true;
  }
  const uint32_t sliceMs = 50;
  uint32_t elapsed = 0;
  while (elapsed < timeoutMs) {
    if (!IsLatestSwitchToken(token)) {
      return false;
    }
    const uint32_t waitMs =
        (timeoutMs - elapsed) > sliceMs ? sliceMs : (timeoutMs - elapsed);
    if (GetEngine()->WaitForState(target, waitMs)) {
      return true;
    }
    elapsed += waitMs;
  }
  return false;
}

static void RecoverAfterSwitchFailure(uint32_t timeoutMs, uint64_t token) {
  if (!IsLatestSwitchToken(token)) {
    return;
  }
  GetEngine()->Stop();
  (void)GetEngine()->WaitForState(EngineState::STOPPED, timeoutMs);
  GetEngine()->Reset();
}

static void ExecuteSwitchGame(napi_env env, void *data) {
  auto *ctx = static_cast<SwitchGameAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (!AcquireSwitchToken(ctx->token)) {
    ctx->result = false;
    return;
  }
  struct SwitchTokenGuard {
    uint64_t token;
    ~SwitchTokenGuard() { ReleaseSwitchToken(token); }
  } guard{ctx->token};

  if (!IsLatestSwitchToken(ctx->token)) {
    ctx->result = false;
    return;
  }

  GetEngine()->ClearLastErrorInfo();

  const EngineState currentState = GetEngine()->GetState();
  if (currentState != EngineState::INIT &&
      currentState != EngineState::STOPPED) {
    GetEngine()->Stop();
    if (!WaitForStateWithToken(EngineState::STOPPED, ctx->timeoutMs,
                               ctx->token)) {
      RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
      ctx->result = false;
      return;
    }
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    ctx->result = false;
    return;
  }

  if (!GetEngine()->Start()) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!GetEngine()->SetFilesDir(ctx->filesDir)) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    ctx->result = false;
    return;
  }

  if (!GetEngine()->LoadCore(ctx->corePath)) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }
  if (!WaitForStateWithToken(EngineState::CORE_LOADED, ctx->timeoutMs,
                             ctx->token)) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    ctx->result = false;
    return;
  }

  if (!GetEngine()->LoadGame(ctx->romPath, ctx->romData)) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }
  if (!WaitForStateWithToken(EngineState::RUNNING, ctx->timeoutMs,
                             ctx->token)) {
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  ctx->result = true;
}

static void CompleteSwitchGame(napi_env env, napi_status status, void *data) {
  auto *ctx = static_cast<SwitchGameAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  napi_value result;
  napi_get_boolean(env, ctx->result, &result);
  napi_resolve_deferred(env, ctx->deferred, result);

  napi_delete_async_work(env, ctx->work);
  delete ctx;
}

static napi_value SwitchGameAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[6];
  if (!GetArgs(env, info, 3, 6, args, &argc, "SwitchGameAsync")) {
    return MakeResolvedPromise(env, false);
  }

  char corePath[1024];
  if (!GetStringArg(env, args[0], corePath, sizeof(corePath),
                    "SwitchGameAsync", "corePath")) {
    return MakeResolvedPromise(env, false);
  }

  char romPath[1024];
  if (!GetStringArgAllowEmpty(env, args[1], romPath, sizeof(romPath),
                              "SwitchGameAsync", "romPath")) {
    return MakeResolvedPromise(env, false);
  }

  char filesDir[1024];
  if (!GetStringArg(env, args[2], filesDir, sizeof(filesDir),
                    "SwitchGameAsync", "filesDir")) {
    return MakeResolvedPromise(env, false);
  }

  napi_value resMgrValue = nullptr;
  uint32_t timeoutMs = 5000;
  uint64_t token = 0;
  int timeoutIndex = -1;
  int tokenIndex = -1;

  if (argc >= 4) {
    napi_valuetype arg3Type = napi_undefined;
    napi_typeof(env, args[3], &arg3Type);
    if (arg3Type == napi_object) {
      resMgrValue = args[3];
      timeoutIndex = 4;
      tokenIndex = 5;
    } else if (arg3Type == napi_number) {
      timeoutIndex = 3;
      tokenIndex = 4;
    }
  }

  if (timeoutIndex >= 0 && argc > static_cast<size_t>(timeoutIndex)) {
    int32_t t = 0;
    if (!GetInt32Arg(env, args[timeoutIndex], t, "SwitchGameAsync",
                     "timeoutMs")) {
      return MakeResolvedPromise(env, false);
    }
    if (t >= 0) {
      timeoutMs = static_cast<uint32_t>(t);
    }
  }

  if (tokenIndex >= 0 && argc > static_cast<size_t>(tokenIndex)) {
    double tokenValue = 0.0;
    if (!GetDoubleArg(env, args[tokenIndex], tokenValue, "SwitchGameAsync",
                      "token")) {
      return MakeResolvedPromise(env, false);
    }
    if (tokenValue > 0) {
      token = static_cast<uint64_t>(tokenValue);
    }
  }

  if (token == 0) {
    token = switch_token.fetch_add(1) + 1;
  }
  switch_token.store(token);

  std::string resolvedRomPath(romPath);
  std::shared_ptr<std::vector<uint8_t>> romData = nullptr;
  if (!LoadRomDataFromRawfileIfNeeded(env, resolvedRomPath, resMgrValue,
                                      std::string(filesDir),
                                      resolvedRomPath, romData)) {
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new SwitchGameAsyncContext();
  ctx->env = env;
  ctx->corePath = corePath;
  ctx->romPath = resolvedRomPath;
  ctx->filesDir = filesDir;
  ctx->romData = romData;
  ctx->timeoutMs = timeoutMs;
  ctx->token = token;

  napi_value promise;
  napi_create_promise(env, &ctx->deferred, &promise);

  napi_value resourceName;
  napi_create_string_utf8(env, "SwitchGameAsync", NAPI_AUTO_LENGTH,
                          &resourceName);
  napi_create_async_work(env, nullptr, resourceName, ExecuteSwitchGame,
                         CompleteSwitchGame, ctx, &ctx->work);
  napi_queue_async_work(env, ctx->work);

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value InitEventBridge(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "InitEventBridge")) {
    return MakeBool(env, false);
  }
  napi_valuetype cbType = napi_undefined;
  if (napi_typeof(env, args[0], &cbType) != napi_ok || cbType != napi_function) {
    LOGF(LOG_ERROR,
                 "[NEW] InitEventBridge requires a function callback");
    return MakeBool(env, false);
  }

  LOGF(LOG_INFO, "[NEW] InitEventBridge called");
  bool success = GetEngine()->InitializeEventBridge(env, args[0]);

  return MakeBool(env, success);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value StopEngine(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] StopEngine called");
  GetEngine()->Stop();

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value StopEngineAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] StopEngineAsync called");
  if (stop_in_progress.exchange(true)) {
    LOGF(LOG_WARN, "[NEW] StopEngineAsync ignored: stop already in progress");
    return MakeBool(env, true);
  }

  std::thread([]() {
    try {
      GetEngine()->Stop();
    } catch (...) {
    }
    stop_in_progress.store(false);
  }).detach();

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value PauseEngine(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] PauseEngine called");
  GetEngine()->Pause();

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ResumeEngine(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] ResumeEngine called");
  GetEngine()->Resume();

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SendInput(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "SendInput")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t id = 0;
  bool pressed = false;

  if (!GetInt32Arg(env, args[0], port, "SendInput", "port") ||
      !GetInt32Arg(env, args[1], id, "SendInput", "id") ||
      !GetBoolArg(env, args[2], pressed, "SendInput", "pressed")) {
    return MakeBool(env, false);
  }

  auto *input = GetEngine()->GetInputInterface();
  if (!input || !GetEngine()->CanSendVirtual(port)) {
    return MakeBool(env, false);
  }
  const bool ok = input->SendInput(port, id, pressed);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SendAnalog(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[4];
  if (!GetArgs(env, info, 4, 4, args, &argc, "SendAnalog")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t index = 0;
  int32_t id = 0;
  double value = 0.0;

  if (!GetInt32Arg(env, args[0], port, "SendAnalog", "port") ||
      !GetInt32Arg(env, args[1], index, "SendAnalog", "index") ||
      !GetInt32Arg(env, args[2], id, "SendAnalog", "id") ||
      !GetDoubleArg(env, args[3], value, "SendAnalog", "value")) {
    return MakeBool(env, false);
  }

  if (value > 32767.0) {
    value = 32767.0;
  } else if (value < -32768.0) {
    value = -32768.0;
  }

  auto *input = GetEngine()->GetInputInterface();
  if (!input || !GetEngine()->CanSendVirtual(port)) {
    return MakeBool(env, false);
  }
  const bool ok =
      input->SendAnalog(port, index, id, static_cast<int>(value));

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value AssignPortSource(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 2, 3, args, &argc, "AssignPortSource")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t sourceType = 0;
  if (!GetInt32Arg(env, args[0], port, "AssignPortSource", "port") ||
      !GetInt32Arg(env, args[1], sourceType, "AssignPortSource",
                   "sourceType")) {
    return MakeBool(env, false);
  }

  std::string deviceId;
  if (argc >= 3) {
    char idBuf[256] = {0};
    if (!GetStringArgAllowEmpty(env, args[2], idBuf, sizeof(idBuf),
                                "AssignPortSource", "deviceId")) {
      return MakeBool(env, false);
    }
    deviceId = idBuf;
  }

  auto *input = GetEngine()->GetInputInterface();
  if (!input) {
    return MakeBool(env, false);
  }
  const bool ok = input->AssignPortSource(port, sourceType, deviceId);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value UnassignPort(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "UnassignPort")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  if (!GetInt32Arg(env, args[0], port, "UnassignPort", "port")) {
    return MakeBool(env, false);
  }

  auto *input = GetEngine()->GetInputInterface();
  if (!input) {
    return MakeBool(env, false);
  }
  const bool ok = input->UnassignPort(port);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ListInputDevices(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *input = GetEngine()->GetInputInterface();
  std::vector<interfaces::InputDeviceInfo> devices;
  if (input) {
    devices = input->ListInputDevices();
  }
  napi_value array = nullptr;
  napi_create_array_with_length(env, devices.size(), &array);

  for (size_t i = 0; i < devices.size(); ++i) {
    napi_value obj = nullptr;
    napi_create_object(env, &obj);

    napi_value val = nullptr;
    napi_create_string_utf8(env, devices[i].deviceId.c_str(),
                            NAPI_AUTO_LENGTH, &val);
    napi_set_named_property(env, obj, "deviceId", val);

    napi_create_int32(env, static_cast<int32_t>(devices[i].sourceType), &val);
    napi_set_named_property(env, obj, "sourceType", val);

    napi_create_string_utf8(env, devices[i].name.c_str(), NAPI_AUTO_LENGTH,
                            &val);
    napi_set_named_property(env, obj, "name", val);

    napi_set_element(env, array, i, obj);
  }

  return array;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SendSensor(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "SendSensor")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t id = 0;
  double value = 0.0;

  if (!GetInt32Arg(env, args[0], port, "SendSensor", "port") ||
      !GetInt32Arg(env, args[1], id, "SendSensor", "id") ||
      !GetDoubleArg(env, args[2], value, "SendSensor", "value")) {
    return MakeBool(env, false);
  }

  auto *input = GetEngine()->GetInputInterface();
  if (!input) {
    return MakeBool(env, false);
  }
  const bool ok = input->SendSensor(port, id, static_cast<float>(value));

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

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

static napi_value MakeResolvedPromise(napi_env env, bool value) {
  napi_deferred deferred;
  napi_value promise;
  napi_create_promise(env, &deferred, &promise);
  napi_value result;
  napi_get_boolean(env, value, &result);
  napi_resolve_deferred(env, deferred, result);
  return promise;
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

  napi_value promise;
  napi_create_promise(env, &ctx->deferred, &promise);

  napi_value resourceName;
  napi_create_string_utf8(env, "WaitForEngineStateAsync", NAPI_AUTO_LENGTH,
                          &resourceName);
  napi_create_async_work(env, nullptr, resourceName, ExecuteWaitForState,
                         CompleteWaitForState, ctx, &ctx->work);
  napi_queue_async_work(env, ctx->work);

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

// --- SaveState NAPI ---
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
  // 返回 ArrayBuffer
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

// --- SRAM NAPI ---
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

// --- 核心控制 NAPI ---
static napi_value ResetCore(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] ResetCore called");
  GetEngine()->ResetCore();
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- 金手指 NAPI ---
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

// --- 统计 NAPI ---
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
  
  // 音频缓冲统计
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

static napi_value SetMinimumAudioLatency(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 0, 1, args, &argc, "SetMinimumAudioLatency")) {
    return MakeBool(env, false);
  }
  int32_t v = 0;
  if (argc >= 1) {
    if (!GetInt32Arg(env, args[0], v, "SetMinimumAudioLatency", "latencyMs")) {
      return MakeBool(env, false);
    }
  }
  if (v < 0) v = 0;
  LOGF(LOG_INFO, "[NEW] SetMinimumAudioLatency called: %{public}d ms", v);
  GetEngine()->SetMinimumAudioLatency(static_cast<unsigned>(v));
  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetAudioSyncMode(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetAudioSyncMode")) {
    return MakeBool(env, false);
  }

  int32_t mode = 1; // Default to BLOCKING
  if (!GetInt32Arg(env, args[0], mode, "SetAudioSyncMode", "mode")) {
    return MakeBool(env, false);
  }

  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    // 0 = NON_BLOCKING, 1 = AUDIO_BLOCKING
    auto syncMode = (mode == 0) ? libretro::AudioBridge::SyncMode::NON_BLOCKING
                                : libretro::AudioBridge::SyncMode::AUDIO_BLOCKING;
    audioBridge->SetSyncMode(syncMode);
    LOGF(LOG_INFO, "[NEW] SetAudioSyncMode: %{public}d", mode);
  }

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- 控制器/区域 NAPI ---
static napi_value SetControllerPortDevice(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetControllerPortDevice")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t device = 0;
  if (!GetInt32Arg(env, args[0], port, "SetControllerPortDevice", "port") ||
      !GetInt32Arg(env, args[1], device, "SetControllerPortDevice", "device")) {
    return MakeBool(env, false);
  }
  if (port < 0 || device < 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetControllerPortDevice invalid: port=%{public}d device=%{public}d",
         port, device);
    return MakeBool(env, false);
  }
  
  auto *input = GetEngine()->GetInputInterface();
  if (!input) {
    return MakeBool(env, false);
  }
  const bool ok = input->SetControllerPortDevice(port, device);
  return MakeBool(env, ok);
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

// --- 状态查询 NAPI ---
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

// --- AV 信息 NAPI ---
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

// --- 视频配置 NAPI ---
static napi_value SetScalingMode(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetScalingMode")) {
    return MakeBool(env, false);
  }

  int32_t mode = 0;
  if (!GetInt32Arg(env, args[0], mode, "SetScalingMode", "mode")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetScalingMode(mode);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetSoftwareMaxResolution(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetSoftwareMaxResolution")) {
    return MakeBool(env, false);
  }

  int32_t w = 0, h = 0;
  if (!GetInt32Arg(env, args[0], w, "SetSoftwareMaxResolution", "width") ||
      !GetInt32Arg(env, args[1], h, "SetSoftwareMaxResolution", "height")) {
    return MakeBool(env, false);
  }
  if (w <= 0 || h <= 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetSoftwareMaxResolution invalid: %{public}dx%{public}d", w,
         h);
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetSoftwareMaxResolution(w, h);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetAIUpscale(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetAIUpscale")) {
    return MakeBool(env, false);
  }

  bool enabled = false;
  if (!GetBoolArg(env, args[0], enabled, "SetAIUpscale", "enabled")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetAIUpscale(enabled);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetHwRenderAllowed(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "SetHwRenderAllowed")) {
    return MakeBool(env, false);
  }

  bool enabled = false;
  if (!GetBoolArg(env, args[0], enabled, "SetHwRenderAllowed", "enabled")) {
    return MakeBool(env, false);
  }

  auto *renderer = GetEngine()->GetRendererInterface();
  if (!renderer) {
    return MakeBool(env, false);
  }
  const bool ok = renderer->SetHwRenderAllowed(enabled);

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

// --- 磁盘控制 NAPI ---
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
  napi_value result;
  napi_create_uint32(env, index, &result);
  return result;
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
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->DiskControlSetImageIndex(static_cast<unsigned>(index));
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlGetNumImages(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  unsigned num = GetEngine()->DiskControlGetNumImages();
  napi_value result;
  napi_create_uint32(env, num, &result);
  return result;
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
    return MakeBool(env, false);
  }
  bool ok = GetEngine()->DiskControlReplaceImageIndex(static_cast<unsigned>(index), path);
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value DiskControlAddImageIndex(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  bool ok = GetEngine()->DiskControlAddImageIndex();
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterLibretroRefactoredNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredStartEngine", nullptr, StartEngine, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredStopEngine", nullptr, StopEngine, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredStopEngineAsync", nullptr, StopEngineAsync, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredPauseEngine", nullptr, PauseEngine, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredResumeEngine", nullptr, ResumeEngine, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredLoadCore", nullptr, LoadCore, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredLoadRom", nullptr, LoadRom, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSwitchGameAsync", nullptr, SwitchGameAsync, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredGetRawFileList", nullptr, GetRawFileList, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredInitEventBridge", nullptr, InitEventBridge, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSendInput", nullptr, SendInput, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSendAnalog", nullptr, SendAnalog, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredAssignPortSource", nullptr, AssignPortSource, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredUnassignPort", nullptr, UnassignPort, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredListInputDevices", nullptr, ListInputDevices, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSendSensor", nullptr, SendSensor, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredGetState", nullptr, GetEngineState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredWaitForState", nullptr, WaitForEngineState, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredWaitForStateAsync", nullptr, WaitForEngineStateAsync, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetLastErrorInfo", nullptr, GetLastErrorInfo, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredClearLastErrorInfo", nullptr, ClearLastErrorInfo, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetFilesDir", nullptr, SetFilesDir, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSetMinimumAudioLatency", nullptr, SetMinimumAudioLatency, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSetAudioSyncMode", nullptr, SetAudioSyncMode, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // Video Config
      {"refactoredSetScalingMode", nullptr, SetScalingMode, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSetSoftwareMaxResolution", nullptr, SetSoftwareMaxResolution, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSetAIUpscale", nullptr, SetAIUpscale, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSetHwRenderAllowed", nullptr, SetHwRenderAllowed, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      // SaveState
      {"refactoredGetSaveStateSize", nullptr, GetSaveStateSize, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredSaveState", nullptr, SaveState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredLoadState", nullptr, LoadState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // SRAM
      {"refactoredGetSRAM", nullptr, GetSRAM, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSetSRAM", nullptr, SetSRAM, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // Core Control
      {"refactoredResetCore", nullptr, ResetCore, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // Disk Control
      {"refactoredDiskControlSetEjectState", nullptr, DiskControlSetEjectState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlGetEjectState", nullptr, DiskControlGetEjectState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlGetImageIndex", nullptr, DiskControlGetImageIndex, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlSetImageIndex", nullptr, DiskControlSetImageIndex, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlGetNumImages", nullptr, DiskControlGetNumImages, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlReplaceImageIndex", nullptr, DiskControlReplaceImageIndex, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredDiskControlAddImageIndex", nullptr, DiskControlAddImageIndex, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // Cheat
      {"refactoredCheatReset", nullptr, CheatReset, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredCheatSet", nullptr, CheatSet, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // Stats
      {"refactoredGetStats", nullptr, GetStats, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredResetStats", nullptr, ResetStats, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredGetInputDebugStats", nullptr, GetInputDebugStats, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      // Controller/Region
      {"refactoredSetControllerPortDevice", nullptr, SetControllerPortDevice,
       nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetRegion", nullptr, GetRegion, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // AV Info
      {"refactoredGetAVInfo", nullptr, GetAVInfo, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredGetCoreOptions", nullptr, GetCoreOptions, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"refactoredSetCoreOption", nullptr, SetCoreOption, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      // State Query
      {"refactoredHasCoreLoaded", nullptr, HasCoreLoaded, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"refactoredHasGameLoaded", nullptr, HasGameLoaded, nullptr, nullptr,
       nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  LOGF(LOG_INFO, " [NEW] LibretroRefactored NAPI registered (40 functions)");
}
