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

file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${file}" ]] && rg -q "${pattern}" "${file}"
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
  "docs/release/release-candidate-runbook.md"
  "docs/release/appgallery-submission-matrix.md"
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
  AppScope/resources entry/src/main/resources entry/oh-package.json5 --glob '!entry/build/**' || true)"
if [[ -n "${placeholder_hits}" ]]; then
  report_fail \
    "RR003-PLACEHOLDER-METADATA" \
    "User-facing app metadata still contains placeholders or empty legal/package fields." \
    "Replace placeholder labels/descriptions/license metadata with release-ready values." \
    "${placeholder_hits}"
fi

release_placeholder_hits="$(rg -n '联系方式占位|发布前补齐|草案|TODO|TBD|待填写|待补齐|example\.com|your-email|support@example' \
  docs/release SUPPORT.md SECURITY.md --glob '!entry/build/**' || true)"
if [[ -n "${release_placeholder_hits}" ]]; then
  report_fail \
    "RR005-RELEASE-MATERIAL-PLACEHOLDER" \
    "Store-facing release material still contains placeholders or draft markers." \
    "Replace draft markers with release-ready wording, or move non-final notes to a non-store-facing internal plan." \
    "${release_placeholder_hits}"
fi

metadata_missing=()
if ! file_contains "AppScope/resources/base/element/string.json" '"name": "app_name"'; then
  metadata_missing+=("AppScope/resources/base/element/string.json: missing app_name")
fi
if ! file_contains "AppScope/resources/base/element/string.json" '"value": "碳影"'; then
  metadata_missing+=("AppScope/resources/base/element/string.json: app_name is not 碳影")
fi
if ! file_contains "AppScope/app.json5" '"vendor": "Carbon Shade Project"'; then
  metadata_missing+=("AppScope/app.json5: vendor mismatch")
fi
if ! file_contains "AppScope/app.json5" '"versionName": "1.0.0"'; then
  metadata_missing+=("AppScope/app.json5: versionName missing or unexpected")
fi
if (( ${#metadata_missing[@]} > 0 )); then
  report_fail \
    "RR006-APP-METADATA-INCOMPLETE" \
    "AppScope metadata is incomplete or not aligned with store listing material." \
    "Align app name, vendor, versionName, icon, and label resources before submitting to AppGallery Connect." \
    "$(printf '%s\n' "${metadata_missing[@]}")"
fi

release_contract_missing=()
if ! file_contains "docs/release/privacy-policy.md" "Carbon Shade Project"; then
  release_contract_missing+=("docs/release/privacy-policy.md: missing developer/team name")
fi
if ! file_contains "docs/release/privacy-policy.md" "ohos.permission.VIBRATE"; then
  release_contract_missing+=("docs/release/privacy-policy.md: missing declared permission explanation")
fi
if ! file_contains "docs/release/eula.md" "不提供"; then
  release_contract_missing+=("docs/release/eula.md: missing no-download/no-content distribution boundary")
fi
if ! file_contains "docs/release/store-listing-template.md" "不提供 ROM、BIOS"; then
  release_contract_missing+=("docs/release/store-listing-template.md: missing ROM/BIOS no-download statement")
fi
if ! file_contains "docs/release/release-candidate-runbook.md" "AppGallery Connect"; then
  release_contract_missing+=("docs/release/release-candidate-runbook.md: missing AppGallery Connect submission steps")
fi
if ! file_contains "docs/release/appgallery-submission-matrix.md" "隐私政策 URL"; then
  release_contract_missing+=("docs/release/appgallery-submission-matrix.md: missing privacy URL status")
fi
if (( ${#release_contract_missing[@]} > 0 )); then
  report_fail \
    "RR007-RELEASE-CONTRACT-INCOMPLETE" \
    "Release-facing legal, privacy, or store listing material does not cover the AppGallery submission baseline." \
    "Complete privacy, EULA, store listing, and submission matrix documents before submitting." \
    "$(printf '%s\n' "${release_contract_missing[@]}")"
fi

if ((failures != 0)); then
  exit 1
fi

echo "[PASS] Store-release readiness checks passed."
