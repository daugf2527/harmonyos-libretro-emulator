# 15 个设计页 Artifact-to-Artifact Gap Audit

> 日期：2026-04-30
> 范围：`stitch_game_emulator_design_plan/_1` 到 `_15`。
> 方法：逐项打开 `screen.png`，读取 `code.html` 的 body 结构/可见文案/主要 class，并对照当前矩阵映射的 ETS 页面/组件与 `main_pages.json` 注册状态。
> 边界：本轮包含静态验收、文档更新与第一批 ArkTS 视觉收口；未编译、未预览、未真机运行；旧架构 `deprecated/legacy/` 不参与。

## _1 Core Manager

### 设计目标
- `screen.png` 是内核与固件管理页：顶部终端栏、`MEMORY_FOOTPRINT` 三段资源条、`ACTIVE_CORES` 列表、`KERNEL_LOG`、底部 System 高亮导航。
- `code.html` 的关键结构包含 memory cards、core cards、kernel log 和底部导航；可见文案包括 `VRAM Allocation`、`Kernel Cache`、`Swap Pressure`、`Snes9x-Core`、`mGBA-Core`、`PCSX-ReARMed`。

### 当前承载
- ETS：`entry/src/main/ets/pages/CoreManagerPage.ets`、`entry/src/main/ets/common/LibretroCoreCatalog.ets`。
- 路由：`pages/CoreManagerPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 当前页面已有 `MEMORY_FOOTPRINT`、`ACTIVE_CORES` 与 `KERNEL_LOG` 静态骨架，但仍需逐项对齐截图中的三段资源条密度、核心卡图标块、状态 badge、按钮边框、log 行间距和底部导航 System 高亮。
- 设计强调窄长终端屏的单列密度，ETS 需要确认在不同窗口宽度下不会把 active core 行压成松散卡片。

### 交互 gap
- `UPDATE` / `INSTALL` / 核心选择 / 诊断入口需要与真实 catalog 能力绑定；不可用的固件源和远端更新应保持禁用或说明态。
- 底部导航已通过 router 跳转承载，但当前静态检查未验证点击反馈、active 状态和返回路径。

### 运行态 gap
- `LOCAL_ONLY`：当前核心目录与固件状态只能从本地 catalog / packaged libs 范围证明。
- `NOT_CONFIGURED`：远端更新源、固件数据库、真实内存/VRAM 压力未接入。
- `需真机验证`：实际 core 扫描、权限、动态内存指标和按钮可用性需设备验证。

### 结论
部分完成。

## _2 Multiplayer Input

### 设计目标
- `screen.png` 是输入映射与联机中心：两个控制器卡、Netplay lobby、jitter telemetry 柱状图、input log、底部 Input 高亮。
- `code.html` 包含 controller cards、battery/latency/protocol、小型房间列表、`Create Room`、实时 telemetry 与输入日志。

### 当前承载
- ETS：`entry/src/main/ets/pages/MultiplayerInputPage.ets`，并关联 `entry/src/main/ets/common/RuntimeInputPortController.ets`。
- 路由：`pages/MultiplayerInputPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 当前页面已有 controller slot、Netplay lobby、telemetry、input log 与刷新/编辑按钮；仍需对齐截图中的卡片高度、三列 stats 小块、房间列表缩略图、jitter 图表网格、input log 右侧状态列。
- 设计是输入中心页，底部 Input 高亮；需确认 ETS 的底部导航与主流程一致。

### 交互 gap
- 外设刷新、端口映射、进入按键布局页应走真实 device route；房间创建/加入若无后端必须禁用或展示未配置态。
- `code.html` 的 hover/active 反馈和房间 chevron 动效尚未逐项落到 ArkUI。

### 运行态 gap
- `LOCAL_ONLY`：本地 input port/controller 列表可静态接入。
- `NOT_CONFIGURED`：Netplay lobby、房间服务、远端 player 数据未配置。
- `需真机验证`：蓝牙/USB 外设、轮询率、输入延迟和端口映射需设备验证。

### 结论
部分完成。

## _3 Shader Preview

### 设计目标
- `screen.png` 是 shader split preview：左侧 `SOURCE_RAW`、右侧 `LIVE_SHADER`，中线分割、scanline 覆盖、大型调参面板和 GPU/latency 浮层。
- `code.html` 包含双半屏预览、`CRT-ROYALE_V4.2`、`INTERLACE_MODE: ACTIVE`、三个 slider、`RESET` / `SAVE_CFG`。

### 当前承载
- ETS：`entry/src/main/ets/pages/ShaderPreviewPage.ets`、`entry/src/main/ets/common/RuntimeRenderSettingsController.ets`。
- 路由：`pages/ShaderPreviewPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 当前 ETS 有 split preview 和调参面板承载；仍需对齐截图的全屏背景图裁切、中央荧光分割线、scanline/CRT 点阵、面板透明度、slider 轨道与 GPU stat 浮层。
- `SAVE_CFG` 在 ETS 中表现为 `APPLY`，需要确认产品文案是否统一。

### 交互 gap
- slider 变化、reset、apply/save 行为需要区分仅保存设置与真实 runtime shader 应用。
- `code.html` 的 split divider 状态和 live shader 标记未通过运行态确认。

### 运行态 gap
- `NOT_CONFIGURED`：真实 shader 列表、GPU load、shader runtime 应用链路未静态证明完整。
- `需真机验证`：GLES 渲染、shader 参数应用、延迟指标和预览帧真实性必须设备验证。

### 结论
部分完成。

## _4 Settings

### 设计目标
- `screen.png` 是系统设置页：Basic/Advanced tab、画面比例 segment、scanline slider、输入设备卡、音量 slider、系统 telemetry 柱状图。
- `code.html` 结构包含 `VIDEO_PROCESSING`、`INPUT_INTERFACE`、`AUDIO_VOLUME`、`SYSTEM_TELEMETRY` 和 bottom System 高亮。

### 当前承载
- ETS：`entry/src/main/ets/pages/SettingsPage.ets`。
- 路由：`pages/SettingsPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 当前 ETS 已有 tab、segment、slider、输入设备卡、telemetry；仍需校准截图中的顶部栏高度、tab 下划线、section 左侧绿条、controller 图片/预览区域、柱状图网格和底部导航间距。
- 设计的高级设置文案在 `code.html` 中存在，需确认 Advanced tab 内容不是只显示占位。

### 交互 gap
- 画面比例、scanline、音量、输入设备入口如未真正写入 controller，应展示 pending/只读状态。
- 输入布局预览点击应跳到真实 `InputLayoutPage`，并保持路由参数与当前设备一致。

### 运行态 gap
- `LOCAL_ONLY`：静态设置状态和本地页面状态可承载。
- `NOT_CONFIGURED`：部分高级渲染/音频设置未证明已接 engine。
- `需真机验证`：渲染、音频、输入设置实际生效需运行验证。

### 结论
部分完成。

## _5 About Help

### 设计目标
- `screen.png` 是关于与帮助页：状态 hero、版本卡、帮助列表、footer 品牌区、底部 System 高亮。
- `code.html` 包含 `Status: Operational`、`Core Version`、`Up Time`、`Documentation & Legal`、四个帮助/版本条目。

### 当前承载
- ETS：`entry/src/main/ets/pages/AboutHelpPage.ets`。
- 路由：`pages/AboutHelpPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 当前 ETS 已承载关于/帮助、版本与 help detail；仍需对齐截图中的大标题字重、版本卡进度条、列表右箭头、footer 分割线和底部品牌块。
- 设计里顶部是 `EMU_CORE_v1.0`，ETS 文案已改成更诚实的 libretro 本地能力说明，需要保留真实性同时补齐视觉层级。

### 交互 gap
- 帮助项进入详情或展开态需和页面状态绑定；外链、反馈、法律文档如无真实入口应禁用。
- 底部导航和 System 高亮需与 Settings/Core/Shader 统一。

### 运行态 gap
- `LOCAL_ONLY`：关于信息与帮助内容来自本地页面。
- `NOT_CONFIGURED`：在线文档、反馈、法律链接后端未证明接入。
- `需真机验证`：版本信息来源、路由、外链能力需设备验证。

### 结论
部分完成。

## _6 Input Layout

### 设计目标
- `screen.png` 是虚拟按键布局编辑器：顶部 calibration mode、左上 telemetry 面板、半透明游戏背景、肩键/方向键/动作键虚线选框、底部编辑 dock。
- `code.html` 包含 `Resolution 1920 X 1080`、`Latency 1.2ms`、`Input Poll 1000Hz`、可拖拽按钮、`重置`、`保存`。

### 当前承载
- ETS：`entry/src/main/ets/pages/InputLayoutPage.ets`、`entry/src/main/ets/common/InputLayoutRepository.ets`。
- 路由：`pages/InputLayoutPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按 `_6` 编辑器主态收口：编辑态独立 calibration header、暗化游戏画布感、左上 telemetry panel、肩键/方向键/动作键虚线选框、底部 floating editor dock 和右侧 calibration markers 已对齐首批视觉目标。
- `position({ x: percent, y: percent })` 继续只用于输入热区的逻辑画布百分比坐标，不作为截图绝对坐标补丁；外层画布仍由 `width('100%')`、`constraintSize` 与 `aspectRatio` 控制。

### 交互 gap
- 选择、微调、重置和保存继续绑定 `InputLayoutRepository` 本地 profile；本轮未新增拖拽能力，避免把设计 demo 的 cursor-move 误写成已完成触控拖拽。
- `_6` 保持布局校准编辑器语义，非编辑态入口仍可回到输入中心；多人/外设/Netplay 信息结构留给 `_2` 收口。

### 运行态 gap
- `LOCAL_ONLY`：布局 profile 可写入本地 repository。
- `需真机验证`：真实触控热区、横竖屏、底部 dock 遮挡和保存后 runtime 使用需设备验证。

### 结论
视觉完成；未编译、未预览、未真机。

## _7 Runtime Controller

### 设计目标
- `screen.png` 是游戏运行页：顶部 telemetry bar、全屏游戏背景、左侧 movement panel、右侧动作键 cluster、Quick Save、Select/Start、底部 System 高亮。
- `code.html` 包含 `FPS`、`LAT`、`CORE`、`ROM_LOAD_SUCCESS`、`MAPPING: DEFAULT_HID`、`VIBRATION: ACTIVE`。

### 当前承载
- ETS：`entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimeTopHudBar.ets`、`entry/src/main/ets/components/RuntimeVirtualControllerLayer.ets`、`entry/src/main/ets/components/RuntimeControlPanel.ets`。
- 路由：`pages/LibretroGamePage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 顶部 compact telemetry、运行画面暗场/scanline、movement 玻璃卡片、动作键 cluster、Quick Save 竖向按钮、Select/Start 和底部 System 高亮已按截图主结构收口。
- 控制面板默认不再作为运行画面主体；仍需真机确认 Quick Save 右侧驻留按钮与不同窗口宽度下的手柄间距。

### 交互 gap
- 虚拟方向键、A/B/X/Y、Select/Start 继续调用真实 runtime input binding；Quick Save 继续绑定 `RuntimeSaveStateController`，不是假 UI 状态。
- `code.html` 的 telemetry 展开/隐藏和拖拽 Quick Save 未作为本轮运行逻辑引入，避免伪造未接入交互。

### 运行态 gap
- `需真机验证`：XComponent 画面、帧率、音频、输入、暂停、存档和实际 core 运行只能设备验证。
- `NOT_CONFIGURED`：震动、部分 overlay 工具若未接 native 能力，不应显示为可用。

### 结论
视觉完成。

## _8 Save State

### 设计目标
- `screen.png` 是存档管理页：顶部存储摘要、slot 列表、首项左滑 actions、云同步提示、底部 archive empty block、删除确认状态在 `code.html` 中存在。
- `code.html` 包含 `Storage: 42.8GB Free`、`Slots: 14/99`、`正在同步至云端`、`读档`、`删除`、delete modal 和 success toast。

### 当前承载
- ETS：`entry/src/main/ets/pages/SaveStatePage.ets`、`entry/src/main/ets/common/SaveStateRepository.ets`。
- 路由：`pages/SaveStatePage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按 `_8` 主体存档页收口：顶部 header、三列本地归档摘要、首项 swipe action 露出宽度、slot 缩略图比例、右侧时间/drag handle 和底部虚线 archive block 已对齐首批视觉目标。
- 截图里部分图片资源带有占位/错误图状态；ETS 继续使用本地 fallback 缩略块，不沿用设计导出远程图片资源。

### 交互 gap
- quick save、load、delete、refresh 需要与当前 ROM 参数和 repository 绑定；滑动删除不能破坏列表稳定 key。
- 云同步文案若无后端必须改为本地归档或未配置状态。

### 运行态 gap
- `LOCAL_ONLY`：本地存档 manifest/repository 可承载。
- `NOT_CONFIGURED`：云同步未配置。
- `需真机验证`：读档/写档、缩略图、文件权限、删除结果需设备验证。

### 结论
视觉完成。

## _9 Pause Overlay

### 设计目标
- `screen.png` 是暂停菜单页：顶部 telemetry、主标题、Resume 大 CTA、四宫格 quick save/load/input/filter、terminate session、subsystem telemetry。
- `code.html` 同时包含桌面侧栏 class 和移动主菜单；截图实际展示移动主菜单。

### 当前承载
- ETS：`entry/src/main/ets/pages/LibretroGamePage.ets`、`entry/src/main/ets/components/RuntimePauseOverlay.ets`。
- 路由：`pages/LibretroGamePage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按 `_9` 移动主菜单态收口：顶部 telemetry bar、左侧绿线标题、Resume 大 CTA、四宫格 action cards、红色 terminate 区域、右侧绿色暗光和 subsystem telemetry 波形/网格已对齐首批视觉目标。
- 设计存在侧栏菜单结构，但截图实际展示移动主菜单；本轮未引入桌面侧栏，避免同时堆叠两套导航。

### 交互 gap
- Resume/stop 可走真实 runtime；quick save/load/input/filter 的可用性必须按能力状态显示。
- input mapping 与 visual filters 若跳转到其它页，应保留当前 runtime 参数或明确不可用。

### 运行态 gap
- `NOT_CONFIGURED`：filter、部分 save/load 快捷能力若未接 native，应显示未配置。
- `需真机验证`：暂停/恢复/停止对 engine 状态的影响需设备运行验证。

### 结论
视觉完成。

## _10 Library Detail

### 设计目标
- `screen.png` 是游戏详情页：云存档 toast、封面 hero、Launch Game CTA、两个 quick action、metadata grid、system telemetry、overview、core specs。
- `code.html` 还包含 loading overlay 状态：`正在加载你的童年`、`CHRONO_TRIGGER.ISO`、进度和 kernel load。

### 当前承载
- ETS：`entry/src/main/ets/pages/LibraryDetailPage.ets`、`entry/src/main/ets/components/LibraryDetailHeroPanel.ets`、`entry/src/main/ets/components/LibraryDetailInfoPanel.ets`、`entry/src/main/ets/components/LibraryLaunchOverlay.ets`。
- 路由：`pages/LibraryDetailPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按 `_10` 主体详情页收口：顶部状态胶囊改为本地资料/运行记录语义，hero 封面边框、Launch Game 绿色 glow CTA、quick action、metadata 三列、telemetry 网格和 overview 灰底文本块已对齐首批视觉目标。
- 剩余视觉风险只在真机侧确认：封面资源裁切、窄屏长标题、telemetry 折线密度、底部导航遮挡和 loading overlay 动效节奏。

### 交互 gap
- Launch -> Runtime 参数、启动 overlay 进度、编辑元数据、返回库页和 quick action toast 需要按真实 route/repository 复核。
- `code.html` 的 loading overlay 是状态外壳，触发机制必须来自真实 launch 流。

### 运行态 gap
- `LOCAL_ONLY`：metadata、library record、runtime snapshot 可来自本地 repository。
- `NOT_CONFIGURED`：云存档同步未配置。
- `需真机验证`：游戏启动、runtime 写回、封面资源和 launch overlay 结束条件需设备验证。

### 结论
视觉完成。

## _11 Library Context Menu

### 设计目标
- `screen.png` 是库页长按/更多菜单弹层态：背景库页被强暗化/模糊，中央 action sheet 包含启动、详情、修改封面、删除存档，底部独立 Cancel。
- `code.html` body 开头就是 fixed overlay 与 action menu，后面才是被遮罩的库页内容。

### 当前承载
- ETS：`entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets`。
- 路由：`pages/LibraryPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按 context menu 弹层态收口：action sheet 宽度、圆角、行高、分割线、图标尺寸、删除项红色层级、背景 blur/dim 强度和独立 Cancel 已对齐首批视觉目标。
- 剩余视觉风险只在真机侧确认：背景模糊强度、遮罩暗度和窄屏下 action sheet 文案换行。

### 交互 gap
- 启动、详情、修改封面、删除存档、取消都需要分区点击；遮罩点击关闭需避免误触底层卡片。
- 删除存档不应直接伪成功，需进入确认或真实删除流程。

### 运行态 gap
- `LOCAL_ONLY`：弹层显示和库记录上下文可本地证明。
- `NOT_CONFIGURED`：修改封面如果未完整接 picker/裁剪/持久化，应显示未配置或进入真实编辑页。
- `需真机验证`：长按/菜单触发、遮罩命中测试、启动/详情路由需设备验证。

### 结论
视觉完成；未编译、未真机。

## _12 Library Home

### 设计目标
- `screen.png` 是库页主体：顶部终端栏、搜索框、CPU/FPS/MEM telemetry、平台 chips、最近运行双卡、全部游戏列表、loading assets、底部 Library 高亮。
- `code.html` 同时包含 hidden success bubble 和 context sheet，但截图主要验收库页主体态。

### 当前承载
- ETS：`entry/src/main/ets/pages/LibraryPage.ets`、`entry/src/main/ets/components/LibrarySearchPanel.ets`、`entry/src/main/ets/components/LibraryGameSections.ets`、`entry/src/main/ets/components/LibraryContextMenuOverlay.ets`。
- 路由：`pages/LibraryPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已按库页主体态收口：sticky header、搜索框高度、telemetry strip 三列、平台 chip、最近运行横向卡、全部游戏行、bottom loading spinner 和底部导航维持 `_12` 主体层级。
- 剩余视觉风险集中在真机滚动密度、封面资源加载效果和长标题截断。

### 交互 gap
- 搜索、平台过滤、卡片进入详情、长按/菜单入口、刷新 toast、底部 loader 都应由真实 repository 和页面状态驱动。
- `code.html` 中 hidden context sheet 可作为 `_11` 的弹层参考，不应混入 `_12` 主体验收结论。

### 运行态 gap
- `LOCAL_ONLY`：库索引、搜索过滤和最近运行来自本地 repository。
- `需真机验证`：封面加载、文件扫描、刷新、长按菜单、滚动性能和路由需设备验证。

### 结论
视觉完成；未编译、未真机。

## _13 Import Entry

### 设计目标
- `screen.png` 是导入空态入口：顶部 `NETWORK: ONLINE`、背景网格/粒子、中心 eject 卡、标题、说明、导入按钮、合法拥有提示、底部 Library 高亮。
- `code.html` 包含隐藏的扫描状态 `正在扫描本地文件... 0%`，但截图是待机空态。

### 当前承载
- ETS：`entry/src/main/ets/pages/ImportEntryPage.ets`、`entry/src/main/ets/components/ImportEmptyStateHero.ets`。
- 路由：`pages/ImportEntryPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已收口空态 hero、背景粒子、导入按钮和扫描状态字段：中心卡尺寸、标题/说明密度、按钮宽度和脚注已贴近截图。
- 顶部 `NETWORK: ONLINE` 已改为 `LOCAL_ONLY`，避免在无云端/网络能力时造成运行态误导。

### 交互 gap
- 导入按钮应启动系统 picker / import service handoff；扫描进度只能来自真实任务或诚实待机态。
- 如果已有游戏则跳转库页的逻辑需确认不会绕过空态验收。

### 运行态 gap
- `LOCAL_ONLY`：本地文件导入入口与沙箱复制链路可静态接入。
- `需真机验证`：picker 权限、URI 访问、导入任务创建和库页刷新需设备验证。

### 结论
视觉完成；未编译、未真机。

## _14 Import Task Overlay

### 设计目标
- `screen.png` 是导入任务执行弹层态：背景主界面强 blur/dim，底部偏中的进度面板，`Executing Task`、`正在导入 1/3`、ETA、progress、source、transfer rate、cancel、process footer。
- `code.html` 还包含 success/error/conflict 三态，截图验收的是 importing 态。

### 当前承载
- ETS：`entry/src/main/ets/pages/ImportTaskOverlayPage.ets`、`entry/src/main/ets/common/RomImportService.ets`、`entry/src/main/ets/common/ImportTaskBridge.ets`。
- 路由：`pages/ImportTaskOverlayPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已收口 importing/success/error/conflict 多态外观：system load 背景、强 dim/blur、进度面板宽度、progress 条、footer status 和 Cancel 按钮尺寸已贴近截图。
- `code.html` 的 `Source: EXT_DISK_A`、`24.4 MB/s`、`33%` 演示值已从初始状态移除；ETS 保持真实导入进度或 `LOCAL_PICKER` / 空任务状态。

### 交互 gap
- cancel、retry、return library、conflict overwrite/skip 需全部来自真实 import task 状态机。
- 没有 pending task 时应显示 `NO_PENDING_IMPORT_TASK` / 诚实空态，而不是播放 fake importing。

### 运行态 gap
- `LOCAL_ONLY`：本地导入 task、冲突处理和沙箱复制可静态承载。
- `需真机验证`：picker 后任务进度、文件复制、冲突、取消、失败重试和返回库页需设备验证。

### 结论
视觉完成；未编译、未真机。

## _15 Onboarding

### 设计目标
- `screen.png` 是首屏引导 step 1：顶部 boot sequence、背景 grid、中心 game icon、标题、说明、主按钮、三列 status/module/latency、底部 build 文案。
- `code.html` 包含两步：step 1 启动引导，step 2 授权说明；有 `transition-page`、grid background、corner accents、scan-line 等效果。

### 当前承载
- ETS：`entry/src/main/ets/pages/OnboardingPage.ets`。
- 路由：`pages/OnboardingPage` 已在 `main_pages.json` 注册。

### 视觉 gap
- 已收口两步引导、核心文案、grid/scanline 状态和权限说明：顶部 glass/blur、中心 icon 卡、corner accents、按钮边框、三列 status spacing 和 step transition 已对齐首批视觉目标。
- 剩余视觉风险在真机侧确认：不同窗口尺寸下的大标题换行、底部 build 文案暗度和 step 2 面板高度。

### 交互 gap
- step 1 到 step 2 的过渡节奏需按 `code.html` 的状态外壳参考实现，但触发必须来自真实用户操作。
- 授权入口当前应跳导入器或库页；如果不直接请求权限，需要把 copy 与系统 picker 机制保持一致。

### 运行态 gap
- `LOCAL_ONLY`：引导步骤、路由和本地导入入口可静态证明。
- `NOT_CONFIGURED`：云端库、映射驱动器和媒体 metadata 授权若未接入，copy 不应暗示已完成。
- `需真机验证`：首次启动路由、系统 picker/权限、动画表现和不同窗口尺寸需设备验证。

### 结论
视觉完成；未编译、未真机。

## 汇总

- 15 个设计目录均完成 `screen.png` + `code.html` + ETS/路由三方静态对照。
- `_11` / `_12` 发现矩阵摘要语义需要修正：`_11` 是库页 context menu 弹层态，`_12` 是库页主体态。
- 第一批 `_15` / `_13` / `_14` / `_12` / `_11` 已完成 ArkTS 视觉收口；仍按本轮约束保留未编译、未预览、未真机验证状态。
- 本轮未编译、未预览、未真机运行；所有 runtime 结论仅限静态可证据范围。
