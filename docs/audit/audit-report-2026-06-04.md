# 全方位质检报告 — 2026-06-04

> 审计对象：`fcacd2d` (refactor: target api22 and tighten napi) 提交后的 17 个未提交变更文件
> 方法：4 个 opus 并行 agent（Batch 1 三路 + Batch 2 一路交叉验证）+ 增量编译实测 + CI 双检
> 验证基线：全部 finding 均 trace 代码/SDK header 实物，非纸面推理

---

## 总体结论

| 维度 | 结果 |
|------|------|
| **P0 阻断问题** | **0 个** |
| 增量编译（quick_signals cxx-build） | ✅ PASS（14/14 编译+链接，含全部 4 个改动 .cpp） |
| 回归守护（check_regression_guards） | ✅ PASS |
| 仓库卫生（check_repo_hygiene） | ✅ PASS |
| skill-contract / ui-fixes | ✅ PASS |
| **整体判断** | **可合入**（仅余 P1/P2/P3 改进项，无功能 bug，无阻断） |

**一句话**：本次 API22 收紧 + NAPI 错误码重构 + RawFile64 迁移 + OHAudio 回调扩展，代码层全部正确且实测可编译。遗留问题集中在"错误码体系跨层未接通"这一**架构决策**，非缺陷。

---

## 📌 修复进度（2026-06-04 质检后修复轮）

| 项 | 状态 | 修复内容 |
|----|------|---------|
| **P1-1** AGENTS.md 双轨 | ✅ RESOLVED | AGENTS.md 公共准则段加 SSOT 镜像注释，标明改动需同步 COMMON.md |
| **P2-1** doc 错误码表 | ✅ RESOLVED | napi-error-code-mapping.md 加 SRAM 预留说明 + ARCH-1 实现现状专节 |
| **P2-2** env 守卫 | ✅ RESOLVED | MakeErrorResult 入口加 `if (!env) return nullptr;` |
| **P2-3** 裸 toast | ✅ RESOLVED（超额） | SaveStatePage 6 处裸 toast → ErrorCodeUtils 查表/中文常量；连带发现并修复**整页 18 处英文 UI 文案**中文化（用户确认范围） |
| **P3-1** SRAM dead constant | ✅ RESOLVED（改注释非删除） | 经核 ArkTS 侧是成对完整设计（3032/3033），**保留并加预留注释**而非删除——保护对称性 |
| **API22 升级** | ✅ 确认已完成 | C++ OH_* API 全扫描无 deprecated（VSync/ScalingModeV/XComponentWithResult/RawFile64 均为现代 API）；ArkTS 8 模块全扫描 0 deprecated |
| **ARCH-1** errorCode 跨层通道 | ✅ RESOLVED（用户选 (a) 接通） | 见下文「ARCH-1 接通实施」 |

### ARCH-1 接通实施（用户决策 (a)，2026-06-04）

**连带发现并修复一个真 bug（R1）**：`refactoredSwitchGameAsync` 的 C++ 完成路径 `CompleteSwitchGame` resolve 的是结构对象 `{success, errorCode, message}`（engine_lifecycle_napi.cpp:864 实物确认），但 ArkTS 侧 TS 声明为 `Promise<boolean>` 且用 `if (!ok)` 判断 —— `!{success:false}` 恒为 `false`，**切换游戏失败时 UI 假报成功（黑屏/卡死，引擎实际未启动）**。仅在失败路径显现，正常路径正常，故长期未被发现。

**改动清单（步骤 1 最小闭环，4 文件）：**
| 文件 | 改动 |
|------|------|
| `ets/common/ErrorCodes.ets` | 新增 `NapiErrorResult` interface（success/errorCode?/message?） |
| `cpp/types/libentry/index.d.ts` | 新增 `NapiErrorResult` + 两个 `refactoredSwitchGameAsync` 重载返回 `Promise<boolean>`→`Promise<NapiErrorResult>` |
| `ets/common/RuntimeSessionController.ets` | `refactoredSwitchGameAsync`×2 + `switchGame()` 返回类型 → `Promise<NapiErrorResult>`；import NapiErrorResult |
| `ets/pages/LibretroGamePage.ets` | 新增 `SwitchGameError extends Error`（参照已有 `ImportCanceledError` 范式）；`if(!ok)`→`if(!result.success)` **修 bug**；catch 优先读 `result.errorCode`→`findByNumericCode`，字符串嗅探降级为兜底（处理非结构化异常） |

**验证**：
- 改动面封闭：`switchGame` 全仓仅 LibretroGamePage 1 处调用；`refactoredSwitchGameAsync` 仅 RuntimeSessionController 内调用；TestGambatte 不调（分步 LoadCore/LoadRom，不受影响）——均实物 grep 确认
- ArkTS 范式安全：`SwitchGameError` + catch `instanceof` + 字段访问与项目已有 `ImportCanceledError`（RomImportService.ets:388/399）完全同构
- CI 回归+卫生 PASS
- ⚠️ **必须 DevEco 真机验证**：故意加载坏 core/ROM，确认改后 UI 正确报错而非黑屏假成功（这是 bug 修复的核心验证点）

**未做（步骤 2/3，可选，无运行时收益）**：LibretroSwitchCoordinator（dead code，无调用者）/ TestGambatte 一致性收口；LoadCore/LoadRom/StartEngine/SaveState 同步接通（当前无结构对象消费方）。如未来需要可继续。



**额外发现并修复的 regression**：SaveStatePage 中文化时发现 `label === 'Archive'` 这种"显示文案当逻辑判断键"的脆弱耦合共 3 处（StatusColumn/SwipeAction），全部已同步对齐（'归档'/'读档'/'删除'），独立核对传入值↔判断键配对正确，滑动删除/读档逻辑未错乱。

**修复轮验证**：CI 三检 + C++ 增量编译 8/8 链接成功全部 PASS。ArkTS 改动需 DevEco 真机复编（quick_signals 不覆盖 ets 编译）。

---

## 问题清单（按真实优先级排序，已纳入 Batch 2 交叉验证修正）

### 🔵 架构决策项（最值得你拍板，原 P1 根因）

**ARCH-1：C++ `MakeErrorResult.errorCode` 跨层通道实际未接通**
- **现象**：C++ 在 `engine_lifecycle_napi.cpp` / `engine_state_napi.cpp` 精心组装 `{success, errorCode, message}` 回传，但 **ArkTS 消费侧全部丢弃 errorCode 字段**——`LibretroGamePage.ets:1040-1049` 靠 `rawMessage.includes('Core'/'核心'/'ROM')` **字符串嗅探**在 ArkTS 端二次推断错误码；`SaveStatePage.ets:282-324` 走 boolean/null 协议。NAPI 接口签名里根本没有结构体类型。
- **影响**：这是"C++ 投入产出不对称"的真正根因。Batch 1 报的"C++ 只覆盖 6/14 错误码"在功能上不重要——即便补齐 14/14，ArkTS 当前也不读。
- **二选一决策**：
  - **(a) 接通**：ArkTS 改为消费 C++ `errorCode` 并按码分支 → 那么补齐 C++ 14 个 + 加 CI 防漂移才有意义
  - **(b) 承认现状**：确认 ArkTS-local 映射为既定架构，把 C++ 的 errorCode 标注为"诊断日志用途、非契约"，降低两侧同步压力
- **建议**：倾向 (b)。字符串嗅探虽不优雅但已工作；接通 errorCode 是较大改动，收益需评估。

### 🟡 P1（建议修）

**P1-1：CLAUDE.md + AGENTS.md 公共准则双轨 SSOT drift**
- **现象**：`CLAUDE.md:5` 新增 `@C:/Users/newwo/.cc-switch/agent-policy/COMMON.md`，`CLAUDE.md:19` 又 `@AGENTS.md`；而 `AGENTS.md:3-14` 把同一份"公共行为准则"**静态手抄了一份**。COMMON.md 改动后 AGENTS.md 不会自动同步。
- **缓解事实**：这是**有意妥协**——AGENTS.md 给 Codex Bot 读，Codex 不支持 `@import`，只能内嵌。
- **建议**：在 AGENTS.md 该段加一行注释 `<!-- 此段为 COMMON.md 镜像副本，修改时需同步 -->`，把隐性 drift 显性化。属可接受的 ~10% 漂移范围，但需留痕。

### 🟢 P2（可选改进）

**P2-1：napi-error-code-mapping.md 主表缺 2 行独立条目**
- `SRAM_LOAD_FAILED=3032` 和 `STATE_TRANSITION_FAILED=3022` 只在代码快照里出现，未在主表单列。建议补两行使"函数表"与"常量定义"对称。（doc 代码快照与 .h 逐字节一致，不影响正确性）

**P2-2：`MakeErrorResult` 缺 `env` 合法性守卫**
- 理论 UB（env==nullptr 时 `napi_is_exception_pending` 是 UB），但当前 14 处 callsite 的 env 全部来自合法来源，**不可达**。加 `if (!env) return nullptr;` 仅收口理论风险，优先级低。

**P2-3：错误反馈两套并行机制**
- SaveStatePage 部分失败直接 `showToastMessage('字面量')` 绕开 ErrorCodes 体系，与 numericCode 体系并存。非本批问题，属同类技术债。

### ⚪ P3（清理项，原 P1 降级）

**P3-1：`SRAM_LOAD_FAILED=3032` 是两侧皆死的 dead constant**
- **Batch 2 决定性发现**：C++ 侧 `GetSRAM`/`SetSRAM` 失败返回 null/bool 不带 errorCode（确凿 dead）；**ArkTS 侧全树搜索 SRAM 唯一命中 `ErrorCodes.ets` 自身**——ArkTS 根本没有 `refactoredGetSRAM`/`refactoredSetSRAM` 调用，SRAM 是引擎内部自动持久化，UI 不经手。
- **结论**：删除 3032（C++ + ArkTS 两边）**零功能影响**。原 Batch 1 评 P1 偏高，实为 P3 清理项或未来 SRAM UI 的预埋。

---

## 已验证通过项（实测，非推理）

### NAPI 错误码重构（Agent A）
- ✅ `engine_lifecycle_napi.cpp` + `engine_state_napi.cpp` **零魔数残留**，14 处 callsite 全部命名常量化（ast-grep 全目录扫描确认）
- ✅ C++ 已定义的 8 个常量数值与 ArkTS `ErrorCodes.ets` **逐一核对全部一致**
- ✅ `MakeErrorResult` 入口即检 `napi_is_exception_pending`，pending-exception 安全链完整
- ✅ 唯一跨线程路径 `CompleteSwitchGame` 的 env/TSFN 全部合规，progress TSFN create→release 配对成立

### 音频 + 资源 + 构建（Agent B）
- ✅ `pending_interrupt_stop_` 消费链**闭环**：`OnRendererError` store(true) → `ProcessPendingInterruptActions()`（每帧无条件调用）exchange 消费 → `Stop()`；内存序 release/acq_rel 配对正确；触发链 trace 实物（retro_run→OnAudioSampleBatch→ProcessAudio→ProcessPendingInterruptActions）
- ✅ RawFile64 函数签名正确（GetRawFileSize64 返回 int64_t，代码按 int64 接收，负值/短读处理正确）
- ✅ kMaxSize 三处数值完全一致（512MB）
- ✅ CMake 库名 `libace_napi.z.so` + `librawfile.z.so` 在本机 NDK lib 目录实测存在
- ✅ 两个新回调签名精确匹配 SDK，CallbackGuard 线程安全与既有回调一致

### 核心引擎 + 文档（Agent C）
- ✅ **删 fallback 宏安全**：`SET_BUFFER_GEOMETRY` / `SET_SWAP_INTERVAL` 等 4 宏在 API22 `external_window.h` 中作为 `NativeWindowOperation` enum **无条件成员**存在（@since 8，无版本守卫）；增量编译实测 PASS 二次确认
- ✅ napi-error-code-mapping.md ↔ engine_napi_common.h 常量值完全一致
- ✅ tech-debt-tracker.md D008 状态 open→closed 正确，诚实标注"未编译/未真机"
- ✅ harmonyos-sdk-target.md API22 描述与 build-profile.json5 一致，文档先行说明了删宏理由

---

## 需你决策 / 后续动作建议

| 项 | 类型 | 建议 |
|----|------|------|
| ARCH-1 errorCode 跨层通道 | 架构决策 | 倾向 (b) 标注诊断用途；若要接通是独立任务 |
| P1-1 AGENTS.md 双轨 | 1 行注释 | 立即可加（低成本留痕） |
| P3-1 SRAM dead constant | 清理 | 可删可留（删则两边一起删） |
| P2 系列 | 可选 | 不阻断，择机 |

### 🟡 待真机/DevEco 验证（本审计未覆盖）
- 全部为**静态 + SDK header 实物 + 增量编译**验证，**未真机运行**
- `OnOutputDeviceChange` 蓝牙/有线拔出场景的实际音频表现（Agent B 原建议 OLD_DEVICE_UNAVAILABLE 时 pause；Batch 2 确认 ArkTS 侧无需同步）
- ArkTS 侧改动为零，本次纯 C++ 改动 quick_signals 已覆盖增量编译

---

## 审计元信息

- **并行 agent**：4 个全 opus 模型（Batch 1: napi-boundary-reviewer + 2×general-purpose；Batch 2: 1×general-purpose 交叉验证）
- **工具使用**：cclsp（部分失效，已用 ast-grep 补全）/ serena / ast-grep / web-search / Read / Grep
- **Batch 2 核心价值**：推翻 Batch 1 优先级评估（Finding 1 P1→P3，Finding 2 根因重定位为 ARCH-1）
- **总 token**：约 540k（4 agent subagent_tokens 合计）
