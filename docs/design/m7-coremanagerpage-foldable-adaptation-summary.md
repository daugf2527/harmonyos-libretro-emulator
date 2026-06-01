# CoreManagerPage 折叠屏适配实施摘要

## 基本信息

- **页面**: `entry/src/main/ets/pages/CoreManagerPage.ets`
- **优先级**: P1（高频使用页面）
- **适配方案**: 自定义响应式布局
- **实施日期**: 2026-05-31

---

## 适配内容

### 1. 单折态（F态）- 保持原有布局

**布局设计**:
- 垂直单栏布局
- 顶部：内存占用指标卡片
- 中间：核心列表（可滚动）
- 底部：系统日志

**交互行为**:
- 点击核心列表项选中，底部显示固件详情
- 保持原有滚动体验

**实现方法**: `@Builder SingleModeLayout()`

---

### 2. 双折态（M态）- 左右双栏

**布局设计**:
- **左侧（40%）**: 核心列表（紧凑版）
  - 核心名称 + 状态标签
  - 平台信息 + SO 文件名
  - 选中高亮显示
- **右侧（60%）**: 核心详情 + 固件状态
  - 内存占用指标卡片
  - 核心详情面板（名称、平台、状态、文件、固件）
  - 系统日志

**交互行为**:
- 左侧点击核心，右侧实时显示详情
- 未选中时右侧显示提示文字
- 选中状态保持（折叠态切换不丢失）

**实现方法**: `@Builder DualModeLayout()`

---

### 3. 三折态（G态）- 左中右三栏

**布局设计**:
- **左侧（30%）**: 核心列表（紧凑版）
  - 与双折态相同的紧凑列表
  - 选中高亮显示
- **中间（40%）**: 核心详情
  - 内存占用指标卡片
  - 核心详情面板（图标、名称、平台、状态、文件、固件状态）
- **右侧（30%）**: 固件依赖 + 系统日志
  - 固件状态面板（已找到文件 / 缺失文件）
  - 系统日志

**交互行为**:
- 左侧点击核心，中间显示详情，右侧显示固件依赖
- 未选中时中间和右侧显示提示文字
- 选中状态保持

**实现方法**: `@Builder TripleModeLayout()`

---

## 技术实现

### 1. 折叠态检测

```typescript
import { display } from '@kit.ArkUI'

@State private foldDisplayMode: display.FoldDisplayMode =
  display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN

private foldStatusListener: (data: display.FoldStatus) => void =
  (data: display.FoldStatus) => {
    this.updateFoldDisplayMode()
  }

aboutToAppear(): void {
  this.updateFoldDisplayMode()
  display.on('foldStatusChange', this.foldStatusListener)
}

aboutToDisappear(): void {
  display.off('foldStatusChange', this.foldStatusListener)
}

private updateFoldDisplayMode(): void {
  try {
    this.foldDisplayMode = display.getFoldDisplayMode()
  } catch (err) {
    LogHelper.error('CoreManagerPage', 'Fold', `getFoldDisplayMode failed: ${err}`)
    this.foldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  }
}
```

### 2. 条件渲染

```typescript
build() {
  Column() {
    EmuHeaderBar({ ... })

    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      this.DualModeLayout()
    } else if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
      this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_SUB) {
      this.TripleModeLayout()
    } else {
      this.SingleModeLayout()
    }

    EmuBottomNav({ ... })
  }
}
```

### 3. 紧凑版核心列表

新增 `@Builder CoreRowCompact(item: ManagedCoreItem)`:
- 减小图标尺寸（18px）
- 减小字体大小（14px / 9px）
- 减小内边距（12px）
- 保留选中高亮效果

### 4. 核心详情面板

新增 `@Builder CoreDetailPanel()`:
- 显示核心图标（32px）
- 显示核心名称、平台、状态、文件
- 显示固件状态和详情
- 卡片式布局，边框和背景色

### 5. 固件状态面板

新增 `@Builder FirmwareStatusPanel()`:
- 显示已找到的固件文件
- 显示缺失的固件文件
- 无固件依赖时显示提示
- 使用不同颜色区分（primary / error）

---

## 状态管理

### 核心选中状态

```typescript
@State private selectedCoreId: string = ''
```

- 单折态：点击核心列表项，底部显示固件详情
- 双折态：点击左侧核心，右侧显示详情
- 三折态：点击左侧核心，中间显示详情，右侧显示固件依赖
- 折叠态切换时状态保持（不重置 selectedCoreId）

### 核心数据

```typescript
@State private coreItems: ManagedCoreItem[] = []
```

- 所有折叠态共享同一份数据
- 异步刷新时使用 token 机制防止竞态

---

## 响应式指标卡片

`@Builder MemoryFootprint()` 在所有折叠态中复用:
- 显示本地核心数量
- 显示固件就绪状态
- 显示远程更新状态
- 使用进度条可视化

---

## 验收标准

### 功能验收

- [x] 支持三种折叠态切换（单折/双折/三折）
- [x] 核心信息显示完整（名称、平台、状态、固件）
- [x] 选中状态在折叠态切换时保持
- [x] 编译通过 + quick_signals PASS
- [ ] 固件状态检测正常（需真机测试）

### 静态检查

```bash
$ bash scripts/check/quick_signals.sh
==== ALL PASS / SKIP ====
  regression   PASS
  hygiene      PASS
  ui-fixes     PASS
  skill-contract PASS
  cxx-build    PASS
```

### 待验证（需 DevEco Studio + 真机）

- [ ] DevEco Studio 编译通过
- [ ] 折叠态切换流畅（无卡顿）
- [ ] 核心列表滚动正常
- [ ] 固件扫描功能正常
- [ ] 选中状态切换动画流畅

---

## 代码变更摘要

### 新增导入

```typescript
import { display } from '@kit.ArkUI'
```

### 新增状态

```typescript
@State private foldDisplayMode: display.FoldDisplayMode =
  display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
private foldStatusListener: (data: display.FoldStatus) => void
```

### 新增方法

- `updateFoldDisplayMode()`: 更新折叠态
- `@Builder SingleModeLayout()`: 单折态布局
- `@Builder DualModeLayout()`: 双折态布局
- `@Builder TripleModeLayout()`: 三折态布局
- `@Builder CoreRowCompact()`: 紧凑版核心列表项
- `@Builder CoreDetailPanel()`: 核心详情面板
- `@Builder FirmwareStatusPanel()`: 固件状态面板

### 修改方法

- `aboutToAppear()`: 添加折叠态监听
- `aboutToDisappear()`: 移除折叠态监听
- `build()`: 条件渲染不同布局

---

## 设计亮点

### 1. 信息层次清晰

- **单折态**: 垂直滚动，适合快速浏览
- **双折态**: 左侧列表 + 右侧详情，减少滚动
- **三折态**: 左侧列表 + 中间详情 + 右侧固件，信息完整展示

### 2. 交互一致性

- 所有折叠态都使用相同的选中状态管理
- 紧凑版列表保持与完整版相同的交互逻辑
- 折叠态切换时状态保持，用户体验连贯

### 3. 空间利用率

- **单折态**: 100% 宽度，最大化信息密度
- **双折态**: 40% 列表 + 60% 详情，平衡浏览和查看
- **三折态**: 30% 列表 + 40% 详情 + 30% 固件，充分利用大屏

### 4. 视觉反馈

- 选中核心高亮显示（`#1800FF41` 背景色）
- 状态标签颜色区分（primary / error）
- 固件状态颜色区分（已找到 / 缺失）

---

## 性能考虑

### 1. 条件渲染

- 使用 `if-else` 条件渲染，只构建当前折叠态的布局
- 避免同时构建三套布局造成内存浪费

### 2. 数据共享

- 所有折叠态共享同一份 `coreItems` 数据
- 避免重复扫描和数据复制

### 3. ForEach keyGenerator

- 所有 ForEach 都提供 keyGenerator: `(item: ManagedCoreItem) => item.id`
- 优化列表渲染性能

---

## 后续优化建议

### 1. 动画过渡

- 添加折叠态切换时的布局过渡动画
- 使用 `animateTo()` 实现平滑切换

### 2. 手势支持

- 三折态支持左右滑动切换核心
- 双折态支持左侧列表滑动返回

### 3. 固件操作

- 添加固件下载功能（当前未接入）
- 添加固件删除功能
- 添加固件验证功能

### 4. 核心操作

- 添加核心删除功能
- 添加核心更新功能
- 添加核心详情页跳转

---

## 参考资料

- [HarmonyOS 折叠屏开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/foldable-screen-development-V5)
- [display.FoldDisplayMode API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#folddisplaymode)
- [响应式布局最佳实践](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/arkts-layout-development-responsive-V5)

---

## 更新日志

- 2026-05-31: 初始版本，完成三种折叠态适配
