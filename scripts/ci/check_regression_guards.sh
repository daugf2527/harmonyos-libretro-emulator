#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

FIRST_PARTY_CPP_DIR="entry/src/main/cpp"
FIRST_PARTY_ETS_DIR="entry/src/main/ets"
LIBRETRO_VENDOR_GLOB="!${FIRST_PARTY_CPP_DIR}/core/libretro/**"

failures=0

# report_fail CODE PROBLEM FIX_HINT DOC_ANCHOR [hits_var_name]
# hits_var_name: optional name of a variable containing hit lines (indented under Hits:)
report_fail() {
  local code="$1"
  local problem="$2"
  local fix="$3"
  local see="$4"
  local hits="${5:-}"
  echo "[FAIL] ${code}" >&2
  echo "  Problem:  ${problem}" >&2
  echo "  Fix:      ${fix}" >&2
  echo "  See:      ${see}" >&2
  if [[ -n "${hits}" ]]; then
    echo "  Hits:" >&2
    while IFS= read -r line; do
      echo "    ${line}" >&2
    done <<< "${hits}"
  fi
  failures=1
}

echo "[INFO] Running static regression guards..."

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] ripgrep (rg) is required." >&2
  exit 1
fi

mmap_hits="$(rg -n '\bmmap\s*\(|\bmunmap\s*\(' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${mmap_hits}" ]]; then
  report_fail \
    "RG001-MMAP" \
    "Direct mmap/munmap on NativeWindow buffer bypasses HarmonyOS GPU sync." \
    "Use OH_NativeBuffer_FromNativeWindowBuffer + OH_NativeBuffer_Map/Unmap." \
    "entry/src/main/cpp/CLAUDE.md#nativebuffer-access-pattern" \
    "${mmap_hits}"
fi

request_buffer_files="$(rg -l 'OH_NativeWindow_RequestBuffer' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${request_buffer_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    if ! rg -q 'OH_NativeBuffer_FromNativeWindowBuffer' "${file}"; then
      report_fail \
        "RG002-BUFFER-PAIR" \
        "RequestBuffer without FromNativeWindowBuffer pairing leaks the buffer handle wrapper." \
        "Add OH_NativeBuffer_FromNativeWindowBuffer call in the same file before access." \
        "entry/src/main/cpp/CLAUDE.md#nativebuffer-access-pattern" \
        "${file}"
    fi
  done <<< "${request_buffer_files}"
fi

map_files="$(rg -l 'OH_NativeBuffer_Map' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${map_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    if ! rg -q 'OH_NativeBuffer_Unmap' "${file}"; then
      report_fail \
        "RG003-MAP-UNPAIRED" \
        "OH_NativeBuffer_Map without paired Unmap leaks GPU mapping and causes frame stalls." \
        "Add OH_NativeBuffer_Unmap in same file (typically after pixel write completes)." \
        "entry/src/main/cpp/CLAUDE.md#nativebuffer-access-pattern" \
        "${file}"
    fi
  done <<< "${map_files}"
fi

timeout_hits="$(rg -n 'SET_TIMEOUT[^\n]*(=|,)[[:space:]]*5\b' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${timeout_hits}" ]]; then
  report_fail \
    "RG004-TIMEOUT" \
    "Hard-coded SET_TIMEOUT=5 starves the surface request queue under heavy load." \
    "Use default timeout or >= 1 frame period; make it configurable if tuning needed." \
    "entry/src/main/cpp/CLAUDE.md#banned-patterns" \
    "${timeout_hits}"
fi

todo_hits="$(rg -n '\b(TODO|FIXME|HACK|XXX)\b' "${FIRST_PARTY_CPP_DIR}" "${FIRST_PARTY_ETS_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${todo_hits}" ]]; then
  report_fail \
    "RG005-MARKER" \
    "TODO/FIXME/HACK/XXX in first-party source rots into untracked debt." \
    "File a tech-debt-tracker.md entry or fix before merge." \
    "AGENTS.md#强制规则" \
    "${todo_hits}"
fi

log_domain_files="$(rg -l '^[[:space:]]*#define[[:space:]]+LOG_DOMAIN[[:space:]]+' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" -g '!*.md' || true)"
if [[ -n "${log_domain_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue

    if ! rg -q '^[[:space:]]*#undef[[:space:]]+LOG_DOMAIN\b' "${file}"; then
      report_fail \
        "RG006-LOGDOMAIN-UNDEF" \
        "LOG_DOMAIN redefined without #undef causes hilog domain ambiguity in shared TU." \
        "Add '#undef LOG_DOMAIN' immediately before the #define line." \
        "entry/src/main/cpp/CLAUDE.md#log_domain-constraints" \
        "${file}"
    fi

    while IFS= read -r raw_value; do
      [[ -z "${raw_value}" ]] && continue
      value="${raw_value//[[:space:]]/}"
      domain=-1
      if [[ "${value}" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        hex_part="${value#0x}"
        hex_part="${hex_part#0X}"
        domain=$((16#${hex_part}))
      elif [[ "${value}" =~ ^[0-9]+$ ]]; then
        domain=$((value))
      else
        report_fail \
          "RG008-LOGDOMAIN-PARSE" \
          "LOG_DOMAIN value must be a hex literal (0xNNNN) or decimal integer." \
          "Rewrite the #define as 0xNNNN form (preferred) or plain integer." \
          "entry/src/main/cpp/CLAUDE.md#log_domain-constraints" \
          "${file}: unsupported LOG_DOMAIN value '${value}'"
        continue
      fi

      if ((domain < 0xD000 || domain > 0xFFFF)); then
        report_fail \
          "RG007-LOGDOMAIN-RANGE" \
          "LOG_DOMAIN outside [0xD000, 0xFFFF] collides with hilog system-reserved space." \
          "Pick a unique value in [0xD000, 0xFFFF] for this translation unit." \
          "entry/src/main/cpp/CLAUDE.md#log_domain-constraints" \
          "${file}: LOG_DOMAIN ${value} out of [0xD000, 0xFFFF]"
      fi
    done < <(awk '/^[[:space:]]*#define[[:space:]]+LOG_DOMAIN[[:space:]]+/ { print $3 }' "${file}")
  done <<< "${log_domain_files}"
fi

if ((failures != 0)); then
  exit 1
fi

echo "[PASS] Static regression guards passed."
