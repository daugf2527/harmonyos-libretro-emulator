# M6: 核心切换流程优化设计

**创建日期**: 2026-05-31
**状态**: 设计阶段
**前置依赖**: M0 切换链路稳定化（单飞/取消/失败恢复）

---

## 1. 当前实现分析

### 1.1 M0 已实现的功能

基于 M0 审计文档（`docs/audit/m0-*.md`），当前切换机制已具备：

#### 单飞机制（Single-Flight）
- **ArkTS 层**:
  - `switching` 标志位防止并发执行
  - `switchToken` 序列号机制（每次递增）
  - `pendingSwitch` 队列（保留最新请求）
  - 600ms 防抖 + 重复启动检测

- **C++ NAPI 层**:
  - 全局 `switch_token` (atomic<uint64_t>)
  - `AcquireSwitchToken/ReleaseSwitchToken` 互斥锁
  - `active_switch_token` 确保同时只有一个 switch 执行
  - 800ms 窗口去重（相同 core+rom）

#### 取消机制（Cancel）
- **用户主动取消**: UI 显示"取消"按钮（仅在 `switching=true` 时）
- **Token 失效**: 递增 `switch_token` 使旧请求失效
- **状态恢复**: Cancel 消息 → UnloadCore → Reset → INIT
- **资源清理**: DiskController 回调清理 + Core deinit

#### 失败恢复（Failure Recovery）
- **C++ 层**: 所有 8 个失败路径调用 `RecoverAfterSwitchFailure`
  - Stop 失败、等待 STOPPED 超时
  - Start 失败、SetFilesDir 失败
  - LoadCore 失败、等待 CORE_LOADED 超时
  - LoadGame 失败、等待 RUNNING 超时

- **ArkTS 层**: 智能重试逻辑
  - `retryCount` 字段（最大 2 次）
  - 同请求才计数（不同游戏独立）
  - 达到上限后显示详细错误

### 1.2 当前切换流程

```
[ArkTS] startOrSwitchGame()
  ↓
[NAPI] SwitchGameAsync()
  ↓
[C++] ExecuteSwitchGame()
  ├─ 1. AcquireSwitchToken (互斥锁)
  ├─ 2. Stop (如果当前有游戏运行)
  ├─ 3. WaitForState(STOPPED, 5000ms)
  ├─ 4. Start (启动引擎线程)
  ├─ 5. SetFilesDir
  ├─ 6. LoadCore (dlopen + 符号解析)
  ├─ 7. WaitForState(CORE_LOADED, 5000ms)
  ├─ 8. LoadGame (retro_load_game)
  ├─ 9. WaitForState(RUNNING, 5000ms)
  └─ 10. ReleaseSwitchToken
```

**关键时间点**:
- **Stop → STOPPED**: 最多 5 秒
- **LoadCore → CORE_LOADED**: 最多 5 秒（dlopen + 初始化）
- **LoadGame → RUNNING**: 最多 5 秒（ROM 读取 + retro_load_game）
- **总计**: 最坏情况 15 秒（3 个超时窗口）

### 1.3 已解决的问题

✅ **并发安全**: 单飞机制防止多个 switch 同时执行
✅ **用户取消**: 显式取消按钮 + token 失效
✅ **失败恢复**: 所有失败路径自动回到 INIT 状态
✅ **重试保护**: 最多重试 2 次，防止无限循环
✅ **状态一致性**: 严格的状态机转换验证

---

## 2. 优化目标

### 2.1 切换速度优化

**目标**: 将典型切换时间从 2-5 秒降低到 0.5-2 秒

#### 优化点 1: Core 预加载
- **问题**: `dlopen` + 符号解析耗时 500ms-2s（取决于 Core 大小）
- **方案**: 后台预加载常用 Core，切换时直接使用
- **收益**: 节省 50%-80% 的 LoadCore 时间

#### 优化点 2: ROM 数据缓存
- **问题**: 小 ROM（<1MB）每次从文件系统读取
- **方案**: LRU 缓存最近使用的 ROM 数据（限制总大小 10MB）
- **收益**: 小 ROM 切换时间从 200ms 降到 <10ms

#### 优化点 3: 状态等待优化
- **问题**: `WaitForState` 使用固定 5 秒超时，即使操作已完成
- **方案**: 使用条件变量立即通知，超时仅作为兜底
- **收益**: 消除不必要的等待延迟

### 2.2 用户体验优化

#### 优化点 4: 进度提示
- **问题**: 用户只看到"切换中..."，不知道卡在哪一步
- **方案**: 细粒度进度回调（Stop/LoadCore/LoadGame/Start）
- **UI 显示**:
  ```
  正在停止当前游戏... (20%)
  正在加载核心... (40%)
  正在加载 ROM... (60%)
  正在启动游戏... (80%)
  完成 (100%)
  ```

#### 优化点 5: 平滑过渡动画
- **问题**: 切换时画面突然黑屏，体验生硬
- **方案**:
  - 淡出当前画面（200ms）
  - 显示加载动画（旋转图标 + 进度条）
  - 淡入新游戏画面（200ms）

#### 优化点 6: 预测性加载
- **问题**: 用户在 ROM 列表滚动时，切换意图明确但未触发
- **方案**:
  - 检测用户在某个 ROM 上停留 >500ms
  - 后台预加载对应 Core（如果未加载）
  - 用户点击时立即切换

### 2.3 异常处理增强

#### 优化点 7: 超时分级
- **问题**: 所有超时都是 5 秒，不区分严重程度
- **方案**:
  - **Stop 超时**: 5 秒（严重，可能死锁）
  - **LoadCore 超时**: 10 秒（大 Core 可能需要更长时间）
  - **LoadGame 超时**: 8 秒（大 ROM 可能需要更长时间）

#### 优化点 8: 资源不足检测
- **问题**: 内存不足时 `dlopen` 失败，但错误信息不明确
- **方案**:
  - 切换前检查可用内存（至少 100MB）
  - 如果不足，先卸载未使用的 Core
  - 显示友好错误："内存不足，已自动清理"

#### 优化点 9: Core 兼容性检测
- **问题**: 某些 Core 在特定设备上不兼容，但只有加载后才知道
- **方案**:
  - 维护 Core 兼容性数据库（设备型号 + Core 版本）
  - 切换前检查兼容性
  - 不兼容时提前拒绝并提示

---

## 3. 设计方案

### 3.1 Core 预加载机制

#### 3.1.1 预加载策略

**触发时机**:
1. **应用启动时**: 预加载最近使用的 Core（最多 3 个）
2. **用户浏览时**: 检测到用户在某个 Core 上停留 >500ms
3. **空闲时**: 后台预加载使用频率 Top 5 的 Core

**预加载优先级**:
```
P0: 当前正在运行的 Core（不卸载）
P1: 最近 3 次使用的 Core
P2: 使用频率 Top 5 的 Core
P3: 用户当前浏览的 Core
```

**内存管理**:
- **最大预加载数量**: 3 个 Core（避免内存占用过高）
- **LRU 淘汰**: 超过 3 个时，卸载最久未使用的
- **内存阈值**: 可用内存 <200MB 时，停止预加载

#### 3.1.2 实现设计

**C++ 层新增类**: `CorePreloader`

```cpp
class CorePreloader {
public:
  // 预加载 Core（异步）
  void PreloadCore(const std::string& corePath);

  // 检查 Core 是否已预加载
  bool IsPreloaded(const std::string& corePath);

  // 获取预加载的 Core（如果存在）
  CoreLoader* GetPreloadedCore(const std::string& corePath);

  // 卸载最久未使用的 Core
  void EvictLRU();

  // 清空所有预加载的 Core
  void Clear();

private:
  struct PreloadedCore {
    std::string path;
    std::unique_ptr<CoreLoader> loader;
    std::chrono::steady_clock::time_point lastUsed;
  };

  std::vector<PreloadedCore> preloadedCores_;
  std::mutex mutex_;
  static constexpr size_t kMaxPreloadedCores = 3;
};
```

**ArkTS 层新增接口**:
```typescript
interface RuntimeSessionNapi {
  // 预加载 Core（后台异步）
  preloadCore(corePath: string): void

  // 检查 Core 是否已预加载
  isPreloaded(corePath: string): boolean
}
```

**集成点**:
- `LibretroGamePage.ets` 的 `onPageShow()`: 预加载最近使用的 Core
- `LibretroGamePage.ets` 的 ROM 列表滚动事件: 检测停留 >500ms 触发预加载
- `ExecuteSwitchGame()`: 优先使用预加载的 Core

### 3.2 ROM 数据缓存

#### 3.2.1 缓存策略

**缓存条件**:
- ROM 大小 ≤1MB（避免缓存大文件）
- 最近 5 次使用的 ROM
- 总缓存大小 ≤10MB

**缓存失效**:
- ROM 文件修改时间变化
- 超过 30 分钟未使用
- 内存不足时强制清理

#### 3.2.2 实现设计

**C++ 层新增类**: `RomCache`

```cpp
class RomCache {
public:
  // 缓存 ROM 数据
  void Cache(const std::string& romPath, const std::vector<uint8_t>& data);

  // 获取缓存的 ROM 数据（如果存在）
  std::optional<std::vector<uint8_t>> Get(const std::string& romPath);

  // 清理过期缓存
  void Evict();

private:
  struct CachedRom {
    std::string path;
    std::vector<uint8_t> data;
    std::chrono::steady_clock::time_point lastUsed;
    time_t fileModTime;
  };

  std::vector<CachedRom> cache_;
  std::mutex mutex_;
  static constexpr size_t kMaxCacheSize = 10 * 1024 * 1024; // 10MB
  static constexpr size_t kMaxRomSize = 1 * 1024 * 1024;    // 1MB
};
```

**集成点**:
- `LoadGame()`: 先检查缓存，命中则直接使用
- `LoadGame()` 成功后: 如果 ROM ≤1MB，加入缓存

### 3.3 进度回调机制

#### 3.3.1 进度事件定义

```cpp
enum class SwitchProgress {
  STOPPING_CURRENT = 20,    // 正在停止当前游戏
  LOADING_CORE = 40,        // 正在加载核心
  LOADING_ROM = 60,         // 正在加载 ROM
  STARTING_GAME = 80,       // 正在启动游戏
  COMPLETED = 100           // 完成
};
```

#### 3.3.2 实现设计

**C++ 层**:
```cpp
// ExecuteSwitchGame() 中添加进度回调
void ExecuteSwitchGame(napi_env env, void *data) {
  auto *ctx = static_cast<SwitchGameAsyncContext *>(data);

  // 1. Stop
  ctx->progressCallback(SwitchProgress::STOPPING_CURRENT);
  if (!GetEngine()->Stop()) { ... }

  // 2. LoadCore
  ctx->progressCallback(SwitchProgress::LOADING_CORE);
  if (!GetEngine()->LoadCore(ctx->corePath)) { ... }

  // 3. LoadGame
  ctx->progressCallback(SwitchProgress::LOADING_ROM);
  if (!GetEngine()->LoadGame(ctx->romPath, ctx->romData)) { ... }

  // 4. Start
  ctx->progressCallback(SwitchProgress::STARTING_GAME);
  // ... 等待 RUNNING

  // 5. Complete
  ctx->progressCallback(SwitchProgress::COMPLETED);
}
```

**ArkTS 层**:
```typescript
// LibretroGamePage.ets
@State switchProgress: number = 0
@State switchProgressText: string = ''

async startOrSwitchGame() {
  // ...
  const success = await runtimeSessionController.switchGameAsync(
    corePath,
    romPath,
    filesDir,
    resMgr,
    timeoutMs,
    token,
    (progress: number, text: string) => {
      this.switchProgress = progress
      this.switchProgressText = text
    }
  )
}

// UI 显示
if (this.switching) {
  Column() {
    Text(this.switchProgressText)
    Progress({ value: this.switchProgress, total: 100, type: ProgressType.Linear })
  }
}
```

### 3.4 平滑过渡动画

#### 3.4.1 动画时序

```
[当前游戏运行]
  ↓ (200ms 淡出)
[黑屏 + 加载动画]
  ↓ (切换过程)
[新游戏首帧]
  ↓ (200ms 淡入)
[新游戏运行]
```

#### 3.4.2 实现设计

**ArkTS 层**:
```typescript
@State switchAnimationOpacity: number = 1.0

async startOrSwitchGame() {
  // 1. 淡出当前画面
  animateTo({ duration: 200 }, () => {
    this.switchAnimationOpacity = 0
  })
  await new Promise(resolve => setTimeout(resolve, 200))

  // 2. 执行切换
  const success = await runtimeSessionController.switchGameAsync(...)

  // 3. 淡入新画面
  if (success) {
    animateTo({ duration: 200 }, () => {
      this.switchAnimationOpacity = 1.0
    })
  }
}

// XComponent 透明度
XComponent({ id: 'xcomponent', type: 'surface' })
  .opacity(this.switchAnimationOpacity)
```

### 3.5 超时分级

#### 3.5.1 超时配置

```cpp
struct SwitchTimeouts {
  uint32_t stopTimeoutMs = 5000;      // Stop 超时（严重）
  uint32_t coreLoadTimeoutMs = 10000; // LoadCore 超时（大 Core）
  uint32_t gameLoadTimeoutMs = 8000;  // LoadGame 超时（大 ROM）
};
```

#### 3.5.2 动态调整

**根据 Core 大小调整**:
```cpp
uint32_t GetCoreLoadTimeout(const std::string& corePath) {
  size_t coreSize = GetFileSize(corePath);
  if (coreSize > 10 * 1024 * 1024) {  // >10MB
    return 15000;  // 15 秒
  } else if (coreSize > 5 * 1024 * 1024) {  // >5MB
    return 10000;  // 10 秒
  } else {
    return 5000;   // 5 秒
  }
}
```

**根据 ROM 大小调整**:
```cpp
uint32_t GetGameLoadTimeout(const std::string& romPath) {
  size_t romSize = GetFileSize(romPath);
  if (romSize > 50 * 1024 * 1024) {  // >50MB
    return 15000;  // 15 秒
  } else if (romSize > 10 * 1024 * 1024) {  // >10MB
    return 10000;  // 10 秒
  } else {
    return 5000;   // 5 秒
  }
}
```

### 3.6 资源不足检测

#### 3.6.1 内存检查

**切换前检查**:
```cpp
bool CheckMemoryAvailable() {
  // 读取 /proc/meminfo 获取可用内存
  size_t availableMemMB = GetAvailableMemoryMB();
  if (availableMemMB < 100) {
    LOGF(LOG_WARN, "Low memory: %zuMB available", availableMemMB);
    return false;
  }
  return true;
}
```

**自动清理**:
```cpp
void ExecuteSwitchGame(napi_env env, void *data) {
  // 检查内存
  if (!CheckMemoryAvailable()) {
    // 尝试清理预加载的 Core
    CorePreloader::GetInstance()->Clear();

    // 再次检查
    if (!CheckMemoryAvailable()) {
      EnsureLastErrorIfEmpty("low_memory", "MemoryCheck",
                             "Available memory < 100MB");
      ctx->result = false;
      return;
    }
  }

  // 继续切换流程...
}
```

---

## 4. 实现建议

### 4.1 代码改动点

#### Phase 1: 基础优化（P0）
1. **状态等待优化** (`libretro_engine.cpp`)
   - 将 `WaitForState` 改为条件变量通知
   - 保留超时作为兜底

2. **超时分级** (`engine_lifecycle_napi.cpp`)
   - 添加 `SwitchTimeouts` 结构
   - 根据文件大小动态调整超时

3. **进度回调** (`engine_lifecycle_napi.cpp` + `LibretroGamePage.ets`)
   - 添加进度事件定义
   - 在关键步骤触发回调
   - UI 显示进度条

#### Phase 2: 性能优化（P1）
4. **Core 预加载** (新增 `core_preloader.cpp`)
   - 实现 `CorePreloader` 类
   - 集成到 `LibretroGamePage.ets`
   - 添加 NAPI 接口

5. **ROM 缓存** (新增 `rom_cache.cpp`)
   - 实现 `RomCache` 类
   - 集成到 `LoadGame` 流程

#### Phase 3: 体验优化（P2）
6. **平滑动画** (`LibretroGamePage.ets`)
   - 添加淡入淡出动画
   - 加载动画组件

7. **资源检测** (`engine_lifecycle_napi.cpp`)
   - 内存检查
   - 自动清理

### 4.2 性能影响评估

#### 内存占用
- **Core 预加载**: +30-100MB（3 个 Core）
- **ROM 缓存**: +10MB（最多）
- **总计**: +40-110MB

**风险**: 低端设备（2GB RAM）可能内存紧张
**缓解**: 动态调整预加载数量（低内存时只预加载 1 个）

#### CPU 占用
- **预加载线程**: 后台低优先级，不影响主线程
- **缓存查找**: O(1) 哈希表查找，<1ms

**风险**: 无明显风险

#### 存储占用
- **ROM 缓存**: 内存缓存，不占用存储
- **Core 预加载**: 不额外占用存储（只是提前加载）

**风险**: 无

### 4.3 测试验证方案

#### 单元测试
1. **CorePreloader 测试**
   - 预加载 3 个 Core，验证 LRU 淘汰
   - 预加载失败时的错误处理
   - 并发预加载的线程安全

2. **RomCache 测试**
   - 缓存命中/未命中
   - 缓存失效（文件修改）
   - 缓存大小限制

#### 集成测试
3. **切换速度测试**
   - 测量 10 次切换的平均时间
   - 对比优化前后（目标: 降低 50%）

4. **内存压力测试**
   - 在低内存设备上连续切换 20 次
   - 验证自动清理机制

5. **异常场景测试**
   - Core 加载失败时的恢复
   - ROM 读取失败时的恢复
   - 内存不足时的提示

#### 真机验证
6. **用户体验测试**
   - 进度提示是否清晰
   - 动画是否流畅
   - 错误提示是否友好

---

## 5. 风险与缓解

### 5.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 预加载的 Core 与实际使用的 Core 版本不一致 | 高 | 低 | 预加载时记录 Core 文件修改时间，切换时验证 |
| ROM 缓存占用过多内存 | 中 | 中 | 严格限制缓存大小（10MB）+ LRU 淘汰 |
| 进度回调频繁触发导致 UI 卡顿 | 低 | 低 | 限制回调频率（最多 100ms 一次） |
| 动态超时导致某些场景超时过短 | 中 | 中 | 保留最小超时（5 秒）+ 用户可配置 |

### 5.2 兼容性风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 旧版本 Core 不支持预加载 | 低 | 低 | 预加载失败时回退到正常加载 |
| 某些设备内存检测不准确 | 中 | 中 | 提供手动禁用预加载的选项 |

### 5.3 用户体验风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 预加载消耗电量 | 低 | 高 | 只在充电时或电量 >50% 时预加载 |
| 进度提示不准确（卡在 80%） | 中 | 中 | 使用真实进度而非估算 |

---

## 6. 实施优先级

### P0: 必须实现（M6 核心目标）
- ✅ 状态等待优化（条件变量）
- ✅ 超时分级（动态调整）
- ✅ 进度回调（UI 显示）

### P1: 高优先级（显著提升体验）
- ✅ Core 预加载（最近使用 + 浏览预测）
- ✅ ROM 缓存（小文件）
- ✅ 资源不足检测（内存检查）

### P2: 中优先级（锦上添花）
- ⚪ 平滑动画（淡入淡出）
- ⚪ 预测性加载（停留 >500ms）

### P3: 低优先级（可选）
- ⚪ Core 兼容性数据库
- ⚪ 用户可配置超时

---

## 7. 成功标准

### 7.1 性能指标
- **切换速度**: 典型场景从 2-5 秒降低到 0.5-2 秒（提升 50%-75%）
- **预加载命中率**: ≥70%（用户切换时 Core 已预加载）
- **ROM 缓存命中率**: ≥50%（小 ROM 切换）

### 7.2 用户体验指标
- **进度可见性**: 100% 的切换操作显示进度
- **错误友好性**: 所有错误都有明确的中文提示
- **动画流畅度**: 60fps 无卡顿

### 7.3 稳定性指标
- **切换成功率**: ≥95%（排除用户取消）
- **内存泄漏**: 连续切换 100 次，内存增长 <10MB
- **崩溃率**: 0 次（所有异常都有恢复机制）

---

## 8. 后续演进方向

### 8.1 智能预加载（M7+）
- 基于用户历史行为预测下一个要玩的游戏
- 机器学习模型：时间段 + 游戏类型 → 预加载优先级

### 8.2 增量更新（M8+）
- Core 版本更新时，只下载差异部分
- 减少更新时间和流量消耗

### 8.3 云端同步（M9+）
- 用户的 Core 使用偏好云端同步
- 新设备自动预加载常用 Core

---

## 9. 总结

### 9.1 设计完整性
- ✅ 考虑了 M0 的成果（单飞/取消/失败恢复）
- ✅ 有明确的异常处理策略（超时分级/资源检测）
- ✅ 有可行的实现路径（分 3 个 Phase）

### 9.2 关键优化点
1. **Core 预加载**: 节省 50%-80% 的 LoadCore 时间
2. **ROM 缓存**: 小 ROM 切换时间从 200ms 降到 <10ms
3. **状态等待优化**: 消除不必要的等待延迟
4. **进度回调**: 用户清楚知道当前进度
5. **超时分级**: 根据文件大小动态调整，减少误报

### 9.3 风险可控
- 内存占用: +40-110MB（可接受）
- 兼容性: 预加载失败时回退到正常加载
- 用户体验: 所有优化都有降级方案

### 9.4 下一步行动
1. **Phase 1 实施**: 状态等待优化 + 超时分级 + 进度回调（1-2 天）
2. **Phase 2 实施**: Core 预加载 + ROM 缓存（2-3 天）
3. **Phase 3 实施**: 平滑动画 + 资源检测（1-2 天）
4. **测试验证**: 单元测试 + 集成测试 + 真机验证（2-3 天）

**预计总工期**: 6-10 天

---

**文档版本**: 1.0
**作者**: Claude (Sonnet 4.6)
**审核状态**: 待审核
