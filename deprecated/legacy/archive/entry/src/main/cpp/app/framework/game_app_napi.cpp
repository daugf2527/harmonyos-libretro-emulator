/*
 * Libretro 通用游戏页面 NAPI 接口
 */

#include "app/framework/plugin_manager.h"
#include "game_app.h"
#include "input/retropad_napi.h"
#include "platform/audio/audio_bridge.h"
#include <hilog/log.h>
 #include <rawfile/raw_file_manager.h>
 #include <string>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "LibretroGameNAPI"

 namespace {
 bool GetNapiStringUtf8(napi_env env, napi_value value, std::string &out)
 {
   size_t size = 0;
   if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) {
     return false;
   }

   std::string buf;
   buf.resize(size + 1);

   size_t written = 0;
   if (napi_get_value_string_utf8(env, value, &buf[0], buf.size(), &written) !=
       napi_ok) {
     return false;
   }

   buf.resize(written);
   out.swap(buf);
   return true;
 }

 bool GetOptionalNapiStringUtf8(napi_env env, napi_value value, std::string &out)
 {
   napi_valuetype t = napi_undefined;
   if (napi_typeof(env, value, &t) != napi_ok || t != napi_string) {
     return false;
   }
   return GetNapiStringUtf8(env, value, out);
 }
 } // namespace

// 加载核心（参考 Game2048Native_InitGame）
static napi_value LoadCore(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 参数不足");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取 XComponent ID
  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取核心路径
  std::string corePath;
  if (!GetNapiStringUtf8(env, args[1], corePath)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string filesDirStr;
  if (argc >= 3) {
    (void)GetOptionalNapiStringUtf8(env, args[2], filesDirStr);
  }

  std::string cacheDirStr;
  if (argc >= 4) {
    (void)GetOptionalNapiStringUtf8(env, args[3], cacheDirStr);
  }

  // 通过 PluginManager 获取 LibretroGameApp 实例
  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无法获取 LibretroGameApp 实例");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  bool success = app->LoadCore(corePath, filesDirStr, cacheDirStr);

  napi_value result;
  napi_get_boolean(env, success, &result);
  return result;
}

static napi_value HasCoreLoaded(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  bool loaded = false;
  if (app && app->GetRenderer()) {
    loaded = app->GetRenderer()->HasCoreLoaded();
  }

  napi_value result;
  napi_get_boolean(env, loaded, &result);
  return result;
}

static napi_value HasRomLoaded(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  bool loaded = false;
  if (app && app->GetRenderer()) {
    loaded = app->GetRenderer()->HasRomLoaded();
  }

  napi_value result;
  napi_get_boolean(env, loaded, &result);
  return result;
}

static napi_value GetState(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_create_int32(env, -1, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_create_int32(env, -1, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  int32_t state = -1;
  if (app && app->GetRenderer()) {
    state = static_cast<int32_t>(app->GetRenderer()->GetState());
  }

  napi_value result;
  napi_create_int32(env, state, &result);
  return result;
}

static napi_value IsCloseComplete(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  bool ok = true;
  if (app && app->GetRenderer()) {
    ok = !app->GetRenderer()->HasCoreLoaded() && !app->GetRenderer()->HasRomLoaded();
  }

  napi_value result;
  napi_get_boolean(env, ok, &result);
  return result;
}

static napi_value GetStats(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
  }

  libretro::LibretroRuntimeStats stats{};
  int32_t state = -1;
  int32_t videoWidth = 0;
  int32_t videoHeight = 0;
  double fps = 0.0;
  int32_t audioSampleRate = 0;

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (app && app->GetRenderer()) {
    state = static_cast<int32_t>(app->GetRenderer()->GetState());
    videoWidth = app->GetRenderer()->GetVideoWidth();
    videoHeight = app->GetRenderer()->GetVideoHeight();
    fps = app->GetRenderer()->GetFps();
    audioSampleRate = app->GetRenderer()->GetAudioSampleRate();
    app->GetRenderer()->GetRuntimeStats(stats);
  }

  // Audio stats (global singleton)
  float audioBufferUsage = 0.0f;
  size_t audioUnderruns = 0;
  size_t audioOverruns = 0;
  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    audioBufferUsage = audioBridge->GetBufferUsage();
    audioBridge->GetBufferStats(audioUnderruns, audioOverruns);
  }

  napi_value obj;
  napi_create_object(env, &obj);

  napi_value v;
  napi_create_int32(env, state, &v);
  napi_set_named_property(env, obj, "state", v);
  napi_create_int32(env, videoWidth, &v);
  napi_set_named_property(env, obj, "videoWidth", v);
  napi_create_int32(env, videoHeight, &v);
  napi_set_named_property(env, obj, "videoHeight", v);
  napi_create_double(env, fps, &v);
  napi_set_named_property(env, obj, "fps", v);
  napi_create_int32(env, audioSampleRate, &v);
  napi_set_named_property(env, obj, "audioSampleRate", v);

  napi_create_double(env, static_cast<double>(stats.videoRefreshCalls), &v);
  napi_set_named_property(env, obj, "videoRefreshCalls", v);
  napi_create_double(env, static_cast<double>(stats.videoNullFrames), &v);
  napi_set_named_property(env, obj, "videoNullFrames", v);
  napi_create_double(env, static_cast<double>(stats.videoDupeFrames), &v);
  napi_set_named_property(env, obj, "videoDupeFrames", v);
  napi_create_double(env, static_cast<double>(stats.audioBatchCalls), &v);
  napi_set_named_property(env, obj, "audioBatchCalls", v);
  napi_create_double(env, static_cast<double>(stats.audioFramesIn), &v);
  napi_set_named_property(env, obj, "audioFramesIn", v);

  napi_create_double(env, static_cast<double>(stats.nwRequestBufferCalls), &v);
  napi_set_named_property(env, obj, "nwRequestBufferCalls", v);
  napi_create_double(env, static_cast<double>(stats.nwRequestBufferFailures), &v);
  napi_set_named_property(env, obj, "nwRequestBufferFailures", v);
  napi_create_double(env, static_cast<double>(stats.nwAbortBufferCalls), &v);
  napi_set_named_property(env, obj, "nwAbortBufferCalls", v);
  napi_create_double(env, static_cast<double>(stats.nbFromWindowBufferFailures), &v);
  napi_set_named_property(env, obj, "nbFromWindowBufferFailures", v);
  napi_create_double(env, static_cast<double>(stats.nbMapFailures), &v);
  napi_set_named_property(env, obj, "nbMapFailures", v);
  napi_create_double(env, static_cast<double>(stats.nbUnmapFailures), &v);
  napi_set_named_property(env, obj, "nbUnmapFailures", v);
  napi_create_double(env, static_cast<double>(stats.nwFlushBufferCalls), &v);
  napi_set_named_property(env, obj, "nwFlushBufferCalls", v);
  napi_create_double(env, static_cast<double>(stats.nwFlushBufferFailures), &v);
  napi_set_named_property(env, obj, "nwFlushBufferFailures", v);
  napi_create_double(env, static_cast<double>(stats.fencePollCalls), &v);
  napi_set_named_property(env, obj, "fencePollCalls", v);
  napi_create_double(env, static_cast<double>(stats.fencePollFailures), &v);
  napi_set_named_property(env, obj, "fencePollFailures", v);
  napi_create_double(env, static_cast<double>(stats.fencePollTimeouts), &v);
  napi_set_named_property(env, obj, "fencePollTimeouts", v);

  napi_create_double(env, audioBufferUsage, &v);
  napi_set_named_property(env, obj, "audioBufferUsage", v);
  napi_create_double(env, static_cast<double>(audioUnderruns), &v);
  napi_set_named_property(env, obj, "audioUnderruns", v);
  napi_create_double(env, static_cast<double>(audioOverruns), &v);
  napi_set_named_property(env, obj, "audioOverruns", v);

  return obj;
}

static napi_value ResetStats(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  bool ok = true;
  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (app && app->GetRenderer()) {
    app->GetRenderer()->ResetRuntimeStats();
  }

  auto *audioBridge = libretro::AudioBridge::GetInstance();
  if (audioBridge) {
    audioBridge->ResetBufferStats();
  }

  napi_value result;
  napi_get_boolean(env, ok, &result);
  return result;
}

// 加载 ROM（参考 Game2048Native_InitGame）
static napi_value LoadRom(napi_env env, napi_callback_info info) {
  size_t argc = 5;
  napi_value args[5];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 3) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 参数不足");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取 XComponent ID
  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取 ROM 路径
  std::string romPathStr;
  if (!GetNapiStringUtf8(env, args[1], romPathStr)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string filesDirStr;
  if (argc >= 4) {
    (void)GetOptionalNapiStringUtf8(env, args[3], filesDirStr);
  }

  std::string cacheDirStr;
  if (argc >= 5) {
    (void)GetOptionalNapiStringUtf8(env, args[4], cacheDirStr);
  }

  // 加载 ROM (直接传递 env 和 args[2])
  // 通过 PluginManager 获取 LibretroGameApp 实例
  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无法获取 LibretroGameApp 实例");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  NativeResourceManager *nativeResourceManager =
      OH_ResourceManager_InitNativeResourceManager(env, args[2]);
  if (!nativeResourceManager) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "❌ 初始化 ResourceManager 失败");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  bool success =
      app->LoadRom(romPathStr, nativeResourceManager, filesDirStr, cacheDirStr);

  OH_ResourceManager_ReleaseNativeResourceManager(nativeResourceManager);

  napi_value result;
  napi_get_boolean(env, success, &result);
  return result;
}

// 开始游戏（参考 Game2048Native_StartGame）
static napi_value StartGame(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 通过 PluginManager 获取 LibretroGameApp 实例
  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无法获取 LibretroGameApp 实例");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  app->StartGame();

  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

static napi_value CloseContent(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  bool success = false;
  if (app) {
    success = app->RequestCloseContent();
  }

  napi_value result;
  napi_get_boolean(env, success, &result);
  return result;
}

// 暂停游戏
static napi_value PauseGame(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (app) {
    app->PauseGame();
  }

  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

// 停止游戏
static napi_value StopGame(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (app) {
    app->StopGame();
  }

  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

// 运行一帧
static napi_value RunFrame(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (app) {
    app->RunFrame();
  }

  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

// 设置按键状态
static napi_value SetButtonState(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 3) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  napi_valuetype idType = napi_undefined;
  napi_valuetype btnType = napi_undefined;
  napi_valuetype pressedType = napi_undefined;
  napi_valuetype portType = napi_undefined;
  napi_typeof(env, args[0], &idType);
  napi_typeof(env, args[1], &btnType);
  napi_typeof(env, args[2], &pressedType);
  if (argc >= 4) {
    napi_typeof(env, args[3], &portType);
  }

  if (idType != napi_string || btnType != napi_number ||
      pressedType != napi_boolean ||
      (argc >= 4 && portType != napi_number)) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "libretroSetButtonState: 参数类型错误");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取 ID
  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取按键 ID
  int32_t buttonId;
  napi_get_value_int32(env, args[1], &buttonId);

  // 获取按下状态
  bool pressed;
  napi_get_value_bool(env, args[2], &pressed);

  int32_t port = 0;
  if (argc >= 4) {
    napi_get_value_int32(env, args[3], &port);
  }

  if (port < 0 || port >= 4) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "libretroSetButtonState: port 超范围: %{public}d",
                 port);
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  if (buttonId < 0 || buttonId >= 16) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "libretroSetButtonState: buttonId 超范围: %{public}d",
                 buttonId);
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  auto app = PluginManager::GetInstance()->GetLibretroGame(xComponentId);
  if (!app) {
    // 兜底：实例未创建时，仍允许写入全局 RetroPad 状态
    SetRetroPadButtonState(port, buttonId, pressed);
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                "libretroSetButtonState: 未找到实例(已写入全局输入): %{public}s",
                xComponentId.c_str());
  } else {
    static size_t btnLogs = 0;
    btnLogs++;
    if (btnLogs <= 20) {
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                  "libretroSetButtonState: id=%{public}s port=%{public}d btn=%{public}d pressed=%{public}d",
                  xComponentId.c_str(), port, buttonId, pressed);
    }
    app->SetButtonState(static_cast<unsigned>(port),
                        static_cast<unsigned>(buttonId), pressed);
  }

  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

// 释放渲染器
static napi_value ReleaseRenderer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  std::string xComponentId;
  if (!GetNapiStringUtf8(env, args[0], xComponentId)) {
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  bool ok = PluginManager::GetInstance()->ReleaseLibretroGame(xComponentId);

  napi_value result;
  napi_get_boolean(env, ok, &result);
  return result;
}

// 注册 NAPI 函数
void RegisterLibretroGameNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"libretroLoadCore", nullptr, LoadCore, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroLoadRom", nullptr, LoadRom, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroStartGame", nullptr, StartGame, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroPauseGame", nullptr, PauseGame, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroStopGame", nullptr, StopGame, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroCloseContent", nullptr, CloseContent, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroHasCoreLoaded", nullptr, HasCoreLoaded, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroHasRomLoaded", nullptr, HasRomLoaded, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroGetState", nullptr, GetState, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroGetStats", nullptr, GetStats, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroResetStats", nullptr, ResetStats, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroIsCloseComplete", nullptr, IsCloseComplete, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"libretroRunFrame", nullptr, RunFrame, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"libretroSetButtonState", nullptr, SetButtonState, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"libretroReleaseRenderer", nullptr, ReleaseRenderer, nullptr, nullptr,
       nullptr, napi_default, nullptr}};

  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ LibretroGame NAPI 注册完成");
}
