/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "retropad_napi.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "RetroPad"

void SetRetroPadButtonState(int32_t port, int32_t button, bool pressed);
void SetRetroPadAnalogState(int32_t port, int32_t axis, int32_t value);

namespace {
    // Constants
    constexpr int32_t MAX_PORTS = 4;
    constexpr int32_t MAX_BUTTONS = 16;
    constexpr int32_t MAX_AXES = 4; // Left X, Left Y, Right X, Right Y
    constexpr int32_t ANALOG_LIMIT = 32767;

    // 全局按键状态 (4 个控制器, 每个 16 个按键)
    std::array<std::array<std::atomic<bool>, MAX_BUTTONS>, MAX_PORTS> g_button_states;
    
    // 全局模拟摇杆状态 (4 个控制器, 每个 4 个轴: 左X, 左Y, 右X, 右Y)
    std::array<std::array<std::atomic<int16_t>, MAX_AXES>, MAX_PORTS> g_analog_states;
    
    // 初始化标志
    std::atomic<bool> g_initialized{false};
    
    /**
     * 初始化全局状态
     */
    void InitializeState() {
        if (!g_initialized.exchange(true)) {
            // 初始化按键状态
            for (auto& controller : g_button_states) {
                for (auto& button : controller) {
                    button.store(false);
                }
            }
            
            // 初始化摇杆状态
            for (auto& controller : g_analog_states) {
                for (auto& axis : controller) {
                    axis.store(0);
                }
            }
            
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RetroPad state initialized");
        }
    }
}

void SetRetroPadButtonState(int32_t port, int32_t button, bool pressed) {
    InitializeState();

    static size_t writeLogs = 0;
    writeLogs++;
    if (writeLogs <= 10) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RetroPad write: port=%{public}d btn=%{public}d pressed=%{public}d",
                     port, button, pressed);
    }

    if (port < 0 || port >= MAX_PORTS) {
        return;
    }

    if (button < 0 || button >= MAX_BUTTONS) {
        return;
    }

    g_button_states[port][button].store(pressed);
}

void SetRetroPadAnalogState(int32_t port, int32_t axis, int32_t value) {
    InitializeState();

    if (port < 0 || port >= MAX_PORTS) {
        return;
    }

    if (axis < 0 || axis >= MAX_AXES) {
        return;
    }

    int16_t clamped_value = static_cast<int16_t>(std::max(-ANALOG_LIMIT, std::min(ANALOG_LIMIT, value)));
    g_analog_states[port][axis].store(clamped_value);
}

// 更新数字按键
napi_value UpdateRetroPadButton(napi_env env, napi_callback_info info) {
    InitializeState();
    
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadButton: Invalid argument count");
        return nullptr;
    }
    
    // 解析参数
    int32_t port, button;
    bool pressed;
    
    napi_get_value_int32(env, args[0], &port);
    napi_get_value_int32(env, args[1], &button);
    napi_get_value_bool(env, args[2], &pressed);
    
    // 验证参数
    if (port < 0 || port >= MAX_PORTS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadButton: Invalid port %{public}d", port);
        return nullptr;
    }
    
    if (button < 0 || button >= MAX_BUTTONS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadButton: Invalid button %{public}d", button);
        return nullptr;
    }
    
    SetRetroPadButtonState(port, button, pressed);
    
    return nullptr;
}

// 更新模拟摇杆
napi_value UpdateRetroPadAnalog(napi_env env, napi_callback_info info) {
    InitializeState();
    
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 3) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadAnalog: Invalid argument count");
        return nullptr;
    }
    
    // 解析参数
    int32_t port, axis, value;
    
    napi_get_value_int32(env, args[0], &port);
    napi_get_value_int32(env, args[1], &axis);
    napi_get_value_int32(env, args[2], &value);
    
    // 验证参数
    if (port < 0 || port >= MAX_PORTS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadAnalog: Invalid port %{public}d", port);
        return nullptr;
    }
    
    if (axis < 0 || axis >= MAX_AXES) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "UpdateRetroPadAnalog: Invalid axis %{public}d", axis);
        return nullptr;
    }
    
    SetRetroPadAnalogState(port, axis, value);
    
    return nullptr;
}

// 获取 RetroPad 状态 (Libretro 回调)
int16_t GetRetroPadState(unsigned port, unsigned device, unsigned index, unsigned id) {
    InitializeState();
    
    // 验证端口
    if (port >= MAX_PORTS) {
        return 0;
    }
    
    if (device == RETRO_DEVICE_JOYPAD) {
        // 数字按键
        if (id < MAX_BUTTONS) {
            return g_button_states[port][id].load() ? 1 : 0;
        }
    }
    else if (device == RETRO_DEVICE_ANALOG) {
        // 模拟摇杆
        // index: 0=左摇杆, 1=右摇杆
        // id: 0=X轴, 1=Y轴
        
        if (index < 2 && id < 2) {
            int axis = index * 2 + id;
            return g_analog_states[port][axis].load();
        }
    }
    
    return 0;
}

// 注册 NAPI 函数
napi_value RegisterRetroPadNapi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {
            "updateRetroPadButton",
            nullptr,
            UpdateRetroPadButton,
            nullptr,
            nullptr,
            nullptr,
            napi_default,
            nullptr
        },
        {
            "updateRetroPadAnalog",
            nullptr,
            UpdateRetroPadAnalog,
            nullptr,
            nullptr,
            nullptr,
            napi_default,
            nullptr
        }
    };
    
    napi_status status = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    if (status != napi_ok) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to register RetroPad NAPI functions");
        return nullptr;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ RetroPad NAPI functions registered");
    
    return exports;
}
