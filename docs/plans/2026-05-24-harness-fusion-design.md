# Harness Fusion Design — carbon-shade-web × harmonyos-libretro-emulator

> 设计日期：2026-05-24
> 适用仓库：`harmonyos-libretro-emulator`（本仓库）+ `carbon-shade-web`（共享设计，PR 各自开）
> 状态：S1 完成（本设计文档）；S2-S7 待实施

## 1. Business goal + Success criteria

### Business goal

把 `carbon-shade-web` 与 `harmonyos-libretro-emulator` 两个个人项目的 Claude Code harness（hooks / skills / agents / settings / statusline）做**双向取长补短**，再结合 2026 年业界共识把"业界 baseline 但两边都没做"的部分补齐。最终落地是两个仓库各自的 PR + 本设计文档作锚点。

### Success criteria

1. 本文档可以独立读懂（任何一边的下一次会话都能照表执行，不需要本次会话 context）。
2. 每条迁移项必须有 **来源**（业界 URL 或对面项目的 `file:line`）+ **验收口径**（怎么算迁完）。
3. 优先级分 P0 / P1 / P2，P0 必须能在 1 次会话内落完（不超过 4 小时实际工时）。
4. 明确点出"业界推荐但不该抄"的反模式（避免 cargo-cult）。

### Out-of-scope（本设计明确不做）

- 不动 `~/.claude/` 全局配置（个人级，与项目融合无关）。
- 不引入业界查到的 HTTP hooks / async hooks（个人项目无远程服务诉求）。
- 不引入 Skills 2.0 eval / A-B 测试（两个项目都还没有足够 skill 量做 A/B）。
- "上下文治理"（CLAUDE.md / memory / statusline 深挖）与"本地反馈回路"两个维度按 force-converge 规则**未深挖**——按需再开新会话。

### 关键约束

- 个人项目，无团队回路（参考 memory `feedback_individual_project_workflow`）。
- 当前 cwd 在 harmony，两边都落地有 cwd 切换风险（参考 memory `feedback_agent_worktree_isolation`）。
- 设计文档放 harmony 这边的 `docs/plans/`，carbon 那边的实施会话直接读这个文件即可。

---

## 2. Hooks gap 矩阵

| 业界 baseline（2026） | carbon | harmony | 双向结论 |
|---|---|---|---|
| **PreToolUse danger-guard** | ❌（无 deny） | ✅ `permissions.deny` 4 条 | **carbon ← harmony**（P0 / C1） |
| **PreToolUse boundary-guard** | ✅ 4 个 `.mjs` | ❌ 完全空 | **harmony ← carbon**（P0 / H1） |
| **PostToolUse auto-validate** | ✅ `post-typecheck.mjs` | ✅ `post-edit-cpp.sh`（codelinter 单文件） | 互不抄 |
| **SessionStart context-inject** | ✅ `reset-status.mjs` | ❌ 完全空 | **harmony ← carbon**（P1 / H3） |
| **UserPromptSubmit** | ✅ 复用 reset-status | ✅ `check-idle-on-prompt.sh` | 业界少见，互不抄 |
| **Stop hook** | ❌ 无 | ✅ `stop-hook.sh`（hygiene + regression） | **carbon ← harmony**（P1 / C3） |
| **`defaultMode: acceptEdits`** | ❌ 默认 ask | ✅ 已设 | **carbon ← harmony**（P0 / C2） |

### 糟粕识别（明确不抄）

- carbon 的 `guard-velocity-writes` / `guard-phaser-boundary` 是 DNF 战斗内核高度业务特定，harmony 无对应业务，**不抄**。
- harmony 的 `post-edit-cpp.sh` 依赖 HarmonyOS `codelinter`，**不能迁到 carbon**（carbon 那边的 `post-typecheck.mjs` 已经对位）。
- 业界 HTTP hooks / async hooks（2026 年新功能）—— 个人项目无远程验证服务诉求，**两边都不抄**。

### 关键互补观察

harmony 缺 **PreToolUse 一整层**（最大 gap），carbon 缺 **Stop hook 一整层**（次大 gap），两边都缺 **SessionStart 真注入**（业界共识但都没做）。

---

## 3. Skills gap 矩阵

| 业界 baseline（2026） | carbon | harmony | 双向结论 |
|---|---|---|---|
| **closed-loop / critic-fixer 6+ 步** | ✅ 9 步成熟（audit-verify 机械引用 + 4 mandatory checkpoint + state-machine resume + anti-patterns refusal） | ❌ 仅 `auto-commit-cicd`（CI 修复循环，无 audit / 无 checkpoint） | **harmony ← carbon**（P0 / H2） |
| **`disable-model-invocation: true`** | ❌ 6 个 skill 都没设 | ❌ `auto-commit-cicd` 没设（**最该设的**） | **两边都补**（P0 / B1） |
| **`learnings.md` 自我改进** | ❌ | ❌ | **两边都补**（P1 / B2） |
| **agent + skill 配对调用** | ✅ `combat-kernel-reviewer` 被 closed-loop 内调 | ✅ `napi-boundary-reviewer` 存在但无 skill 调它（孤儿） | **harmony 补**（P0 / 顺带 H2 做） |
| **chained-skills** | ⚠️ closed-loop 内嵌 audit + verify-all | ❌ 单 skill | **个人项目复用度低，不强推**（P2） |
| **code-reviewer 自修闭环** | ✅ closed-loop step 3-4（main Claude 自修，不派 fix agent） | ❌ | harmony 抄 closed-loop 时自带 |

### 糟粕识别（明确不抄）

- carbon 的 `dnf-physics-extraction` / `add-action` / `gen-test` 高度 DNF 业务特定，harmony 无对应业务，**不抄**。
- carbon 的 `audit` skill 依赖 `topics.json` + `scripts/audit-verify.mjs`：harmony 抄"主题分割 + 机械引用核验"**思想**，但脚本要按 NAPI/C++ 边界重写（不直接抄 .mjs）。
- 业界 Skills 2.0 eval / A-B 测试 —— Section 1 out-of-scope。

### 关键互补观察

harmony skills 远远落后 carbon（1 vs 6），但**不该盲目补齐到 6**。harmony 真正需要的最小集是：1 个移植版 `closed-loop`（带 `napi-boundary-reviewer` 接入）+ 业务 skill 按需再加。carbon 反过来该向 harmony 学的是"**单一 skill 内的安全约束写法**"——`auto-commit-cicd` 的 *"修复循环 ≤ 3 次 / 不 force push / 不 --no-verify / 不提交 secrets"* 几条硬约束是业界共识但 carbon 的 closed-loop 没明写。

---

## 4. 双向迁移清单

### P0（必须 1 次会话内落完，每项 ≤ 1 小时）

#### H1 — harmony 新增 PreToolUse 框架

- **来源**：carbon `.claude/hooks/guard-*.mjs` × 4 + carbon `.claude/settings.json:13-55`
- **内容**：harmony 新建 3 个 PreToolUse guard（不要 4 个 —— `guard-velocity-writes` / `guard-phaser-boundary` 不抄）：
  1. `guard-deprecated.sh` —— 拦写入 `deprecated/legacy/**`
  2. `guard-vendored-libretro.sh` —— 拦写入 `entry/src/main/cpp/core/libretro/**`
  3. `guard-lockfile.sh` —— warn 编辑 `oh-package-lock.json5`
- **实施**：新建 3 个 bash 脚本到 `.claude/hooks/`，`settings.json` 加 `PreToolUse` 段（matcher: `Edit|Write`）。注意 memory `feedback_claude_hook_command` —— hook command 字段会被自动加 `bash ` 前缀，复合 shell 语句要抽到脚本里。
- **验收**：
  1. 试编辑 `deprecated/legacy/x.cpp` → 被 deny + 提示原因
  2. 试编辑 `entry/src/main/cpp/core/libretro/foo.cpp` → 被 deny
  3. 改 `oh-package-lock.json5` → 看到 warn 但不 block

#### H2 — harmony 移植 `closed-loop` skill

- **来源**：carbon `.claude/skills/closed-loop/SKILL.md`（9 步 + 4 mandatory checkpoint + state-machine resume + anti-patterns refusal）
- **内容**：harmony 新建 `.claude/skills/closed-loop/SKILL.md`：
  - 9 步框架不变，4 个 mandatory human checkpoint 保留
  - topic 换成：NAPI 边界 / Engine 状态机 / Audio bridge / VideoPipeline / NativeBuffer 用法 / 资源生命周期
  - `audit-verify.mjs` 替换为更轻的 `Read + grep` 验证（不写脚本，main Claude 在 step 2 直接做机械再核查）
  - step 8 gate 用 harmony 的 `bash scripts/check/quick_signals.sh`
  - step 4 fix 涉及 `entry/src/main/cpp/app/napi/**` 时**必须**先派 `napi-boundary-reviewer` agent
- **实施**：单文件创建
- **验收**：手动 `/closed-loop` 跑 NAPI topic 一遍能完成 9 步 + 命中 4 个 mandatory checkpoint

#### B1 — 副作用 skill 全加 `disable-model-invocation: true`

- **来源**：业界共识（[MindStudio](https://www.mindstudio.ai/blog/claude-code-skills-self-improving-workflows)）
- **内容**：在 `SKILL.md` frontmatter 加 `disable-model-invocation: true`
  - harmony：`.claude/skills/auto-commit-cicd/SKILL.md`
  - carbon：`.claude/skills/closed-loop/SKILL.md` + `.claude/skills/audit/SKILL.md`
- **验收**：在 Claude Code 内 prompt "提交代码" / "跑闭环"，skill 不自动触发；只有用户敲 `/auto-commit-cicd` / `/closed-loop` 才触发

#### C1 — carbon 抄 `permissions.deny`

- **来源**：harmony `.claude/settings.json:17-23`
- **内容**：carbon `.claude/settings.json` 加：
  ```json
  "deny": [
    "Bash(rm -rf*)",
    "Bash(curl*)",
    "Bash(* | bash*)",
    "Read(**.env)",
    "Read(**secrets**)"
  ]
  ```
- **验收**：carbon 内尝试 `Bash(rm -rf foo)` 被拒

#### C2 — carbon 抄 `defaultMode: acceptEdits`

- **来源**：harmony `.claude/settings.json:2`
- **内容**：carbon `settings.json` 顶层加 `"defaultMode": "acceptEdits"`
- **验收**：carbon 会话内 Edit/Write 不再弹窗确认

### P1（可分多次会话，2-4 周窗口）

| ID | 内容 | 来源 |
|---|---|---|
| **H3** | harmony 新增 `SessionStart` hook：输出 `git status -s` + `git log --oneline -3` + 上次 `quick_signals.sh` 摘要 | carbon `reset-status.mjs` + 业界 SessionStart context-inject |
| **C3** | carbon 新增 `Stop` hook：跑 `npm run analyze` + 写 idle 时间戳 | harmony `.claude/stop-hook.sh` |
| **B2** | 每个 P0 skill 配同目录 `learnings.md`（初始空 + 表头），与 `session-debrief` 联动追加 | 业界自我改进闭环 |

### P2 / 明确不做

| 项 | 理由 |
|---|---|
| `status.json` + statusline 任务进度可视化 | 跨"上下文治理"维度，留待该专题会话整体设计 |
| carbon `audit` skill 完整移植 + `audit-verify.mjs` 重写 | 工程量大，先观察 closed-loop 跑 1-2 次效果再决策 |
| chained-skills 多 skill 串联 | 个人项目复用度低 |
| HTTP hooks / async hooks（2026 业界新） | 个人项目无远程验证服务诉求 |
| Skills 2.0 eval / A-B 测试 | skill 数量不够支持 A/B 统计 |
| carbon 抄 harmony 分层 CLAUDE.md | DNF 项目只 1 个领域，不需要分层 |

### 工作量平衡

- harmony 侧 P0 = H1 + H2 + B1.harmony = 3 项
- carbon 侧 P0 = C1 + C2 + B1.carbon = 3 项
- **双向 P0 工作量大致平衡**

---

## 5. 业界引用（按 Section 2-4 的论证顺序）

| # | 来源 | 用在哪 |
|---|---|---|
| 1 | [Claude Code Hooks Guide（Anthropic 官方）](https://code.claude.com/docs/en/hooks-guide) | hook 事件 / 配置位置 / exit code 语义 |
| 2 | [Claude Code Hooks: Production CI/CD Patterns（Pixelmojo）](https://www.pixelmojo.io/blogs/claude-code-hooks-production-quality-ci-cd-patterns) | "3 hook starter pack" + Exit code 2 是 power tool |
| 3 | [Claude Code Hooks Mastery（disler/GitHub）](https://github.com/disler/claude-code-hooks-mastery) | 实战示例库参考 |
| 4 | [Extend Claude with skills（Anthropic 官方）](https://code.claude.com/docs/en/skills) | SKILL.md anatomy + 渐进加载 100/5000 token |
| 5 | [Workflow Patterns（MindStudio）](https://www.mindstudio.ai/blog/claude-code-agentic-workflow-patterns) | 5 种 workflow 模式（sequential / operator / split-merge / agent-teams / headless） |
| 6 | [Self-Improving Workflows（MindStudio）](https://www.mindstudio.ai/blog/claude-code-skills-self-improving-workflows) | `learnings.md` 自我改进 + `disable-model-invocation` |
| 7 | [psantanna closed-loop reference impl](https://psantanna.com/claude-code-my-workflow/workflow-guide.html) | 学术写作场景的闭环管道参考实现（critic-fixer + 多 agent 评审） |
| 8 | [Snyk ToxicSkills research](https://snyk.io/articles/top-claude-skills-developers/) | 36% 测试 skill 有 prompt injection——本设计"思想抄脚本不抄"的安全理由 |

---

## 6. 实施分会话计划

| 阶段 | cwd | 预算 | 范围 | 验收 |
|---|---|---|---|---|
| **S1（本会话）** | harmony | ≈3 h | 产出本设计文档 + 写入 `feedback_setup_harness_first_before_coding` memory | 设计文档 commit + MEMORY.md 多一行 |
| **S2** | harmony | 1.5 h | **P0 harmony 侧**：H1 + H2 + B1.harmony | 各按 P0 验收口径手动跑一遍 → 提 PR 到 harmony |
| **S3** | carbon | 1.5 h | **P0 carbon 侧**：C1 + C2 + B1.carbon **+ CT1 + CT2**（拆分 CLAUDE.md / .claudeignore；详见附录 A） | settings.json 改完 + CLAUDE.md 拆分完成 + 提 PR |
| **S4-S6** | 按需 | 各 1 h | **P1**：H3 / C3 / B2 / CT3 / CT5 / FB1 **+ AG1**（详见附录 A、B、C），每会话挑 1-2 项 | - |
| **S7+** | 视情况 | - | **P2 探索**：观察 P0/P1 跑 2-4 周效果后决策 | - |

---

## 7. 本设计如何使用（给下次会话的指引）

**开 S2 会话时**（cwd = harmony）：

1. 读本文件 Section 4 的 H1 / H2 / B1.harmony 三条
2. 按 P0 实施顺序：**H1（最简单，热身）→ B1.harmony（一行 frontmatter）→ H2（最重，留充足时间）**
3. 每条做完按"验收口径"手动验证，验证通过才进下一条
4. 全部完成后 `git commit` + `gh pr create`
5. 完成 S2 后，更新本文件第 6 节状态："S2 已完成 → 待 S3"

**开 S3 会话时**（需 `cd D:/carbon-shade-web`）：

1. 读本文件 Section 4 的 C1 / C2 / B1.carbon 三条
2. 单次会话内完成（都是 `settings.json` + frontmatter 改动）
3. 提 PR 后更新本文件状态

**遇到决策歧义时**：回看 Section 2-3 的"糟粕识别"和"关键互补观察"两段——那是设计的核心 invariant，违反它就要 stop and ask。

---

## 附录 A — 维度 3：上下文治理（速通版）

业界共识（2026）：CLAUDE.md **80-120 行最优 / ≤200 行推荐 / ≤300 行上限**；MEMORY.md **超 200 行被截断**；CLAUDE.md 是 *advisory* 非 mandatory（~70% 遵守率，强制要 hooks）；新 facility：`@import` 语法（5 层递归）/ `.claude/rules/` 路径作用域 / `subagent memory`（v2.1.33+）。

### Gap 矩阵

| 业界 baseline | carbon | harmony | 双向结论 |
|---|---|---|---|
| **CLAUDE.md ≤200 行** | ❌ 单文件 ≈21K（超 4-6 倍） | ✅ root 已分层 / AGENTS.md 449 行偏厚 | **carbon 拆分**（P0 / CT1）+ **harmony AGENTS.md 处理**（P2 / CT4） |
| **分层 / subdirectory CLAUDE.md** | ❌ | ✅ root + ets/ + cpp/ | **carbon ← harmony**（P0 顺带 CT1） |
| **.claudeignore** | ❌ | ✅ | **carbon ← harmony**（P0 / CT2） |
| **MEMORY.md ≤200 行** | ✅ 28 条 | ✅ 17 条 | 两边都安全 |
| **`@import` 语法模块化** | ❌ | ❌ | 两边都补（P1 / CT3） |
| **`subagent memory`（v2.1.33+）** | ❌ | ❌ | 两边都补（P1 / CT5，给 napi/combat reviewer 各配） |
| **statusline + status.json** | ✅ | ❌ | **harmony ← carbon**（P2，与 B3 合并） |

### 糟粕识别（明确不抄）

- `CONTEXT.md` / `SKILLS.md` registry —— 业界新概念但**未沉淀**
- `/compact 60%` 主动触发 —— 单会话技巧，跨会话设计无关
- Enterprise 三层（org/service/local）—— 个人项目无组织层
- `.claude/rules/` 路径作用域 —— CLAUDE.md 分层已够用

### P0 / P1 / P2

**P0**：
- **CT1**（carbon）：拆分 CLAUDE.md `21K → root ≤200 行 + 子目录 CLAUDE.md`。来源：harmony 分层 + [orchestrator size limits](https://orchestrator.dev/blog/2026-04-06--claude-code-agent-memory-2026/) + [HumanLayer writing-a-good-claude-md](https://www.humanlayer.dev/blog/writing-a-good-claude-md)。验收：`wc -l` 每个文件 ≤200。
- **CT2**（carbon）：抄 `.claudeignore`（屏蔽 dist/ node_modules/ .tmp/ verification/）。验收：carbon 内 Grep 不再扫到 dist/。

**P1**：
- **CT3**（两边）：引入 `@import` 串各 chunk。
- **CT5**（两边）：每个现有 agent 配同目录 `*.memory.md`（subagent memory，v2.1.33+）。

**P2 / 探索**：
- **CT4**（harmony）：AGENTS.md 449 行 → 探索拆 3-5 个 `.claude/rules/arkui-*.md` 路径作用域文件。**降级理由**：ArkUI 业务复杂，硬拆可能让规则查找更费劲；先用 root CLAUDE.md `@import AGENTS.md` 引用即可，等 ArkUI 模块自然演化再拆。

**P2 / 不做**：CONTEXT.md/SKILLS.md registry / /compact 60% / Enterprise 三层 / `.claude/rules/` 路径作用域。

---

## 附录 B — 维度 4：本地反馈 + CI 补齐（速通版）

业界共识（[DEV husky/pre-commit](https://dev.to/myougatheaxo/git-hooks-with-claude-code-build-quality-gates-with-husky-and-pre-commit-27l0) / [Lefthook](https://liambx.com/blog/ai-agent-lint-enforcement-lefthook-claude-code) / [Agentic pre-commit](https://www.linkedin.com/posts/nicholasmoore_agent-sdk-overview-activity-7426695024094113792-x9LR) / [anthropic/claude-quickstarts](https://github.com/anthropics/claude-quickstarts/blob/main/.pre-commit-config.yaml)）：**5 层反馈塔** = ① PostToolUse hook（per-edit）② pre-commit（lint-staged）③ commit-msg ④ pre-push ⑤ CI；Tier 1 = local pre-commit + Tier 2 = CI；PostToolUse 是 2026 关键升级（"finally brings Claude Code up to parity with Cursor"）。

### Gap 矩阵

| 业界 baseline | carbon | harmony | 双向结论 |
|---|---|---|---|
| **① PostToolUse 自动 validate** | ✅ `post-typecheck.mjs` (tsc) | ✅ `post-edit-cpp.sh` (codelinter 单文件) | **已做**（hooks 维度已收）|
| **② pre-commit git hook**（Husky / Lefthook / bash） | ❌ 靠手跑 `npm run analyze` | ❌ Stop hook 仅覆盖 Claude 路径；用户手动 `git commit` 裸奔 | **两边都补**（P1 / FB1）|
| **③ commit-msg hook** | ❌ | ❌ | **P2**（skill 已按格式生成，hook 重复）|
| **④ pre-push hook** | ❌ | ❌ | **P2**（CI 已覆盖）|
| **⑤ CI** | ✅ build-dnf-extract.yml | ✅ harmonyos-pr-ci + release | 已做 |
| **本地快反馈脚本（cursor 平价）** | ✅ npm run analyze (8 gates) | ✅ quick_signals.sh (~10s) | **已做** — 两边都不输业界 |
| **Agentic pre-commit（Claude SDK）** | ❌ | ❌ | **两边跳过**（ROI 低）|

### 糟粕识别（明确不抄）

- **Agentic pre-commit** —— 业界热点但个人项目 ROI 低（每次 commit 吃 API token）
- **5 层反馈塔全做** —— 个人项目 ①+②+⑤ 三层够，③④ 跳过
- **Lefthook 迁移 Husky** —— 个人项目尺度速度差异不显著，不划算迁
- **commit-msg 强制 Conventional Commits** —— 与 `auto-commit-cicd` skill 重复

### P0 / P1 / P2

**P0**：无（业界推 ② 缺位但不致命；cursor 平价快反馈 ①+⑤ 都做了）

**P1**：
- **FB1**（两边都补）：补 pre-commit git hook —— **保护"用户命令行手动 `git commit`"不经过 Claude 的路径**
  - carbon：`.husky/pre-commit` 跑 `npm run analyze`（首选 lint-staged 风格只跑 staged 文件）
  - harmony：`.git/hooks/pre-commit` 跑 `bash scripts/check/quick_signals.sh`（不用 Husky，HarmonyOS 工程非 Node）
  - 验收：本地 `git commit` 失败时拒绝提交 + 错误信息可读

**P2 / 不做**：commit-msg / pre-push / Agentic pre-commit / Lefthook 迁移 / 5 层全做。

### 关键互补观察

两边在维度 4 的现状**已经接近业界 best**——cursor 平价的本地快反馈 ①+⑤ 都做了。**唯一真实 gap 是 ②**（git pre-commit 层），且是因为"用户手动 commit 时不经过 Claude" 这条侧门才有意义。

---

## 附录 C — 维度 5：Agents（速通版）

业界共识 2026：`.claude/agents/<name>.md` 用 frontmatter `model`（sonnet/opus）+ `tools` 受限（review-only 只给 Read/Grep/Glob）+ `description` 决定 Claude 主动派的精度；推 review-only 不推 fix-agent（trust 问题）；多 agent 协作 = split-and-merge / sequential / orchestrator；description 写"Use when X ... NOT for Y"格式提高触发精度。

### Gap 矩阵

| 业界 baseline | carbon | harmony | 双向结论 |
|---|---|---|---|
| **review-only agent**（tools 限 Read/Grep/Glob） | ✅ `combat-kernel-reviewer` 1.6K（被 closed-loop 调） | ✅ `napi-boundary-reviewer` 7.3K（但**孤儿，无 skill 调用**） | **harmony 接入 closed-loop**（H2 自带；P0 顺带）|
| **model 档位 frontmatter** | ✅ sonnet | ✅ sonnet | 两边都做了 ✅ |
| **tools 受限** | ✅ | ✅ Read/Grep/Glob/Bash | 两边都做了 ✅ |
| **description "Use when X ... NOT for Y"** | ⚠️ 短描述 | ✅ napi-reviewer 明确写"NOT for general C++ review" | **carbon ← harmony**（P1 / AG1） |
| **fix agent 反模式** | ✅ closed-loop 明确反对（main Claude 自修） | N/A | 两边都遵守 ✅ |
| **多 agent 协作** | ⚠️ closed-loop 单 type 并行 dispatch（按 topic） | ❌ 单孤儿 | 个人项目 agent 少，不强推（P2） |

### 糟粕识别（明确不抄）

- **great_cto plugin 模式（7 个专业 agent 联动）** —— 个人项目过度
- **fix-agent / agent 调 agent 递归** —— 业界明确反对（trust 失控）

### P0 / P1 / P2

**P0**：无（H2 自带把 napi-reviewer 接入 closed-loop；其他已对位）

**P1**：
- **AG1**（carbon）：`combat-kernel-reviewer.md` description 加"Use when ... NOT for ..."模式（参考 harmony `napi-boundary-reviewer.md:3`），提高 Claude 主动派精度。

**P2 / 不做**：great_cto 多 agent 编排 / fix-agent / agent 递归调用。

---

## 附录 D — 维度 6：MCP servers（结论：non-gap）

业界共识：项目级 `.mcp.json` 固化项目所需 MCP（serena / cclsp / sequential-thinking 等），优势是跨开发者/跨机器一致；劣势是与用户全局 MCP 冗余。**个人项目场景**：除非项目绑特殊 MCP（如 LSP），否则用全局即可。

### Gap 矩阵 + 结论

| 业界 baseline | carbon | harmony | 结论 |
|---|---|---|---|
| **项目级 `.mcp.json`** | ❌ | ❌ | **两边都不补** —— 个人项目用全局即可，避免与 `~/.claude/mcp.json` 冗余 |
| **MCP 配置文件分离**（如 `.claude/cclsp.json`） | ❌（TS 用全局 typescript-lsp 够） | ✅ `.claude/cclsp.json` 绑 HarmonyOS NDK clangd | **carbon 不补**（无对应 LSP 特殊需求） |
| **MCP PATH/env Windows 坑** | N/A | N/A | 已在 memory `feedback_mcp_path_style` 沉淀 |

### 结论：维度 6 全部 P2 / 不做

两边的 MCP 现状（靠全局 + harmony 的 `cclsp.json` LSP 例外）**实际是个人项目的 best practice** —— 补项目级 `.mcp.json` 增加同步心智成本，性价比低。维度 6 是 **non-gap**，主要价值是确认现状合理。

---

## 附录 E — 相关 memory（背景上下文）

- `feedback_individual_project_workflow` —— 个人项目砍团队回路
- `feedback_agent_worktree_isolation` —— cwd 切换风险
- `feedback_force_converge_signal` —— input 预算硬刹车
- `feedback_claude_hook_command` —— hook command 自动加 `bash ` 前缀
- `feedback_setup_harness_first_before_coding` —— 本会话新增：外围搭齐再开工
