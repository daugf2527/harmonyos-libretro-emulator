# GreasyFork 脚本改造 ClawHub Skill 可行性总结（2026-03-23）

## 1. 结论（先给结论）
- 可行，但不能按 `Skill-only` 走 1:1 迁移。
- 推荐路线是 `Skill + Plugin` 联合改造，而不是“把 userscript 直接翻译成 SKILL.md”。
- 以工程可交付口径估算：
  - 仅 Skill 化可覆盖约 30%-50%（偏流程型、弱注入依赖脚本）。
  - Skill + Plugin 可覆盖约 70%-85%（含跨域、状态、工具能力扩展场景）。
  - 其余脚本应放弃迁移或仅做人工定制版。

## 2. 能力差异（为什么不能 1:1）
- Userscript 运行模型：浏览器注入执行，依赖 `@run-at`、`@grant`、`unsafeWindow`、`GM_*` 等能力。
- OpenClaw Skill 模型：`SKILL.md` 主要是“指导 Agent 何时、如何调用工具”。
- 当脚本依赖早期注入、页面上下文劫持、强页面时序绑定时，Skill 本体无法等价替代，需 Plugin 扩展工具或运行时能力。

## 3. 迁移分级（落地规则）
- A 类（可自动化）
  - 特征：DOM 操作/信息抽取/常规流程自动化。
  - 要求：无 `unsafeWindow`、无强依赖 `document-start`、无远程动态执行。
  - 方案：Skill 化，可进入自动发布候选池。
- B 类（半自动）
  - 特征：跨域请求、状态存储、外部服务依赖。
  - 方案：Skill + 轻服务或 Plugin；必须人工审批。
- C 类（高风险/强耦合）
  - 特征：依赖 `unsafeWindow`、注入时机严格、页面劫持/反检测逻辑明显。
  - 方案：Plugin 定制或放弃迁移，不进自动发布。

## 4. 必加硬闸门（否则上线风险过高）
- License Gate：无许可证或许可证不兼容直接 `block`。
- Security Gate：规则扫描 + AI 审计双引擎，冲突结果强制 `review`。
- Deterministic Gate：产物与依赖快照可复现，支持可验证回滚。
- Capacity Gate：候选量受人工审核能力约束，不能固定高吞吐硬推。
- Runtime Gate：上线后监控异常外联、警告率、隐藏率，触发模板族一键冻结。

## 5. 你当前参数建议（可直接作为初版）
- 每日候选量 `N`：先 80-120（稳定后再提升到 200）。
- Canary 数量：10（仅限低风险白名单站点）。
- 自动发布上限：仅 A 类中的低权限、无外联、无动态加载脚本。
- Review 占比阈值：20%-25%（超过暂停扩批）。
- 自动下线：采用复合阈值（警告率 + 隐藏率 + 异常外联）。

## 6. 对你“目标与边界”的逐条点评（犀利版）
- 1) GreasyFork 只作数据源：可行。问题在于“来源可信”不等于“内容可分发”，必须加 License Gate 与内容责任边界。
- 2) 不做原样搬运、做 Skill/Plugin 重构：方向正确。问题在于要定义“最小重构度”，否则只是改壳。
- 3) 只做高价值热门：正确。问题在于“热门”会把灰黑产脚本也推上来，热度不能直接当正向分。
- 4) 上架前规则+AI+测试+灰度：正确。问题在于缺少量化阈值与失败预算，容易沦为流程打卡。

## 7. 对你“六阶段主流程”的逐环节点评（逐段对照）
| 环节 | 可行性判断 | 你方案亮点 | 关键问题（必须补） | 建议硬修复 |
|---|---|---|---|---|
| Discover | 高 | API 化发现 + TopN 机制 | `N=200` 与人工审核产能不匹配；热度指标被滥用风险高 | 先用 80-120；加站点白名单和风险先验扣分 |
| Normalize | 高 | canonical schema + 追溯字段 | 仅靠代码 hash + 相似度，抗改壳/抗混淆不足 | 增加 AST 归一化指纹与依赖锁定摘要 |
| Static Scan | 中高 | 规则+AI 双引擎 | 没有误报/漏报指标；规则过审但 AI 高危仅转 review，缺少强制人工 SLA | 定义 precision/recall 目标；review 超时自动阻断发布 |
| Transform | 中 | A/B/C 分流合理 | A 类自动化边界仍过宽，DOM 脚本也可隐式追踪/外传 | A 类再细分为 A1(可自动发)/A2(需人审) |
| Test | 中 | 结构/行为/安全复测三层 | 缺少“行为等价”基线；只测触发词无法证明功能没跑偏 | 增加关键站点回放与前后差异快照 |
| Release | 中高 | Canary + 扩批 + 回滚思路 | 仅 `transform_version + source_hash` 回滚不够，可执行依赖会漂移 | 增加制品快照与依赖 lock，保证可复现回退 |

## 8. 你“异常处理方案”的薄弱点
- Discover 429/超时处理可行，但应加全局限速与站点级熔断，避免雪崩重试。
- Normalize 的人工补字段可行，但需要“补字段审计日志”，避免手工污染评分。
- 扫描冲突转 review 正确，但需定义“高风险冲突不得带条件放行”。
- Transform 二次再生后转人工合理，但要记录失败模式并反馈到提示词与模板库。
- 发布重试正确，但要幂等键（`source_hash + transform_version + target_slug`）防重复上架。
- 上架后暂停模板族正确，但应支持一键冻结“同作者/同依赖/同外联域名”关联集。

## 9. 你“关键控制点”的补强建议
- 高价值阈值：加入“风险预算”，热门但高风险直接降级到观察池，不进当天发布池。
- 重构度阈值：定义硬性清单（结构变更、依赖显式、风险声明、可观测埋点）缺一不可。
- 自动化边界：只允许 A1 自动发布（低权限、无外联、无动态加载、无追踪特征）。
- 商业化展示：显式区块还不够，需要强提示与用户可关闭开关，默认不隐式开启。

## 10. 你要先拍板的 5 个参数（最终建议）
- 每日候选量 N：先 80-120，连续两周稳定后再向 200 提升。
- Canary 数量：10（保留），但仅限低风险白名单站点。
- 自动发布上限：仅 A1，不是“所有 A 类”。
- Review 占比阈值：20%-25%（超过立即暂停扩批）。
- 自动下线阈值：复合触发（警告率 + 隐藏率 + 异常外联）而非单指标。

## 11. 对齐结论
- 你的方案不是“不可行”，而是“可行但当前风控规格不足以上生产强度”。
- 先补 License、可复现回滚、A 类细分和容量闸门，这套流程就能稳定跑起来。

## 12. 参考（外部依据）
- OpenClaw Creating Skills: https://docs.openclaw.ai/tools/creating-skills
- OpenClaw Skills: https://docs.openclaw.ai/tools/skills
- OpenClaw Tools & Plugins: https://docs.openclaw.ai/tools/index
- OpenClaw Plugins: https://docs.openclaw.ai/tools/plugin
- OpenClaw Plugin Manifest: https://docs.openclaw.ai/plugins/manifest
- Tampermonkey Documentation: https://www.tampermonkey.net/documentation.php
- Greasy Fork API subdomain announcement: https://greasyfork.org/ug/discussions/greasyfork/273741-new-subdomain-for-api-requests-api-greasyfork-org
- Greasy Fork API sample endpoint: https://api.greasyfork.org/en/scripts.json
