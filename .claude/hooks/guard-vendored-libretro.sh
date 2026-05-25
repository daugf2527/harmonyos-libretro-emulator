#!/usr/bin/env bash
# .claude/hooks/guard-vendored-libretro.sh
# PreToolUse hook (Edit|Write) — block edits to entry/src/main/cpp/core/libretro/**.
# Rationale: this is vendored libretro.h / RetroArch upstream code; patches must
# go upstream, not to the local copy. post-edit-cpp.sh already skips codelinter
# on this path — keep edits out altogether.

set -u

file=$(grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
       | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
       | head -1)

[[ -z "$file" ]] && exit 0
norm="${file//\\//}"

case "$norm" in
  *entry/src/main/cpp/core/libretro/*)
    echo "BLOCK: 禁止编辑 entry/src/main/cpp/core/libretro/** — 这是 vendored libretro 上游代码，改动请走上游 PR；本地若必须分叉先迁出该目录" >&2
    exit 2
    ;;
esac
exit 0
