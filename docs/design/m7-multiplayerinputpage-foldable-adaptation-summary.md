# M7 MultiplayerInputPage 折叠屏适配实施摘要

**实施日期**: 2026-05-31
**优先级**: P1
**适配方案**: 自定义响应式布局
**状态**: ✅ 已完成

---

## 适配内容

### 单折态（F态）
- **布局**: 保持现有垂直布局
- **内容**: 玩家卡片 → 联机房间 → 延迟图表 + 输入日志 → 操作按钮
- **特点**: 单栏滚动，紧凑布局

### 双折态（M态）
- **布局**: 左右分栏（40% / 60%）
- **左侧（40%）**: 玩家列表 + 联机房间 + 操作按钮
- **右侧（60%）**: 延迟图表 + 输入日志
- **特点**: 双栏并排，左侧配置，右侧监控

### 三折态（G态）
- **布局**: 三栏布局（25% / 50% / 25%）
- **左侧（25%）**: 玩家列表 + 操作按钮
- **中间（50%）**: 联机房间 + 延迟图表
- **右侧（25%）**: 输入日志
- **特点**: 三栏并排，信息分区清晰

---

## 技术实现

### 折叠态检测
```typescript
// 折叠态状态
@State private foldStatus: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN
@State private displayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN

// 生命周期注册监听
aboutToAppear(): void {
  this.foldStatus = display.getFoldStatus()
  this.displayMode = display.getFoldDisplayMode()
  display.on('foldStatusChange', this.foldStatusListener)
  display.on('foldDisplayModeChange', this.displayModeListener)
}

aboutToDisappear(): void {
  display.off('foldStatusChange', this.foldStatusListener)
  display.off('foldDisplayModeChange', this.displayModeListener)
}
```

### 折叠态判断逻辑
```typescript
// 三折态全展开（G态）
private isTripleFoldExpanded(): boolean {
  return this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED &&
    this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL
}

// 双折态展开（M态）
private isDoubleFoldExpanded(): boolean {
  return this.foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
    this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
    (this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED &&
      this.displayMode !== display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL)
}
```

### 条件渲染
```typescript
build() {
  Column() {
    EmuHeaderBar({ ... })

    // 根据折叠态选择布局
    if (this.isTripleFoldExpanded()) {
      this.TripleFoldLayout()
    } else if (this.isDoubleFoldExpanded()) {
      this.DoubleFoldLayout()
    } else {
      this.SingleFoldLayout()
    }

    EmuBottomNav({ ... })
  }
}
```

---

## 修复的问题

### 问题 1: 折叠态判断方法未使用
**原代码**:
```typescript
private isFoldedState(): boolean { ... }
private isHalfFoldedState(): boolean { ... }
private isExpandedState(): boolean { ... }
```
- 三个方法定义但从未被调用
- 逻辑混乱，`isFoldedState()` 判断条件包含 `FOLD_DISPLAY_MODE_FULL`（错误）

**修复**:
- 删除未使用的方法
- 新增 `isTripleFoldExpanded()` 和 `isDoubleFoldExpanded()` 两个方法
- 逻辑清晰，准确判断三折态和双折态

### 问题 2: build() 中条件判断过于严格
**原代码**:
```typescript
if (this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL &&
    this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED) {
  // 三折态
} else if (this.foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
    this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN) {
  // 双折态
}
```
- 三折态判断条件过于严格，可能导致某些设备无法匹配
- 双折态判断缺少 `EXPANDED + 非FULL` 的情况

**修复**:
```typescript
if (this.isTripleFoldExpanded()) {
  this.TripleFoldLayout()
} else if (this.isDoubleFoldExpanded()) {
  this.DoubleFoldLayout()
} else {
  this.SingleFoldLayout()
}
```
- 使用封装的判断方法，逻辑清晰
- 双折态判断覆盖更多情况（`HALF_FOLDED` / `MAIN` / `EXPANDED + 非FULL`）

---

## 布局细节

### 单折态（F态）
```typescript
@Builder
private SingleFoldLayout() {
  Scroll() {
    Column({ space: 22 }) {
      // 玩家卡片列表
      Column({ space: 14 }) {
        ForEach(this.controllerSlots, ...)
      }

      // 联机房间
      this.LobbySection()

      // 延迟图表 + 输入日志
      Column({ space: 14 }) {
        this.TelemetrySection()
        this.InputLogSection()
      }

      // 操作按钮
      this.ActionStrip()
    }
    .width('100%')
    .constraintSize({ maxWidth: 780 })
    .padding({ left: 24, right: 24, top: 24, bottom: 32 })
  }
  .layoutWeight(1)
  .scrollBar(BarState.Off)
}
```

### 双折态（M态）
```typescript
@Builder
private DoubleFoldLayout() {
  Row({ space: 0 }) {
    // 左侧：玩家列表 + 联机房间 + 操作按钮（40%）
    Scroll() {
      Column({ space: 14 }) {
        ForEach(this.controllerSlots, ...)
        this.LobbySection()
        this.ActionStrip()
      }
      .padding({ left: 20, right: 20, top: 24, bottom: 32 })
    }
    .width('40%')
    .backgroundColor(EmuColors.background)

    // 右侧：延迟图表 + 输入日志（60%）
    Scroll() {
      Column({ space: 14 }) {
        this.TelemetrySection()
        this.InputLogSection()
      }
      .padding({ left: 20, right: 20, top: 24, bottom: 32 })
    }
    .width('60%')
    .backgroundColor(EmuColors.surfaceContainerLowest)
  }
  .layoutWeight(1)
}
```

### 三折态（G态）
```typescript
@Builder
private TripleFoldLayout() {
  Row({ space: 0 }) {
    // 左侧：玩家列表 + 操作按钮（25%）
    Scroll() {
      Column({ space: 14 }) {
        ForEach(this.controllerSlots, ...)
        this.ActionStrip()
      }
      .padding({ left: 16, right: 16, top: 24, bottom: 32 })
    }
    .width('25%')
    .backgroundColor(EmuColors.background)

    // 中间：联机房间 + 延迟图表（50%）
    Scroll() {
      Column({ space: 14 }) {
        this.LobbySection()
        this.TelemetrySection()
      }
      .padding({ left: 20, right: 20, top: 24, bottom: 32 })
    }
    .width('50%')
    .backgroundColor(EmuColors.surfaceContainerLowest)

    // 右侧：输入日志（25%）
    Scroll() {
      Column({ space: 14 }) {
        this.InputLogSection()
      }
      .padding({ left: 16, right: 16, top: 24, bottom: 32 })
    }
    .width('25%')
    .backgroundColor(EmuColors.surfaceContainer)
  }
  .layoutWeight(1)
}
```

---

## 验收标准

### 已完成
- [x] 支持三种折叠态切换（单折/双折/三折）
- [x] 设备分配功能保持（`refreshDevices()` / `buildControllerSlots()`）
- [x] 响应式玩家卡片（`ControllerCard` 在所有折叠态可用）
- [x] 编译通过 + quick_signals PASS

### 待验证（需真机测试）
- [ ] 折叠态切换时布局平滑过渡
- [ ] 设备刷新功能在所有折叠态正常工作
- [ ] 联机房间选择在所有折叠态可用
- [ ] 输入日志实时更新在所有折叠态显示正常

---

## 代码改动统计

| 文件 | 改动类型 | 行数 |
|------|----------|------|
| `MultiplayerInputPage.ets` | 修复折叠态判断逻辑 | ~15 行 |
| `MultiplayerInputPage.ets` | 修复 build() 条件判断 | ~10 行 |

**总改动**: ~25 行（修复现有代码，未新增功能）

---

## 设计决策

### 为什么不使用 FoldableLayouts 组件？
- MultiplayerInputPage 已有完整的三种布局 Builder（`SingleFoldLayout` / `DoubleFoldLayout` / `TripleFoldLayout`）
- 只需修复折叠态判断逻辑，无需引入额外组件
- 自定义响应式布局更灵活，可精确控制每个区域的宽度和内容

### 为什么双折态判断包含 `EXPANDED + 非FULL`？
- 某些双折设备在全展开时 `FoldStatus` 为 `EXPANDED`，但 `DisplayMode` 不是 `FULL`
- 这种情况应归类为双折态（M态），而非三折态（G态）
- 确保双折设备在全展开时也能正确显示双栏布局

### 为什么三折态左右两侧宽度不同（25% / 25%）？
- 左侧玩家列表内容较少（2 个卡片 + 操作按钮），25% 足够
- 右侧输入日志内容较多（设备列表 + 状态信息），25% 也足够
- 中间联机房间 + 延迟图表是核心内容，占 50% 更合理

---

## 后续优化建议

### P2 优化
1. **折叠态切换动画**: 添加 `animateTo()` 实现平滑过渡
2. **玩家卡片响应式**: 三折态左侧 25% 时，卡片内容可进一步精简
3. **输入日志滚动**: 三折态右侧 25% 时，日志列表可能需要更小的字体

### P3 优化
1. **联机房间卡片**: 双折态/三折态时，房间卡片可显示更多信息（如玩家头像）
2. **延迟图表交互**: 三折态中间 50% 时，图表可支持点击查看详细数据
3. **设备分配拖拽**: 双折态/三折态时，支持拖拽设备到玩家槽位

---

## 参考资料

- [HarmonyOS 折叠屏开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/foldable-screen-development-V5)
- [display.FoldStatus API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#foldstatus)
- [display.FoldDisplayMode API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#folddisplaymode)

---

## 更新日志

- **2026-05-31**: 初始版本，修复折叠态判断逻辑，quick_signals PASS
