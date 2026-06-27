#!/usr/bin/env bash
# scripts/check/quick_signals.sh
#
# AI feedback loop entry point — combines fast static checks plus (when
# build artifacts exist) an incremental native build into one PASS/FAIL
# summary. Designed to be invoked after code edits to give Claude or human
# a quick signal without waiting for a full hvigor sync.
#
# Usage:
#   bash scripts/check/quick_signals.sh
#
# Exit code:
#   0 = all signals PASS or SKIP
#   1 = at least one signal FAIL
#
# Flags:
#   --quiet / -q  suppress per-check output; only emit summary (+ failing
#                 check output on FAIL). Used by pre-commit hook so a clean
#                 commit doesn't flood the terminal with 100+ lines.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CXX_BUILD_DIR="entry/.cxx/default/default/debug/arm64-v8a"

# M3 core-compat: 核心 .so 产物 + 本地测试 ROM 目录（任一存在即可生成清单）
M3_CORES_DIR="entry/build/default/intermediates/libs/default/arm64"
M3_ROMS_DIR="${M3_TEST_ROMS_DIR:-build/test-roms}"

# hvigor bundles its own cmake outside $PATH. Fall back through known
# install locations before giving up.
find_cmake() {
  if command -v cmake >/dev/null 2>&1; then
    command -v cmake
    return 0
  fi
  local candidates=(
    "D:/Program Files/DevEco Studio/sdk/default/openharmony/native/build-tools/cmake/bin/cmake.exe"
    "/c/Program Files/DevEco Studio/sdk/default/openharmony/native/build-tools/cmake/bin/cmake.exe"
    "${HOME}/AppData/Local/Programs/DevEco Studio/sdk/default/openharmony/native/build-tools/cmake/bin/cmake.exe"
  )
  for p in "${candidates[@]}"; do
    if [[ -x "${p}" ]]; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

NAMES=()
RESULTS=()
SECS=()
LOGS=()   # per-check log paths (quiet mode only)

QUIET=0
for arg in "$@"; do
  case "$arg" in --quiet|-q) QUIET=1 ;; esac
done

run_check() {
  local name="$1"; shift
  local t0=${SECONDS} rc=0

  if [[ $QUIET -eq 1 ]]; then
    local tmp; tmp=$(mktemp)
    LOGS+=("$tmp")
    "$@" >"$tmp" 2>&1; rc=$?
    sed -i "s|^|[${name}] |" "$tmp" 2>/dev/null || true
  else
    "$@" 2>&1 | sed "s|^|[${name}] |"
    rc=${PIPESTATUS[0]}
  fi

  local dur=$((SECONDS - t0))
  NAMES+=("$name"); SECS+=("$dur")
  (( rc == 0 )) && RESULTS+=("PASS") || RESULTS+=("FAIL")
}

skip_check() {
  local name="$1" reason="$2"
  [[ $QUIET -eq 0 ]] && echo "[${name}] SKIP: ${reason}"
  NAMES+=("$name"); SECS+=("0"); RESULTS+=("SKIP")
}

trap 'echo ""; echo "==== quick_signals interrupted ===="; exit 130' INT TERM

[[ $QUIET -eq 0 ]] && echo "==== quick_signals starting ===="

run_check regression bash scripts/ci/check_regression_guards.sh
run_check hygiene    bash scripts/ci/check_repo_hygiene.sh
run_check ui-fixes   bash scripts/test/verify_ui_fixes.sh
run_check skill-contract bash scripts/ci/check_skill_contract.sh

# M3 Layer 1: 生成核心兼容性测试清单（需先编译产物或有 ROM 目录）
if [[ -d "${M3_CORES_DIR}" || -d "${M3_ROMS_DIR}" ]]; then
  run_check core-compat bash scripts/test/check_core_compatibility.sh
else
  skip_check core-compat "核心产物/本地测试 ROM 目录均不存在；需先 DevEco Sync/编译，或设置 M3_TEST_ROMS_DIR"
fi

if [[ -f "${CXX_BUILD_DIR}/build.ninja" ]]; then
  if cmake_bin="$(find_cmake)"; then
    run_check cxx-build "${cmake_bin}" --build "${CXX_BUILD_DIR}"
  else
    skip_check cxx-build "cmake not found (extend find_cmake() in this script)"
  fi
else
  skip_check cxx-build "no build.ninja under ${CXX_BUILD_DIR}; run DevEco Sync first"
fi

total_fail=0
for i in "${!NAMES[@]}"; do
  [[ "${RESULTS[$i]}" == "FAIL" ]] && total_fail=$((total_fail + 1))
done

if (( total_fail == 0 )); then
  final_status="ALL PASS / SKIP"
  exit_code=0
else
  final_status="${total_fail} FAIL"
  exit_code=1
fi

if [[ $QUIET -eq 1 && $exit_code -ne 0 ]]; then
  # Quiet+FAIL: replay buffered output for failing checks only.
  for i in "${!NAMES[@]}"; do
    if [[ "${RESULTS[$i]}" == "FAIL" && -n "${LOGS[$i]:-}" ]]; then
      cat "${LOGS[$i]}"
    fi
  done
fi
# Clean up temp logs.
for f in "${LOGS[@]:-}"; do [[ -f "$f" ]] && rm -f "$f"; done

echo ""
echo "==== quick_signals summary ===="
for i in "${!NAMES[@]}"; do
  printf "  %-12s %-5s (%ss)\n" "${NAMES[$i]}" "${RESULTS[$i]}" "${SECS[$i]}"
done
echo ""
if (( total_fail == 0 )); then
  echo "==== ALL PASS / SKIP ===="
else
  echo "==== ${total_fail} FAIL ===="
fi

# Persist summary for H3 SessionStart hook to read on next session.
# Failure to write is non-fatal (e.g. read-only filesystem in CI).
{
  mkdir -p .claude 2>/dev/null
  {
    echo "# quick_signals snapshot — $(date '+%Y-%m-%d %H:%M:%S')"
    for i in "${!NAMES[@]}"; do
      printf "  %-12s %-5s (%ss)\n" "${NAMES[$i]}" "${RESULTS[$i]}" "${SECS[$i]}"
    done
    echo "  => ${final_status}"
  } > .claude/.last-quick-signals.txt 2>/dev/null
} || true

exit "${exit_code}"
