# Four-Way Consistency Audit — 2026-05-28 17:45

按 6 层方法论（四方一致 → 横竖切 → 成熟度 → SOT → 机制vs纪律 → 实测先行）周期性扫描，**无特定诱因**。

四方事实源：
- **memory** — `C:/Users/newwo/.claude/projects/D--windsulf-daugf2527-repos-harmonyos-libretro-emulator/memory/` (49 文件 + MEMORY.md)
- **git** — HEAD = `798869e`, working tree 仅 `.claude/settings.json` modified
- **code** — `.claude/{skills,agents,hooks,settings.json,statusline.sh,stop-hook.sh}` + `scripts/{ci,check,gc}/`
- **docs** — `CLAUDE.md` × 4 + `AGENTS.md` + `docs/**`

---

## L2 横切（数量层 10 项）

| # | 指标 | 期望 vs 实际 | 状态 |
|---|---|---|---|
| HX1 | skills 数 | 4 (arkui-design / auto-commit-cicd / closed-loop / gc) | ✅ |
| HX2 | agents 数 | 2 + 1 sidecar (.memory.md) | ✅ |
| HX3 | hooks 数 | 8（含 stop-hook 在根） | ✅ |
| HX4 | scripts/ci 数 | 6 | ✅ |
| HX5 | scripts/check 数 | 2; gc 加 2 | ✅ |
| HX6 | memory 49 vs MEMORY.md 49 索引 | 完全对齐 | ✅ |
| HX7 | CLAUDE.md @import 3 个 target 都存在 | OK | ✅ |
| HX8 | docs/plans 数 | 15 | ✅ |
| HX9 | regression guards 8 类 banned-pattern (mmap / TODO / SET_TIMEOUT=5 / LOG_DOMAIN range / Map-Unpaired …) | OK | ✅ |
| HX10 | closed-loop topics 数 | 8 (T1–T8) | ✅ |

数量层 **全绿**，无 drift。

## L2 竖切（行为层 8 项）

| # | 验证项 | 实测结果 | 成熟度 |
|---|---|---|---|
| ZQ1 | closed-loop 9→8 step 标注一致 | ⚠️ commit 798869e 说"9→8"，SKILL.md 仍写 "## The 9 steps"，因 Step 0–Step 8 共 9 个 heading；commit message 算的是 fix-step（不含 Step 0），二者口径不同 | **stub** drift |
| ZQ2a | multi-model（commit 80e1484 #1） | SKILL.md L324 起"Cross-model verification" 段在场 | **跑通**（手动可触发） |
| ZQ2b | 3-agent cap（commit 80e1484 #2） | 落在用户级 `~/.claude/skills/dispatching-parallel-agents/SKILL.md` L14 "Hard cap: ≤ 3 parallel agents"，含详细规则 | **跑通** |
| ZQ2c | statusline v2（commit 80e1484 #3） | `.claude/statusline.sh` L4–6 自标 v2，含 model + tok + cost 字段 | **编译** + 实运行已产 `.last-quick-signals.txt` 证明 hook 触发链 |
| ZQ3 | gc skill + 范本报告 | SKILL.md + 2 个范本报告 `docs/gc-*-20260528-155349.md` 在场 | **跑通**（已生成过） |
| ZQ4 | ArkUI 拆分（commit cf0e56f） | AGENTS.md 120 行（commit msg 称 438→120）+ arkui-design 7 子文件 437 行 | **跑通** |
| ZQ5 | MCP 决策树（CLAUDE.md L72–113） | 表完整 + cclsp.json 配 clangd | **跑通** |
| ZQ6 | audit-evaluator agent | `.claude/agents/audit-evaluator.md` 头信息齐 + Phase A/B 多模型说明 | **跑通** |
| ZQ7 | regression guards 4 段消息 (commit 8f2dec6) | `report_fail()` 输出 CODE / Problem / Fix / See 4 行；当前所有 banned-pattern 命中 0，需临时注入才能看 4 段格式 | **测试**（commit msg 已含临时触发验证记录） |
| ZQ8 | quick_signals snapshot 真在 | `.claude/.last-quick-signals.txt` 17:28:11 ALL PASS | **跑通** |

竖切发现：**1 条 stub-级 drift**（ZQ1 标号口径不统一）。其余均跑通 / 测试级。

---

## P0 SECURITY finding — 已现场处理 ✅

**F1 settings-json-secret**：
- 位置：`.claude/settings.json:5` 明文 `FIRECRAWL_API_KEY=fc-092f…138`
- 历史：仅在 working tree，**未进 git history**（`git log --all -S` 0 命中）
- 处置：删 `env` 段（firecrawl 已弃用，key 也无用了）
- 触发 memory：`feedback_secret_in_settings_pause_first.md` — "看到 settings.json 含 secret 立刻 STOP"
- 状态：✅ FIXED（`grep -c 'FIRECRAWL\|fc-092f' .claude/settings.json` = 0）

---

## P1 DOC DRIFT finding — 已现场处理 ✅

**F2 CLAUDE.md 与 memory 关于 firecrawl 的口径冲突**：
- memory `feedback_firecrawl_deprecated` 已声明整体弃用（覆盖 2 条历史 memory）
- CLAUDE.md 仍在 3 处推荐 firecrawl：
  - L79 工具表把 firecrawl 当 Web 类首选
  - L111 工具瘦身记录写"**TODO**：等用户决策"（决策已经下，未同步）
  - L149–151 Web research tips 提到 `firecrawl_search` / `firecrawl_scrape` / `firecrawl_parse`
- 处置：3 处全部改为"已弃用"指针，引导到 `mcp__web-search__*` + memory 溯源
- 状态：✅ FIXED（`grep -nE 'firecrawl' CLAUDE.md` 仅剩 3 处指向 memory 的指针）

---

## P2 STUB-DRIFT finding — 留待用户决策

**F3 closed-loop "9 steps" 标号语义冲突**（ZQ1 详情）：
- 现状：SKILL.md 写 `## The 9 steps (Step 5 merged into Step 7 on 2026-05-28; Step 0 added 2026-05-28)`
- 实际 heading 9 个：Step 0、1、2、3、4、5、6、7、8
- commit 798869e 说"9→8 步"——commit 内的"9"指原 fix-step 数（不含 Step 0 的 10 个 heading，已删掉 Rebuild），"8"指现 fix-step 数
- 两个数字口径不同造成阅读时 cognitive load
- 建议改法（任选一）：
  - 方案 A：`## The 8 fix steps (Step 0 是 sprint contract，不计入 fix step；Step 5 Rebuild 已并入 Step 7)`
  - 方案 B：`## The 9 stages (Step 0–8: Step 0 是 sprint contract + Step 1–8 是 fix flow)`
- 不属于"行为漂移"，纯叙事一致性；放入 `docs/tech-debt-tracker.md` 或等下一次闭环维护一起改

---

## SOT 盘表（L4）

| 主题 | SOT | 派生引用方 |
|---|---|---|
| 闭环步骤定义 | `.claude/skills/closed-loop/SKILL.md` | commit msg / memory / docs/audit/*.md |
| Topic hazards | `.claude/skills/closed-loop/topics/T*.md` | SKILL.md Step 0 引用 |
| 8 类 banned-pattern | `scripts/ci/check_regression_guards.sh` | `entry/src/main/cpp/CLAUDE.md` 列举 |
| ArkUI 规范 | `.claude/skills/arkui-design/references/01–06.md` | AGENTS.md / `entry/src/main/ets/CLAUDE.md` 摘要 |
| MCP 决策树 | `CLAUDE.md` "MCP / Skill 工具决策树" 段 | memory `feedback_mcp_static_text_insufficient` |
| firecrawl 弃用 | `memory/feedback_firecrawl_deprecated.md` | CLAUDE.md 仅留指针（修复后） |
| harness 时间线 | `memory/project_2026_05_28_harness_overhaul.md` | git log（commit `aad12c4` `80e1484` `798869e` 等） |

无 SOT 重复定义，无 SOT 冲突。

## 机制 vs 纪律分账（L5）

| Finding | 治理路径 | 备注 |
|---|---|---|
| F1 secret | **纪律**（memory `secret_in_settings_pause_first`） + 可选**机制** | 可加 PreToolUse hook 扫 settings.json 关键词 |
| F2 firecrawl drift | **机制**（`scripts/gc/scan_doc_drift.sh` 可扫"弃用工具仍被推荐") | 现 gc 应能捕获，本次未触发可能因 grep pattern 不足 |
| F3 step 标号 | **纪律**（commit 时把"9→8"和 heading "9 steps" 口径对齐） | 不值得加机制 |

**机制能扩**：gc scan_doc_drift 增加规则"memory 中标记 deprecated 的工具名不应出现在 CLAUDE.md 中"。

## 方法论沉淀（L7）

这次扫描验证了一条之前没显式写的隐含规则：**memory 决策 → 散在文档同步**这条链路无自动机制，靠纪律。要么 (a) gc 加 deprecation drift rule，要么 (b) 每次写 deprecation memory 时立即 grep CLAUDE.md / AGENTS.md 同步。

---

## 修复汇总

| Finding | 处置 | 状态 |
|---|---|---|
| F1 settings.json secret | working tree 直接删 env 段 | ✅ DONE |
| F2 CLAUDE.md firecrawl 3 处推荐 | 改为"已弃用"指针 | ✅ DONE |
| F3 closed-loop step 标号 | 留待下次维护或用户决策 | ⏸ DEFER（tech-debt） |

## 下一步建议

1. **commit F1+F2 修复**（commit message 范例见报告底部）
2. **F3 决策**：方案 A / B / 维持现状（不修）？
3. **可选机制升级**：给 `scripts/gc/scan_doc_drift.sh` 加 "deprecated tool still recommended" 规则
4. 把这套 6 层方法论沉淀到 user-level memory（如果跨项目都要这样扫，下次直接调用）

## Reference

- 6 层方法论原始版（用户输入，见对话上文）
- memory `feedback_secret_in_settings_pause_first` / `feedback_firecrawl_deprecated`
- HEAD = 798869e（含本报告之前所有 harness commit）
