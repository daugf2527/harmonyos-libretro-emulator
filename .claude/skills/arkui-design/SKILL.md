---
name: arkui-design
description: |
  ArkUI / ArkTS 页面落地与组件设计规范。Use when 改 entry/src/main/ets/ 下的 .ets 文件、做蓝湖/HTML/截图→ArkUI 转化、写新页面/组件、踩 ArkUI 安全区/响应式/状态管理坑、SDK 升级 ArkTS 兼容性问题。NOT for 改 cpp/napi/audio/video 或 docs。CRITICAL: 仅在确认任务涉及 ets/ 时加载,纯 cpp/native 任务不要触发。
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Edit, Write
trigger: |
  Read 或 Edit entry/src/main/ets/**/*.ets / 用户说"做页面 / 还原稿 / 适配 / 重构 UI / 蓝湖 / HTML 转 ArkUI / 安全区 / 响应式 / 键盘避让"
---

# arkui-design — ArkUI / ArkTS 设计落地规范

## 核心信条(常驻,~10 行)

1. 目标是**设计语义提取 + 鸿蒙组件生成**,不是逐像素截图修补
2. 蓝湖 / HTML / 截图三者职责:HTML 状态外观、业务代码状态来源、截图静态结果验收
3. 主结构走 `Column / Row / Stack / List / Grid + layoutWeight + constraintSize`,**禁止** `top/left/marginTop/translate/offset` 对截图
4. 布局/间距/圆角用 `vp`,字体用 `fp`,**不要** 沿用 HTML px / lpx
5. 顶部/底部安全区、键盘避让走系统能力,**不要** 手写 `paddingTop/marginTop` magic number
6. 列表用 `List + ListItem`(长列表 `LazyForEach`+ 稳定 key),网格用 `Grid`,导航用 `Navigation/Tabs/SideBarContainer`
7. 新增页面后**必须** 注册 `entry/src/main/resources/base/profile/main_pages.json`
8. 状态驱动 UI;**禁止** 给 `@Prop` 传函数;页面状态用 `@State`,只读父传子用 `@Prop`,双向用 `@Link`
9. 异步加载/定时器/跨页回写页面**必须** 用 `PageLifecycleGuard` 模板(token + cleanup)
10. SDK 兼容性问题:先查华为官方文档 → 再查本机 SDK 头 → 再改代码(枚举如 `FontWeight.SemiBold`/`Alignment.TopCenter` 在当前 SDK 可能不存在)

## 何时调用本 skill

| 触发场景 | 必读 reference |
|---|---|
| 蓝湖稿 / HTML / 截图 → ArkUI 落地 | `references/01-core-rules.md` + `references/03-page-workflow.md` + `references/06-anti-patterns.md` |
| 写新页面 / 重构页面 | `references/02-layout-and-units.md` + `references/04-component-rules.md` |
| 调状态管理 / 路由跳转 / 生命周期 | `references/05-engineering-constraints.md` |
| SDK 升级 / 编译报错 ArkTS 兼容性 | `references/05-engineering-constraints.md`(SDK 适配段) |
| 蓝湖 750 设计稿换算 | `references/05-engineering-constraints.md`(蓝湖换算段) |
| 反模式快速识别(代码 review) | `references/06-anti-patterns.md` |

## 5 步页面落地标准流程

蓝湖 / HTML / 截图 → ArkUI 任务**必须** 按此顺序输出,普通修 bug/查代码不强制:

1. **页面结构树**(PageScaffold / SafeTopArea / MainContent / 各 Section)
2. **组件拆分方案**(SafeHeader / InfoCard / SettingList / FooterArea 等)
3. **样式 token 列表**(colors / sizes / radius / spacing / shadows)
4. **断点与容器选型说明**(单列 / md/lg 双列 / List / Grid / WaterFlow / Navigation)
5. **ArkTS / ArkUI 代码**

输出后追加:
- 固定值与自适应值说明
- 移除了哪些"截图补丁式参数"
- 为什么选择当前 ArkUI 容器和技术路径

详见 `references/03-page-workflow.md`。

## 优先级(冲突时遵循)

1. 安全区正确
2. 多设备 / 多窗口适配正确
3. 容器选型正确
4. 组件复用正确
5. 视觉接近设计稿(放最后是因为前 4 项错了再像也是技术债)

## 静态扫描命令(改完 UI 必跑)

```bash
rg -n "\.position\(|\.markAnchor\(|\.translate\(|\.offset\(|\.width\('[0-9]+vp'\)|\.height\('[0-9]+vp'\)|\.width\([0-9]{2,}\)|\.height\([0-9]{2,}\)" \
   entry/src/main/ets/pages entry/src/main/ets/components \
   -g "*.ets" -g "!deprecated/**" -g "!legacy/**"
```

命中不等于必错——区分"业务热区固定尺寸"(如虚拟手柄按钮)和"截图补丁式布局"。前者说明外层自适应依据,后者必须整改。

## 进阶参考

- `references/01-core-rules.md` — 核心定位 / 输入材料规则 / 设计稿与状态职责边界 / 2026-04 执行口径
- `references/02-layout-and-units.md` — 布局单位 / 安全区 / 响应式 / 容器选型
- `references/03-page-workflow.md` — 5 步流程详解 / HTML→ArkUI 转换表 / 设计 token 与自适应边界
- `references/04-component-rules.md` — 页面根 / 顶部 / 卡片 / 列表项 / 资源主题规范
- `references/05-engineering-constraints.md` — ArkTS 类型/状态管理/生命周期/路由/键盘焦点/列表性能/SDK 适配/蓝湖换算
- `references/06-anti-patterns.md` — 危险信号识别 / 工程硬性禁止项 / 设计页落地输出要求
