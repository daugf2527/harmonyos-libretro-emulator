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
echo "Project: closed-loop (audit→fix→commit cycle on harmony subsystem) | auto-commit-cicd (auto git→PR→CI→merge w/ retry)"
echo "User: using-superpowers (skill bootstrap, call first each session) | dispatching-parallel-agents (2+ independent tasks no shared state) | executing-plans (written plan w/ checkpoints) | subagent-driven-development (multi-agent plan exec) | systematic-debugging (before any bug fix) | test-driven-development (test before impl) | brainstorming (before creative work) | finishing-a-development-branch (impl done → merge/PR) | session-debrief (end/bye/idle injection)"

echo ""
echo "=== MCP servers available (declarative) ==="
echo "Project (.claude/cclsp.json): cclsp (12 — find_definition/find_references/get_diagnostics_for_file/get_hover/get_incoming_calls/get_outgoing_calls/find_workspace_symbols/prepare_call_hierarchy/rename_symbol/etc) | serena (21 — find_symbol/find_referencing_symbols/get_symbols_overview/get_diagnostics_for_file/replace_symbol_body/list_memories/write_memory/etc)"
echo "User: ast-grep (4 — find_code/find_code_by_rule/dump_syntax_tree/test_match_code_rule) | mcp-server-firecrawl (24 — scrape/search/extract/etc) | sequential-thinking (1)"
echo "Decision tree: CLAUDE.md 'MCP / Skill 工具决策树' — 别只用 Read/Grep"

# Write static MCP status for statusline (5 servers configured)
echo "5/5" > .claude/.last-mcp-status.txt 2>/dev/null
