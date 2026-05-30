#include "engine_napi_common.h"
#include "platform/resource/rawfile_rom_processor.h"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <rawfile/raw_dir.h>
#include <rawfile/raw_file_manager.h>

// 警告:以下文件级 static 变量绑定到 .so 生命周期而非 napi_env。
// 当前 HarmonyOS ArkTS 单实例场景下没问题;但若未来引入 Worker / 多 env,
// 所有 env 会共享同一套全局状态,可能出现 stale token 干扰或互斥锁在已销毁
// 线程持有时死锁。若启用 Worker 支持,需将这些状态包装在 EngineNapiState
// 类中,并通过 napi_set_instance_data(env, ...) 按 env 隔离。
static std::atomic<bool> stop_in_progress{false};
static std::atomic<uint64_t> switch_token{0};
static std::mutex switch_mutex;
static std::condition_variable switch_cond;
static uint64_t active_switch_token = 0;
static std::mutex switch_dedupe_mutex;
static std::string last_switch_core_path;
static std::string last_switch_rom_path;
static uint64_t last_switch_request_ms = 0;
static constexpr uint64_t kSwitchDedupeWindowMs = 800;

static uint64_t GetSteadyNowMs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<uint64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(now).count());
}

static bool ShouldDedupSwitchRequest(const std::string &corePath,
                                     const std::string &romPath) {
  bool switchingNow = false;
  {
    std::lock_guard<std::mutex> lock(switch_mutex);
    switchingNow = active_switch_token != 0;
  }

  const EngineState state = GetEngine()->GetState();
  const bool engineBusy =
      switchingNow || state == EngineState::STARTING ||
      state == EngineState::LOADING || state == EngineState::STOPPING ||
      state == EngineState::RUNNING || state == EngineState::GAME_LOADED ||
      state == EngineState::CORE_LOADED;

  const uint64_t nowMs = GetSteadyNowMs();
  std::lock_guard<std::mutex> dedupeLock(switch_dedupe_mutex);
  const bool sameRequest =
      corePath == last_switch_core_path && romPath == last_switch_rom_path;
  const bool withinWindow =
      nowMs >= last_switch_request_ms &&
      (nowMs - last_switch_request_ms) < kSwitchDedupeWindowMs;

  last_switch_core_path = corePath;
  last_switch_rom_path = romPath;
  last_switch_request_ms = nowMs;

  return sameRequest && withinWindow && engineBusy;
}

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
    GetEngine()->SetLastErrorInfo("rawfile_resource_manager_missing",
                                  "LoadRomDataFromRawfileIfNeeded",
                                  "ResourceManager is required for rawfile ROM");
    return false;
  }

  NativeResourceManager *mng =
      OH_ResourceManager_InitNativeResourceManager(env, resMgrValue);
  if (!mng) {
    LOGF(LOG_WARN, "[NEW] Failed to init ResourceManager for rawfile ROM");
    GetEngine()->SetLastErrorInfo("rawfile_resource_manager_init_failed",
                                  "LoadRomDataFromRawfileIfNeeded",
                                  "OH_ResourceManager_InitNativeResourceManager failed");
    return false;
  }

  std::string filesDir = filesDirOverride.empty() ? GetEngine()->GetFilesDir()
                                                  : filesDirOverride;
  auto result = RawfileRomProcessor::Process(inputPath, mng, filesDir);
  if (!result.success) {
    LOGF(LOG_ERROR,
         "[NEW] ROM rawfile load failed: %{public}s",
         result.error_message.c_str());
    GetEngine()->SetLastErrorInfo("rawfile_rom_process_failed",
                                  "LoadRomDataFromRawfileIfNeeded",
                                  result.error_message);
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

static void CollectRawDirRecursive(NativeResourceManager *mgr,
                                   const std::string &rootDir,
                                   const std::string &currentSubDir,
                                   std::vector<std::string> &outFiles) {
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

    RawDir *subDir = OH_ResourceManager_OpenRawDir(mgr, absolutePath.c_str());
    if (subDir) {
      OH_ResourceManager_CloseRawDir(subDir);
      CollectRawDirRecursive(mgr, rootDir, relativePath, outFiles);
    } else {
      outFiles.push_back(relativePath);
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

  std::vector<std::string> files;
  CollectRawDirRecursive(mgr, dir, "", files);
  napi_value list = BuildStringArray(env, files);
  OH_ResourceManager_ReleaseNativeResourceManager(mgr);
  return list;
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct RawFileListAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  NativeResourceManager *mgr = nullptr;
  std::string dir;
  std::vector<std::string> files;
};

static void ExecuteGetRawFileListAsync(napi_env env, void *data) {
  auto *ctx = static_cast<RawFileListAsyncContext *>(data);
  if (!ctx || !ctx->mgr) {
    return;
  }
  CollectRawDirRecursive(ctx->mgr, ctx->dir, "", ctx->files);
}

static void CompleteGetRawFileListAsync(napi_env env, napi_status status,
                                        void *data) {
  auto *ctx = static_cast<RawFileListAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status != napi_ok) {
    LOGF(LOG_ERROR,
         "[NEW] GetRawFileListAsync work failed: status=%{public}d",
         static_cast<int>(status));
    napi_value errMsg;
    napi_create_string_utf8(env, "async_work_failed", NAPI_AUTO_LENGTH, &errMsg);
    napi_reject_deferred(env, ctx->deferred, errMsg);
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    if (ctx->mgr) {
      OH_ResourceManager_ReleaseNativeResourceManager(ctx->mgr);
      ctx->mgr = nullptr;
    }
    delete ctx;
    return;
  }

  napi_value result = BuildStringArray(env, ctx->files);
  napi_resolve_deferred(env, ctx->deferred, result);

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  if (ctx->mgr) {
    OH_ResourceManager_ReleaseNativeResourceManager(ctx->mgr);
    ctx->mgr = nullptr;
  }
  delete ctx;
}

static napi_value GetRawFileListAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 1, 2, args, &argc, "GetRawFileListAsync")) {
    return MakeResolvedStringArrayPromise(env, {});
  }

  char dir[256] = "roms";
  if (argc >= 2) {
    if (!GetStringArg(env, args[1], dir, sizeof(dir), "GetRawFileListAsync",
                      "dir")) {
      return MakeResolvedStringArrayPromise(env, {});
    }
  }

  NativeResourceManager *mgr =
      OH_ResourceManager_InitNativeResourceManager(env, args[0]);
  if (!mgr) {
    LOGF(LOG_ERROR, "[NEW] GetRawFileListAsync: init resource manager failed");
    return MakeResolvedStringArrayPromise(env, {});
  }

  auto *ctx = new RawFileListAsyncContext();
  ctx->mgr = mgr;
  ctx->dir = dir;

  napi_value promise;
  napi_create_promise(env, &ctx->deferred, &promise);

  napi_value resourceName;
  napi_create_string_utf8(env, "GetRawFileListAsync", NAPI_AUTO_LENGTH,
                          &resourceName);
  napi_status createStatus =
      napi_create_async_work(env, nullptr, resourceName,
                             ExecuteGetRawFileListAsync,
                             CompleteGetRawFileListAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] GetRawFileListAsync create work failed");
    napi_value empty = BuildStringArray(env, {});
    napi_resolve_deferred(env, ctx->deferred, empty);
    if (ctx->mgr) {
      OH_ResourceManager_ReleaseNativeResourceManager(ctx->mgr);
      ctx->mgr = nullptr;
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] GetRawFileListAsync queue work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value empty = BuildStringArray(env, {});
    napi_resolve_deferred(env, ctx->deferred, empty);
    if (ctx->mgr) {
      OH_ResourceManager_ReleaseNativeResourceManager(ctx->mgr);
      ctx->mgr = nullptr;
    }
    delete ctx;
    return promise;
  }

  return promise;
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
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::string corePath;
  std::string romPath;
  std::string filesDir;
  std::shared_ptr<std::vector<uint8_t>> romData;
  uint32_t timeoutMs = 0;
  uint64_t token = 0;
  uint64_t callerToken = 0;
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

static void EnsureLastErrorIfEmpty(const std::string &reason,
                                   const std::string &step,
                                   const std::string &message) {
  auto err = GetEngine()->GetLastErrorInfo();
  if (!err.reason.empty()) {
    return;
  }
  GetEngine()->SetLastErrorInfo(reason, step, message);
}

static void RecoverAfterSwitchFailure(uint32_t timeoutMs, uint64_t token) {
  auto preservedError = GetEngine()->GetLastErrorInfo();
  if (!IsLatestSwitchToken(token)) {
    LOGF(LOG_WARN,
         "[NEW] RecoverAfterSwitchFailure: stale token, skip recovery (token=%llu)",
         static_cast<unsigned long long>(token));
    return;
  }
  LOGF(LOG_INFO,
       "[NEW] RecoverAfterSwitchFailure: starting recovery (reason=%s, step=%s)",
       preservedError.reason.c_str(), preservedError.step.c_str());

  const bool stopped = GetEngine()->Stop();
  auto stopError = GetEngine()->GetLastErrorInfo();
  if (stopError.reason.empty() && !preservedError.reason.empty()) {
    stopError = preservedError;
  }
  if (!stopped) {
    LOGF(LOG_ERROR,
         "[NEW] RecoverAfterSwitchFailure: stop timeout, skip reset to avoid lifecycle overlap");
    return;
  }

  const bool reachedStopped = GetEngine()->WaitForState(EngineState::STOPPED, timeoutMs);
  if (!reachedStopped) {
    LOGF(LOG_WARN,
         "[NEW] RecoverAfterSwitchFailure: timeout waiting STOPPED, proceeding with Reset anyway");
  }

  GetEngine()->Reset();
  LOGF(LOG_INFO, "[NEW] RecoverAfterSwitchFailure: Reset() completed, engine back to INIT");

  if (!stopError.reason.empty()) {
    GetEngine()->SetLastErrorInfo(stopError.reason, stopError.step,
                                  stopError.message);
  }
}

static void RecoverAfterStopRequestFailure(uint32_t timeoutMs, uint64_t token) {
  auto preservedError = GetEngine()->GetLastErrorInfo();
  if (!IsLatestSwitchToken(token)) {
    return;
  }
  if (WaitForStateWithToken(EngineState::STOPPED, timeoutMs, token)) {
    GetEngine()->Reset();
    if (!preservedError.reason.empty()) {
      GetEngine()->SetLastErrorInfo(preservedError.reason, preservedError.step,
                                    preservedError.message);
    }
    return;
  }
  if (GetEngine()->WaitForState(EngineState::INIT, 0)) {
    if (!preservedError.reason.empty()) {
      GetEngine()->SetLastErrorInfo(preservedError.reason, preservedError.step,
                                    preservedError.message);
    }
    return;
  }
  EnsureLastErrorIfEmpty("switch_stop_unrecovered", "Stop",
                         "Stop() failed and engine did not reach STOPPED/INIT");
}

static void ExecuteSwitchGame(napi_env env, void *data) {
  auto *ctx = static_cast<SwitchGameAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (!AcquireSwitchToken(ctx->token)) {
    EnsureLastErrorIfEmpty("switch_cancelled", "AcquireSwitchToken",
                           "stale switch token before acquire");
    ctx->result = false;
    return;
  }
  struct SwitchTokenGuard {
    uint64_t token;
    ~SwitchTokenGuard() { ReleaseSwitchToken(token); }
  } guard{ctx->token};

  if (!IsLatestSwitchToken(ctx->token)) {
    EnsureLastErrorIfEmpty("switch_cancelled", "SwitchToken",
                           "stale switch token after acquire");
    ctx->result = false;
    return;
  }

  GetEngine()->ClearLastErrorInfo();

  const EngineState currentState = GetEngine()->GetState();
  if (currentState != EngineState::INIT &&
      currentState != EngineState::STOPPED) {
    if (!GetEngine()->Stop()) {
      EnsureLastErrorIfEmpty("switch_stop_failed", "Stop",
                             "Stop() returned false before switch");
      RecoverAfterStopRequestFailure(ctx->timeoutMs, ctx->token);
      ctx->result = false;
      return;
    }
    if (!WaitForStateWithToken(EngineState::STOPPED, ctx->timeoutMs,
                               ctx->token)) {
      EnsureLastErrorIfEmpty("switch_wait_stopped_timeout", "WaitForState",
                             "timeout waiting STOPPED before switch");
      RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
      ctx->result = false;
      return;
    }
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    EnsureLastErrorIfEmpty("switch_cancelled", "SwitchToken",
                           "stale switch token before start");
    ctx->result = false;
    return;
  }

  if (!GetEngine()->Start()) {
    EnsureLastErrorIfEmpty("switch_start_failed", "Start",
                           "Start() returned false");
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!GetEngine()->SetFilesDir(ctx->filesDir)) {
    EnsureLastErrorIfEmpty("switch_set_files_dir_failed", "SetFilesDir",
                           "SetFilesDir() returned false");
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    EnsureLastErrorIfEmpty("switch_cancelled", "SwitchToken",
                           "stale switch token before load core");
    ctx->result = false;
    return;
  }

  if (!GetEngine()->LoadCore(ctx->corePath)) {
    EnsureLastErrorIfEmpty("switch_load_core_failed", "LoadCore",
                           "LoadCore() returned false");
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }
  if (!WaitForStateWithToken(EngineState::CORE_LOADED, ctx->timeoutMs,
                             ctx->token)) {
    EnsureLastErrorIfEmpty("switch_wait_core_loaded_timeout", "WaitForState",
                           "timeout waiting CORE_LOADED");
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }

  if (!IsLatestSwitchToken(ctx->token)) {
    EnsureLastErrorIfEmpty("switch_cancelled", "SwitchToken",
                           "stale switch token before load game");
    ctx->result = false;
    return;
  }

  if (!GetEngine()->LoadGame(ctx->romPath, ctx->romData)) {
    EnsureLastErrorIfEmpty("switch_load_game_failed", "LoadGame",
                           "LoadGame() returned false");
    RecoverAfterSwitchFailure(ctx->timeoutMs, ctx->token);
    ctx->result = false;
    return;
  }
  if (!WaitForStateWithToken(EngineState::RUNNING, ctx->timeoutMs,
                             ctx->token)) {
    EnsureLastErrorIfEmpty("switch_wait_running_timeout", "WaitForState",
                           "timeout waiting RUNNING");
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

  if (status != napi_ok) {
    GetEngine()->SetLastErrorInfo("switch_async_work_failed",
                                  "SwitchGameAsync",
                                  "SwitchGameAsync complete callback status was not napi_ok");
    ctx->result = false;
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
  uint64_t callerToken = 0;
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
      callerToken = static_cast<uint64_t>(tokenValue);
    }
  }

  std::string resolvedRomPath(romPath);
  std::shared_ptr<std::vector<uint8_t>> romData = nullptr;
  if (!LoadRomDataFromRawfileIfNeeded(env, resolvedRomPath, resMgrValue,
                                      std::string(filesDir),
                                      resolvedRomPath, romData)) {
    return MakeResolvedPromise(env, false);
  }

  if (ShouldDedupSwitchRequest(std::string(corePath), resolvedRomPath)) {
    LOGF(LOG_WARN,
         "[NEW] SwitchGameAsync deduped duplicate request within %{public}llu ms",
         static_cast<unsigned long long>(kSwitchDedupeWindowMs));
    return MakeResolvedPromise(env, true);
  }

  // 使用 native 全局递增 token 作为并发仲裁依据，避免前端局部 token
  // 与 native 全局 token 不同源导致误判 stale。
  token = switch_token.fetch_add(1) + 1;
  if (callerToken > 0) {
    LOGF(LOG_INFO,
         "[NEW] SwitchGameAsync token mapped: caller=%{public}llu, native=%{public}llu",
         static_cast<unsigned long long>(callerToken),
         static_cast<unsigned long long>(token));
  }

  auto *ctx = new SwitchGameAsyncContext();
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
  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSwitchGame,
      CompleteSwitchGame, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] SwitchGameAsync create work failed");
    GetEngine()->SetLastErrorInfo("switch_async_create_failed",
                                  "SwitchGameAsync",
                                  "napi_create_async_work failed");
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] SwitchGameAsync queue work failed");
    GetEngine()->SetLastErrorInfo("switch_async_queue_failed",
                                  "SwitchGameAsync",
                                  "napi_queue_async_work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value CancelSwitch(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, "[NEW] CancelSwitch called");

  // 递增 switch_token 使所有等待中的 switch 请求失效
  const uint64_t newToken = switch_token.fetch_add(1) + 1;
  LOGF(LOG_INFO, "[NEW] CancelSwitch: incremented token to %{public}llu",
       static_cast<unsigned long long>(newToken));

  // 释放当前持有的 switch token（如果有）
  {
    std::lock_guard<std::mutex> lock(switch_mutex);
    if (active_switch_token != 0) {
      LOGF(LOG_INFO, "[NEW] CancelSwitch: releasing active token %{public}llu",
           static_cast<unsigned long long>(active_switch_token));
      active_switch_token = 0;
      switch_cond.notify_all();
    }
  }

  // 向 Engine 发送 Cancel 消息
  GetEngine()->Cancel();

  return MakeBool(env, true);
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
  const bool stopped = GetEngine()->Stop();

  return MakeBool(env, stopped);
  NAPI_TRY_CATCH_END(env, nullptr)
}

struct StopEngineAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  bool stopped = false;
};

static void ExecuteStopEngineAsync(napi_env env, void *data) {
  auto *ctx = static_cast<StopEngineAsyncContext *>(data);
  if (!ctx) {
    return;
  }
  ctx->stopped = GetEngine()->Stop();
  // 门禁在 Execute 尾部复位，确保异常路径（Stop 超时返回 false）也能解除门禁，
  // 让后续调用不被永久阻断。Complete 不再重复复位。
  stop_in_progress.store(false);
}

static void CompleteStopEngineAsync(napi_env env, napi_status status,
                                    void *data) {
  auto *ctx = static_cast<StopEngineAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] StopEngineAsync work failed: status=%{public}d",
         static_cast<int>(status));
    GetEngine()->SetLastErrorInfo("stop_async_work_failed",
                                  "StopEngineAsync",
                                  "StopEngineAsync complete callback status was not napi_ok");
    napi_value errMsg;
    napi_create_string_utf8(env, "stop_async_work_failed", NAPI_AUTO_LENGTH,
                            &errMsg);
    napi_reject_deferred(env, ctx->deferred, errMsg);
  } else {
    if (!ctx->stopped) {
      LOGF(LOG_WARN,
           "[NEW] StopEngineAsync completed with stop timeout/failure");
    }
    napi_value result;
    napi_get_boolean(env, ctx->stopped, &result);
    napi_resolve_deferred(env, ctx->deferred, result);
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value StopEngineAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] StopEngineAsync called");
  if (stop_in_progress.exchange(true)) {
    LOGF(LOG_WARN, "[NEW] StopEngineAsync ignored: stop already in progress");
    return MakeResolvedPromise(env, true);
  }

  auto *ctx = new StopEngineAsyncContext();

  napi_value promise;
  napi_create_promise(env, &ctx->deferred, &promise);

  napi_value resourceName;
  napi_create_string_utf8(env, "StopEngineAsyncWork", NAPI_AUTO_LENGTH,
                          &resourceName);
  napi_status createStatus =
      napi_create_async_work(env, nullptr, resourceName, ExecuteStopEngineAsync,
                             CompleteStopEngineAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    LOGF(LOG_ERROR, "[NEW] StopEngineAsync create work failed");
    GetEngine()->SetLastErrorInfo("stop_async_create_failed",
                                  "StopEngineAsync",
                                  "napi_create_async_work failed");
    stop_in_progress.store(false);
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] StopEngineAsync queue work failed");
    GetEngine()->SetLastErrorInfo("stop_async_queue_failed",
                                  "StopEngineAsync",
                                  "napi_queue_async_work failed");
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    stop_in_progress.store(false);
    napi_value falseVal;
    napi_get_boolean(env, false, &falseVal);
    napi_resolve_deferred(env, ctx->deferred, falseVal);
    delete ctx;
    return promise;
  }

  return promise;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ResetEngine(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, " [NEW] ResetEngine called");
  GetEngine()->Reset();
  const bool resetOk = GetEngine()->GetState() == EngineState::INIT;
  if (!resetOk) {
    LOGF(LOG_WARN, "[NEW] ResetEngine did not converge to INIT");
  }
  return MakeBool(env, resetOk);
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

void RegisterLifecycleNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredStartEngine", nullptr, StartEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredStopEngine", nullptr, StopEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredStopEngineAsync", nullptr, StopEngineAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResetEngine", nullptr, ResetEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredPauseEngine", nullptr, PauseEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredResumeEngine", nullptr, ResumeEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadCore", nullptr, LoadCore, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredLoadRom", nullptr, LoadRom, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSwitchGameAsync", nullptr, SwitchGameAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredCancelSwitch", nullptr, CancelSwitch, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetRawFileList", nullptr, GetRawFileList, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetRawFileListAsync", nullptr, GetRawFileListAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredInitEventBridge", nullptr, InitEventBridge, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {
    LOGF(LOG_ERROR, "[NEW] RegisterLifecycleNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
