# API22 前瞻迁移方案 — 路由 Navigation + 状态 V2(选择性)

> **For Claude:** 本文档是 2026-06-04 质检后，用户要求"用最佳 API"的前瞻优化方案。
> 联网核对 + 2 个 opus agent 实地测绘产出。**实施前必读对应章节 + 重新 Read 实物**。

---

> ## ⛔ 2026-06-04 暂缓决策 + 实物核查修正（用户拍板：两案均暂缓）
>
> 本文档下方原始方案保留作 audit trail，但**已知失真/证伪，动手前以本块为准**：
>
> **方案 B（状态 V2）— ❌ 废弃，不要实施。**
> 文档建议把 HUD DTO 标 `@ObservedV2 + @Trace`，但实践已证伪：V1 项目里 `@ObservedV2` 类定义本身就触发编译器递归代理 → **heap OOM**（上会话连续 3 次崩溃）。
> 详见 memory `feedback_arkts_v1v2_no_mixing.md`。perfDisplay 现状（`LibretroGamePage.ets:441/474/490` 纯 V1 整体替换）**已是当前最优**，保持不动。
>
> **方案 A（路由 Navigation）— ⏸️ 暂缓。**
> router 在 API22 **未 deprecated**（上会话核查 0 deprecated API），迁移属纯合规/前瞻投入、**无功能收益**。用户 2026-06-04 决定本会话暂缓。
> 若未来重启，先按下方"实物核查修正"更新数据，**别用下方过时的旧数字**。
>
> **实物核查修正（2026-06-04 Explore agent 复测，覆盖下方旧数据）：**
> - router 调用方式：全仓 **0 处静态 import**，统一走 `this.getUIContext().getRouter().pushUrl/replaceUrl/back`（UIContext 是 API12+ 统一入口，封装点天然集中——迁移利好）
> - 跳转边实测 **~42 条**（pushUrl 17 + replaceUrl 19 + back 3 + getParams 4），比下方"28 条"多 ~50%
> - Navigation/NavPathStack/NavDestination 当前 **0 使用**（`commitLaunchNavigation` 是业务方法名，非 ArkUI Navigation）
> - 底部 tab 切换：10 页 `onBottomNavClick` 统一 `replaceUrl({url: route})`，EmuBottomNav 纯回调不导航（与下方描述一致）

**背景**：项目 native 核心（GLES/Vulkan/CPU 三后端 + 音频 AudioWorkgroup）联网核对后**已是 API22 最佳实践**；音频 LatencyMode 用 NORMAL 是踩坑后的有意决策（FAST 致音频断续，**不改**）。剩余两个官方推荐的前瞻迁移如下。

---

## 决策结论（用户 2026-06-04 拍板）

| 迁移 | 范围 | 理由 |
|------|------|------|
| **状态管理 V2** | **仅 LibretroGamePage 60fps HUD 性能 DTO** | agent 实测：项目 0 个 @Link/@Provide/@Observed，V2 优势全无用武之地。全迁 250 处是低 ROI 合规苦力活。只有 HUD 高频 DTO 上 @ObservedV2+@Trace 有真实性能收益 |
| **路由 Navigation** | **完整迁移（15 生产页，6 步渐进）** | 官方推荐；生产路由仅 15 页；4 传参点已 bridge 解耦（最大利好）；可 router/Navigation 共存渐进 |

---

# 方案 A：路由 router → Navigation（完整迁移）

## 摘要
- **生产页面 15 个**（19 个 @Entry 中 4 个 CoreLoaderTest/LibretroNewArchTestPage/TestGambatte/RomManagerPage 是 DevEco 调试页，未注册 main_pages.json，**不迁**）
- 跳转边 ~28 条（pushUrl 11 + replaceUrl 14 + back 3）
- 传参点 4 个（**全部已是 getParams + bridge 双路径 = 迁移最大利好**）
- 复杂度：简单 7 / 中 6 / 复杂 2（LibraryDetailPage 折叠态双形态 + ImportTaskOverlayPage 多分支 replace）
- **推荐架构**：单一根 Navigation（壳页）+ 15 页转 NavDestination + 底部 3 tab 改 stack 操作（**不**升级真 Tabs，ROI 低）

## EmuBottomNav 机制（迁移最关键）
- `EmuBottomNav` 是纯展示组件，自身不导航；每页 `onBottomNavClick(key)` → `getEmuBottomNavTargetRoute` → `replaceUrl` 切 3 个根（library→LibraryPage / input→MultiplayerInputPage / system→SettingsPage）
- **路 A（推荐）**：底部 tab 切换改为对 NavPathStack 根操作（`stack.clear()+pushPathByName` 或 `replacePathByName`），EmuBottomNav 零改动，只改 11 处 onBottomNavClick 实现体
- **路 B（不做）**：升级真 Tabs + tab 内嵌 Navigation——11 页骨架重写，游戏页/详情页 tab 归属混乱，ROI 低

## NavPathStack 架构
- **navDestination builder 方案**（非 routerMap）——单模块无懒加载诉求，迁移摩擦最低
- 新建壳页 EmuShell（改造 EmuAppShell.ets），EntryAbility.loadContent 新目标
- 传参 `getParams()` → `stack.getParamByName(name)` 取数组末元素，**bridge fallback 全保留**（天然双保险）
- SaveStatePage/MetadataEditPage **无 bridge**，迁移前**先补一对 bridge**（仿 LibraryDetailBridge）

## 分步实施（每步独立编译+真机+回滚）
- **Step 0** 搭壳 EmuShell + 空 PageBuilder，EntryAbility 仍 loadContent LibraryPage（PoC）
- **Step 1** 抽 15 页 build 主体为 @Component XxxContent，原 @Entry 暂留（旧路由仍可跑）
- **Step 2** 切 system 子树（SettingsPage + 5 叶子页，最独立先验证机制）
- **Step 3** 切 input 子树（MultiplayerInputPage ↔ InputLayoutPage）
- **Step 4** 切 library 子树（含折叠态 LibraryDetailPage；传参换 getParamByName + 补 bridge）
- **Step 5** 切入口 + 导入流 + 收尾（loadContent 改 EmuShell；删残留 @Entry/getRouter；4 调试页保留 router）

## 风险点
1. router/Navigation 共存栈错乱（官方警告）→ 按子树整体切，不在一条链半混用；**Step 2-4 中间态底部 tab 跨体系互切已知临时不一致，Step 4 收口前不发布**
2. getParamByName 返回数组 → 封装 readNavParam<T> 取 last
3. SaveStatePage/MetadataEditPage 无 bridge → 迁移前先补
4. LibraryDetailPage 折叠态双形态（单折跳页/双三折内嵌）→ push 决策留 LibraryPage 侧
5. 底部安全区双 padding → hideTitleBar(true) + 复核避让
6. back() 语义（LibretroGamePage 2 处）→ stack.pop()，栈底空行为要测

## 真机必验项
冷启动落 LibraryPage / Onboarding→Import→库 / 底部 3 tab 互切不堆栈 / 库→详情(单折跳+半折内嵌) / 详情→启动游戏→back / 详情→资料编辑→保存回写 / 详情→存档管理(补 bridge 后不丢参) / 导入流 / Settings 5 二级页 / 后台前台+折叠展开栈不丢

## 关键文件
- RouteHelper.ets / EmuBottomNav.ets / EntryAbility.ets:62 / Index.ets(demo)
- main_pages.json（缺 4 调试页）/ module.json5（无 routerMap）
- LibraryLaunchBridge.ets / LibraryDetailBridge.ets（利好，已存在）
- 传参消费点：LibretroGamePage:584 / LibraryDetailPage:234 / SaveStatePage:98(无bridge) / MetadataEditPage:58(无bridge)

---

# 方案 B：状态 V2（仅核心高频部分）

## 实施范围（极小）
**只改 LibretroGamePage 的 60fps HUD 性能 DTO**，不动其余 249 处 @State。

agent 实测全仓 V1 装饰器：@State=250、@Prop~150、@Watch=5、**@Link/@Provide/@Consume/@Observed/@ObjectLink/@Track 全 0**。V2 的显式数据流/字段级刷新/跨层 Provider 优势在本项目无用武之地。

## 具体改动
1. 把 LibretroGamePage 里 60fps 刷新的性能数值 model（PerfDisplayState / RuntimeStatsDTO / hudMetricsCache 相关）抽成独立类
2. 该类标 `@ObservedV2`，高频字段标 `@Trace`
3. LibretroGamePage 持有该类实例（V2 兼容：V1 页可持有 @ObservedV2 类）
4. 验证：真机玩一局，HUD 数值实时刷新，确认增量 rerender 生效（不再整页重渲染）

## 为何不全迁（留档）
- 250 处 @State 大多 primitive 或整体替换数组，V1 当前性能已够
- V2 核心卖点字段级增量 rerender 只在极少数高频对象有收益
- 全迁 = 252 处机械替换 + 5 处 @Monitor 改写 + 6 批真机回归，纯合规投入无功能收益
- enableV2Compatibility（API22 可用）允许 V1/V2 共存，未来若需全迁可随时按 agent 的 6 批方案推进

## 风险
- LibretroGamePage 是最深组件树（跨 FoldableLayouts/RuntimePauseOverlay/RuntimeVirtualControllerLayer/VirtualController 4 文件）
- 若 HUD DTO 改 @ObservedV2 后传给 V1 子组件，跨界处可能需 UIUtils.enableV2Compatibility 包裹
- **必须真机验证**：玩一局确认 HUD 刷新正常 + 输入/暂停/折叠态不受影响

---

## 实施顺序建议
1. **先做方案 B**（范围极小，1 个文件，快速见效，风险隔离）
2. **再做方案 A**（6 步渐进，跨多文件，每步真机验证）

两者独立，互不阻塞。所有 .ets 改动 quick_signals 不覆盖编译，每步必须 DevEco 复编 + 真机（见 memory feedback_quick_signals_not_arkts_compile）。
