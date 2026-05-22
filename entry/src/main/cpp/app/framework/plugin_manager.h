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
#ifndef PLUGIN_MANAGER_H
#define PLUGIN_MANAGER_H

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <cstdint>
#include <js_native_api.h>
#include <js_native_api_types.h>
#include <mutex>
#include <string>
#include <unordered_map>

struct NewArchInputStats {
  uint64_t touchCount = 0;
  uint64_t mouseCount = 0;
  uint64_t keyCount = 0;
  bool hasFocus = false;
  bool mouseDown = false;
  int lastTouchType = -1;
  int lastMouseAction = -1;
  int lastKeyAction = -1;
};

class PluginManager {
public:
  ~PluginManager();

  static PluginManager *GetInstance();

  void SetNativeXComponent(std::string &id,
                           OH_NativeXComponent *nativeXComponent);
  void Export(napi_env env, napi_value exports);
  bool GetNewArchInputStats(NewArchInputStats &out) const;

private:
  // nativeXComponentMap_ 在 napi 调用线程(Export)与 UI 线程(SetNativeXComponent
  // 经由 Surface 回调)之间共享,必须用 mutex 保护避免哈希表内部状态损坏。
  mutable std::mutex map_mutex_;
  std::unordered_map<std::string, OH_NativeXComponent *> nativeXComponentMap_;
};
#endif // PLUGIN_MANAGER_H
