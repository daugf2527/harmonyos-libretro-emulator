# 待验证清单总表(Verification Backlog Index)

**创建**: 2026-06-01
**用途**: 把散落各里程碑的真机验证项汇成一张索引——回答"该测什么 / 先测什么 / 照哪份文档 / 现在什么状态"。
**背景**: 2026-06-01 质检发现"验证赤字"——多个里程碑标 ✅ 已完成,实际只到"代码落地 + quick_signals PASS",真机这一环缺位(符合 AGENTS.md「代理不运行,用户自己执行」约定,故验证天然欠用户这一步)。

> 这是**活文档**:照单验证用,验证完更新「状态」列。**不要归档**。

---

## 优先级原则:按地基依赖排序

底层被越多上层依赖,越该先验证——地基若返工,垒在上面的全跟着塌。

```
M0 切换链路 ┐
M1 ROM-IO   �heavy地基(所有玩法都先过这两关) → P0 先测
M4/M5 出画  ┘上层(依赖 M0 起得来 + M1 加载得了) → P1 次测
M3 质量门禁  元能力(脚本未落地,先补落地再谈跑) → 见下
M2 可观测性  账本对齐问题,非验证问题 → 先改 Roadmap
```

---

## 验证总表

| 优先级 | 里程碑 | Roadmap 声称 | 真实成熟度 | 验证依据文档 | 真机状态 |
|---|---|---|---|---|---|
| **P0** | **M0 切换链路** | ✅ 已完成 | 代码落地 + plan 完整 | `docs/audit/m0-t29-verification-plan.md`(6 场景,PASS/FAIL + hilog 关键字齐全) | ⬜ 未跑 |
| **P0** | **M1 ROM-IO** | ✅ 已完成 | 代码落地 + 执行报告 | `docs/plans/2026-05-31-m1-rom-io-closure.md`(验收标准段) | ⬜ 未跑 |
| **P1** | **M5 GLES** | 进行中 | 代码落地 + checklist 详尽 | `docs/plans/2026-05-31-m5-gles-verification-checklist.md`(7 项初始化检查 + 代码行号) | ⬜ 未跑 |
| **P1** | **M5 Vulkan** | 进行中(兜底) | 代码落地 + plan 详尽 | `docs/plans/2026-05-31-m5-vulkan-verification-plan.md`(5 场景 transfer-only) | ⬜ 未跑 |
| **P1** | **M4 视频一致性** | ✅ 已完成 | 代码审计为主(无真机) | `docs/audit/m4-t46-video-callback-audit.md` | ⬜ 未跑(建议随 M5 一起测) |
| **门禁** | **M3 质量门禁** | ✅ 已完成 | ⚠️ **stub**:矩阵+脚本仅设计,`scripts/test/` 无 matrix/compat 落地 | `docs/design/m3-automated-test-design.md` / `m3-core-compatibility-matrix.md` | ⬜ 脚本未落地,无法跑 |
| **账本** | **M2 可观测性** | 未开始 | ⚠️ working tree 已在加 error code,且文档/代码 drift | `docs/reference/napi-error-code-mapping.md` | N/A(先对齐 Roadmap) |

---

## 建议验证批次(开真机时照批跑,不必逐个现想)

### 批次 1 — P0 地基(最先,一次开机跑完)
照 `m0-t29-verification-plan.md` 跑 M0 全 6 场景 + `m1-rom-io-closure.md` 验收段:
- 高频点击防抖 / 快速切不同游戏队列 / 切换中取消 / 损坏 ROM 失败恢复 / 长时压力
- need_fullpath / CUE 多文件 / 大 ROM 不阻塞 UI
- **若 M0 暴露问题 → 停止往 M6/M7 垒,先修地基**(这正是当前"优先级倒挂"的风险点)

### 批次 2 — P1 出画(地基绿了再测)
照 `m5-gles-verification-checklist.md` + `m5-vulkan-verification-plan.md`,M4 视频一致性合并进来:
- GLES 至少 1 核心稳定出画 / Vulkan transfer-only 兜底出画
- 切 core / 切缩放模式后画面比例正确(M4)
- 旋转 / 前后台切换 swapchain 重建

### 批次 3 — P2 叶子(攒着批量测,代价小)
M6 多核心/ROM 管理 + M7 折叠屏——非地基,晚测返工代价小。

---

## 需先处理的非真机项(收口阶段做,不占真机时间)

1. **M3 脚本落地**:Roadmap 改 ✅→⚠️(设计完成/脚本未落地);或补脚本再谈"完成"。
2. **M2 账本 + 技术债**:
   - Roadmap「未开始」与 working tree 实况不符,需对齐。
   - error code 硬编码 magic number(`8001`/`8002`)vs `napi-error-code-mapping.md` 的 145 行映射表脱节 → 建议抽常量到 `engine_napi_common.h`(已加 `feedback` 类技术债候选)。
3. **4 个 ✅ 措辞**:M0/M1/M4 + M3 的 ✅ 建议加注"(代码落地,真机验证 pending)",与 `Roadmap.md:10` 那行自己定的口径统一。

---

## 状态图例
⬜ 未跑 / 🟡 部分跑过 / ✅ 真机通过 / ❌ 真机暴露问题
