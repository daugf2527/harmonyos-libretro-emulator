# GreasyFork -> ClawHub 开发说明 v1（范围 1-7）

更新时间：2026-03-23  
适用范围：仅覆盖你指定的 1-7（不含发布回滚细节、运行期告警体系、验收条目）

## 0. 设计前提（基于联网核对）
- GreasyFork API 已迁移到 `api.greasyfork.org`，`/en/scripts.json` 与 `by-site` 系列端点可用于发现与拉取元数据。
- GreasyFork 的脚本元信息关键项包括 `@match/@include/@exclude/@grant/@require/@resource/@license/@antifeature` 等，可用于标准化与风控特征提取。
- Tampermonkey 模型下 `@grant`、`@run-at`、`unsafeWindow`、`@require` 决定脚本权限与执行上下文，直接影响迁移分流。
- OpenClaw 中 Skill 是 `SKILL.md`（指导 Agent 用工具），Plugin 才是扩展运行能力与工具注册主体；Plugin 通过 `openclaw.plugin.json` 的 `id/configSchema/skills` 等字段声明。

说明：下面第 2-7 节中的阈值、权重、表结构是工程化建议，属于在官方能力边界上的实现推导，可直接作为 v1 起点。

## 1) Canonical Schema（字段定义）

### 1.1 顶层结构
```json
{
  "canonicalVersion": "1.0.0",
  "source": {},
  "popularity": {},
  "scriptMeta": {},
  "capabilities": {},
  "risk": {},
  "dedup": {},
  "trace": {}
}
```

### 1.2 字段表（必填/类型/说明）
| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| canonicalVersion | 是 | string | Canonical 版本号 |
| source.provider | 是 | enum | 固定 `greasyfork` |
| source.scriptId | 是 | int | GreasyFork 脚本 ID |
| source.scriptUrl | 是 | string | 脚本页面 URL |
| source.codeUrl | 是 | string | `.user.js` 下载地址 |
| source.locale | 否 | string | 来源语言 |
| source.license | 否 | string/null | 来源 license 文本 |
| source.version | 否 | string/null | 来源版本 |
| source.codeUpdatedAt | 是 | datetime | API `code_updated_at` |
| source.fetchedAt | 是 | datetime | 抓取时间 |
| source.sourceHash | 是 | string | 原始代码 `sha256` |
| popularity.dailyInstalls | 是 | int | API 字段 |
| popularity.totalInstalls | 是 | int | API 字段 |
| popularity.fanScore | 否 | float | API `fan_score` |
| popularity.goodRatings | 否 | int | API 字段 |
| popularity.okRatings | 否 | int | API 字段 |
| popularity.badRatings | 否 | int | API 字段 |
| scriptMeta.name | 是 | string | 名称 |
| scriptMeta.description | 是 | string | 描述 |
| scriptMeta.match | 否 | string[] | `@match` |
| scriptMeta.include | 否 | string[] | `@include` |
| scriptMeta.exclude | 否 | string[] | `@exclude` |
| scriptMeta.grants | 否 | string[] | `@grant` 列表 |
| scriptMeta.runAt | 否 | enum | `document-start/body/end/idle/context-menu` |
| scriptMeta.connect | 否 | string[] | `@connect` 域名 |
| scriptMeta.require | 否 | string[] | `@require` URL |
| scriptMeta.resource | 否 | string[] | `@resource` URL |
| scriptMeta.antifeature | 否 | string[] | `@antifeature` 声明 |
| capabilities.tags | 是 | string[] | 能力标签（如 `dom_automation`） |
| capabilities.outboundDomains | 否 | string[] | 代码静态提取到的外联域名 |
| capabilities.dynamicCode | 是 | bool | 是否含动态执行能力 |
| capabilities.unsafeWindowUsed | 是 | bool | 是否使用 `unsafeWindow` |
| risk.tags | 是 | string[] | 风险标签（规则+AI合并） |
| risk.ruleScore | 是 | int | 规则风险分 0-100 |
| risk.aiScore | 是 | int | AI 风险分 0-100 |
| risk.finalDecision | 是 | enum | `pass/review/block` |
| dedup.codeHash | 是 | string | 与 `sourceHash` 同源或归一化 hash |
| dedup.astFingerprint | 是 | string | AST 归一化指纹 |
| dedup.clusterId | 否 | string | 同质簇 ID |
| trace.ingestJobId | 是 | string | 任务链路 ID |
| trace.transformVersion | 否 | string | 改造器版本 |
| trace.ruleSetVersion | 是 | string | 规则集版本 |
| trace.aiModel | 是 | string | 审计模型标识 |

### 1.3 约束
- `sourceHash` 与 `astFingerprint` 同时存在，避免只靠文本 hash 被“改壳”绕过。
- `scriptMeta.match/include` 至少一个存在时才允许进入 Transform。
- `risk.finalDecision=block` 的记录不得进入自动改造队列。

## 2) 评分公式（用于 Discover TopN）

### 2.1 总分定义
`finalScore = 0.32*P + 0.18*Q + 0.15*F + 0.20*B - 0.10*R - 0.05*H`

所有分项归一化到 0-100。

### 2.2 分项计算
- P（热度）：
  - `P = 60 * min(1, log10(totalInstalls+1)/6) + 40 * min(1, dailyInstalls/300)`
- Q（口碑）：
  - `raw = fanScore`（缺失时用 Wilson 近似：good/totalRatings）
  - `volumeFactor = min(1, (good+ok+bad)/50)`
  - `Q = raw * volumeFactor`
- F（新鲜度）：
  - `days = now - codeUpdatedAt`
  - `F = 100 * exp(-days/120)`
- B（业务价值）：
  - 站点白名单匹配 + 场景复用度打分（0/40/70/100 四档）
- R（风险扣分）：
  - 使用规则初筛分（0-100，越高越危险）
- H（同质化扣分）：
  - 同簇数量越大扣分越高（最高 100）

### 2.3 入选阈值
- `finalScore >= 60` 才进候选池。
- `risk.ruleScore >= 70` 直接降级为 `review-only`（不进自动路径）。

## 3) A/B/C 分类判定规则（机器可执行）

### 3.1 规则优先级
1. 先判 C（高风险/强耦合）  
2. 再判 B（需要扩展能力）  
3. 其余判 A

### 3.2 判定逻辑
```text
if unsafeWindowUsed == true -> C
if runAt in [document-start] and contains hook patterns -> C
if dynamicCode == true and has network fetch/require of executable code -> C

else if grants contains GM_xmlhttpRequest or GM.xmlHttpRequest -> B
else if connect not empty -> B
else if grants intersects [GM_setValue, GM_getValue, GM_deleteValue] -> B
else if requires remote dependencies -> B

else -> A
```

### 3.3 A 类再细分（自动化边界）
- A1（可自动发布候选）：
  - 无 `unsafeWindow`
  - 无动态执行（`eval/new Function/字符串定时器`）
  - 无跨域能力（无 `GM_xmlhttpRequest`、`@connect` 为空）
  - `runAt` 不为 `document-start`
- A2（A 类但需人工）：
  - 满足 A，但命中弱风险规则（如第三方依赖较多、antifeature 声明不清晰）

## 4) 静态扫描规则清单（v1）

| 规则ID | 严重级别 | 检测点 | 处置 |
|---|---|---|---|
| RS001 | High | 混淆特征（高熵字符串+压缩器签名） | review |
| RS002 | Critical | `eval/new Function` | block |
| RS003 | Critical | `fetch/xhr` 拉 JS 后执行 | block |
| RS004 | High | 动态 `<script src>` 注入第三方域 | review |
| RS005 | High | `unsafeWindow` 直接读写敏感对象 | review/C |
| RS006 | Critical | `cookie/localStorage` + 网络发送联动 | block |
| RS007 | High | 可疑外联域名（非目标站点且无声明） | review |
| RS008 | Medium | 过度权限（grant 超过最小必要） | review |
| RS009 | Medium | `@require/@resource` 无 SRI 且来源不可信 | review |
| RS010 | Medium | 广告/追踪模式与 `@antifeature` 不一致 | review |

补充：
- 规则命中采用“最高严重级别优先”。
- `Critical` 默认 `block`，除非人工 override（必须留审计记录）。

## 5) AI 审计 I/O 协议（固定 JSON）

### 5.1 输入 Schema（简化）
```json
{
  "scriptId": 560618,
  "sourceHash": "sha256:...",
  "meta": {
    "grants": ["GM_setValue"],
    "runAt": "document-end",
    "connect": ["example.com"]
  },
  "ruleHits": [
    {"id": "RS008", "severity": "Medium", "evidence": "..."}
  ],
  "codeSnippet": "..."
}
```

### 5.2 输出 Schema（强约束）
```json
{
  "intentSummary": "string",
  "capabilityTags": ["dom_automation"],
  "riskScore": 0,
  "findings": [
    {
      "type": "over_permission",
      "severity": "medium",
      "evidence": "string",
      "confidence": 0.0
    }
  ],
  "decision": "pass|review|block",
  "decisionReason": "string",
  "needsHumanReview": true
}
```

### 5.3 决策融合
- `finalDecision = max(ruleDecision, aiDecision)`（严重度优先）。
- 任一方给 `block` -> 直接 `block`。
- 规则 `pass` + AI `review/block` -> 强制 `review/block`，不得自动放行。

## 6) 队列与状态机（Queue + State Machine）

### 6.1 队列划分
- `discover_queue`
- `normalize_queue`
- `scan_queue`
- `transform_queue`
- `test_queue`
- `publish_prep_queue`
- `manual_review_queue`
- `retry_queue`
- `dead_letter_queue`

### 6.2 状态流转
```text
DISCOVERED
 -> NORMALIZED
 -> RULE_SCANNED
 -> AI_SCANNED
 -> CLASSIFIED
 -> TRANSFORMED
 -> TESTED
 -> READY_FOR_RELEASE

终态:
 -> BLOCKED
 -> MANUAL_REVIEW
 -> FAILED_RETRYABLE
 -> FAILED_FATAL
```

### 6.3 幂等与重试
- 幂等键：`idempotencyKey = scriptId + ":" + sourceHash + ":" + transformVersion`
- 每阶段最大重试：3 次
- 退避策略：`2^n * 30s + jitter(0~10s)`
- 超限进入 `dead_letter_queue`，必须人工处理后才能回流

## 7) 存储设计（PostgreSQL v1）

### 7.1 表清单
- `gf_source_script`
- `canonical_script`
- `scan_rule_result`
- `scan_ai_result`
- `classification_result`
- `transform_job`
- `pipeline_task`
- `audit_event`

### 7.2 建议字段（关键表）
`gf_source_script`
- `id` (pk)
- `provider` (text, default `greasyfork`)
- `script_id` (int, unique with provider)
- `source_hash` (text)
- `version` (text)
- `license` (text)
- `raw_meta` (jsonb)
- `raw_code_ref` (text)
- `fetched_at` (timestamptz)

`canonical_script`
- `id` (pk)
- `source_script_fk` (fk)
- `canonical_version` (text)
- `doc` (jsonb)
- `ast_fingerprint` (text)
- `cluster_id` (text)
- `created_at` (timestamptz)

`pipeline_task`
- `id` (pk)
- `idempotency_key` (text, unique)
- `stage` (text)
- `status` (text)
- `retry_count` (int)
- `next_retry_at` (timestamptz)
- `last_error` (text)
- `updated_at` (timestamptz)

### 7.3 索引建议
- `gf_source_script(provider, script_id)` unique
- `gf_source_script(source_hash)` btree
- `canonical_script(ast_fingerprint)` btree
- `pipeline_task(status, stage, next_retry_at)` btree
- `scan_rule_result(script_fk, severity)` btree

### 7.4 审计要求
- 人工改判、人工补字段、人工回流任务必须写 `audit_event`。
- `audit_event` 最低字段：`actor`, `action`, `target_id`, `before`, `after`, `created_at`。

---

## 附：实现优先级（建议）
1. 先完成 `1 + 3 + 6`（字段、分类器、状态机），保证链路能跑。  
2. 再补 `4 + 5`（规则引擎与 AI 审计融合），提升风控质量。  
3. 最后完善 `2 + 7`（评分迭代与数据治理），优化吞吐与稳定性。  

## 参考来源（联网）
- OpenClaw Skills: https://docs.openclaw.ai/skills
- OpenClaw Creating Skills: https://docs.openclaw.ai/tools/creating-skills
- OpenClaw Plugin Manifest: https://docs.openclaw.ai/plugins/manifest
- OpenClaw ClawHub: https://docs.openclaw.ai/tools/clawhub
- OpenClaw Plugins（in-process/能力边界）: https://docs.openclaw.ai/plugin
- GreasyFork API 子域公告: https://greasyfork.org/en/discussions/greasyfork/273741-new-subdomain-for-api-requests-api-greasyfork-org
- GreasyFork Meta Keys: https://greasyfork.org/en/help/meta-keys
- GreasyFork External Scripts Policy: https://greasyfork.org/en/help/external-scripts
- Tampermonkey Documentation: https://www.tampermonkey.net/documentation.php
