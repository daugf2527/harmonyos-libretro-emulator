# 剩余任务拆解与并发执行计划

**创建日期**: 2026-05-31
**目标**: 将 M2/M5/M6/M7 大型任务拆解为可并发执行的小任务
**执行模式**: Agent 并发执行 + 主 AI 验收

---

## M2 可观测性与错误治理（P1）

### 目标
统一错误分类、步骤码、耗时统计与关键日志上报。

### 任务拆解

#### M2-T1: 错误码枚举设计（独立任务，30 分钟）
**负责**: Agent (Opus)
**输入**:
- `docs/audit/m2-t31-error-handling-audit.md`
- 当前 NAPI 返回值模式（boolean）
**输出**:
- `entry/src/main/ets/common/ErrorCodes.ets` - 错误码枚举定义
- 包含：文件 I/O、路由、引擎操作、JSON 解析等分类
**验收标准**:
- [ ] 错误码覆盖审计文档中的 5 大类错误
- [ ] 每个错误码有清晰的描述和建议处理方式
- [ ] 编译通过

#### M2-T2: NAPI 错误传播增强（独立任务，45 分钟）
**负责**: Agent (Opus)
**输入**:
- M2-T1 的错误码定义
- `entry/src/main/cpp/app/napi/libretro_engine_napi.cpp`
**输出**:
- 修改 NAPI 函数返回详细错误信息（不只是 boolean）
- 使用`napi_create_object` 返回 `{ success: boolean, errorCode?: string, message?: string }`
**验收标准**:
- [ ] 至少 5 个关键 NAPI 函数返回详细错误
- [ ] ArkTS 层可以获取错误详情
- [ ] 编译通过 + quick_signals PASS

#### M2-T3: 步骤码定义（独立任务，20 分钟）
**负责**: Agent (Sonnet)
**输入**:
- 引擎启动/切换流程（LoadCore → LoadRom → Start）
**输出**:
- `entry/src/main/ets/common/EngineSteps.ets` - 步骤码枚举
- 包含：INIT, LOADING_CORE, CORE_LOADED, LOADING_ROM, ROM_LOADED, STARTING, RUNNING 等
**验收标准**:
- [ ] 步骤码覆盖完整启动流程
- [ ] 编译通过

#### M2-T4: 耗时统计工具类（独立任务，30 分钟）
**负责**: Agent (Sonnet)
**输入**:
- 无依赖
**输出**:
- `entry/src/main/ets/common/PerformanceTracker.ets` - 耗时统计工具
- 支持：开始计时、结束计时、获取耗时、重置
**验收标准**:
- [ ] 提供简单易用的 API
- [ ] 支持多个并发计时器
- [ ] 编译通过

#### M2-T5: 集成错误码到现有错误处理（依赖 M2-T1，45 分钟）
**负责**: Agent (Opus)
**输入**:
- M2-T1 的错误码定义
- 当前 try-catch 块（31 个文件）
**输出**:
- 更新关键页面的错误处理使用新错误码
- 优先：LibretroGamePage, LibraryPage, SaveStatePage
**验收标准**:
- [ ] 至少 3 个关键页面使用新错误码
- [ ] 错误信息更具体
- [ ] 编译通过 + quick_signals PASS

---

## M5 HW_RENDER 基础闭环（P1）

### 目标
GLES/Vulkan 最小链路稳定，出画可回退。

### 任务拆解

#### M5-T1: Vulkan 日志分析脚本验证（独立任务，15 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `scripts/analyze_vulkan_logs.sh`
- `scripts/quick_vulkan_check.sh`
**输出**:
- 验证脚本语法正确性
- 添加缺失的错误处理
- 添加使用示例到脚本注释
**验收标准**:
- [ ] 脚本可以正常执行（bash -n 检查）
- [ ] 有清晰的使用说明
- [ ] quick_signals PASS

#### M5-T2: Vulkan 验证清单文档完善（独立任务，20 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `docs/plans/2026-05-31-m5-vulkan-verification-plan.md`
**输出**:
- 添加"常见问题排查"章节
- 添加"快速验证步骤"（5 分钟版本）
- 添加"验证结果模板"
**验收标准**:
- [ ] 文档结构清晰
- [ ] 用户可以快速上手验证

#### M5-T3: GLES 稳定性检查清单（独立任务，30 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `entry/src/main/cpp/platform/graphics/gles_renderer.cpp`
- M4 审计文档
**输出**:
- `docs/plans/2026-05-31-m5-gles-verification-checklist.md`
- 包含：初始化检查、渲染检查、错误恢复检查
**验收标准**:
- [ ] 清单覆盖关键验证点
- [ ] 有明确的 PASS/FAIL 标准

---

## M6 内容与配置（P1）

### 目标
多核心/多 ROM 管理，核心选项持久化。

### 任务拆解

#### M6-T1: 核心选项持久化验证（独立任务，20 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `entry/src/main/cpp/core/libretro/core_options_registry.cpp`
- `entry/src/main/cpp/core/libretro/env_dispatcher.cpp`
**输出**:
- 验证报告：核心选项持久化是否完整工作
- 列出：保存路径、加载时机、保存时机
**验收标准**:
- [ ] 确认持久化已实现
- [ ] 列出测试步骤

#### M6-T2: 核心管理 UI 设计（独立任务，45 分钟）
**负责**: Agent (Opus)
**输入**:
- `entry/src/main/ets/pages/CoreManagerPage.ets`（现有页面）
- ArkUI 设计规范
**输出**:
- `docs/design/m6-core-manager-ui-spec.md`
- 包含：核心列表、核心详情、核心切换、核心删除
- 线框图（ASCII art）
**验收标准**:
- [ ] UI 设计符合 ArkUI 规范
- [ ] 覆盖核心管理的主要场景
- [ ] 有清晰的交互流程

#### M6-T3: ROM 管理 UI 设计（独立任务，45 分钟）
**负责**: Agent (Opus)
**输入**:
- `entry/src/main/ets/pages/LibraryPage.ets`（现有页面）
- M1 Phase 2 的 ROM 沙盒结构
**输出**:
- `docs/design/m6-rom-manager-ui-spec.md`
- 包含：ROM 列表、ROM 详情、ROM 删除、ROM 导入
- 线框图（ASCII art）
**验收标准**:
- [ ] UI 设计符合 ArkUI 规范
- [ ] 覆盖 ROM 管理的主要场景
- [ ] 与现有 LibraryPage 协调

#### M6-T4: 核心切换流程优化设计（独立任务，30 分钟）
**负责**: Agent (Sonnet)
**输入**:
- M0 切换链路稳定化成果
- 当前核心切换实现
**输出**:
- `docs/design/m6-core-switch-optimization.md`
- 包含：切换流程、异常处理、回退机制
**验收标准**:
- [ ] 设计考虑了 M0 的成果
- [ ] 有明确的异常处理策略

---

## M7 交互与多形态（P2）

### 目标
折叠屏布局与虚拟手柄交互收敛。

### 任务拆解

#### M7-T1: 折叠屏布局组件审计（独立任务，30 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `entry/src/main/ets/components/FoldableLayouts.ets`
**输出**:
- 审计报告：组件是否完整、是否有 bug、是否符合规范
- 列出：已实现功能、缺失功能、待优化点
**验收标准**:
- [ ] 审计报告完整
- [ ] 列出具体的改进建议

#### M7-T2: 折叠屏适配页面清单（独立任务，20 分钟）
**负责**: Agent (Sonnet)
**输入**:
- 所有页面列表（18 个）
- 折叠屏适配需求
**输出**:
- `docs/design/m7-foldable-adaptation-checklist.md`
- 列出：需要适配的页面、优先级、适配方案
**验收标准**:
- [ ] 清单覆盖所有页面
- [ ] 有明确的优先级

#### M7-T3: 虚拟手柄交互优化设计（独立任务，30 分钟）
**负责**: Agent (Sonnet)
**输入**:
- `entry/src/main/ets/components/VirtualController.ets`
- `entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`
**输出**:
- `docs/design/m7-virtual-controller-optimization.md`
- 包含：触控反馈、按键映射、布局调整
**验收标准**:
- [ ] 设计考虑了用户体验
- [ ] 有具体的实现建议

---

## 并发执行计划

### 第一批（可并发，预计 45 分钟）
- M2-T1: 错误码枚举设计（Agent 1, Opus）
- M2-T3: 步骤码定义（Agent 2, Sonnet）
- M2-T4: 耗时统计工具类（Agent 3, Sonnet）
- M5-T1: Vulkan 日志分析脚本验证（Agent 4, Sonnet）
- M6-T1: 核心选项持久化验证（Agent 5, Sonnet）

### 第二批（可并发，预计 45 分钟）
- M2-T2: NAPI 错误传播增强（Agent 1, Opus，依赖 M2-T1）
- M5-T2: Vulkan 验证清单文档完善（Agent 2, Sonnet）
- M5-T3: GLES 稳定性检查清单（Agent 3, Sonnet）
- M6-T2: 核心管理 UI 设计（Agent 4, Opus）
- M6-T3: ROM 管理 UI 设计（Agent 5, Opus）

### 第三批（可并发，预计 45 分钟）
- M2-T5: 集成错误码到现有错误处理（Agent 1, Opus，依赖 M2-T1）
- M6-T4: 核心切换流程优化设计（Agent 2, Sonnet）
- M7-T1: 折叠屏布局组件审计（Agent 3, Sonnet）
- M7-T2: 折叠屏适配页面清单（Agent 4, Sonnet）
- M7-T3: 虚拟手柄交互优化设计（Agent 5, Sonnet）

---

## 验收流程

### 主 AI 验收检查点

#### 代码类任务验收
1. [ ] 编译通过（quick_signals PASS）
2. [ ] 代码符合项目规范（CLAUDE.md + AGENTS.md）
3. [ ] 无 regression guards 违规
4. [ ] 有适当的日志和错误处理
5. [ ] 与现有代码风格一致

#### 设计类任务验收
1. [ ] 设计文档结构清晰
2. [ ] 覆盖关键场景
3. [ ] 有明确的验收标准
4. [ ] 考虑了现有架构约束
5. [ ] 有具体的实现建议

#### 审计类任务验收
1. [ ] 审计报告完整
2. [ ] 列出具体问题和证据
3. [ ] 有可行的改进建议
4. [ ] 优先级明确

---

## 执行命令模板

### 派发 Agent 命令
```bash
# 第一批（5 个并发）
Agent({
  description: "M2-T1 错误码枚举设计",
  model: "opus",
  prompt: "设计统一错误码枚举。输入：docs/audit/m2-t31-error-handling-audit.md。输出：entry/src/main/ets/common/ErrorCodes.ets，包含 5 大类错误（文件 I/O、路由、引擎操作、JSON 解析、EventHub），每个错误码有描述和处理建议。验收：覆盖审计文档错误类型 + 编译通过。"
})

# 其他 Agent 类似...
```

### 验收命令
```bash
# 检查编译
bash scripts/check/quick_signals.sh

# 检查文件是否生成
ls -la entry/src/main/ets/common/ErrorCodes.ets

# 检查代码质量
grep -n "TODO\|FIXME" entry/src/main/ets/common/ErrorCodes.ets
```

---

## 预期时间线

- **第一批**: 45 分钟（5 个并发 Agent）
- **验收 + 调整**: 15 分钟
- **第二批**: 45 分钟（5 个并发 Agent）
- **验收 + 调整**: 15 分钟
- **第三批**: 45 分钟（5 个并发 Agent）
- **验收 + 调整**: 15 分钟
- **总计**: ~3 小时

---

## 风险与缓解

### 风险 1: Agent 输出质量不一致
**缓解**:
- 使用 Opus 处理复杂任务（NAPI、UI 设计）
- 使用 Sonnet 处理标准任务（文档、审计）
- 主 AI 严格验收

### 风险 2: 任务间依赖导致阻塞
**缓解**:
- 第一批全部独立任务
- 第二批只有 M2-T2 依赖 M2-T1
- 第三批只有 M2-T5 依赖 M2-T1

### 风险 3: Agent 超时或失败
**缓解**:
- 每个任务限制在 45 分钟内
- 失败任务可以重新派发
- 有明确的输入/输出/验收标准

---

## 后续实施任务

完成上述设计和审计任务后，需要实施：
- M2: 实际集成错误码到所有页面（预计 2-3h）
- M6: 实现核心管理和 ROM 管理 UI（预计 3-4h）
- M7: 实现折叠屏适配（预计 2-3h）

这些实施任务可以在后续会话中继续拆解和并发执行。
