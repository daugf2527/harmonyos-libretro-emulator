# AppGallery Release Candidate Runbook

更新时间：2026-07-07

本手册用于把一个干净 release candidate 推到可提交 AppGallery Connect 的状态。仓库代理只做静态准备；构建、签名、真机截图、真机冒烟由具备证书、账号和设备的人执行。

## 0. 前置阻断

- `entry/src/main/resources/rawfile/roms/` 不得进入发布包。
- `entry/src/main/resources/base/media/cover_*.png` 不得进入发布包，除非已有明确授权和发布评审记录。
- 截图、商店文案、隐私政策、用户协议不能展示或暗示提供商业 ROM、BIOS 或未授权内容下载。

## 1. 静态检查

在仓库根目录执行：

```bash
bash scripts/ci/check_release_readiness.sh
bash scripts/ci/check_repo_hygiene.sh
bash scripts/ci/check_regression_guards.sh
```

预期：三个命令均退出 0。若 `check_release_readiness.sh` 命中 ROM 或封面资源，先移出发布包再继续。

## 2. Release 构建与签名

GitHub release workflow 已包含 release 构建、HAP smoke check 和签名步骤。执行前确认 production environment 中已配置：

- `HARMONY_COMMANDLINE_TOOLS_URL`
- `HARMONY_COMMANDLINE_TOOLS_SHA256`
- `HARMONY_SIGN_KEYSTORE_B64`
- `HARMONY_SIGN_CERT_B64`
- `HARMONY_SIGN_PROFILE_B64`
- `HARMONY_SIGN_KEY_ALIAS`
- `HARMONY_SIGN_KEY_PWD`
- `HARMONY_SIGN_KEYSTORE_PWD`

触发方式：

```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
```

产物验收：

- workflow 成功结束。
- artifact 中包含 release HAP。
- HAP 内包含 `module.json`、`ets/modules.abc`、`libs/arm64-v8a/libentry.so`。
- 产物使用 AppGallery Connect 对应 profile 签名。

## 3. AppGallery Connect 填报

- 应用名：碳影 / Carbon Shade
- 开发者名称：Carbon Shade Project
- 分类：工具 / 娱乐，最终以后台可选类目为准
- 隐私政策 URL：填写公开托管后的 `docs/release/privacy-policy.md` 对应网页地址
- 用户协议：填写公开托管后的 `docs/release/eula.md` 地址，或确认应用内 About/Help 可读
- 支持入口：https://github.com/daugf2527/harmonyos-libretro-emulator/issues

## 4. 干净截图清单

截图必须来自同一个 release candidate 产物，不使用旧设计图或含未授权资源的开发截图。

- 首次启动 / Onboarding
- 导入入口
- 导入完成后的游戏库
- 游戏详情页
- 运行时画面 + 虚拟手柄
- 存档页
- 设置页
- 关于与帮助页

截图检查：

- 不展示未授权 ROM 名称、商业封面、商标或 BIOS 文件。
- 不出现 debug/test 页面入口。
- 应用名、图标、启动图与商店页一致。
- 关于页能看到隐私、用户协议、内容来源和支持入口说明。

## 5. 真机冒烟

使用 release HAP 在目标 HarmonyOS 手机执行：

- 首次启动：无崩溃，进入产品主路径。
- 文件导入：选择用户自有内容，导入完成后库页可见。
- 启动游戏：选择 core 与内容后进入运行页。
- 输入：虚拟按键有视觉反馈，游戏内输入生效。
- 暂停恢复：暂停页可打开，恢复后画面继续。
- 存读档：可创建存档并读取，失败时有可理解提示。
- 切后台恢复：切后台再返回，应用不崩溃，状态可恢复或有明确提示。
- 卸载重装：首次启动路径正常，不依赖旧本地数据。

## 6. 提交审核前记录

提交前在 release 记录中写明：

- HAP 版本号与 Git tag
- 静态检查命令输出
- 真机型号与 HarmonyOS 版本
- 冒烟结果
- 截图目录或附件位置
- 未覆盖风险，例如特定 core、特定机型或 Vulkan/GLES 差异
