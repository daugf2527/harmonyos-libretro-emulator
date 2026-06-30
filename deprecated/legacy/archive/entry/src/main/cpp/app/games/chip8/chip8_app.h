/*
 * [LEGACY] This file is part of the old Standalone Chip8 implementation (Phase 2).
 * It is replaced by the Libretro Bridge architecture (Phase 3).
 *
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
#ifndef CHIP8_APP_H
#define CHIP8_APP_H

#include "core/emulators/chip8/chip8_core.h"
#include "platform/sync/vsync_manager.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <chrono>
#include <js_native_api.h>
#include <js_native_api_types.h>
#include <mutex>
#include <native_window/external_window.h>
#include <string>
#include <unordered_map>

class Chip8App {
public:
  // 构造函数需要 public 以支持 std::make_shared
  Chip8App(std::string id);
  ~Chip8App();

  static Chip8App *GetInstance(std::string &id);
  static void Release(std::string &id);

  void SetNativeWindow(OHNativeWindow *nativeWindow);
  void SetWidth(uint64_t width);
  void SetHeight(uint64_t height);

  // Core rendering function: draws a test pattern directly to the buffer
  void RenderTestFrame();

  // JS Export functions
  void Export(napi_env env, napi_value exports);
  static napi_value NapiDrawPattern(napi_env env, napi_callback_info info);
  static napi_value NapiChangeColor(napi_env env, napi_callback_info info);

  // XComponent Callbacks
  void RegisterCallback(OH_NativeXComponent *nativeXComponent);

  void ChangeColor();

private:
  void InitChip8();

  std::string id_;
  OHNativeWindow *nativeWindow_ = nullptr;
  OHNativeWindowBuffer *buffer_ = nullptr;
  int fenceFd_ = -1;

  uint64_t width_ = 0;
  uint64_t height_ = 0;

  // Animation state
  int offsetX_ = 0;
  uint32_t drawColor_ = 0xFFFF0000; // Default Red

  OH_NativeXComponent_Callback renderCallback_;

  // The Brain
  Chip8Core *core_ = nullptr;

  // VSync manager for hardware-synchronized rendering
  VsyncManager *vsyncManager_ = nullptr;

  // Performance monitoring
  std::chrono::steady_clock::time_point lastFpsTime_;
  int frameCount_ = 0;
  float currentFps_ = 0.0f;

  // Thread safety: 保护渲染相关的共享状态
  std::mutex renderMutex_;

  // VSync callback
  void OnVSyncFrame(long long timestamp);
};

#endif // CHIP8_APP_H
