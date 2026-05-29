---
name: gc
description: |
  Run garbage collection for repository entropy: scan doc-drift +
  code-drift, append new technical debt items to docs/tech-debt-tracker.md.
  Use when 用户说 "/gc" / "跑 gc" / "扫熵" / "扫漂移" / 准备发版前
  / weekly 回顾. NOT for fixing the drift (人决策何时批量修).
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Glob
trigger: when user explicitly invokes /gc, OR says "扫熵 / 跑 gc / 漂移扫描 / weekly 清理"
---

# /gc — Repository Entropy Scan → Tech-Debt Append

## What this exists for

OpenAI Harness Engineering 的核心观察：**agent 生成速度 > 人工评审速度**，
坏模式（doc-drift、code-drift、过时注释、失效引用）会在 AI 辅助开发中快速累积。

本项目已有两道防线：

```
check_regression_guards.sh  ← 硬规则（mmap/TODO/LOG_DOMAIN 等）命中即 CI fail
/gc                         ← 软规则（doc-drift / code-drift）命中只警告 + 追加 debt
```

`/gc` 不替代 `check_regression_guards.sh`，也不替代 `/closed-loop`。
它是**周期性熵管理**：扫出漂移 → 追加到 `docs/tech-debt-tracker.md` →
人决定何时批量修（个人项目策略，见 memory `feedback_individual_project_workflow`）。

**不自动改代码，不自动开 PR。** 发现 ≠ 修复。

## When to invoke

Use this skill when:
- 用户显式 `/gc` 或 "跑 gc" / "扫熵" / "漂移扫描"
- 准备发版前 last-minute sweep（发版前必跑）
- 每周（周日 / 周一）回顾，清点累积债务

Do NOT use this skill for:
- 修具体 bug → 用 `/closed-loop`
- 自动 commit / 开 PR → 用 `/auto-commit-cicd`
- 文档校对 / 改 typo → 直接 Edit
- 快速构建健康检查 → `bash scripts/check/quick_signals.sh`

## Steps（4 步,5 段契约）

每步必备 5 段(契约缺失会让"完成"无 ground truth,见 memory `feedback_task_contract_missing`):
**Input** / **Goal** / **ROLE matrix** / **Output** / **Done criteria**

ROLE 4 层(见 memory `feedback_skill_role_separation`):L1 脚本(机械事实)/ L2 MCP(语义查询)/ L3 subagent(并行发现)/ L4 主 AI(推理判断)。
**越权(任何方向)= bug**。

### Step 1 — Doc drift scan

**Input**: 仓库当前 working tree(Git HEAD + 未提交改动)。

**Goal**: 列出所有"引用路径解析失败"的事实(机械层),零判断。

**ROLE matrix**:
- [L1 脚本] `bash scripts/gc/scan_doc_drift.sh` — 提取路径串 + `[ -e $path ]` 校验
- [L1 脚本] 占位符 `<>` / 省略号 `...` / 句末标点剥除(纯字符级,不识别语义)
- [NOT] 不识别"replaces"否定语境(L4 才能判)
- [NOT] 不识别 fenced code block(L4 才能判)
- [NOT] 不优先级判定(P0/P1/P2 是 L4 该 Step 3 做)

**Output**:
- `docs/gc-drift-report-<TS>.md`(TS = `date +%Y%m%d-%H%M%S`)
- 退出码:0 = clean / 1 = 有 drift(总数见 stdout + 报告 Summary)
- **下一步如何 trust**: 报告里每条 `X referenced in F:L -> MISSING` 是**候选**,需 Step 3 主 Claude 逐条语义判;不要把 scanner 输出直接当 finding。

**Done criteria**:
- [ ] 报告文件已生成
- [ ] stdout 显示 `Drifts found: N` 数字
- [ ] 退出码为 0 或 1(非 128/255 等截断值)

---

### Step 2 — Code drift scan

**Input**: 仓库当前 working tree。

**Goal**: 列出 `entry/src/main/**` 中匹配已知 anti-pattern 的事实(机械层),零判断。

**ROLE matrix**:
- [L1 脚本] `bash scripts/gc/scan_code_drift.sh` — pattern grep
- [NOT] 不判该 pattern 是否仍代表上游官方现状(rule lag 维度交 `/four-way-audit`)
- [NOT] 不优先级判定

**Output**:
- `docs/gc-code-drift-<TS>.md`(同一 TS)
- 退出码:0 = clean / 1 = 有 drift(各 Pattern 命中数见 stdout)
- **下一步如何 trust**: 各 Pattern 命中是候选,Step 3 主 Claude 决定哪些进 tracker。
- **若 Step 1+2 退出码均 0 → 输出 "✓ clean,无新 debt" 并停止**

**Done criteria**:
- [ ] 报告文件已生成
- [ ] 各 Pattern 命中数已输出(P1:N P2:N P3:N P4:N P5:N P6:N)
- [ ] 退出码为 0 或 1

---

### Step 3 — 提取 new debt(主 Claude 做)

**Input**:
- Step 1 产物 `docs/gc-drift-report-<TS>.md`
- Step 2 产物 `docs/gc-code-drift-<TS>.md`
- 现有 `docs/tech-debt-tracker.md`(查重用)

**Goal**: 从 scanner 候选中筛掉假阳性 + 重复,产出**真新 debt 候选清单**给用户 checkpoint。

**ROLE matrix**:
- [L4 主 AI] **语境识别**:每条 MISSING 看上下文 5-10 行,是否在否定语境(replaces / removed / deprecated / 不存在)
- [L4 主 AI] **代码块识别**:是否在 ```fenced``` block 或 inline `bash` 命令里
- [L4 主 AI] **跨仓库识别**:路径前是否有跨仓库前缀(`/d/foo/...`)被中段截取
- [L1 Bash 实测] 不确定时 `ls $path` 实测验证
- [L4 主 AI] **优先级判定**:P0(运行时/安全/数据)/ P1(可维护)/ P2(风格)
- [L4 主 AI] **查重**:tech-debt-tracker.md 是否已有同 file:line
- [NOT] **不眼神判一批**(本会话 19 项"全是假阳性"翻车,实际混 3 真 drift)
- [NOT] 不做 rule lag verify(交 /four-way-audit)
- [NOT] 不自动追加(必走 checkpoint)

**Output**:
- 候选 debt 清单(展示给用户,内存中)
- 每条标注:`[verified: ls 已查]` / `[skipped: scanner 噪音]` / `[duplicate: D<NNN>]`
- **下一步如何 trust**: 用户 checkpoint 选择追加范围 → Step 4 严格按选择 Edit。

**Done criteria**:
- [ ] 每条 scanner 输出已逐条标注(无遗漏)
- [ ] 真新候选数 / 重复数 / 假阳性数 三个数字明确
- [ ] checkpoint 已展示(展示但未追加)

候选条目格式:
```
| D<NNN> | <P0/P1/P2> | <file:line> | <一句话描述> | gc-<TS> | open |
```

─── CHECKPOINT(MANDATORY HUMAN)───
展示:新增候选 N 条,其中 P0=a / P1=b / P2=c
询问:[全追加 / 只追加 P0+P1 / 让我挑 / 跳过]
**不得跳过此 checkpoint,不得自动追加。**

---

### Step 4 — Append to tech-debt-tracker.md(经用户确认后)

**Input**: Step 3 产物候选清单 + 用户 checkpoint 选择范围。

**Goal**: 严格按用户选择把候选写入 tech-debt-tracker.md,不增不减。

**ROLE matrix**:
- [L4 主 AI] Edit `docs/tech-debt-tracker.md` 在 `## Debt list` 末尾追加
- [L1 机械] 编号从现有最大 D<NNN> 递增,不跳号
- [NOT] 不 commit(用户自己决定)
- [NOT] 不修改其他段(只 append 到 Debt list)

**Output**:
- `docs/tech-debt-tracker.md` 已 append N 条
- 摘要输出(stdout):"已追加 D<NNN>-D<NNN+M>,P0=a P1=b P2=c"
- **下一步如何 trust**: 用户自行 commit 或继续别的工作。

**Done criteria**:
- [ ] tech-debt-tracker.md 包含新 D<NNN> 条目
- [ ] 编号连续递增,无跳号
- [ ] 无 git add / git commit 调用

─── 不要 commit ───
追加完成后只输出摘要,不执行 `git add` / `git commit`。
用户决定何时 commit(见 memory `feedback_individual_project_workflow`)。

## State machine: resuming from partial run

上次 `/gc` 中途断开时，按以下规则续跑：

```
检查 docs/ 下最新的 gc-* 文件：
  ls docs/gc-*-report-*.md 2>/dev/null | sort | tail -1
  ls docs/gc-code-drift-*.md 2>/dev/null | sort | tail -1

情况 A: gc-drift-report-<TS>.md 存在，gc-code-drift-<TS>.md 不存在
  → 跳过 Step 1，从 Step 2 续跑（使用已有 TS）

情况 B: 两份报告都存在，tech-debt-tracker.md 未更新（对比报告 TS 与 tracker 最后修改时间）
  → 跳过 Step 1+2，从 Step 3 续跑（Read 已有两份报告）

情况 C: 两份报告都存在，tracker 已更新
  → 本轮 gc 已完成，输出摘要后停止
```

不写死 TS，始终用 `| sort | tail -1` 拿最新一份。

## Anti-patterns to refuse

| 请求 | 拒绝理由 |
|---|---|
| "gc 完顺便 commit 追加的 debt" | Step 4 后不 commit，人决定；见 memory `feedback_individual_project_workflow` |
| "gc 完自动开 PR 修扫出来的 debt" | 个人项目不需要 PR 流程；同上 |
| "/gc 顺便修了所有 P0" | /gc 只扫不修；真要修走 `/closed-loop` |
| "/gc 跑前先 git pull" | 只读本地状态，不 pull |
| "跳过 Step 3 的 checkpoint 直接追加" | checkpoint 是强制人工确认，不可绕过 |
| "30 条同 pattern 告警先全追加再优化" | 噪音让用户对 gc 报告失去信任;同 pattern 批量告警应先逐条 ls 实测,该撤的撤 |
| "/gc 顺便检查规则是否过时" | rule lag 维度交 `/four-way-audit`;/gc 只做引用解析 + scanner pattern |

## Reference

```
Doc drift scanner:          scripts/gc/scan_doc_drift.sh
Code drift scanner:         scripts/gc/scan_code_drift.sh
Debt sink:                  docs/tech-debt-tracker.md
Closed-loop (fix-side):     .claude/skills/closed-loop/SKILL.md
Auto-commit (commit-side):  .claude/skills/auto-commit-cicd/SKILL.md
Harness engineering origin: https://openai.com/index/harness-engineering/
Individual project workflow: memory feedback_individual_project_workflow
```
