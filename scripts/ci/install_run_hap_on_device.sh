#!/usr/bin/env bash

set -euo pipefail

: "${HAP_FILE:?HAP_FILE is required}"
: "${APP_BUNDLE_NAME:?APP_BUNDLE_NAME is required}"
: "${APP_ABILITY_NAME:?APP_ABILITY_NAME is required}"
: "${APP_MODULE_NAME:?APP_MODULE_NAME is required}"

if ! command -v hdc >/dev/null 2>&1; then
  echo "[FAIL] hdc is required in PATH." >&2
  exit 1
fi

if [[ ! -f "${HAP_FILE}" ]]; then
  echo "[FAIL] HAP file not found: ${HAP_FILE}" >&2
  exit 1
fi

remote_path="${HDC_REMOTE_TMP_PATH:-data/local/tmp/$(basename "${HAP_FILE}")}"

echo "[INFO] Checking connected HarmonyOS devices..."
hdc list targets

echo "[INFO] Sending HAP to device: ${remote_path}"
hdc file send "${HAP_FILE}" "${remote_path}"

echo "[INFO] Installing HAP..."
hdc shell bm install -p "${remote_path}"

echo "[INFO] Starting ability..."
hdc shell aa start -a "${APP_ABILITY_NAME}" -b "${APP_BUNDLE_NAME}" -m "${APP_MODULE_NAME}"

echo "[INFO] Cleaning temporary package..."
hdc shell rm -rf "${remote_path}"

echo "[INFO] Device install/run completed."
