#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

hvigorw_bin="${ROOT_DIR}/hvigorw"
if [[ ! -x "${hvigorw_bin}" ]]; then
  if ! command -v hvigorw >/dev/null 2>&1; then
    echo "[FAIL] hvigorw is required in PATH." >&2
    exit 1
  fi
  hvigorw_bin="$(command -v hvigorw)"
fi

if [[ ! -x "${hvigorw_bin}" ]]; then
  echo "[FAIL] hvigorw is not executable: ${hvigorw_bin}" >&2
  exit 1
fi

if ! command -v ohpm >/dev/null 2>&1; then
  echo "[FAIL] ohpm is required in PATH." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[FAIL] npm is required in PATH." >&2
  exit 1
fi

build_mode="${HARMONY_BUILD_MODE:-release}"
product_name="${HARMONY_PRODUCT_NAME:-default}"
module_target="${HARMONY_MODULE_TARGET:-entry@default}"

echo "[INFO] Configuring npm/ohpm registry..."
npm config set strict-ssl false
npm config set registry https://repo.huaweicloud.com/repository/npm/
npm config set "@ohos:registry" https://repo.harmonyos.com/npm/

ohpm config set registry https://ohpm.openharmony.cn/ohpm/
ohpm config set strict_ssl false

install_deps() {
  local dir="$1"
  if [[ ! -f "${dir}/oh-package.json5" ]]; then
    return
  fi
  echo "[INFO] Installing dependencies in ${dir}"
  (
    cd "${dir}"
    ohpm install --all
  )
}

install_deps "${ROOT_DIR}"
install_deps "${ROOT_DIR}/entry"

echo "[INFO] Running hvigor unsigned build..."
"${hvigorw_bin}" clean --no-daemon
"${hvigorw_bin}" assembleHap --mode module \
  -p module="${module_target}" \
  -p product="${product_name}" \
  -p buildMode="${build_mode}" \
  -p enableSignTask=false \
  --no-daemon

mapfile -t hap_files < <(find "${ROOT_DIR}/entry/build" -type f -name "*.hap" | sort)
if (( ${#hap_files[@]} == 0 )); then
  echo "[FAIL] No HAP artifact found under entry/build." >&2
  exit 1
fi

unsigned_hap=""
signed_hap=""
for file in "${hap_files[@]}"; do
  if [[ -z "${unsigned_hap}" && "${file}" == *"-unsigned.hap" ]]; then
    unsigned_hap="${file}"
  fi
  if [[ -z "${signed_hap}" && "${file}" == *"-signed.hap" ]]; then
    signed_hap="${file}"
  fi
done

primary_hap="${hap_files[0]}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "primary_hap=${primary_hap}"
    echo "unsigned_hap=${unsigned_hap}"
    echo "signed_hap=${signed_hap}"
    echo "hap_count=${#hap_files[@]}"
  } >> "${GITHUB_OUTPUT}"
fi

echo "[INFO] Build completed. Found ${#hap_files[@]} HAP artifact(s)."
echo "[INFO] Primary HAP: ${primary_hap}"
