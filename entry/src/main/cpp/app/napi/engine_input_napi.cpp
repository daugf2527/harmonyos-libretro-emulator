#include "engine_napi_common.h"
#include "core/engine/input_manager.h"
#include "interfaces/input/i_input_manager.h"

using libretro::InputManager;

namespace {

void SetInputError(const char *reason, const char *step, const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

void EnsureInputErrorIfEmpty(const char *reason, const char *step,
                             const char *message) {
  auto *engine = GetEngine();
  if (!engine) {
    return;
  }
  auto err = engine->GetLastErrorInfo();
  if (!err.reason.empty()) {
    return;
  }
  engine->SetLastErrorInfo(reason, step, message);
}

} // namespace

static InputManager *GetInput() { return InputManager::GetInstance(); }

static napi_value SendInput(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "SendInput")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t id = 0;
  bool pressed = false;

  if (!GetInt32Arg(env, args[0], port, "SendInput", "port") ||
      !GetInt32Arg(env, args[1], id, "SendInput", "id") ||
      !GetBoolArg(env, args[2], pressed, "SendInput", "pressed")) {
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "SendInput",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  if (!input->CanSendVirtual(port)) {
    SetInputError("virtual_input_unavailable", "SendInput",
                  "Virtual input is not assigned to the requested port");
    return MakeBool(env, false);
  }
  const bool ok = input->SendInput(port, id, pressed);
  if (!ok) {
    SetInputError("input_button_invalid", "SendInput",
                  "Button input parameters are outside supported range");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SendAnalog(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[4];
  if (!GetArgs(env, info, 4, 4, args, &argc, "SendAnalog")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t index = 0;
  int32_t id = 0;
  double value = 0.0;

  if (!GetInt32Arg(env, args[0], port, "SendAnalog", "port") ||
      !GetInt32Arg(env, args[1], index, "SendAnalog", "index") ||
      !GetInt32Arg(env, args[2], id, "SendAnalog", "id") ||
      !GetDoubleArg(env, args[3], value, "SendAnalog", "value")) {
    return MakeBool(env, false);
  }

  if (value > 32767.0) {
    value = 32767.0;
  } else if (value < -32768.0) {
    value = -32768.0;
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "SendAnalog",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  if (!input->CanSendVirtual(port)) {
    SetInputError("virtual_input_unavailable", "SendAnalog",
                  "Virtual input is not assigned to the requested port");
    return MakeBool(env, false);
  }
  const bool ok =
      input->SendAnalog(port, index, id, static_cast<int>(value));
  if (!ok) {
    SetInputError("analog_input_invalid", "SendAnalog",
                  "Analog input parameters are outside supported range");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value AssignPortSource(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 2, 3, args, &argc, "AssignPortSource")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t sourceType = 0;
  if (!GetInt32Arg(env, args[0], port, "AssignPortSource", "port") ||
      !GetInt32Arg(env, args[1], sourceType, "AssignPortSource",
                   "sourceType")) {
    return MakeBool(env, false);
  }

  std::string deviceId;
  if (argc >= 3) {
    char idBuf[256] = {0};
    if (!GetStringArgAllowEmpty(env, args[2], idBuf, sizeof(idBuf),
                                "AssignPortSource", "deviceId")) {
      return MakeBool(env, false);
    }
    deviceId = idBuf;
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "AssignPortSource",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  const bool ok = input->AssignPortSource(port, sourceType, deviceId);
  if (!ok) {
    SetInputError("assign_port_source_failed", "AssignPortSource",
                  "Port source assignment failed for the requested route");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value UnassignPort(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[1];
  if (!GetArgs(env, info, 1, 1, args, &argc, "UnassignPort")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  if (!GetInt32Arg(env, args[0], port, "UnassignPort", "port")) {
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "UnassignPort",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  const bool ok = input->UnassignPort(port);
  if (!ok) {
    SetInputError("unassign_port_failed", "UnassignPort",
                  "Port unassignment failed for the requested route");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value ListInputDevices(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *input = GetInput();
  std::vector<interfaces::InputDeviceInfo> devices;
  if (input) {
    devices = input->ListInputDevices();
  }
  napi_value array = nullptr;
  // Audit B-F2: all napi_create_* calls checked; OOM returns nullptr (bubbles JS exception)
  if (napi_create_array_with_length(env, devices.size(), &array) != napi_ok) {
    return nullptr;
  }

  for (size_t i = 0; i < devices.size(); ++i) {
    napi_value obj = nullptr;
    if (napi_create_object(env, &obj) != napi_ok) { return nullptr; }

    if (!SetNamedPropertyChecked(env, obj, "deviceId",
                                 MakeString(env, devices[i].deviceId)) ||
        !SetNamedPropertyChecked(
            env, obj, "sourceType",
            MakeInt32(env, static_cast<int32_t>(devices[i].sourceType))) ||
        !SetNamedPropertyChecked(env, obj, "name",
                                 MakeString(env, devices[i].name)) ||
        !SetElementChecked(env, array, static_cast<uint32_t>(i), obj)) {
      return nullptr;
    }
  }

  return array;
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SendSensor(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[3];
  if (!GetArgs(env, info, 3, 3, args, &argc, "SendSensor")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t id = 0;
  double value = 0.0;

  if (!GetInt32Arg(env, args[0], port, "SendSensor", "port") ||
      !GetInt32Arg(env, args[1], id, "SendSensor", "id") ||
      !GetDoubleArg(env, args[2], value, "SendSensor", "value")) {
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "SendSensor",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  const bool ok = input->SendSensor(port, id, static_cast<float>(value));
  if (!ok) {
    SetInputError("sensor_input_invalid", "SendSensor",
                  "Sensor input parameters are outside supported range");
  }

  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value SetControllerPortDevice(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetControllerPortDevice")) {
    return MakeBool(env, false);
  }

  int32_t port = 0;
  int32_t device = 0;
  if (!GetInt32Arg(env, args[0], port, "SetControllerPortDevice", "port") ||
      !GetInt32Arg(env, args[1], device, "SetControllerPortDevice", "device")) {
    return MakeBool(env, false);
  }
  if (port < 0 || device < 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetControllerPortDevice invalid: port=%{public}d device=%{public}d",
         port, device);
    SetInputError("controller_port_device_invalid", "SetControllerPortDevice",
                  "Controller port and device must be non-negative");
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "SetControllerPortDevice",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  const bool ok = input->SetControllerPortDevice(port, device);
  if (!ok) {
    EnsureInputErrorIfEmpty("controller_port_device_unavailable",
                            "SetControllerPortDevice",
                            "Controller port device callback is unavailable");
  }
  return MakeBool(env, ok);
  NAPI_TRY_CATCH_END(env, nullptr)
}

static napi_value GetInputDescriptorMask(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  auto *engine = GetEngine();
  uint16_t mask = engine ? engine->GetInputDescriptorMask() : 0;
  return MakeUint32(env, static_cast<uint32_t>(mask));
  NAPI_TRY_CATCH_END(env, nullptr)
}

void RegisterInputNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"refactoredSendInput", nullptr, SendInput, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSendAnalog", nullptr, SendAnalog, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredAssignPortSource", nullptr, AssignPortSource, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredUnassignPort", nullptr, UnassignPort, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredListInputDevices", nullptr, ListInputDevices, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSendSensor", nullptr, SendSensor, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredSetControllerPortDevice", nullptr, SetControllerPortDevice, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetInputDescriptorMask", nullptr, GetInputDescriptorMask, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {  // Audit B-F3: log only; throwing here has undefined behavior in module init
    LOGF(LOG_ERROR, "RegisterInputNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
