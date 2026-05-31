# Input Mapper 基础框架实施完成

## 完成内容

### 1. ArkTS 数据结构与存储
- **`entry/src/main/ets/common/InputMappingRepository.ets`**
  - `InputMappingProfile` 接口：键位映射配置
  - `KeyMapping` 接口：单个键位映射（KeyCode → Joypad ID）
  - `createDefaultInputMappingProfile()`：默认配置（保留当前硬编码映射）
  - `loadInputMappingProfile()`：从文件加载配置
  - `saveInputMappingProfile()`：保存配置到文件
  - 存储路径：`{filesDir}/input/key_mapping.json`

### 2. ArkTS 服务层
- **`entry/src/main/ets/common/InputMappingService.ets`**
  - `InputMappingService` 类：管理配置加载与同步
  - `initialize(context)`：在 EntryAbility 启动时初始化
  - `getCurrentProfile()`：获取当前配置
  - `updateProfile(profile)`：更新配置并同步到 C++
  - `resetToDefault()`：重置为默认配置
  - `applyToNative()`：通过 NAPI 传递配置到 C++ 侧

### 3. C++ 侧映射表
- **`entry/src/main/cpp/app/framework/plugin_manager.cpp`**
  - `InputKeyMappingTable()`：全局映射表（KeyCode → Joypad ID）
  - `UpdateInputKeyMapping(mappings)`：更新映射表（从 NAPI 调用）
  - `MapKeyCodeToJoypad(code, outId)`：查表映射（替代硬编码 switch-case）
  - 默认映射：保留当前 11 个键位的硬编码行为

### 4. NAPI 接口
- **`entry/src/main/cpp/app/napi/input_mapping_napi.h/cpp`**
  - `RegisterInputMappingNapi(env, exports)`：注册 NAPI 接口
  - `setInputKeyMapping(mappingMap)`：ArkTS 调用接口
  - `ParseKeyCode(keyCodeStr)`：字符串 → 枚举值转换（支持 A-Z + 方向键 + 功能键）

### 5. 集成点
- **`entry/src/main/ets/entryability/EntryAbility.ets`**
  - `onCreate()` 中初始化 `InputMappingService`（不触发 libentry.so 加载）
- **`entry/src/main/cpp/app/napi/module_init.cpp`**
  - 注册 `RegisterInputMappingNapi` 到 libentry.so 导出表
- **`entry/src/main/cpp/CMakeLists.txt`**
  - 添加 `app/napi/input_mapping_napi.cpp` 到编译列表

## 验证结果

```
==== quick_signals summary ====
  regression   PASS  (34s)
  hygiene      PASS  (12s)
  ui-fixes     PASS  (24s)
  skill-contract PASS  (55s)
  cxx-build    PASS  (8s)

==== ALL PASS / SKIP ====
```

- ✅ 回归检查通过
- ✅ 代码卫生检查通过
- ✅ C++ 增量编译通过
- ✅ 默认行为向后兼容（11 个键位映射保持不变）

## 扩展点（UI 集成）

### 1. 获取当前配置
```typescript
import { getInputMappingService } from '../common/InputMappingService'

const service = getInputMappingService()
const profile = service.getCurrentProfile()
// profile.keyMappings: KeyMapping[]
```

### 2. 更新配置
```typescript
import { InputMappingProfile } from '../common/InputMappingRepository'

const newProfile: InputMappingProfile = {
  version: 1,
  profileName: 'custom',
  keyMappings: [
    { keyCode: 'KEY_Z', joypadId: 0, displayName: 'B' },
    { keyCode: 'KEY_X', joypadId: 8, displayName: 'A' },
    // ... 其他映射
  ],
  updatedAt: Date.now()
}

await service.updateProfile(newProfile)
// 自动保存到文件 + 同步到 C++ 侧
```

### 3. 重置为默认
```typescript
await service.resetToDefault()
```

### 4. Joypad ID 参考（libretro.h）
```
RETRO_DEVICE_ID_JOYPAD_B        = 0
RETRO_DEVICE_ID_JOYPAD_Y        = 1
RETRO_DEVICE_ID_JOYPAD_SELECT   = 2
RETRO_DEVICE_ID_JOYPAD_START    = 3
RETRO_DEVICE_ID_JOYPAD_UP       = 4
RETRO_DEVICE_ID_JOYPAD_DOWN     = 5
RETRO_DEVICE_ID_JOYPAD_LEFT     = 6
RETRO_DEVICE_ID_JOYPAD_RIGHT    = 7
RETRO_DEVICE_ID_JOYPAD_A        = 8
RETRO_DEVICE_ID_JOYPAD_X        = 9
RETRO_DEVICE_ID_JOYPAD_L        = 10
RETRO_DEVICE_ID_JOYPAD_R        = 11
RETRO_DEVICE_ID_JOYPAD_L2       = 12
RETRO_DEVICE_ID_JOYPAD_R2       = 13
RETRO_DEVICE_ID_JOYPAD_L3       = 14
RETRO_DEVICE_ID_JOYPAD_R3       = 15
```

### 5. 支持的 KeyCode（可扩展）
当前支持：
- 方向键：`KEY_DPAD_UP/DOWN/LEFT/RIGHT`
- 字母键：`KEY_A` ~ `KEY_Z`
- 功能键：`KEY_ENTER`, `KEY_SPACE`, `KEY_ESCAPE`

扩展方法：在 `input_mapping_napi.cpp` 的 `ParseKeyCode()` 函数中添加新的 if 分支。

## 后续工作（不包含在本次实施）

1. **UI 编辑界面**
   - 键位映射编辑页面
   - 按键捕获功能
   - 冲突检测

2. **多 Profile 管理**
   - Profile 列表
   - 切换 Profile
   - 导入/导出

3. **手柄自动识别**
   - 检测手柄型号
   - 自动加载对应 Profile

## 技术说明

- **线程安全**：C++ 侧映射表使用 `std::mutex` 保护
- **默认行为**：未配置时使用硬编码默认值，保证向后兼容
- **延迟加载**：InputMappingService 在 EntryAbility onCreate 初始化，不触发 libentry.so 加载
- **持久化**：配置保存在 `{filesDir}/input/key_mapping.json`，JSON 格式
