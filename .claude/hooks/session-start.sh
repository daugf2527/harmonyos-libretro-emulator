#!/usr/bin/env bash
# .claude/hooks/session-start.sh — H3 SessionStart context inject
#
# Outputs current git status, recent commits, and last quick_signals
# summary so Claude has working context at session start without burning
# tool calls to pull the same info.
#
# Reference: docs/plans/2026-05-24-harness-fusion-design.md H3

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "=== git status -s ==="
git status -s 2>&1 | head -30

echo ""
echo "=== git log --oneline -3 ==="
git log --oneline -3 2>&1

if [[ -f .claude/.last-quick-signals.txt ]]; then
  echo ""
  echo "=== last quick_signals ==="
  cat .claude/.last-quick-signals.txt
fi

echo ""
echo "=== Skills available (declarative inventory) ==="
echo "Project: closed-loop (audit→fix→commit cycle on harmony subsystem) | auto-commit-cicd (auto git→PR→CI→merge w/ retry)"
echo "User: using-superpowers (skill bootstrap, call first each session) | dispatching-parallel-agents (2+ independent tasks no shared state) | executing-plans (written plan w/ checkpoints) | subagent-driven-development (multi-agent plan exec) | systematic-debugging (before any bug fix) | test-driven-development (test before impl) | brainstorming (before creative work) | finishing-a-development-branch (impl done → merge/PR) | session-debrief (end/bye/idle injection)"
