# M6 核心管理 UI 规范

## 1. 功能需求

### 1.1 核心功能
- **核心列表展示**：显示已安装核心（从 `LIBRETRO_CORE_CATALOG` 读取，扫描 `bundleCodeDir/libs/{abi}/{soFile}` 验证安装状态）
- **核心详情查看**：点击核心卡片展开详情（版本、支持格式、固件依赖状态）
- **固件依赖管理**：显示每个核心的固件依赖状态（已就绪 / 缺失项）
- **核心状态监控**：实时扫描本地核心与 `filesDir/system` 固件目录

### 1.2 当前不支持（M6 范围外）
- 核心切换（设置默认核心）— 当前由 LibraryRecord.preferredCoreId 控制
- 核心删除（卸载）— 核心打包在 HAP 内，不支持运行时删除
- 远端更新 — 当前构建未配置远端仓库

## 2. UI 设计

### 2.1 页面布局（ASCII 线框图）

```
┌─────────────────────────────────────────────────────────────┐
│ [≡] 碳影 / Carbon Shade          内核与固件管理 [⚙]        │ ← EmuHeaderBar
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  内存占用                        已安装 4/6 个本地核心       │ ← 状态摘要
│                                                               │
│  ┌──────────────┬──────────────┬──────────────┐            │
│  │ LOCAL CORE   │ FIRMWARE     │ REMOTE UPDATE│            │ ← MemoryFootprint
│  │ 6 项         │ 2/3 个需固件 │ 未配置        │            │   (3 列指标卡片)
│  │ ████████ 72% │ ████ 44%     │ █ 18%        │            │
│  └──────────────┴──────────────┴──────────────┘            │
│                                                               │
│  已识别核心                                                  │ ← 列表标题
│                                                               │
│  本页只展示本地已打包 core 与 filesDir/system 下的固件...  │ ← 说明文字
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ [📱] mgba                                  [已安装]    │  │ ← CoreRow
│  │      Game Boy Advance | mgba_libretro.so  [固件就绪]  │  │   (可点击选中)
│  │      BIOS 可选 · 已找到 gba_bios.bin                  │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │ [📱] snes9x                                [已安装]    │  │
│  │      Super Nintendo | snes9x_libretro.so  [无需固件]  │  │
│  │      无额外固件依赖                                    │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │ [📋] pcsx_rearmed                          [未找到]    │  │
│  │      PlayStation | pcsx_rearmed_libretro.so [缺失项]  │  │
│  │      BIOS 必需 · 缺失 scph1001.bin                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  mgba: BIOS 可选 · 已找到 gba_bios.bin / 无缺失项          │ ← 选中核心详情
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ 运行日志                                               │  │ ← KernelLog
│  │ [SCAN] 仅扫描 bundleCodeDir/libs 下已打包的 core 文件 │  │   (系统状态日志)
│  │ [FW] 本地固件目录: /data/.../files/system             │  │
│  │ [FW] 2/3 个需固件核心已就绪                           │  │
│  │ [FW] 已找到: gba_bios.bin, sega_cd_bios.bin           │  │
│  │ [NET] 当前构建未配置远端 core / firmware 仓库...      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│  [🏠 首页]  [📚 游戏库]  [⚙️ 系统]  [👤 我的]              │ ← EmuBottomNav
└─────────────────────────────────────────────────────────────┘
```

### 2.2 核心列表项设计（CoreRow 组件）

**卡片结构**（横向布局）：
```
┌─────┬──────────────────────────────────────┬──────────┐
│ 图标 │ 核心名称                              │ 状态标签  │
│ [📱]│ mgba                                 │ [已安装] │
│     │ Game Boy Advance | mgba_libretro.so │ [固件就绪]│
│     │ BIOS 可选 · 已找到 gba_bios.bin      │          │
└─────┴──────────────────────────────────────┴──────────┘
```

**视觉层次**：
- **主标题**（核心名称）：15sp / Medium / onSurface
- **副标题**（平台 + soFile）：9sp / onSurfaceVariant
- **固件详情**：9sp / onSurfaceVariant / 最多 2 行
- **状态标签**：
  - 已安装：primary 色 + 边框
  - 未找到：error 色 + 边框
  - 固件状态：hasFirmwareDependencies ? primary : onSurfaceVariant

**交互状态**：
- 默认：surfaceContainerLowest 背景
- 选中：`#1800FF41` 半透明 primary 背景
- 点击：切换 `selectedCoreId`，触发底部详情展开

### 2.3 交互流程

```
用户进入页面
    ↓
aboutToAppear() → refreshCoreStatus()
    ↓
扫描 bundleCodeDir/libs/{abi}/*.so
    ↓
读取 filesDir/system 固件文件
    ↓
构建 ManagedCoreItem[] 列表
    ↓
渲染核心列表（ForEach）
    ↓
用户点击核心卡片
    ↓
selectedCoreId = item.id
    ↓
底部展开固件详情文本
    ↓
用户点击底部导航
    ↓
replaceUrl 跳转其他页面
```

**异步刷新流程**（带 token 取消机制）：
```
refreshCoreStatus()
    ↓
token = beginCoreRefresh()
    ↓
for each catalog item:
    hasCoreFile(context, soFile) → installed
    buildCoreFirmwareDependencyState(id, systemEntries) → firmwareState
    if (!isCurrentCoreRefresh(token)) return  ← 页面销毁时取消
    ↓
coreItems = nextItems
statusText = buildStatusText(nextItems)
firmwareSummaryText = buildFirmwareSummaryText(nextItems, systemEntries)
```

## 3. 技术约束

### 3.1 ArkUI 规范遵循

**布局单位**：
- 字体：9sp（辅助文字）/ 15sp（主标题）/ 20sp（指标数值）
- 间距：6vp（行内）/ 14vp（卡片内）/ 24vp（区块间）
- 圆角：无（卡片边框直角，符合 retro 风格）

**安全区**：
- `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`
- 内容区 `constraintSize({ maxWidth: 920 })`（桌面端居中）

**响应式**：
- 使用 `layoutWeight(1)` 实现弹性布局
- MemoryFootprint 三列等宽（`layoutWeight(1)` × 3）
- 核心列表项左侧图标固定 44vp，中间内容 `layoutWeight(1)`，右侧状态标签固定宽度

### 3.2 状态管理

**@State 变量**（符合 ArkUI 性能规范）：
- `coreItems: ManagedCoreItem[]` — 核心列表数据
- `statusText: string` — 顶部状态摘要
- `selectedCoreId: string` — 当前选中核心 ID
- `firmwareSummaryText: string` — 固件摘要文本
- `firmwareFilesText: string` — 固件文件列表
- `firmwareDirectoryText: string` — 固件目录路径
- `remoteUpdateText: string` — 远端更新状态

**私有变量**（不触发 UI 更新）：
- `pageActive: boolean` — 页面活跃状态
- `coreRefreshToken: number` — 刷新取消 token
-`navItems: EmuBottomNavItem[]` — 底部导航配置（只读）

**避免 @State 过度使用**：
-`navItems` 使用 `readonly` 私有变量（不变数据）
- `coreRefreshToken` 不装饰 @State（内部控制变量）

### 3.3 与现有风格一致

**参考 LibraryPage 设计模式**：
- 顶部 `EmuHeaderBar`（标题 + 右侧标签 + 图标）
- 底部 `EmuBottomNav`（4 个导航项 + dot 指示器）
- 中间 `Scroll` 容器（`layoutWeight(1)` 占满剩余空间）
- 内容区 `constraintSize({ maxWidth })` 居中
- 使用 `EmuColors` / `EmuTypography` 统一 token

**色彩方案**：
- 背景：`EmuColors.background`（深色）
- 卡片：`EmuColors.surfaceContainerLowest`
- 主色：`EmuColors.primary`（#00FF41 绿色）
- 错误：`EmuColors.error`（红色）
- 文字：`EmuColors.onSurface` / `onSurfaceVariant`

**字体**：
- 标题：Medium / Bold
- 正文：Regular
- 代码/日志：`fontFamily('monospace')` + `letterSpacing(1.4)`

## 4. 实现建议

### 4.1 组件拆分

**当前实现**（单文件 395 行）：
```
CoreManagerPage (Entry Component)
├── MemoryFootprint (@Builder)
│   └── FootprintCell (@Builder) × 3
├── CoreRow (@Builder)
│   ├── EmuIcon (已有组件)
│   └── 状态标签 (Text)
└── KernelLog (@Builder)
```

**建议保持现状**：
- 页面逻辑简单（只读展示 + 选中交互）
- @Builder 方法已充分拆分（3 个）
- 无需提取独立组件文件

**如需扩展（M7+）**：
- 提取 `CoreListItem.ets`（支持删除/更新操作）
- 提取 `FirmwareStatusPanel.ets`（固件管理独立页面）

### 4.2 数据流

```
LIBRETRO_CORE_CATALOG (静态配置)
    ↓
buildCatalogItems() → ManagedCoreItem[] (初始状态)
    ↓
refreshCoreStatus()
    ↓
hasCoreFile() → installed: boolean
buildCoreFirmwareDependencyState() → CoreFirmwareDependencyState
    ↓
coreItems (更新 @State)
    ↓
ForEach(coreItems) → CoreRow (@Builder)
    ↓
onClick → selectedCoreId (更新 @State)
    ↓
buildSelectedCoreFirmwareText() → 底部详情文本
```

**数据源**：
- `LIBRETRO_CORE_CATALOG`（`LibretroCoreCatalog.ts`）— 核心元数据
- `bundleCodeDir/libs/{abi}/*.so` — 已安装核心文件
- `filesDir/system/*` — 固件文件
- `CoreFirmwareRepository.ts` — 固件依赖规则

**数据转换**：
```typescript
CoreConfig (catalog)
    ↓
ManagedCoreItem (UI model)
    ├── id: string
    ├── name: string
    ├── platform: string
    ├── soFile: string
    ├── status: '已安装' | '未找到'
    ├── installed: boolean
    ├── firmwareStatus: string
    ├── firmwareDetail: string
    ├── firmwareFoundText: string
    ├── firmwareMissingText: string
    └── hasFirmwareDependencies: boolean
```

### 4.3 错误处理

**Context 不可用**：
```typescript
if (!context) {
  this.statusText = '上下文不可用'
  this.coreItems = this.buildCatalogItems()  // 显示占位数据
  return
}
```

**文件访问失败**（`hasCoreFile`）：
```typescript
try {
  await fs.access(path)
  return true
} catch (err) {
  continue  // 尝试下一个 ABI 候选路径
}
return false  // 所有路径都失败
```

**页面销毁取消**（防止内存泄漏）：
```typescript
if (!this.isCurrentCoreRefresh(token)) {
  return  // 页面已销毁或新刷新已开始，放弃当前操作
}
```

**路由跳转失败**：
```typescript
this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
  LogHelper.error('CoreManagerPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
})
```

### 4.4 性能优化

**已应用的优化**：
1. **ForEach keyGenerator**：`(item: ManagedCoreItem) => item.id`（避免全量重建）
2. **异步取消机制**：`coreRefreshToken` + `isCurrentCoreRefresh()`（页面销毁时中断扫描）
3. **@State 最小化**：只装饰 UI 直接依赖的变量
4. **@Builder 方法**：复用组件逻辑，避免 build() 膨胀

**无需 LazyForEach**：
- 核心列表最多 6 项（`maxVisibleItems = Math.min(6, LIBRETRO_CORE_CATALOG.length)`）
- 远低于 LazyForEach 阈值（>50 项）

**无需 setTimeout**：
- `aboutToAppear()` 使用 `void this.refreshCoreStatus()`（fire-and-forget async）
- 符合 ArkUI 性能规范（避免 setTimeout 生命周期问题）

## 5. 与 LibraryPage 对比

| 维度 | LibraryPage | CoreManagerPage |
|------|-------------|-----------------|
| **数据源** | 动态扫描 ROM 文件 | 静态 catalog + 动态验证 |
| **列表规模** | 100-500+ 游戏 | 6 个核心（固定） |
| **交互复杂度** | 长按菜单 / 搜索 / 下拉刷新 | 点击选中 |
| **状态管理** | 12 个 @State 变量 | 7 个 @State 变量 |
| **性能优化** | LazyForEach + 缓存 | ForEach（数据量小） |
| **@Builder 数量** | 7 个 | 3 个 |
| **文件行数** | 947 行 | 395 行 |

**设计一致性**：
- 相同的 `EmuHeaderBar` / `EmuBottomNav` 布局
- 相同的 `EmuColors` / `EmuTypography` token
- 相同的 `constraintSize({ maxWidth })` 居中策略
- 相同的 `expandSafeArea` 安全区处理

## 6. 验收标准

- [x] **UI 设计符合 ArkUI 规范**
  - 布局单位使用 vp/sp
  - 安全区正确处理
  - 响应式布局（layoutWeight）
  - 最大宽度约束（920vp）

- [x] **覆盖核心管理的主要场景**
  - 核心列表展示（已安装 / 未找到）
  - 固件依赖状态（已就绪 / 缺失项）
  - 核心详情查看（点击选中）
  - 系统状态日志（KernelLog）

- [x] **有清晰的交互流程**
  - 页面加载 → 扫描核心 → 渲染列表
  - 点击核心 → 选中状态 → 展开详情
  - 点击导航 → 路由跳转

- [x] **有 ASCII art 线框图**
  - 页面整体布局（第 2.1 节）
  - 核心列表项结构（第 2.2 节）
  - 交互流程图（第 2.3 节）
  - 数据流图（第 4.2 节）

## 7. 未来扩展方向（M7+）

### 7.1 核心切换（设置默认核心）
- 在 CoreRow 添加"设为默认"按钮
- 更新 LibraryRecord.preferredCoreId
- 需要与 LibraryRepository 集成

### 7.2 核心删除（卸载）
- **技术限制**：核心打包在 HAP 内，无法运行时删除
- **可行方案**：
  - 添加"禁用"状态（不在 LibraryPage 显示）
  - 或提供"重置为出厂核心"功能

### 7.3 远端更新
- 配置远端 core / firmware 仓库 URL
- 实现下载 + 校验 + 安装流程
- 需要网络权限 + 存储权限

### 7.4 固件管理独立页面
- 提取 FirmwareStatusPanel 组件
- 支持固件上传 / 删除 / 校验
- 显示固件文件详情（MD5 / 大小 / 来源）

## 8. 关键设计决策

### 8.1 为什么不支持核心删除？
- 核心文件打包在 `bundleCodeDir/libs/{abi}/` 下（HAP 只读区域）
- HarmonyOS 不允许运行时修改应用包内容
- 替代方案：通过"禁用"状态隐藏核心

### 8.2 为什么限制最多 6 个核心？
```typescript
const maxVisibleItems = Math.min(6, LIBRETRO_CORE_CATALOG.length)
```
- 当前实现为演示/测试阶段
- 避免列表过长影响性能
- 生产环境可移除此限制

### 8.3 为什么使用 ForEach 而非 LazyForEach？
- 核心列表固定 6 项（远低于性能阈值）
- LazyForEach 适用于 >50 项的大列表
- 当前实现简单高效，无需过度优化

### 8.4 为什么固件状态只读不可编辑？
- M6 定位为"状态监控"而非"固件管理"
- 固件上传/删除功能复杂度高（需要文件选择器 + 校验逻辑）
- 留待 M7 固件管理独立页面实现

---

**文档版本**：v1.0
**创建日期**：2026-05-31
**适用版本**：M6 核心管理功能
**维护者**：Codex Bot
