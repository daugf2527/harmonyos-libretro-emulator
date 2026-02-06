/*
 * Phase 3.2 - Game2048 Native NAPI 实现
 */

#include "game2048_native_napi.h"
#include "app/framework/plugin_manager.h"
#include "hilog/log.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "Game2048NativeNAPI"

// 当前游戏 ID (用于 VSync 回调)
static std::string g_currentGameId;

/**
 * 初始化游戏
 * @param xComponentId XComponent ID
 * @param soPath Libretro 核心路径
 * @return boolean 是否成功
 */
napi_value Game2048Native_InitGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048Native_InitGame called");

  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 获取 XComponent ID
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *xcomp_id = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], xcomp_id, str_size + 1, &str_size);
  std::string xComponentId(xcomp_id);
  delete[] xcomp_id;

  // 获取 SO 路径
  napi_get_value_string_utf8(env, args[1], nullptr, 0, &str_size);
  char *so_path = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[1], so_path, str_size + 1, &str_size);
  std::string soPath(so_path);
  delete[] so_path;

  std::string filesDirStr;
  if (argc >= 3) {
    napi_valuetype t;
    napi_typeof(env, args[2], &t);
    if (t == napi_string) {
      napi_get_value_string_utf8(env, args[2], nullptr, 0, &str_size);
      char *files_dir = new char[str_size + 1];
      napi_get_value_string_utf8(env, args[2], files_dir, str_size + 1,
                                 &str_size);
      filesDirStr.assign(files_dir);
      delete[] files_dir;
    }
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "XComponent ID: %{public}s", xComponentId.c_str());
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "SO Path: %{public}s", soPath.c_str());

  // 获取 Game2048NativeApp 实例
  auto app = PluginManager::GetInstance()->GetGame2048Native(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无法获取 Game2048NativeApp 实例");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
  }

  // 初始化游戏
  bool success = app->InitGame(soPath, filesDirStr);

  if (success) {
    g_currentGameId = xComponentId;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 游戏初始化成功");
  }

  napi_value result;
  napi_get_boolean(env, success, &result);
  return result;
}

/**
 * 启动游戏循环 (VSync 驱动)
 * @param xComponentId XComponent ID
 */
napi_value Game2048Native_StartGameLoop(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048Native_StartGameLoop called (VSync)");

  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "参数不足");
    return nullptr;
  }

  // 获取 XComponent ID
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *xcomp_id = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], xcomp_id, str_size + 1, &str_size);
  std::string xComponentId(xcomp_id);
  delete[] xcomp_id;

  g_currentGameId = xComponentId;

  // 启动 VSync 驱动的游戏循环
  auto app = PluginManager::GetInstance()->GetGame2048Native(xComponentId);
  if (app) {
    app->StartVSync();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ VSync 游戏循环已启动 (跟随系统帧率)");
  } else {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "无法获取 Game2048NativeApp 实例");
  }

  return nullptr;
}

/**
 * 停止游戏循环 (VSync)
 */
napi_value Game2048Native_StopGameLoop(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048Native_StopGameLoop called (VSync)");

  if (!g_currentGameId.empty()) {
    auto app = PluginManager::GetInstance()->GetGame2048Native(g_currentGameId);
    if (app) {
      app->StopVSync();
      OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ VSync 游戏循环已停止");
    }
  }

  return nullptr;
}

/**
 * 重置游戏
 */
napi_value Game2048Native_ResetGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048Native_ResetGame called");

  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    return nullptr;
  }

  // 获取 XComponent ID
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *xcomp_id = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], xcomp_id, str_size + 1, &str_size);
  std::string xComponentId(xcomp_id);
  delete[] xcomp_id;

  auto app = PluginManager::GetInstance()->GetGame2048Native(xComponentId);
  if (app) {
    app->ResetGame();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 游戏已重置");
  }

  return nullptr;
}

/**
 * 清理游戏
 */
napi_value Game2048Native_DeinitGame(napi_env env, napi_callback_info info) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048Native_DeinitGame called");

  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    return nullptr;
  }

  // 获取 XComponent ID
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *xcomp_id = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], xcomp_id, str_size + 1, &str_size);
  std::string xComponentId(xcomp_id);
  delete[] xcomp_id;

  auto app = PluginManager::GetInstance()->GetGame2048Native(xComponentId);
  if (app) {
    // 先停止 VSync
    app->StopVSync();
    // 再清理游戏
    app->DeinitGame();
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 游戏已清理");
  }

  return nullptr;
}

/**
 * 设置输入
 */
napi_value Game2048Native_SetInput(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 3) {
    return nullptr;
  }

  // 获取 XComponent ID
  size_t str_size;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_size);
  char *xcomp_id = new char[str_size + 1];
  napi_get_value_string_utf8(env, args[0], xcomp_id, str_size + 1, &str_size);
  std::string xComponentId(xcomp_id);
  delete[] xcomp_id;

  // 获取按键 ID
  int32_t keyId;
  napi_get_value_int32(env, args[1], &keyId);

  // 获取按键状态
  bool pressed;
  napi_get_value_bool(env, args[2], &pressed);

  auto app = PluginManager::GetInstance()->GetGame2048Native(xComponentId);
  if (app) {
    app->SetInput(keyId, pressed);
  }

  return nullptr;
}

/**
 * 注册 NAPI 函数
 */
void RegisterGame2048NativeNapi(napi_env env, napi_value exports) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RegisterGame2048NativeNapi START");

  napi_property_descriptor desc[] = {
      {"initGameNative", nullptr, Game2048Native_InitGame, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"startGameLoopNative", nullptr, Game2048Native_StartGameLoop, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"stopGameLoopNative", nullptr, Game2048Native_StopGameLoop, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"resetGameNative", nullptr, Game2048Native_ResetGame, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"deinitGameNative", nullptr, Game2048Native_DeinitGame, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"setInputNative", nullptr, Game2048Native_SetInput, nullptr, nullptr,
       nullptr, napi_default, nullptr}};

  napi_status status = napi_define_properties(
      env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (status != napi_ok) {
    OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "napi_define_properties FAILED");
    return;
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Game2048Native NAPI functions registered");
}
