#!/usr/bin/env bash

set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "[FAIL] curl is required." >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "[FAIL] unzip is required." >&2
  exit 1
fi

: "${HARMONY_CLI_INSTALL_DIR:?HARMONY_CLI_INSTALL_DIR is required}"
: "${HARMONY_COMMANDLINE_TOOLS_URL:?HARMONY_COMMANDLINE_TOOLS_URL is required}"

mkdir -p "${HARMONY_CLI_INSTALL_DIR}"

archive_path="${HARMONY_CLI_INSTALL_DIR}/command-line-tools.zip"
tool_home="${HARMONY_CLI_INSTALL_DIR}/command-line-tools"
sdk_overlay_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/ci-assets/harmony-sdk-api26"
sdk_home="${tool_home}/sdk"
sdk_root="${sdk_home}/default"
openharmony_root="${sdk_root}/openharmony"
hms_root="${sdk_root}/hms"

if [[ ! -d "${tool_home}" ]]; then
  echo "[INFO] Downloading HarmonyOS Command Line Tools..."
  curl_args=(
    --fail
    --location
    --retry 3
    --connect-timeout 30
    --output "${archive_path}"
  )

  if [[ -n "${HARMONY_COMMANDLINE_TOOLS_AUTH_HEADER:-}" ]]; then
    curl_args+=(-H "${HARMONY_COMMANDLINE_TOOLS_AUTH_HEADER}")
  elif [[ -n "${HARMONY_COMMANDLINE_TOOLS_AUTH_TOKEN:-}" ]]; then
    auth_scheme="${HARMONY_COMMANDLINE_TOOLS_AUTH_SCHEME:-Bearer}"
    curl_args+=(-H "Authorization: ${auth_scheme} ${HARMONY_COMMANDLINE_TOOLS_AUTH_TOKEN}")
  elif [[ "${HARMONY_COMMANDLINE_TOOLS_URL}" =~ ^https://(api\.)?github\.com/ ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    # Fallback for private GitHub assets in same repository/org.
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  if [[ "${HARMONY_COMMANDLINE_TOOLS_URL}" =~ ^https://api\.github\.com/repos/.*/releases/assets/[0-9]+$ ]]; then
    curl_args+=(-H "Accept: application/octet-stream")
  elif [[ -n "${HARMONY_COMMANDLINE_TOOLS_AUTH_ACCEPT:-}" ]]; then
    curl_args+=(-H "Accept: ${HARMONY_COMMANDLINE_TOOLS_AUTH_ACCEPT}")
  fi

  curl "${curl_args[@]}" "${HARMONY_COMMANDLINE_TOOLS_URL}"

  if [[ -n "${HARMONY_COMMANDLINE_TOOLS_SHA256:-}" ]]; then
    echo "[INFO] Verifying command line tools checksum..."
    echo "${HARMONY_COMMANDLINE_TOOLS_SHA256}  ${archive_path}" | sha256sum -c -
  fi

  echo "[INFO] Extracting command line tools..."
  unzip -q "${archive_path}" -d "${HARMONY_CLI_INSTALL_DIR}"
fi

if [[ ! -x "${tool_home}/bin/hvigorw" ]]; then
  echo "[FAIL] hvigorw not found at ${tool_home}/bin/hvigorw" >&2
  exit 1
fi

sdk_toolchains="${openharmony_root}/toolchains"
if [[ ! -d "${sdk_toolchains}" ]]; then
  echo "[FAIL] HarmonyOS toolchains directory not found: ${sdk_toolchains}" >&2
  exit 1
fi

deveco_sdk_home="${sdk_home}"

if [[ -d "${sdk_overlay_dir}" ]]; then
  echo "[INFO] Applying API26 SDK metadata overlay..."
  mkdir -p "${tool_home}/sdk/default/openharmony/native"
  mkdir -p "${tool_home}/sdk/default/openharmony/ets"
  mkdir -p "${tool_home}/sdk/default/openharmony/js"
  mkdir -p "${tool_home}/sdk/default/openharmony/toolchains"
  mkdir -p "${tool_home}/sdk/default/openharmony/previewer"
  cp "${sdk_overlay_dir}/sdk-pkg.json" "${tool_home}/sdk/default/sdk-pkg.json"
  cp "${sdk_overlay_dir}/openharmony/native/oh-uni-package.json" "${tool_home}/sdk/default/openharmony/native/oh-uni-package.json"
  cp "${sdk_overlay_dir}/openharmony/ets/oh-uni-package.json" "${tool_home}/sdk/default/openharmony/ets/oh-uni-package.json"
  cp "${sdk_overlay_dir}/openharmony/js/oh-uni-package.json" "${tool_home}/sdk/default/openharmony/js/oh-uni-package.json"
  cp "${sdk_overlay_dir}/openharmony/toolchains/oh-uni-package.json" "${tool_home}/sdk/default/openharmony/toolchains/oh-uni-package.json"
  cp "${sdk_overlay_dir}/openharmony/previewer/oh-uni-package.json" "${tool_home}/sdk/default/openharmony/previewer/oh-uni-package.json"
fi

if [[ ! -d "${sdk_home}" ]]; then
  echo "[FAIL] HarmonyOS SDK home not found: ${sdk_home}" >&2
  exit 1
fi

if [[ ! -d "${sdk_root}" ]]; then
  echo "[FAIL] HarmonyOS SDK root not found: ${sdk_root}" >&2
  exit 1
fi

if [[ ! -d "${openharmony_root}" ]]; then
  echo "[FAIL] OpenHarmony SDK root not found: ${openharmony_root}" >&2
  exit 1
fi

if [[ ! -d "${hms_root}" ]]; then
  echo "[FAIL] HMS SDK root not found: ${hms_root}" >&2
  exit 1
fi

node_home=""
if [[ -d "${tool_home}/tool/node/bin" ]]; then
  node_home="${tool_home}/tool/node/bin"
elif [[ -d "${tool_home}/tool/node" ]]; then
  node_home="${tool_home}/tool/node"
fi

if [[ -z "${GITHUB_ENV:-}" || -z "${GITHUB_PATH:-}" ]]; then
  echo "[FAIL] GITHUB_ENV and GITHUB_PATH must be set in GitHub Actions." >&2
  exit 1
fi

{
  echo "HARMONY_COMMANDLINE_TOOLS_HOME=${tool_home}"
  echo "DEVECO_SDK_HOME=${deveco_sdk_home}"
  echo "HARMONY_SDK_DEFAULT_HOME=${sdk_root}"
  echo "HARMONY_SDK_TOOLCHAINS=${sdk_toolchains}"
} >> "${GITHUB_ENV}"

{
  echo "${tool_home}/bin"
  echo "${sdk_toolchains}"
} >> "${GITHUB_PATH}"

if [[ -n "${node_home}" ]]; then
  echo "${node_home}" >> "${GITHUB_PATH}"
fi

print_sdk_dir_summary() {
  local label="$1"
  local dir="$2"
  echo "[INFO] ${label}: ${dir}"
  if [[ ! -d "${dir}" ]]; then
    echo "[WARN] Directory missing: ${dir}"
    return
  fi
  find "${dir}" -maxdepth 1 -mindepth 1 | sort | sed 's#^#[INFO]   #'
}

print_sdk_file_probe() {
  local label="$1"
  local path="$2"
  if [[ -f "${path}" ]]; then
    echo "[INFO] ${label}: ${path}"
  else
    echo "[WARN] ${label} missing: ${path}"
  fi
}

echo "[INFO] HARMONY_COMMANDLINE_TOOLS_HOME=${tool_home}"
echo "[INFO] DEVECO_SDK_HOME=${deveco_sdk_home}"
echo "[INFO] HARMONY_SDK_DEFAULT_HOME=${sdk_root}"
echo "[INFO] HARMONY_SDK_TOOLCHAINS=${sdk_toolchains}"
echo "[INFO] PATH node_home=${node_home:-<not-found>}"
print_sdk_dir_summary "DEVECO_SDK_HOME entries" "${deveco_sdk_home}"
print_sdk_dir_summary "SDK root entries" "${sdk_root}"
print_sdk_dir_summary "OpenHarmony entries" "${openharmony_root}"
print_sdk_dir_summary "HMS entries" "${hms_root}"
print_sdk_dir_summary "HMS native entries" "${hms_root}/native"
print_sdk_dir_summary "HMS native sysroot entries" "${hms_root}/native/sysroot"
print_sdk_dir_summary "HMS toolchains entries" "${hms_root}/toolchains"
print_sdk_file_probe "SDK root package manifest" "${sdk_root}/sdk-pkg.json"
print_sdk_file_probe "OpenHarmony uni-package.json" "${openharmony_root}/uni-package.json"
print_sdk_file_probe "HMS uni-package.json" "${hms_root}/uni-package.json"
print_sdk_file_probe "OpenHarmony native manifest" "${openharmony_root}/native/oh-uni-package.json"
print_sdk_file_probe "OpenHarmony ets manifest" "${openharmony_root}/ets/oh-uni-package.json"
print_sdk_file_probe "OpenHarmony js manifest" "${openharmony_root}/js/oh-uni-package.json"
print_sdk_file_probe "OpenHarmony toolchains manifest" "${openharmony_root}/toolchains/oh-uni-package.json"
print_sdk_file_probe "OpenHarmony previewer manifest" "${openharmony_root}/previewer/oh-uni-package.json"
print_sdk_file_probe "HMS native manifest" "${hms_root}/native/uni-package.json"
print_sdk_file_probe "HMS ets manifest" "${hms_root}/ets/uni-package.json"
print_sdk_file_probe "HMS js manifest" "${hms_root}/js/uni-package.json"
print_sdk_file_probe "HMS toolchains manifest" "${hms_root}/toolchains/uni-package.json"
print_sdk_file_probe "HMS previewer manifest" "${hms_root}/previewer/uni-package.json"
print_sdk_file_probe "OpenHarmony package.json" "${openharmony_root}/package.json"
print_sdk_file_probe "HMS package.json" "${hms_root}/package.json"
print_sdk_file_probe "HMS native sysroot marker" "${hms_root}/native/sysroot/usr/include"

echo "[INFO] HarmonyOS command line environment prepared."
