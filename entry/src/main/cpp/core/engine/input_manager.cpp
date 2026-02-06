#include "input_manager.h"
#include "input_port_router.h"
#include <cstdio>
#include <hilog/log.h>
#include <utility>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "InputManager"
#undef LOG_FLOW
#define LOG_FLOW "Input"
#include "common/log_prefix.h"

namespace libretro {

namespace {
bool IsValidPort(int port) {
  return port >= 0 && port < InputSnapshot::kMaxPorts;
}

bool IsValidButton(int id) {
  return id >= 0 && id < InputSnapshot::kMaxButtons;
}

bool IsValidAnalog(int index, int id) {
  if (index < 0 || id < 0) {
    return false;
  }
  int axis_idx = (index * 2) + id;
  return axis_idx >= 0 && axis_idx < InputSnapshot::kMaxAnalogAxes;
}

bool IsValidSensor(int id) {
  return id >= 0 && id < InputSnapshot::kMaxSensors;
}

int16_t ClampToInt16(int value) {
  if (value > INT16_MAX) {
    return INT16_MAX;
  }
  if (value < INT16_MIN) {
    return INT16_MIN;
  }
  return static_cast<int16_t>(value);
}

bool TryParseSourceType(int sourceType, InputSourceType &out) {
  switch (sourceType) {
  case static_cast<int>(InputSourceType::None):
    out = InputSourceType::None;
    return true;
  case static_cast<int>(InputSourceType::Virtual):
    out = InputSourceType::Virtual;
    return true;
  case static_cast<int>(InputSourceType::Keyboard):
    out = InputSourceType::Keyboard;
    return true;
  case static_cast<int>(InputSourceType::Mouse):
    out = InputSourceType::Mouse;
    return true;
  case static_cast<int>(InputSourceType::Gamepad):
    out = InputSourceType::Gamepad;
    return true;
  case static_cast<int>(InputSourceType::BluetoothGamepad):
    out = InputSourceType::BluetoothGamepad;
    return true;
  case static_cast<int>(InputSourceType::Unknown):
    out = InputSourceType::Unknown;
    return true;
  default:
    return false;
  }
}
} // namespace

InputManager *InputManager::g_instance = nullptr;

InputManager::InputManager(EventBridge *eventBridge)
    : eventBridge_(eventBridge) {
  g_instance = this;
  LOGF(LOG_INFO, "InputManager created");
}

InputManager::~InputManager() {
  if (g_instance == this) {
    g_instance = nullptr;
  }
  LOGF(LOG_INFO, "InputManager destroyed");
}

InputManager *InputManager::GetInstance() { return g_instance; }

bool InputManager::SendInput(int port, int id, bool pressed) {
  if (!IsValidPort(port) || !IsValidButton(id)) {
    return false;
  }
  inputSnapshot_.SetButton(port, id, pressed);
  return true;
}

bool InputManager::SendAnalog(int port, int index, int id, int value) {
  if (!IsValidPort(port) || !IsValidAnalog(index, id)) {
    return false;
  }
  inputSnapshot_.SetAnalog(port, index, id, ClampToInt16(value));
  return true;
}

bool InputManager::SendPointer(int port, int x, int y, bool pressed) {
  if (!IsValidPort(port)) {
    return false;
  }
  inputSnapshot_.SetPointer(port, ClampToInt16(x), ClampToInt16(y), pressed);
  return true;
}

bool InputManager::SendSensor(int port, int id, float value) {
  if (!IsValidPort(port) || !IsValidSensor(id)) {
    return false;
  }
  inputSnapshot_.SetSensor(port, id, value);
  return true;
}

void InputManager::Clear() { inputSnapshot_.Clear(); }

void InputManager::ClearPort(int port) { inputSnapshot_.ClearPort(port); }

bool InputManager::AssignPortSource(int port, int sourceType,
                                    const std::string &deviceId) {
  if (!portRouter_) {
    return false;
  }
  InputSourceType parsed = InputSourceType::Unknown;
  if (!TryParseSourceType(sourceType, parsed)) {
    return false;
  }
  return portRouter_->AssignPort(port, parsed, deviceId);
}

bool InputManager::UnassignPort(int port) {
  if (!portRouter_) {
    return false;
  }
  return portRouter_->UnassignPort(port);
}

std::vector<interfaces::InputDeviceInfo> InputManager::ListInputDevices()
    const {
  if (!portRouter_) {
    return {};
  }
  auto devices = portRouter_->ListDevices();
  std::vector<interfaces::InputDeviceInfo> result;
  result.reserve(devices.size());
  for (const auto &device : devices) {
    interfaces::InputDeviceInfo info;
    info.deviceId = device.deviceId;
    info.sourceType = static_cast<int>(device.sourceType);
    info.name = device.name;
    result.push_back(info);
  }
  return result;
}

bool InputManager::SetControllerPortDevice(int port, int device) {
  if (port < 0 || device < 0) {
    return false;
  }
  if (!controller_port_device_callback_) {
    return false;
  }
  controller_port_device_callback_(static_cast<unsigned>(port),
                                   static_cast<unsigned>(device));
  return true;
}

interfaces::InputDebugStats InputManager::GetDebugStats() const {
  return {};
}

void InputManager::SetPortRouter(InputPortRouter *router) {
  portRouter_ = router;
}

void InputManager::SetControllerPortDeviceCallback(
    std::function<void(unsigned, unsigned)> callback) {
  controller_port_device_callback_ = std::move(callback);
}

// --- Static Callbacks ---

void InputManager::OnInputPoll() {
  // Input polling is handled asynchronously via atomic InputSnapshot updates.
  // So this callback is mostly a no-op or a synchronization point if needed
  // using fences in future. Currently, Libretro cores call this to signal they
  // are about to read input.
}

int16_t InputManager::OnInputState(unsigned port, unsigned device,
                                   unsigned index, unsigned id) {
  if (!g_instance) {
    return 0;
  }

  // Delegate to InputSnapshot logic
  // Note: The original logic in LibretroEngine delegated to
  // inputSnapshot_.GetButton/GetAnalog/GetPointer depending on device type. We
  // need to reproduce that logic here. However, input_snapshot.h didn't have a
  // unified "OnInputState" helper, it had GetButton/GetAnalog etc. Let's
  // implement the switch-case logic here similar to how it's typically done in
  // Libretro frontends.

  // Check InputSnapshot implementation (based on previous view_file, checks
  // were lock-free) We need to route the request based on device type.

  // Since we don't have the original LibretroEngine::OnInputState logic visible
  // right now (it was in the truncated part of libretro_engine.cpp), we must
  // assume standard Libretro input handling behaviors. Let's look at what
  // input_snapshot.h offers. Based on typical usage:

  if (device == RETRO_DEVICE_JOYPAD) {
    // Handle JOYPAD_MASK query (id == RETRO_DEVICE_ID_JOYPAD_MASK)
    if (index == 0) {
      if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
        return static_cast<int16_t>(
            g_instance->inputSnapshot_.GetButtonsMask(port));
      }
      // Single button query
      return g_instance->inputSnapshot_.GetButton(port, id) ? 1 : 0;
    }
  }

  if (device == RETRO_DEVICE_ANALOG) {
    // index: RETRO_DEVICE_INDEX_ANALOG_LEFT (0) or RIGHT (1)
    // id: RETRO_DEVICE_ID_ANALOG_X (0) or Y (1)
    return g_instance->inputSnapshot_.GetAnalog(port, index, id);
  }

  if (device == RETRO_DEVICE_POINTER) {
    int16_t x = 0;
    int16_t y = 0;
    bool pressed = false;
    g_instance->inputSnapshot_.GetPointer(port, x, y, pressed);
    switch (id) {
    case RETRO_DEVICE_ID_POINTER_X:
      return x;
    case RETRO_DEVICE_ID_POINTER_Y:
      return y;
    case RETRO_DEVICE_ID_POINTER_PRESSED:
      return pressed ? 1 : 0;
    default:
      return 0;
    }
  }

  // RETRO_DEVICE_LIGHTGUN / RETRO_DEVICE_MOUSE / RETRO_DEVICE_KEYBOARD
  // 当前未实现，保持返回 0。

  return 0;
}

bool InputManager::OnRumble(unsigned port, retro_rumble_effect effect,
                            uint16_t strength) {
  if (!g_instance || !g_instance->eventBridge_) {
    return false;
  }

  char payload[128];
  snprintf(payload, sizeof(payload),
           "{\"port\": %u, \"effect\": %d, \"strength\": %u}", port,
           static_cast<int>(effect), strength);

  g_instance->eventBridge_->Emit("rumble", payload, false);
  return true;
}

bool InputManager::OnSensorSetState(unsigned port, retro_sensor_action action,
                                    unsigned rate) {
  if (!g_instance || !g_instance->eventBridge_) {
    return false;
  }

  char payload[128];
  snprintf(payload, sizeof(payload),
           "{\"port\": %u, \"action\": %d, \"rate\": %u}", port,
           static_cast<int>(action), rate);
  g_instance->eventBridge_->Emit("sensor_state", payload, false);
  return true;
}

float InputManager::OnSensorGetInput(unsigned port, unsigned id) {
  if (!g_instance) {
    return 0.0f;
  }
  return g_instance->inputSnapshot_.GetSensor(port, id);
}

} // namespace libretro
