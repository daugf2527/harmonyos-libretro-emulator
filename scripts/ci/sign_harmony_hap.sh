#!/usr/bin/env bash

set -euo pipefail

: "${HAP_SIGN_TOOL_JAR:?HAP_SIGN_TOOL_JAR is required}"
: "${UNSIGNED_HAP:?UNSIGNED_HAP is required}"
: "${SIGNED_HAP_OUTPUT:?SIGNED_HAP_OUTPUT is required}"
: "${SIGN_KEY_ALIAS:?SIGN_KEY_ALIAS is required}"
: "${SIGN_APP_CERT_FILE:?SIGN_APP_CERT_FILE is required}"
: "${SIGN_PROFILE_FILE:?SIGN_PROFILE_FILE is required}"
: "${SIGN_KEYSTORE_FILE:?SIGN_KEYSTORE_FILE is required}"
: "${SIGN_KEY_PWD:?SIGN_KEY_PWD is required}"
: "${SIGN_KEYSTORE_PWD:?SIGN_KEYSTORE_PWD is required}"

if [[ ! -f "${HAP_SIGN_TOOL_JAR}" ]]; then
  echo "[FAIL] hap-sign-tool.jar not found: ${HAP_SIGN_TOOL_JAR}" >&2
  exit 1
fi

if [[ ! -f "${UNSIGNED_HAP}" ]]; then
  echo "[FAIL] unsigned HAP not found: ${UNSIGNED_HAP}" >&2
  exit 1
fi

mkdir -p "$(dirname "${SIGNED_HAP_OUTPUT}")"

echo "[INFO] Signing HAP..."
java -jar "${HAP_SIGN_TOOL_JAR}" sign-app \
  -keyAlias "${SIGN_KEY_ALIAS}" \
  -signAlg "SHA256withECDSA" \
  -mode "localSign" \
  -appCertFile "${SIGN_APP_CERT_FILE}" \
  -profileFile "${SIGN_PROFILE_FILE}" \
  -inFile "${UNSIGNED_HAP}" \
  -keystoreFile "${SIGN_KEYSTORE_FILE}" \
  -outFile "${SIGNED_HAP_OUTPUT}" \
  -keyPwd "${SIGN_KEY_PWD}" \
  -keystorePwd "${SIGN_KEYSTORE_PWD}"

if [[ ! -f "${SIGNED_HAP_OUTPUT}" ]]; then
  echo "[FAIL] signing did not generate expected output: ${SIGNED_HAP_OUTPUT}" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "signed_hap=${SIGNED_HAP_OUTPUT}" >> "${GITHUB_OUTPUT}"
fi

echo "[INFO] Signing completed: ${SIGNED_HAP_OUTPUT}"
