# NAPI 错误码映射表

本文档记录 C++ NAPI 层与 ArkTS ErrorCodes.ets 的错误码映射关系。

## 修改的 NAPI 函数

以下 5 个关键 NAPI 函数已从返回 `boolean` 改为返回结构化错误对象：

```typescript
interface NapiErrorResult {
  success: boolean;
  errorCode?: number;  // 对应 ErrorCodes.ets 的 numericCode
  message?: string;    // 错误描述
}
```

## 错误码映射

| NAPI 函数 | 成功返回 | 失败错误码 | ErrorCodes 定义 | 说明 |
|-----------|---------|-----------|----------------|------|
| `refactoredLoadCore` | `{ success: true }` | 3001 | `EngineErrorCodes.CORE_LOAD_FAILED` | 核心加载失败（dlopen/符号缺失） |
| `refactoredLoadRom` | `{ success: true }` | 3010 | `EngineErrorCodes.ROM_LOAD_FAILED` | ROM 加载失败（文件不存在/格式错误） |
| `refactoredStartEngine` | `{ success: true }` | 3020 | `EngineErrorCodes.ENGINE_START_FAILED` | 引擎启动失败 |
| `refactoredSaveState` | `ArrayBuffer` (向后兼容) | 3031 | `EngineErrorCodes.SAVE_STATE_SAVE_FAILED` | 存档保存失败 |
| `refactoredSwitchGameAsync` | `{ success: true }` | 3001/3010/3020/3022 | 多种错误码 | 游戏切换失败（根据失败阶段映射） |

### refactoredSwitchGameAsync 错误码映射逻辑

`SwitchGameAsync` 是复合操作，根据失败阶段返回不同错误码：

- **3001 (CORE_LOAD_FAILED)**: `errorInfo.reason` 包含 `"load_core"`
- **3010 (ROM_LOAD_FAILED)**: `errorInfo.reason` 包含 `"load_game"`
- **3020 (ENGINE_START_FAILED)**: `errorInfo.reason` 包含 `"start"`
- **3022 (STATE_TRANSITION_FAILED)**: 取消操作或其他状态转换失败

## NAPI 参数校验错误码

参数校验失败时使用 8000 系列错误码（`NapiErrorCodes`）：

| 错误码 | ErrorCodes 定义 | 说明 |
|-------|----------------|------|
| 8001 | `INVALID_ARGUMENT_COUNT` | 参数数量错误 |
| 8002 | `INVALID_ARGUMENT_TYPE` | 参数类型错误 |

## 向后兼容性

### refactoredSaveState 特殊处理

`refactoredSaveState` 成功时返回 `ArrayBuffer`（保持向后兼容），失败时返回错误对象：

```typescript
// 成功
const result = libentry.refactoredSaveState();
if (result instanceof ArrayBuffer) {
  // 旧代码路径：直接使用 ArrayBuffer
}

// 失败
const result = libentry.refactoredSaveState();
if (typeof result === 'object' && 'success' in result) {
  // 新代码路径：检查 success/errorCode/message
  if (!result.success) {
    console.error(`Save failed: ${result.message} (code: ${result.errorCode})`);
  }
}
```

### ArkTS 层迁移建议

旧代码：
```typescript
const success = libentry.refactoredLoadCore(corePath);
if (!success) {
  console.error('Core load failed');
}
```

新代码：
```typescript
const result = libentry.refactoredLoadCore(corePath);
if (!result.success) {
  const errorDef = ErrorCodeUtils.findByNumericCode(result.errorCode);
  const userMessage = errorDef?.userMessage || result.message;
  console.error(`Core load failed: ${userMessage}`);

  // 根据策略处理
  if (ErrorCodeUtils.shouldShowUserPrompt(result.errorCode)) {
    promptAction.showToast({ message: userMessage });
  }
}
```

## 实现细节

### C++ 辅助函数

`engine_napi_common.h` 新增：

```cpp
napi_value MakeErrorResult(napi_env env, bool success, int errorCode = 0,
                           const char *message = nullptr);
```

### 错误信息来源

所有错误消息从 `LibretroEngine::GetLastErrorInfo()` 获取：

```cpp
auto errorInfo = GetEngine()->GetLastErrorInfo();
const char *message = errorInfo.message.empty()
    ? "Default error message"
    : errorInfo.message.c_str();
return MakeErrorResult(env, false, 3001, message);
```

## 测试验证

### 编译验证

```bash
bash scripts/check/quick_signals.sh
```

- ✅ C++ 增量编译通过
- ✅ 静态回归检查通过
- ✅ 仓库卫生检查通过

### 运行时验证（需 DevEco Studio）

1. 触发核心加载失败（路径不存在）
2. 检查返回对象包含 `{ success: false, errorCode: 3001, message: "..." }`
3. 验证 ArkTS 层可以通过 `ErrorCodeUtils.findByNumericCode(3001)` 获取错误定义

## 相关文件

- **错误码定义**: `entry/src/main/ets/common/ErrorCodes.ets`
- **NAPI 辅助函数**: `entry/src/main/cpp/app/napi/engine_napi_common.h`
- **生命周期 NAPI**: `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp`
- **状态 NAPI**: `entry/src/main/cpp/app/napi/engine_state_napi.cpp`

## 后续工作

- [ ] M2-T5: 集成错误码到现有 ArkTS 错误处理（LibretroGamePage/LibraryPage 等）
- [ ] 添加运行时测试用例验证错误码传播
- [ ] 考虑为其他 NAPI 函数（如 `refactoredLoadState`）添加详细错误
