/*
 * Phase 3.2 - Game2048 Native NAPI 接口
 * 为 Game2048Native.ets 提供 NAPI 函数
 */

#ifndef GAME2048_NATIVE_NAPI_H
#define GAME2048_NATIVE_NAPI_H

#include "napi/native_api.h"

// NAPI 函数声明
napi_value Game2048Native_InitGame(napi_env env, napi_callback_info info);
napi_value Game2048Native_StartGameLoop(napi_env env, napi_callback_info info);
napi_value Game2048Native_StopGameLoop(napi_env env, napi_callback_info info);
napi_value Game2048Native_ResetGame(napi_env env, napi_callback_info info);
napi_value Game2048Native_DeinitGame(napi_env env, napi_callback_info info);
napi_value Game2048Native_SetInput(napi_env env, napi_callback_info info);

// 注册函数
void RegisterGame2048NativeNapi(napi_env env, napi_value exports);

#endif // GAME2048_NATIVE_NAPI_H
