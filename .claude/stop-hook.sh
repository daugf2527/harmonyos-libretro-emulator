#!/usr/bin/env bash
# Claude Code Stop hook — runs CI hygiene + regression checks if ripgrep is available.
# Invoked as `bash .claude/stop-hook.sh` from project root.
#
# Output policy (2026-05-28, P2-2 silent-on-success):
#   - If all gates PASS → echo only the summary block (~5 lines).
#   - If any gate FAILS → echo full output (so the user / Claude can debug).
#   - If ripgrep missing → install hint as before.
#
# Rationale: quick_signals.sh emits ~100+ lines on every commit. The full
# transcript is high value only when something fails. Suppressing it on PASS
# saves user terminal scrollback and Claude context window after Bash tool
# calls. External consumer (auto-debrief / statusline) reads
# .claude/.last-quick-signals.txt instead of this hook's stdout.

if which rg >/dev/null 2>&1; then
    hygiene_log=$(mktemp)
    regression_log=$(mktemp)
    quick_log=$(mktemp)
    trap 'rm -f "$hygiene_log" "$regression_log" "$quick_log"' EXIT

    bash scripts/ci/check_repo_hygiene.sh > "$hygiene_log" 2>&1
    hygiene_rc=$?

    if [[ $hygiene_rc -eq 0 ]]; then
        bash scripts/ci/check_regression_guards.sh > "$regression_log" 2>&1
        regression_rc=$?
    else
        regression_rc=1
        echo "(skipped — hygiene failed first)" > "$regression_log"
    fi

    if [[ $hygiene_rc -ne 0 || $regression_rc -ne 0 ]]; then
        # Any gate failed → dump full output for diagnosis.
        echo "==== stop-hook: FAILURE — full output below ===="
        echo "---- hygiene (rc=$hygiene_rc) ----"
        cat "$hygiene_log"
        echo "---- regression (rc=$regression_rc) ----"
        cat "$regression_log"
        echo "================================================"
    else
        # All PASS → quiet, single-line summary only.
        echo "[stop-hook] hygiene + regression: PASS"
    fi
else
    echo '[claude-hook] system ripgrep missing — install via:'
    echo '    scoop install ripgrep  |  choco install ripgrep  |  pacman -S mingw-w64-x86_64-ripgrep'
    echo '  Hook will skip until installed.'
fi

# Always stamp activity timestamp for auto-debrief idle detection (independent of rg).
bash scripts/check/session_idle_detector.sh stop
