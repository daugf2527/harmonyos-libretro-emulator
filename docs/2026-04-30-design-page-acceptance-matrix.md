# 15 个设计页验收矩阵

> 日期：2026-04-30
> 范围：`docs/design/stitch-game-emulator-plan/_1` 到 `_15` 的原生 ArkTS 承载关系与后续视觉收口入口。
> 约束：本矩阵只记录当前仓库可见状态，不把“有相似 ETS 页面”写成“设计页已完成”。本轮未编译、未预览、未真机验证。
> 详细依据：见 `docs/2026-04-30-design-page-artifact-gap-audit.md`；2026-05-04 运行截图对照见 `docs/2026-05-04-artifact-to-runtime-gap-audit.md`。

## 状态规则

- `已完成` 只允许使用：`未开始` / `部分完成` / `视觉完成` / `运行态完成`。
- `screen.png` 用于静态视觉验收，`code.html` 用于结构、动效和状态参考。
- 后端、设备、云端或真实外设能力未接入时，`运行态缺口` 必须写明 `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`。
- 旧架构 `deprecated/legacy/` 不参与本矩阵。

## 验收矩阵

| 设计目录 | ETS 页面/组件 | 已完成 | 视觉缺口 | 交互缺口 | 运行态缺口 | 详细报告 | 下一步 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `docs/design/stitch-game-emulator-plan/_1` | `entry/src/main/ets/pages/CoreManagerPage.ets`、`entry/src/main/ets/common/LibretroCoreCatalog.ets` | 视觉完成 | 三段资源条、核心行、图标块、状态 badge、远端禁用标识、kernel log 密度和底部 System 高亮已按截图主态收口。 | 核心列表绑定本地 `LibretroCoreCatalog` 和 packaged lib 扫描；远端 UPDATE/INSTALL、固件库和在线诊断显示 `REMOTE_DISABLED` / `LOCAL_ONLY`。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：远端更新、固件库、真实内存指标未接入。 | `# _1 Core Manager` | 用户真机验收：本地 core 扫描、选中态、System 分组导航和日志文案。 |
| `docs/design/stitch-game-emulator-plan/_2` | `entry/src/main/ets/pages/MultiplayerInputPage.ets`、`entry/src/main/ets/common/RuntimeInputPortController.ets` | 视觉完成 | 2026-05-04 对照：运行截图 `08_input_netplay_center.png` 与设计同为 Input / Netplay Center 主入口；移动端密度更紧，远端房间缩略图未进入运行态，Netplay 未配置状态可见。 | 外设刷新继续走真实 `RuntimeInputPortController`，布局编辑跳真实 `InputLayoutPage`；Netplay 创建/加入保持禁用和 `NOT_CONFIGURED/OFFLINE`。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：已有主入口截图；蓝牙/USB、多端口输入、刷新后状态变化、布局编辑跳转和 Netplay 后端仍需设备/后端验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_2-multiplayer-input` | 补外设刷新、布局编辑跳转和真设备输入截图；不升级运行态完成。 |
| `docs/design/stitch-game-emulator-plan/_3` | `entry/src/main/ets/pages/ShaderPreviewPage.ets`、`entry/src/main/ets/common/RuntimeRenderSettingsController.ets` | 视觉完成 | 2026-05-04 对照：仅有 `code.html + screen.png + ETS` 静态证据；split preview、中央 handle、scanline/CRT、参数面板、slider 和 stats 浮层已静态对齐。 | RESET/SAVE_CFG 仅处理本地预览状态；GPU stats、shader runtime 和 GLES 应用链路明确 `NOT_CONFIGURED` / `PREVIEW_ONLY`。 | `缺最新截图` / `NOT_CONFIGURED` / `需真机验证`：不能确认当前运行页可见状态，真实 shader 列表、GPU stats、GLES 应用链路需设备验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_3-shader-preview` | 先补 Shader Preview 最新运行截图，再验收 Engine 高亮、split preview 和参数面板。 |
| `docs/design/stitch-game-emulator-plan/_4` | `entry/src/main/ets/pages/SettingsPage.ets` | 视觉完成 | 2026-05-04 对照：`09/10/11` 覆盖 Basic、Advanced、telemetry/audio；tab、section 绿条、slider、输入预览、telemetry 和 System 高亮可见，小差异在 Advanced 列表密度。 | 画面比例、scanline、音量仍是页面本地状态；高级项显示 `LOCAL_PRESET` / `PREVIEW_ONLY`，未伪装成已写入 runtime。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：已有三个设置态截图；渲染、音频、输入设置实际效果仍需运行验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_4-settings` | 补设置项实际生效验证和入口跳转截图；不升级运行态完成。 |
| `docs/design/stitch-game-emulator-plan/_5` | `entry/src/main/ets/pages/AboutHelpPage.ets` | 视觉完成 | hero、版本卡、帮助列表、右箭头、footer 品牌区和 System 导航高亮已按截图主态收口。 | 帮助项只做本地展开态；在线文档、反馈、法律链接未接真实入口，保持 `LOCAL_ONLY` / `NOT_CONFIGURED`。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：在线帮助/外链未接入，版本来源需验证。 | `# _5 About Help` | 用户真机验收：帮助展开、System 导航、版本/about 文案和底部 footer。 |
| `docs/design/stitch-game-emulator-plan/_6` | `entry/src/main/ets/pages/InputLayoutPage.ets`、`entry/src/main/ets/common/InputLayoutRepository.ets` | 视觉完成 | 编辑态 calibration header、暗化游戏画布、telemetry panel、肩键/方向键/动作键虚线选框、底部 floating dock 和右侧 markers 已按截图主态收口；仍需真机确认横竖屏遮挡。 | 选择、微调、重置、保存继续绑定本地 profile；未新增拖拽能力，逻辑画布 `position({ x: percent, y: percent })` 不作为截图绝对坐标。 | `LOCAL_ONLY` / `需真机验证`：布局持久化、触控热区、横竖屏与 runtime 使用需设备验证。 | `# _6 Input Layout` | 用户真机验收：编辑态进入/退出、选择按键、微调、保存、重置、runtime 触控热区使用。 |
| `docs/design/stitch-game-emulator-plan/_7` | `entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimeTopHudBar.ets`、`entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`、`entry/src/main/ets/components/RuntimeControlPanel.ets` | 视觉完成 | 2026-05-04 对照：仅有 `code.html + screen.png + ETS` 静态证据；top telemetry、movement 卡片、动作键 cluster、Quick Save、Select/Start 静态承载匹配。 | 虚拟按钮、暂停、隐藏手柄、即时存档/读档继续保持真实 input/runtime 语义；HTML 的 telemetry toggle 和 Quick Save 拖拽未伪造。 | `缺最新截图` / `NOT_CONFIGURED` / `需真机验证`：不能确认当前运行页可见状态，XComponent、帧率、音频、输入、震动和 core 运行需设备验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_7-runtime-controller` | 先补 Runtime Controller 最新运行截图，再验收方向键、A/B/X/Y、Select/Start、Quick Save、暂停和底部导航。 |
| `docs/design/stitch-game-emulator-plan/_8` | `entry/src/main/ets/pages/SaveStatePage.ets`、`entry/src/main/ets/common/SaveStateRepository.ets` | 视觉完成 | 顶部 header、三列本地归档摘要、swipe action、slot 缩略图、右侧时间/drag handle 和虚线 archive block 已按截图收口；仍需真机看滑动露出和长文件名。 | Quick save/load/delete/refresh 继续绑定当前 ROM 和 repository；云同步保持 `NOT_CONFIGURED`，不显示真实同步。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：云同步未配置，读写档和文件权限需设备验证。 | `# _8 Save State` | 用户真机验收：quick save、load、delete confirm、空列表和当前 ROM 过滤。 |
| `docs/design/stitch-game-emulator-plan/_9` | `entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimePauseOverlay.ets` | 视觉完成 | 顶部 telemetry bar、标题绿线、Resume CTA、四宫格、terminate 区域、右侧暗光和 telemetry 波形已按移动截图收口；仍需真机看小窗口滚动。 | Resume/stop 继续接真实 runtime；save/load/filter/input mapping 按现有能力状态处理，不伪造 native 能力。 | `NOT_CONFIGURED` / `需真机验证`：暂停、恢复、停止、快捷存读档和滤镜需运行验证。 | `# _9 Pause Overlay` | 用户真机验收：暂停、恢复、结束运行、四个快捷入口和小窗口滚动。 |
| `docs/design/stitch-game-emulator-plan/_10` | `entry/src/main/ets/pages/LibraryDetailPage.ets`、`entry/src/main/ets/components/LibraryDetailHeroPanel.ets`、`entry/src/main/ets/components/LibraryDetailInfoPanel.ets`、`entry/src/main/ets/components/LibraryLaunchOverlay.ets` | 视觉完成 | 顶部本地状态胶囊、hero 封面、绿色 CTA、metadata grid、telemetry 网格和 overview 灰底已按主体截图收口；仍需真机看封面裁切和长标题。 | Library -> Detail -> Runtime 参数、launch overlay、编辑元数据和 quick actions 继续按真实 route/repository 驱动。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：云存档未配置，启动和 runtime 写回需设备验证。 | `# _10 Library Detail` | 用户真机验收：库页进入详情、启动 overlay、编辑资料、存档入口和返回库页。 |
| `docs/design/stitch-game-emulator-plan/_11` | `entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets` | 视觉完成 | action sheet 宽度、暗化 blur、分割线、删除项红色层级和独立 Cancel 已按截图收紧；仍需真机看命中区域与背景模糊强度。 | 启动、详情、修改封面、删除存档、取消已保持分区点击；遮罩关闭仍需设备命中测试。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：修改封面若未接 picker/持久化需标未配置，菜单触发需设备验证。 | `# _11 Library Context Menu` | 用户真机验收：长按菜单、遮罩关闭、各操作入口。 |
| `docs/design/stitch-game-emulator-plan/_12` | `entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibrarySearchPanel.ets`、`entry/src/main/ets/components/LibraryGameSections.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets` | 视觉完成 | 2026-05-04 对照：`01/04/06/07` 覆盖空库、加载、搜索加载；搜索框、telemetry strip、chip、loader 和底部 Library 高亮可见，但有内容列表/context menu 缺截图。 | 搜索、平台过滤、卡片详情、长按菜单、刷新 toast 和底部 loader 继续由 repository/page state 驱动。 | `LOCAL_ONLY` / `需真机验证`：已有空库/加载/搜索加载证据；库索引、封面加载、完整列表、长按菜单、滚动和路由需设备验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_12-library-home` | 补有 ROM 列表、最近运行横卡、全部游戏行和 context menu 截图；不升级运行态完成。 |
| `docs/design/stitch-game-emulator-plan/_13` | `entry/src/main/ets/pages/ImportEntryPage.ets`、`entry/src/main/ets/components/ImportEmptyStateHero.ets` | 视觉完成 | 2026-05-04 对照：`03_import_authorization_required.png` 是授权 step 2，和 `_13/screen.png` 的导入空态 step 1 不同；`01/04` 只提供库页入口辅助证据。 | 导入按钮仍只做真实 picker/import service handoff；pre-picker 不再强化假网络在线状态。 | `LOCAL_ONLY` / `需真机验证`：已有授权态截图；step 1 导入空态、picker、任务页跳转和库刷新仍需设备验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_13-import-entry` | 补 `_13` step 1 导入空态和 picker/任务创建截图；不升级运行态完成。 |
| `docs/design/stitch-game-emulator-plan/_14` | `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`、`entry/src/main/ets/common/RomImportService.ets`、`entry/src/main/ets/common/ImportTaskBridge.ets` | 视觉完成 | 2026-05-04 对照：`05_import_task_empty_dialog.png` 是 `NO_PENDING_IMPORT_TASK` 空态，不是 `_14/screen.png` 的 importing 进度态；弹层宽度、dim/blur 层级可见。 | cancel/retry/return/conflict 处理继续来自真实 import task；无 pending task 时保持 `NO_PENDING_IMPORT_TASK` 诚实空态。 | `LOCAL_ONLY` / `需真机验证`：已有无任务空态截图；有 pending task、复制、冲突、取消、失败重试、成功和返回库页路径仍缺截图。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_14-import-task-overlay` | 补有 pending task 的 importing/conflict/success/failure 截图；不升级运行态完成。 |
| `docs/design/stitch-game-emulator-plan/_15` | `entry/src/main/ets/pages/OnboardingPage.ets` | 视觉完成 | 2026-05-04 对照：`02_boot_welcome_quick_start.png` 与设计同为欢迎 step 1；header、中心 icon、主 CTA、三列 status 可见，glass/scan-line 强度偏保守。 | 两步切换、授权入口和进入导入/库页路径继续绑定真实用户操作与 router。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：已有 step 1 截图；step 2 授权态、按钮点击、router 跳转和动画仍需设备验证。 | `docs/2026-05-04-artifact-to-runtime-gap-audit.md#_15-onboarding` | 补 step 2 授权态、进入导入/库页路由截图；不升级运行态完成。 |

## 视觉收口顺序

1. `Onboarding(_15)`
2. `Import(_13/_14)`
3. `Library(_12/_11)`
4. `Detail(_10)`
5. `Runtime/Pause/Input/Save(_7/_9/_6/_8/_2)`
6. `Settings/Core/Shader/About(_4/_1/_3/_5)`

## 当前路由注册核对

`entry/src/main/resources/base/profile/main_pages.json` 当前已注册以下矩阵相关页面：

- `pages/OnboardingPage`
- `pages/ImportEntryPage`
- `pages/LibraryPage`
- `pages/LibraryDetailPage`
- `pages/SettingsPage`
- `pages/SaveStatePage`
- `pages/MultiplayerInputPage`
- `pages/InputLayoutPage`
- `pages/CoreManagerPage`
- `pages/ShaderPreviewPage`
- `pages/AboutHelpPage`
- `pages/ImportTaskOverlayPage`
- `pages/LibretroGamePage`

## 后续执行口径

- 每完成一组视觉收口，必须同步更新本矩阵对应行，不允许只改代码不更新状态。
- 页面代码收口只处理对应组的布局、字号、间距、边框、blur、grid、scan-line、状态切换和按钮反馈。
- 不新增假运行态能力；例如 Netplay 没有后端时，UI 只能显示 `NOT_CONFIGURED`，不能写成真实可用房间服务。
- 每次改动后至少执行 `git diff --check` 和固定布局静态扫描；编译、预览、真机截图由用户执行。
