#!/usr/bin/env bash
# .claude/statusline.sh — OS1 project-level status line
#
# Pure bash JSON parsing (no jq dependency — see CLAUDE.md "statusline"
# warning: Claude Code Git Bash $PATH injection bug can hide jq).
#
# Output: [branch+dirty] qs:PASS|FAIL|? idle:Nm
# Example: [refactor/build-method-split-newarch*] qs:PASS idle:5m
#
# Reference: docs/plans/2026-05-24-harness-fusion-design.md OS1

input=$(cat)
cwd=$(echo "$input" | grep -oE '"current_dir"\s*:\s*"[^"]*"' | sed -E 's/.*"current_dir"\s*:\s*"([^"]*)".*/\1/')
[[ -z "$cwd" ]] && cwd=$(echo "$input" | grep -oE '"cwd"\s*:\s*"[^"]*"' | sed -E 's/.*"cwd"\s*:\s*"([^"]*)".*/\1/')
[[ -z "$cwd" ]] && cwd="$(pwd)"

cd "$cwd" 2>/dev/null || cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

branch=$(git branch --show-current 2>/dev/null || echo "?")
dirty=""
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && dirty="*"

qs="?"
if [[ -f .claude/.last-quick-signals.txt ]]; then
  if grep -q "ALL PASS" .claude/.last-quick-signals.txt 2>/dev/null; then
    qs="PASS"
  elif grep -q "FAIL" .claude/.last-quick-signals.txt 2>/dev/null; then
    qs="FAIL"
  fi
fi

mcp=""
if [[ -f .claude/.last-mcp-status.txt ]]; then
  mcp_val=$(cat .claude/.last-mcp-status.txt 2>/dev/null | head -1)
  [[ -n "$mcp_val" ]] && mcp=" mcp:$mcp_val"
fi

idle=""
if [[ -f .claude/.last-activity-ts ]]; then
  last_ts=$(cat .claude/.last-activity-ts 2>/dev/null)
  if [[ "$last_ts" =~ ^[0-9]+$ ]]; then
    now=$(date +%s)
    if (( now > last_ts )); then
      gap=$((now - last_ts))
      (( gap > 60 )) && idle=" idle:$((gap/60))m"
    fi
  fi
fi

echo "[$branch$dirty] qs:$qs$mcp$idle"
