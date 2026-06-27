# AppGallery 上架闭环清单

更新时间：2026-06-27

## 当前结论

当前仓库距离“可提交 AppGallery 审核”仍有明确缺口，暂不应直接发版。最大阻塞项不是构建链路，而是版权/法务/素材/说明闭环未收口。

## P0 阻塞项

- 保持 `entry/src/main/resources/rawfile/roms/` 与商业风格封面资源不回归。
  - 本轮已从工作树移除 bundled ROM/镜像/压缩包与 `cover_*.png` 资源。
  - `scripts/ci/check_release_readiness.sh` 已作为回归守卫；新增同类资源前必须先完成授权与发布策略评审。
- 对外发布可访问的隐私政策。
  - 仓库内需要有最终文案源稿。
  - 商店后台需要能填写可访问 URL。
- 完成用户协议 / EULA。
  - 至少覆盖“仅提供前端壳”“不提供 ROM 下载”“用户自行保证内容使用权”“第三方 core 与内容来源免责声明”。
- 补齐最终应用元数据。
  - 名称、描述、图标、截图、版本亮点、支持平台、联系方式不能再使用占位值。

## P1 高优先级项

- 首次启动与 About 页增加更明确的信任说明。
  - 当前有本地帮助文案，但未形成完整隐私/授权闭环。
- 统一发布定位。
  - 当前仓库同时呈现“工程测试页”和“产品页”入口，发布版需要收敛到用户路径。
- 完成商店素材包。
  - 图标、启动图、手机截图、功能说明、更新说明、中英文文案。
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
- `entry/src/main/resources/*/element/string.json`: 已替换 `DrawingToXComponent` 等占位标签。
- `entry/src/main/ets/pages/AboutHelpPage.ets`: 有基础合规说明，但仍是本地帮助态，不是完整法律材料。
- `README.md` / `README.en.md`: 已明确商店版只接受用户导入内容与发布守卫边界。

## 执行顺序

1. 持续保持 bundled ROM / 封面资源不回归。
2. 定稿隐私政策、EULA、商店文案。
3. 收敛发布版入口与帮助说明。
4. 由用户执行真机构建、截图、后台配置和最终提交。

## 本轮已落地

- 新增 `scripts/ci/check_release_readiness.sh`。
- 在 PR / Release workflow 接入发布就绪守卫。
- 修正部分占位元数据与 README 发布边界描述。
- 新增 `docs/release/` 基础材料模板。

## 本轮未执行

- 未编译。
- 未真机验证。
- 未实际登录 AppGallery Connect 填报。
