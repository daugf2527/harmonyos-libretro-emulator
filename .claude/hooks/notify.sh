#!/usr/bin/env bash
# .claude/hooks/notify.sh — NT1 Notification hook (Windows)
#
# Triggered on Claude Code Notification events (long task done / Claude
# waiting for input). Surfaces a Windows toast/message-box notification.
#
# Prefers BurntToast (toast, non-intrusive); falls back to `msg`
# (Windows built-in, more intrusive). Claude does NOT auto-install
# BurntToast — it modifies user-global PowerShell modules. To enable
# (one-time user action):
#   powershell -Command "Install-Module BurntToast -Scope CurrentUser -Force"
#
# Reference: docs/plans/2026-05-24-harness-fusion-design.md NT1

input=$(cat)
msg=$(echo "$input" | grep -oE '"message"\s*:\s*"[^"]*"' | sed -E 's/.*"message"\s*:\s*"([^"]*)".*/\1/')
[[ -z "$msg" ]] && msg="Claude Code event"
# Truncate + strip single quotes that would break PowerShell quoting.
msg_short="${msg:0:100}"
msg_safe="${msg_short//\'/}"

if powershell.exe -NoProfile -Command "Get-Module -ListAvailable BurntToast" 2>/dev/null | grep -q BurntToast; then
  powershell.exe -NoProfile -Command "New-BurntToastNotification -Text 'Claude Code', '$msg_safe'" >/dev/null 2>&1 || true
else
  # Fallback: msg command (always on Windows; pops a blocking message box).
  msg "${USERNAME:-$USER}" "Claude Code: $msg_safe" 2>/dev/null || true
fi

exit 0
