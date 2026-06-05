#!/usr/bin/env bash
# scripts/test/check_core_compatibility.sh
#
# M3 Layer 1 — 生成核心兼容性测试清单 build/test-manifest.json。
# 扫描已编译的 libretro 核心 (.so) 与测试 ROM，产出供 Layer 2 (ArkTS 真机
# CoreCompatibilityTest) 消费的清单。设计见 docs/design/m3-automated-test-design.md。
#
# Usage:
#   bash scripts/test/check_core_compatibility.sh
#
# Exit code:
#   0 = 清单生成成功（核心/ROM 目录不存在时输出空清单，仍 0，不阻塞 CI/quick_signals）
#   1 = 写入失败等硬错误
#
# 与设计文档的差异（实物核对 2026-06-05）：
#   - .so 命名实际为 *_libretro.ohos-arm64.so（HarmonyOS 产物后缀），非通用 *_libretro.so
#   - ROM 扩展名白名单取自 entry/src/main/ets/pages/TestGambatte.ets 的 coreId→extensions 映射并集
#   - JSON 用逐行 printf 构建，无 jq 依赖（与项目其它脚本一致）

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

# === 路径常量 ===
CORES_DIR="entry/build/default/intermediates/libs/default/arm64"
ROMS_DIR="entry/src/main/resources/rawfile/roms"
OUTPUT_DIR="build"
OUTPUT_JSON="${OUTPUT_DIR}/test-manifest.json"

# === ROM 扩展名白名单（TestGambatte.ets coreId→extensions 并集，小写）===
# 排除 download_roms.sh / README.md 等非 ROM 文件。
ROM_EXTS="gb gbc gba dmg nes fds unf unif smc sfc swc fig bs st gd3 gd7 dx2 bsx \
md mdx smd gen sms gg sg bms 68k sgd chd m3u cue iso agb toc ccd pbp nds ids dsi \
ngp ngc ngpc npc zip 7z dsk sna kcr hvf cmd int"

is_rom_file() {
  local name_lower
  name_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  local ext="${name_lower##*.}"
  # 无扩展名（如 mrboom 的 .desktop 之外不收）直接否
  [[ "${ext}" == "${name_lower}" ]] && return 1
  local e
  for e in ${ROM_EXTS}; do
    [[ "${ext}" == "${e}" ]] && return 0
  done
  return 1
}

# === 步骤 1: 扫描核心 .so ===
CORE_FILES=()
if [[ -d "${CORES_DIR}" ]]; then
  while IFS= read -r f; do
    [[ -n "${f}" ]] && CORE_FILES+=("${f}")
  done < <(find "${CORES_DIR}" -maxdepth 1 -name "*_libretro.ohos-arm64.so" -type f 2>/dev/null | sort)
fi
echo "[M3] cores: ${#CORE_FILES[@]} (dir: ${CORES_DIR})"

# === 步骤 2: 扫描 ROM ===
ROM_FILES=()
if [[ -d "${ROMS_DIR}" ]]; then
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    is_rom_file "$(basename "${f}")" && ROM_FILES+=("${f}")
  done < <(find "${ROMS_DIR}" -type f 2>/dev/null | sort)
fi
echo "[M3] roms: ${#ROM_FILES[@]} (dir: ${ROMS_DIR})"

# === 步骤 3: 生成 test-manifest.json（逐行 printf，避免 heredoc 变量展开坑）===
mkdir -p "${OUTPUT_DIR}" || { echo "[M3] FAIL: cannot mkdir ${OUTPUT_DIR}"; exit 1; }

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

{
  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "coreCount": %d,\n' "${#CORE_FILES[@]}"
  printf '  "romCount": %d,\n' "${#ROM_FILES[@]}"
  printf '  "cores": [\n'
  for i in "${!CORE_FILES[@]}"; do
    base="$(basename "${CORE_FILES[$i]}")"
    # coreId = 去掉 _libretro.ohos-arm64.so 后缀
    core_id="${base%_libretro.ohos-arm64.so}"
    printf '    {"coreId": "%s", "file": "%s"}' "$(json_escape "${core_id}")" "$(json_escape "${base}")"
    [[ $i -lt $((${#CORE_FILES[@]} - 1)) ]] && printf ','
    printf '\n'
  done
  printf '  ],\n'
  printf '  "roms": [\n'
  for i in "${!ROM_FILES[@]}"; do
    base="$(basename "${ROM_FILES[$i]}")"
    rel="${ROM_FILES[$i]#"${ROMS_DIR}"/}"
    printf '    {"file": "%s", "path": "roms/%s"}' "$(json_escape "${base}")" "$(json_escape "${rel}")"
    [[ $i -lt $((${#ROM_FILES[@]} - 1)) ]] && printf ','
    printf '\n'
  done
  printf '  ]\n'
  printf '}\n'
} > "${OUTPUT_JSON}" || { echo "[M3] FAIL: cannot write ${OUTPUT_JSON}"; exit 1; }

echo "[M3] manifest written: ${OUTPUT_JSON} ($((${#CORE_FILES[@]} + ${#ROM_FILES[@]})) entries)"
