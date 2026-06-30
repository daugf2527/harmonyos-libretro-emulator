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

#ifndef RETROPAD_NAPI_H
#define RETROPAD_NAPI_H

#include <napi/native_api.h>
#include <cstdint>

// Libretro 设备类型
#ifndef RETRO_DEVICE_JOYPAD
#define RETRO_DEVICE_JOYPAD 1
#endif
#ifndef RETRO_DEVICE_ANALOG
#define RETRO_DEVICE_ANALOG 5
#endif

// Libretro RetroPad 按键 ID
#ifndef RETRO_DEVICE_ID_JOYPAD_B
#define RETRO_DEVICE_ID_JOYPAD_B        0
#define RETRO_DEVICE_ID_JOYPAD_Y        1
#define RETRO_DEVICE_ID_JOYPAD_SELECT   2
#define RETRO_DEVICE_ID_JOYPAD_START    3
#define RETRO_DEVICE_ID_JOYPAD_UP       4
#define RETRO_DEVICE_ID_JOYPAD_DOWN     5
#define RETRO_DEVICE_ID_JOYPAD_LEFT     6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT    7
#define RETRO_DEVICE_ID_JOYPAD_A        8
#define RETRO_DEVICE_ID_JOYPAD_X        9
#define RETRO_DEVICE_ID_JOYPAD_L       10
#define RETRO_DEVICE_ID_JOYPAD_R       11
#define RETRO_DEVICE_ID_JOYPAD_L2      12
#define RETRO_DEVICE_ID_JOYPAD_R2      13
#define RETRO_DEVICE_ID_JOYPAD_L3      14
#define RETRO_DEVICE_ID_JOYPAD_R3      15
#endif

// Libretro 模拟摇杆索引
#ifndef RETRO_DEVICE_INDEX_ANALOG_LEFT
#define RETRO_DEVICE_INDEX_ANALOG_LEFT   0
#endif
#ifndef RETRO_DEVICE_INDEX_ANALOG_RIGHT
#define RETRO_DEVICE_INDEX_ANALOG_RIGHT  1
#endif

// Libretro 模拟摇杆轴
#ifndef RETRO_DEVICE_ID_ANALOG_X
#define RETRO_DEVICE_ID_ANALOG_X         0
#endif
#ifndef RETRO_DEVICE_ID_ANALOG_Y
#define RETRO_DEVICE_ID_ANALOG_Y         1
#endif

// 供 Native 侧直接写入全局 RetroPad 状态（避免依赖 NAPI 参数）
void SetRetroPadButtonState(int32_t port, int32_t button, bool pressed);
void SetRetroPadAnalogState(int32_t port, int32_t axis, int32_t value);

/**
 * 更新 RetroPad 数字按键状态
 * 
 * @param env NAPI 环境
 * @param info 回调信息
 * @return napi_value
 * 
 * 参数:
 *   - port: 控制器端口 (0-3)
 *   - button: 按键 ID (0-15)
 *   - pressed: 是否按下 (boolean)
 */
napi_value UpdateRetroPadButton(napi_env env, napi_callback_info info);

/**
 * 更新 RetroPad 模拟摇杆状态
 * 
 * @param env NAPI 环境
 * @param info 回调信息
 * @return napi_value
 * 
 * 参数:
 *   - port: 控制器端口 (0-3)
 *   - axis: 摇杆轴 (0-3: 左X, 左Y, 右X, 右Y)
 *   - value: 轴值 (-32767 ~ 32767)
 */
napi_value UpdateRetroPadAnalog(napi_env env, napi_callback_info info);

/**
 * 获取 RetroPad 状态 (供 Libretro 回调使用)
 * 
 * @param port 控制器端口 (0-3)
 * @param device 设备类型 (RETRO_DEVICE_JOYPAD 或 RETRO_DEVICE_ANALOG)
 * @param index 设备索引 (模拟摇杆使用: 0=左, 1=右)
 * @param id 按键/轴 ID
 * @return int16_t 按键状态 (0/1) 或轴值 (-32767 ~ 32767)
 */
int16_t GetRetroPadState(unsigned port, unsigned device, unsigned index, unsigned id);

/**
 * 注册 RetroPad NAPI 接口
 * 
 * @param env NAPI 环境
 * @param exports 导出对象
 * @return napi_value
 */
napi_value RegisterRetroPadNapi(napi_env env, napi_value exports);

#endif // RETROPAD_NAPI_H
