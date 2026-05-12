#include "engine_napi_common.h"
#include "core/engine/input_manager.h"
#include "interfaces/input/i_input_manager.h"

using libretro::InputManager;

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
  if (!input || !input->CanSendVirtual(port)) {
    return MakeBool(env, false);
  }
  const bool ok = input->SendInput(port, id, pressed);

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
  if (!input || !input->CanSendVirtual(port)) {
    return MakeBool(env, false);
  }
  const bool ok =
      input->SendAnalog(port, index, id, static_cast<int>(value));

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
    return MakeBool(env, false);
  }
  const bool ok = input->AssignPortSource(port, sourceType, deviceId);
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
    return MakeBool(env, false);
  }
  const bool ok = input->UnassignPort(port);
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
  napi_create_array_with_length(env, devices.size(), &array);

  for (size_t i = 0; i < devices.size(); ++i) {
    napi_value obj = nullptr;
    napi_create_object(env, &obj);

    napi_value val = nullptr;
    napi_create_string_utf8(env, devices[i].deviceId.c_str(),
                            NAPI_AUTO_LENGTH, &val);
    napi_set_named_property(env, obj, "deviceId", val);

    napi_create_int32(env, static_cast<int32_t>(devices[i].sourceType), &val);
    napi_set_named_property(env, obj, "sourceType", val);

    napi_create_string_utf8(env, devices[i].name.c_str(), NAPI_AUTO_LENGTH,
                            &val);
    napi_set_named_property(env, obj, "name", val);

    napi_set_element(env, array, i, obj);
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
    return MakeBool(env, false);
  }
  const bool ok = input->SendSensor(port, id, static_cast<float>(value));

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
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    return MakeBool(env, false);
  }
  const bool ok = input->SetControllerPortDevice(port, device);
  return MakeBool(env, ok);
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
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
