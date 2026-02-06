/*
 * CoreLoader NAPI 接口头文件
 * Phase 3.1 - 暴露给 ArkTS 的测试接口
 */

#ifndef CORE_LOADER_NAPI_H
#define CORE_LOADER_NAPI_H

#include "napi/native_api.h"

/**
 * 注册 CoreLoader 相关的 NAPI 函数
 * 在 hello.cpp 的 Init 函数中调用
 */
void RegisterCoreLoaderNapi(napi_env env, napi_value exports);

#endif // CORE_LOADER_NAPI_H
