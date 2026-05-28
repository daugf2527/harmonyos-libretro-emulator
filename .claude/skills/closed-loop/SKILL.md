---
name: closed-loop
description: |
  Run the full audit → core-review → fix → fix-verify → gate → commit
  workflow on a harmony stage topic (NAPI / Engine / Audio / Video /
  NativeBuffer / Resource lifecycle / Input+EventBridge /
  SaveState+SRAM+Disk). Use when user says "跑闭环 X" / "audit + 修 X" /
  "完整审一下 X" / "/closed-loop". Drives the 9-step trust chain
  end-to-end with 4 mandatory human checkpoints.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Agent, TaskCreate, TaskUpdate, TaskList, TaskGet
model: sonnet
trigger: when user explicitly invokes /closed-loop, OR says "完整闭环走一遍 / audit + 修 / 闭环跑 X"
---

# /closed-loop — Audit → Core-Review → Fix → Verify → Commit (harmony)

## What this exists for

`scripts/check/quick_signals.sh` proves build/regression hygiene but
**doesn't catch semantic / cross-language / NativeBuffer-lifecycle
bugs**. The closed-loop catches what fast signals can't, and crucially
does it with **machine-re-verifiable trust between every stage**:

```
sub-agents (broad discovery, parallel by topic)
    ↓ each finding has structured citation (file:line + evidence_excerpt)
    ↓ main Claude MECHANICALLY re-reads cited file:line via Read + grep
main Claude (single reviewer + implementer)
    ↓ judges REAL / REAL_LOWER / DESIGN / FALSE_POSITIVE per-finding
    ↓ fixes REAL findings directly via Edit
    ↓ if fix touches entry/src/main/cpp/app/napi/** → MUST dispatch
      napi-boundary-reviewer agent BEFORE applying the edit
    ↓ re-dispatches same audit topic on the fix code
sub-agents (fix verification)
    ↓ each fix-finding cites the fix code (where the new guard lives)
    ↓ main Claude re-verifies fix citations via Read + grep
gate gauntlet (bash scripts/check/quick_signals.sh)
    ↓ green
human checkpoint
    ↓ approves commit message + scope
git commit
```

**No step trusts the previous step's claim.** This is harmony's adapted
form of the trust chain pattern; see [[harness-fusion-2026-05-24]].

## When to invoke

Use this skill when:
- User explicitly says `/closed-loop` or "跑闭环" / "audit + 修" / "完整审"
- User asks to deep-audit + fix a specific scope (one of the 8 topics
  below, or a custom scope)
- A major milestone is about to commit and we want one last semantic sweep

Do NOT use this skill for:
- Quick sanity check (use `bash scripts/check/quick_signals.sh`)
- Single-file lookup (use Read/Grep)
- Plain agent dispatch without verification (just use `Agent` tool directly)
- UI / ArkTS-only fixes (different workflow, ts/ets layer doesn't have
  NativeBuffer lifetime hazards that justify the full 9-step gauntlet)

## Topics (8 fixed, harmony-tuned)

| ID | Name | Scope | Hazards |
|---|---|---|---|
| **T1** | NAPI 边界 | `entry/src/main/cpp/app/napi/` | env lifetime / TSFN thread / ArkTS↔C++ type / error-throw / ref+buffer lifecycle |
| **T2** | Engine 状态机 | `entry/src/main/cpp/core/engine/libretro_engine.*` | state transitions / message queue races / retro_run reentrancy / cleanup ordering |
| **T3** | Audio bridge | `entry/src/main/cpp/platform/audio/audio_bridge.*` | resampler buffer ownership / DRC bounds / ring buffer race / underrun handling |
| **T4** | VideoPipeline | `entry/src/main/cpp/core/engine/video_pipeline.*` + renderer | pixel format negotiation / geometry resize / Hardware/Software/GLES/Vulkan switch / NativeBuffer dequeue/queue |
| **T5** | NativeBuffer 用法 | cross-cutting: any code calling `OH_NativeBuffer_*` / `OH_NativeWindow_*` | acquire/release pairing / format mismatch / map/unmap pairing / use-after-free |
| **T6** | 资源生命周期 | XComponent / NativeWindow / EGL surface / file descriptors / SRAM/SaveState | surface recreation under config change / fd leaks / atomic save guarantees |
| **T7** | Input / EventBridge 跨层 | `cpp/app/napi/engine_input_napi.cpp` + `core/engine/event_bridge.cpp` + `core/input/input_snapshot.h` + `core/input/input_port_router.cpp` + `ets/common/LibretroEventHub.ets` + `ets/common/RuntimeInputCommandBridge.ets` + `ets/common/RuntimeInputPortController.ets` + `ets/pages/MultiplayerInputPage.ets` | input snapshot atomicity / 整数溢出 / TSFN release+abort 顺序 / CallJsHandler pending-exception / 跨层 event 路由 (ArkTS hub ↔ C++ bridge ↔ libretro input) / engine-ready guard / async lifecycle (replayLatest catch / removeListener / Hub singleton destroy) / NAPI error-throw helper 一致性 |
| **T8** | SaveState / SRAM / Disk I/O 持久化 | `cpp/core/engine/core_state_manager.*` + `core/engine/libretro_engine.cpp` (SaveState/SRAM/Disk 路径) + `cpp/core/libretro/disk_controller.*` + `cpp/app/napi/engine_state_napi.cpp` + `cpp/app/napi/engine_disk_napi.cpp` + `ets/common/SaveStateRepository.ets` + `ets/common/LibrarySaveFilePurger.ets` + `ets/common/RuntimeSaveStateController.ets` + `ets/pages/SaveStatePage.ets` + `ets/pages/LibretroGamePage.ets` (quick save/load 路径) | state-machine guard (GAME_LOADED required) / retro_serialize+retro_get_memory_data 线程模型 (Engine thread + ExecuteSyncTask) / DiskController callbacks_ 在 core unload 时悬空 / EngineSyncTask 超时栈悬挂 TOCTOU / NAPI async_work + napi_cancelled guard / ArkTS 文件 I/O 原子写 (tmp+rename) + manifest 一致性 / async file I/O 不阻塞主线程 / unlink ENOENT 容忍语义 / purge 按 manifest.romFile 过滤 vs 文件名前缀

## The 10 steps (Step 0 added 2026-05-28)

### Step 0 — Done criteria(sprint contract,开工前定)

外网共识(Addy Osmani):"写下 done-condition 阻止 scope drift 比任何 prompt 调整都管用"。
项目 memory `feedback_completeness_is_scenario_not_form` 反复出现的根因——开工时未明确
"什么叫审完",fix 完了才回头问 "够不够"。

**动作**:在创建 `AUDIT_DIR` 之后(Step 1 之前)立刻写 `AUDIT_DIR/DONE.md`:

```markdown
# Done criteria — audit-<TS> (topic: T<n>)

## 边界(必明确,防 scope drift)
- Scope in:  <文件 glob / 目录列表 / 行为子集>
- Scope out: <显式排除的相邻子系统,例如 "T7 不审 ArkTS 侧 keymap UI">

## 完成条件(场景驱动,逐条 checkbox,fix 完逐条勾选)
- [ ] 所有 P0 finding 已 fix 或显式标记 WONT_FIX(理由必填)
- [ ] 所有 fix 通过 Step 6/7 verify(verify agent 报 FIXED + 主 Claude citation 确认)
- [ ] Step 8 quick_signals 全 PASS
- [ ] 业务侧"会踩坑的真实场景"(由用户/topic 性质给出)逐条验证:
  - [ ] <场景 1,例如 T7: 切核重启后 input 不再重发已释放 TSFN>
  - [ ] <场景 2,例如 T7: ArkTS 侧 hub 离页后 C++ 侧 listener 自动清理>
  - [ ] ...
- [ ] napi-boundary-reviewer(若 fix 涉及 NAPI)verdict ≠ block
- [ ] audit-evaluator(若有)drift ≤ 20%

## 不在本次范围(显式 defer)
- <项 1: 理由 + defer 到哪个 audit>
- <项 2>
```

**约束**:
- 完成条件 MUST 是**场景驱动**,不是"checklist 填空"(memory `feedback_completeness_is_scenario_not_form`)
- 场景由 topic 性质 + 项目 memory 共同决定;不要凭空发明
- DONE.md 一旦写定,Step 1 之后**不许悄悄改**——确实要改 scope 必须显式记录 "scope drift: <原因>"

**State after step 0**: `AUDIT_DIR/DONE.md` 存在,scope + checkbox 全部填写。

### Step 1 — Audit dispatch

Ask user which topic(s) (default: ask user to choose, do NOT auto-default
to all 8 — the audit is expensive). Create
`docs/audit/audit-<YYYYMMDD-HHMMSS>/` directory; remember this path as
AUDIT_DIR.

For each chosen topic, dispatch ONE Sonnet agent (use `Agent` tool with
`model: "sonnet"` per [[feedback_subagent_model]] — never Haiku). Each
agent must:
- Write findings to `AUDIT_DIR/agent-<topic-id>.md`
- Use this finding format (strict):

```markdown
## F<N>: <one-line claim>

- severity: P0 | P1 | P2
- file: <relative path>
- line: <single line or N-M range>
- evidence_excerpt: |
    <copy of the cited lines, verbatim, ≤8 lines>
- claim: <full explanation, why it's a bug, what should happen>
- suggested_fix: <one-paragraph repair shape; do NOT write the patch>
```

- Receive constraint: "DO NOT modify files. DO NOT run hvigorw / cmake.
  DO NOT invent citations — only cite lines you actually Read."
- **TOOL POLICY (MANDATORY)**: Using Grep to answer "who calls X / where is X defined /
  what references X" is FORBIDDEN in this agent. For symbol/reference/caller lookup
  you MUST use MCP tools:
  `mcp__cclsp__find_references` | `mcp__cclsp__find_definition` |
  `mcp__cclsp__get_incoming_calls` | `mcp__serena__find_referencing_symbols` |
  `mcp__cclsp__find_workspace_symbols`.
  Grep is allowed ONLY for non-symbol file-content text searches.

Dispatch ALL agents in PARALLEL (single message, multiple Agent tool calls).

**State after step 1**: `AUDIT_DIR/agent-*.md` exists (one per topic).

### Step 2 — Citation verify (Read + grep, manual)

For each finding in each `agent-<topic>.md`:

1. `Read` the cited file at the cited line range.
2. Compare actual file content to `evidence_excerpt`:
   - **VERIFIED** — bytes match (allow trivial whitespace drift)
   - **CITATION_DRIFT** — same code exists but ±N lines off
   - **FILE_MISSING** — file path doesn't exist
   - **FORMAT_ERROR** — agent's finding malformed
3. Stamp each finding with the verdict in a new file
   `AUDIT_DIR/VERIFIED.md` (table form, one row per finding).

This replaces carbon's `scripts/audit-verify.mjs` — keep it manual to
avoid scaffolding scripts before they prove their weight.

**State after step 2**: `AUDIT_DIR/VERIFIED.md` exists with VERIFIED count.

### ─── CHECKPOINT A (auto-pass unless user said "stop after each step") ───

Report counts: "X VERIFIED / Y CITATION_DRIFT / Z FORMAT_ERROR /
W FILE_MISSING across N topics." Do not pause unless user explicitly asked.

### Step 3 — Main Claude core-review

For EACH finding stamped `VERIFIED`:

1. `Read` the cited file at the cited line range, plus ±20 lines
   surrounding context. NEVER skip this — step 2 only proves the bytes
   match, not that the agent's *interpretation* is correct.
2. Judge the finding's claim and assign a **verdict**:
   - `REAL` — confirmed bug at the cited severity
   - `REAL_LOWER` — confirmed but severity overstated (specify the true severity)
   - `MITIGATED` — code does the cited thing but upstream check makes it unreachable
   - `DESIGN` — intentional, not a bug
   - `FALSE_POSITIVE` — agent misread the code
3. Append to `AUDIT_DIR/CORE-REVIEW.md`:

```markdown
## Agent <topic-id> — N VERIFIED

| # | Severity | Verdict | Notes |
|---|---|---|---|
| F1 | P0 | REAL | <one-line why it stands at this severity> |
| F2 | P0 | REAL_LOWER P1 | <one-line why severity is overstated> |
```

End with final tally: total REAL by severity + cross-agent calibration
notes (e.g., "T4 over-labels P0 on geometry resize").

**Trust rule**: do not treat any finding as REAL until its cited code
has been read in this step. Skipping the Read means trusting the
sub-agent verbatim — exactly the failure mode this workflow prevents.

**LSP / AST 协同**（2026-05-26 ECP2 加；总览见 root `CLAUDE.md` "MCP / Skill 工具决策树"）：

判 verdict 前 **MUST 先用 MCP**——Grep/Read 不是等效替代，不是 fallback：
- `mcp__cclsp__find_references` / `mcp__serena__find_referencing_symbols` — 看 finding 影响面（多 caller 同问题 → severity 上调；单 caller → 可能 REAL_LOWER）
- `mcp__cclsp__get_diagnostics_for_file` — LSP 已知的 type/warning 可能直接判 `FALSE_POSITIVE`（LSP 不报警 = 编译器满意）
- `mcp__ast-grep__find_code` — 看 finding pattern 是否泛存在（譬如 finding 说 "F12 mmap 用错" → `mmap(` 模式扫，看是单点还是全项目通病）
- `mcp__cclsp__get_hover` — 看相关类型 / 函数签名，NAPI 边界改动尤其有用
- `mcp__sequential-thinking__sequentialthinking` — 罕见 finding 拿不准时多角度推理（不滥用）

**用 Grep/Read 之前必须问自己**：MCP 能回答这个问题吗？能 → 用 MCP；不能（如内容文本搜索）→ 再用 Grep。

**State after step 3**: `AUDIT_DIR/CORE-REVIEW.md` exists with verdict per finding.

### ─── CHECKPOINT B (MANDATORY HUMAN) ───

Surface the verdict table. Ask:

```
Found N REAL findings (M P0, K P1, L P2) + Q REAL_LOWER. Top P0:
 - F1: <claim> @ <file:line>
 - F2: ...
What to fix? [all REAL P0+P1 / specific list / discuss / skip fix step]
```

**Wait for explicit user response. Do not proceed without it.**

If user picks specific findings, write that list to `AUDIT_DIR/FIX-PLAN.md`
so step 4 has a stable to-do.

### Step 4 — Main Claude fixes

For each finding the user approved (per FIX-PLAN.md):

1. Re-read the cited code + surrounding context to find the right place
   for the bounds check / null guard / buffer release / state-machine guard.
2. **If the fix touches `entry/src/main/cpp/app/napi/**`: BEFORE applying
   the Edit, dispatch the `napi-boundary-reviewer` agent** with the
   proposed change description. Wait for its review. Apply only after
   review passes (or document the override in CORE-REVIEW.md).
3. Apply the fix via `Edit`. Each fix must:
   - Be **minimal** — don't refactor while fixing
   - Be **comment-traceable** — add `// Audit F<N>: <one-line>` near the new code
   - **Not change behavior for valid inputs** — fixes are defensive
4. Group fixes by file. Batch all fixes for one file into one Edit
   sequence to minimize regressions.

**Do not dispatch a generic "fix agent"**. Per the trust chain rationale,
main Claude is the implementer. The only sub-agent dispatch in step 4 is
the `napi-boundary-reviewer` *pre-review*, which is verification, not
implementation.

**LSP 协同**（2026-05-26 ECP2 加）：

每个 fix 前 **MUST 先查 MCP**——Grep/Read 不是等效替代：
- `mcp__cclsp__find_references` — 看这个函数 / 类型在哪些其他地方被引用，fix 是否影响 caller 行为
- `mcp__cclsp__get_incoming_calls` — 调用链谁触发，理解 fix 的实际触发条件
- `mcp__serena__get_diagnostics_for_file` — fix 前后看 type warning 是否变化

**用 Grep/Read 之前必须问自己**：MCP 能回答这个问题吗？能 → 用 MCP；不能 → 再用 Grep。

NAPI 边界改动的 LSP 协同与 `napi-boundary-reviewer` agent **并行**——agent 跑深度审；MCP 跑覆盖面。

**State after step 4**: uncommitted edits in the working tree, listed by
`git diff --stat`.

### Step 5 — Rebuild (if C++ changed)

If any file under `entry/src/main/cpp/` changed, incrementally build via
DevEco Studio's existing `.cxx` ninja directory:

```bash
# Discover the build.ninja path (one of the architectures):
ls entry/.cxx/*/*/*/build.ninja 2>/dev/null
# Pick the most recently used arch (default arm64-v8a) and build:
cmake --build "entry/.cxx/<config>/<arch>/<abi>" --target libentry_static
```

Or run the wider hygiene + incremental build via:

```bash
bash scripts/check/quick_signals.sh
```

If only ets/ets-side changed, no C++ rebuild needed — step 8's
`quick_signals.sh` covers TS-side regression.

### ─── CHECKPOINT C (MANDATORY HUMAN) ───

Show user `git diff --stat` + (if C++ built) the build PASS/FAIL line. Ask:

```
N files changed (+X -Y). C++ build: <OK / FAIL>. Diff looks reasonable?
[continue to fix-verify / inspect specific file / revert specific fix]
```

**Wait for response.** Do not proceed without it.

### Step 6 — Fix-verify agent dispatch

Create `docs/audit/audit-<ORIGINAL_TS>-fixverify/` (suffix the original
audit dir's timestamp — aids correlation).

Dispatch ONE Sonnet agent per affected topic (usually just the topics
user picked findings from in step 3). Each agent's prompt MUST include:

1. The list of original findings to re-check (read from `AUDIT_DIR/agent-<topic>.md`)
2. The strict finding format (same as step 1)
3. Verdict field added: `verdict: FIXED | PARTIAL | UNFIXED`
4. New `citation` must point at the **fix code** (where the new guard /
   check / release lives), not the original buggy line
5. Constraint: "DO NOT find NEW issues; only verify the listed originals"
6. **TOOL POLICY (MANDATORY)**: Same as audit agent — Grep for symbol/reference lookup
   is FORBIDDEN. Use `mcp__cclsp__find_references` | `mcp__cclsp__find_definition` |
   `mcp__serena__find_referencing_symbols` for any caller/definition lookup.

Output to `<FIXVERIFY_DIR>/agent-<topic>-fixverify.md`.

### Step 7 — Citation verify on the fix-verify reports (Read + grep, manual)

Same procedure as step 2, but on the fix-verify reports. The fix code
must exist where the agent claims; a `CITATION_DRIFT` here often means
the agent's evidence_excerpt is the right code but the line range is
off-by-a-few — read the code yourself to confirm the fix is actually
correct (line-range drift ≠ fix failure).

### Step 8 — Gate gauntlet

```bash
bash scripts/check/quick_signals.sh
```

Quick signals chains: `check_regression_guards.sh` + `check_repo_hygiene.sh`
+ incremental `cmake --build`. All must be green. If any fails, **fix that
first** (loop back to step 4 — do not commit a half-fixed state).

If quick_signals reports SKIP for `cmake --build` because DevEco Sync
hasn't been run, run a full sync once via DevEco Studio UI, then re-run.

**Done-criteria gate(2026-05-28 加)**:
打开 `AUDIT_DIR/DONE.md`,逐条 checkbox 自检:
- 全部勾上 → 通过
- 有未勾 → 要么补漏(回 Step 4)、要么显式升为 WONT_FIX(理由写进 DONE.md 同一条)
- 场景类未勾(场景没法在本环境验证)→ 标 `[DEFER-MANUAL]` + 写明用户/真机什么时候验

不许"checkbox 大部分勾上,凑合 commit"——`feedback_completeness_is_scenario_not_form`
的原话:**完整不是形式美,是场景驱动**。

### ─── CHECKPOINT D (MANDATORY HUMAN) ───

Draft the commit message:

```
<scope>: <one-line subject under 70 chars>

<body explaining WHY, not just WHAT. Reference the audit dir for traceability.>

Verification:
  bash scripts/check/quick_signals.sh → PASS
  audit fix-verify: X/X FIXED, all citations VERIFIED
  napi-boundary-reviewer (if applicable): <verdict>

Audit artifacts:
  docs/audit/<AUDIT_DIR_NAME>/ (original + CORE-REVIEW.md)
  docs/audit/<FIXVERIFY_DIR_NAME>/ (fix verification)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Show user the full draft. Wait for "go" / "edit X" / "abort".

### Step 9 — Stage + commit

**Explicit file list, no `git add -A`**. Only stage files YOU edited in
step 4 + the audit artifacts under `docs/audit/`. Files modified by the
user pre-session stay out unless explicitly approved.

```bash
git add <file1> <file2> ... docs/audit/<AUDIT_DIR_NAME>/
git status -s    # confirm clean staging
git commit -m "$(cat <<'EOF' ... EOF)"
git log --oneline -3
```

Report commit hash to user. Done.

## State machine: resuming from a partial run

If the user comes back mid-flow and says "继续闭环" / "/closed-loop resume",
detect state via artifacts (no script — use `ls docs/audit/*/`):

```
Has AUDIT_DIR/DONE.md ?
├── no  → step 0 not done, must write DONE.md first
└── yes → has AUDIT_DIR/agent-*.md ?
   ├── no  → step 1 not done, resume step 1
   └── yes → has AUDIT_DIR/VERIFIED.md ?
      ├── no  → resume step 2 (citation-verify)
      └── yes → has AUDIT_DIR/CORE-REVIEW.md ?
         ├── no  → resume step 3 (core-review)
         └── yes → has AUDIT_DIR/FIX-PLAN.md ?
            ├── no  → resume CHECKPOINT B (ask user what to fix)
            └── yes → git diff non-empty?
               ├── no  → resume step 4 (fixing)
               └── yes → has FIXVERIFY_DIR ?
                  ├── no  → resume step 5 (rebuild)
                  └── yes → has FIXVERIFY_DIR/<reports> ?
                     ├── no  → resume step 6 (dispatch fix-verify agents)
                     └── yes → green gates ?
                        ├── no  → resume step 7-8 (citation-verify + gate)
                        └── yes → DONE.md checkbox 全勾?
                           ├── no  → 补漏 / 升 WONT_FIX + 理由 / 改 scope
                           └── yes → resume CHECKPOINT D (commit draft)
```

Pick the most recent timestamped dir as the "active" one if multiple exist.

## Reference

- Fast signals gate: `scripts/check/quick_signals.sh`
- NAPI sub-agent: `.claude/agents/napi-boundary-reviewer.md`
- Regression / hygiene scripts: `scripts/ci/check_regression_guards.sh` + `check_repo_hygiene.sh`
- Trust chain rationale: [[harness-fusion-2026-05-24]] / `docs/plans/2026-05-24-harness-fusion-design.md`
- Sub-agent model floor (Sonnet min, no Haiku): [[feedback_subagent_model]]
- Worktree isolation caveat: [[feedback_agent_worktree_isolation]]
- Hook stdin lesson: post-edit-cpp.sh history (heredoc + json.load conflict)

## Anti-patterns to refuse

If user pushes for any of these, refuse and explain why:

- **"Skip core-review, just fix what the agent said"** — exact failure
  mode this workflow exists to prevent. Sub-agent claims are unverified
  until step 3.
- **"Auto-commit without showing me the diff"** — CHECKPOINT C exists
  because fixes can look right in code but still subtly break behavior.
- **"Dispatch a fix agent for each finding"** — adds a new trust layer
  without a verifier. Main Claude is the implementer, by design.
- **"Run all 9 steps no checkpoints"** — checkpoints B/C/D exist for
  decision authority. Removing them gives Claude autonomy that isn't
  earned yet on this codebase.
- **"Fix the warnings I just noticed while you're in there"** — scope
  creep. Each finding gets a minimal fix; off-scope cleanup goes in a
  separate commit.
- **"Skip the napi-boundary-reviewer for this one NAPI fix"** — NAPI
  edits have hidden env / thread / ref-lifetime hazards that the
  reviewer agent is specifically tuned to catch.

- **"Skip Step 0 because 'we know what we're auditing'"** — Step 0 是
  sprint contract,memory `feedback_completeness_is_scenario_not_form` 反复
  踩过这个坑。开工不写 done criteria 等于让 fix scope 飘。3 分钟写 DONE.md
  比 fix 完反复追问 "审完了吗" 省时间。

## What this skill does NOT cover

- **ets/ets-only fixes** — different workflow (or use `auto-commit-cicd`
  after manual review).
- **Vendored libretro upstream code** — `entry/src/main/cpp/core/libretro/`
  is blocked by `guard-vendored-libretro.sh`; patches must go upstream.
- **PR creation / pushing to remote** — stop at local commit; user
  decides when to push.
