/*
 * Phase 3.2 - Game2048 Wrapper 头文件
 */

#ifndef GAME2048_WRAPPER_H
#define GAME2048_WRAPPER_H

#include "napi/native_api.h"

// 导出的 NAPI 函数
napi_value Game2048_InitGame(napi_env env, napi_callback_info info);
napi_value Game2048_RunFrame(napi_env env, napi_callback_info info);
napi_value Game2048_ResetGame(napi_env env, napi_callback_info info);
napi_value Game2048_DeinitGame(napi_env env, napi_callback_info info);
napi_value Game2048_SetInput(napi_env env, napi_callback_info info);

#endif // GAME2048_WRAPPER_H
