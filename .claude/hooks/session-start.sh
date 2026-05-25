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
