# M0 任务 27: Switch 可取消机制实施报告

生成时间: 2026-05-31

## 1. 实施概述

为 Switch 流程添加显式取消机制，允许用户在游戏切换过程中主动取消操作。

### 关键改动

1. **C++ Engine 层**: 添加 `Cancel` 消息类型和处理逻辑
2. **NAPI 层**: 添加 `cancelSwitch()` 接口
3. **ArkTS UI 层**: 添加取消按钮（仅在 `switching=true` 时显示）
4. **状态恢复**: 取消后自动恢复到 `INIT` 状态

## 2. 详细改动

### 2.1 C++ Engine 层

#### engine_messages.h
添加 `Cancel` 消息类型：

```cpp
enum class MessageType {
  // ... 其他消息类型
  Cancel,     // 取消 Switch 请求
  // ...
};
```

#### libretro_engine.h
添加公共 `Cancel()` 方法：

```cpp
void Cancel();
```

#### libretro_engine.cpp

**Cancel() 方法实现**（line 654-659）：
```cpp
void LibretroEngine::Cancel() {
  LOGF(LOG_INFO, "[NEW] Cancel called");
  if (!messageQueue_.Push({MessageType::Cancel, {}})) {
    LOGF(LOG_WARN, "[NEW] Cancel dropped: message queue closed");
  }
}
```

**HandleMessage() 处理 Cancel**（line 1336-1363）：
```cpp
case MessageType::Cancel:
  LOGF(LOG_INFO, "[NEW] Message: Cancel Received");
  // Cancel 只在 STARTING/LOADING 状态有效，直接 Reset 回 INIT
  {
    EngineState currentState = state_.load();
    if (currentState == EngineState::STARTING ||
        currentState == EngineState::LOADING ||
        currentState == EngineState::CORE_LOADED) {
      LOGF(LOG_INFO, "[NEW] Cancel: resetting from state=%{public}d",
           static_cast<int>(currentState));
      UnloadGameIfNeeded("cancel");
      if (coreLoader_.IsLoaded()) {
        if (diskController_) {
          diskController_->ClearCallbacks();
        }
        if (coreLoader_.GetDeinit()) {
          coreLoader_.GetDeinit()();
        }
        coreLoader_.UnloadCore();
      }
      envState_.ResetCoreState();
      Reset();
      TransitionTo(EngineState::INIT);
    } else {
      LOGF(LOG_WARN, "[NEW] Cancel ignored: state=%{public}d",
           static_cast<int>(currentState));
    }
  }
  break;
```

**关键逻辑**:
- 只在 `STARTING` / `LOADING` / `CORE_LOADED` 状态响应取消
- 清理已加载的核心（调用 `deinit`、`UnloadCore`）
- 清理 DiskController 回调（防止悬空指针）
- 调用 `Reset()` 重置引擎状态
- 转换到 `INIT` 状态

### 2.2 NAPI 层

#### engine_lifecycle_napi.cpp

**CancelSwitch() 实现**（line 774-799）：
```cpp
static napi_value CancelSwitch(napi_env env, napi_callback_info info) {
  NAPI_TRY_CATCH_BEGIN
  LOGF(LOG_INFO, "[NEW] CancelSwitch called");

  // 递增 switch_token 使所有等待中的 switch 请求失效
  const uint64_t newToken = switch_token.fetch_add(1) + 1;
  LOGF(LOG_INFO, "[NEW] CancelSwitch: incremented token to %{public}llu",
       static_cast<unsigned long long>(newToken));

  // 释放当前持有的 switch token（如果有）
  {
    std::lock_guard<std::mutex> lock(switch_mutex);
    if (active_switch_token != 0) {
      LOGF(LOG_INFO, "[NEW] CancelSwitch: releasing active token %{public}llu",
           static_cast<unsigned long long>(active_switch_token));
      active_switch_token = 0;
      switch_cond.notify_all();
    }
  }

  // 向 Engine 发送 Cancel 消息
  GetEngine()->Cancel();

  return MakeBool(env, true);
  NAPI_TRY_CATCH_END(env, nullptr)
}
```

**NAPI 导出注册**（line 977）：
```cpp
{"refactoredCancelSwitch", nullptr, CancelSwitch, nullptr, nullptr, nullptr, napi_default, nullptr},
```

**关键逻辑**:
1. 递增全局 `switch_token`，使所有等待中的 switch 请求失效
2. 释放 `active_switch_token` 并唤醒等待线程
3. 调用 Engine 的 `Cancel()` 方法发送消息

### 2.3 ArkTS UI 层

#### RuntimeSessionController.ets

**接口定义**（line 16）：
```typescript
interface RuntimeSessionNapi {
  // ...
  refactoredCancelSwitch(): boolean
  // ...
}
```

**cancelSwitch() 方法**（line 99-101）：
```typescript
cancelSwitch(): boolean {
  return nativeApi.refactoredCancelSwitch()
}
```

#### LibretroGamePage.ets

**取消按钮 UI**（line 698-713）：
```typescript
// 取消按钮：仅在 switching=true 时显示
if (this.switching) {
  Button('取消')
    .width(60)
    .height(40)
    .fontSize(EmuTypography.base)
    .fontColor(EmuColors.error)
    .backgroundColor('#CC000000')
    .border({ width: 0.5, color: '#33FF4444', style: BorderStyle.Solid })
    .borderRadius(4)
    .margin({ left: 18, top: 100 })
    .onClick(() => {
      LogHelper.info('LibretroGame', 'Engine', 'Cancel switch requested');
      runtimeSessionController.cancelSwitch();
      this.switching = false;
      this.switchError = '';
    })
}
```

**UI 设计**:
- 位置：左上角菜单按钮下方（top: 100）
- 颜色：红色边框 + 红色文字（`EmuColors.error`）
- 显示条件：`this.switching === true`
- 点击行为：
  1. 调用 `cancelSwitch()`
  2. 重置 `switching = false`
  3. 清空 `switchError`

## 3. 状态转换流程

### 正常 Switch 流程
```
INIT → STARTING → LOADING → CORE_LOADED → GAME_LOADED → RUNNING
```

### Cancel 流程
```
STARTING/LOADING/CORE_LOADED → Cancel 消息 → UnloadCore → Reset → INIT
```

### 关键保护
1. **Token 失效**: `switch_token` 递增后，所有旧请求的 `IsLatestSwitchToken()` 返回 false
2. **互斥锁释放**: `active_switch_token = 0` 并 `notify_all()`，唤醒等待线程
3. **资源清理**: 
   - `UnloadGameIfNeeded("cancel")`
   - `diskController_->ClearCallbacks()`
   - `coreLoader_.GetDeinit()()`
   - `coreLoader_.UnloadCore()`
   - `envState_.ResetCoreState()`
   - `Reset()`

## 4. 测试验证

### 4.1 编译验证
```bash
bash scripts/check/quick_signals.sh
```

**结果**: ✅ ALL PASS
- regression: PASS (12s)
- hygiene: PASS (3s)
- ui-fixes: PASS (8s)
- skill-contract: PASS (19s)
- cxx-build: PASS (10s)

### 4.2 静态检查
- ✅ 无 regression guards 违规
- ✅ 无 hygiene 问题
- ✅ C++ 增量编译通过

### 4.3 预期行为

**场景 1: 用户在 Core 加载中取消**
1. 用户点击"取消"按钮
2. `switch_token` 递增，旧请求失效
3. Engine 收到 `Cancel` 消息
4. 状态从 `LOADING` → `INIT`
5. UI `switching` 标志重置为 false
6. 取消按钮消失

**场景 2: 用户在 ROM 加载中取消**
1. 同上流程
2. 已加载的 Core 被卸载（`UnloadCore`）
3. 状态恢复到 `INIT`

**场景 3: 取消后立即发起新 Switch**
1. 旧 token 已失效
2. 新 Switch 获取新 token
3. 正常执行新 Switch 流程

## 5. 关键约束

### 5.1 状态约束
- Cancel 只在 `STARTING` / `LOADING` / `CORE_LOADED` 状态有效
- 其他状态（`RUNNING` / `PAUSED` / `STOPPED`）忽略 Cancel

### 5.2 线程安全
- `switch_token` 使用 `atomic<uint64_t>`
- `active_switch_token` 受 `switch_mutex` 保护
- Engine 消息队列线程安全

### 5.3 资源清理
- 必须先清理 `DiskController` 回调再 `UnloadCore`（防止悬空指针）
- 必须调用 `coreLoader_.GetDeinit()` 再 `UnloadCore`
- 必须调用 `Reset()` 清理引擎状态

## 6. 与现有机制的协同

### 6.1 与 Switch 单飞机制协同
- Cancel 通过递增 `switch_token` 触发单飞机制
- 所有等待中的请求通过 `IsLatestSwitchToken()` 检查失效
- `AcquireSwitchToken()` 中的 `wait()` 被 `notify_all()` 唤醒

### 6.2 与 pendingSwitch 协同
- Cancel 后 UI 重置 `switching = false`
- 如果有 `pendingSwitch`，用户可以重新触发
- 新请求获取新 token，不受旧 token 影响

### 6.3 与错误恢复协同
- Cancel 清空 `switchError`
- 状态恢复到 `INIT`，可以重新开始

## 7. 未来改进方向

### 7.1 UI 增强
- 添加取消确认对话框（防止误触）
- 显示取消进度（"正在取消..."）
- 取消后显示提示信息

### 7.2 状态细化
- 区分"用户取消"和"超时取消"
- 记录取消原因到日志

### 7.3 性能优化
- 如果 Core 尚未加载完成，可以更快中断 `dlopen`
- 如果 ROM 尚未读取完成，可以中断文件 I/O

## 8. 总结

### 实施完成度
- ✅ C++ Engine 层 Cancel 消息处理
- ✅ NAPI 层 cancelSwitch 接口
- ✅ ArkTS UI 层取消按钮
- ✅ 状态恢复到 INIT
- ✅ Token 失效机制
- ✅ 资源清理逻辑
- ✅ 编译验证通过

### 关键成果
1. **用户体验**: 用户可以主动取消长时间的 Switch 操作
2. **状态一致性**: 取消后状态干净恢复到 INIT
3. **线程安全**: 所有并发控制机制正确协同
4. **资源安全**: 核心卸载前正确清理回调和状态

### 测试建议
1. **手动测试**: 在真机上测试取消按钮功能
2. **压力测试**: 快速连续点击取消和启动
3. **状态验证**: 取消后检查 Engine 状态是否为 INIT
4. **日志验证**: 检查 hilog 中的 Cancel 相关日志

### 文件清单
- `entry/src/main/cpp/core/engine/engine_messages.h` - 添加 Cancel 消息类型
- `entry/src/main/cpp/core/engine/libretro_engine.h` - 添加 Cancel() 方法声明
- `entry/src/main/cpp/core/engine/libretro_engine.cpp` - 实现 Cancel() 和 HandleMessage(Cancel)
- `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp` - 添加 CancelSwitch NAPI 接口
- `entry/src/main/ets/common/RuntimeSessionController.ets` - 添加 cancelSwitch() 方法
- `entry/src/main/ets/pages/LibretroGamePage.ets` - 添加取消按钮 UI

---

**实施状态**: ✅ 完成  
**验证状态**: ✅ 编译通过，静态检查通过  
**待测试**: 真机功能测试
