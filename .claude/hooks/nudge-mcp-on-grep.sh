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
[MCP-POLICY] Grep call #$count this session.
!! 本次 Grep 若是在查"谁调用了 X / X 在哪定义 / 哪些地方引用了 X"= POLICY VIOLATION !!
   MUST 改用 MCP：
     find_references | find_definition | get_incoming_calls | get_outgoing_calls   (cclsp)
     find_symbol | find_referencing_symbols                                         (serena)
     find_code | find_code_by_rule                                                  (ast-grep)
   Grep 仅允许：文件内容文本搜索 / CI banned-pattern 扫描 / 非符号字符串匹配。
   MCP 能更精确回答的问题上用 Grep = 工具选型错误。(CLAUDE.md 'MCP / Skill 工具决策树')
EOF
fi

exit 0
