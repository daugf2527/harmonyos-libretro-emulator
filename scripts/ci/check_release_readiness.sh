#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

failures=0

list_existing_files() {
  local path="$1"
  shift || true
  [[ -e "${path}" ]] || return 0
  rg --files "${path}" "$@" || true
}

report_fail() {
  local code="$1"
  local problem="$2"
  local fix="$3"
  local hits="${4:-}"
  echo "[FAIL] ${code}" >&2
  echo "  Problem:  ${problem}" >&2
  echo "  Fix:      ${fix}" >&2
  if [[ -n "${hits}" ]]; then
    echo "  Hits:" >&2
    while IFS= read -r line; do
      echo "    ${line}" >&2
    done <<< "${hits}"
  fi
  failures=1
}

echo "[INFO] Running store-release readiness checks..."

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] ripgrep (rg) is required." >&2
  exit 1
fi

rom_hits="$(list_existing_files 'entry/src/main/resources/rawfile/roms')"
if [[ -n "${rom_hits}" ]]; then
  report_fail \
    "RR001-BUNDLED-ROM" \
    "Store releases must not ship bundled ROM payloads or ROM-related helper material under rawfile/roms." \
    "Remove the rawfile/roms tree from release-bound resources, or move it fully to an internal/dev-only distribution flow outside the shipping app package." \
    "${rom_hits}"
fi

cover_hits="$(list_existing_files 'entry/src/main/resources/base/media' -g 'cover_*.png')"
if [[ -n "${cover_hits}" ]]; then
  report_fail \
    "RR004-BUNDLED-COVER-IP" \
    "Store releases must not ship bundled commercial-looking cover art assets without a clear redistribution basis." \
    "Replace bundled cover assets with original artwork, generated placeholders, or dynamically imported user-provided covers." \
    "${cover_hits}"
fi

required_docs=(
  "docs/release/appgallery-readiness-checklist.md"
  "docs/release/privacy-policy.md"
  "docs/release/eula.md"
  "docs/release/store-listing-template.md"
)

missing_docs=()
for file in "${required_docs[@]}"; do
  if [[ ! -f "${file}" ]]; then
    missing_docs+=("${file}")
  fi
done
if (( ${#missing_docs[@]} > 0 )); then
  report_fail \
    "RR002-RELEASE-DOCS" \
    "Store-release baseline documents are missing." \
    "Add the required files under docs/release/ and keep them updated before release." \
    "$(printf '%s\n' "${missing_docs[@]}")"
fi

placeholder_hits="$(rg -n 'DrawingToXComponent|module description|Please describe the basic information\.|^  \"license\": \"\"|^  \"author\": \"\"|\"value\": \"description\"' \
  entry/src/main/resources entry/oh-package.json5 --glob '!entry/build/**' || true)"
if [[ -n "${placeholder_hits}" ]]; then
  report_fail \
    "RR003-PLACEHOLDER-METADATA" \
    "User-facing app metadata still contains placeholders or empty legal/package fields." \
    "Replace placeholder labels/descriptions/license metadata with release-ready values." \
    "${placeholder_hits}"
fi

if ((failures != 0)); then
  exit 1
fi

echo "[PASS] Store-release readiness checks passed."
