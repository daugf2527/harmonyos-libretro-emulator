# closed-loop learnings

Append-only log of cross-session learnings from running `/closed-loop`.
Update via the user-level `session-debrief` skill at the end of a closed-loop
session, or by manual Append at any time.

v2.1.x+ Claude Code reads this alongside `SKILL.md`; older clients should
Read it explicitly when invoking the skill to benefit from prior findings.

## Per-topic patterns

Recurring REAL / FALSE_POSITIVE / DESIGN findings, fix recipes by review topic.
Reuse before re-discovering.

### NAPI boundary

<!-- 2026-MM-DD — VERDICT: REAL/LOWER/DESIGN/FALSE_POSITIVE — file:line — finding — fix -->

### Engine state machine

### Audio bridge

### VideoPipeline

### NativeBuffer lifecycle

### Resource lifecycle

## Process meta-learnings

How the 9-step trust chain + 4 checkpoints actually performed across sessions.
Surprises, friction points, places where audit-verify saved a fix round.

<!-- 2026-MM-DD — observation -->

## Anti-patterns observed

User-reported / self-noticed deviations from the 9-step flow.

<!-- e.g. skipped step 2 mechanical re-verify, hit a fix-and-revert cycle -->
