/*
 * Input Mapping NAPI Interface
 * 提供键位映射配置的 NAPI 接口
 */

#ifndef INPUT_MAPPING_NAPI_H
#define INPUT_MAPPING_NAPI_H

#include <napi/native_api.h>

/**
 * 注册输入映射相关的 NAPI 接口
 */
void RegisterInputMappingNapi(napi_env env, napi_value exports);

#endif // INPUT_MAPPING_NAPI_H
