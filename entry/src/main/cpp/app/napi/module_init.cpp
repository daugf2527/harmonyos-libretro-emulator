/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "app/framework/plugin_manager.h"
#include "app/napi/core_loader_napi.h"
#include "napi/native_api.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD001
#define LOG_TAG "ModuleInit"
#undef LOG_FLOW
#define LOG_FLOW "NAPI"
#include "common/log_prefix.h"

// Gambatte 测试函数声明（测试文件已移至tests/目录，暂时禁用）
// extern void RegisterGambatteTestNapi(napi_env env, napi_value exports);
// extern void RegisterGambatteROMTestNapi(napi_env env, napi_value exports);

// 通用 Libretro (重构引擎) NAPI 声明
extern void RegisterLibretroRefactoredNapi(napi_env env, napi_value exports);

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  LOGF(LOG_INFO, "========== libentry.so Init START ==========");

  // 注册 XComponent 相关接口
  LOGF(LOG_INFO, "Registering XComponent interfaces...");
  PluginManager::GetInstance()->Export(env, exports);
  LOGF(LOG_INFO, "XComponent interfaces registered");

  // 注册 CoreLoader 测试接口 (Phase 3.1)
  LOGF(LOG_INFO, "Registering CoreLoader NAPI interfaces...");
  RegisterCoreLoaderNapi(env, exports);
  LOGF(LOG_INFO, "CoreLoader NAPI interfaces registered");

  // [LEGACY] 注册 Gambatte 测试接口（已禁用，测试文件在tests/目录）
  // LOGF(LOG_INFO, "Registering Gambatte test interfaces...");
  // RegisterGambatteTestNapi(env, exports);
  // RegisterGambatteROMTestNapi(env, exports);
  // LOGF(LOG_INFO, "Gambatte test interfaces registered");

  // 注册重构后的模拟器接口
  LOGF(LOG_INFO, "Registering Libretro Refactored interfaces...");
  RegisterLibretroRefactoredNapi(env, exports);
  LOGF(LOG_INFO, "Libretro Refactored interfaces registered");

  LOGF(LOG_INFO, "========== libentry.so Init COMPLETE ==========");
  return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
  LOGF(LOG_INFO, "========== RegisterEntryModule CALLED ==========");
  napi_module_register(&demoModule);
  LOGF(LOG_INFO, "========== napi_module_register COMPLETE ==========");
}
