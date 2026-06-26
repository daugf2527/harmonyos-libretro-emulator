#include "input_manager.h"
#include "input_port_router.h"
#include <cstdio>
#include <hilog/log.h>
#include <utility>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD014
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

std::atomic<InputManager *> InputManager::g_instance{nullptr};

InputManager::InputManager(EventBridge *eventBridge)
    : eventBridge_(eventBridge) {
  g_instance.store(this, std::memory_order_release);
  LOGF(LOG_INFO, "InputManager created");
}

InputManager::~InputManager() {
  InputManager *expected = this;
  (void)g_instance.compare_exchange_strong(expected, nullptr,
                                           std::memory_order_acq_rel,
                                           std::memory_order_acquire);
  LOGF(LOG_INFO, "InputManager destroyed");
}

InputManager *InputManager::GetInstance() {
  return g_instance.load(std::memory_order_acquire);
}

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
  if (!IsValidPort(port) || device < 0) {
    return false;
  }
  if (!controller_port_device_callback_) {
    return false;
  }
  return controller_port_device_callback_(static_cast<unsigned>(port),
                                          static_cast<unsigned>(device));
}

interfaces::InputDebugStats InputManager::GetDebugStats() const {
  return {};
}

void InputManager::SetPortRouter(InputPortRouter *router) {
  portRouter_ = router;
}

void InputManager::SetControllerPortDeviceCallback(
    std::function<bool(unsigned, unsigned)> callback) {
  controller_port_device_callback_ = std::move(callback);
}

bool InputManager::CanSendVirtual(int port) const {
  if (!portRouter_) {
    return false;
  }
  return portRouter_->CanSendVirtual(port);
}

bool InputManager::ResolvePortForDevice(const std::string &deviceId,
                                        InputSourceType sourceType,
                                        int &outPort) {
  if (!portRouter_) {
    return false;
  }
  return portRouter_->ResolvePortForDevice(deviceId, sourceType, outPort);
}

void InputManager::RecordInputDevice(const std::string &deviceId,
                                     InputSourceType sourceType,
                                     const std::string &name) {
  if (!portRouter_) {
    return;
  }
  portRouter_->RecordDeviceSeen(deviceId, sourceType, name);
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
  InputManager *instance = g_instance.load(std::memory_order_acquire);
  if (!instance) {
    return 0;
  }

  // Route libretro input queries by device type and read from InputSnapshot.

  if (device == RETRO_DEVICE_JOYPAD) {
    // Handle JOYPAD_MASK query (id == RETRO_DEVICE_ID_JOYPAD_MASK)
    if (index == 0) {
      if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
        return static_cast<int16_t>(
            instance->inputSnapshot_.GetButtonsMask(port));
      }
      // Single button query
      return instance->inputSnapshot_.GetButton(port, id) ? 1 : 0;
    }
  }

  if (device == RETRO_DEVICE_ANALOG) {
    // index: RETRO_DEVICE_INDEX_ANALOG_LEFT (0) or RIGHT (1)
    // id: RETRO_DEVICE_ID_ANALOG_X (0) or Y (1)
    return instance->inputSnapshot_.GetAnalog(port, index, id);
  }

  if (device == RETRO_DEVICE_POINTER) {
    int16_t x = 0;
    int16_t y = 0;
    bool pressed = false;
    instance->inputSnapshot_.GetPointer(port, x, y, pressed);
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

  // RETRO_DEVICE_LIGHTGUN / RETRO_DEVICE_MOUSE / RETRO_DEVICE_KEYBOARD:
  // currently unimplemented, return 0.

  return 0;
}

bool InputManager::OnRumble(unsigned port, retro_rumble_effect effect,
                            uint16_t strength) {
  InputManager *instance = g_instance.load(std::memory_order_acquire);
  if (!instance || !instance->eventBridge_) {
    return false;
  }

  char payload[128];
  snprintf(payload, sizeof(payload),
           "{\"port\": %u, \"effect\": %d, \"strength\": %u}", port,
           static_cast<int>(effect), strength);

  instance->eventBridge_->Emit("rumble", payload, false);
  return true;
}

bool InputManager::OnSensorSetState(unsigned port, retro_sensor_action action,
                                    unsigned rate) {
  InputManager *instance = g_instance.load(std::memory_order_acquire);
  if (!instance || !instance->eventBridge_) {
    return false;
  }

  char payload[128];
  snprintf(payload, sizeof(payload),
           "{\"port\": %u, \"action\": %d, \"rate\": %u}", port,
           static_cast<int>(action), rate);
  instance->eventBridge_->Emit("sensor_state", payload, false);
  return true;
}

float InputManager::OnSensorGetInput(unsigned port, unsigned id) {
  InputManager *instance = g_instance.load(std::memory_order_acquire);
  if (!instance) {
    return 0.0f;
  }
  return instance->inputSnapshot_.GetSensor(port, id);
}

} // namespace libretro
