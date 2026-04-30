# 15 个设计页验收矩阵

> 日期：2026-04-30
> 范围：`stitch_game_emulator_design_plan/_1` 到 `_15` 的原生 ArkTS 承载关系与后续视觉收口入口。
> 约束：本矩阵只记录当前仓库可见状态，不把“有相似 ETS 页面”写成“设计页已完成”。本轮未编译、未预览、未真机验证。
> 详细依据：见 `docs/2026-04-30-design-page-artifact-gap-audit.md`。

## 状态规则

- `已完成` 只允许使用：`未开始` / `部分完成` / `视觉完成` / `运行态完成`。
- `screen.png` 用于静态视觉验收，`code.html` 用于结构、动效和状态参考。
- 后端、设备、云端或真实外设能力未接入时，`运行态缺口` 必须写明 `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`。
- 旧架构 `deprecated/legacy/` 不参与本矩阵。

## 验收矩阵

| 设计目录 | ETS 页面/组件 | 已完成 | 视觉缺口 | 交互缺口 | 运行态缺口 | 详细报告 | 下一步 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `stitch_game_emulator_design_plan/_1` | `entry/src/main/ets/pages/CoreManagerPage.ets`、`entry/src/main/ets/common/LibretroCoreCatalog.ets` | 部分完成 | 已有 memory/core/log 骨架；仍需对齐资源条、核心卡、状态 badge、log 密度和 System 导航高亮。 | UPDATE/INSTALL/核心选择/诊断入口需按真实 catalog 能力启用或禁用。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：远端更新、固件库、真实内存指标未接入。 | `# _1 Core Manager` | 第六组收口：与 Shader/Settings/About 统一 Engine/System 视觉语言。 |
| `stitch_game_emulator_design_plan/_2` | `entry/src/main/ets/pages/MultiplayerInputPage.ets`、`entry/src/main/ets/common/RuntimeInputPortController.ets` | 部分完成 | 已有控制器、Netplay、telemetry 和 input log；仍需对齐控制器 stat 小块、房间列表、jitter 图表和日志状态列。 | 外设刷新、端口映射和布局编辑需走真实 device route；Netplay 创建/加入未接后端时禁用。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：多人输入、蓝牙/USB、Netplay 服务需设备/后端验证。 | `# _2 Multiplayer Input` | 第五组收口：与 `_6` 输入布局一起核对，联机保持诚实未配置态。 |
| `stitch_game_emulator_design_plan/_3` | `entry/src/main/ets/pages/ShaderPreviewPage.ets`、`entry/src/main/ets/common/RuntimeRenderSettingsController.ets` | 部分完成 | 已有 split preview 和调参面板；仍需对齐全屏图像裁切、中央分割线、scanline/CRT、浮层 stats 和 slider 轨道。 | RESET/APPLY/SAVE_CFG 语义需统一，并区分静态 preview 与真实 runtime shader 应用。 | `NOT_CONFIGURED` / `需真机验证`：真实 shader 列表、GPU stats、GLES 应用链路需设备验证。 | `# _3 Shader Preview` | 第六组收口：先标清 preview 能力，再做 split preview 视觉。 |
| `stitch_game_emulator_design_plan/_4` | `entry/src/main/ets/pages/SettingsPage.ets` | 部分完成 | 已有 tabs、segment、slider、输入设备卡和 telemetry；仍需对齐顶部栏、section 绿条、controller 预览和柱状图。 | 设置项如未写入真实 controller/repository，应显示只读或未配置，不能伪装成已应用。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：渲染、音频、输入设置实际效果需运行验证。 | `# _4 Settings` | 第六组收口：优先核对现有真实设置 controller，再补视觉。 |
| `stitch_game_emulator_design_plan/_5` | `entry/src/main/ets/pages/AboutHelpPage.ets` | 部分完成 | 已有关于/帮助承载；仍需对齐 hero、版本卡、帮助列表、footer 品牌区和 System 导航高亮。 | 帮助项、外链、反馈、法律文档如无真实入口应禁用或显示未配置。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：在线帮助/外链未接入，版本来源需验证。 | `# _5 About Help` | 第六组收口：作为 System 分组末尾，统一 About 与 Settings 的视觉语言。 |
| `stitch_game_emulator_design_plan/_6` | `entry/src/main/ets/pages/InputLayoutPage.ets`、`entry/src/main/ets/common/InputLayoutRepository.ets` | 部分完成 | 已有布局编辑状态和保存逻辑；仍需对齐 calibration 画布、虚线选框、按键尺寸、底部 dock 和 telemetry 浮层。 | 拖拽/选择/重置/保存必须基于百分比逻辑画布，避免设计稿绝对坐标。 | `LOCAL_ONLY` / `需真机验证`：布局持久化、触控热区、横竖屏与 runtime 使用需设备验证。 | `# _6 Input Layout` | 第五组收口：先检查外层自适应画布，再做控件视觉和反馈。 |
| `stitch_game_emulator_design_plan/_7` | `entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimeTopHudBar.ets`、`entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`、`entry/src/main/ets/components/RuntimeControlPanel.ets` | 部分完成 | 已有 runtime HUD、虚拟手柄和控制面板；仍需对齐 playfield、CRT/scanline、movement 卡片、动作键 cluster 和 Quick Save。 | 虚拟按钮、暂停、隐藏手柄、即时存档/读档必须保持真实 input/runtime 语义。 | `NOT_CONFIGURED` / `需真机验证`：XComponent、帧率、音频、输入、震动和 core 运行需设备验证。 | `# _7 Runtime Controller` | 第五组收口：只改视觉层和 HUD 展示，不改 engine/input 事件语义。 |
| `stitch_game_emulator_design_plan/_8` | `entry/src/main/ets/pages/SaveStatePage.ets`、`entry/src/main/ets/common/SaveStateRepository.ets` | 部分完成 | 已有存档列表、delete confirm、toast 和 empty archive；仍需对齐 swipe action、slot 缩略图、顶部摘要和虚线 archive block。 | Quick save/load/delete/refresh 需绑定当前 ROM 和 repository；云同步文案无后端时不能显示真实同步。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：云同步未配置，读写档和文件权限需设备验证。 | `# _8 Save State` | 第五组收口：先核对本地 slot 真实数据，再补列表和弹层视觉。 |
| `stitch_game_emulator_design_plan/_9` | `entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimePauseOverlay.ets` | 部分完成 | 已有 pause overlay；仍需对齐标题绿线、Resume CTA、四宫格、terminate 区域、telemetry 折线和暗化背景。 | Resume/stop 可接真实能力；save/load/filter/input mapping 需按能力状态显示或跳真实页面。 | `NOT_CONFIGURED` / `需真机验证`：暂停、恢复、停止、快捷存读档和滤镜需运行验证。 | `# _9 Pause Overlay` | 第五组收口：按 `_9` 统一暂停面板，但不伪造存档/滤镜能力。 |
| `stitch_game_emulator_design_plan/_10` | `entry/src/main/ets/pages/LibraryDetailPage.ets`、`entry/src/main/ets/components/LibraryDetailHeroPanel.ets`、`entry/src/main/ets/components/LibraryDetailInfoPanel.ets`、`entry/src/main/ets/components/LibraryLaunchOverlay.ets` | 视觉完成 | 顶部本地状态胶囊、hero 封面、绿色 CTA、metadata grid、telemetry 网格和 overview 灰底已按主体截图收口；仍需真机看封面裁切和长标题。 | Library -> Detail -> Runtime 参数、launch overlay、编辑元数据和 quick actions 继续按真实 route/repository 驱动。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：云存档未配置，启动和 runtime 写回需设备验证。 | `# _10 Library Detail` | 用户真机验收：库页进入详情、启动 overlay、编辑资料、存档入口和返回库页。 |
| `stitch_game_emulator_design_plan/_11` | `entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets` | 视觉完成 | action sheet 宽度、暗化 blur、分割线、删除项红色层级和独立 Cancel 已按截图收紧；仍需真机看命中区域与背景模糊强度。 | 启动、详情、修改封面、删除存档、取消已保持分区点击；遮罩关闭仍需设备命中测试。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：修改封面若未接 picker/持久化需标未配置，菜单触发需设备验证。 | `# _11 Library Context Menu` | 用户真机验收：长按菜单、遮罩关闭、各操作入口。 |
| `stitch_game_emulator_design_plan/_12` | `entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibrarySearchPanel.ets`、`entry/src/main/ets/components/LibraryGameSections.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets` | 视觉完成 | 搜索框、telemetry strip、平台 chip、最近运行双卡、全部游戏行和 bottom loader 已按主体截图收紧；仍需真机确认滚动密度和长文本。 | 搜索、平台过滤、卡片详情、长按菜单、刷新 toast 和底部 loader 继续由 repository/page state 驱动。 | `LOCAL_ONLY` / `需真机验证`：库索引、封面加载、文件扫描、滚动和路由需设备验证。 | `# _12 Library Home` | 用户真机验收：搜索、筛选、滚动、长按菜单。 |
| `stitch_game_emulator_design_plan/_13` | `entry/src/main/ets/pages/ImportEntryPage.ets`、`entry/src/main/ets/components/ImportEmptyStateHero.ets` | 视觉完成 | 中心 hero 卡、标题/说明密度、导入按钮宽度、脚注和 `LOCAL_ONLY` 顶部状态已收口；粒子位置为装饰层，仍需真机确认动效强度。 | 导入按钮仍只做真实 picker/import service handoff；pre-picker 不再强化假网络在线状态。 | `LOCAL_ONLY` / `需真机验证`：本地文件选择、权限、导入任务创建和库刷新需设备验证。 | `# _13 Import Entry` | 用户真机验收：空态进入 picker，并成功跳任务页。 |
| `stitch_game_emulator_design_plan/_14` | `entry/src/main/ets/pages/ImportTaskOverlayPage.ets`、`entry/src/main/ets/common/RomImportService.ets`、`entry/src/main/ets/common/ImportTaskBridge.ets` | 视觉完成 | importing 面板宽度、背景 dim/blur、progress、footer 和 Cancel 尺寸已对齐；演示值已替换为真实任务/本地占位。 | cancel/retry/return/conflict 处理继续来自真实 import task；无 pending task 时保持 `NO_PENDING_IMPORT_TASK` 诚实空态。 | `LOCAL_ONLY` / `需真机验证`：导入进度、复制、冲突、取消、失败重试和返回库页需设备验证。 | `# _14 Import Task Overlay` | 用户真机验收：有 pending task 和无 pending task 两条路径。 |
| `stitch_game_emulator_design_plan/_15` | `entry/src/main/ets/pages/OnboardingPage.ets` | 视觉完成 | grid、glass header、中心 icon 卡、corner accents、主按钮、三列 status、底部 build 文案和 step 过渡已完成首批视觉对齐；仍需真机确认不同窗口尺寸。 | 两步切换、授权入口和进入导入/库页路径继续绑定真实用户操作与 router。 | `LOCAL_ONLY` / `NOT_CONFIGURED` / `需真机验证`：云端库/映射驱动器未配置，权限/picker/动画需设备验证。 | `# _15 Onboarding` | 用户真机验收：首启 step 1/step 2 切换与路由。 |

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
