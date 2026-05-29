#!/usr/bin/env bash

# scripts/ci/check_skill_contract.sh
# 元规则机制 1(2026-05-29):扫每个 SKILL.md 里 ### Step N / ### L<n> 标题
# 后面是否齐全 5 段契约(In / Out / Role / Done)。缺一段 = fail。
#
# 沉淀的元方法论:
#   - memory feedback_task_contract_missing  (Layer 2 根因)
#   - memory feedback_skill_role_separation  (Layer 1 4 层 ROLE)
#
# 5 段契约模板(每个 step / 层必备):
#   > **In**:  ...
#   > **Out**: ...
#   > **Role**: [L1/L2/L3/L4] + [NOT 越权]
#   > **Done**: [ ] checklist

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

failures=0
checked_files=0
checked_steps=0
violating_steps=0
violations=""

# 检查的 SKILL 文件清单(只查工作流 skill,不查"什么时候用 X"类指南 skill)
SKILL_FILES=(
  ".claude/skills/closed-loop/SKILL.md"
  ".claude/skills/four-way-audit/SKILL.md"
  ".claude/skills/gc/SKILL.md"
  ".claude/skills/auto-commit-cicd/SKILL.md"
)

# 例外清单(故意不需要 5 段契约的 step,在文件名:Step 标题 处加豁免)
# 例: closed-loop "## The 8 fix steps (Step 0 是 sprint contract...)" 是章节标题,不是 step
# 通过下面的 step 正则 "^### Step [0-9]" / "^### L[0-9]" 自然过滤掉

check_step_block() {
  local file="$1"
  local start_line="$2"
  local step_title="$3"

  # 取 step 标题后 40 行作为 contract block 检查范围(支持 blockquote 紧凑式 4 行
  # 或 paragraph 展开式 5 段;后者较长,40 行是安全上限)
  local block
  block=$(sed -n "$((start_line + 1)),$((start_line + 40))p" "$file")

  local missing=""

  # In: 支持 blockquote "> **In**:" 或 paragraph "**Input**:" 两种
  if ! echo "$block" | grep -qE '^\s*(>\s*)?\*\*(In|Input)\*\*[:：]'; then
    missing="${missing} In"
  fi
  # Out: 支持 "> **Out**:" 或 "**Output**:"
  if ! echo "$block" | grep -qE '^\s*(>\s*)?\*\*(Out|Output)\*\*[:：]'; then
    missing="${missing} Out"
  fi
  # Role: 支持 "> **Role**:" 或 "**ROLE matrix**:"
  if ! echo "$block" | grep -qE '^\s*(>\s*)?\*\*(Role|ROLE matrix)\*\*[:：]'; then
    missing="${missing} Role"
  fi
  # Done: 支持 "> **Done**:" 或 "**Done criteria**:"
  if ! echo "$block" | grep -qE '^\s*(>\s*)?\*\*(Done|Done criteria)\*\*[:：]'; then
    missing="${missing} Done"
  fi

  if [[ -n "$missing" ]]; then
    violating_steps=$((violating_steps + 1))
    violations="${violations}  ${file}:${start_line} \"${step_title}\" — missing:${missing}"$'\n'
  fi
}

for file in "${SKILL_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[WARN] Skill file not found: $file" >&2
    continue
  fi

  checked_files=$((checked_files + 1))

  # 提取所有 ### Step N / ### L<n> 标题及其行号
  while IFS=: read -r lno title; do
    [[ -z "$lno" ]] && continue
    checked_steps=$((checked_steps + 1))
    check_step_block "$file" "$lno" "$title"
  done < <(grep -nE '^### (Step [0-9]+|L[0-9]+(\.[0-9]+)?)\s' "$file" 2>/dev/null || true)
done

# 报告
echo "[INFO] check_skill_contract: 扫 ${checked_files} 文件,${checked_steps} 个 step/层"

if [[ $violating_steps -gt 0 ]]; then
  echo "[FAIL] SKILL_CONTRACT_MISSING" >&2
  echo "  Problem:  ${violating_steps}/${checked_steps} 个 step 缺 5 段契约(In/Out/Role/Done)" >&2
  echo "  Fix:      给每个 ### Step N / ### L<n> 标题下加 4 行 markdown blockquote:" >&2
  echo "              > **In**:  上一步产物 file/state" >&2
  echo "              > **Out**: 我交什么 → 下一步如何 trust" >&2
  echo "              > **Role**: [L1 脚本/L2 MCP/L3 subagent/L4 主 AI] + [NOT 越权]" >&2
  echo "              > **Done**: [ ] checklist 可勾选" >&2
  echo "  See:      memory feedback_task_contract_missing + feedback_skill_role_separation" >&2
  echo "  Hits:" >&2
  printf '%s' "$violations" >&2
  exit 1
fi

echo "[OK] All ${checked_steps} steps have 5-段契约 (In/Out/Role/Done)"
exit 0
