/*
 * Input Mapping NAPI Interface Implementation
 */

#include "input_mapping_napi.h"
#include <ace/xcomponent/native_xcomponent_key_event.h>
#include <hilog/log.h>
#include <string>
#include <unordered_map>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD001
#undef LOG_TAG
#define LOG_TAG "InputMappingNapi"
#undef LOG_FLOW
#define LOG_FLOW "NAPI"
#include "common/log_prefix.h"

// 声明 plugin_manager.cpp 中的函数
extern void UpdateInputKeyMapping(const std::unordered_map<int, int> &mappings);

/**
 * 将 KeyCode 字符串转换为枚举值
 * 例如 "KEY_Z" -> KEY_Z
 */
static int ParseKeyCode(const std::string &keyCodeStr) {
  // 简化实现：直接映射常用键
  if (keyCodeStr == "KEY_DPAD_UP") return KEY_DPAD_UP;
  if (keyCodeStr == "KEY_DPAD_DOWN") return KEY_DPAD_DOWN;
  if (keyCodeStr == "KEY_DPAD_LEFT") return KEY_DPAD_LEFT;
  if (keyCodeStr == "KEY_DPAD_RIGHT") return KEY_DPAD_RIGHT;
  if (keyCodeStr == "KEY_ENTER") return KEY_ENTER;
  if (keyCodeStr == "KEY_SPACE") return KEY_SPACE;
  if (keyCodeStr == "KEY_ESCAPE") return KEY_ESCAPE;
  if (keyCodeStr == "KEY_Z") return KEY_Z;
  if (keyCodeStr == "KEY_X") return KEY_X;
  if (keyCodeStr == "KEY_A") return KEY_A;
  if (keyCodeStr == "KEY_S") return KEY_S;
  if (keyCodeStr == "KEY_Q") return KEY_Q;
  if (keyCodeStr == "KEY_W") return KEY_W;
  if (keyCodeStr == "KEY_E") return KEY_E;
  if (keyCodeStr == "KEY_R") return KEY_R;
  if (keyCodeStr == "KEY_T") return KEY_T;
  if (keyCodeStr == "KEY_Y") return KEY_Y;
  if (keyCodeStr == "KEY_U") return KEY_U;
  if (keyCodeStr == "KEY_I") return KEY_I;
  if (keyCodeStr == "KEY_O") return KEY_O;
  if (keyCodeStr == "KEY_P") return KEY_P;
  if (keyCodeStr == "KEY_D") return KEY_D;
  if (keyCodeStr == "KEY_F") return KEY_F;
  if (keyCodeStr == "KEY_G") return KEY_G;
  if (keyCodeStr == "KEY_H") return KEY_H;
  if (keyCodeStr == "KEY_J") return KEY_J;
  if (keyCodeStr == "KEY_K") return KEY_K;
  if (keyCodeStr == "KEY_L") return KEY_L;
  if (keyCodeStr == "KEY_C") return KEY_C;
  if (keyCodeStr == "KEY_V") return KEY_V;
  if (keyCodeStr == "KEY_B") return KEY_B;
  if (keyCodeStr == "KEY_N") return KEY_N;
  if (keyCodeStr == "KEY_M") return KEY_M;
  return -1; // 未知键
}

/**
 * NAPI 接口：setInputKeyMapping(mappingMap)
 * @param mappingMap { "KEY_Z": 0, "KEY_X": 8, ... }
 */
static napi_value SetInputKeyMapping(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to read arguments");
    return nullptr;
  }

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Missing argument: mappingMap");
    return nullptr;
  }

  // 检查参数是否为对象
  napi_valuetype valueType;
  if (napi_typeof(env, args[0], &valueType) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to read argument type");
    return nullptr;
  }
  if (valueType != napi_object) {
    napi_throw_error(env, nullptr, "Argument must be an object");
    return nullptr;
  }

  // 遍历对象属性
  napi_value propertyNames = nullptr;
  if (napi_get_property_names(env, args[0], &propertyNames) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to read mapping keys");
    return nullptr;
  }

  uint32_t propertyCount = 0;
  if (napi_get_array_length(env, propertyNames, &propertyCount) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to read mapping key count");
    return nullptr;
  }

  std::unordered_map<int, int> mappings;
  for (uint32_t i = 0; i < propertyCount; i++) {
    napi_value propertyName = nullptr;
    if (napi_get_element(env, propertyNames, i, &propertyName) != napi_ok) {
      continue;
    }

    // 获取键名（KeyCode 字符串）
    size_t keyStrLen = 0;
    if (napi_get_value_string_utf8(env, propertyName, nullptr, 0,
                                   &keyStrLen) != napi_ok) {
      continue;
    }
    std::string keyCodeStr;
    keyCodeStr.resize(keyStrLen + 1);
    if (napi_get_value_string_utf8(env, propertyName, &keyCodeStr[0],
                                   keyCodeStr.size(), &keyStrLen) != napi_ok) {
      continue;
    }
    keyCodeStr.resize(keyStrLen);

    // 获取值（Joypad ID）
    napi_value propertyValue = nullptr;
    if (napi_get_property(env, args[0], propertyName, &propertyValue) !=
        napi_ok) {
      continue;
    }
    int32_t joypadId = 0;
    if (napi_get_value_int32(env, propertyValue, &joypadId) != napi_ok) {
      continue;
    }

    // 转换 KeyCode 字符串为枚举值
    int keyCode = ParseKeyCode(keyCodeStr);
    if (keyCode >= 0) {
      mappings[keyCode] = joypadId;
    } else {
      LOGF(LOG_WARN, "Unknown KeyCode: %{public}s", keyCodeStr.c_str());
    }
  }

  // 更新映射表
  UpdateInputKeyMapping(mappings);

  napi_value result = nullptr;
  if (napi_get_boolean(env, true, &result) != napi_ok) {
    return nullptr;
  }
  return result;
}

/**
 * 注册 NAPI 接口
 */
void RegisterInputMappingNapi(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"setInputKeyMapping", nullptr, SetInputKeyMapping, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_status status =
      napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]),
                             desc);
  if (status != napi_ok) {
    LOGF(LOG_ERROR,
         "RegisterInputMappingNapi: napi_define_properties failed: %{public}d",
         status);
    return;
  }
  LOGF(LOG_INFO, "Input mapping NAPI registered");
}
