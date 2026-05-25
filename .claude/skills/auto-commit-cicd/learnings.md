# auto-commit-cicd learnings

Append-only log of cross-session learnings from running `/auto-commit-cicd`.
Update via the user-level `session-debrief` skill at the end of a session
that used this skill, or by manual Append at any time.

v2.1.x+ Claude Code reads this alongside `SKILL.md`; older clients should
Read it explicitly when invoking the skill.

## CI failure recipes

Recurring CI failure modes + repro signal + fix shortcut. Reuse before
re-discovering.

<!-- 2026-MM-DD — failure signature (job:step) — root cause — fix diff/command -->

## Commit message conventions actually used

What `type(scope)` combinations have landed in this project. Useful for
drafting the next Step 3.3 message.

<!-- e.g. chore(harness): .claude/ + scripts/ ai-feedback changes
     e.g. fix(perf): ArkUI re-render fixes
     e.g. docs(plans): docs/plans/ design / roadmap updates -->

## Process meta-learnings

How the 7-step flow + commit message CHECKPOINT performed; user feedback
on the checkpoint UX (e.g. preferred draft format).

<!-- 2026-MM-DD — observation -->

## Anti-patterns observed

User-reported / self-noticed deviations from the documented flow.

<!-- e.g. skipped Step 2 pre-check, CI caught what local would have caught -->
