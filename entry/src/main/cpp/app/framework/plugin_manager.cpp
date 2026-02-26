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

#include "plugin_manager.h"
#include "core/engine/libretro_engine.h"
#include "core/libretro/libretro.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <ace/xcomponent/native_xcomponent_key_event.h>
#include <atomic>
#include <cstdint>
#include <hilog/log.h>
#include <mutex>
#include <native_window/external_window.h>
#include <string>
#include <unordered_map>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD001
#undef LOG_TAG
#define LOG_TAG "PluginManager"
#undef LOG_FLOW
#define LOG_FLOW "UI"
#include "common/log_prefix.h"

namespace {
struct NewArchPointerState {
  bool mouseDown = false;
  bool hasFocus = false;
};

std::mutex &NewArchPointerStateMutex() {
  static std::mutex *m = new std::mutex();
  return *m;
}

std::unordered_map<std::string, NewArchPointerState> &NewArchPointerStateById() {
  static std::unordered_map<std::string, NewArchPointerState> *m =
      new std::unordered_map<std::string, NewArchPointerState>();
  return *m;
}

void SetNewArchMouseDown(const std::string &xId, bool down) {
  if (xId.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  NewArchPointerStateById()[xId].mouseDown = down;
}

bool GetNewArchMouseDown(const std::string &xId) {
  if (xId.empty()) {
    return false;
  }
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  auto &states = NewArchPointerStateById();
  auto it = states.find(xId);
  return it != states.end() ? it->second.mouseDown : false;
}

void SetNewArchHasFocus(const std::string &xId, bool focus) {
  if (xId.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  NewArchPointerStateById()[xId].hasFocus = focus;
}

bool AnyNewArchMouseDown() {
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  for (const auto &kv : NewArchPointerStateById()) {
    if (kv.second.mouseDown) {
      return true;
    }
  }
  return false;
}

bool AnyNewArchHasFocus() {
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  for (const auto &kv : NewArchPointerStateById()) {
    if (kv.second.hasFocus) {
      return true;
    }
  }
  return false;
}

void ClearNewArchPointerState(const std::string &xId) {
  if (xId.empty()) {
    return;
  }
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  NewArchPointerStateById().erase(xId);
}

void ClearAllNewArchPointerStates() {
  std::lock_guard<std::mutex> lock(NewArchPointerStateMutex());
  NewArchPointerStateById().clear();
}

std::string GetNewArchXComponentId(OH_NativeXComponent *component) {
  if (!component) {
    return std::string();
  }
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  if (OH_NativeXComponent_GetXComponentId(component, idStr, &idSize) !=
      OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    return std::string();
  }
  return std::string(idStr);
}

std::atomic<uint64_t> &TouchEventCount() {
  static std::atomic<uint64_t> *v = new std::atomic<uint64_t>(0);
  return *v;
}

std::atomic<uint64_t> &MouseEventCount() {
  static std::atomic<uint64_t> *v = new std::atomic<uint64_t>(0);
  return *v;
}

std::atomic<uint64_t> &KeyEventCount() {
  static std::atomic<uint64_t> *v = new std::atomic<uint64_t>(0);
  return *v;
}

std::atomic<int> &LastTouchType() {
  static std::atomic<int> *v = new std::atomic<int>(-1);
  return *v;
}

std::atomic<int> &LastMouseAction() {
  static std::atomic<int> *v = new std::atomic<int>(-1);
  return *v;
}

std::atomic<int> &LastKeyAction() {
  static std::atomic<int> *v = new std::atomic<int>(-1);
  return *v;
}

static bool NormalizeAndSendPointer(OH_NativeXComponent *component,
                                    void *window, int port, float x, float y,
                                    bool pressed) {
  if (!component || !window) {
    return false;
  }

  uint64_t width = 0;
  uint64_t height = 0;
  if (OH_NativeXComponent_GetXComponentSize(component, window, &width,
                                            &height) !=
          OH_NATIVEXCOMPONENT_RESULT_SUCCESS ||
      width == 0 || height == 0) {
    return false;
  }

  float normX = (x / static_cast<float>(width)) * 65535.0f - 32768.0f;
  float normY = (y / static_cast<float>(height)) * 65535.0f - 32768.0f;

  if (normX < -32768.0f)
    normX = -32768.0f;
  if (normX > 32767.0f)
    normX = 32767.0f;
  if (normY < -32768.0f)
    normY = -32768.0f;
  if (normY > 32767.0f)
    normY = 32767.0f;

  libretro::LibretroEngine::GetInstance()->SendPointer(
      port, static_cast<int16_t>(normX), static_cast<int16_t>(normY), pressed);
  return true;
}

static std::string BuildKeyDeviceId(OH_NativeXComponent_KeyEvent *keyEvent) {
  if (!keyEvent) {
    return std::string();
  }
  int64_t deviceId = -1;
  if (OH_NativeXComponent_GetKeyEventDeviceId(keyEvent, &deviceId) !=
      OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    return std::string();
  }
  return std::string("key:") + std::to_string(deviceId);
}

static std::string BuildMouseDeviceId() { return std::string("mouse:0"); }

static bool ResolvePortForDevice(const std::string &deviceId,
                                 libretro::InputSourceType sourceType,
                                 int &outPort) {
  return libretro::LibretroEngine::GetInstance()->ResolvePortForDevice(
      deviceId, sourceType, outPort);
}

static bool MapKeyCodeToJoypad(OH_NativeXComponent_KeyCode code, int &outId) {
  switch (code) {
  case KEY_DPAD_UP:
    outId = RETRO_DEVICE_ID_JOYPAD_UP;
    return true;
  case KEY_DPAD_DOWN:
    outId = RETRO_DEVICE_ID_JOYPAD_DOWN;
    return true;
  case KEY_DPAD_LEFT:
    outId = RETRO_DEVICE_ID_JOYPAD_LEFT;
    return true;
  case KEY_DPAD_RIGHT:
    outId = RETRO_DEVICE_ID_JOYPAD_RIGHT;
    return true;
  case KEY_ENTER:
    outId = RETRO_DEVICE_ID_JOYPAD_START;
    return true;
  case KEY_SPACE:
    outId = RETRO_DEVICE_ID_JOYPAD_SELECT;
    return true;
  case KEY_ESCAPE:
    outId = RETRO_DEVICE_ID_JOYPAD_B;
    return true;
  case KEY_Z:
    outId = RETRO_DEVICE_ID_JOYPAD_B;
    return true;
  case KEY_X:
    outId = RETRO_DEVICE_ID_JOYPAD_A;
    return true;
  case KEY_A:
    outId = RETRO_DEVICE_ID_JOYPAD_Y;
    return true;
  case KEY_S:
    outId = RETRO_DEVICE_ID_JOYPAD_X;
    return true;
  default:
    break;
  }
  return false;
}

static unsigned MapKeyCodeToRetroKey(OH_NativeXComponent_KeyCode code) {
  switch (code) {
  case KEY_DPAD_UP:
    return RETROK_UP;
  case KEY_DPAD_DOWN:
    return RETROK_DOWN;
  case KEY_DPAD_LEFT:
    return RETROK_LEFT;
  case KEY_DPAD_RIGHT:
    return RETROK_RIGHT;
  case KEY_ENTER:
    return RETROK_RETURN;
  case KEY_SPACE:
    return RETROK_SPACE;
  case KEY_ESCAPE:
    return RETROK_ESCAPE;
  case KEY_Z:
    return RETROK_z;
  case KEY_X:
    return RETROK_x;
  case KEY_A:
    return RETROK_a;
  case KEY_S:
    return RETROK_s;
  default:
    break;
  }

  // Best-effort fallback for printable ASCII-like keycodes.
  const unsigned rawCode = static_cast<unsigned>(code);
  if (rawCode >= RETROK_SPACE && rawCode <= RETROK_DELETE) {
    return rawCode;
  }
  return RETROK_UNKNOWN;
}

static uint32_t BuildRetroCharacter(unsigned retroKeycode, bool down) {
  if (!down) {
    return 0;
  }
  if (retroKeycode >= RETROK_SPACE && retroKeycode <= RETROK_DELETE) {
    return static_cast<uint32_t>(retroKeycode);
  }
  return 0;
}

static bool HandleNewArchKeyEvent(OH_NativeXComponent *component) {
  if (!component) {
    return false;
  }

  OH_NativeXComponent_KeyEvent *keyEvent = nullptr;
  if (OH_NativeXComponent_GetKeyEvent(component, &keyEvent) !=
          OH_NATIVEXCOMPONENT_RESULT_SUCCESS ||
      !keyEvent) {
    return false;
  }

  OH_NativeXComponent_KeyAction action = OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
  if (OH_NativeXComponent_GetKeyEventAction(keyEvent, &action) !=
      OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    return false;
  }
  LastKeyAction().store(static_cast<int>(action));

  OH_NativeXComponent_KeyCode code = KEY_UNKNOWN;
  if (OH_NativeXComponent_GetKeyEventCode(keyEvent, &code) !=
      OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    return false;
  }

  const bool isDown = (action == OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN);
  const bool isUp = (action == OH_NATIVEXCOMPONENT_KEY_ACTION_UP);
  if (!isDown && !isUp) {
    return false;
  }

  const unsigned retroKeycode = MapKeyCodeToRetroKey(code);
  const uint32_t character = BuildRetroCharacter(retroKeycode, isDown);
  bool keyboardDispatched = false;
  if (retroKeycode != RETROK_UNKNOWN || character != 0) {
    keyboardDispatched = libretro::LibretroEngine::GetInstance()
                             ->DispatchKeyboardEvent(isDown, retroKeycode,
                                                     character, 0);
  }

  int joypadId = -1;
  const bool mapToJoypad = MapKeyCodeToJoypad(code, joypadId);

  const std::string xId = GetNewArchXComponentId(component);
  const uint64_t count = ++KeyEventCount();
  if (count <= 3 || (count % 60) == 0) {
    LOGF(LOG_INFO,
         " [NEW_ARCH] KeyEvent: %{public}s action=%{public}d code=%{public}d",
         xId.c_str(), static_cast<int>(action), static_cast<int>(code));
  }

  std::string deviceId = BuildKeyDeviceId(keyEvent);
  if (deviceId.empty()) {
    deviceId = "key:unknown";
  }
  libretro::LibretroEngine::GetInstance()->RecordInputDevice(
      deviceId, libretro::InputSourceType::Keyboard,
      std::string("Keyboard ") + deviceId);

  bool joypadDispatched = false;
  if (mapToJoypad) {
    int port = 0;
    if (!ResolvePortForDevice(deviceId, libretro::InputSourceType::Keyboard,
                              port)) {
      return keyboardDispatched;
    }

    libretro::LibretroEngine::GetInstance()->SendInput(port, joypadId, isDown);
    joypadDispatched = true;
  }

  return keyboardDispatched || joypadDispatched;
}

} // namespace

PluginManager *PluginManager::GetInstance() {
  static PluginManager pluginManager;
  return &pluginManager;
}

PluginManager::~PluginManager() {
  LOGF(LOG_INFO, "~PluginManager");
  nativeXComponentMap_.clear();
  ClearAllNewArchPointerStates();
}

void PluginManager::Export(napi_env env, napi_value exports) {
  if ((env == nullptr) || (exports == nullptr)) {
    LOGF(LOG_ERROR, "Export: env or exports is null");
    return;
  }

  napi_value exportInstance = nullptr;
  if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ,
                              &exportInstance) != napi_ok) {
    LOGF(LOG_ERROR, "Export: napi_get_named_property fail");
    return;
  }

  napi_valuetype exportType = napi_undefined;
  if (napi_typeof(env, exportInstance, &exportType) != napi_ok) {
    LOGF(LOG_WARN, "Export: napi_typeof fail");
    return;
  }

  if (exportType != napi_object) {
    return;
  }

  OH_NativeXComponent *nativeXComponent = nullptr;
  napi_status unwrapStatus = napi_unwrap(
      env, exportInstance, reinterpret_cast<void **>(&nativeXComponent));
  if (unwrapStatus != napi_ok || nativeXComponent == nullptr) {
    static size_t unwrapFailCount = 0;
    unwrapFailCount++;
    if (unwrapFailCount <= 3 || (unwrapFailCount % 100) == 0) {
      LOGF(LOG_WARN, "Export: napi_unwrap fail: %{public}d",
           static_cast<int>(unwrapStatus));
    }
    return;
  }

  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  if (OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize) !=
      OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
    LOGF(LOG_ERROR, "Export: OH_NativeXComponent_GetXComponentId fail");
    return;
  }
  std::string id(idStr);
  auto context = PluginManager::GetInstance();
  if ((context != nullptr) && (nativeXComponent != nullptr)) {
    context->SetNativeXComponent(id, nativeXComponent);

    if (id.find("phase1") != std::string::npos ||
        id.find("new_arch") != std::string::npos) {
      // 新架构引擎渲染 (LibretroEngine)
      LOGF(LOG_INFO, " [NEW_ARCH] Detected New Arch XComponent: %{public}s",
           id.c_str());

      static OH_NativeXComponent_Callback callback;
      callback.OnSurfaceCreated = [](OH_NativeXComponent *component,
                                     void *window) {
        if (!component || !window) {
          return;
        }
        const std::string xId = GetNewArchXComponentId(component);
        LOGF(LOG_INFO,
             " [NEW_ARCH] Surface Created: %{public}s window=%{public}p",
             xId.c_str(), window);
        libretro::LibretroEngine::GetInstance()->SetNativeWindow(
            xId, (OHNativeWindow *)window);

        uint64_t width = 0;
        uint64_t height = 0;
        if (OH_NativeXComponent_GetXComponentSize(component, window, &width,
                                                  &height) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
          libretro::LibretroEngine::GetInstance()->OnNativeWindowResized(
              xId, static_cast<int>(width), static_cast<int>(height));
        }
      };
      callback.OnSurfaceChanged = [](OH_NativeXComponent *component,
                                     void *window) {
        if (!component || !window) {
          return;
        }
        const std::string xId = GetNewArchXComponentId(component);
        uint64_t width = 0, height = 0;
        (void)OH_NativeXComponent_GetXComponentSize(component, window, &width,
                                                    &height);
        LOGF(LOG_INFO,
             " [NEW_ARCH] Surface Changed: %{public}s %{public}lux%{public}lu",
             xId.c_str(), width, height);
        auto *engine = libretro::LibretroEngine::GetInstance();
        // SurfaceChanged 可能在 window 指针不变时发生，显式触发 generation 切换。
        engine->SetNativeWindow(xId, (OHNativeWindow *)window, true);
        engine->OnNativeWindowResized(xId, static_cast<int>(width),
                                      static_cast<int>(height));
      };
      callback.OnSurfaceDestroyed = [](OH_NativeXComponent *component,
                                       void *window) {
        const std::string xId = GetNewArchXComponentId(component);
        OHNativeWindow *destroyed = static_cast<OHNativeWindow *>(window);
        LOGF(LOG_INFO,
             " [NEW_ARCH] Surface Destroyed: %{public}s window=%{public}p",
             xId.c_str(), destroyed);
        libretro::LibretroEngine::GetInstance()->ClearNativeWindowIfMatch(
            xId, destroyed);
        ClearNewArchPointerState(xId);
      };
      callback.DispatchTouchEvent = [](OH_NativeXComponent *component,
                                       void *window) {
        if (!component || !window) {
          return;
        }
        OH_NativeXComponent_TouchEvent touchEvent;
        if (OH_NativeXComponent_GetTouchEvent(component, window, &touchEvent) ==
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
          const std::string xId = GetNewArchXComponentId(component);
          LastTouchType().store(static_cast<int>(touchEvent.type));
          const uint64_t count = ++TouchEventCount();
          if (count <= 3 || (count % 60) == 0) {
            LOGF(LOG_INFO,
                 " [NEW_ARCH] TouchEvent: %{public}s type=%{public}d "
                 "points=%{public}u",
                 xId.c_str(), static_cast<int>(touchEvent.type),
                 static_cast<unsigned>(touchEvent.numPoints));
          }
          uint64_t width = 0, height = 0;
          if (OH_NativeXComponent_GetXComponentSize(component, window, &width,
                                                    &height) !=
                  OH_NATIVEXCOMPONENT_RESULT_SUCCESS ||
              width == 0 || height == 0) {
            return;
          }

          // 只处理单点触控，模拟 Pointer 设备 (光枪/触摸屏)
          if (touchEvent.numPoints > 0) {
            OH_NativeXComponent_TouchPoint &point = touchEvent.touchPoints[0];
            const std::string pointerDeviceId = BuildMouseDeviceId();
            int port = 0;
            if (!ResolvePortForDevice(pointerDeviceId,
                                      libretro::InputSourceType::Mouse, port)) {
              port = 0;
            }

            // 坐标归一化映射到 [-0x8000, 0x7fff]
            // X: 0..width -> -0x8000..0x7fff
            // Y: 0..height -> -0x8000..0x7fff

            float normX =
                (point.x / static_cast<float>(width)) * 65535.0f - 32768.0f;
            float normY =
                (point.y / static_cast<float>(height)) * 65535.0f - 32768.0f;

            // 边界钳制
            if (normX < -32768.0f)
              normX = -32768.0f;
            if (normX > 32767.0f)
              normX = 32767.0f;
            if (normY < -32768.0f)
              normY = -32768.0f;
            if (normY > 32767.0f)
              normY = 32767.0f;

            bool pressed = (touchEvent.type == OH_NATIVEXCOMPONENT_DOWN ||
                            touchEvent.type == OH_NATIVEXCOMPONENT_MOVE);

            libretro::LibretroEngine::GetInstance()->SendPointer(
                port, static_cast<int16_t>(normX), static_cast<int16_t>(normY),
                pressed);
          }
        }
      };
      OH_NativeXComponent_RegisterCallback(nativeXComponent, &callback);
      LOGF(LOG_INFO, " [NEW_ARCH] XComponent callbacks registered");

      static OH_NativeXComponent_MouseEvent_Callback mouseCallback;
      mouseCallback.DispatchMouseEvent = [](OH_NativeXComponent *component,
                                            void *window) {
        if (!component || !window) {
          return;
        }

        OH_NativeXComponent_MouseEvent mouseEvent;
        if (OH_NativeXComponent_GetMouseEvent(component, window, &mouseEvent) !=
            OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
          return;
        }

        const std::string xId = GetNewArchXComponentId(component);
        LastMouseAction().store(static_cast<int>(mouseEvent.action));
        const uint64_t count = ++MouseEventCount();
        if (count <= 3 || (count % 60) == 0) {
          LOGF(LOG_INFO,
               " [NEW_ARCH] MouseEvent: %{public}s action=%{public}d "
               "button=%{public}u",
               xId.c_str(), static_cast<int>(mouseEvent.action),
               static_cast<unsigned>(mouseEvent.button));
        }

        const std::string deviceId = BuildMouseDeviceId();
        libretro::LibretroEngine::GetInstance()->RecordInputDevice(
            deviceId, libretro::InputSourceType::Mouse, "Mouse");
        int port = 0;
        if (!ResolvePortForDevice(deviceId, libretro::InputSourceType::Mouse,
                                  port)) {
          return;
        }

        if (mouseEvent.action == OH_NATIVEXCOMPONENT_MOUSE_PRESS &&
            (mouseEvent.button & OH_NATIVEXCOMPONENT_LEFT_BUTTON)) {
          SetNewArchMouseDown(xId, true);
        } else if (mouseEvent.action == OH_NATIVEXCOMPONENT_MOUSE_RELEASE &&
                   (mouseEvent.button & OH_NATIVEXCOMPONENT_LEFT_BUTTON)) {
          SetNewArchMouseDown(xId, false);
        } else if (mouseEvent.action == OH_NATIVEXCOMPONENT_MOUSE_CANCEL) {
          SetNewArchMouseDown(xId, false);
        }

        const bool pressed = GetNewArchMouseDown(xId);
        (void)NormalizeAndSendPointer(component, window, port, mouseEvent.x,
                                      mouseEvent.y, pressed);
      };
      mouseCallback.DispatchHoverEvent = [](OH_NativeXComponent *component,
                                            bool isHover) {
        const std::string xId = GetNewArchXComponentId(component);
        if (!isHover) {
          SetNewArchMouseDown(xId, false);
        }
      };

      int32_t mouseRet = OH_NativeXComponent_RegisterMouseEventCallback(
          nativeXComponent, &mouseCallback);
      if (mouseRet != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGF(LOG_WARN,
             " [NEW_ARCH] RegisterMouseEventCallback failed: %{public}d",
             mouseRet);
      }

      int32_t focusRet = OH_NativeXComponent_RegisterFocusEventCallback(
          nativeXComponent, [](OH_NativeXComponent *component, void *window) {
            (void)window;
            const std::string xId = GetNewArchXComponentId(component);
            SetNewArchHasFocus(xId, true);
          });
      if (focusRet != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGF(LOG_WARN,
             " [NEW_ARCH] RegisterFocusEventCallback failed: %{public}d",
             focusRet);
      }

      int32_t blurRet = OH_NativeXComponent_RegisterBlurEventCallback(
          nativeXComponent, [](OH_NativeXComponent *component, void *window) {
            (void)window;
            const std::string xId = GetNewArchXComponentId(component);
            SetNewArchHasFocus(xId, false);
            SetNewArchMouseDown(xId, false);
            const std::string deviceId = BuildMouseDeviceId();
            int port = 0;
            if (ResolvePortForDevice(deviceId, libretro::InputSourceType::Mouse,
                                     port)) {
              libretro::LibretroEngine::GetInstance()->SendPointer(port, 0, 0,
                                                                   false);
              return;
            }
            // 未解析到端口时兜底清理常见端口，避免残留 pressed 状态。
            for (int fallbackPort = 0; fallbackPort < 4; ++fallbackPort) {
              libretro::LibretroEngine::GetInstance()->SendPointer(
                  fallbackPort, 0, 0, false);
            }
          });
      if (blurRet != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGF(LOG_WARN,
             " [NEW_ARCH] RegisterBlurEventCallback failed: %{public}d",
             blurRet);
      }

      int32_t keyRet = OH_NativeXComponent_RegisterKeyEventCallbackWithResult(
          nativeXComponent,
          [](OH_NativeXComponent *component, void *window) -> bool {
            (void)window;
            return HandleNewArchKeyEvent(component);
          });
      if (keyRet != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGF(
            LOG_WARN,
            " [NEW_ARCH] RegisterKeyEventCallbackWithResult failed: %{public}d",
            keyRet);
        int32_t keyRet2 = OH_NativeXComponent_RegisterKeyEventCallback(
            nativeXComponent, [](OH_NativeXComponent *component, void *window) {
              (void)window;
              (void)HandleNewArchKeyEvent(component);
            });
        if (keyRet2 != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
          LOGF(LOG_WARN,
               " [NEW_ARCH] RegisterKeyEventCallback failed: %{public}d",
               keyRet2);
        }
      }
    } else {
      LOGF(LOG_INFO, "Legacy XComponent path removed, ignoring: %{public}s",
           id.c_str());
    }
  }
}

void PluginManager::SetNativeXComponent(std::string &id,
                                        OH_NativeXComponent *nativeXComponent) {
  LOGF(LOG_INFO, "set native xComponent, ID = %{public}s.", id.c_str());
  if (nativeXComponent == nullptr) {
    LOGF(LOG_ERROR, "xcomponent null");
    return;
  }

  if (nativeXComponentMap_.find(id) == nativeXComponentMap_.end()) {
    nativeXComponentMap_[id] = nativeXComponent;
    return;
  }

  if (nativeXComponentMap_[id] != nativeXComponent) {
    nativeXComponentMap_[id] = nativeXComponent;
  }
}

bool PluginManager::GetNewArchInputStats(NewArchInputStats &out) const {
  out.touchCount = TouchEventCount().load();
  out.mouseCount = MouseEventCount().load();
  out.keyCount = KeyEventCount().load();
  out.hasFocus = AnyNewArchHasFocus();
  out.mouseDown = AnyNewArchMouseDown();
  out.lastTouchType = LastTouchType().load();
  out.lastMouseAction = LastMouseAction().load();
  out.lastKeyAction = LastKeyAction().load();
  return true;
}
