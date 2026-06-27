# Runtime Screenshots 2026-05-04

> 日期：2026-05-04
> 范围：本目录保存本轮运行截图 / 验收截图，用于辅助页面状态核对。
> 边界：本索引不替代 `docs/2026-04-30-design-page-acceptance-matrix.md`；设计完成度仍以 15 个设计页验收矩阵和后续 artifact-to-artifact 对照为准。

这一目录收纳 2026-05-04 的运行截图索引和对应截图文件。

用途：
- 作为设计页验收、运行态快照和差异分析的证据归档。
- 避免将截图资产长期暴露在仓库根目录。

## 截图清单

| 文件名 | 对应页面 / 状态 | 关联设计目录 | 验收用途 |
| --- | --- | --- | --- |
| `01_library_empty_import.png` | `LibraryPage` 空库导入入口态 | `_12 Library Home` / `_13 Import Entry` | 核对库页空态、导入 CTA、底部导航与 Import 链路入口。 |
| `02_boot_welcome_quick_start.png` | `OnboardingPage` 首启欢迎 / quick start 态 | `_15 Onboarding` | 核对首启引导主视觉、状态卡、主按钮和进入导入 / 库页的入口层级。 |
| `03_import_authorization_required.png` | `ImportEntryPage` 导入授权 / 本地文件选择前状态 | `_13 Import Entry` | 核对导入页授权提示、空态 hero、`LOCAL_ONLY` 口径和 picker 入口。 |
| `04_library_empty_import_alt.png` | `LibraryPage` 空库导入入口替代截图 | `_12 Library Home` / `_13 Import Entry` | 作为空库导入态复核图，辅助确认同一流程不同截图下布局稳定性。 |
| `05_import_task_empty_dialog.png` | `ImportTaskOverlayPage` 无 pending task 空任务弹层 | `_14 Import Task Overlay` | 核对 `NO_PENDING_IMPORT_TASK` 诚实空态、弹层宽度、背景 dim 和返回路径。 |
| `06_library_loading_assets.png` | `LibraryPage` 库资源加载 / 刷新状态 | `_12 Library Home` | 核对库页 telemetry、加载提示、内容区密度和底部 loader。 |
| `07_library_search_snes_loading.png` | `LibraryPage` 搜索 SNES / 加载过滤状态 | `_12 Library Home` | 核对搜索框、平台过滤、搜索结果加载与列表区域稳定性。 |
| `08_input_netplay_center.png` | `MultiplayerInputPage` Input / Netplay Center 主入口 | `_2 Multiplayer Input` | 核对输入端口、Netplay 未配置态、输入日志、布局编辑入口和底部 Input 高亮。 |
| `09_system_basic_settings.png` | `SettingsPage` Basic 设置页 | `_4 Settings` | 核对基础设置 tab、section、slider、输入设备预览和 System 分组导航。 |
| `10_system_advanced_settings.png` | `SettingsPage` Advanced 设置页 | `_4 Settings` | 核对高级设置 tab、导航项、未配置能力标识和页面滚动密度。 |
| `11_system_telemetry_audio.png` | `SettingsPage` telemetry / audio 相关状态 | `_4 Settings` | 核对 telemetry 柱状图、音频设置展示和 System 页面状态切换。 |

## 使用口径

- 本目录截图来自 2026-05-04 的运行态 / 验收态快照，只能证明当时截图中的页面状态可见。
- 如果截图与设计矩阵冲突，优先回到 `docs/design/stitch-game-emulator-plan/_N/screen.png`、`code.html` 和当前 ETS 承载页逐项对照。
- 后续新增截图时，按文件名顺序追加本表，并写清页面、状态、设计目录和验收用途。
- 本轮未编译、未真机验证；截图索引只做静态归档。
