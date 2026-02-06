#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

FIRST_PARTY_CPP_DIR="entry/src/main/cpp"
FIRST_PARTY_ETS_DIR="entry/src/main/ets"
LIBRETRO_VENDOR_GLOB="!${FIRST_PARTY_CPP_DIR}/core/libretro/**"

failures=0

report_fail() {
  echo "[FAIL] $1" >&2
  failures=1
}

echo "[INFO] Running static regression guards..."

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] ripgrep (rg) is required." >&2
  exit 1
fi

mmap_hits="$(rg -n '\bmmap\s*\(|\bmunmap\s*\(' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${mmap_hits}" ]]; then
  report_fail "Direct mmap/munmap usage is forbidden for NativeWindow pixel access."
  echo "${mmap_hits}" >&2
fi

request_buffer_files="$(rg -l 'OH_NativeWindow_RequestBuffer' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${request_buffer_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    if ! rg -q 'OH_NativeBuffer_FromNativeWindowBuffer' "${file}"; then
      report_fail "${file}: OH_NativeWindow_RequestBuffer requires OH_NativeBuffer_FromNativeWindowBuffer."
    fi
  done <<< "${request_buffer_files}"
fi

map_files="$(rg -l 'OH_NativeBuffer_Map' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${map_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    if ! rg -q 'OH_NativeBuffer_Unmap' "${file}"; then
      report_fail "${file}: OH_NativeBuffer_Map requires OH_NativeBuffer_Unmap in same file."
    fi
  done <<< "${map_files}"
fi

timeout_hits="$(rg -n 'SET_TIMEOUT[^\n]*(=|,)[[:space:]]*5\b' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${timeout_hits}" ]]; then
  report_fail "Hard-coded SET_TIMEOUT=5 is forbidden."
  echo "${timeout_hits}" >&2
fi

todo_hits="$(rg -n '\b(TODO|FIXME|HACK|XXX)\b' "${FIRST_PARTY_CPP_DIR}" "${FIRST_PARTY_ETS_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${todo_hits}" ]]; then
  report_fail "TODO/FIXME/HACK/XXX markers are not allowed in first-party source."
  echo "${todo_hits}" >&2
fi

log_domain_files="$(rg -l '^[[:space:]]*#define[[:space:]]+LOG_DOMAIN[[:space:]]+' "${FIRST_PARTY_CPP_DIR}" -S -g "${LIBRETRO_VENDOR_GLOB}" || true)"
if [[ -n "${log_domain_files}" ]]; then
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue

    if ! rg -q '^[[:space:]]*#undef[[:space:]]+LOG_DOMAIN\b' "${file}"; then
      report_fail "${file}: missing '#undef LOG_DOMAIN' before redefinition."
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
        report_fail "${file}: unsupported LOG_DOMAIN value '${value}'."
        continue
      fi

      if ((domain < 0xD000 || domain > 0xFFFF)); then
        report_fail "${file}: LOG_DOMAIN ${value} out of [0xD000, 0xFFFF]."
      fi
    done < <(awk '/^[[:space:]]*#define[[:space:]]+LOG_DOMAIN[[:space:]]+/ { print $3 }' "${file}")
  done <<< "${log_domain_files}"
fi

if ((failures != 0)); then
  exit 1
fi

echo "[PASS] Static regression guards passed."
