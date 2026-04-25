#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

echo "[INFO] Running repository hygiene checks..."

if ! command -v git >/dev/null 2>&1; then
  echo "[FAIL] git is required." >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] ripgrep (rg) is required." >&2
  exit 1
fi

conflicts="$(rg -n --hidden --glob '!.git' '^(<<<<<<< .+|=======|>>>>>>> .+)$' || true)"
if [[ -n "${conflicts}" ]]; then
  echo "[FAIL] Merge conflict markers detected:" >&2
  echo "${conflicts}" >&2
  exit 1
fi

tracked_build_outputs="$(git ls-files | rg '^(entry/build/|entry/\.cxx/|entry/\.preview/|\.hvigor/|oh_modules/)' || true)"
if [[ -n "${tracked_build_outputs}" ]]; then
  echo "[FAIL] Tracked build/cache outputs detected:" >&2
  echo "${tracked_build_outputs}" >&2
  exit 1
fi

shell_files="$(rg --files -g '*.sh' || true)"
if [[ -n "${shell_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    bash -n "${file}"
  done <<< "${shell_files}"
fi

echo "[PASS] Repository hygiene checks passed."
