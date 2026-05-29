#!/usr/bin/env bash
# .claude/hooks/session-start.sh — H3 SessionStart context inject
#
# Outputs current git status, recent commits, and last quick_signals
# summary so Claude has working context at session start without burning
# tool calls to pull the same info.
#
# Reference: docs/plans/2026-05-24-harness-fusion-design.md H3

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Reset per-session Grep counter for the MCP-nudge hook
echo 0 > .claude/.grep-call-count.txt 2>/dev/null

echo "=== git status -s ==="
git status -s 2>&1 | head -30

echo ""
echo "=== git log --oneline -3 ==="
git log --oneline -3 2>&1

if [[ -f .claude/.last-quick-signals.txt ]]; then
  echo ""
  echo "=== last quick_signals ==="
  cat .claude/.last-quick-signals.txt
fi

echo ""
echo "=== Skills available (declarative inventory) ==="
echo "Project: closed-loop (audit→fix→commit cycle on harmony subsystem) | auto-commit-cicd (auto git→PR→CI→merge w/ retry) | gc (entropy/drift scanner) | four-way-audit (cross-source consistency audit) | arkui-design (ArkUI/ArkTS page & component design)"
echo "User: using-superpowers (skill bootstrap, call first each session) | dispatching-parallel-agents (2+ independent tasks no shared state) | executing-plans (written plan w/ checkpoints) | subagent-driven-development (multi-agent plan exec) | systematic-debugging (before any bug fix) | test-driven-development (test before impl) | finishing-a-development-branch (impl done → merge/PR) | session-debrief (end/bye/idle injection)"

echo ""
echo "=== MCP servers available (declarative) ==="
echo "Project (.claude/cclsp.json): cclsp (12 — find_definition/find_references/get_diagnostics_for_file/get_hover/get_incoming_calls/get_outgoing_calls/find_workspace_symbols/prepare_call_hierarchy/rename_symbol/etc) | serena (21 — find_symbol/find_referencing_symbols/get_symbols_overview/get_diagnostics_for_file/replace_symbol_body/list_memories/write_memory/etc)"
echo "User: ast-grep (4 — find_code/find_code_by_rule/dump_syntax_tree/test_match_code_rule) | web-search (2 — web_fetch/web_search) | sequential-thinking (1)"

echo ""
echo "=== MCP TOOL POLICY — 本会话强制执行 ==="
echo "【禁止】用 Grep 回答以下问题：'谁调用了 X / X 在哪定义 / 哪些地方引用了 X'"
echo "【必须】符号/引用/调用链查询，MUST 优先选："
echo "  cclsp  : find_references | find_definition | get_incoming_calls | get_outgoing_calls | find_workspace_symbols"
echo "  serena : find_symbol | find_referencing_symbols | get_symbols_overview"
echo "  ast-grep: find_code | find_code_by_rule   （AST 模式 / 配对检查）"
echo "【允许 Grep 的场景】文件内容文本搜索 | CI regression guard 扫 banned-pattern | 非符号字符串匹配"
echo "判断原则：MCP 能给更精确答案的地方用 Grep = 工具选型错误，不是 fallback。"
echo "详见：CLAUDE.md 'MCP / Skill 工具决策树'"

# Write static MCP status for statusline (5 servers configured)
echo "5/5" > .claude/.last-mcp-status.txt 2>/dev/null
