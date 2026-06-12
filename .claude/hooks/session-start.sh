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
echo "=== MCP 工具策略（分语言实证版,2026-06-08 5天质检实测校准）==="
echo "C++ 符号/引用/调用链 → cclsp/codegraph 优先;但【空结果≠不存在】必须 Grep 实物兜底"
echo "                       (实测连活着的 GetEventName/Emit 都查不到)。C++ 诊断靠 cxx-build。"
echo "ArkTS .ets          → serena 符号级(find_symbol/get_symbols_overview)可用;"
echo "                       【serena LSP 诊断 + ast-grep 结构匹配对 .ets 失效(invalid AST)】"
echo "                       → 诊断/结构/定性只能 Grep/Read + 真机编译。"
echo "配对/banned-pattern/文本 → Grep 或 ast-grep(仅非 .ets);web 上游真值 → web-search。"
echo "判断原则：按语言选工具,非一刀切优先 MCP。Grep 在 .ets 与文本场景往往是【正确】选择,非 fallback。"
echo "详见：CLAUDE.md '工具决策树' + memory feedback_mcp_tools_fail_on_ets"

# Write static MCP status for statusline (5 servers configured)
echo "5/5" > .claude/.last-mcp-status.txt 2>/dev/null
