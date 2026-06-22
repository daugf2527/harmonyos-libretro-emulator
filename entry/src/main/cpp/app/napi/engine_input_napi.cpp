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

bool IsValidInputPort(int32_t port) {
  return port >= 0 && port < libretro::InputSnapshot::kMaxPorts;
}

bool IsValidInputButton(int32_t id) {
  return id >= 0 && id < libretro::InputSnapshot::kMaxButtons;
}

bool IsValidInputAnalog(int32_t index, int32_t id) {
  if (index < 0 || id < 0) {
    return false;
  }
  const int32_t axisIndex = (index * 2) + id;
  return axisIndex >= 0 &&
         axisIndex < libretro::InputSnapshot::kMaxAnalogAxes;
}

bool IsValidInputSensor(int32_t id) {
  return id >= 0 && id < libretro::InputSnapshot::kMaxSensors;
}

bool IsValidInputSourceType(int32_t sourceType) {
  switch (sourceType) {
  case 0:
  case 1:
  case 2:
  case 3:
  case 4:
  case 5:
  case 6:
    return true;
  default:
    return false;
  }
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
  if (!IsValidInputPort(port)) {
    SetInputError("input_port_invalid", "SendInput",
                  "Requested input port is outside supported range");
    return MakeBool(env, false);
  }
  if (!IsValidInputButton(id)) {
    SetInputError("input_button_invalid", "SendInput",
                  "Requested button id is outside supported range");
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
  if (!IsValidInputPort(port)) {
    SetInputError("analog_port_invalid", "SendAnalog",
                  "Requested analog input port is outside supported range");
    return MakeBool(env, false);
  }
  if (!IsValidInputAnalog(index, id)) {
    SetInputError("analog_axis_invalid", "SendAnalog",
                  "Requested analog index/id is outside supported range");
    return MakeBool(env, false);
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
  if (!IsValidInputPort(port)) {
    SetInputError("assign_port_invalid", "AssignPortSource",
                  "Requested input port is outside supported range");
    return MakeBool(env, false);
  }
  if (!IsValidInputSourceType(sourceType)) {
    SetInputError("assign_port_source_type_invalid", "AssignPortSource",
                  "Requested input source type is unsupported");
    return MakeBool(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "AssignPortSource",
                  "InputManager instance is unavailable");
    return MakeBool(env, false);
  }
  const bool ok = input->AssignPortSource(port, sourceType, deviceId);
  if (!ok) {
    EnsureInputErrorIfEmpty("assign_port_source_failed", "AssignPortSource",
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
  if (!IsValidInputPort(port)) {
    SetInputError("unassign_port_invalid", "UnassignPort",
                  "Requested input port is outside supported range");
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
    EnsureInputErrorIfEmpty("unassign_port_failed", "UnassignPort",
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
  if (!IsValidInputPort(port)) {
    SetInputError("sensor_port_invalid", "SendSensor",
                  "Requested sensor input port is outside supported range");
    return MakeBool(env, false);
  }
  if (!IsValidInputSensor(id)) {
    SetInputError("sensor_id_invalid", "SendSensor",
                  "Requested sensor id is outside supported range");
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
  if (!IsValidInputPort(port) || device < 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetControllerPortDevice invalid: port=%{public}d device=%{public}d",
         port, device);
    SetInputError("controller_port_device_invalid", "SetControllerPortDevice",
                  "Controller port or device is outside supported range");
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

struct SetControllerPortDeviceAsyncContext {
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  int32_t port = 0;
  int32_t device = 0;
  bool ok = false;
};

static void ExecuteSetControllerPortDeviceAsync(napi_env env, void *data) {
  auto *ctx = static_cast<SetControllerPortDeviceAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  auto *input = GetInput();
  if (!input) {
    return;
  }
  ctx->ok = input->SetControllerPortDevice(ctx->port, ctx->device);
}

static void CompleteSetControllerPortDeviceAsync(napi_env env, napi_status status,
                                                 void *data) {
  auto *ctx = static_cast<SetControllerPortDeviceAsyncContext *>(data);
  if (!ctx) {
    return;
  }

  if (status == napi_cancelled) {
    LOGF(LOG_WARN,
         "[NEW] SetControllerPortDeviceAsync cancelled (env teardown); skipping NAPI calls");
    if (ctx->work) {
      napi_delete_async_work(env, ctx->work);
      ctx->work = nullptr;
    }
    delete ctx;
    return;
  }

  if (status != napi_ok) {
    SetInputError("controller_port_device_async_work_failed",
                  "SetControllerPortDeviceAsync",
                  "Async controller-port-device completion callback status was not napi_ok");
    napi_value reason = MakeUndefined(env);
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
  } else {
    if (!ctx->ok) {
      EnsureInputErrorIfEmpty("controller_port_device_unavailable",
                              "SetControllerPortDeviceAsync",
                              "Controller port device callback is unavailable");
    }
    napi_value result = MakeBool(env, ctx->ok);
    if (result) {
      (void)ResolveDeferredChecked(env, ctx->deferred, result);
    }
  }

  if (ctx->work) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
  }
  delete ctx;
}

static napi_value SetControllerPortDeviceAsync(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  size_t argc = 0;
  napi_value args[2];
  if (!GetArgs(env, info, 2, 2, args, &argc, "SetControllerPortDeviceAsync")) {
    return MakeResolvedPromise(env, false);
  }

  int32_t port = 0;
  int32_t device = 0;
  if (!GetInt32Arg(env, args[0], port, "SetControllerPortDeviceAsync", "port") ||
      !GetInt32Arg(env, args[1], device, "SetControllerPortDeviceAsync", "device")) {
    return MakeResolvedPromise(env, false);
  }
  if (!IsValidInputPort(port) || device < 0) {
    LOGF(LOG_ERROR,
         "[NEW] SetControllerPortDeviceAsync invalid: port=%{public}d device=%{public}d",
         port, device);
    SetInputError("controller_port_device_invalid", "SetControllerPortDeviceAsync",
                  "Controller port or device is outside supported range");
    return MakeResolvedPromise(env, false);
  }

  auto *input = GetInput();
  if (!input) {
    SetInputError("input_manager_unavailable", "SetControllerPortDeviceAsync",
                  "InputManager instance is unavailable");
    return MakeResolvedPromise(env, false);
  }

  auto *ctx = new SetControllerPortDeviceAsyncContext();
  ctx->port = port;
  ctx->device = device;

  napi_value promise = nullptr;
  if (napi_create_promise(env, &ctx->deferred, &promise) != napi_ok) {
    delete ctx;
    return nullptr;
  }

  napi_value resourceName = MakeString(env, "SetControllerPortDeviceAsync");
  if (!resourceName) {
    SetInputError("controller_port_device_async_create_failed",
                  "SetControllerPortDeviceAsync",
                  "Failed to create async resource name");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status createStatus = napi_create_async_work(
      env, nullptr, resourceName, ExecuteSetControllerPortDeviceAsync,
      CompleteSetControllerPortDeviceAsync, ctx, &ctx->work);
  if (createStatus != napi_ok || !ctx->work) {
    SetInputError("controller_port_device_async_create_failed",
                  "SetControllerPortDeviceAsync",
                  "Failed to create async controller-port-device work item");
    napi_value reason = MakeString(env, "async_work_create_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  napi_status queueStatus = napi_queue_async_work(env, ctx->work);
  if (queueStatus != napi_ok) {
    napi_delete_async_work(env, ctx->work);
    ctx->work = nullptr;
    SetInputError("controller_port_device_async_queue_failed",
                  "SetControllerPortDeviceAsync",
                  "Failed to queue async controller-port-device work item");
    napi_value reason = MakeString(env, "async_work_queue_failed");
    if (reason) {
      (void)RejectDeferredChecked(env, ctx->deferred, reason);
    }
    delete ctx;
    return promise;
  }

  return promise;
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
      {"refactoredSetControllerPortDeviceAsync", nullptr, SetControllerPortDeviceAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"refactoredGetInputDescriptorMask", nullptr, GetInputDescriptorMask, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_status regStatus = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  if (regStatus != napi_ok) {  // Audit B-F3: log only; throwing here has undefined behavior in module init
    LOGF(LOG_ERROR, "RegisterInputNapi: napi_define_properties failed: %{public}d", regStatus);
  }
}
