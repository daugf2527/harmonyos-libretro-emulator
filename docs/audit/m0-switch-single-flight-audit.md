# M0 Switch 单飞实现审计报告

生成时间: 2026-05-31

## 1. Switch 调用点分析

### ArkTS 层 (LibretroGamePage.ets)

**主入口**: `startOrSwitchGame()` (line 774)

**防护机制**:
1. **switching 标志位** (line 775-782)
   - 如果正在切换，记录到 `pendingSwitch` 而非立即执行
   - 避免并发执行

2. **switchToken 机制** (line 813-814)
   - 每次调用递增 token
   - 通过 `isCurrentSwitchTask(token)` 检查是否为最新请求
   - 多处检查点: line 816, 842, 852, 868

3. **防抖机制** (line 806-811)
   - `startOrSwitchDebounceMs = 600ms`
   - 防止高频点击

4. **重复启动检测** (line 795-802)
   - 检查当前游戏是否已运行
   - 避免同一游戏反复 stop/start

**调用触发点**:
- `onPageShow()` → line 309
- ROM 选择变化 → line 550
- 控制面板启动按钮 → line 688

### C++ NAPI 层 (engine_lifecycle_napi.cpp)

**主入口**: `SwitchGameAsync()` (line 633)

**单飞机制**:
1. **全局 switch_token** (line 386-388)
   - `IsLatestSwitchToken()` 检查是否为最新请求

2. **AcquireSwitchToken/ReleaseSwitchToken** (line 390-411)
   - 使用 `switch_mutex` + `switch_cond` 实现互斥
   - `active_switch_token` 确保同时只有一个 switch 执行
   - 等待队列: 旧请求会在 `wait()` 中被取消

3. **SwitchTokenGuard RAII** (line 506-509)
   - 自动释放 token，防止异常时死锁

4. **多处 token 检查**:
   - AcquireSwitchToken 前后 (line 500, 511)
   - 每个等待状态前 (line 540, 563, 586)
   - RecoverAfterSwitchFailure 中 (line 449, 472)

5. **去重机制** (line 709-712)
   - `ShouldDedupSwitchRequest()` (line 31-52)
   - 800ms 窗口内相同 core+rom 请求直接返回成功

## 2. 多次调用风险评估

### ✅ 已防护场景

1. **高频点击**: 600ms 防抖 + 800ms 去重
2. **并发调用**: switching 标志 + pendingSwitch 队列
3. **异步竞态**: switchToken 多点检查
4. **C++ 层并发**: mutex + active_switch_token 互斥

### ⚠️ 潜在风险

1. **pendingSwitch 只保留最后一个**
   - 如果用户快速点击 A→B→C，只会执行 A 和 C
   - B 请求会被覆盖
   - **影响**: 中等，符合"最新优先"语义

2. **token 溢出**
   - `switchToken` 为 number 类型，理论上可溢出
   - **影响**: 极低，需要 2^53 次调用

3. **页面销毁时的清理**
   - `aboutToDisappear()` 中 `switchToken += 1` 会取消进行中的 switch
   - 但 C++ 层的 `active_switch_token` 不会立即清理
   - **影响**: 低，下次调用会自然覆盖

## 3. 状态机实现

### ArkTS 状态
- `switching: boolean` - 是否正在切换
- `switchError: string` - 错误信息
- `pendingSwitch: PendingSwitch | undefined` - 待执行请求
- `switchToken: number` - 请求序列号

### C++ 状态
- `switch_token: atomic<uint64_t>` - 全局最新 token
- `active_switch_token: uint64_t` - 当前执行中的 token
- `switch_mutex` + `switch_cond` - 互斥锁和条件变量

### 状态转换
```
IDLE → switching=true → AcquireSwitchToken → ExecuteSwitchGame
  ↓
  ├─ 成功 → ReleaseSwitchToken → switching=false → 检查 pendingSwitch
  ├─ 取消 → ReleaseSwitchToken → switching=false
  └─ 失败 → RecoverAfterSwitchFailure → ReleaseSwitchToken → switching=false
```

## 4. 结论

**单飞实现状态**: ✅ 已实现，机制完善

**核心机制**:
1. ArkTS 层: switching 标志 + switchToken + 防抖
2. C++ 层: mutex 互斥 + token 检查 + 去重

**建议改进** (M0 任务 27-30):
1. 添加显式取消机制 (当前只能通过新请求覆盖)
2. 完善失败恢复逻辑 (RecoverAfterSwitchFailure 已有基础)
3. 添加高频切换压力测试
