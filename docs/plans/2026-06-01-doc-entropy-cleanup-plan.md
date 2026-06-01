# 文档熵清理 — 归档清单

**创建**: 2026-06-01(主 Claude 接手产出,原后台 agent 卡在引用安全检查步,已停)
**用途**: 把 docs/ 的过程产物归档到 `docs/archive/`,降低文档/代码比(当前 116 md vs 205 源码 = 0.57)。
**纪律**: 只产清单 + 给 `git mv` 命令,**不自动执行**(AGENTS.md「代理不主动 commit」;git mv 需你授权)。

---

## ⚠️ 引用安全检查结论(归档前必读)

对每个候选 grep 了活文档(Roadmap/CLAUDE/AGENTS/tech-debt-tracker)。**3 个候选被引用,绝不能归档**——否则断链:

| 不能动的文件/目录 | 被谁引用 | 后果 |
|---|---|---|
| `docs/audit/audit-20260527-124137/`(7 文件) | tech-debt-tracker **D001–D005** | 5 条技术债证据链断裂 |
| `docs/gc-code-drift-20260528-155349.md` | tech-debt-tracker **D006** | D006 来源失链 |
| `docs/gc-code-drift-20260529-113336.md` | tech-debt-tracker **D007** | D007 来源失链 |

---

## 归档清单(44 文件,引用安全=0,可移)

### A 组 — audit 子目录里的 subagent 中间产物(36 文件 → `docs/archive/audit/`)

| 时间戳目录 | 文件数 | 内容 |
|---|---|---|
| `audit-20260525-140000/` | 17 | agent-T1~T6 / FIX-VERIFY-T* / VERIFIED / CORE-REVIEW / test.txt |
| `audit-20260527-090735/` | 5 | CORE-REVIEW / FIX-PLAN / agent-T3/T4 |
| `audit-20260527-090735-fixverify/` | 3 | fixverify 中间产物 |
| `audit-20260527-101206/` | 6 | agent-T7A/B/C / VERIFIED |
| `audit-20260529-115043/` | 5 | agent-T8 / DONE / VERIFIED |

> ⚠️ `audit-20260527-124137/` **不在此列**(被 D001–D005 引用,保留原位)

### B 组 — 根目录散落过程文档(8 文件 → `docs/archive/`)

| 文件 | 归档子目录 |
|---|---|
| `gc-drift-report-20260528-155347.md` | `archive/gc/` |
| `gc-drift-report-20260529-113208.md` | `archive/gc/` |
| `gc-four-way-audit-20260528-1745.md` | `archive/gc/` |
| `2026-05-04-next-session-handoff.md` | `archive/misc/` |
| `recent_issues_retrospective_2026-02.md` | `archive/misc/` |
| `2026-04-30-design-page-artifact-gap-audit.md` | `archive/misc/` |
| `2026-05-04-artifact-to-runtime-gap-audit.md` | `archive/misc/` |
| `2026-05-04-arkts-ui-static-scan.md` | `archive/misc/` |

---

## 保留原位清单(明确不动)

- **被引用**:`audit-20260527-124137/`、`gc-code-drift-20260528/29`(见上方安全检查)
- **里程碑审计活文档**:`docs/audit/m0-*.md`(其中 `m0-t29-verification-plan.md` 被 `verification-backlog-index.md` 引用)、`m2-t31-*`、`m4-t46-*`
- **正式规格/设计**:`docs/design/**`、`docs/2026-02-06-new-arch-technical-whitepaper.md`、白皮书类
- **活文档**:Roadmap / blockers / tech-debt-tracker / 问题.md / input-mapper / input_port_routing_guide

---

## 执行命令(待授权,勿自动跑)

```bash
mkdir -p docs/archive/audit docs/archive/gc docs/archive/misc
# A 组(5 个目录,排除 124137)
for d in audit-20260525-140000 audit-20260527-090735 audit-20260527-090735-fixverify \
         audit-20260527-101206 audit-20260529-115043; do
  git mv "docs/audit/$d" "docs/archive/audit/$d"
done
# B 组
git mv docs/gc-drift-report-20260528-155347.md docs/gc-drift-report-20260529-113208.md \
       docs/gc-four-way-audit-20260528-1745.md docs/archive/gc/
git mv docs/2026-05-04-next-session-handoff.md docs/recent_issues_retrospective_2026-02.md \
       docs/2026-04-30-design-page-artifact-gap-audit.md docs/2026-05-04-artifact-to-runtime-gap-audit.md \
       docs/2026-05-04-arkts-ui-static-scan.md docs/archive/misc/
```

## 预期效果

| 指标 | 前 | 后 |
|---|---|---|
| docs/ 总 md | 116 | 72 主线 + 44 archive |
| docs/audit 时间戳目录 | 6 | 1(124137 保留) |
| docs 根目录散落过程文档 | 8 | 0 |
| 文档/代码比(主线) | 0.57 | 0.36 |
