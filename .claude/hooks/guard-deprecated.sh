#!/usr/bin/env bash
# .claude/hooks/guard-deprecated.sh
# PreToolUse hook (Edit|Write) — block edits to deprecated/legacy/**.
# Rationale: deprecated/legacy/ is excluded from mainline by .claudeignore;
# changes there are wasted work and risk reactivating retired code paths.

set -u

# Extract tool_input.file_path from stdin JSON via pure bash (grep+sed).
# Reason: python heredoc + json.load(sys.stdin) conflicts — heredoc consumes
# the script's stdin so no JSON ever reaches python. See harness-fusion notes.
file=$(grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
       | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
       | head -1)

[[ -z "$file" ]] && exit 0
norm="${file//\\//}"

case "$norm" in
  */deprecated/legacy/*|deprecated/legacy/*)
    echo "BLOCK: 禁止编辑 deprecated/legacy/** — 已弃代码（在 .claudeignore 中），改动是浪费工时；如需复活请先把文件移出 deprecated/legacy/" >&2
    exit 2
    ;;
esac
exit 0
