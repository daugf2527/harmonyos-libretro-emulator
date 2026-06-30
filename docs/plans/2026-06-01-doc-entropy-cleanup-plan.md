# 文档熵清理 — 归档清单

**创建**: 2026-06-01(主 Claude 接手产出,原后台 agent 卡在引用安全检查步,已停)
**用途**: 把 docs/ 的过程产物归档到 `docs/archive/`,降低文档/代码比(当前 116 md vs 205 源码 = 0.57)。
**状态**: 已执行；本页保留为归档决策记录，避免后续重复判断。

---

## ⚠️ 引用安全检查结论(归档前必读)

对每个候选 grep 了活文档(Roadmap/CLAUDE/AGENTS/tech-debt-tracker)。**3 个候选被引用,绝不能归档**——否则断链:

| 不能动的文件/目录 | 被谁引用 | 后果 |
|---|---|---|
| `docs/audit/audit-20260527-124137/`(7 文件) | tech-debt-tracker **D001–D005** | 5 条技术债证据链断裂 |
| `docs/archive/gc/code/gc-code-drift-20260528-155349.md` | tech-debt-tracker **D006** | D006 来源失链 |
| `docs/archive/gc/code/gc-code-drift-20260529-113336.md` | tech-debt-tracker **D007** | D007 来源失链 |

---

## 已清理对象(本页记录范围)

### A 组 — 已删除的 audit 中间产物目录

| 时间戳目录 | 文件数 | 内容 |
|---|---|---|
| `audit-20260525-140000/` | 17 | agent-T1~T6 / FIX-VERIFY-T* / VERIFIED / CORE-REVIEW / test.txt |
| `audit-20260527-090735/` | 5 | CORE-REVIEW / FIX-PLAN / agent-T3/T4 |
| `audit-20260527-090735-fixverify/` | 3 | fixverify 中间产物 |
| `audit-20260527-101206/` | 6 | agent-T7A/B/C / VERIFIED |
| `audit-20260529-115043/` | 5 | agent-T8 / DONE / VERIFIED |

> 当前仅保留 `docs/audit/audit-20260527-124137/`，因为它仍被 tech-debt-tracker 的 D001–D005 直接引用。

### B 组 — 已保留的 gc drift 证据

| 文件 | 保留原因 |
|---|---|
| `docs/archive/gc/code/gc-code-drift-20260528-155349.md` | `tech-debt-tracker.md` D006 证据链 |
| `docs/archive/gc/code/gc-code-drift-20260529-113336.md` | `tech-debt-tracker.md` D007 证据链 |

---

## 当前保留边界

- **被引用**:`docs/audit/audit-20260527-124137/`、`docs/archive/gc/code/gc-code-drift-20260528-155349.md`、`docs/archive/gc/code/gc-code-drift-20260529-113336.md`
- **里程碑审计活文档**:`docs/audit/m0-*.md`(其中 `m0-t29-verification-plan.md` 被 `verification-backlog-index.md` 引用)、`m2-t31-*`、`m4-t46-*`
- **正式规格/设计**:`docs/design/**`、`docs/2026-02-06-new-arch-technical-whitepaper.md`、白皮书类
- **活文档**:Roadmap / blockers / tech-debt-tracker / docs/reference/known-issues.md / input-mapper / input_port_routing_guide

---

## 清理后结果

| 指标 | 前 | 后 |
|---|---|---|
| docs/archive/audit 时间戳目录 | 6 | 仅保留被引用的 `audit-20260527-124137/` |
| docs/archive/gc/code drift 报告 | 25 | 仅保留 D006/D007 证据两份 |
| legacy 示例入口 | `deprecated/legacy/entry/` | `deprecated/legacy/archive/entry/` |
