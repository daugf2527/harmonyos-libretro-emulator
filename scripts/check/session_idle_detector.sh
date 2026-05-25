#!/usr/bin/env bash
# scripts/check/session_idle_detector.sh
#
# Claude Code session-idle heuristic for auto-debrief.
#
# Two modes:
#   stop  — called from Stop hook. Just stamps "response ended" timestamp.
#   check — called from UserPromptSubmit hook. Compares now vs last stamp;
#           if the gap exceeds threshold, emits a one-line suggestion that
#           Claude will see as <user-prompt-submit-hook> content in the
#           next turn. Always updates the timestamp.
#
# Threshold: env var CLAUDE_DEBRIEF_IDLE_MIN (default 15).
#
# State file: .claude/.last-activity-ts (epoch seconds; .claude/ is gitignored).
#
# Usage:
#   bash scripts/check/session_idle_detector.sh stop
#   bash scripts/check/session_idle_detector.sh check

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS_FILE="${ROOT_DIR}/.claude/.last-activity-ts"
THRESHOLD_MIN="${CLAUDE_DEBRIEF_IDLE_MIN:-15}"
THRESHOLD_SEC=$((THRESHOLD_MIN * 60))

MODE="${1:-check}"
NOW=$(date +%s)

touch_ts() {
  mkdir -p "$(dirname "${TS_FILE}")"
  echo "${NOW}" > "${TS_FILE}"
}

case "${MODE}" in
  stop)
    touch_ts
    ;;
  check)
    if [[ -f "${TS_FILE}" ]]; then
      LAST=$(cat "${TS_FILE}" 2>/dev/null || echo "${NOW}")
      # Guard against non-numeric content
      if [[ "${LAST}" =~ ^[0-9]+$ ]]; then
        GAP=$((NOW - LAST))
        if (( GAP > THRESHOLD_SEC )); then
          GAP_MIN=$((GAP / 60))
          echo "[auto-detected idle: previous Claude response ended ${GAP_MIN} min ago. If you are starting a fresh task or this concludes the previous segment, consider running /session-debrief to capture lessons before context fades.]"
        fi
      fi
    fi
    touch_ts
    ;;
  *)
    echo "[session_idle_detector] unknown mode: ${MODE} (expected: stop | check)" >&2
    exit 1
    ;;
esac
