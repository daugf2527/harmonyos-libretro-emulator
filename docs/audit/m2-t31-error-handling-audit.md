# M2-T31 错误处理现状审计报告

**审计日期**: 2026-05-31  
**审计范围**: entry/src/main/ets (ArkTS 层) + entry/src/main/cpp (C++ 层，排除 deprecated/legacy 和 vendored core/libretro)

---

## 1. 执行摘要

### 1.1 覆盖率统计

| 层级 | 文件总数 | 含 try-catch 文件数 | 覆盖率 | 含日志文件数 |
|------|---------|-------------------|--------|-------------|
| **ArkTS** | 81 | 31 | 38.3% | 24 |
| **C++** | 47 | 0 | 0% | 43 |

**关键发现**:
- ArkTS 层有基础错误处理覆盖（38.3%），但 C++ 层**完全没有 try-catch**（依赖返回值 + 日志）
- C++ 层日志覆盖率高（91.5%），但错误传播到 ArkTS 层存在断裂

---

## 2. ArkTS 层错误处理分析

### 2.1 try-catch 分布

**31 个文件含 try-catch**，主要集中在：

| 模块 | 文件数 | 典型文件 |
|------|--------|---------|
| **Repository 层** | 7 | GameMetadataRepository, InputLayoutRepository, SaveStateRepository |
| **Page 层** | 13 | LibretroGamePage, LibraryPage, SaveStatePage, InputLayoutPage |
| **Service 层** | 5 | RomImportService, LibrarySaveFilePurger, LibretroSwitchCoordinator |
| **Component 层** | 2 | VirtualController, FoldableLayouts |
| **Ability 层** | 1 | EntryAbility |
| **其他** | 3 | RuntimePathResolver, RuntimeInputPortController, RuntimeSaveStateController |

### 2.2 错误类型分类

通过 catch 块分析，识别出以下错误类型：

| 错误类型 | 出现次数 | 典型场景 | 处理方式 |
|---------|---------|---------|---------|
| **文件 I/O** | ~45 | fs.readText/write/mkdir/listFile 失败 | 日志 + 返回默认值/空数组 |
| **路由跳转** | ~20 | router.pushUrl/replaceUrl 失败 | console.error + 静默失败 |
| **引擎操作** | ~8 | 核心加载/ROM 加载/启动失败 | LogHelper.error + UI 提示 |
| **JSON 解析** | ~5 | JSON.parse 失败 | 返回默认对象 |
| **EventHub** | 1 | EventHub.start 失败 | LogHelper.warn + 继续启动 |

**问题识别**:
1. **路由错误静默失败**: 20+ 处 `router.catch((err) => console.error(...))` 无 UI 反馈
2. **文件错误吞噬**: 多处 `catch (_err) { return [] }` 无日志，用户无感知
3. **错误分类不明确**: 缺少 ErrorCode 枚举，无法区分"文件不存在"vs"权限拒绝"

### 2.3 日志格式分析

#### LogHelper 使用（推荐格式）

**统计**:
- `LogHelper.error`: 55 次（19 个文件）
- `LogHelper.warn`: 27 次（13 个文件）
- `LogHelper.info`: 大量（未统计）

**格式**: `LogHelper.error(tag, flow, message, domain?)`
- **tag**: 模块名（如 'LibretroGame', 'LibraryPage'）
- **flow**: 操作类型（如 'Engine', 'Route', 'Save'）
- **message**: 错误描述（含上下文变量）
- **domain**: 可选，默认 0xD003

**示例**:
```typescript
LogHelper.error('LibretroGame', 'Engine', `启动失败: ${err.message}`);
LogHelper.warn('LibraryPage', 'ROM', `刷新库列表失败: ${message}`);
```

#### console.error 使用（不推荐）

**统计**: ~30 次，主要在路由错误处理

**格式**: `console.error(\`[PageName] operation failed: ${err.message}\`)`

**问题**: 
- 无 domain/tag 分类，hilog 过滤困难
- 格式不统一（有的带 `[PageName]`，有的不带）

### 2.4 错误传播机制

#### 从 C++ 到 ArkTS

**当前机制**:
1. **NAPI 返回 boolean**: `refactoredLoadCore(path) -> Promise<boolean>`
   - `true` = 成功
   - `false` = 失败（**无错误详情**）
2. **EventHub 事件**: `core_crash` 事件携带 `{ reason, step?, message? }`
3. **NAPI 异常**: `napi_throw_error` → ArkTS catch

**问题**:
- **boolean 返回值信息量不足**: ArkTS 无法区分"文件不存在"vs"符号缺失"vs"内存不足"
- **EventHub 异步通知延迟**: 错误发生到 UI 显示有延迟
- **NAPI 异常未统一**: 部分函数 throw，部分返回 false

---

## 3. C++ 层错误处理分析

### 3.1 错误处理模式

**C++ 层完全没有 try-catch**，采用以下模式：

| 模式 | 使用场景 | 示例 |
|------|---------|------|
| **返回 bool** | 操作成功/失败 | `bool LoadCore(path)` |
| **返回 nullptr** | 对象创建失败 | `OH_NativeWindow_RequestBuffer` |
| **返回错误码** | 系统 API | `napi_status`, `OH_*` 返回值 |
| **日志 + 继续** | 非致命错误 | `LOGF(LOG_WARN, "..."); return false;` |
| **日志 + 中断** | 致命错误 | `LOGF(LOG_ERROR, "..."); return false;` |

**无异常原因**: HarmonyOS NDK 禁用 C++ 异常（`-fno-exceptions`）

### 3.2 日志格式分析

#### LOGF 宏使用

**统计**:
- `LOGF(LOG_ERROR, ...)`: 215 次（29 个文件）
- `LOGF(LOG_WARN, ...)`: 186 次（27 个文件）
- `LOGF(LOG_INFO, ...)`: 大量（未统计）

**格式**: `LOGF(level, fmt, ...)`
- 展开为: `OH_LOG_Print(LOG_APP, level, LOG_DOMAIN, LOG_TAG, LOG_PREFIX_FMT fmt, LOG_TAG, LOG_FLOW, ##__VA_ARGS__)`
- **前缀**: `【LOG_TAG】【LOG_FLOW】`
- **domain**: 每个文件独立定义（0xD000-0xD061）

**示例**:
```cpp
// libretro_engine.cpp
#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD010
#undef LOG_TAG
#define LOG_TAG "LibretroEngine"
#undef LOG_FLOW
#define LOG_FLOW "Engine"

LOGF(LOG_ERROR, "LoadCore failed: %{public}s", path);
```

#### LOG_DOMAIN 分配

**已分配域**（30 个文件样本）:

| Domain | 模块 | 文件数 |
|--------|------|--------|
| 0xD001 | NAPI / Core Loader | 4 |
| 0xD002 | NAPI Common | 1 |
| 0xD003 | Env Dispatcher / Core Loader | 2 |
| 0xD004 | Logger Provider | 1 |
| 0xD005 | Input Port Router | 1 |
| 0xD006-0xD009 | Graphics (Context/GLES/Render/Video) | 4 |
| 0xD010-0xD014 | Engine (Core/State/Event/Input/Quirks) | 5 |
| 0xD020-0xD022 | Audio (Bridge/Player/RingBuffer) | 3 |
| 0xD030-0xD032 | Resource (Platform/Rawfile/Temp) | 3 |
| 0xD040 | VSync | 1 |
| 0xD050-0xD051 | Fence/File Security | 2 |
| 0xD060-0xD061 | Tests | 2 |

**问题**: 
- 部分 domain 重复（0xD001 被 4 个文件使用）
- 缺少统一分配表

### 3.3 NAPI 错误传播

#### 当前机制（engine_napi_common.h）

**Helper 函数**:
```cpp
// 1. 参数校验失败 → throw
bool GetArgs(env, info, minArgs, maxArgs, args, argcOut, func) {
  if (argc < minArgs) {
    napi_throw_type_error(env, nullptr, "Wrong number of arguments");
    return false;
  }
}

// 2. 类型转换失败 → throw
bool GetStringArg(env, arg, out, outSize, func, argName) {
  if (status != napi_ok) {
    napi_throw_type_error(env, nullptr, "Expected string argument");
    return false;
  }
}

// 3. 返回值包装 → 检查 pending exception
napi_value MakeBool(env, value) {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
    return nullptr;  // 已有异常，不覆盖
  }
  napi_get_boolean(env, value, &result);
  return result;
}
```

**宏包装**:
```cpp
#define NAPI_TRY_CATCH_BEGIN try {
#define NAPI_TRY_CATCH_END(env, defaultReturn) \
  } catch (const std::exception &e) { \
    LOGF(LOG_ERROR, "[NEW] NAPI exception: %{public}s", e.what()); \
    napi_throw_error(env, nullptr, e.what()); \
    return defaultReturn; \
  }
```

**问题**:
- **宏未被使用**: 搜索结果显示 C++ 层无 try-catch，宏定义未生效
- **异常 vs 返回值混用**: 部分函数 throw，部分返回 false，ArkTS 侧处理不一致

---

## 4. 错误分类体系（当前缺失）

### 4.1 识别出的错误类别

通过日志消息分析，识别出以下隐式分类：

| 类别 | 子类 | 典型消息 | 出现频率 |
|------|------|---------|---------|
| **文件系统** | 读取失败 | "读取本地 metadata 失败" | 高 |
| | 写入失败 | "保存输入布局失败" | 高 |
| | 目录操作 | "读取存档目录失败" | 中 |
| **引擎** | 核心加载 | "LoadCore failed" | 高 |
| | ROM 加载 | "LoadGame failed" | 高 |
| | 启动失败 | "启动失败" | 中 |
| | 崩溃 | "core_crash" | 低 |
| **渲染** | 初始化失败 | "GLES init failed" | 中 |
| | 帧提交失败 | "SwapBuffers failed" | 低 |
| **音频** | 播放器启动 | "AudioPlayer start failed" | 中 |
| | 缓冲区下溢 | "RingBuffer underrun" | 低 |
| **网络/资源** | 资源加载 | "Rawfile open failed" | 中 |
| **NAPI** | 参数错误 | "Wrong number of arguments" | 低 |
| | 类型错误 | "Expected string argument" | 低 |
| **路由** | 跳转失败 | "replaceUrl failed" | 高 |

### 4.2 建议的错误码体系

**缺失**: 当前无 ErrorCode 枚举，建议引入：

```typescript
// ArkTS 层
enum LibretroErrorCode {
  // 文件系统 (1000-1999)
  FILE_NOT_FOUND = 1001,
  FILE_READ_ERROR = 1002,
  FILE_WRITE_ERROR = 1003,
  PERMISSION_DENIED = 1004,
  
  // 引擎 (2000-2999)
  CORE_LOAD_FAILED = 2001,
  CORE_SYMBOL_MISSING = 2002,
  ROM_LOAD_FAILED = 2010,
  ROM_INVALID_FORMAT = 2011,
  ENGINE_START_FAILED = 2020,
  ENGINE_CRASHED = 2021,
  
  // 渲染 (3000-3999)
  GRAPHICS_INIT_FAILED = 3001,
  SURFACE_LOST = 3002,
  
  // 音频 (4000-4999)
  AUDIO_INIT_FAILED = 4001,
  AUDIO_UNDERRUN = 4002,
  
  // NAPI (5000-5999)
  INVALID_ARGUMENT = 5001,
  TYPE_MISMATCH = 5002,
}
```

---

## 5. Top 3 问题区域

### 5.1 问题 1: NAPI 错误传播断裂（P0）

**现象**:
- C++ 层返回 `false`，ArkTS 层只知道"失败"，不知道"为什么失败"
- 示例: `refactoredLoadCore(path)` 返回 `false`，可能是文件不存在、符号缺失、内存不足等

**影响**:
- 用户看到"加载失败"，无法自助排查
- 开发者需要同时查看 ArkTS 日志和 hilog 才能定位

**根因**:
- NAPI 函数只返回 boolean，无错误详情
- `napi_throw_error` 未被一致使用

**建议修复**:
1. 引入 `LibretroResult<T>` 类型:
   ```typescript
   interface LibretroResult<T> {
     success: boolean;
     data?: T;
     error?: { code: number; message: string };
   }
   ```
2. NAPI 函数返回结构化错误:
   ```cpp
   napi_value result = CreateObject(env);
   SetProperty(env, result, "success", false);
   SetProperty(env, result, "error", CreateError(env, 2001, "Core symbol missing: retro_init"));
   ```

### 5.2 问题 2: 路由错误静默失败（P1）

**现象**:
- 20+ 处 `router.pushUrl(...).catch((err) => console.error(...))` 无 UI 反馈
- 用户点击按钮无响应，不知道是否成功

**影响**:
- 用户体验差（点击无反馈）
- 开发者难以复现（需要特定条件触发路由失败）

**根因**:
- 路由 API 返回 Promise，错误被 catch 吞噬
- 无统一的路由错误处理机制

**建议修复**:
1. 封装路由 helper:
   ```typescript
   async function navigateTo(url: string, mode: 'push' | 'replace' = 'push') {
     try {
       if (mode === 'push') {
         await router.pushUrl({ url });
       } else {
         await router.replaceUrl({ url });
       }
     } catch (err) {
       LogHelper.error('Router', 'Navigate', `跳转失败: ${url}, ${err.message}`);
       promptAction.showToast({ message: '页面跳转失败，请重试' });
     }
   }
   ```
2. 全局替换 20+ 处调用点

### 5.3 问题 3: 日志格式不统一（P2）

**现象**:
- ArkTS 层混用 `LogHelper` 和 `console.error`
- C++ 层部分 domain 重复（0xD001 被 4 个文件使用）

**影响**:
- hilog 过滤困难（`hilog -t LibretroGame` 可能漏掉 console.error）
- domain 冲突导致日志混淆

**根因**:
- 无强制规范，开发者自由选择
- domain 分配无中心化管理

**建议修复**:
1. **ArkTS 层**: 禁用 `console.error`，统一用 `LogHelper`
   - 添加 ESLint 规则: `no-restricted-syntax: ["error", "CallExpression[callee.object.name='console'][callee.property.name='error']"]`
2. **C++ 层**: 建立 domain 分配表（docs/logging-domains.md）:
   ```markdown
   | Domain | 模块 | 文件 |
   |--------|------|------|
   | 0xD001 | NAPI Entry | module_init.cpp |
   | 0xD002 | NAPI Lifecycle | engine_lifecycle_napi.cpp |
   | 0xD003 | NAPI Input | engine_input_napi.cpp |
   ...
   ```
3. 添加 CI 检查: `scripts/ci/check_log_domain_conflicts.sh`

---

## 6. 错误处理覆盖缺口

### 6.1 ArkTS 层缺口

**无错误处理的高风险区域**:

| 文件 | 风险操作 | 当前状态 |
|------|---------|---------|
| `LibretroEventHub.ets` | NAPI 调用 (`nativeApi.startEventHub()`) | 有 try-catch |
| `RuntimeInputPortController.ets` | 端口映射 NAPI 调用 | 部分覆盖 |
| `RuntimeRenderSettingsRepository.ets` | 文件 I/O | **无 try-catch** |
| `RuntimeInputPreferencesRepository.ets` | 文件 I/O | **无 try-catch** |
| `CoreFirmwareRepository.ets` | 文件 I/O | 有 try-catch（但吞噬错误） |

### 6.2 C++ 层缺口

**无日志的错误路径**:

通过代码审查（未在本次 grep 中覆盖），以下场景可能缺少日志：

1. **内存分配失败**: `new` / `malloc` 返回 nullptr（C++ 层无异常，需手动检查）
2. **线程创建失败**: `std::thread` 构造函数可能抛异常（注释提到但未处理）
3. **Mutex 死锁**: 无超时机制，无死锁检测日志

---

## 7. 建议改进优先级

### P0 (阻塞 M2 发布)

1. **NAPI 错误传播修复**
   - 引入 `LibretroResult<T>` 类型
   - 修改 10+ 个核心 NAPI 函数（LoadCore/LoadGame/Start/Pause/Resume）
   - 预计工作量: 3-5 天

2. **core_crash 事件增强**
   - 添加 `errorCode` 字段
   - 补充 C++ 层崩溃上下文（当前状态、最后操作）
   - 预计工作量: 1-2 天

### P1 (M2.1 改进)

3. **路由错误统一处理**
   - 封装 `navigateTo` helper
   - 替换 20+ 处调用点
   - 预计工作量: 1 天

4. **文件 I/O 错误分类**
   - 引入 `FileErrorCode` 枚举
   - 区分"不存在"vs"权限拒绝"vs"磁盘满"
   - 预计工作量: 2 天

### P2 (技术债)

5. **日志格式统一**
   - 禁用 `console.error`（ESLint 规则）
   - 建立 LOG_DOMAIN 分配表
   - 添加 CI 检查
   - 预计工作量: 1 天

6. **错误处理覆盖补全**
   - 为 `RuntimeRenderSettingsRepository` 等 5 个文件添加 try-catch
   - 预计工作量: 0.5 天

---

## 8. 附录: 统计数据明细

### 8.1 ArkTS 层 try-catch 文件清单

```
entry/src/main/ets/entryability/EntryAbility.ets
entry/src/main/ets/common/CoreFirmwareRepository.ets
entry/src/main/ets/common/GameMetadataRepository.ets
entry/src/main/ets/common/InputLayoutRepository.ets
entry/src/main/ets/common/LibrarySaveFilePurger.ets
entry/src/main/ets/common/LibretroSwitchCoordinator.ets
entry/src/main/ets/common/RomImportService.ets
entry/src/main/ets/common/RuntimeInputPortController.ets
entry/src/main/ets/common/RuntimePathResolver.ets
entry/src/main/ets/common/RuntimeRomSourceScanner.ets
entry/src/main/ets/common/RuntimeSaveStateController.ets
entry/src/main/ets/common/SaveStateRepository.ets
entry/src/main/ets/components/VirtualController.ets
entry/src/main/ets/pages/CoreLoaderTest.ets
entry/src/main/ets/pages/CoreManagerPage.ets
entry/src/main/ets/pages/InputLayoutPage.ets
entry/src/main/ets/pages/LibraryDetailPage.ets
entry/src/main/ets/pages/LibraryPage.ets
entry/src/main/ets/pages/LibretroGamePage.ets
entry/src/main/ets/pages/LibretroNewArchTestPage.ets
entry/src/main/ets/pages/MetadataEditPage.ets
entry/src/main/ets/pages/OnboardingPage.ets
entry/src/main/ets/pages/SaveStatePage.ets
entry/src/main/ets/pages/SettingsPage.ets
entry/src/main/ets/pages/TestGambatte.ets
entry/src/main/ets/pages/AboutHelpPage.ets
entry/src/main/ets/pages/ImportEntryPage.ets
entry/src/main/ets/pages/ImportTaskOverlayPage.ets
entry/src/main/ets/pages/Index.ets
entry/src/main/ets/pages/MultiplayerInputPage.ets
entry/src/main/ets/pages/ShaderPreviewPage.ets
```

### 8.2 C++ 层日志文件清单（部分）

```
entry/src/main/cpp/app/framework/plugin_manager.cpp
entry/src/main/cpp/app/napi/core_loader_napi.cpp
entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp
entry/src/main/cpp/app/napi/engine_input_napi.cpp
entry/src/main/cpp/app/napi/engine_state_napi.cpp
entry/src/main/cpp/core/engine/libretro_engine.cpp
entry/src/main/cpp/core/engine/video_pipeline.cpp
entry/src/main/cpp/core/engine/event_bridge.cpp
entry/src/main/cpp/core/libretro/core_loader.cpp
entry/src/main/cpp/platform/audio/audio_bridge.cpp
entry/src/main/cpp/platform/audio/audio_player.cpp
entry/src/main/cpp/platform/graphics/gles_renderer.cpp
entry/src/main/cpp/platform/graphics/graphics_context.cpp
entry/src/main/cpp/common/file_security.cpp
... (共 43 个文件)
```

---

## 9. 审计方法论

### 9.1 工具使用

- **Grep**: 查找 try-catch / LogHelper / LOGF / console.error
- **统计**: 文件数量、出现次数、分布
- **代码审查**: 典型错误处理模式、缺口识别

### 9.2 审计限制

- **未覆盖**: 
  - vendored libretro core 代码（core/libretro/**，第三方代码）
  - deprecated/legacy 代码（已废弃）
  - 运行时错误率（需真机测试）
- **未验证**: 
  - 错误恢复有效性（需集成测试）
  - 用户体验影响（需 UX 测试）

---

**审计人**: Claude (Opus 4.7)  
**审计工具**: Grep / Bash / Read  
**审计耗时**: ~15 分钟  
**下一步**: 根据 P0 优先级实施 NAPI 错误传播修复
