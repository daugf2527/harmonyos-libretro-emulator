#!/usr/bin/env bash
# .claude/hooks/nudge-mcp-on-grep.sh
# PreToolUse hook (matcher: Grep) — non-blocking reminder to consider MCP
# cclsp/serena/ast-grep for symbol/reference lookups instead of Grep.
#
# Rationale: CLAUDE.md "MCP / Skill 工具决策树" + SessionStart MCP inventory
# injection (commit 95a7bd4 / 6068a82) both stayed at 0% actual MCP call rate
# in a 30k-token, 9-step closed-loop session (audit-20260527-090735).
# Static text injection insufficient — nudge at the tool-trigger point.
#
# Throttle: emit on call #1, then every 10 calls. Counter file
# `.claude/.grep-call-count.txt` is reset at SessionStart.
#
# Never blocks Grep; always exit 0. Output goes to stderr — Claude Code
# typically surfaces PreToolUse stderr into the tool-result feedback path.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Consume the JSON stdin to avoid producer block, even if we don't parse it.
cat > /dev/null

state_file=".claude/.grep-call-count.txt"
count=0
if [[ -f "$state_file" ]]; then
  count=$(cat "$state_file" 2>/dev/null || echo 0)
fi
count=$((count + 1))
echo "$count" > "$state_file"

# Throttle: call #1, then every 10
should_remind=0
if [[ $count -eq 1 ]] || [[ $((count % 10)) -eq 0 ]]; then
  should_remind=1
fi

if [[ $should_remind -eq 1 ]]; then
  cat >&2 <<EOF
[MCP-HINT] Grep call #$count this session（分语言提示,非违规判定）。
   • 查 C++ "谁调用/在哪定义/谁引用 X" → 优先 cclsp/codegraph;但空结果必须 Grep 兜底(空≠不存在)。
   • 查 .ets(ArkTS) → serena 符号级 OK;LSP 诊断/ast-grep 结构匹配对 .ets 失效,定性就用 Grep/Read。
   • 文本 / banned-pattern / 配对扫 → Grep 本就是正确工具。
   按语言选,非一刀切。详见 CLAUDE.md '工具决策树' / memory feedback_mcp_tools_fail_on_ets。
EOF
fi

exit 0
