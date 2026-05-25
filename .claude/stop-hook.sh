#!/usr/bin/env bash
# Claude Code Stop hook — runs CI hygiene + regression checks if ripgrep is available.
# Invoked as `bash .claude/stop-hook.sh` from project root.

if which rg >/dev/null 2>&1; then
    bash scripts/ci/check_repo_hygiene.sh && bash scripts/ci/check_regression_guards.sh
else
    echo '[claude-hook] system ripgrep missing — install via:'
    echo '    scoop install ripgrep  |  choco install ripgrep  |  pacman -S mingw-w64-x86_64-ripgrep'
    echo '  Hook will skip until installed.'
fi

# Always stamp activity timestamp for auto-debrief idle detection (independent of rg).
bash scripts/check/session_idle_detector.sh stop
