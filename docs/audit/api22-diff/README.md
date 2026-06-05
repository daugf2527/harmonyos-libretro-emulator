# API 22 三源差异审计 — 总览 / 差异性结论

> 审计日期: 2026-06-05 · 范围: **C++ 原生层** `entry/src/main/cpp/`（排除 `core/libretro/**`）+ **ArkTS 层** `entry/src/main/ets/`
> 方法: 并行多 agent（Opus）+ 主 AI 综合 + audit-evaluator 独立复核 · 子文件见下方索引
>
> **两层结论一句话**：C++ 原生层对 API22 **零兼容性缺陷**；ArkTS 层 API 用法也全对，但**用法层挖到 2 个真问题**（NAPI 返回类型 SSOT 谎报 + orphan 模块对象 spread），均需修。

## 三源定义

| 源 | 内容 | 路径 |
|----|------|------|
| **A 本地代码** | 本仓 C++ 实际调用的 `OH_*` Native API | `entry/src/main/cpp/`（19 文件，267 处调用） |
| **B 本机 SDK header** | **权威真值源** | `D:\Program Files\DevEco Studio\sdk\default\openharmony\native\sysroot\usr\include\` |
| **C 官方 API22 文档** | 交叉验证 since/deprecated 措辞 | developer.huawei.com |

## ⚠️ 关键事实 — 决定"差异"的口径

**本机 SDK header version = 6.0.2.130 / apiVersion = 22，即本机 SDK 本身就是 API22。**
`build-profile.json5`: `compatibleSdkVersion = targetSdkVersion = 6.0.2(22)`。

→ 「源B 本机SDK」与「源C API22」**基本同源**，真正的差异面只在 **「源A 本地用法 vs API22 header 契约」**。
→ header 里 `__attribute__((__availability__(ohos, introduced=N.0.0)))` = since 真值，`@deprecated` 注释 = deprecated 真值，无需 web 补全（源 C 仅对关键 deprecated 符号抽查交叉验证）。

---

## C++ 原生层 — 四子系统汇总

| 子系统 | 文件 | 实际调用符号 | 真实bug | 缺失 | 签名不匹配 | deprecated误用 | 最高since | 状态 |
|--------|------|:---:|:---:|:---:|:---:|:---:|:---:|------|
| 音频 OHAudio | [audio-subsystem.md](audio-subsystem.md) | 37 | 0 | 0 | 0 | 0 | 20 | ✅ 完成+第三方独立复核 |
| XComponent/输入 | [xcomponent-input.md](xcomponent-input.md) | 30 | 0 | 0 | 0 | 0 | 14/18 | ✅ 完成 |
| 图形/窗口/同步 | [graphics-window-sync.md](graphics-window-sync.md) | 24 | 0 | 0 | 0 | 0 | 20 | ✅ 完成+主AI抽验 |
| 资源/文件IO/日志 | [resource-system.md](resource-system.md) | 13 | 0 | 0 | 0 | 0 | 12 | ✅ 完成 |
| **C++ 合计** | | **104** | **0** | **0** | **0** | **0** | **20** | |

> 符号口径：`104` = 各子系统"实际调用"符号去重计数；全仓 `grep` 到 `110` distinct `OH_*` 含 include 头文件名、注释提及、未用符号的差异。
> [audio-resource-system.md](audio-resource-system.md) 为早期重复草稿，已标废弃。

---

## ArkTS 层 — 三子系统汇总（`arkts/` 子目录）

> ArkTS 侧用 8 个 Kit、69 处 import。SDK 真值源 = `…\openharmony\ets\api\@ohos.*.d.ts`（JSDoc `@since`/`@deprecated`）。
> **ArkTS 与 C++ 的关键区别**：符号"存在性/签名"由 ArkTS **编译期类型检查**保证（用错符号 .ets 直接编译失败），故"缺失/签名不匹配"风险结构性低于 C++。真实风险面 = deprecated（编译期仅警告）+ **用法层兼容坑**（本仓历史多次踩，是 ArkTS 审计重点）。

| 子系统 | 文件 | 实际调用符号 | API兼容差异 | deprecated误用 | 用法层真问题 | 状态 |
|--------|------|:---:|:---:|:---:|:---:|------|
| AbilityKit + ArkUI | [arkts/ability-arkui.md](arkts/ability-arkui.md) | 18 | 0 | 0 | 0 | ✅ 完成 |
| CoreFileKit + ArkData | [arkts/file-data.md](arkts/file-data.md) | 22 | 0 | 0 | 0 | ✅ 完成（主AI接手） |
| 4小Kit + **用法坑专项** | [arkts/misc-and-usage.md](arkts/misc-and-usage.md) | 5 | 0 | 0 | **2** | ✅ 完成 |
| **ArkTS 合计** | | **45** | **0** | **0** | **2** | |

> ArkTS 侧 API 兼容性同样 **0 差异 / 0 deprecated**：`display`/`window` 主动避开 4 个 `@deprecated since 9` 老接口（用 `getLastWindow`/`setWindowKeepScreenOn`/`getFoldStatus`）；`@ohos.file.fs` 整模块零 deprecated；RDB `securityLevel` 必填项已正确提供。
> **但用法层专项扫出 2 个真问题**（见下）——这是本轮唯一实质 finding，C++ 4 域 + ArkTS API 兼容性全绿后，问题全部集中在 ArkTS 用法层。

---

## 🔴 ArkTS 用法层 2 个真问题（已主AI亲验代码实物，非 agent 转述）

### 问题 1 [HIGH] — NAPI 返回类型 SSOT 谎报 → 生产路径"失败假报成功"

- **C++ 实物**（裁决真值）：`MakeErrorResult`（`engine_napi_common.h:434`）用 `MakeObject` + `SetNamedProperty("success",…)` 返回**结构对象** `{success, errorCode, message}`。`refactoredStartEngine`/`LoadCore`/`LoadRom` 全部 `return MakeErrorResult(...)`（`engine_lifecycle_napi.cpp` L365/369/...）。
- **SSOT 谎报**：`entry/src/main/cpp/types/libentry/index.d.ts` L36/42/43 声明这 3 个为 **`() => boolean`** —— 与 C++ 实物矛盾。`AGENTS.md` NAPI Inventory 表同步沿用了错误签名。
- **后果（已亲验）**：生产路径 `LibretroSwitchCoordinator.ets` L135/147/168 信了 SSOT，写 `if (!refactoredStartEngine())`。对象恒 truthy → `!对象` 恒 false → **引擎启动/加载真失败时，这几行 `start_engine_failed`/`load_core_failed` 错误分支永不执行**（死分支）。测试页 `LibretroNewArchTestPage.ets`/`TestGambatte.ets` 反而正确（本地声明 `NapiErrorResult` 读 `.success`）。
- **当前未爆原因**：L152 紧跟的 `refactoredWaitForStateAsync`（返回真 boolean）状态机超时兜住了大部分失败 → 真失败被延迟到 WaitForState 超时才暴露、错误归因偏移，但不是没事。
- **同类历史**：项目 memory `feedback_napi_return_type_lie_hides_bug` 记录过完全一致的坑。
- **修复方向**（需你拍板，本审计未改码）：要么把 `index.d.ts` + `AGENTS.md` 3 处签名改回 `=> NapiErrorResult`（与 C++ 一致，然后修 Coordinator 判定为 `.success`）；要么 C++ 改回真返 boolean（影响测试页）。**推荐前者**（C++ 结构化返回是更好的设计，错的是 SSOT 声明）。

### 问题 2 [MED-HIGH] — orphan 模块对象 spread，接线即编译失败

- **实物**：`LibraryMetadataMigration.ets:168` `return { ...record, releaseYear:…, updatedAt: Date.now() }` —— 对象 spread。
- **为何是问题**：ArkTS 禁 `arkts-no-spread`（**只允许数组 spread，禁对象 spread**，已 web 验证 API22 仍生效）。
- **为何现在不爆（已亲验）**：`LibraryMetadataMigration.ets` **从未被任何文件 import**（orphan 模块，grep 0 import）→ 不在构建图内。一旦有人接线引用，立即编译失败。
- **修复方向**：改为显式字段赋值（`const r = {…}; r.releaseYear = …`）或逐字段构造，去掉 `...record`。本审计未改码。

---


## 差异性总结论

### 🟢 核心结论：本地代码对 HarmonyOS API22 的 OH_ Native API 使用 **零兼容性缺陷**

104 个实际调用符号 **全部** 在 API22 header 存在、签名逐参一致、since 全覆盖、无 deprecated 误用、无硬编码数值（全用符号常量）。四个子系统独立审计 + 一个第三方 audit-evaluator 独立复核（音频）结论一致，无 self-grade 虚高。

### deprecated 规避 — 全部正确（0 命中），三处"易踩坑"本地都用了新版

| 子系统 | header 中的 @deprecated 旧版 | 本地实际用法 |
|--------|------|------|
| 音频 | `SetRendererCallback` + `OH_AudioRenderer_Callbacks`（@dep since 20） | 4 个新拆分回调 WriteData/Interrupt/OutputDeviceChange/Error |
| 图形 | `OH_NativeWindow_NativeWindowSetScalingMode`（@dep since 10） | `...SetScalingModeV2`（since 12）+ `OHScalingModeV2` |
| 资源 | `GetRawFileDescriptor`/`ReleaseRawFileDescriptor`（@dep since 12） | 64 位 `OpenRawFile64`/`ReadRawFile64`/`CloseRawFile64` |

### since 边界 — 全部 ≤22 覆盖，且高 since 处均有运行期兜底

- 最高 since=20 出现在两处：**音频 Workgroup 系列（9 符号）** 与 **图形 NativeFence（3 符号）**。目标 22 ≥ 20，编译期零 unavailable 报错。
- **运行期双保险**（架构亮点）：音频 Workgroup 失败 → `workgroup_disabled_` CAS 自禁用、补静音照常出声；NativeFence → `dlopen`+`dlsym` 软加载，缺失整体回退 `poll()`/`close()` POSIX 路径。**即便未来 minSDK 下探 < 20，低版本设备也不崩、只降级。**

### 🟡 唯一"行为待确认"项（非 API 兼容性差异，已第三方复核定性）

**音频 `OH_AudioWorkgroup_Start` 单位错位**：header 注释口径为**毫秒**，本地 `audio_player.cpp` L509-523 传入 `clock_gettime(CLOCK_MONOTONIC)` 算出的**纳秒**。
→ 后果：大核调度优化在真机上**很可能从未真正生效**（传纳秒巨值 → Start 大概率返回 `ERROR_INVALID_PARAM` → workgroup 静默自禁用）。**不破声、不属 API 兼容性缺陷**。
→ 建议：真机 profile 验证；若要让优化生效，把 L510-523 改为毫秒口径（`/1000000`）。

### 审计输入勘误（之前会话发现，非代码问题，记录防误导）

- 音频：旧清单称 `libretro_engine.cpp` 调用 Workgroup → 实为 L1139 一行**注释字符串**，真实 callsite 全在 `audio_player.cpp`。
- XComponent：旧清单标 `RESULT_SUCCESS=16` → header/官方真值 **=0**；本地用符号常量未硬编码，零影响。

### API22 可用、本地未用（增强清单，非缺陷）

- **XComponent**：`ArkUI_XComponentSurfaceConfig`（**API22 新增**，surface 不透明度）、`RegisterUIInputEventCallback`（since12，官方手柄/轴输入通道）
- **音频**：`SetRendererWriteDataCallbackAdvanced`（partial-write）、`GetUnderflowCount`、`SetSpeed`（快进/慢放接入点）
- **资源**：`OH_FileUri_GetFileName`（since13）、`OH_ResourceManager_IsRawDir`（since12）

---

## 约束声明

- 本审计为 **静态源码 + header 比对**，**未编译、未真机验证**（遵循项目 AGENTS.md 交互偏好）。
- 源 C（官方 web 文档）因本机 header 已是 API22 权威 + 后端封禁风险，仅对关键 deprecated/高-since 符号抽查交叉验证；graphics/resource 域以 header `@since`/`@deprecated` 注释为准。
- 未改任何业务代码（`.cpp`/`.h`/`.ets`）；产出仅本目录 5 个审计 md。
