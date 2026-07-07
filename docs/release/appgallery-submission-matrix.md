# AppGallery 提交矩阵

更新时间：2026-07-07

本矩阵按华为 AppGallery / AppGallery Connect 上架流程拆解，记录本项目当前证据和缺口。状态分为：

- `READY`：仓库内材料已具备，提交前仍需最终复核。
- `BLOCKED`：当前不可提交。
- `USER_ACTION`：必须由具备账号、证书或真机的人执行。

| 上架项 | 当前项目证据 | 状态 | 下一步 |
| --- | --- | --- | --- |
| 开发者账号与实名认证 | 仓库无法验证账号状态 | USER_ACTION | 在 AppGallery Connect 完成开发者认证 |
| 创建 HarmonyOS 应用 | `AppScope/app.json5` 已有 `bundleName=io.carbonshade.emulator` | USER_ACTION | 在后台创建应用并确认包名 / APP ID |
| 应用名称 | `AppScope/resources/base/element/string.json` 为“碳影”；商店文案含 `碳影 / Carbon Shade` | READY | 后台名称与包内名称保持一致 |
| 图标与启动图 | `AppScope/resources/base/media/app_icon.png`、`entry/src/main/resources/base/media/icon.png`、`startIcon.png` 已存在但当前有 WIP | USER_ACTION | 用 release candidate 产物复核图标和启动图 |
| 应用简介与版本亮点 | `docs/release/store-listing-template.md` | READY | 粘贴到后台并按字数限制微调 |
| 应用截图 | `docs/release/release-candidate-runbook.md` 定义 8 张干净截图清单 | USER_ACTION | 使用同一个 release HAP 真机截图，至少满足后台最小张数要求 |
| 内容分级 | 仓库仅记录需配置，未能代替后台问卷 | USER_ACTION | 在 AppGallery Connect 按实际能力填写内容分级 |
| 隐私政策 URL | `docs/release/privacy-policy.md` 已有源稿；尚未公开托管 | BLOCKED | 发布公开 URL，并填写到后台 |
| 用户协议 / EULA | `docs/release/eula.md` 已有源稿；About 页已有摘要 | READY | 推荐同步公开 URL，或确认应用内可读版本满足审核要求 |
| 权限说明 | `module.json5` 只声明 `ohos.permission.VIBRATE`；隐私政策已说明用途 | READY | 后台权限用途说明与隐私政策一致 |
| 软件包上传 | release workflow 已有构建、HAP smoke check 和签名步骤 | USER_ACTION | 用真实签名材料产出 release HAP 并上传 |
| 发布 Profile / 签名 | `.github/workflows/harmonyos-release.yml` 需要 `HARMONY_SIGN_*` secrets | USER_ACTION | 配置 AppGallery Connect 对应证书、Profile 和 GitHub secrets |
| 合法性检测 / 上架自检 | `release-candidate-runbook.md` 已要求上传后检查 | USER_ACTION | 在后台读取自检结果并修复阻断项 |
| 版权与 IP | `check_release_readiness.sh` 阻止 bundled ROM 与 `cover_*.png` | BLOCKED | 移出当前 `rawfile/roms/` 与商业风格封面资源 |
| 不提供 ROM/BIOS 下载声明 | 商店文案、隐私政策、EULA、About 页均已声明 | READY | 截图和后台描述不得出现相反暗示 |
| 真机冒烟 | `release-candidate-runbook.md` 已列冒烟路径 | USER_ACTION | 记录机型、系统版本、HAP 版本、结果和截图 |

## 当前提交结论

当前项目不应直接提交审核。必须先处理两个 `BLOCKED` 项：

1. 移出发布包中的 `entry/src/main/resources/rawfile/roms/` 与 `entry/src/main/resources/base/media/cover_*.png`。
2. 将隐私政策发布到公网可访问 URL，并在 AppGallery Connect 填写。

随后再完成 `USER_ACTION` 项：后台创建/填报、签名 release HAP、上传软件包、采集干净截图、真机冒烟和上架自检。
