---
name: four-way-audit
description: |
  四方一致性审查 — git / code / md / memory 四个事实源深度阅读 + 跨维度对比,
  抓概念脱节 / 规则滞后 / deprecated 仍推荐 / stale snapshot / 内容矛盾。
  Use when 用户说 "/four-way-audit" / "四方一致性" / "四维审查" / "跨维度对齐"
  / "deprecation drift" / "概念口径" / 季度回顾 / 重大重构前。
  NOT for 路径引用扫描(走 /gc)、bug 修复(走 /closed-loop)、PR 合并(走 /auto-commit-cicd)。
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, mcp__web-search__web_search, mcp__web-search__web_fetch, mcp__cclsp__find_workspace_symbols, mcp__serena__list_memories, mcp__serena__read_memory
trigger: when user explicitly invokes /four-way-audit, OR says "四方一致 / 四维审查 / 跨维度对齐 / deprecation drift / 季度审计"
---

# /four-way-audit — Cross-Source Consistency Audit

## What this exists for

`/gc` 只能看引用路径解析得到不,**抓不到**:
- 本地规则 vs 上游官方脱节(本地禁 V1 反模式,上游 V2 已允许)
- deprecated 决策没扩散(memory 弃 firecrawl,但 CLAUDE.md 还在推)
- 概念口径不统一(commit 说"9→8 step",SKILL 标题"9 steps")
- stale snapshot(memory 记 "15 个 docs/plans",今日 17 个)
- 内容矛盾(A.md 说 X,B.md 说 ¬X)

这些是**跨事实源对比 + 主 Claude 阅读推理**才抓得到的 drift,无法用 grep 脚本扫。
本 skill 沉淀 commit `1e876e8` 那次手工审计的 6 层方法论。

## 四方事实源

| 源 | 范围 | 典型查询 |
|---|---|---|
| **git** | HEAD + 最近 N 条 commit + working tree | `git log --oneline -20`, `git diff`, `git log -S <keyword>` |
| **code** | `.claude/{skills,agents,hooks}` + `scripts/` + `src/` | Read 各 SKILL.md / 关键 .cpp/.ets / scripts/ |
| **md/docs** | `CLAUDE.md` × N + `AGENTS.md` + `docs/**` | Glob `**/*.md` + Read |
| **memory** | `~/.claude/projects/<proj>/memory/*.md` + MEMORY.md | `mcp__serena__list_memories` + Read |

## When to invoke

Use this skill when:
- 用户显式 `/four-way-audit` / "四方一致性" / "四维审查"
- 重大重构前(确保各源一致再动)
- 季度/半年回顾(熵积累后整体对账)
- 发现单点 drift 后,怀疑同类型多发
- 沉淀 feedback_*_deprecated 后(同会话扫一次扩散)

Do NOT use this skill for:
- 路径引用断裂扫描 → `/gc` 已覆盖
- 修具体 bug → `/closed-loop`
- 自动 commit/PR → `/auto-commit-cicd`
- 单文件 typo → 直接 Edit

## 6 层方法论(L1-L6)

### L1 — 四方快照(基础数据采集)

并行做 4 个采集,产 4 张事实清单:

```bash
# git 侧
git log --oneline -30
git status --short
git diff --stat HEAD~10..HEAD

# code 侧 — 配置/工具/脚本
ls -la .claude/{skills,agents,hooks}
ls scripts/{ci,check,gc}
cat .claude/settings.json

# md/docs 侧
find . -name 'CLAUDE.md' -o -name 'AGENTS.md' 2>/dev/null
ls docs/plans/ docs/audit/ 2>/dev/null
```

```
# memory 侧 (mcp)
mcp__serena__list_memories
Read C:/Users/newwo/.claude/projects/<proj>/memory/MEMORY.md
```

**产出**: 心里记住 4 张表,不必落地写 — 后续比对用。

### L2 — 横切(数量层)

10 项左右的 invariant 数量检查,期望值 vs 实测,全绿才进 L3:

| 典型项 | 期望来源 | 检查方式 |
|---|---|---|
| skills 数 | MEMORY.md / CLAUDE.md 索引 | `ls .claude/skills/` |
| agents 数 | 同上 | `ls .claude/agents/` |
| hooks 数 | settings.json hooks 段 | grep hooks 数 |
| memory N 文件 vs MEMORY.md 索引 N 行 | 应相等 | `ls memory/*.md \| wc -l` vs `grep -c '^- \[' MEMORY.md` |
| CLAUDE.md @import target | @import 列表 | `[ -e $target ]` 逐个验 |
| regression guards 类数 | check_regression_guards.sh banned 数 | grep |

**输出格式**:

```
| # | 指标 | 期望 vs 实际 | 状态 |
|---|---|---|---|
| HX1 | skills 数 | 4 (gc/four-way-audit/closed-loop/auto-commit-cicd) | ✅ |
```

L2 出 drift 即 P0/P1 — 数量级错配是硬 bug,不是叙事 drift。

### L3 — 竖切(行为层)

每个新近 commit / 重大决策 / harness 改造,验证"真的能跑通"。这层是核心。

| # | 验证项 | 实测方式 | 成熟度 |
|---|---|---|---|
| ZQ1 | <commit X 的特性> | <Read 关键文件 + 实跑 / Bash 试运行 / mcp 试调> | **stub** / **编译** / **测试** / **跑通** |

成熟度阶梯(从低到高):
- **stub** — 只有 markdown,代码空
- **编译** — 代码在,跑过一次但无回归测
- **测试** — 有 fixture / regression guard
- **跑通** — 真实场景跑过,有产物证据(如 `.last-quick-signals.txt`)

L3 出 drift 即 **stub-级 drift**(声称跑通,实测 stub) — 是叙事 vs 实物的脱节。

### L3.5 — 规则 vs 上游 web verify(2026-05-29 加)

L3 验证项中**凡是基于"本地规则"判违规/通过的**,必跑 `mcp__web-search__web_search` 核对上游官方现状:

```
1. 识别 finding 引用的本地规则(CLAUDE.md / AGENTS.md / SKILL.md / memory 某条)
2. 提取规则核心声明(e.g. "禁止 @State 复杂类型")
3. web verify
   query: "<framework> <feature> <year> best practice"
   e.g. "ArkTS @State decorator complex object 2026 best practice"
4. 对比
   - 一致 → finding 成立
   - 上游已演进 → finding 撤回 + 加 meta-finding(本地规则需更新)
```

**例外**(可跳 verify):
- 项目业务约定(LOG_DOMAIN / EmuUiTokens / 路径 glob)
- 安全/正确性硬约束(mmap NativeBuffer / 跨线程加锁)
- session 内 < 30 分钟刚下的决策

详见 memory `feedback_local_rule_may_lag_upstream`。

### L4 — SOT 盘表(Single Source of Truth)

列出每个关键主题的 SOT,看是否有重复定义 / 冲突:

| 主题 | SOT | 派生引用方 | 一致? |
|---|---|---|---|
| 闭环步骤定义 | `.claude/skills/closed-loop/SKILL.md` | commit msg / memory / docs/audit | ✅ |
| 8 类 banned-pattern | `scripts/ci/check_regression_guards.sh` | `entry/src/main/cpp/CLAUDE.md` 列举 | ✅ |
| ArkUI 规范 | `.claude/skills/arkui-design/references/` | AGENTS.md / `entry/src/main/ets/CLAUDE.md` | ? |

发现重复定义/冲突即 P1 — 派生方必须只 link 不复制。

### L5 — 机制 vs 纪律分账

对每条 drift,判治理路径:

| Finding | 治理 | 备注 |
|---|---|---|
| F1 | **机制** | 加 hook / scanner pattern / CI guard |
| F2 | **纪律**(memory) | 加 `feedback_*.md` 提醒下次 |
| F3 | **混合** | 主路径机制 + 边界靠纪律 |

**机制 > 纪律** — 同类 drift 反复出现就该升级机制。
不滥用机制 — 一次性 / 个体 drift 用纪律即可。

### L6 — 现场处理 + 报告 + 沉淀

按优先级分桶处理:

| 级别 | 当场处理? | 沉淀 |
|---|---|---|
| **P0**(安全/数据) | 立刻修 | report + memory |
| **P1**(行为漂移) | 同会话现场修 | report |
| **P2**(叙事漂移) | 当场修 OR 进 tech-debt-tracker | report |
| **P3**(scanner 自身 bug) | 当场修工具 | 不进 tracker(harness 自身 bug 不积压) |

报告路径: `docs/four-way-audit-<TS>.md`,TS = `date +%Y%m%d-%H%M%S`。

报告必须包含:
1. 4 张事实快照(L1)
2. L2 横切表
3. L3 竖切表 + L3.5 web verify 结论
4. L4 SOT 盘表
5. L5 机制/纪律分账
6. L6 修复汇总 + DEFER 项进 `docs/tech-debt-tracker.md`

## Steps 流程(对应 6 层)

```
Step 1: L1 四方快照采集(并行)
Step 2: L2 横切扫描 → 出 drift 即 P0/P1
Step 3: L3 竖切扫描 + L3.5 web verify 嵌入
Step 4: L4 SOT 盘表
Step 5: L5 机制/纪律分账
Step 6: L6 现场修 + 报告 + tech-debt 追加(经 user CHECKPOINT)

─── CHECKPOINT(MANDATORY HUMAN, Step 6 前) ───
展示: P0=a / P1=b / P2=c / P3=d 分桶
询问: [全现场修 / 选择性现场修 / 只 P0+P1 修 P2 进 tracker / 跳过]
不得跳过 checkpoint,不得自动 commit。
```

## Anti-patterns to refuse

| 请求 | 拒绝理由 |
|---|---|
| "/four-way-audit 顺便 commit" | Step 6 后不 commit;commit 由 `/auto-commit-cicd` 或用户决定 |
| "/four-way-audit 顺便修所有 P0" | P0 当场修是默认动作,不是顺便;P1/P2 必须经 checkpoint |
| "跳过 L3.5 web verify" | 本地规则可能滞后(`feedback_local_rule_may_lag_upstream`);未 verify 不得判 finding 成立 |
| "L1 只看 git,跳过 memory" | 四方缺一 = 不叫四方一致性;memory 是高频脱节源 |
| "用 grep 扫一遍替代 L3 竖切" | L3 是行为验证,grep 只看字面;每项必须 Read 关键文件 + 实测 |
| "本会话连跑两次 /four-way-audit" | 间隔 < 24h 重跑无新信息;除非 session 内做了重大改动 |

## Dogfood 验收

重构 / 修订本 skill 后,必须能抓到以下 5 个历史案例(否则白做):

1. **F1 secret in settings.json**(commit `1e876e8`)— L1 git diff + L6 P0 现场修
2. **F2 firecrawl 弃用未扩散**(同上)— L4 SOT(memory)vs L3 派生引用(CLAUDE.md)冲突
3. **F3 closed-loop "9 step" vs "8 step"**(同上)— L4 SOT 派生不一致
4. **本会话 R1 audit-verify.mjs 缺失**— L3 竖切实测 / `/gc` 也能抓
5. **本会话 @State V1/V2 脱节**— L3.5 web verify

## Reference

```
6 层方法论原型:           commit 1e876e8 + docs/gc-four-way-audit-20260528-1745.md
SOT-style audit 参考:    .claude/skills/closed-loop/SKILL.md (audit/fix-verify)
路径扫描 SKILL(配套):     .claude/skills/gc/SKILL.md
Web verify mcp 工具:     mcp__web-search__web_search / web_fetch
关键 memory:
  - feedback_local_rule_may_lag_upstream    (L3.5 规则验证)
  - feedback_deprecation_drift_needs_mechanism (L4-L5 deprecation 扩散)
  - feedback_individual_project_workflow    (个人项目 checkpoint 节奏)
```
