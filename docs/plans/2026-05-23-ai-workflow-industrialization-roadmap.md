# AI Workflow Industrialization Roadmap (v2 — Revised)

> **For Claude:** 这是路线图（设计文档）的第二版，由 2026-05-23 同日反向 review 后重写。v1 把"工业化"当成普世命题，借了 6 回路框架 + 11 个外部资料的弹药；v2 收窄到个人 HarmonyOS 项目的真实反馈闭环。

**Goal:** 让"你 + Claude"在 HarmonyOS emulator 项目上有 **2 条闭环回路**：

1. 改代码 → 1 命令拿信号（构建/lint/regression）
2. 会话结束 → 沉淀反思到 memory

**不在范围**: 任务派发、评审、发布、横切成本（这些是 v1 借框架借来的伪需求，已砍）。

---

## 为什么砍

v1 的 6 回路框架（① 上下文 / ② 任务派发 / ③ 测试 / ④ 评审 / ⑤ 发布 / ⑥ 反思）有 3 个是团队假设：

- ② 任务派发 — 单人无意义
- ④ 评审 — 自审 + 现有 `check_regression_guards.sh` / `check_repo_hygiene.sh` 已经够
- ⑤ 发布 — release workflow 已闭环

v1 的"横切成本"维度没有 firecrawl/Claude API token 基线就是伪命题，砍。

v1 的 P0（unit test runner）方向错：emulator 项目核心 emulation 不靠单元测试验证，靠 build + 真机 + 人眼。修一个名义 test runner 解决不了真痛点。

---

## 2 回路设计

### 回路 A：改 → 1 命令拿信号

**问题**: AI 改完代码（C++ / ArkTS / build 脚本 / hook），没有快速反馈说"这次改动有没有出错"。现有：
- `check_regression_guards.sh`（banned patterns，~1s）
- `check_repo_hygiene.sh`（仓库卫生，~1s）
- CMake 测试目标 `libretro_tests`（CI 只 build 不 run，本地无 runner）
- ArkTS 编译要走 hvigor sync（慢，~分钟级，没法快速跑）

**目标态**: 一个命令组合所有快信号（regression / hygiene / 增量 cmake build），秒级出 PASS/FAIL 摘要。慢信号（hvigor sync / 真机部署）继续走 DevEco。

**实交（P0）**:
1. `scripts/check/quick_signals.sh` — 串联 3 项：regression-guards、repo-hygiene、（如果 `entry/.cxx/.../arm64-v8a/build.ninja` 存在）调 `cmake --build entry/.cxx/.../arm64-v8a --target entry -- -j` 做增量编译
2. 输出格式：每项 PASS/FAIL/SKIP + 总和退出码
3. 失败时打印精确文件:行号（regression script 已支持，cmake 也已支持）
4. 更新根 `CLAUDE.md` 的 "Common Development Commands" 加这个入口

**不做**（本会话）:
- 改 CI 加 run-test step
- ArkTS 快速 lint runner（hvigor 不给增量 lint 入口，需要研究）
- PostToolUse hook 自动跑（先手动用 1 周看够不够稳）

**验收**:
- 当前代码上跑 `bash scripts/check/quick_signals.sh` 全 PASS，<5s
- 改一个 banned pattern（如 `core/engine/foo.cpp` 加 `mmap`）能立刻被 catch
- 改一处编译错（如删一个 include），cmake step 能 catch

---

### 回路 B：会话结束沉淀反思

**问题**: 每次会话有大量"哪些工具浪费了 token / 哪些 skill 没生效 / 哪个上下文应该提前装"的元信号，但全靠 ad-hoc 记忆，沉淀到 `~/.claude/.../memory/` 的不到 5%。

**目标态**: 会话结束前 Claude 主动问 3-5 个固定问题，答案直接写 memory。

**实交（P1）**:
1. `~/.claude/skills/session-debrief/SKILL.md` — frontmatter 用 `description` 让 Claude 在 "用户说结束/我要走了" 时自动调用
2. 内容：5 个固定问题
   - 这次会话哪 1 个工具调用最浪费 token？
   - 哪个 skill 该触发但没触发？
   - 我（Claude）对哪个判断错了，应该写入 feedback memory？
   - 下次同主题会话开场前，要先加载什么上下文？
   - 这次有哪个"非显然"的方法被用户验证有效（写入 feedback memory 防漂移）？
3. 输出：每个问题 1-2 句，由 Claude 直接 Write 到 memory（feedback / project 类型）+ 更新 MEMORY.md 索引

**自动触发增强（同会话实交）**:
- `scripts/check/session_idle_detector.sh` — 双模式（`stop` 盖时间戳 / `check` 算 gap 输出 sentinel）
- `.claude/hooks/check-idle-on-prompt.sh` — UserPromptSubmit hook，包装 check 模式
- `.claude/stop-hook.sh` 追加调用 `stop` 模式
- `.claude/settings.json` 加 `UserPromptSubmit` event 接 hook
- 阈值默认 15 min，env `CLAUDE_DEBRIEF_IDLE_MIN` 可覆盖
- 状态文件 `.claude/.last-activity-ts`（`.claude/` 已 gitignored）
- 当 UserPromptSubmit 检测到 idle，输出 `[auto-detected idle: ... consider running /session-debrief ...]`，被 Claude 视为 user-prompt-submit-hook 注入，SKILL.md 已识别此触发

**不做**（本会话）:
- ~~自动触发（先靠 Claude 主动调用，1 周后看准确率再考虑 Stop hook）~~ → 已做
- 跨 session aggregation 报告
- 完全自动（headless API 分析 transcript）

**验收**:
- 装好 skill ✓
- session_idle_detector.sh `check` / `stop` / 非法 mode 三路径测过 ✓
- Stop hook 集成测过（原有 hygiene/regression 全 PASS + idle stamp 静默执行） ✓
- 模拟 20/25 min idle 能正确产出 sentinel 文案 ✓
- 下次会话临结束时 Claude 主动调起，5 个问题各有 1 条 memory 产出（或明确说"无 → 跳过"）—— 待实际会话验证

---

## 砍掉的（v1 的内容，记录理由）

| v1 项 | 砍的理由 |
|---|---|
| ② 任务派发 playbook | 单人项目无意义 |
| ④ 评审回路 PR auto-review | 现有 hygiene/regression 已覆盖 |
| ⑤ 发布回路增强 | release workflow 已闭环 |
| 横切成本独立维度 | 无 firecrawl/Claude token 基线，无法量化 |
| AnySearch PoC | 装它前应先量化 firecrawl 痛感 |
| CodeGraph PoC | ArkTS 支持不明；且不解决 emulator 项目核心痛点 |
| OpenCLI PoC | 需自写 Huawei docs adapter，投入高 |
| Skill `paths:` 作用域 | 优化，不是闭环；启动 token 不是瓶颈时不做 |
| `claude-code-setup` 一键体验 | 反思机制有了之后再说 |
| maestro-flow / codeg / 整包采纳 | pre-1.0 / 单 maintainer / 框架锁定 / 70% 是团队功能 |

---

## 待续（next iteration 触发条件）

- **触发 P2 任务派发 playbook**: 当 1 个会话需要 > 3 个 subagent 调用时
- **触发成本工具 PoC**: 当 firecrawl 月用量 > 50 credit 或 Claude API 月费 > 某阈值
- **触发 CI run-test step**: 当 `quick_signals.sh` 稳定 1 周
- **触发 ArkTS 快速 lint**: 当 ArkTS 改动密度增大、每次都靠 hvigor sync 拖慢时
- **触发评审 PR auto-review**: 当未来引入协作者时

---

## 风险

1. **回路 A 的 cmake 增量 step 可能依赖 `entry/.cxx` 已经被 hvigor 构建过**（OHOS NDK toolchain 在 cmake configure 时由 hvigor 注入）。Fallback: 检测到 build.ninja 不存在时 SKIP，输出"先在 DevEco 跑一次 Sync 再用此脚本"
2. **回路 B 的 skill 触发时机靠 description 匹配**，可能不准（用户说"结束"时 Claude 没识别）。Fallback: skill 描述里加强语义；同时支持用户手动 `/session-debrief`
3. **路线图本身可能 1-2 个月内还要再修**（这是个人项目，节奏不可预测）。Accept

---

## 索引

- v1 推翻：本文件 git 历史里有
- 触发对话：2026-05-23 用户原话"我开发这个项目一开始没想好流水线，工作流"
- 关键转折：用户"非常对，说到我心里了"——确认砍掉团队回路、收窄到反馈闭环
- 关联 commit：`bf1e059 build: always export compile_commands.json for clangd LSP`
- 内存：`feedback_individual_project_workflow` / `project_2026_05_23_workflow_roadmap`
