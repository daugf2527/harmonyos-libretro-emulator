#!/usr/bin/env bash
# .claude/hooks/check-idle-on-prompt.sh
# UserPromptSubmit hook — delegates to project-level idle detector.
bash scripts/check/session_idle_detector.sh check
