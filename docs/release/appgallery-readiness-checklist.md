# AppGallery 上架闭环清单

更新时间：2026-07-07

## 当前结论

当前仓库距离“可提交 AppGallery 审核”仍有明确缺口，暂不应直接发版。仓库内商店文案、隐私政策、EULA、About 页说明和 release candidate 执行手册已补强；剩余最大阻塞项是当前工作区仍存在发布包不可携带的 ROM/封面资源，以及外部隐私政策 URL、签名构建、真机截图和 AppGallery Connect 填报尚未完成。

## P0 阻塞项

- 保持 `entry/src/main/resources/rawfile/roms/` 与商业风格封面资源不回归。
  - 当前工作区存在 `entry/src/main/resources/rawfile/roms/` 与 `cover_*.png`，必须在 release candidate 前移出发布包。
  - `scripts/ci/check_release_readiness.sh` 已作为回归守卫；新增同类资源前必须先完成授权与发布策略评审。
- 对外发布可访问的隐私政策。
  - 仓库内已有发布文案源稿：`docs/release/privacy-policy.md`。
  - 商店后台需要能填写可访问 URL。
- 完成用户协议 / EULA。
  - 仓库内已有发布文案源稿：`docs/release/eula.md`。
  - About 页已加入应用内可读的 EULA / 隐私 / 内容来源摘要。
- 补齐最终应用元数据。
  - 名称、描述、版本亮点、支持入口已写入 `docs/release/store-listing-template.md`。
  - 图标和启动图需以当前 release candidate 资源为准复核。
  - 截图必须重新从干净 release candidate 真机获取。

## P1 高优先级项

- 首次启动与 About 页增加更明确的信任说明。
  - About 页已加入隐私、用户协议、内容来源和支持入口摘要；需真机确认展示效果。
- 统一发布定位。
  - 默认 Ability 已进入产品库页；发布 profile 不再注册旧入口选择页，旧兜底页也不再展示工程入口按钮。
- 完成商店素材包。
  - 图标、启动图、手机截图、功能说明、更新说明、中英文文案；文案已有，截图需重新采集。
- 建立兼容性声明。
  - 说明当前推荐 core/机型/输入方式与已知限制。

## P2 持续改进项

- 真机验收矩阵。
  - 导入、启动、暂停恢复、存档、切后台、旋转、异常恢复。
- 用户支持闭环。
  - FAQ、反馈渠道、问题分流模板。
- 内容策略。
  - 是否提供“无版权争议的公开域/自研示例内容”作为首启演示。

## 仓库内证据

- `scripts/ci/check_release_readiness.sh`: 阻止 `rawfile/roms` 与 `cover_*.png` 重新进入当前工作树。
- `entry/src/main/ets/common/RuntimeRomSourceScanner.ets`: 运行时 ROM 扫描已收敛到应用沙箱导入源。
- `entry/oh-package.json5`: 已补齐基础 `license` / `author` / description 元数据。
- `entry/src/main/resources/*/element/string.json`: 已替换旧工程模板占位标签。
- `AppScope/resources/base/element/string.json`: 已将发布展示名改为“碳影”。
- `entry/src/main/ets/pages/AboutHelpPage.ets`: 已加入隐私政策、用户协议、内容来源和支持入口摘要。
- `docs/release/release-candidate-runbook.md`: 已记录 release 构建签名、截图、真机冒烟和提交前记录步骤。
- `docs/release/appgallery-submission-matrix.md`: 已按 AppGallery 提交流程记录项目证据、阻断项和用户动作项。
- `scripts/ci/check_release_readiness.sh`: 已增强 AppScope 元数据、release 文档占位、隐私/EULA/商店文案覆盖项检查。
- `README.md` / `README.en.md`: 已明确商店版只接受用户导入内容与发布守卫边界。

## 执行顺序

1. 持续保持 bundled ROM / 封面资源不回归。
2. 定稿隐私政策、EULA、商店文案。
3. 真机复核发布版入口与帮助说明。
4. 由用户执行真机构建、截图、后台配置和最终提交。

## 本轮已落地

- 新增 `scripts/ci/check_release_readiness.sh`。
- 在 PR / Release workflow 接入发布就绪守卫。
- 修正部分占位元数据与 README 发布边界描述。
- 新增 `docs/release/` 基础材料模板。
- 修正 AppScope 发布展示名。
- 补齐商店文案、版本亮点、支持入口、隐私政策和 EULA 联系方式。
- About 页加入应用内法律与支持说明。
- 新增 release candidate 执行手册。
- 新增 AppGallery 提交矩阵。
- 增强 release readiness 守卫覆盖更多上架材料缺口。
- 发布 profile 移除旧入口选择页，未引用的测试 profile 已删除。
- base ability label 已与 AppScope 统一为“碳影”，英文名保留在 en_US 与商店英文文案中。
- CoreManager 页用户可见“测试/native”措辞已收敛为“核心可用性检查”。

## 本轮未执行

- 未编译。
- 未真机验证。
- 未实际登录 AppGallery Connect 填报。
- 未发布隐私政策 / EULA 的公网 URL。
