# Repository Guidelines

> **WARNING: TOP PRIORITY**  
> Default to Chinese responses unless the user explicitly asks for another language.

## 强制规则（与仓库规范同级）
- 官方优先：不确定即查华为鸿蒙官方文档与 libretro 官方标准/`libretro.h`，禁止凭经验猜测 API 行为。
- 文档抓取：华为开发者文档为 SPA，需抓取渲染结果时使用 `firecrawl_scrape`。
- NativeBuffer：访问 NativeWindow buffer 像素内存必须走 `OH_NativeBuffer_FromNativeWindowBuffer` + `OH_NativeBuffer_Map/Unmap` 流程，禁止直接对 BufferHandle 使用 `mmap/munmap`。
- 线程同步：VSync 回调线程与主线程/ArkTS 共享状态必须用 `std::mutex + std::lock_guard` 保护，且同一状态统一锁边界。
- 日志规范：日志域使用 `0xD000-0xFFFF`；重定义前先 `#undef LOG_DOMAIN`；数值日志使用 `%{public}d/%{public}u/%{public}X`。
- ArkTS/NAPI：返回匿名对象必须定义显式 `interface` 类型，避免 `Object/any`；跨语言数值建议 `Number()` 显式转换。
- NativeWindow：避免强制设置 `SET_TIMEOUT=5`；如需设置，使用默认或 >= 1 帧周期。
- 交互偏好：不写测试脚本；不编译/不运行（用户自己执行）。
- 交互要求：若环境提供三术 `mcp4_zhi` 工具，则所有询问/确认通过该工具进行。
- 约定：旧架构（`deprecated/legacy/`）不参与后续检索与代码编辑（除非用户明确要求）。

## ArkTS 编程规范（华为官方，检查要求）
- 命名：类/枚举/命名空间用 UpperCamelCase；变量/方法/参数用 lowerCamelCase；常量/枚举值全大写+下划线；布尔名避免否定，优先 is/has/can/should 前缀；标识符用清晰英文，避免单字母/非标准缩写/中文拼音。
- 格式：只用空格缩进，禁 Tab；建议 2 空格（续行 4 空格）；行宽≤120；if/for/while 等建议有大括号；switch case/default 缩进一层且语句再缩进。
- 换行与空格：换行时操作符放行末；一行只声明/赋值一个变量；关键字与 ( 之间空格、函数名与 ( 无空格；else/catch 与前 } 同行且有空格；{ 前加空格（对象字面量首参/模板字符串例外）；二元/三元运算符两侧空格；逗号后空格且逗号/分号前不空格；数组 [] 内无空格；避免连续多空格。
- 字面量与块风格：字符串建议单引号；对象字面量属性>4 个需全部换行；大括号与语句同一行。
- 编程实践：类属性建议显式访问修饰符；浮点数小数点前后不省略 0；判断 NaN 必须用 `Number.isNaN()`；数组遍历优先 Array 方法；控制条件中不做赋值；finally 中禁止 return/break/continue/throw；非跨语言场景避免 `ESObject`；数组类型建议用 `T[]`。

## Codebase Overview (High Level)
- Core emulation/libretro engine code is under `entry/src/main/cpp/core/`.
- HarmonyOS platform adapters live under `entry/src/main/cpp/platform/` (audio/graphics/xcomponent/sync).

## 运行链路图（含调用顺序与线程标注）

### 新架构链路（LibretroEngine + VideoPipeline）
```
[ArkTS/UI 线程]
XComponent.onLoad (new_arch*/phase1*) 
  -> libentry.so (NAPI 初始化 + PluginManager::Export)
  -> 注册 XComponent 回调（Surface/Touch/Key/Mouse）

[XComponent 回调线程]
SurfaceCreated/Changed
  -> LibretroEngine::SetNativeWindow
  -> LibretroEngine::OnNativeWindowResized
  -> Engine 消息队列: WindowCreated

[ArkTS/UI 线程]
refactoredStartEngine / refactoredLoadCore / refactoredLoadRom
  -> libretro_engine_napi.cpp
  -> LibretroEngine::Start / LoadCore / LoadGame
  -> Engine 消息队列: Start / LoadCore / LoadRom

[Engine 线程: LibretroEngine::GameLoop]
HandleMessage(LoadCore)
  -> CoreLoader::LoadCore (dlopen/dlsym)
  -> SetupCallbacks (env/video/audio/input)
  -> retro_init / retro_get_system_info
HandleMessage(LoadRom)
  -> retro_load_game
  -> retro_get_system_av_info
  -> AudioBridge::Reset(sample_rate)
  -> TransitionTo(RUNNING)

[Engine 线程]
ProcessFrame
  -> retro_run
  -> retro_video_refresh -> LibretroEngine::OnVideoRefresh
     -> VideoPipeline::Render (CPU/GLES)
  -> retro_audio_sample_batch -> AudioBridge::ProcessAudio

[渲染路径 - CPU/GLES]
CPU: OH_NativeWindow_RequestBuffer -> Map -> PixelConverter -> Flush
GLES: GLESRenderer::Init/Render -> SwapBuffers

[音频线程 / OHAudio 回调线程]
AudioPlayer::OnWriteDataCallback
  -> RingBuffer::Read (不足则静音)

[输入路径]
ArkTS 虚拟手柄 / 键盘 / 触控
  -> refactoredSendInput / PluginManager 指针/键盘回调
  -> InputManager::SendInput/SendPointer
  -> Libretro input_poll/input_state 回调读取 InputSnapshot
```

## Project Structure & Module Organization
- `entry/src/main/ets/`: ArkTS UI and routing (pages, abilities, interfaces).
- `entry/src/main/cpp/`: Native C++ implementation (framework, platform, input, NAPI bindings).
- `entry/src/main/cpp/tests/`: Native test helpers for core loading and ROM checks.
- `entry/src/main/resources/`: App resources, assets, and raw files.
- `AppScope/`: App-level resources and configuration.
- `docs/`, `README*.md`, `Roadmap.md`: Design notes and usage references.
- `entry/build/` and `entry/build-profile.json5`: generated outputs; do not edit by hand.

## Commit & Pull Request Guidelines
- Commit history mixes short Chinese summaries and Conventional Commit-style subjects (e.g., `refactor(build): ...`).
- Use a concise, imperative summary; optionally add a `type(scope):` prefix when it helps clarity.
- PRs should include: what changed, how it was validated (device + HarmonyOS version), and screenshots for UI changes.

## Configuration Tips
- Local SDK/NDK paths are machine-specific (see the shell scripts); avoid committing local paths or `entry/build/` artifacts.

## 图形 API 现状（官方文档要点，精简版）
- Vulkan：SDK 支持 v1.4.309，具体可用版本依赖 GPU 驱动；OHOS 扩展支持 OHNativeWindow/OH_NativeBuffer 互操作。
- OpenGL（桌面）：API version 20 支持 OpenGL 3.0，API version 22 支持 OpenGL 4.2；仅明确 PC/部分 Tablet，需 OH_Graphics_QueryGL 判断。
- OpenGL ES：HarmonyOS 支持 OpenGL ES 3.2；扩展需在上下文初始化后通过 glGetString 查询。
- 手机端：OH_Graphics_QueryGL 返回空，不能假设有桌面 OpenGL 3.x，应默认 GLES/Vulkan 路径。
**“所有 EGL/GL 操作只在 Engine 线程执行”**原则，这是移动端图形开发的金科玉律。只要守住这条线，90% 的崩溃都能避免

## 鸿蒙模拟器能力判断（需共识）
- 平台定位：按“移动端 ARM 平台”处理，默认 Egl + OpenGL ES，Vulkan 视设备支持。
- 性能硬约束：系统禁 JIT/dynarec（不是 LLVM 问题），HW_RENDER 只解决“能出画面”，不等于性能可玩。
- 可覆盖范围：8/16 位主机、GB/GBC/GBA、NDS、PS1、街机等可用。
- 不可期待范围：N64/PSP/DC/Saturn 多数只能勉强运行或不可玩；PS2/3DS/GC/Wii 基本不可行（依赖 dynarec）。
- 核心要求：必须具备 GLES/Vulkan 后端，不能只依赖桌面 OpenGL。


# ArkUI / ArkTS Development Guidelines

## 核心定位
- 目标不是截图式还原，而是把蓝湖设计稿、导出的 HTML/CSS、页面预览图转化为符合 HarmonyOS 技术体系的 ArkUI / ArkTS 页面与组件
- 你的角色是“设计语义提取器 + 鸿蒙组件生成器”，不是“逐像素截图修补器”

## 总目标
1. 视觉接近设计稿
2. 代码符合 HarmonyOS / ArkUI / ArkTS 技术体系
3. 支持不同窗口尺寸、安全区、状态栏、横竖屏和多设备适配
4. 组件可复用、可维护、可扩展
5. 禁止通过固定 `top` / `left` / `marginTop` / `offset` 对截图

## 输入材料使用规则
1. 蓝湖稿只作为视觉参考，不做逐像素翻译
2. HTML/CSS 只作为结构和样式参考，不直接等价映射到 ArkUI
3. 预览图只用于校验视觉层级和风格，不作为运行时坐标依据

## 设计稿、HTML 与业务状态的职责边界
- 最终落地原则：`HTML` 负责状态外观，业务代码负责状态来源，截图负责静态结果验收。
- `screen.png` / 设计截图用于定义“某个状态停在某一帧时最终应长什么样”，重点校验字号、间距、层级、颜色、边框、阴影、元素有无。
- `code.html` 用于定义“状态切换时如何表现”，重点参考结构、交互形式、动效风格、反馈节奏和显隐关系；不要把其中的 demo 数据、随机数、固定定时器直接搬进正式实现。
- 业务代码必须绑定真实事件、真实数据和真实流程；禁止为了贴近 demo 演示效果而制造假状态、假 telemetry、假定时触发或与产品逻辑无关的自动流程。
- 当截图与 HTML 冲突时：
- 静态最终态以截图为准。
- 动效与交互表现以 HTML 为参考。
- 状态进入、退出、数据内容和触发条件以真实业务逻辑为准。
- 对详情页、启动页、菜单态等页面，允许复用 HTML 的“状态外壳”，但必须把触发机制替换为真实状态机；不要把 demo 模式直接当产品逻辑。

## 技术基线与布局原则

### 布局单位
- 布局、间距、圆角、图标尺寸优先使用 `vp`
- 字体优先使用 `fp`
- 不要批量沿用 HTML/CSS 的 `px`
- 不要把 `lpx` 作为主布局单位
- 不带单位的数值默认按 `vp` 处理

### 安全区原则
- 普通内容默认放在安全区内
- 只允许背景层延展到安全区外
- 不允许手写 `paddingTop` / `marginTop` / `top` 模拟状态栏避让
- 顶部状态栏、底部安全区、软键盘避让优先使用系统能力

### 响应式原则
- 页面不能默认只有手机竖屏
- 必须显式考虑断点、窗口尺寸变化和多设备宽度变化
- 可使用媒体查询、窗口尺寸变化监听或 ArkUI 响应式组件能力
- 不要为了贴合单张预览图破坏响应式布局

### 容器选型原则
- 单列普通内容：优先 `Column` / `Row`
- 列表页：优先 `List + ListItem`
- 大列表：优先 `List + LazyForEach`
- 页面级多列/分栏：优先 `GridRow` / `GridCol`
- 重复网格卡片：优先 `Grid`
- 瀑布流：优先 `WaterFlow`
- 单栏或双栏导航：优先 `Navigation`
- 侧边导航：优先 `SideBarContainer`
- 底部或侧边导航切换：优先 `Tabs`
- 复杂兄弟锚定：优先 `RelativeContainer`
- 叠层：优先 `Stack`

## 页面开发流程

### 第一步：页面结构树
至少输出：
- `PageScaffold`
- `SafeTopArea` / `Header`
- `MainContent` / `ScrollContent`
- `BrandSection` / `CardSection` / `ListSection` / `BottomArea`（按需）

### 第二步：组件拆分方案
优先拆出：
- `PageScaffold`
- `SafeHeader` / `BrandHeader`
- `InfoCard` / `SectionBlock`
- `SettingList` / `SettingListItem`
- `ActionRow` / `FooterArea`
- `ResponsiveContainer` / `AdaptiveGridSection`（按需）

### 第三步：样式 token
分类输出：
- colors / text sizes / icon sizes
- radius / spacing
- shadows / line styles
- button heights

### 第四步：断点与容器决策
必须先判断：
- 页面是否只需单列
- 是否需要 `md` / `lg` 双列或三列
- 是否属于列表、网格、瀑布流、分栏导航，是否需要窗口变化监听与 `LazyForEach`
- 是否需要资源限定词支持深浅色、方向或设备类型差异

### 第五步：ArkTS / ArkUI 代码
- 最后才输出代码

## HTML/CSS 到 ArkUI 的转换规则
- `flex column` -> `Column`
- `flex row` -> `Row`
- `flex: 1` -> `layoutWeight(1)` 或等效弹性布局
- `width: 100%` -> 子项宽度跟随父容器，优先由父容器控制
- `justify-content: space-between` -> `justifyContent(SpaceBetween)`
- `align-items: center` -> `alignItems(Center)`
- 重复列表 -> `List + ListItem`
- 大量重复项 -> `List + LazyForEach`
- 绝对定位 -> 优先重构为容器关系，不直接照搬
- 页面多列区块 -> `GridRow` / `GridCol`
- 重复卡片阵列 -> `Grid`
- 侧边导航或双栏布局 -> `Navigation` / `SideBarContainer` / `Tabs`

## 设计 token 与自适应边界

### 可固定的值
- 图标尺寸
- 字号
- 字重
- 颜色
- 圆角
- 卡片内边距
- 行高
- 分割线
- 阴影
- 按钮高度

### 不可固定的值
- 顶部安全区高度
- 页面内容起始高度
- 品牌区距顶部的绝对距离
- 卡片区通过 `marginTop` 推出来的位置
- 箭头、图标、标题的上下微调偏移
- 整页背景图缩放和裁切关系
- 依赖某一张预览图的绝对纵坐标

## 页面与组件规范

### 页面根容器规范
- 页面根容器 `width / height = 100%`
- 背景优先使用 `backgroundColor` 或渐变
- 除非确有复杂视觉需求，否则不要使用整页背景图
- 主内容优先通过 `padding`、section spacing、`layoutWeight`、自适应容器完成布局
- 页面需要滚动时，使用 `Scroll` / `List` 等正确滚动容器，不手写超长静态 `Column`

### 顶部区域规范
- 顶部内容按安全区处理
- `Header` 位置由 `PageScaffold` / `SafeTopArea` 统一控制
- 返回按钮、标题、右操作区在 `Header` 内垂直居中
- 不要出现 `20`、`26.5`、`44` 之类不明顶部补偿值

### 卡片规范
- 卡片使用 `width('100%')`
- 卡片宽度由父容器左右留白控制
- 卡片内部通过 `padding` 控制内容留白
- 卡片之间使用统一 section spacing
- 不在子组件里写死横向宽度和偏移去凑版式

### 列表项规范
- 设置项、菜单项、信息项优先使用 `List + ListItem`
- 左图标固定尺寸
- 中间文字区占剩余空间
- 右箭头固定尺寸并垂直居中
- 不允许 `arrowTop` / `arrowBottom` / `iconOffsetY` / `titleShift`
- 文本过长时优先截断，不要挤压图标和箭头

### 资源与主题规范
- 优先把颜色、间距、圆角抽为 token 或资源
- 系统语义图标优先考虑系统资源 / `Symbol`
- 品牌 logo、插画、产品图才使用媒体资源
- 深浅色、横竖屏、密度、设备类型差异优先通过资源限定词处理
- 不要把主题差异写成组件内部的大量 `if / else`
- 蓝湖导出的图片、图标、插画不得直接从设计目录引用到正式页面代码
- 正式开发使用的资源必须接入 `entry/src/main/resources/base/media/` 后，再通过 `$r('app.media.xxx')` 引用
- 如果设计资源尚未正式接入，代理应先列出缺失资源清单，再判断是否可以开工
- 资源命名应语义化，避免长期保留 `img_1.png`、`group_4.png` 这类蓝湖默认导出名

## 工程级开发约束

### ArkTS 类型与语法约束
- 优先使用显式 `interface` / `class` 定义数据结构，不要在属性、数组或回调参数里写内联对象类型
- 避免滥用 `any`、隐式类型推断和临时拼接的大对象；页面状态、接口数据、列表项数据都应有明确类型
- `@State`、`@Prop`、`@Link` 等装饰变量在声明时必须提供明确类型；需要初始化的状态应提供合理初始值
- 不要在 `ForEach` / `LazyForEach` 的回调参数中声明匿名对象类型；先抽出命名类型再使用
- 跨线程、任务池或并发场景传值时，优先传基础类型或结构明确的可序列化数据；不要传 UI 上下文、组件实例或不可安全共享对象

### 状态管理与组件通信约束
- UI 必须由状态驱动，不要依赖命令式“手动刷新某个组件”的补丁式做法
- 页面私有状态优先使用 `@State`，父传子只读数据使用 `@Prop`，父子双向同步使用 `@Link`，跨层共享状态时才谨慎使用 `@Provide` / `@Consume`
- 不要给 `@Prop` 传函数值；点击事件优先放在父容器，或改用 ArkUI 兼容的状态同步 / 事件通信方式
- 页面组件负责页面级状态、断点和窗口环境；展示组件只负责展示，不持有业务级共享状态
- 不要让叶子组件自行维护页面级状态、路由状态或窗口断点逻辑
- 不要把整页状态塞进一个超大对象再跨层传递；优先拆分为语义明确、边界清晰的小状态

### 页面、路由与导航约束
- 新增页面后，必须同步注册到 `entry/src/main/resources/base/profile/main_pages.json`，否则页面跳转可能表面成功但无法正常展示
- 页面跳转参数必须有明确类型，不要依赖随手拼接的匿名对象透传
- 旧 `router` / `AppRouter` 过渡层已移除；应用内页面导航统一优先使用 `Navigation + NavPathStack`
- `Navigation.hideNavBar(true)` 时，不要让页面栈为空；需要首屏走栈时先 `pushPath`
- 不要把返回 `NavDestination()` 的页面直接当作 `Navigation` 的首屏内容；应通过 `navDestination` builder 渲染
- 根级 `Navigation` 目的地统一显式包 `NavDestination().hideTitleBar(true)`，避免默认 `TitleBar` 干扰并触发白屏
- 页面组件负责路由入口、页面生命周期与页面级数据初始化；不要把路由逻辑下沉到纯展示组件
- 区分“分组标题”和“可点击列表项”，不要默认标题区可点击
- 如果底部区域承担“导航 + 关键操作”的复合职责，应优先封装为公共 Dock 组件，而不是强行套用 `Tabs`
- Dock 中的导航项与中间主操作区应分区点击，避免整条底栏绑定统一点击事件
- 中间主操作区如存在录音、播放、暂停、停止等状态，应由明确枚举驱动，而不是通过多个布尔值堆叠控制
- 公共 Dock 组件在不同页面中的尺寸、圆角、阴影和点击热区应保持一致；页面只负责当前导航态与页面级接入

### 安全区、键盘与焦点约束
- 顶部状态栏、底部安全区、软键盘避让优先使用系统能力，不要手写 magic number 做补偿
- 键盘弹出后需要保持整体布局稳定时，优先使用 `expandSafeArea([SafeAreaType.KEYBOARD])` 等官方能力，而不是手工计算偏移量
- 输入框焦点获取、清除、提交与底部操作区上移，都要通过 ArkUI 官方焦点与键盘机制实现，不要通过延时、位移或额外占位块硬修
- 需要沉浸式背景时，只允许背景层扩展到安全区外；交互内容、标题栏、按钮区默认留在安全区内

### 列表、网格与性能约束
- 长列表默认考虑 `LazyForEach`
- 少量静态项可使用 `ForEach`；中长列表、大数据集、重复网格和瀑布流优先使用 `LazyForEach`
- `ForEach` / `LazyForEach` 的数据项必须提供稳定 key，不要长期使用索引充当业务主键
- `Grid` 配合 `LazyForEach` 使用时，要根据卡片复杂度和滚动密度评估 `cacheCount`，不要默认忽略缓存策略
- 列表和网格优先数据驱动，不要为重复项生成大量重复静态组件代码
- 列表刷新必须走响应式数据更新；不要依赖“重新进入页面”或整页重建来掩盖刷新问题
- 滚动容器中的列表项、卡片项避免做重计算、重复创建重量级对象或层级过深的嵌套结构
- 不要把几十个同构组件手写展开在页面里

### HarmonyOS 6 / API 20+ 适配要求
- 每次升级 `compileSdkVersion`、`targetSdkVersion` 或相关 Kit 版本时，先检查官方 Upgrade Guide、API diff 与已知问题清单，再决定是否直接改代码
- 升级后重点回归：页面跳转、输入法避让、列表滚动、弹窗浮层、自定义导航、图片资源、横竖屏切换和多窗口适配
- 如果应用需要兼容历史版本设备，不能只在最新模拟器或单一设备上验证；必须在目标兼容范围内做关键页面回归
- 自定义组件、二次封装导航栏、列表容器和复杂布局在 SDK 升级后属于高风险区域，优先检查行为变化和属性废弃情况
- 使用字体权重、路由、焦点、弹窗、窗口等系统 API 前，优先确认当前 HarmonyOS SDK 是否实际支持对应枚举值、属性或方法
- 遇到 ArkUI / SDK 兼容性、焦点、命中测试、键盘、导航或系统组件行为问题时，排查顺序固定为：
  - 先查 HarmonyOS 官方文档
  - 再查本机 SDK 声明文件，确认当前工程实际可编译版本与可用 API
  - 最后再改代码，禁止在未核实官方文档和 SDK 类型定义前凭经验猜测 API
- 如果同类 API 存在版本差异，优先选择当前仓库已经验证可编译的写法，不要默认沿用其他平台或历史版本经验
- 出现编译错误时，优先回查 SDK 可用 API 与类型定义；不要继续叠加样式或结构修改去掩盖兼容性问题
- 新增页面或公共组件后，如遇 ArkTS 编译失败，优先排查 `FontWeight`、`Alignment`、`VerticalAlign`、`ImageFit`、路由 API 等系统枚举或属性是否与当前 SDK 兼容，再判断是否是布局或业务代码问题
- 不要想当然使用 `FontWeight.SemiBold`、`FontWeight.Black`、`Alignment.TopCenter`、`Alignment.BottomCenter`、`VerticalAlign.Start` 等当前仓库 SDK 可能并不存在的写法
- 遇到这类兼容性报错时，先采用当前工程已验证可编译的最小替代写法，例如 `FontWeight.Medium`、`FontWeight.Bold`、`Alignment.Top`、`Alignment.Bottom`、`VerticalAlign.Center`，通过编译后再做视觉微调
- 当蓝湖静态稿转 ArkUI 页面时报错，不要一边继续堆布局一边猜 API；应先把系统枚举、装饰器约束和资源引用方式校正到当前 SDK 可用范围，再继续页面还原
- 对弹层、分享卡片、Dock、引导浮层这类自定义 UI，首次落地时优先做一个最小可编译版本，再逐步补视觉细节；不要在未验证 SDK 枚举可用性的前提下一次性堆完全部样式

### 蓝湖 750 设计稿换算与 ArkUI 落地规则
- 对导出 CSS 中的绝对坐标与补偿值，应只把它们当作视觉参考，不得直接平移到 ArkUI；必须改为 `Column`、`Row`、`Stack`、`List`、`GridRow` 等容器关系重建布局
- 字号优先级：设计标注值（iOS / Android / 蓝湖开发标注）高于导出 CSS 值；若已拿到设计标注，应优先使用标注值，不再机械依赖导出 CSS 中的字号
- 当导出 CSS 值与设计标注值冲突时，字体、行高、关键图标尺寸优先采用设计标注；导出 CSS 主要用于确认信息层级、相对比例和模块结构
- ArkUI 落地时，布局、间距、尺寸、圆角优先使用 `vp`；字体优先使用 `fp`；不要把导出 HTML/CSS 的 `px`、`rem` 或脚本换算值直接原样搬进 ArkTS
- `/2` 只是候选换算，不是最终真值；落地后仍需通过真机或预览验证长文本挤压、按钮宽度、底部 Dock 遮挡、安全区、横竖屏与多设备宽度下的显示稳定性
- 如果页面在 `/2` 后仍出现文案溢出、卡片被按钮挤压、图标与文字基线不齐等问题，应优先调整容器分配、`layoutWeight`、`maxLines`、`textOverflow`、区块间距与组件结构，而不是继续对单个数值做截图补丁式微调

## 反模式与禁止事项

### 危险信号识别
如果现有代码或 HTML/CSS 中出现下面任一情况，应直接判定为“需要重构”，而不是继续微调：
- 顶部有 `26.5` / `44` 之类奇怪补偿值
- 品牌区、卡片区靠多个 `marginTop` 顶出来
- 背景是一整张纯色底图
- 箭头需要单独做上下偏移
- 同一个页面复制成多个版本
- 子项宽度和偏移大量写死
- 为通过预览图验收而加多个小数值
- 明明是列表却手写一堆 `Row`
- 明明是大列表却不用 `LazyForEach`
- 明明需要分栏却靠 `margin` 和 `width` 百分比硬拼

### 工程硬性禁止项
- 禁止逐像素翻译蓝湖稿
- 禁止把 HTML/CSS 的 `absolute` 直接照搬为 ArkUI
- 禁止固定 `paddingTop` / `marginTop` / `top` 模拟安全区
- 禁止用整页背景图充当纯色背景
- 禁止用 `arrowTop` / `arrowBottom` / `iconOffsetY` / `titleShift` 这类微调参数对截图
- 禁止在子组件中写死宽度，再靠 `margin` 去拼位置
- 禁止复制多个近似页面文件而不抽组件
- 禁止以单一手机截图为唯一适配标准
- 禁止给 `@Prop` 传函数
- 禁止新增页面后遗漏 `main_pages.json` 注册
- 禁止在 ArkTS 中书写内联对象类型并依赖其通过编译
- 禁止使用索引作为长期稳定 key 渲染业务列表
- 禁止在键盘弹出、状态栏避让、底部安全区场景中手写补偿值修布局
- 禁止用频繁重建页面、重复 `push` / `replace` 路由或整树刷新掩盖状态管理问题

## 最终输出要求
请严格按以下顺序输出：
1. 页面结构树
2. 组件拆分方案
3. 样式 token 列表
4. 断点与容器选型说明
5. ArkTS / ArkUI 代码
6. 固定值与自适应值说明
7. 你移除了哪些“截图补丁式参数”
8. 你为什么选择当前的 ArkUI 容器和技术路径

## 优先级
优先保证：
1. 安全区正确
2. 多设备 / 多窗口适配正确
3. 容器选型正确
4. 组件复用正确
5. 视觉接近设计稿
