#!/usr/bin/env bash
# Claude Code PostToolUse hook — single-file codelinter on C++ edits.
# Triggered by Edit|Write on .cpp files. Reads PostToolUse JSON on stdin,
# runs HarmonyOS codelinter on the touched file, blocks if error-level
# findings exist. Vendored libretro cores are skipped.
#
# History: 2026-05-25 — rewrote to use pure-bash JSON parsing. Previous
# python-heredoc impl had a stdin conflict (heredoc consumed stdin so
# json.load(sys.stdin) read empty), making the hook silent-skip forever.

set -u

CL='D:/hongmeng/command-line-tools/bin/codelinter.bat'
PY='/c/Users/newwo/bin/python3'

[[ -x "$PY" ]] || exit 0       # python3 missing → silent skip
[[ -f "$CL" ]] || exit 0       # codelinter missing → silent skip

# Buffer stdin once; grep twice.
# Prefer tool_response.filePath (definitive post-edit path), fallback to
# tool_input.file_path. Reason: PostToolUse JSON puts the resolved path
# under tool_response after a successful Edit/Write.
input=$(cat)

file=$(printf '%s' "$input" \
       | grep -o '"filePath"[[:space:]]*:[[:space:]]*"[^"]*"' \
       | sed -E 's/.*"filePath"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
       | head -1)
if [[ -z "$file" ]]; then
  file=$(printf '%s' "$input" \
         | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
         | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
         | head -1)
fi

# Gate: .cpp only, must exist, not vendored.
case "$file" in *.cpp) ;; *) exit 0 ;; esac
[[ -f "$file" ]] || exit 0
norm="${file//\\//}"
[[ "$norm" == *"core/libretro/"* ]] && exit 0

# Run codelinter → JSON report.
report="/tmp/.cl-hook-$$.json"
trap 'rm -f "$report"' EXIT
"$CL" -e error -f json -o "$report" "$file" >/dev/null 2>&1

# Parse report. Python is invoked the *correct* way here: code via -c,
# heredoc never used. The report path comes from argv, not stdin.
"$PY" -c "
import sys, json
report_path, file_path = sys.argv[1], sys.argv[2]
try:
    with open(report_path, 'r', encoding='utf-8') as f:
        findings = json.load(f)
except Exception:
    sys.exit(0)
if not isinstance(findings, list) or not findings:
    sys.exit(0)
errs = [x for x in findings
        if str(x.get('severity', 'error')).lower() == 'error']
if not errs:
    sys.exit(0)
lines = []
for x in errs[:20]:
    ln   = x.get('line', '?')
    rule = x.get('rule', x.get('ruleId', 'rule?'))
    msg  = x.get('message', '')
    lines.append(f'  L{ln}: [{rule}] {msg}')
reason = (f'codelinter found {len(errs)} error(s) in {file_path}:\n'
          + '\n'.join(lines))
print(json.dumps({'decision': 'block', 'reason': reason}))
" "$report" "$file"

exit 0
