# M7 InputLayoutPage 折叠屏适配实施摘要

## 概述

**页面**: `entry/src/main/ets/pages/InputLayoutPage.ets`
**适配方案**: 自定义响应式布局
**实施日期**: 2026-05-31
**状态**: ✅ 已完成静态检查

---

## 适配目标

InputLayoutPage 是输入布局编辑页面，用户可以拖拽调整虚拟按钮位置和映射。折叠屏适配需要：

1. **单折态（F态）**：保持现有垂直布局
2. **双折态（M态）**：左右分栏，左侧设备列表，右侧编辑区
3. **三折态（G态）**：三栏布局，左侧设备列表，中间预览区，右侧属性面板

---

## 技术实现

### 1. 折叠态检测

```typescript
@State private currentFoldMode: 'single' | 'dual' | 'triple' = 'single'
private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
  this.detectFoldMode()
}

private detectFoldMode(): void {
  try {
    const foldStatus = display.getFoldStatus()
    const displayClass = display.getFoldDisplayMode()

    if (foldStatus === display.FoldStatus.FOLD_STATUS_FOLDED) {
      this.currentFoldMode = 'single'
    } else if (foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
      this.currentFoldMode = 'dual'
    } else if (displayClass === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      this.currentFoldMode = 'triple'
    } else {
      this.currentFoldMode = 'dual'
    }
  } catch (err) {
    // 非折叠屏设备，默认单折态
    this.currentFoldMode = 'single'
  }
}
```

**生命周期管理**:
- `aboutToAppear()`: 注册 `foldStatusChange` 监听器，初始化折叠态
- `aboutToDisappear()`: 注销监听器

---

### 2. 布局设计

#### 单折态（F态）- 保持现有布局

```
┌─────────────────────┐
│   Header Bar        │
├─────────────────────┤
│                     │
│  预览区 / 编辑区     │
│  (垂直滚动)          │
│                     │
│  - 控制器卡片        │
│  - Netplay 区域     │
│                     │
├─────────────────────┤
│   Bottom Nav        │
└─────────────────────┘
```

**特点**:
- 保持原有单栏垂直布局
- 编辑模式全屏显示编辑器
- 非编辑模式显示设备列表

---

#### 双折态（M态）- 左右分栏

```
┌─────────────────────────────────────┐
│          Header Bar                 │
├──────────┬──────────────────────────┤
│          │                          │
│  设备列表 │   预览区 / 编辑区         │
│  (30%)   │   (70%)                  │
│          │                          │
│  - P1    │   编辑模式:               │
│  - P2    │   - 按钮拖拽编辑          │
│  - Net   │   - 底部操作栏            │
│          │                          │
│          │   非编辑模式:             │
│          │   - 提示进入编辑          │
│          │                          │
└──────────┴──────────────────────────┘
```

**特点**:
- 左侧 30%：设备列表（控制器卡片 + Netplay）
- 右侧 70%：预览/编辑区域
- 编辑模式时右侧显示完整编辑器
- 非编辑模式时右侧显示提示信息

---

#### 三折态（G态）- 三栏布局

```
┌────────────────────────────────────────────────────┐
│                  Header Bar                        │
├──────────┬─────────────────────┬───────────────────┤
│          │                     │                   │
│  设备列表 │     预览区          │   属性编辑面板     │
│  (20%)   │     (50%)           │   (30%)           │
│          │                     │                   │
│  - P1    │  编辑模式:           │  - Resolution     │
│  - P2    │  - 按钮拖拽编辑      │  - Latency        │
│  (紧凑)  │  - 校准标记          │  - Selected       │
│          │  - Toast 提示        │  - Mapped         │
│          │                     │  - 保存按钮        │
│          │  非编辑模式:         │  - 重置按钮        │
│          │  - 提示进入编辑      │                   │
│          │                     │  非编辑模式:       │
│          │                     │  - 提示信息        │
│          │                     │                   │
└──────────┴─────────────────────┴───────────────────┘
```

**特点**:
- 左侧 20%：紧凑型设备列表（`CompactControllerCard`）
- 中间 50%：预览区（编辑模式显示可拖拽按钮）
- 右侧 30%：属性编辑面板（`PropertyPanel` + `EditorActionButtons`）
- 三栏独立滚动，互不干扰

---

### 3. 关键组件

#### 3.1 紧凑型控制器卡片

```typescript
@Builder
private CompactControllerCard(item: ControllerCardItem) {
  Column({ space: 8 }) {
    Row({ space: 6 }) {
      Row()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(item.status === 'READY' ? EmuColors.primary : EmuColors.outline)

      Text(item.label)
        .fontSize(10)
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1.2)
    }
    .alignItems(VerticalAlign.Center)

    Text(item.name)
      .fontSize(EmuTypography.sm)
      .fontWeight(FontWeight.Medium)
      .fontColor(EmuColors.onSurface)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })

    Text(item.status)
      .fontSize(10)
      .fontColor(item.status === 'READY' ? EmuColors.primary : EmuColors.onSurfaceVariant)
  }
  .width('100%')
  .padding(12)
  .backgroundColor(EmuColors.surfaceContainer)
  .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  .alignItems(HorizontalAlign.Start)
}
```

**用途**: 三折态左侧栏，节省空间

---

#### 3.2 属性编辑面板

```typescript
@Builder
private PropertyPanel() {
  Column({ space: 12 }) {
    this.PropertyRow('Resolution', `${this.editorLayoutWidth} X ${this.editorLayoutHeight}`)
    this.PropertyRow('Latency', 'INPUT_QUEUE')
    this.PropertyRow('Input Poll', this.layoutStatusText)
    this.PropertyRow('Selected', this.selectedButtonId.toUpperCase())

    Column({ space: 8 }) {
      Text('Mapped')
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .width('100%')

      Select(this.getRetroSelectOptions())
        .selected(this.getRetroOptionIndex())
        .value(`RETRO_${this.getCurrentRetroLabel()}`)
        // ... Select 配置
        .onSelect((index: number) => {
          const opt = RETRO_BUTTON_OPTIONS[index]
          if (opt) {
            this.setSelectedButtonRetroId(opt.retroButtonId)
          }
        })
    }
    .width('100%')
  }
  .width('100%')
  .padding(12)
  .backgroundColor('#22000000')
  .border({ width: 0.5, color: '#55484848', style: BorderStyle.Solid })
}
```

**用途**: 三折态右侧栏，实时显示和编辑按钮属性

---

#### 3.3 编辑操作按钮

```typescript
@Builder
private EditorActionButtons() {
  Column({ space: 12 }) {
    Button('保存布局')
      .width('100%')
      .height(44)
      .fontSize(EmuTypography.md)
      .fontWeight(FontWeight.Bold)
      .fontColor('#004C0C')
      .backgroundColor(EmuColors.primary)
      .onClick(() => {
        void this.saveCurrentLayout()
      })

    Button('重置布局')
      .width('100%')
      .height(44)
      .fontSize(EmuTypography.md)
      .fontWeight(FontWeight.Bold)
      .fontColor(EmuColors.onSurfaceVariant)
      .backgroundColor(EmuColors.surfaceContainerHigh)
      .onClick(() => {
        void this.resetCurrentLayout()
      })
  }
  .width('100%')
}
```

**用途**: 三折态右侧栏，快速保存/重置操作

---

### 4. 拖拽编辑保持

**关键点**:
- 所有折叠态都保持 `PanGesture` 拖拽功能
- `EditableButton` 组件在所有布局中复用
- 拖拽边界计算基于 `editorLayoutWidth/Height`（440x340 逻辑画布）
- 使用百分比定位（`getEditorPercentX/Y`），适配不同屏幕尺寸

```typescript
@Builder
private EditableButton(button: InputLayoutButton, isSelected: boolean) {
  Stack() {
    // ... 按钮渲染
  }
  .position({ x: this.getEditorPercentX(button.x), y: this.getEditorPercentY(button.y) })
  .onClick(() => {
    this.selectedButtonId = button.id
  })
  .gesture(
    PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
      .onActionStart(() => {
        this.selectedButtonId = button.id
        this.captureDragStart(button)
      })
      .onActionUpdate((event: GestureEvent) => {
        this.applyDragUpdate(button.id, event.offsetX, event.offsetY)
      })
      .onActionEnd(() => {
        this.layoutStatusText = 'LOCAL_LAYOUT_DIRTY'
      })
  )
}
```

---

### 5. 条件渲染逻辑

```typescript
build() {
  Column() {
    if (this.isEditorMode()) {
      this.EditorHeaderBar()
    } else {
      EmuHeaderBar({ /* ... */ })
    }

    // 根据折叠态渲染不同布局
    if (this.currentFoldMode === 'single') {
      this.SingleFoldLayout()
    } else if (this.currentFoldMode === 'dual') {
      this.DualFoldLayout()
    } else {
      this.TripleFoldLayout()
    }

    // 单折态非编辑模式显示底部导航
    if (!this.isEditorMode() && this.currentFoldMode === 'single') {
      EmuBottomNav({ /* ... */ })
    }
  }
  .width('100%')
  .height('100%')
  .backgroundColor(EmuColors.background)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}
```

---

## 状态管理

### 状态保持

折叠态切换时，以下状态保持不变：

| 状态变量 | 说明 | 保持原因 |
|---------|------|---------|
| `layoutButtons` | 按钮布局数据 | 用户编辑的核心数据 |
| `selectedButtonId` | 当前选中按钮 | 编辑上下文 |
| `layoutStatusText` | 布局状态文本 | 保存状态提示 |
| `activeMode` | 编辑模式开关 | 用户操作模式 |

### 状态响应

折叠态切换时，以下状态自动更新：

| 状态变量 | 说明 | 更新时机 |
|---------|------|---------|
| `currentFoldMode` | 当前折叠态 | `foldStatusChange` 事件触发 |

---

## 验证结果

### 静态检查

```bash
bash scripts/check/quick_signals.sh
```

**结果**: ✅ ALL PASS

- [x] regression guards PASS
- [x] hygiene checks PASS
- [x] ui-fixes PASS (78 项断言)
- [x] skill-contract PASS
- [x] cxx-build PASS

### 待真机验证

- [ ] 三种折叠态切换流畅性
- [ ] 拖拽编辑在不同折叠态下的精度
- [ ] 布局保存后在不同折叠态加载一致性
- [ ] 三折态属性面板实时更新响应
- [ ] 横竖屏切换时布局适配

---

## 设计决策

### 1. 为什么不使用 FoldableLayouts 组件？

**原因**:
- InputLayoutPage 有复杂的编辑/非编辑模式切换
- 三折态需要独立的属性编辑面板（不是简单的双栏/三栏）
- 自定义响应式布局更灵活，可以精确控制每个区域的内容

**参考**: SaveStatePage 也使用自定义响应式布局

---

### 2. 三折态为什么独立属性面板？

**原因**:
- 三折态屏幕空间充足（通常 ≥ 2000px 宽）
- 独立面板避免遮挡预览区
- 实时编辑体验更好（不需要切换视图）
- 符合专业编辑工具的交互模式（左侧资源，中间画布，右侧属性）

---

### 3. 双折态为什么不显示属性面板？

**原因**:
- 双折态屏幕空间有限（通常 1200-1600px 宽）
- 70% 预览区已经包含编辑器底部操作栏（保存/重置按钮）
- 属性编辑（Select 映射）可以在编辑器内的 Telemetry 面板完成
- 避免过度拥挤，保持清晰的视觉层次

---

## 性能考虑

### 1. 条件渲染

- 使用 `if/else` 条件渲染，只构建当前折叠态的布局
- 避免同时渲染三套布局（内存占用）

### 2. 状态更新

- `currentFoldMode` 变化触发重新渲染
- `layoutButtons` 数组使用不可变更新（`[...this.layoutButtons]`）
- 拖拽时只更新单个按钮，不触发全局重排

### 3. 滚动性能

- 三栏布局各自独立滚动
- 使用 `scrollBar(BarState.Auto)` 按需显示滚动条

---

## 已知限制

### 1. 编辑器画布尺寸固定

- 逻辑画布固定为 440x340
- 使用百分比定位适配不同屏幕
- 真机测试需验证触控热区精度

### 2. 横竖屏切换

- 当前实现未显式处理横竖屏切换
- 依赖 ArkUI 自动布局
- 真机测试需验证横屏下的布局表现

### 3. 动画过渡

- 折叠态切换无过渡动画
- 布局直接切换（ArkUI 默认行为）
- 未来可考虑添加淡入淡出动画

---

## 后续优化方向

### P1 - 真机验证后修复

1. 触控热区精度调整（如果拖拽不准确）
2. 横竖屏适配优化（如果布局异常）
3. 折叠态切换动画（如果用户反馈需要）

### P2 - 体验增强

1. 三折态中间预览区支持缩放（pinch gesture）
2. 双折态右侧支持快速切换预览/属性面板
3. 保存布局时记录折叠态，加载时恢复

---

## 参考资料

- [HarmonyOS 折叠屏开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/foldable-screen-development-V5)
- [display.FoldStatus API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#foldstatus)
- SaveStatePage 自定义响应式布局实现
- LibraryPage 自定义响应式布局实现

---

## 更新日志

- 2026-05-31: 初始实施完成，静态检查通过
