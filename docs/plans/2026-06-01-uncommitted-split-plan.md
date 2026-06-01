# 未提交改动原子化 Commit 计划

**生成时间**: 2026-06-01
**仓库**: harmonyos-libretro-emulator
**分析范围**: 24 个已跟踪改动文件 + 18 个未跟踪文件（含 4 个 ets 新文件）
**改动规模**: 3255 insertions, 348 deletions
**横跨里程碑**: M2（错误治理）/ M5（Vulkan/GLES 验证）/ M6（核心/ROM 管理）/ M7（折叠屏适配）

---

## 文件主题归属分析

| 文件 | 主题 | 备注 |
|------|------|------|
| `entry/src/main/cpp/app/napi/engine_napi_common.h` | M2 | 新增 `MakeErrorResult()` 帮助函数 |
| `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp` | M2 + M6 | 错误结构化返回 + SwitchGame 进度回调 + 动态超时 |
| `entry/src/main/cpp/app/napi/engine_state_napi.cpp` | M2 | `SaveState` 失败从 null 改为 `MakeErrorResult` |
| `entry/src/main/cpp/app/napi/module_init.cpp` | M6 | 注册 `RegisterInputMappingNapi` |
| `entry/src/main/cpp/app/framework/plugin_manager.cpp` | M6 | `MapKeyCodeToJoypad` switch→unordered_map + `UpdateInputKeyMapping()` |
| `entry/src/main/cpp/common/file_security.cpp` | M6 | 合并 `temp_roms` 到 `roms/` 沙箱，更新注释 |
| `entry/src/main/cpp/common/file_security.h` | M6 | 同上，头文件注释同步 |
| `entry/src/main/cpp/platform/resource/temp_file_manager.cpp` | M6 | 新增 `roms/imported` / `roms/temp` 子目录初始化 |
| `entry/src/main/cpp/CMakeLists.txt` | M6 | 添加 `input_mapping_napi.cpp` 到构建 |
| `entry/src/main/ets/common/RuntimeSessionController.ets` | M6 | `SwitchProgressCallback` 类型 + 透传进度回调 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | M6 | 初始化 `InputMappingService` |
| `entry/src/main/ets/pages/LibretroGamePage.ets` | M2 + M7 | 引入 `ErrorCodes`/`FoldableLayouts`，折叠态检测，进度状态 |
| `entry/src/main/ets/pages/LibraryPage.ets` | M2 + M7 | 引入 `ErrorCodeUtils`，折叠态检测 + 详情面板 |
| `entry/src/main/ets/pages/SaveStatePage.ets` | M2 + M7 | `MakeErrorResult` 错误消息替换 + 折叠态布局 |
| `entry/src/main/ets/pages/CoreManagerPage.ets` | M7 | 折叠态三模式布局（Single/Dual/Triple） |
| `entry/src/main/ets/pages/InputLayoutPage.ets` | M7 | 折叠态检测 + DualFoldLayout / TripleFoldLayout |
| `entry/src/main/ets/pages/MultiplayerInputPage.ets` | M7 | 折叠态适配 |
| `entry/src/main/ets/pages/SettingsPage.ets` | M7 | `FoldableMode` 枚举 + 折叠布局 |
| `entry/src/main/ets/pages/ImportEntryPage.ets` | M7 | `foldDisplayMode` 监听 + InstructionPanel/PreviewPanel |
| `entry/src/main/ets/pages/OnboardingPage.ets` | M7 | 折叠屏适配 |
| `scripts/analyze_vulkan_logs.sh` | M5 | `set -euo pipefail` + grep `|| true` 防 exit 1 + 增强文档注释 |
| `scripts/quick_vulkan_check.sh` | M5 | 同 analyze，防脚本误 exit |
| `docs/plans/2026-05-31-m5-vulkan-verification-plan.md` | M5 | 追加常见问题排查（第 10 节，Swapchain/格式/性能等） |
| `.claude/scheduled_tasks.lock` | 杂项 | 废弃锁文件（deleted） |

### 未跟踪文件归属

| 文件 | 主题 |
|------|------|
| `entry/src/main/ets/common/ErrorCodes.ets` | M2（地基） |
| `entry/src/main/ets/common/EngineSteps.ets` | M2（地基） |
| `entry/src/main/ets/common/PerformanceTracker.ets` | M2（工具） |
| `entry/src/main/ets/pages/RomManagerPage.ets` | M6（ROM 管理） |
| `docs/napi-error-code-mapping.md` | M2（文档） |
| `docs/design/m6-core-manager-ui-spec.md` | M6（文档） |
| `docs/design/m6-core-switch-optimization.md` | M6（文档） |
| `docs/design/m6-rom-manager-ui-spec.md` | M6（文档） |
| `docs/design/m7-foldable-adaptation-checklist.md` | M7（文档） |
| `docs/design/m7-coremanagerpage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-inputlayoutpage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-librarypage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-libretrogamepage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-multiplayerinputpage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-savestatepage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-settingspage-foldable-adaptation-summary.md` | M7（文档） |
| `docs/design/m7-virtual-controller-optimization.md` | M7（文档） |
| `docs/plans/2026-05-31-execution-report.md` | 综合报告 |
| `docs/plans/2026-05-31-m5-gles-verification-checklist.md` | M5（文档） |
| `docs/plans/2026-05-31-m6-phase1-implementation-summary.md` | M6（文档） |
| `docs/plans/2026-05-31-remaining-tasks-breakdown.md` | 综合规划 |
| `docs/plans/2026-05-31-rom-manager-implementation.md` | M6（文档） |

---

## 有序 Commit 计划

### Commit 1（P0）— M2 错误治理地基：ArkTS 错误码枚举

**建议 commit message**:
```
feat(m2): add ErrorCodes, EngineSteps, PerformanceTracker ArkTS modules
```

**包含文件**:
- `entry/src/main/ets/common/ErrorCodes.ets` *(新文件)*
- `entry/src/main/ets/common/EngineSteps.ets` *(新文件)*
- `entry/src/main/ets/common/PerformanceTracker.ets` *(新文件)*
- `docs/napi-error-code-mapping.md` *(新文件)*

**理由**: 这三个模块是后续所有 M2 错误码引用的地基（LibraryPage/SaveStatePage/LibretroGamePage 均 import `ErrorCodes.ets`），必须最先进仓，否则后续 commit 的 import 会悬空。

**风险标注**: ⚠️未编译（3 个 .ets 新文件，quick_signals 不覆盖 ArkTS 编译，需 DevEco 复编验证）

---

### Commit 2（P0）— M2 错误治理地基：NAPI 层结构化错误返回

**建议 commit message**:
```
feat(m2): add MakeErrorResult helper and structured error returns in NAPI layer
```

**包含文件**:
- `entry/src/main/cpp/app/napi/engine_napi_common.h`
- `entry/src/main/cpp/app/napi/engine_state_napi.cpp`

**理由**: `engine_napi_common.h` 新增 `MakeErrorResult()` 内联函数；`engine_state_napi.cpp` 使用该函数替换 `SaveState` 的 null 返回。两文件高度耦合，同一 commit 保证头文件和第一批调用者同步入库。

**风险标注**: ⚠️NAPI-REVIEW（`app/napi/**` 改动，改变 NAPI 返回值类型 bool→object，需验证 ArkTS 侧兼容性）

---

### Commit 3（P0）— M2 错误治理：engine_lifecycle_napi 结构化错误 + 进度回调框架

**建议 commit message**:
```
feat(m2): migrate engine_lifecycle_napi to MakeErrorResult with error codes and progress TSFN
```

**包含文件**:
- `entry/src/main/cpp/app/napi/engine_lifecycle_napi.cpp`

**理由**: 改动量最大（273 行净增），涉及 `StartEngine`/`LoadCore`/`LoadRom`/`SwitchGameAsync` 四个函数的错误返回结构化改造，以及 TSFN 进度回调机制。内容单一聚焦，独立成 commit 方便回滚和 review。

**风险标注**: ⚠️NAPI-REVIEW（`app/napi/**` 改动；新增 `SwitchProgressCallback` TSFN，需验证 TSFN 生命周期管理正确性；`SwitchGameAsync` 参数位增加 1 个，需确认 ArkTS 侧调用兼容）

---

### Commit 4（P1）— M5 Vulkan/GLES 验证工具增强

**建议 commit message**:
```
fix(m5): harden vulkan log analysis scripts against grep exit-code failures
```

**包含文件**:
- `scripts/analyze_vulkan_logs.sh`
- `scripts/quick_vulkan_check.sh`
- `docs/plans/2026-05-31-m5-vulkan-verification-plan.md`
- `docs/plans/2026-05-31-m5-gles-verification-checklist.md` *(新文件)*

**理由**: 脚本改动（`set -euo pipefail` + grep `|| true` 防误 exit）和文档（Vulkan 计划第 10 节常见问题排查 + GLES 清单）同属 M5 验证基础设施，不涉及业务代码，可独立提交。

**风险标注**: 无

---

### Commit 5（P1）— M6 ROM 沙箱目录结构重组

**建议 commit message**:
```
refactor(m6): consolidate rom sandbox dirs from temp_roms/ to roms/{builtin,imported,temp}/
```

**包含文件**:
- `entry/src/main/cpp/common/file_security.cpp`
- `entry/src/main/cpp/common/file_security.h`
- `entry/src/main/cpp/platform/resource/temp_file_manager.cpp`

**理由**: 三个文件共同实现"将 `temp_roms/` 路径合并到 `roms/` 沙箱"这一单一重构，删除旧路径、新增 `roms/imported` 和 `roms/temp` 子目录，逻辑内聚。

**风险标注**: 无（C++ 非 NAPI 层，纯文件系统路径改动）

---

### Commit 6（P1）— M6 可定制输入映射：plugin_manager + CMake + module_init

**建议 commit message**:
```
feat(m6): add runtime-configurable key mapping via InputMappingNapi and UpdateInputKeyMapping
```

**包含文件**:
- `entry/src/main/cpp/app/framework/plugin_manager.cpp`
- `entry/src/main/cpp/app/napi/module_init.cpp`
- `entry/src/main/cpp/CMakeLists.txt`

**理由**: `plugin_manager.cpp` 将硬编码 switch→运行时可更新 unordered_map；`module_init.cpp` 注册新的 `InputMappingNapi`；`CMakeLists.txt` 添加新源文件。三者构成同一特性的一套变更，缺任何一个都不完整。

**风险标注**: ⚠️NAPI-REVIEW（`module_init.cpp` 属于 `app/napi/**`；新增 NAPI 接口注册；`input_mapping_napi.cpp` 已确认存在且为已跟踪文件）

---

### Commit 7（P1）— M6 核心切换进度透传：RuntimeSessionController + EntryAbility

**建议 commit message**:
```
feat(m6): thread SwitchProgressCallback through RuntimeSessionController and init InputMappingService
```

**包含文件**:
- `entry/src/main/ets/common/RuntimeSessionController.ets`
- `entry/src/main/ets/entryability/EntryAbility.ets`

**理由**: `RuntimeSessionController` 新增 `SwitchProgressCallback` 类型并透传给 NAPI，是 Commit 3（NAPI 进度 TSFN）的 ArkTS 对接层；`EntryAbility` 初始化 `InputMappingService` 与 Commit 6 的 NAPI 注册配套。两文件共属 M6 启动/初始化链路。

**风险标注**: ⚠️未编译（2 个 .ets 文件；`InputMappingService.ets` 已确认存在且为已跟踪文件）

---

### Commit 8（P1）— M6 ROM 管理器页面

**建议 commit message**:
```
feat(m6): add RomManagerPage for user ROM library management
```

**包含文件**:
- `entry/src/main/ets/pages/RomManagerPage.ets` *(新文件)*
- `docs/plans/2026-05-31-rom-manager-implementation.md` *(新文件)*
- `docs/design/m6-rom-manager-ui-spec.md` *(新文件)*

**理由**: 新页面 RomManagerPage 是 M6 ROM 管理里程碑的 UI 实现，与规范文档和实施报告同 commit，形成"代码+文档"原子对。

**风险标注**: ⚠️未编译（新页面 .ets，需 DevEco 复编 + 路由注册确认）

---

### Commit 9（P1）— M6 CoreManagerPage 以外的核心切换设计文档

**建议 commit message**:
```
docs(m6): add core-manager-ui-spec, core-switch-optimization design docs and phase1 summary
```

**包含文件**:
- `docs/design/m6-core-manager-ui-spec.md` *(新文件)*
- `docs/design/m6-core-switch-optimization.md` *(新文件)*
- `docs/plans/2026-05-31-m6-phase1-implementation-summary.md` *(新文件)*

**理由**: 纯文档，无代码风险，与 M6 代码改动文档化对齐，独立 docs commit 方便后续搜索和 review 隔离。

**风险标注**: 无

---

### Commit 10（P2）— M7 折叠屏适配地基：CoreManagerPage

**建议 commit message**:
```
feat(m7): add foldable display mode adaptation to CoreManagerPage (Single/Dual/Triple layout)
```

**包含文件**:
- `entry/src/main/ets/pages/CoreManagerPage.ets`
- `docs/design/m7-coremanagerpage-foldable-adaptation-summary.md` *(新文件)*

**理由**: CoreManagerPage 是折叠屏适配中改动最彻底的页面之一，引入三种布局模式。作为 M7 适配的第一个 commit 有参考价值，文档随代码提交。

**风险标注**: ⚠️未编译（.ets，折叠屏三模式布局需 DevEco Inspector 验证）

---

### Commit 11（P2）— M7 折叠屏适配：InputLayoutPage + MultiplayerInputPage

**建议 commit message**:
```
feat(m7): add foldable layout adaptation to InputLayoutPage and MultiplayerInputPage
```

**包含文件**:
- `entry/src/main/ets/pages/InputLayoutPage.ets`
- `entry/src/main/ets/pages/MultiplayerInputPage.ets`
- `docs/design/m7-inputlayoutpage-foldable-adaptation-summary.md` *(新文件)*
- `docs/design/m7-multiplayerinputpage-foldable-adaptation-summary.md` *(新文件)*

**理由**: 两个输入相关页面使用相同的 `detectFoldMode()` 模式（`display.getFoldStatus()` + 判断阈值），实现高度类似，同组提交减少 commit 数量。

**风险标注**: ⚠️未编译（.ets，折叠布局需 DevEco 复编）

---

### Commit 12（P2）— M7 折叠屏适配：LibraryPage（含 M2 ErrorCode 集成）

**建议 commit message**:
```
feat(m7): add foldable layout and ErrorCodeUtils integration to LibraryPage
```

**包含文件**:
- `entry/src/main/ets/pages/LibraryPage.ets`
- `docs/design/m7-librarypage-foldable-adaptation-summary.md` *(新文件)*

**理由**: LibraryPage 同时引入 M7 折叠态检测+详情面板和 M2 ErrorCodeUtils，两个改动交织在同一文件中无法干净分离，合并为一个 commit（依赖 Commit 1 的 ErrorCodes.ets 已入库）。

**风险标注**: ⚠️未编译（.ets）

---

### Commit 13（P2）— M7 折叠屏适配：LibretroGamePage（含 M2 ErrorCode + M6 进度状态）

**建议 commit message**:
```
feat(m7): add foldable layout, ErrorCodes, and switch progress state to LibretroGamePage
```

**包含文件**:
- `entry/src/main/ets/pages/LibretroGamePage.ets`
- `docs/design/m7-libretrogamepage-foldable-adaptation-summary.md` *(新文件)*

**理由**: LibretroGamePage 是最复杂的页面，同时包含 M7（折叠态检测+`FoldableLayouts` 组件引入）、M2（`ErrorCodeUtils`）和 M6（`switchProgress`/`switchProgressText` 状态）三个主题改动，因为都集中在同一文件无法再拆分。

**风险标注**: ⚠️未编译（.ets，`FoldableLayouts.ets` 已确认存在且为已跟踪文件）

---

### Commit 14（P2）— M7 折叠屏适配：SaveStatePage（含 M2 ErrorCode）

**建议 commit message**:
```
feat(m7): add foldable layout and ErrorCodes integration to SaveStatePage
```

**包含文件**:
- `entry/src/main/ets/pages/SaveStatePage.ets`
- `docs/design/m7-savestatepage-foldable-adaptation-summary.md` *(新文件)*

**理由**: SaveStatePage 同时包含 M7 折叠适配（三种 layout）和 M2 错误码替换（`SAVE_STATE_FAILED`→`ErrorCodeUtils.getUserMessage`），改动内聚于单文件。

**风险标注**: ⚠️未编译（.ets）

---

### Commit 15（P2）— M7 折叠屏适配：SettingsPage + OnboardingPage + ImportEntryPage

**建议 commit message**:
```
feat(m7): add foldable layout adaptation to SettingsPage, OnboardingPage, and ImportEntryPage
```

**包含文件**:
- `entry/src/main/ets/pages/SettingsPage.ets`
- `entry/src/main/ets/pages/OnboardingPage.ets`
- `entry/src/main/ets/pages/ImportEntryPage.ets`
- `docs/design/m7-settingspage-foldable-adaptation-summary.md` *(新文件)*

**理由**: 三个页面的折叠屏适配改动规模适中（SettingsPage 272 行、ImportEntryPage 172 行、OnboardingPage 93 行），都是纯 M7 折叠布局改动无交叉主题，合并一个 commit 控制总 commit 数量。

**风险标注**: ⚠️未编译（.ets）

---

### Commit 16（P3）— M7 折叠屏适配：虚拟手柄优化设计文档 + 总 checklist

**建议 commit message**:
```
docs(m7): add foldable adaptation checklist and virtual controller optimization design
```

**包含文件**:
- `docs/design/m7-foldable-adaptation-checklist.md` *(新文件)*
- `docs/design/m7-virtual-controller-optimization.md` *(新文件)*

**理由**: 纯文档，无代码风险，放最后提交。

**风险标注**: 无

---

### Commit 17（P3）— 综合规划文档 + 杂项清理

**建议 commit message**:
```
docs: add M2/M5/M6/M7 execution report and task breakdown; remove stale lock file
```

**包含文件**:
- `docs/plans/2026-05-31-execution-report.md` *(新文件)*
- `docs/plans/2026-05-31-remaining-tasks-breakdown.md` *(新文件)*
- `.claude/scheduled_tasks.lock` *(deleted)*

**理由**: 综合执行报告和任务拆解文档属于跨里程碑的规划层，不依附于某个特定里程碑，放最后方可引用前面所有 commit 完成情况。同时清理废弃锁文件。

**风险标注**: 无

---

## 提交顺序总览

```
P0（地基，先提）
  ↓
  Commit 1  feat(m2): ArkTS ErrorCodes/EngineSteps/PerformanceTracker [⚠️未编译]
  Commit 2  feat(m2): MakeErrorResult + engine_state_napi [⚠️NAPI-REVIEW]
  Commit 3  feat(m2): engine_lifecycle_napi 结构化错误 + TSFN 进度 [⚠️NAPI-REVIEW]
  Commit 4  fix(m5): Vulkan 脚本防误 exit + GLES checklist
  Commit 5  refactor(m6): ROM 沙箱目录结构重组

P1（功能主体）
  ↓
  Commit 6  feat(m6): InputMappingNapi + plugin_manager + CMake [⚠️NAPI-REVIEW]
  Commit 7  feat(m6): RuntimeSessionController 进度透传 + EntryAbility [⚠️未编译]
  Commit 8  feat(m6): RomManagerPage 新页面 [⚠️未编译]
  Commit 9  docs(m6): 设计文档 + phase1 总结

P2（叶子功能）
  ↓
  Commit 10  feat(m7): CoreManagerPage 折叠适配 [⚠️未编译]
  Commit 11  feat(m7): InputLayoutPage + MultiplayerInputPage 折叠适配 [⚠️未编译]
  Commit 12  feat(m7): LibraryPage 折叠适配 [⚠️未编译]
  Commit 13  feat(m7): LibretroGamePage 折叠适配 [⚠️未编译]
  Commit 14  feat(m7): SaveStatePage 折叠适配 [⚠️未编译]
  Commit 15  feat(m7): SettingsPage + OnboardingPage + ImportEntryPage [⚠️未编译]

P3（收尾）
  ↓
  Commit 16  docs(m7): checklist + 虚拟手柄优化设计
  Commit 17  docs: 综合报告 + 废弃锁文件清理
```

---

## 前置核查结论

2026-06-01 复核确认以下文件均存在且为已跟踪文件，不构成拆 commit 前置阻断：

- `entry/src/main/cpp/app/napi/input_mapping_napi.cpp`
- `entry/src/main/ets/common/InputMappingService.ets`
- `entry/src/main/ets/components/FoldableLayouts.ets`

---

## 摘要

| 维度 | 数量 |
|------|------|
| 总 commit 数 | **17 个** |
| 涉及 NAPI review 的 commit | **3 个**（Commit 2、3、6）|
| 涉及未编译 .ets 的 commit | **8 个**（Commit 1、7、8、10、11、12、13、14、15；⚠️15 含 3 页面）|
| 纯文档 commit | **3 个**（Commit 9、16、17）|
| 无风险 commit | **2 个**（Commit 4、5）|
| 里程碑覆盖 | M2 × 3、M5 × 1、M6 × 4、M7 × 6、综合 × 3 |
