#!/usr/bin/env bash
# scripts/ci/check_arkts_codelinter.sh
#
# ArkTS 性能/规范静态检查(按需工具,非 quick_signals 常驻)— 补 .ets 的【性能/AST
# 规范】检查空白(cxx-build 只覆盖 C++;serena LSP/ast-grep 对 .ets 失效 —
# memory feedback_mcp_tools_fail_on_ets)。
#
# ⚠️ 能力边界(2026-06-08 实测,切勿当编译验证):
#   - codelinter 默认仅 @performance + @cross-device 规则集,【不抓】ArkTS 语法/类型
#     error(no-any / no-var / V1V2 误用等 correctness 规则全不跑)。
#   - 启用 @typescript-eslint/recommended 需项目根 code-linter.json5;但本地 CLI 实测
#     无法激活(单文件扫缺 hvigor 类型上下文,注入 `any` 探针 0 命中)。
#   - → ArkTS 编译/类型盲区仍【只能靠 hvigor(DevEco 复编)】,无轻量 CLI 替代。
#   - 本脚本补的是【性能反模式】维度(如 custom-component 滥用),不是编译/类型验证。
#
# CI 同跑 codelinter(harmonyos-*-ci.yml `codelinter -e error ... .`),同样仅
#   @performance 规则集 → CI 对 .ets correctness 亦零覆盖,靠后续 Build HAP 兜编译。
#
# 用法:
#   bash scripts/ci/check_arkts_codelinter.sh            # 全 ets 目录(~34s)
#   bash scripts/ci/check_arkts_codelinter.sh <f1.ets>…  # 指定文件(增量,~20s/文件)
#
# Exit:
#   0 = 0 个 error 级 finding(warn/suggestion 不 gate,只汇总)
#   1 = ≥1 个 error  /  2 = codelinter 不可用(SKIP 语义,调用方决定是否致命)
#
# 关键正确性点:codelinter `-e error` 在 warn-only 文件上仍返回 exit=1(实测),
#   故**绝不裸信 exit code** — 必须解析 JSON report 的 severity 统计 error 数。

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

SCAN_TARGET=("entry/src/main/ets")
[[ $# -gt 0 ]] && SCAN_TARGET=("$@")

# codelinter 经 DevEco command-line-tools 提供,不在 $PATH 时探测已知位置。
# wrapper(.bat)会自行注入 DEVECO_NODE_HOME / DEVECO_SDK_HOME。
find_codelinter() {
  if command -v codelinter >/dev/null 2>&1; then
    echo "codelinter"; return 0
  fi
  local candidates=(
    "/d/hongmeng/command-line-tools/bin/codelinter.bat"
    "D:/hongmeng/command-line-tools/bin/codelinter.bat"
    "${HARMONY_CLI_INSTALL_DIR:-}/command-line-tools/bin/codelinter.bat"
    "/c/command-line-tools/bin/codelinter.bat"
  )
  for p in "${candidates[@]}"; do
    [[ -n "${p}" && -x "${p}" ]] && { echo "${p}"; return 0; }
  done
  return 1
}

CODELINTER="$(find_codelinter)" || {
  echo "SKIP: codelinter 不可用(非 DevEco 环境 / command-line-tools 未装)"
  echo "  本地装法见 CLAUDE.md;CI 由 setup_harmony_env.sh 提供"
  exit 2
}

REPORT="$(mktemp -t cl-report-XXXXXX.json 2>/dev/null || echo "${ROOT_DIR}/.cl-report.json")"
trap 'rm -f "${REPORT}"' EXIT

echo "codelinter scope: ${SCAN_TARGET[*]}"

# Git Bash 下必须 cmd //c(双斜杠)调 .bat,否则 /c 被 MSYS 当 C:\ 路径转换、
# cmd 进交互态秒退只回显 banner(实测踩坑)。command -v 命中的真 codelinter 直调。
if [[ "${CODELINTER}" == *.bat ]]; then
  cmd //c "${CODELINTER}" -e error -f json -o "${REPORT}" "${SCAN_TARGET[@]}" >/dev/null 2>&1
else
  "${CODELINTER}" -e error -f json -o "${REPORT}" "${SCAN_TARGET[@]}" >/dev/null 2>&1
fi
# 不读 $? — codelinter `-e error` 对 warn-only 也 exit=1;以 JSON 解析为准。

if [[ ! -s "${REPORT}" ]]; then
  echo "PASS: 0 finding(codelinter 无输出报告 = 干净)"
  exit 0
fi

# 解析 JSON:统计 error / warn 数,打印 error 明细。纯 python3(项目既有依赖)。
python3 - "${REPORT}" << 'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print(f"WARN: 报告解析失败({e}) — 视为 SKIP"); sys.exit(2)
bs = chr(92)
errs, warns = [], 0
for f in data:
    name = f.get('filePath', '?').split(bs)[-1]
    for m in f.get('messages', []):
        if m.get('severity') == 'error':
            errs.append((name, m.get('line', '?'), m.get('rule', '?'), m.get('message', '')))
        elif m.get('severity') == 'warn':
            warns += 1
print(f"  errors={len(errs)}  warns={warns}(非 gate)")
for n, l, r, msg in errs[:30]:
    print(f"  ERROR {n}:{l} [{r}] {msg[:80]}")
if len(errs) > 30:
    print(f"  … 另有 {len(errs)-30} 条 error")
sys.exit(1 if errs else 0)
PYEOF
rc=$?

if [[ $rc -eq 0 ]]; then
  echo "PASS: 0 error 级 ArkTS finding"
elif [[ $rc -eq 1 ]]; then
  echo "FAIL: 存在 error 级 ArkTS finding(同 CI gate 口径)"
fi
exit $rc
