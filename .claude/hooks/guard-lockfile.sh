#!/usr/bin/env bash
# .claude/hooks/guard-lockfile.sh
# PreToolUse hook (Edit|Write) — ask before editing oh-package-lock.json5.
# Rationale: lockfile changes should come from ohpm install / DevEco Sync, not
# manual edits. We don't hard-block (legitimate conflict resolution sometimes
# needs manual fix-ups), but we force a user confirmation each time via the
# PreToolUse JSON hookSpecificOutput.permissionDecision: "ask" path.

set -u

file=$(grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
       | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
       | head -1)

[[ -z "$file" ]] && exit 0
norm="${file//\\//}"

case "$norm" in
  *oh-package-lock.json5|oh-package-lock.json5)
    cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"你正在直接编辑 oh-package-lock.json5。通常这应由 ohpm install / DevEco Sync 维护——若是合并冲突手工修复请确认，若是误改请取消。"}}
JSON
    exit 0
    ;;
esac
exit 0
