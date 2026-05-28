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

## Steps（4 步）

### Step 1 — Doc drift scan

```bash
bash scripts/gc/scan_doc_drift.sh
```

- 扫描对象：`CLAUDE.md` / `AGENTS.md` / `docs/plans/*.md` / `docs/tech-debt-tracker.md`
  中引用的文件路径、函数名、章节标题是否仍然存在于代码库
- 输出：`docs/gc-drift-report-<TS>.md`（TS = `date +%Y%m%d-%H%M%S`）
- 退出码 = drift 总数（0 = clean）
- 若脚本不存在 → 报错停止，不继续 Step 2

### Step 2 — Code drift scan

```bash
bash scripts/gc/scan_code_drift.sh
```

- 扫描对象：`entry/src/main/cpp/**/*.cpp` / `entry/src/main/ets/**/*.ets`
  中的软规则违反（过时 API 用法、已知 anti-pattern、注释里的 TODO/FIXME 残留）
- 输出：`docs/gc-code-drift-<TS>.md`（同一 TS）
- 退出码 = drift 总数（0 = clean）
- 若 Step 1 退出码 = 0 且 Step 2 退出码 = 0 → 输出 "✓ clean，无新 debt" 并停止

### Step 3 — 提取 new debt（主 Claude 做，非自动）

Read 两份报告，提取**新的、有具体 `file:line` 的** drift 条目。

对每条 drift：
1. 检查 `docs/tech-debt-tracker.md` 里是否已有同样 `file:line` 的 debt 条目
2. 没有 → 生成候选 `D<NNN>` 条目（编号 = 现有最大编号 + 1 起递增）
3. 有 → 跳过（不重复追加）

候选条目格式：
```
| D<NNN> | <P0/P1/P2> | <file:line> | <一句话描述> | gc-<TS> | open |
```

优先级判断：
- **P0**：影响运行时正确性 / 安全 / 数据丢失
- **P1**：影响可维护性 / 跨层一致性
- **P2**：风格 / 注释 / 文档漂移

把候选列表展示给用户，等待确认。

─── CHECKPOINT（MANDATORY HUMAN）───
展示：新增候选 N 条，其中 P0=a / P1=b / P2=c
询问：[全追加 / 只追加 P0+P1 / 让我挑 / 跳过]
**不得跳过此 checkpoint，不得自动追加。**

### Step 4 — Append to tech-debt-tracker.md（经用户确认后）

```
Edit docs/tech-debt-tracker.md
在 "## Debt list" 章节末尾追加用户确认的条目
编号从现有最大 D<NNN> 递增，不跳号
```

─── 不要 commit ───
追加完成后只输出摘要，不执行 `git add` / `git commit`。
用户决定何时 commit（见 memory `feedback_individual_project_workflow`）。

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
