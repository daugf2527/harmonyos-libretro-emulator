#!/usr/bin/env bash
# .claude/statusline.sh — OS1 project-level status line
#
# Version: v2 (2026-05-28)
# v1: branch + qs + mcp + idle
# v2: + model + token estimate + cost (disler v6/v8 风格,简化版)
#
# Reference: disler/claude-code-hooks-mastery status_lines/
# Constraint: pure bash (grep+sed) — see CLAUDE.md "statusline" 警告
#
# Output: [branch+dirty] qs:PASS|FAIL|? [model|tok:Nk|$X.XX] mcp:... idle:Nm

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

# --- v2: model + token estimate + cost ---
model_id=$(echo "$input" | grep -oE '"id"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"id"\s*:\s*"([^"]*)".*/\1/') || true
cost_raw=$(echo "$input" | grep -oE '"total_cost_usd"\s*:\s*[0-9]+(\.[0-9]+)?' | sed -E 's/.*:\s*//' ) || true
exceeds=$(echo "$input" | grep -oE '"exceeds_200k_tokens"\s*:\s*(true|false)' | sed -E 's/.*:\s*//' ) || true

# model short name
model_short=""
if [[ -n "$model_id" ]]; then
  case "$model_id" in
    claude-opus-4-7*)   model_short="opus" ;;
    claude-sonnet-4-6*) model_short="sonnet" ;;
    claude-haiku-4-5*)  model_short="haiku" ;;
    *)                  model_short=$(echo "$model_id" | sed -E 's/([^0-9]*).*/\1/' | sed 's/-$//') ;;
  esac
fi

# token estimate from cost: $1 ≈ 100k tok
tok_seg=""
if [[ "$exceeds" == "true" ]]; then
  tok_seg="tok:200k+"
elif [[ -n "$cost_raw" ]]; then
  # integer part of cost * 100 = approx k-tokens
  cost_int=${cost_raw%%.*}
  cost_frac=${cost_raw#*.}
  # pad/truncate frac to 2 digits
  cost_frac="${cost_frac}00"
  cost_frac="${cost_frac:0:2}"
  ktok=$(( cost_int * 100 + 10#$cost_frac )) || true
  (( ktok >= 1 )) && tok_seg="tok:${ktok}k"
fi

# cost display: $X.XX (2 decimal places via string)
cost_seg=""
if [[ -n "$cost_raw" ]]; then
  # format to 2 decimal places without bc: split on dot
  c_int=${cost_raw%%.*}
  c_frac=${cost_raw#*.}
  c_frac="${c_frac}00"
  c_frac="${c_frac:0:2}"
  cost_seg="\$${c_int}.${c_frac}"
fi

# assemble [model|tok|cost] segment
info_parts=""
[[ -n "$model_short" ]] && info_parts="$model_short"
if [[ -n "$tok_seg" ]]; then
  [[ -n "$info_parts" ]] && info_parts="$info_parts|$tok_seg" || info_parts="$tok_seg"
fi
if [[ -n "$cost_seg" ]]; then
  [[ -n "$info_parts" ]] && info_parts="$info_parts|$cost_seg" || info_parts="$cost_seg"
fi

info_block=""
[[ -n "$info_parts" ]] && info_block=" [$info_parts]"

echo "[$branch$dirty] qs:$qs$info_block$mcp$idle"
