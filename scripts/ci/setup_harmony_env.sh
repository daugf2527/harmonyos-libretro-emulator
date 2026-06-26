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

sdk_toolchains="${tool_home}/sdk/default/openharmony/toolchains"
if [[ ! -d "${sdk_toolchains}" ]]; then
  echo "[FAIL] HarmonyOS toolchains directory not found: ${sdk_toolchains}" >&2
  exit 1
fi

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

print_sdk_diagnostics() {
  local sdk_root="${tool_home}/sdk/default"
  local oh_root="${sdk_root}/openharmony"

  echo "[INFO] SDK diagnostics: sdk root = ${sdk_root}"
  if [[ -f "${sdk_root}/sdk-pkg.json" ]]; then
    echo "[INFO] sdk-pkg.json"
    cat "${sdk_root}/sdk-pkg.json"
  else
    echo "[WARN] sdk-pkg.json missing: ${sdk_root}/sdk-pkg.json"
  fi

  echo "[INFO] OpenHarmony component directories"
  find "${oh_root}" -maxdepth 1 -mindepth 1 -type d | sort || true

  local component
  for component in native ets js toolchains previewer; do
    local component_dir="${oh_root}/${component}"
    local manifest="${component_dir}/oh-uni-package.json"
    if [[ -d "${component_dir}" ]]; then
      echo "[INFO] Component ${component}: present"
      du -sh "${component_dir}" || true
      if [[ -f "${manifest}" ]]; then
        echo "[INFO] ${component} manifest"
        cat "${manifest}"
      else
        echo "[WARN] ${component} manifest missing: ${manifest}"
      fi
      echo "[INFO] ${component} sample files"
      find "${component_dir}" -maxdepth 2 -type f | sort | head -n 20 || true
    else
      echo "[WARN] Component ${component}: missing directory ${component_dir}"
    fi
  done
}

print_sdk_diagnostics

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
  echo "HARMONY_SDK_TOOLCHAINS=${sdk_toolchains}"
} >> "${GITHUB_ENV}"

{
  echo "${tool_home}/bin"
  echo "${sdk_toolchains}"
} >> "${GITHUB_PATH}"

if [[ -n "${node_home}" ]]; then
  echo "${node_home}" >> "${GITHUB_PATH}"
fi

echo "[INFO] HarmonyOS command line environment prepared."
