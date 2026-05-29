#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT="docs/gc-code-drift-${TIMESTAMP}.md"

ETS_DIR="entry/src/main/ets"
CPP_DIR="entry/src/main/cpp"
TOKENS_FILE="${ETS_DIR}/common/EmuUiTokens.ets"
CLAUDE_MD="CLAUDE.md"
AGENTS_MD="AGENTS.md"

# ── Pattern 1: @State decorating complex types ──────────────────────────────
p1_raw="$(rg '@State' "${ETS_DIR}" --glob '*.ets' -n --no-heading 2>/dev/null \
  | grep -vE ':\s*(string|number|boolean)\s*[=;?]' \
  | grep -v '// ' \
  || true)"
p1_hits="$(echo "${p1_raw}" | grep -c . || true)"
[[ "${p1_raw}" == "" ]] && p1_hits=0

# ── Pattern 2: Inline color literals (not in EmuUiTokens.ets) ───────────────
p2_raw="$(rg "0xFF[0-9A-Fa-f]{6}|'#[0-9A-Fa-f]{3,8}'" "${ETS_DIR}" --glob '*.ets' -n --no-heading 2>/dev/null \
  | grep -v "EmuUiTokens.ets" \
  || true)"
p2_hits="$(echo "${p2_raw}" | grep -c . || true)"
[[ "${p2_raw}" == "" ]] && p2_hits=0

# ── Pattern 3: ForEach without keyGenerator (list for human review) ──────────
p3_raw="$(rg 'ForEach\(' "${ETS_DIR}" --glob '*.ets' -n --no-heading 2>/dev/null || true)"
p3_hits="$(echo "${p3_raw}" | grep -c . || true)"
[[ "${p3_raw}" == "" ]] && p3_hits=0

# ── Pattern 4: build() method > 200 lines ───────────────────────────────────
p4_raw=""
while IFS= read -r filepath; do
  [[ -z "${filepath}" ]] && continue
  result="$(awk '
    /build\(\)[[:space:]]*(:[[:space:]]*void[[:space:]]*)?\{/ && !in_build {
      in_build=1; start=NR; depth=0
    }
    in_build {
      n=split($0,chars,"")
      for(i=1;i<=n;i++){
        if(chars[i]=="{") depth++
        if(chars[i]=="}"){
          depth--
          if(depth==0){
            len=NR-start+1
            if(len>200) print FILENAME ":" start ": build() spans " len " lines"
            in_build=0; break
          }
        }
      }
    }
  ' "${filepath}" 2>/dev/null || true)"
  [[ -n "${result}" ]] && p4_raw="${p4_raw}${result}"$'\n'
done < <(rg 'build\(\)' "${ETS_DIR}" --glob '*.ets' -l --path-separator / 2>/dev/null || true)
p4_hits="$(echo "${p4_raw}" | grep -c . || true)"
[[ "${p4_raw}" == "" ]] && p4_hits=0

# ── Pattern 5: NAPI exports not documented in CLAUDE.md / AGENTS.md ──────────
p5_raw=""
while IFS= read -r fn_name; do
  [[ -z "${fn_name}" ]] && continue
  if ! grep -qF "${fn_name}" "${CLAUDE_MD}" "${AGENTS_MD}" 2>/dev/null; then
    p5_raw="${p5_raw}${fn_name} — not found in CLAUDE.md / AGENTS.md"$'\n'
  fi
done < <(rg '^\s*\{"([a-zA-Z][a-zA-Z0-9_]+)"' "${CPP_DIR}/app/napi" --glob '*.cpp' -o --no-filename 2>/dev/null \
  | sed 's/.*{"\([^"]*\)".*/\1/' | sort -u || true)
p5_hits="$(echo "${p5_raw}" | grep -c . || true)"
[[ "${p5_raw}" == "" ]] && p5_hits=0

# ── Pattern 6: condition_variable wait without lock in scope ─────────────────
p6_raw=""
while IFS= read -r match; do
  [[ -z "${match}" ]] && continue
  file="$(echo "${match}" | cut -d: -f1)"
  lineno="$(echo "${match}" | cut -d: -f2)"
  context="$(awk "NR>=${lineno}-20 && NR<${lineno}" "${file}" 2>/dev/null || true)"
  if ! echo "${context}" | grep -qE 'unique_lock|lock_guard'; then
    p6_raw="${p6_raw}${match} — no unique_lock/lock_guard in preceding 20 lines"$'\n'
  fi
done < <(rg '\.wait(_for|_until)?\(' "${CPP_DIR}" --glob '*.cpp' --glob '*.h' -n --no-heading 2>/dev/null \
  | grep -v 'core/libretro' | grep -v 'fence_utils' || true)
p6_hits="$(echo "${p6_raw}" | grep -c . || true)"
[[ "${p6_raw}" == "" ]] && p6_hits=0

# ── Format hits as markdown list ─────────────────────────────────────────────
fmt_list() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    echo "_none_"
    return
  fi
  echo "${raw}" | grep . | sed 's/^/- `/' | sed 's/$/`/'
}

# ── Write report ─────────────────────────────────────────────────────────────
cat > "${REPORT}" <<EOF
# Code Drift Scan — ${TIMESTAMP}

## Pattern 1: ArkTS @State decorating complex types

Source: entry/src/main/ets/CLAUDE.md#state-decorator
Suspicious hits: ${p1_hits}

$(fmt_list "${p1_raw}")

## Pattern 2: Inline color literals (should use EmuUiTokens)

Source: entry/src/main/ets/CLAUDE.md (EmuUiTokens convention)
Hits: ${p2_hits}

$(fmt_list "${p2_raw}")

## Pattern 3: ForEach — keyGenerator presence (human review required)

Source: entry/src/main/ets/CLAUDE.md#foreach-always-provide-keygenerator
All ForEach calls listed — verify 3rd argument exists: ${p3_hits}

$(fmt_list "${p3_raw}")

## Pattern 4: build() method > 200 lines

Source: entry/src/main/ets/CLAUDE.md#build-method-keep-under-200-lines
Hits: ${p4_hits}

$(fmt_list "${p4_raw}")

## Pattern 5: NAPI exports not documented in CLAUDE.md / AGENTS.md

Source: AGENTS.md (ArkTS/NAPI boundary rule)
Hits: ${p5_hits}

$(fmt_list "${p5_raw}")

## Pattern 6: condition_variable wait without lock in scope

Source: memory feedback_condition_variable_lock_invariant
Hits: ${p6_hits}

$(fmt_list "${p6_raw}")

## Summary

| Pattern | Hits | Severity |
|---|---|---|
| 1. @State complex | ${p1_hits} | P2 |
| 2. Inline color | ${p2_hits} | P2 |
| 3. ForEach no keyGen | ${p3_hits} | P1 |
| 4. build() >200 lines | ${p4_hits} | P1 |
| 5. NAPI exports undocumented | ${p5_hits} | P1 |
| 6. wait without lock | ${p6_hits} | P0 |

Recommend: feed Pattern 5/6 P0/P1 hits into tech-debt-tracker.md.
EOF

echo "[scan_code_drift] Report: ${REPORT}"
echo "  P1:${p1_hits} P2:${p2_hits} P3:${p3_hits} P4:${p4_hits} P5:${p5_hits} P6:${p6_hits}"

total=$((p1_hits + p2_hits + p3_hits + p4_hits + p5_hits + p6_hits))
# Exit code 仅表示 clean/dirty（0/1），total 数字通过上方 echo + REPORT 提供。
# 历史曾用 exit ${total},但 bash exit code 只有 0-255,total > 255 会被 mod 256 截断
# (例 total=640 → exit 128 看起来像 SIGTERM,且 total=256 → exit 0 误判为 clean)。
if [ ${total} -gt 0 ]; then
  exit 1
else
  exit 0
fi
