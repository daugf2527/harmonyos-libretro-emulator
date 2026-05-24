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

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CXX_BUILD_DIR="entry/.cxx/default/default/debug/arm64-v8a"

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

run_check() {
  local name="$1"
  shift
  local t0=${SECONDS}

  "$@" 2>&1 | sed "s|^|[${name}] |"
  local rc=${PIPESTATUS[0]}

  local dur=$((SECONDS - t0))
  NAMES+=("${name}")
  SECS+=("${dur}")
  if (( rc == 0 )); then
    RESULTS+=("PASS")
  else
    RESULTS+=("FAIL")
  fi
}

skip_check() {
  local name="$1"
  local reason="$2"
  echo "[${name}] SKIP: ${reason}"
  NAMES+=("${name}")
  SECS+=("0")
  RESULTS+=("SKIP")
}

trap 'echo ""; echo "==== quick_signals interrupted ===="; exit 130' INT TERM

echo "==== quick_signals starting ===="

run_check regression bash scripts/ci/check_regression_guards.sh
run_check hygiene    bash scripts/ci/check_repo_hygiene.sh
run_check ui-fixes   bash scripts/test/verify_ui_fixes.sh

if [[ -f "${CXX_BUILD_DIR}/build.ninja" ]]; then
  if cmake_bin="$(find_cmake)"; then
    run_check cxx-build "${cmake_bin}" --build "${CXX_BUILD_DIR}"
  else
    skip_check cxx-build "cmake not found (extend find_cmake() in this script)"
  fi
else
  skip_check cxx-build "no build.ninja under ${CXX_BUILD_DIR}; run DevEco Sync first"
fi

echo ""
echo "==== quick_signals summary ===="
total_fail=0
for i in "${!NAMES[@]}"; do
  printf "  %-12s %-5s (%ss)\n" "${NAMES[$i]}" "${RESULTS[$i]}" "${SECS[$i]}"
  [[ "${RESULTS[$i]}" == "FAIL" ]] && total_fail=$((total_fail + 1))
done

echo ""
if (( total_fail == 0 )); then
  echo "==== ALL PASS / SKIP ===="
  exit 0
else
  echo "==== ${total_fail} FAIL ===="
  exit 1
fi
