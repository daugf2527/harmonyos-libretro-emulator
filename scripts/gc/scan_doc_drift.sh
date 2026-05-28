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
  grep -oE '`(entry|scripts|docs)/[^` )]+`|\((entry|scripts|docs)/[^)]+\)|(entry|scripts|docs)/[A-Za-z0-9_./*-]+' "$file" 2>/dev/null \
    | sed 's/^`//; s/`$//; s/^(//; s/)$//' \
    | sed 's/:[0-9]*$//' \
    | sort -u
}

path_exists() {
  local p="$1"
  if [[ "$p" == *"*"* ]]; then
    local parent="${p%%\**}"
    parent="${parent%/}"
    [ -d "$parent" ]
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

# ── Summary ──────────────────────────────────────────────────────────────────
grand_total=$((a_total + b_total + d_total + c_total))
grand_drifts=$((a_drifts + b_drifts + d_drifts))

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

exit ${grand_drifts}
