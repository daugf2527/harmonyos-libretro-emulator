#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

MEMORY_DIR="/c/Users/newwo/.claude/projects/D--windsulf-daugf2527-repos-harmonyos-libretro-emulator/memory"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="docs/gc-drift-report-${TIMESTAMP}.md"

total_refs=0
total_drifts=0

rpt() { printf '%s\n' "$*" | tee -a "${REPORT}"; }

extract_paths() {
  local file="$1"
  # 提取候选路径,做纯机械层(L1)过滤:
  # B5 <TS>/<YYYYMMDD-HHMMSS> 等模板占位符 — 字符级匹配,L1 合法
  # B6 ... 省略号占位符(英文) — 字符级,L1 合法
  # B4 句末标点(.md. / .md, / .md; / .md-) — 字符级 sed 剥除,L1 合法
  # B3 跨仓库绝对路径(/d/foo/docs/...) — 提取正则加锚点,字符级,L1 合法
  # B2 fenced code block(```...```) — markdown 结构语法,机械可识别,L1 合法
  #
  # 不在 L1 做(已上移到 /gc Step 3 主 AI):
  # B1 否定语境(replaces/removed/deprecated)— 关键词匹配是脆弱启发式,
  #    新词("superseded by"等)会漏;改由主 AI Step 3 看上下文 5-10 行判定。
  #    见 memory feedback_skill_role_separation.
  awk '
    BEGIN { in_code = 0 }
    /^[ \t]*```/ { in_code = !in_code; next }
    { if (!in_code) printf "%d:%s\n", NR, $0 }
  ' "$file" 2>/dev/null \
    | grep -E '(^|[ `(\[\|])(entry|scripts|docs)/[A-Za-z0-9_./*-]+' \
    | while IFS=: read -r lno content; do
        # B5: 跳过含模板占位符 <...> 的整行(提取后再过滤会丢失 < > 信息)
        if echo "$content" | grep -qE '<[A-Za-z_][A-Za-z0-9_-]*>'; then
          continue
        fi
        # 提取该行所有候选路径(要求前面是非路径字符)
        echo "$content" | grep -oE '(^|[ `(\[\|])(entry|scripts|docs)/[A-Za-z0-9_./*-]+' \
          | sed 's/^[^a-zA-Z]//'
      done \
    | sed 's/^`//; s/`$//; s/^(//; s/)$//' \
    | sed 's/:[0-9]*$//' \
    | sed 's/[.,;:-]*$//' \
    | grep -vE '<[^>]+>' \
    | grep -vE '\.\.\.' \
    | sort -u
}

path_exists() {
  local p="$1"
  if [[ "$p" == *"*"* ]]; then
    # 含 glob 的路径: 用 bash glob 实际展开,看是否有任何匹配
    # 旧实现"只查第一个 * 之前的父目录存在"会误报多 * pattern(如 docs/gc-*-report-*.md
    # 拆出 docs/gc- 父目录就不存在);改用 compgen 真实展开
    local matches
    matches=$(compgen -G "$p" 2>/dev/null | head -1)
    [ -n "$matches" ]
  else
    [ -e "$p" ]
  fi
}

check_paths_in_file() {
  local src_file="$1"
  local section_drifts=0
  local section_refs=0
  local drift_lines=""

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    section_refs=$((section_refs + 1))
    if ! path_exists "$path"; then
      section_drifts=$((section_drifts + 1))
      local lineno
      lineno=$(grep -n "$path" "$src_file" 2>/dev/null | head -1 | cut -d: -f1 || echo "?")
      drift_lines="${drift_lines}  - \`${path}\` referenced in ${src_file}:${lineno} -> MISSING\n"
    fi
  done < <(extract_paths "$src_file")

  total_refs=$((total_refs + section_refs))
  total_drifts=$((total_drifts + section_drifts))

  printf '%s:%s:%s' "$section_refs" "$section_drifts" "$drift_lines"
}

mkdir -p docs
printf '# Doc Drift Report -- %s\n\n' "${TIMESTAMP}" > "${REPORT}"

# ── Check A ──────────────────────────────────────────────────────────────────
rpt "## A. CLAUDE.md / AGENTS.md path references"
rpt ""

A_SOURCES=(
  "CLAUDE.md"
  "AGENTS.md"
  "entry/src/main/ets/CLAUDE.md"
  "entry/src/main/cpp/CLAUDE.md"
)

while IFS= read -r f; do A_SOURCES+=("$f"); done < <(find .claude/skills -name 'SKILL.md' 2>/dev/null | sed 's|^\./||' || true)
while IFS= read -r f; do A_SOURCES+=("$f"); done < <(find .claude/skills/closed-loop/topics -name 'T*.md' 2>/dev/null | sed 's|^\./||' || true)
while IFS= read -r f; do A_SOURCES+=("$f"); done < <(find .claude/agents -name '*.md' 2>/dev/null | sed 's|^\./||' || true)

a_total=0; a_drifts=0; a_drift_text=""
for src in "${A_SOURCES[@]}"; do
  [ -f "$src" ] || continue
  result=$(check_paths_in_file "$src")
  refs="${result%%:*}"; rest="${result#*:}"; drifts="${rest%%:*}"; lines="${rest#*:}"
  a_total=$((a_total + refs))
  a_drifts=$((a_drifts + drifts))
  [[ -n "$lines" ]] && a_drift_text="${a_drift_text}${lines}"
done

rpt "- Total references: ${a_total}"
rpt "- Drift count: ${a_drifts}"
if [[ -n "$a_drift_text" ]]; then
  rpt "- Drifted:"
  printf '%b' "$a_drift_text" | tee -a "${REPORT}"
else
  rpt "- Drifted: none"
fi
rpt ""

# ── Check B ──────────────────────────────────────────────────────────────────
rpt "## B. Historical fix log file references"
rpt ""

ETS_CLAUDE="entry/src/main/ets/CLAUDE.md"
b_total=0; b_drifts=0; b_drift_text=""

if [ -f "$ETS_CLAUDE" ]; then
  while IFS= read -r fname; do
    [[ -z "$fname" ]] && continue
    b_total=$((b_total + 1))
    total_refs=$((total_refs + 1))
    if ! find "entry/src/main/ets" -name "$fname" 2>/dev/null | grep -q .; then
      b_drifts=$((b_drifts + 1))
      total_drifts=$((total_drifts + 1))
      lineno=$(grep -n "$fname" "$ETS_CLAUDE" 2>/dev/null | head -1 | cut -d: -f1 || echo "?")
      b_drift_text="${b_drift_text}  - \`${fname}\` referenced in ${ETS_CLAUDE}:${lineno} -> MISSING\n"
    fi
  done < <(grep -oE '`[A-Za-z0-9_-]+\.ets`' "$ETS_CLAUDE" 2>/dev/null | tr -d '`' | sort -u || true)
fi

rpt "- Total references: ${b_total}"
rpt "- Drift count: ${b_drifts}"
if [[ -n "$b_drift_text" ]]; then
  rpt "- Drifted:"
  printf '%b' "$b_drift_text" | tee -a "${REPORT}"
else
  rpt "- Drifted: none"
fi
rpt ""

# ── Check C ──────────────────────────────────────────────────────────────────
rpt "## C. docs/plans/ completed plan commit references (warnings only)"
rpt ""

c_total=0; c_warn=0; c_warn_text=""

if [ -d "docs/plans" ]; then
  while IFS= read -r plan; do
    while IFS= read -r hash; do
      [[ -z "$hash" ]] && continue
      c_total=$((c_total + 1))
      total_refs=$((total_refs + 1))
      if ! git log --format='%H %h' 2>/dev/null | grep -qF "$hash"; then
        c_warn=$((c_warn + 1))
        c_warn_text="${c_warn_text}  - \`${hash}\` in ${plan} -> NOT FOUND in git log (warning)\n"
      fi
    done < <(grep -iE '已完成|已 merge|已上线|completed:' "$plan" 2>/dev/null \
              | grep -oE '[0-9a-f]{7,40}' | sort -u || true)
  done < <(find docs/plans -name '*.md' 2>/dev/null || true)
fi

rpt "- Total commit refs checked: ${c_total}"
rpt "- Warnings (hash not in git log): ${c_warn}"
if [[ -n "$c_warn_text" ]]; then
  rpt "- Warnings:"
  printf '%b' "$c_warn_text" | tee -a "${REPORT}"
else
  rpt "- Warnings: none"
fi
rpt ""

# ── Check D ──────────────────────────────────────────────────────────────────
rpt "## D. Memory file path references"
rpt ""

d_total=0; d_drifts=0; d_drift_text=""

if [ -d "$MEMORY_DIR" ]; then
  while IFS= read -r mfile; do
    [ -f "$mfile" ] || continue
    result=$(check_paths_in_file "$mfile")
    refs="${result%%:*}"; rest="${result#*:}"; drifts="${rest%%:*}"; lines="${rest#*:}"
    d_total=$((d_total + refs))
    d_drifts=$((d_drifts + drifts))
    [[ -n "$lines" ]] && d_drift_text="${d_drift_text}${lines}"
  done < <(find "$MEMORY_DIR" -name '*.md' 2>/dev/null || true)
else
  rpt "> Warning: memory directory not found at ${MEMORY_DIR}"
fi

rpt "- Total references: ${d_total}"
rpt "- Drift count: ${d_drifts}"
if [[ -n "$d_drift_text" ]]; then
  rpt "- Drifted:"
  printf '%b' "$d_drift_text" | tee -a "${REPORT}"
else
  rpt "- Drifted: none"
fi
rpt ""

# ── Check E ──────────────────────────────────────────────────────────────────
# 元规则扩散扫描(2026-05-29 加,机制 3)
# memory 含 MANDATORY/必备/必跑/必用 等元规则关键词的 feedback_*.md,
# 应在 CLAUDE.md / AGENTS.md / .claude/skills/**/*.md 至少一处被引用,
# 否则是"决策孤岛"(memory 立规但散在文档不知道,见 feedback_deprecation_drift_needs_mechanism)
rpt "## E. Memory meta-rule diffusion (元规则扩散扫描)"
rpt ""

e_total=0; e_warn=0; e_warn_text=""

if [ -d "$MEMORY_DIR" ]; then
  # 找含元规则关键词的 memory 文件
  while IFS= read -r mfile; do
    [ -f "$mfile" ] || continue
    # 文件含 "MANDATORY" / "必备" / "必跑" / "必用" / "强制" → 视为元规则 memory
    if ! grep -qiE 'MANDATORY|必备|必跑|必用|强制' "$mfile" 2>/dev/null; then
      continue
    fi
    e_total=$((e_total + 1))
    total_refs=$((total_refs + 1))

    # 拿 memory 文件名(不含路径,不含 .md 后缀)作为引用 key
    mname=$(basename "$mfile" .md)

    # 扫 CLAUDE.md / AGENTS.md / 项目内 sub-CLAUDE.md / .claude/skills 是否含此 key
    # 加 user-level ~/.claude/CLAUDE.md(跨项目方法论可能在 user 层引,不算孤岛)
    user_claudemd="${HOME}/.claude/CLAUDE.md"
    if ! grep -rqlE "${mname}" CLAUDE.md AGENTS.md entry/src/main/ets/CLAUDE.md entry/src/main/cpp/CLAUDE.md .claude/skills "$user_claudemd" 2>/dev/null; then
      e_warn=$((e_warn + 1))
      total_drifts=$((total_drifts + 1))
      e_warn_text="${e_warn_text}  - \`${mname}\` (memory MANDATORY rule) -> NOT REFERENCED in CLAUDE.md/AGENTS.md/skills/ (含 user-level)\n"
    fi
  done < <(find "$MEMORY_DIR" -name 'feedback_*.md' 2>/dev/null || true)
fi

rpt "- Total meta-rule memory checked: ${e_total}"
rpt "- Diffusion gaps (memory not referenced anywhere): ${e_warn}"
if [[ -n "$e_warn_text" ]]; then
  rpt "- Drifted:"
  printf '%b' "$e_warn_text" | tee -a "${REPORT}"
else
  rpt "- Drifted: none"
fi
rpt ""

# ── Summary ──────────────────────────────────────────────────────────────────
grand_total=$((a_total + b_total + d_total + c_total + e_total))
grand_drifts=$((a_drifts + b_drifts + d_drifts + e_warn))

rpt "## Summary"
rpt ""
rpt "Total checks: ${grand_total}"
rpt "Drifts found: ${grand_drifts}"
if [[ $grand_drifts -gt 0 ]]; then
  rpt "Recommend action: feed into tech-debt-tracker.md if Y > 0"
else
  rpt "Recommend action: none — all references valid"
fi

echo ""
echo "Report written to: ${ROOT_DIR}/${REPORT}"

# Exit code 仅表示 clean/dirty(0/1),drift 数字通过 stdout + REPORT 提供。
# bash exit code 只有 0-255,grand_drifts > 255 时会被 mod 256 截断造成误判。
if [ ${grand_drifts} -gt 0 ]; then
  exit 1
else
  exit 0
fi
