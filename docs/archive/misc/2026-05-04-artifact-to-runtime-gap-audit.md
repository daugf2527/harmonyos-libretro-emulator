# `_2/_3/_4/_7/_12/_13/_14/_15` Artifact-to-Runtime Gap Audit

> 日期：2026-05-04
> 范围：`docs/design/stitch-game-emulator-plan/_2/_3/_4/_7/_12/_13/_14/_15`。
> 方法：对照 `code.html`、`screen.png`、`docs/verification/runtime-screenshots-2026-05-04/README.md` 中登记的最新运行截图，以及当前 ETS 承载页/组件。
> 边界：audit-only；本轮不改 ArkTS；未编译、未预览、未真机。`_3` 和 `_7` 缺 2026-05-04 最新运行截图，运行态结论只能标缺证据。

## Evidence Manifest

| 设计目录 | 设计资产 | 最新截图 | ETS 承载 |
| --- | --- | --- | --- |
| `_15 Onboarding` | `docs/design/stitch-game-emulator-plan/_15/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/02_boot_welcome_quick_start.png` | `entry/src/main/ets/pages/OnboardingPage.ets` |
| `_13 Import Entry` | `docs/design/stitch-game-emulator-plan/_13/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/03_import_authorization_required.png`；`01/04` 作为库页空态入口辅助证据 | `entry/src/main/ets/pages/ImportEntryPage.ets`、`entry/src/main/ets/components/ImportEmptyStateHero.ets` |
| `_14 Import Task Overlay` | `docs/design/stitch-game-emulator-plan/_14/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/05_import_task_empty_dialog.png` | `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`、`entry/src/main/ets/common/RomImportService.ets`、`entry/src/main/ets/common/ImportTaskBridge.ets` |
| `_12 Library Home` | `docs/design/stitch-game-emulator-plan/_12/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/01_library_empty_import.png`、`04_library_empty_import_alt.png`、`06_library_loading_assets.png`、`07_library_search_snes_loading.png` | `entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibrarySearchPanel.ets`、`entry/src/main/ets/components/LibraryGameSections.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets` |
| `_2 Multiplayer Input` | `docs/design/stitch-game-emulator-plan/_2/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/08_input_netplay_center.png` | `entry/src/main/ets/pages/MultiplayerInputPage.ets`、`entry/src/main/ets/common/RuntimeInputPortController.ets` |
| `_7 Runtime Controller` | `docs/design/stitch-game-emulator-plan/_7/code.html`、`screen.png` | 缺最新截图 | `entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimeTopHudBar.ets`、`entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`、`entry/src/main/ets/components/RuntimeControlPanel.ets` |
| `_4 Settings` | `docs/design/stitch-game-emulator-plan/_4/code.html`、`screen.png` | `docs/verification/runtime-screenshots-2026-05-04/09_system_basic_settings.png`、`10_system_advanced_settings.png`、`11_system_telemetry_audio.png` | `entry/src/main/ets/pages/SettingsPage.ets` |
| `_3 Shader Preview` | `docs/design/stitch-game-emulator-plan/_3/code.html`、`screen.png` | 缺最新截图 | `entry/src/main/ets/pages/ShaderPreviewPage.ets`、`entry/src/main/ets/common/RuntimeRenderSettingsController.ets` |

## Overall Findings

- P0：未发现错页、主入口缺失或运行截图显示页面完全不可用的证据。
- P1：`_13` 最新截图停在授权 step 2，和 `_13/screen.png` 的导入空态 step 1 不同；当前只能证明导入链路存在，不能证明 step 1/step 2 的完整视觉都已运行截图覆盖。
- P1：`_14` 最新截图是 `NO_PENDING_IMPORT_TASK` 空任务弹层，不是 `_14/screen.png` 的 importing 进度态；有 pending task、冲突、失败、成功态仍缺运行截图。
- P1：`_3`、`_7` 缺最新运行截图，不能把静态设计对照升级为运行态完成。
- P2：`_12` 运行截图覆盖空库、加载、搜索加载态，但没有覆盖有封面游戏列表和 context menu；列表封面、长按菜单、扫描动效仍是待截图证据。
- 细节口径：本报告将 `screen.png` 视为“某状态的静态最终态”，将 `code.html` 视为“结构/动效参考”，将最新截图视为“当前运行态快照”。如果三者不是同一个状态，只能标“状态未同态覆盖”，不能写成视觉完成度被运行态证明。

## Deep-Dive Checklist

| 设计目录 | 同态覆盖 | 结构覆盖 | 视觉细审剩余项 | 交互/状态细审剩余项 | 当前判定 |
| --- | --- | --- | --- | --- | --- |
| `_15` | 覆盖 step 1；缺 step 2 | Header、grid、中心 icon、CTA、三列 status 均覆盖 | glass/scan-line/corner accents 强度需要单屏截图复核；运行截图比设计更压缩 | `switchToStep2()`、授权按钮、导入/库页 router 缺操作截图 | 小差异 |
| `_13` | 未同态：设计是导入空态 step 1，运行图是授权 step 2 | 导入链路存在；`LOCAL_ONLY` 口径优于 HTML 的 `NETWORK: ONLINE` | 设计 upload 卡与运行 folder 卡不是同态；按钮位置、脚注文案、粒子分布未在 step 1 运行图中证明 | picker 打开、扫描进度、任务创建、跳 `_14` 缺证据 | 需补证据 |
| `_14` | 未同态：设计是 importing，运行图是 empty dialog | 背景 dim/blur、弹层宽度、居中层级覆盖 | importing 的 progress、footer、source/rate、Cancel 尺寸未被运行图覆盖；empty 态警告色不能代表主态 | pending task、conflict、success、failure、retry/cancel 缺截图 | 需补证据 |
| `_12` | 部分覆盖：空库/加载/搜索加载；缺有内容列表 | Header、搜索、telemetry、chips、loader、底部 nav 覆盖 | 最近运行横卡、封面裁切、游戏行、context menu blur 缺运行图；长截图与单屏 viewport 差异需分状态验收 | 搜索选择、筛选、刷新、长按菜单、详情跳转缺操作截图 | 小差异偏缺证据 |
| `_2` | 覆盖主入口 | controller slot、Netplay、input log、底部 Input 覆盖 | 运行图移动端纵向堆叠更紧；远端房间缩略图被替换为 `NOT_CONFIGURED` 诚实态 | 外设刷新、端口变化、布局编辑跳转、真设备输入缺截图 | 小差异 |
| `_7` | 缺最新运行图 | 静态 ETS 承载完整 | Quick Save 右侧 rail、D-pad/action cluster 间距、bottom nav 遮挡缺当前截图 | XComponent、虚拟输入、pause、quick save/load 缺设备证据 | 缺证据 |
| `_4` | 覆盖 Basic/Advanced/telemetry 三态 | tabs、section、slider、input preview、telemetry、System nav 覆盖 | Advanced 列表密度与设计 Basic 主态不能直接同态比较；输入预览图片/按钮基线需真机复核 | 设置值是否写入 engine、入口跳转缺操作证据 | 小差异 |
| `_3` | 缺最新运行图 | 静态 ETS 承载完整 | split preview、panel blur、stats 浮层、bottom Engine 高亮缺当前截图 | RESET/SAVE_CFG 仅本地预览，shader runtime/GPU stats 缺设备证据 | 缺证据 |

## Evidence Granularity Notes

- 尺寸差异：设计 `screen.png` 多为 1600px 高的长图，最新运行截图约 865-929px 高，不能用单屏截图直接否定长图下方内容；必须按状态和 viewport 拆验。
- `_2` 设计图宽 434、高 1600，运行图宽 435、高 899，宽度几乎同源但运行图截取高度少一半；因此只能判断首屏主入口，不能判断下半部分 input log/telemetry 完整滚动。
- `_12` 设计图宽 562、高 1600，运行图宽约 415-435、高约 903-929，比例明显不同；列表密度、最近运行卡和 bottom loader 必须分空库/有内容/搜索/长按菜单四态验收。
- `_13/_14` 的最大风险是状态不一致，不是像素误差。`_13` 需要 step 1 导入空态同态截图；`_14` 需要 pending task importing 同态截图。
- `_3/_7` 缺最新截图时，只能写静态承载与实现边界；任何“运行态看起来没问题”的结论都不成立。

## _15 Onboarding

### 证据来源
- `code.html`：glass header、grid/scan-line、`step-1` / `step-2` 两步流、主按钮和页面 transition。
- `screen.png`：欢迎 step 1，中心手柄 icon、标题、说明、主按钮、底部三列状态。
- 最新截图：`02_boot_welcome_quick_start.png`，显示欢迎/quick start 态。
- ETS：`OnboardingPage.ets`，含 grid indexes、`openImportEntry()`、`openLibraryPage()`、按钮 touch/translate 反馈。

### 视觉差异
- 布局：最新截图与设计截图同为居中首启欢迎态，header、中心 icon、标题、说明、主 CTA 和底部状态层级一致。
- 字号/密度：运行截图标题与按钮密度接近设计；页面整体更偏移动端纵向压缩，属于小差异。
- 颜色/透明度：黑底荧光绿主色一致；运行截图顶部 `BOOT_SEQUENCE` 和 `LOCAL_ONLY` 状态更明确。
- 边框/阴影/blur：设计的 glass/header、corner accents 和微弱扫描线在运行截图中可见但强度偏保守。
- 状态层级：运行截图只覆盖 step 1，未覆盖授权 step 2。

### 交互差异
- HTML demo 的 step transition 只是前端演示；ETS 使用真实按钮事件进入导入页或库页。
- 授权入口、跳转导入、跳转库页还缺运行截图串联证据。

### 运行态差异
- 最新截图能证明 Onboarding 欢迎态可见。
- 不能证明 step 2 授权态、按钮点击、router 跳转、动画完整可用。

### 结论
小差异。保留 `视觉完成`；运行态仍是 `LOCAL_ONLY / NOT_CONFIGURED / 需真机验证`。

### Deep-Dive Remaining Items
- `code.html` 中 step 2 有大号授权卡、scan-line 和 permission protocol block；当前最新截图只覆盖 step 1，不能证明 step 2 动效和授权卡在 ETS 中与设计同态。
- ETS 使用 `animateTo` 做 step out/in，和 HTML 的 CSS transition 目标一致；但运行截图没有覆盖 transition 中间态，后续只能验最终态，不应要求逐帧一致。
- 运行图 `02` 顶部状态为 `BOOT_SEQUENCE: 01`，设计也为 boot step 1；这是同态证据。缺口集中在下一步授权态，而不是欢迎态本身。
- 需要补的最小证据：点击“立即开启”后的 step 2 截图、点击“打开导入器”后的 ImportEntry 路由截图、点击跳过/进入库页后的 Library 路由截图。

## _13 Import Entry

### 证据来源
- `code.html`：导入页空态、粒子背景、`NETWORK: ONLINE` demo 文案、inline scan progress 和 `startImport()` 演示。
- `screen.png`：导入 step 1，中心 upload 卡、标题、说明、选择文件按钮和底部 Library 高亮。
- 最新截图：`03_import_authorization_required.png`，显示授权 step 2；`01/04` 显示库页空态入口可进入导入链路。
- ETS：`ImportEntryPage.ets`、`ImportEmptyStateHero.ets`，`startImport()` 走真实导入入口，并显示 `LOCAL_ONLY`。

### 视觉差异
- 布局：最新主截图是授权态，不是设计截图中的空态导入 CTA；两者同属导入链路，但状态不同。
- 字号/密度：授权态标题更长、顶部说明更密；运行截图底部主按钮更贴近移动端可触达区域。
- 颜色/透明度：ETS 已把 HTML 的 `NETWORK: ONLINE` 改为本地/授权口径，符合运行态诚实原则。
- 边框/阴影/blur：中心文件夹卡比设计 upload 卡更具体，主视觉仍在中轴。
- 状态层级：step 1 空态由 `01/04` 的库页入口间接覆盖，`03` 直接覆盖 step 2 授权。

### 交互差异
- HTML 的扫描进度是 demo 定时器；ETS 应只在真实 picker/import handoff 后推进。
- 当前截图不能证明 picker 打开、任务创建、跳到 `_14` 的完整链路。

### 运行态差异
- 最新截图证明授权前状态可见，库页空态证明导入入口可见。
- 缺 step 1 导入页本体运行截图、picker 结果和导入任务创建截图。

### 结论
需修证据，不是代码 P0。保留 `视觉完成`，但运行态证据应标“授权态已截图，空态/任务创建缺截图”。

### Deep-Dive Remaining Items
- 设计同态是 `_13/screen.png`：顶部 `NETWORK: ONLINE`、中心 upload/triangle 卡、标题“一键导入游戏，重温经典”、按钮“选择游戏文件导入”、底部 Library 高亮。
- 运行图 `03` 是授权态：顶部 `STEP 02`、标题“允许访问文件，才能导入你手机里的游戏”、folder 卡、protocol block、底部“打开导入器”。这不是同一 UI 状态。
- ETS 已将 HTML 的网络在线 demo 改为 `LOCAL_ONLY`，这是正确的状态收敛；但因为运行图没有 step 1，无法判断 `ImportEmptyStateHero` 的 upload 卡、按钮宽度、脚注和粒子位置是否在真实单屏中达标。
- `ImportEntryPage.ets` 中 `startImport()`、`finishImportFlow()` 和 scan progress 存在真实流程意图；当前运行截图没有覆盖扫描进度条、button pressed、任务 bridge 跳转。
- 需要补的最小证据：进入 `_13` 后尚未授权/尚未选择文件的 step 1 截图、点击按钮弹 picker 前后的截图、选择文件后跳 `_14` 的任务创建截图。

## _14 Import Task Overlay

### 证据来源
- `code.html`：背景 blur/dim、importing/success/error 三态、progress、`Cancel Task` 和状态 transition。
- `screen.png`：正在导入 `1/3` 的进度弹层。
- 最新截图：`05_import_task_empty_dialog.png`，显示无 pending task 的 `NO_PENDING_IMPORT_TASK` 空态弹层。
- ETS：`ImportTaskOverlayPage.ets`、`RomImportService.ets`、`ImportTaskBridge.ets`，有 `NO_PENDING_IMPORT_TASK`、cancel/retry/conflict/result 分支和生命周期 guard。

### 视觉差异
- 布局：运行截图是空任务弹层，弹层宽度、居中、背景 dim 与设计的 importing 弹层一致，但主体图标/文案不同。
- 字号/密度：空态文案更短，按钮密度更低；不能代表 importing 状态视觉。
- 颜色/透明度：空态使用警告色，设计 importing 使用荧光绿进度线；这是状态差异，不是同态偏差。
- 边框/阴影/blur：背景 blur/dim 和弹层边界可见，符合设计层级。
- 状态层级：只覆盖 no-pending；未覆盖 importing、success、error、conflict。

### 交互差异
- HTML 用 `toggleState()` 手动切换 demo；ETS 应由真实 import task、冲突和失败结果驱动。
- 返回导入、取消、重试、覆盖、返回库页都缺运行截图证据。

### 运行态差异
- 最新截图证明“没有任务时不伪造进度”的诚实空态可见。
- 不能证明有 pending task 时的真实进度、取消、冲突、失败、成功路径。

### 结论
需修证据。视觉外壳小差异，但 `_14/screen.png` 对应的 importing 主态缺运行截图。

### Deep-Dive Remaining Items
- 设计同态是 importing：`EXECUTING_TASK`、`正在导入 1/3`、`EST: 02:45`、进度条约三分之一、`SOURCE: EXT_DISK_A`、`24.4 MB/S`、右侧 `CANCEL TASK`、底部 `PROCESS_ID` 和 `VERIFYING_CHECKSUM...`。
- 运行图 `05` 是 empty：警告 icon、`没有导入任务`、`IMPORT_TASK_EMPTY`、取消/再试一次。它只能证明“空任务不伪造进度”。
- 背景 dim/blur、弹层宽度、居中层级已经可以从 `05` 看到；但 progress/footer/source/rate/Cancel 的布局没有同态证据。
- ETS 的 `ImportTaskOverlayPage.ets` 覆盖 importing、conflict、success、failure 和 empty 分支；本轮只看到 empty，所以不能判断有任务时的 `progressPercent`、`etaText`、`transferRateText` 是否在单屏里稳定。
- 需要补的最小证据：有 pending task 的 importing 截图、cancel 后状态、冲突列表、成功结果、失败重试。尤其 importing 是 `_14/screen.png` 主态，优先级最高。

## _12 Library Home

### 证据来源
- `code.html`：sticky header、搜索、telemetry strip、平台 chips、最近运行卡、全部游戏列表、pull refresh、context menu 和 bottom loader。
- `screen.png`：有封面游戏列表主态。
- 最新截图：`01/04` 空库导入态、`06` loading assets、`07` SNES 搜索加载态。
- ETS：`LibraryPage.ets`、`LibrarySearchPanel.ets`、`LibraryGameSections.ets`、`LibraryContextMenuOverlay.ets`，搜索/筛选/刷新由 repository/page state 驱动。

### 视觉差异
- 布局：运行截图覆盖空库、加载和搜索加载态；与设计截图的有内容列表主态不同。
- 字号/密度：搜索框、telemetry strip、chips、底部导航密度接近；空库态标题明显占据更多中部空间。
- 颜色/透明度：黑底荧光绿、灰色 secondary 信息和底部 Library 高亮一致。
- 边框/阴影/blur：搜索框、空态卡、loader 表现稳定；context menu 的 blur 只在 HTML/ETS 中可见，缺最新截图。
- 状态层级：运行截图证明空库和加载态；未证明封面列表、最近运行横卡、全部游戏行、长按菜单。

### 交互差异
- HTML 的 pull refresh、搜索 popover、context sheet 是 demo 行为；ETS 有真实 search debounce、refresh token、repository scanning 和 long-press overlay。
- 搜索输入、筛选 chip、刷新 toast、长按菜单和详情跳转仍需设备截图或操作验证。

### 运行态差异
- 最新截图证明 Library 页面可见、空库导入入口可见、搜索加载态可见、底部导航稳定。
- 缺有 ROM 索引后的完整列表态和 context menu 运行截图。

### 结论
小差异偏证据不足。保留 `视觉完成`；运行态证据只覆盖空库/加载/搜索加载，不覆盖完整库列表。

### Deep-Dive Remaining Items
- 设计同态是有内容库页：搜索框、telemetry strip、平台 chips、最近运行两张封面、全部游戏行、bottom loader、底部 Library 高亮。
- 运行图 `01/04` 是空库导入入口，`06` 是 loading assets，`07` 是 SNES 搜索加载；这些覆盖了壳层和加载态，但没有覆盖有内容列表。
- HTML 中包含 context menu、success toast、search popover、pull refresh；ETS 中也有 `showContextMenu`、`searchBusy`、`refreshing`、`bottomLoaderActive`、long press timer 等状态，但最新截图没有覆盖 context menu 和 toast。
- 设计图为长列表截屏，运行图为单屏状态；列表下半部分不能从当前图判断，不能写“全部游戏行已运行态完成”。
- 需要补的最小证据：有 ROM 数据的首屏、滚动到全部游戏区、搜索有结果 popover、长按 context menu、刷新 toast。

## _2 Multiplayer Input

### 证据来源
- `code.html`：两个 controller cards、三列 stats、Netplay Lobby、Create Room、jitter telemetry、input log、底部 Input 高亮。
- `screen.png`：DualSense/Xbox 双控制器、房间列表、jitter 图和 input log。
- 最新截图：`08_input_netplay_center.png`，显示 Input / Netplay Center 主入口。
- ETS：`MultiplayerInputPage.ets`、`RuntimeInputPortController.ets`，外设刷新、layout editor route、Netplay `NOT_CONFIGURED`。

### 视觉差异
- 布局：运行截图保留 controller slot、Netplay lobby、输入日志和底部 Input 高亮；相比设计图，运行态更窄、更移动端纵向堆叠。
- 字号/密度：运行截图文本更紧，controller 卡统计块更简化；主信息可读。
- 颜色/透明度：本地 connected、disabled、offline 状态用绿/灰/红区分，符合诚实状态。
- 边框/阴影/blur：卡片边界和 Netplay 区域明确；设计图中的远端房间缩略图未进入运行态。
- 状态层级：运行截图把 remote lobby service not configured 放在主层级，避免伪造在线房间。

### 交互差异
- HTML 的 Create Room/房间行 hover 是 demo；ETS 中创建房间禁用，外设刷新和编辑布局为真实入口。
- 还缺蓝牙/USB 真设备接入、刷新后状态变化和布局编辑跳转截图。

### 运行态差异
- 最新截图证明 Input / Netplay Center 主入口可见，底部 Input 高亮正确。
- Netplay 后端、外设轮询率、真实延迟和多端口输入仍缺设备验证。

### 结论
小差异。保留 `视觉完成`；运行态仍是 `LOCAL_ONLY / NOT_CONFIGURED / 需真机验证`。

### Deep-Dive Remaining Items
- 设计图顶部两个 controller cards 分别是 DualSense / Xbox，运行图使用 `Virtual Pad P1` 和 `External Device`，是更贴近当前本地能力的状态替换。
- 设计图的 Netplay 房间列表是在线 demo，运行图显示 remote lobby service 未配置；这是正确的诚实降级，不应当算视觉缺失。
- 运行图首屏覆盖 controller、Netplay、input log/底部 Input 高亮；但设计长图下方 jitter telemetry 的完整柱状图与输入日志下半部分在当前运行图中没有完全覆盖。
- ETS 中 `refreshInputDevices()` 和“编辑按键布局”按钮存在，运行图没有覆盖刷新后的状态变化，也没有覆盖跳 `InputLayoutPage`。
- 需要补的最小证据：刷新设备前后对比、插入/连接真实外设后的状态、进入布局编辑页、Netplay 未配置按钮禁用态细节。

## _7 Runtime Controller

### 证据来源
- `code.html`：全屏 controller canvas、top telemetry、D-pad、A/B/X/Y cluster、Quick Save resident button、Select/Start、telemetry toggle 和 Quick Save drag demo。
- `screen.png`：运行态控制器主画面。
- 最新截图：缺。
- ETS：`LibretroGamePage.ets`、`RuntimeTopHudBar.ets`、`RuntimeVirtualControllerLayer.ets`、`RuntimeControlPanel.ets`，虚拟按钮、pause、hide controller、quick save/load 绑定真实 runtime 语义。

### 视觉差异
- 布局：静态设计与 ETS 承载关系匹配，但没有 2026-05-04 运行图确认当前显示。
- 字号/密度：无法基于最新截图判断；只能沿用 2026-04-30 静态审计结论。
- 颜色/透明度：静态设计为暗场 + green HUD；ETS 预计同系。
- 边框/阴影/blur：Quick Save、glass panel、top HUD 是否在当前窗口尺寸下不遮挡，缺截图。
- 状态层级：运行画面、暂停、隐藏手柄、control panel 状态缺最新运行态证据。

### 交互差异
- HTML 的 Quick Save drag 和 telemetry toggle 是 demo；ETS 绑定真实 button/sendRuntimeButton、pause 和 runtime save status。
- 虚拟输入、暂停、即时存读档、XComponent 画面必须设备验证。

### 运行态差异
- 缺最新截图，不能确认当前 runtime controller 可见状态。
- 不能判断底部导航、Quick Save、手柄热区、横竖屏间距是否与 ETS 预期一致。

### 结论
缺证据。静态设计对照为小差异，但运行态必须保持“缺最新截图，不能确认”。

### Deep-Dive Remaining Items
- 设计图关键是全屏控制器 overlay：top HUD、暗场游戏画面、movement panel、A/B/X/Y cluster、Quick Save rail、Select/Start、bottom System 高亮。
- ETS 承载拆分清晰：`RuntimeTopHudBar` 负责 HUD，`RuntimeVirtualControllerLayer` 负责 movement/action/Quick Save/Select Start，`RuntimeControlPanel` 负责运行控制面板。
- 静态代码中 Quick Save rail、按钮尺寸、`onButtonChange`、`sendRuntimeButton` 语义存在；但缺运行截图时不能判断横竖屏间距、底部导航遮挡和 XComponent 背景是否实际正确。
- HTML 的 Quick Save drag、telemetry toggle 是 demo 行为；ETS 没有伪造拖拽，这一点是正确边界。后续若产品要求拖拽，需要单独列为功能缺口，而不是视觉缺口。
- 需要补的最小证据：游戏运行页默认态、按下方向键/A 键反馈、Quick Save 状态、Pause overlay、隐藏手柄状态。

## _4 Settings

### 证据来源
- `code.html`：Basic/Advanced tabs、video processing、input interface、audio volume、system telemetry 和底部 System 高亮。
- `screen.png`：Basic 设置主态。
- 最新截图：`09_system_basic_settings.png`、`10_system_advanced_settings.png`、`11_system_telemetry_audio.png`。
- ETS：`SettingsPage.ets`，`activeTab`、aspect/scanline/volume 本地状态、`LOCAL_PRESET`、`PREVIEW_ONLY`。

### 视觉差异
- 布局：Basic、Advanced、telemetry/audio 三个截图覆盖主要设置状态；和设计图的单屏 Basic 主态一致性较高。
- 字号/密度：运行截图中 Advanced 列表更稀疏，但 tab、section、slider、telemetry 可读性稳定。
- 颜色/透明度：System 高亮、section 绿条和灰色说明一致；`LOCAL_PRESET/PREVIEW_ONLY` 诚实标识清晰。
- 边框/阴影/blur：输入设备预览卡、telemetry 柱状图、slider 轨道已可见；blur 不是此页主风险。
- 状态层级：运行截图覆盖 Basic、Advanced 和 telemetry/audio，但不证明设置已写入 engine。

### 交互差异
- HTML 的 tab switch 是 DOM demo；ETS 用 `activeTab` 切换，设置值仍是页面本地状态。
- 输入布局、多输入中心、Shader Preview 等跳转入口缺操作截图。

### 运行态差异
- 最新截图证明三个设置态可见，底部 System 高亮正确。
- 不能证明 aspect/scanline/audio/input 设置实际影响 runtime。

### 结论
小差异。保留 `视觉完成`；运行态仍需 engine 生效验证。

### Deep-Dive Remaining Items
- 设计图是 Basic 主态；运行图覆盖 Basic、Advanced、telemetry/audio 三态，证据比其他页充分。
- Basic 图中画面比例 segment、scanline slider、输入设备预览、音量 slider 与设计结构一致；Advanced 图中 `GPU Backend`、`Frame Pacing`、`Audio Buffer`、`Shader Mode` 等诚实标 `LOCAL_PRESET/PREVIEW_ONLY`。
- 运行图 `11` 的 telemetry/audio 状态覆盖了柱状图和 volume slider，但输入设备预览区上方元素更紧，需要真机确认是否存在文字/图形重叠。
- ETS 的设置值仍是页面本地状态；从截图不能证明写入 engine 或影响 runtime。这个缺口属于运行态功能验证，不是视觉对齐。
- 需要补的最小证据：切 tab 操作录屏/截图、调整 slider 后状态、从设置进入 Shader/Input/Core 等页面、设置影响 runtime 的设备验证。

## _3 Shader Preview

### 证据来源
- `code.html`：split preview、scanline overlay、shader parameters panel、RESET/SAVE_CFG、GPU stats 和底部 Engine 高亮。
- `screen.png`：Shader Preview 主态。
- 最新截图：缺。
- ETS：`ShaderPreviewPage.ets`、`RuntimeRenderSettingsController.ets`，本地 slider、`SHADER_RUNTIME_NOT_CONFIGURED`、`PREVIEW_ONLY`。

### 视觉差异
- 布局：静态设计与 ETS 承载关系匹配，包含 split preview、中央 handle、参数面板和 stats 浮层。
- 字号/密度：缺最新运行截图，不能确认当前窗口下 slider 面板和底部导航是否拥挤。
- 颜色/透明度：设计为绿/黑 shader control；ETS 明确显示 `NOT_CONFIGURED/PREVIEW_ONLY`。
- 边框/阴影/blur：参数面板 blur 和 stats 浮层是否与当前 ArkUI 效果一致，缺截图。
- 状态层级：只可确认静态代码中没有把 shader runtime 伪装成已配置。

### 交互差异
- HTML 的 SAVE_CFG 是视觉按钮；ETS RESET/SAVE_CFG 只处理本地预览状态。
- 真实 shader 列表、GPU stats、GLES 应用链路缺接线和设备验证。

### 运行态差异
- 缺最新截图，不能确认运行页面可见状态。
- 不能判断 Engine 高亮、split preview、参数面板和底部导航是否与 ETS 预期一致。

### 结论
缺证据。静态设计对照为小差异，但运行态必须保持“缺最新截图，不能确认”。

### Deep-Dive Remaining Items
- 设计图关键是左右 split preview、中央 green handle、右侧 scanline/CRT、浮动参数面板、GPU stats、底部 Engine 高亮。
- ETS 中 `ShaderPreviewPage.ets` 有 `scanlineIntensity`、`curvature`、`saturation`、`SHADER_RUNTIME_NOT_CONFIGURED`、`PREVIEW_ONLY`，说明当前实现没有把 shader runtime 伪装成已接入。
- 缺最新截图时，不能判断参数面板在真实 viewport 中是否遮挡 preview、bottom nav 是否覆盖 stats、blur/backdrop 是否符合 ArkUI 实际效果。
- HTML 的 `SAVE_CFG` 是视觉参考；ETS 的 SAVE_CFG 只保存本地 preview 状态。后续若要求真实 GLES shader 应用，需要从 `RuntimeRenderSettingsController` 到 native render pipeline 单独验。
- 需要补的最小证据：Shader Preview 当前页面截图、RESET/SAVE_CFG 点击后状态、Engine 高亮、参数面板与底部 nav 同屏不遮挡。

## Follow-up Priority

| 优先级 | 项目 | 原因 |
| --- | --- | --- |
| P1 | `_14` pending task / conflict / success / failure 截图 | 当前只覆盖 `NO_PENDING_IMPORT_TASK`，与设计主态不同。 |
| P1 | `_3` / `_7` 最新运行截图 | 两页不能做 runtime 三方对照。 |
| P1 | `_13` step 1 导入空态截图 | 最新主截图是授权 step 2，缺设计截图同态证据。 |
| P2 | `_12` 有内容列表和 context menu 截图 | 当前只覆盖空库、加载和搜索加载。 |
| P2 | `_2` 外设刷新 / 布局编辑跳转截图 | 当前只覆盖主入口静态状态。 |
| P2 | `_4` 设置项实际生效验证 | 当前只能证明 UI 状态可见，不能证明 runtime 生效。 |

## Verification Notes

- 本轮只读检查了 8 个目录的 `code.html` / `screen.png` 存在性。
- 读取了 `docs/verification/runtime-screenshots-2026-05-04/README.md`，最新截图仅映射 `_2/_4/_12/_13/_14/_15`。
- 生成并查看了临时 contact sheet：`%TEMP%/harmony_design_sheet_20260504.png`、`%TEMP%/harmony_runtime_sheet_20260504.png`，未写入仓库。
- 复跑固定布局扫描命令；命中均来自既有 ETS 代码。本轮 audit-only 未修改 ArkTS，因此没有新增固定布局风险。命中类型主要是 token 级尺寸、输入热区/扫描线/按钮反馈等既有业务尺寸，后续修 UI 时需按页面逐项复判。
- 未编译、未真机、未运行测试脚本。
