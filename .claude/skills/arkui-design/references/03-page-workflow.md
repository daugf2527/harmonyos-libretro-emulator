# 03 — 5 步页面落地流程 / HTML→ArkUI 转换 / 设计 token 与自适应边界

## 页面开发流程

### 第一步:页面结构树

至少输出:
- `PageScaffold`
- `SafeTopArea` / `Header`
- `MainContent` / `ScrollContent`
- `BrandSection` / `CardSection` / `ListSection` / `BottomArea`(按需)

### 第二步:组件拆分方案

优先拆出:
- `PageScaffold`
- `SafeHeader` / `BrandHeader`
- `InfoCard` / `SectionBlock`
- `SettingList` / `SettingListItem`
- `ActionRow` / `FooterArea`
- `ResponsiveContainer` / `AdaptiveGridSection`(按需)

### 第三步:样式 token

分类输出:
- colors / text sizes / icon sizes
- radius / spacing
- shadows / line styles
- button heights

### 第四步:断点与容器决策

必须先判断:
- 页面是否只需单列
- 是否需要 `md` / `lg` 双列或三列
- 是否属于列表、网格、瀑布流、分栏导航,是否需要窗口变化监听与 `LazyForEach`
- 是否需要资源限定词支持深浅色、方向或设备类型差异

### 第五步:ArkTS / ArkUI 代码

- 最后才输出代码

## HTML/CSS 到 ArkUI 的转换规则

- `flex column` -> `Column`
- `flex row` -> `Row`
- `flex: 1` -> `layoutWeight(1)` 或等效弹性布局
- `width: 100%` -> 子项宽度跟随父容器,优先由父容器控制
- `justify-content: space-between` -> `justifyContent(SpaceBetween)`
- `align-items: center` -> `alignItems(Center)`
- 重复列表 -> `List + ListItem`
- 大量重复项 -> `List + LazyForEach`
- 绝对定位 -> 优先重构为容器关系,不直接照搬
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
