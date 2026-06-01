# M7 折叠屏适配页面清单

## 概述

本文档列出所有 18 个页面的折叠屏适配状态、优先级和方案。

**折叠屏形态**：
- 单折（折叠/展开）
- 双折（折叠/半展开/全展开）
- 三折（折叠/部分展开/全展开）

**适配目标**：
- 展开态充分利用大屏空间（双栏/三栏布局）
- 折叠态保持单栏紧凑布局
- 折叠态切换时平滑过渡，不丢失状态

---

## 优先级判断标准

| 优先级 | 定义 | 典型场景 |
|--------|------|----------|
| **P0** | 游戏核心流程，必须适配 | 游戏运行页面、游戏库主页 |
| **P1** | 高频使用页面，强烈建议适配 | 设置页、核心管理、输入配置 |
| **P2** | 低频页面，可选适配 | 关于页、调试页、测试页 |
| **N/A** | 无需适配 | 纯文本页面、单一功能页面 |

---

## 页面清单（18 个）

### P0 - 游戏核心流程（2 个）

#### 1. LibretroGamePage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P0
- **适配方案**: 使用 FoldableLayouts 组件
- **适配内容**:
  - 单折态（F态）：上下分屏，游戏画面 65%，虚拟手柄 35%
  - 双折态（M态）：Digital GameBoy 风格，上半区显示器，下半区控制台
  - 三折态（G态）：Switch Layout 风格，左手柄 + 游戏视窗 + 右手柄
  - XComponent 实例复用，切换折叠态时游戏状态保持
- **验收标准**:
  - [x] 支持三种折叠态切换（单折/双折/三折）
  - [x] 游戏状态保持（XComponent 实例复用，切换不中断）
  - [x] 代码结构清晰（条件渲染 + @Builder 方法）
  - [ ] 编译通过（需 DevEco Studio 验证）
  - [ ] 性能流畅（需真机测试）
- **实施摘要**: [m7-libretrogamepage-foldable-adaptation-summary.md](./m7-libretrogamepage-foldable-adaptation-summary.md)

#### 2. LibraryPage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P0
- **适配方案**: 响应式布局（不使用 FoldableLayouts 组件）
- **适配内容**:
  - 单折态（F态）：单栏游戏列表，点击直接启动游戏
  - 双折态（M态）：左侧游戏列表（40%），右侧游戏详情预览（60%）
  - 三折态（G态）：左侧平台筛选（20%），中间游戏列表（50%），右侧游戏详情（30%）
  - 点击行为自适应：单折态直接启动，双折/三折态显示详情
  - 搜索结果点击行为同步适配
- **验收标准**:
  - [x] 支持三种折叠态切换（单折/双折/三折）
  - [x] 双折态双栏布局，点击游戏右侧显示详情
  - [x] 三折态三栏布局，左侧平台筛选独立面板
  - [x] 单折态保持原有单栏布局和交互
  - [x] 折叠态切换时状态保持（选中平台、搜索关键词）
  - [x] 编译通过 + quick_signals PASS
  - [ ] 性能流畅（需真机测试）
- **实施摘要**: [m7-librarypage-foldable-adaptation-summary.md](./m7-librarypage-foldable-adaptation-summary.md)

---

### P1 - 高频使用页面（6 个）

#### 3. SettingsPage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 单折态（F态）：单栏垂直布局，保持原有设计
  - 双折态（M态）：左侧设置分组导航（30%），右侧设置详情（70%）
  - 三折态（G态）：左侧一级分类（20%），中间二级分类（30%），右侧设置详情（50%）
  - 设置项分组：画面设置 / 音频音量 / 输入设备 / 系统信息
- **验收标准**:
  - [x] 支持三种折叠态切换
  - [x] 布局清晰，易于导航
  - [x] quick_signals PASS
  - [ ] DevEco Studio 编译通过（需验证）
  - [ ] 真机测试折叠态切换流畅（需验证）
  - [ ] 设置项可正常修改（需验证）
- **实施摘要**: [m7-settingspage-foldable-adaptation-summary.md](./m7-settingspage-foldable-adaptation-summary.md)

#### 4. CoreManagerPage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 单折态（F态）：保持现有布局（指标卡片 + 核心列表 + 日志）
  - 双折态（M态）：左侧核心列表（40%），右侧核心详情 + 固件状态（60%）
  - 三折态（G态）：左侧核心列表（30%），中间核心详情（40%），右侧固件依赖 + 系统日志（30%）
  - 折叠态检测使用 display.getFoldDisplayMode()
  - 选中状态管理，双折态/三折态点击选中显示详情
- **验收标准**:
  - [x] 支持三种折叠态切换
  - [x] 核心信息显示完整
  - [x] 编译通过 + quick_signals PASS
  - [ ] 固件状态检测正常（需真机测试）
- **实施摘要**: [m7-coremanagerpage-foldable-adaptation-summary.md](./m7-coremanagerpage-foldable-adaptation-summary.md)

#### 5. InputLayoutPage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 单折态（F态）：保持现有垂直布局（预览区 + 按钮列表）
  - 双折态（M态）：左侧按钮列表（30%），右侧预览+编辑面板（70%）
  - 三折态（G态）：左侧按钮列表（20%），中间预览区（50%），右侧属性编辑面板（30%）
  - 折叠态检测使用 display.getFoldStatus() 和 display.getFoldDisplayMode()
  - 拖拽编辑功能在所有折叠态保持可用
  - 三折态独立属性编辑面板，实时调整按钮映射
- **验收标准**:
  - [x] 支持三种折叠态切换
  - [x] 拖拽编辑功能正常（PanGesture 保持）
  - [x] 编译通过 + quick_signals PASS
  - [ ] 布局保存/加载正常（需真机测试）
  - [ ] 三折态属性面板实时更新（需真机测试）
- **实施摘要**: [m7-inputlayoutpage-foldable-adaptation-summary.md](./m7-inputlayoutpage-foldable-adaptation-summary.md)

#### 6. SaveStatePage.ets
- **当前状态**: ✅ 已适配（2026-05-31）
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 单折态（F态）：保持现有列表布局，点击直接加载
  - 双折态（M态）：左侧存档列表（40%），右侧存档详情+预览（60%）
  - 三折态（G态）：左侧列表（30%），中间详情（40%），右侧操作+预览（30%）
  - 折叠态检测使用 display.getFoldStatus() 和 display.getFoldDisplayMode()
  - 选中状态管理，双折态/三折态点击选中显示详情
- **验收标准**:
  - [x] 支持三种折叠态切换
  - [x] 布局合理，信息完整
  - [x] 静态检查通过（quick_signals PASS）
  - [ ] 编译通过（需 DevEco Studio 验证）
  - [ ] 加载/删除操作在两种形态下都可用（需真机测试）
- **实施摘要**: [m7-savestatepage-foldable-adaptation-summary.md](./m7-savestatepage-foldable-adaptation-summary.md)

#### 7. LibraryDetailPage.ets
- **当前状态**: 未适配
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：左侧封面/元数据（40%），右侧详情/操作（60%）
  - 折叠态：单栏垂直布局
- **验收标准**:
  - [ ] 展开态双栏，封面更大，详情更清晰
  - [ ] 折叠态单栏，保持所有信息可见
  - [ ] 编辑/删除操作在两种形态下都可用

#### 8. MultiplayerInputPage.ets
- **当前状态**: 未适配
- **优先级**: P1
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：多个玩家输入配置并排显示
  - 折叠态：单栏垂直布局，每个玩家配置独立卡片
- **验收标准**:
  - [ ] 展开态 2-4 个玩家配置并排显示
  - [ ] 折叠态单栏，保持所有玩家配置可见
  - [ ] 输入设备选择在两种形态下都可用

---

### P2 - 低频页面（7 个）

#### 9. ImportEntryPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：导入选项卡片更宽，按钮更大
  - 折叠态：紧凑布局
- **验收标准**:
  - [ ] 展开态卡片充分利用空间
  - [ ] 折叠态保持所有选项可见

#### 10. ImportTaskOverlayPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：任务列表更宽，进度条更清晰
  - 折叠态：紧凑布局
- **验收标准**:
  - [ ] 展开态任务列表充分利用空间
  - [ ] 折叠态保持所有任务可见

#### 11. MetadataEditPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 使用 FoldableLayouts 组件
- **适配内容**:
  - 展开态：左侧表单（50%），右侧预览（50%）
  - 折叠态：单栏表单，预览折叠
- **验收标准**:
  - [ ] 展开态双栏，实时预览
  - [ ] 折叠态单栏，保持表单数据

#### 12. ShaderPreviewPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：预览区域更大
  - 折叠态：紧凑布局
- **验收标准**:
  - [ ] 展开态预览区域充分利用空间
  - [ ] 折叠态保持预览可见

#### 13. OnboardingPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：引导内容居中，左右留白
  - 折叠态：全宽布局
- **验收标准**:
  - [ ] 展开态内容居中，不过宽
  - [ ] 折叠态全宽，保持可读性

#### 14. AboutHelpPage.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 自定义响应式布局
- **适配内容**:
  - 展开态：文本内容居中，左右留白
  - 折叠态：全宽布局
- **验收标准**:
  - [ ] 展开态内容居中，不过宽
  - [ ] 折叠态全宽，保持可读性

#### 15. Index.ets
- **当前状态**: 未适配
- **优先级**: P2
- **适配方案**: 无需适配（启动页）
- **适配内容**: 启动页，通常全屏显示
- **验收标准**:
  - [ ] 展开态/折叠态都居中显示

---

### N/A - 测试页面（3 个）

#### 16. CoreLoaderTest.ets
- **当前状态**: 未适配
- **优先级**: N/A
- **适配方案**: 无需适配（测试页）
- **适配内容**: 开发测试页面，不面向用户
- **验收标准**: 无

#### 17. TestGambatte.ets
- **当前状态**: 未适配
- **优先级**: N/A
- **适配方案**: 无需适配（测试页）
- **适配内容**: 开发测试页面，不面向用户
- **验收标准**: 无

#### 18. LibretroNewArchTestPage.ets
- **当前状态**: 未适配
- **优先级**: N/A
- **适配方案**: 无需适配（测试页）
- **适配内容**: 开发测试页面，不面向用户
- **验收标准**: 无

---

## 统计摘要

| 优先级 | 页面数量 | 占比 |
|--------|----------|------|
| P0 | 2 | 11.1% |
| P1 | 6 | 33.3% |
| P2 | 7 | 38.9% |
| N/A | 3 | 16.7% |
| **总计** | **18** | **100%** |

**适配方案分布**：
- 使用 FoldableLayouts 组件：7 个（P0/P1 核心页面）
- 自定义响应式布局：8 个（P1/P2 辅助页面）
- 无需适配：3 个（测试页面）

---

## 适配方案详解

### 方案 A：使用 FoldableLayouts 组件

**适用场景**：需要明确的双栏/三栏布局切换的页面。

**实现方式**：
```typescript
import { FoldableLayouts } from '../components/FoldableLayouts'

@Entry
@Component
struct ExamplePage {
  build() {
    FoldableLayouts({
      // 折叠态：单栏布局
      foldedLayout: () => {
        this.SingleColumnLayout()
      },
      // 展开态：双栏布局
      unfoldedLayout: () => {
        this.TwoColumnLayout()
      }
    })
  }

  @Builder SingleColumnLayout() {
    Column() {
      // 单栏内容
    }
  }

  @Builder TwoColumnLayout() {
    Row() {
      // 左栏
      Column() { }
        .width('40%')

      // 右栏
      Column() { }
        .width('60%')
    }
  }
}
```

**优点**：
- 统一的折叠态检测逻辑
- 自动处理状态切换
- 代码结构清晰

**缺点**：
- 需要重构现有布局代码
- 两套布局代码维护成本

---

### 方案 B：自定义响应式布局

**适用场景**：布局相对简单，只需调整尺寸/间距的页面。

**实现方式**：
```typescript
import { display } from '@kit.ArkUI'

@Entry
@Component
struct ExamplePage {
  @State isFolded: boolean = true
  private foldStatusListener: (data: display.FoldStatus) => void =
    (data: display.FoldStatus) => {
      this.isFolded = (data === display.FoldStatus.FOLD_STATUS_FOLDED)
    }

  aboutToAppear(): void {
    display.on('foldStatusChange', this.foldStatusListener)
  }

  aboutToDisappear(): void {
    display.off('foldStatusChange', this.foldStatusListener)
  }

  build() {
    Column() {
      // 根据 isFolded 动态调整布局
      Row() { }
        .width(this.isFolded ? '100%' : '80%')
        .padding(this.isFolded ? 16 : 32)
    }
  }
}
```

**优点**：
- 改动最小，渐进式适配
- 单套布局代码，维护成本低

**缺点**：
- 需要手动处理折叠态检测
- 复杂布局代码可读性差

---

## 实施建议

### 阶段 1：P0 页面（必须完成）
1. LibretroGamePage.ets - 游戏运行页面
2. LibraryPage.ets - 游戏库主页

**预计工作量**：2-3 天

---

### 阶段 2：P1 页面（强烈建议）
3. SettingsPage.ets - 设置页
4. CoreManagerPage.ets - 核心管理
5. InputLayoutPage.ets - 输入配置
6. SaveStatePage.ets - 存档管理
7. LibraryDetailPage.ets - 游戏详情
8. MultiplayerInputPage.ets - 多人输入配置

**预计工作量**：4-5 天

---

### 阶段 3：P2 页面（可选）
9-15. 其他辅助页面

**预计工作量**：3-4 天

---

## 测试场景

### 基础测试
- [ ] 单折设备：折叠态 ↔ 展开态切换
- [ ] 双折设备：折叠态 ↔ 半展开态 ↔ 全展开态切换
- [ ] 三折设备：折叠态 ↔ 部分展开态 ↔ 全展开态切换

### 功能测试
- [ ] 游戏运行中切换折叠态，游戏不暂停
- [ ] 列表滚动位置在切换后保持
- [ ] 表单输入数据在切换后保持
- [ ] 虚拟手柄在不同形态下都可操作

### 性能测试
- [ ] 折叠态切换时无明显卡顿（< 100ms）
- [ ] 布局重排不触发全页面重绘
- [ ] 内存占用无明显增加

---

## 风险与注意事项

### 风险 1：FoldableLayouts 组件性能
- **描述**：双套布局代码可能导致内存占用增加
- **缓解措施**：使用 @Builder 延迟构建，只渲染当前形态的布局

### 风险 2：状态同步
- **描述**：折叠态切换时，两套布局的状态可能不同步
- **缓解措施**：使用 @State/@Link 统一管理状态，避免局部状态

### 风险 3：测试覆盖
- **描述**：折叠屏设备种类多，测试覆盖困难
- **缓解措施**：优先测试主流设备（Mate X5/X6），使用模拟器覆盖其他形态

### 风险 4：第三方库兼容性
- **描述**：部分第三方组件可能不支持折叠屏
- **缓解措施**：优先使用官方组件，第三方组件需单独测试

---

## 参考资料

- [HarmonyOS 折叠屏开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/foldable-screen-development-V5)
- [display.FoldStatus API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#foldstatus)
- [响应式布局最佳实践](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/arkts-layout-development-responsive-V5)

---

## 更新日志

- 2026-05-31: 初始版本，完成 18 个页面清单
