# M7 SettingsPage 折叠屏适配实施摘要

## 实施日期
2026-05-31

## 适配方案
**自定义响应式布局**（方案 B）

## 布局设计

### 单折态（F态）- 折叠状态
- **布局**：单栏垂直布局（保持原有设计）
- **Tab 切换**：顶部 Tab Header（基础设置 / 高级设置）
- **内容区域**：
  - 基础设置：画面设置 → 输入设备 → 音频音量 → 系统信息（垂直滚动）
  - 高级设置：高级控制卡片 → 设置项列表 → 导航链接（垂直滚动）
- **特点**：紧凑布局，适合单手操作

### 双折态（M态）- 半展开状态
- **布局**：左右双栏布局（30% + 70%）
- **左侧导航栏（30%）**：
  - 设置分组列表（画面设置 / 音频音量 / 输入设备 / 系统信息）
  - 带图标和高亮选中状态
  - 固定不滚动
- **右侧详情区（70%）**：
  - 根据左侧选中的分组显示对应设置项
  - 可垂直滚动
  - 保持原有设置项布局（Slider / Select / Card）
- **特点**：导航清晰，操作高效

### 三折态（G态）- 全展开状态
- **布局**：三栏布局（20% + 30% + 50%）
- **左侧一级分类（20%）**：
  - Tab 切换（基础设置 / 高级设置）
  - 紧凑卡片式布局
  - 带边框高亮选中状态
- **中间二级分类（30%）**：
  - 设置分组列表（同双折态）
  - 根据左侧 Tab 动态显示分组
- **右侧详情区（50%）**：
  - 根据中间选中的分组显示对应设置项
  - 可垂直滚动
- **特点**：信息层级清晰，充分利用大屏空间

## 分组策略

### 基础设置分组
1. **画面设置（video）**
   - 画面比例选择（4:3 / 16:9 / NATIVE）
   - CRT 扫描线强度 Slider

2. **输入设备（input）**
   - 输入设备状态卡片
   - 本地触控布局信息
   - 外接设备列表

3. **音频音量（audio）**
   - 主音量 Slider

4. **系统信息（system）**
   - 最近一次运行摘要
   - Telemetry 面板（FPS / 音频缓冲 / 柱状图）

### 高级设置
- 保持原有单栏布局（不分组）
- 包含：高级控制按钮 / GPU Backend / Scaling Mode / Software Resolution / Audio Buffer / Shader Mode / 导航链接

## 技术实现

### 折叠态检测
```typescript
import { display } from '@kit.ArkUI'

enum FoldableMode {
  SINGLE = 'single',  // 单折态（F态）
  DUAL = 'dual',      // 双折态（M态）
  TRIPLE = 'triple'   // 三折态（G态）
}

// 监听折叠状态变化
private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
  this.updateFoldableMode(data)
}

aboutToAppear(): void {
  this.detectFoldableMode()
  display.on('foldStatusChange', this.foldStatusListener)
}

aboutToDisappear(): void {
  display.off('foldStatusChange', this.foldStatusListener)
}
```

### 状态管理
- `@State foldableMode: FoldableMode`：当前折叠态
- `@State activeGroup: string`：当前选中的设置分组（双折态 / 三折态使用）
- `@State activeTab: string`：当前选中的 Tab（基础 / 高级）

### 条件渲染
```typescript
build() {
  if (this.foldableMode === FoldableMode.SINGLE) {
    // 单栏布局
    this.SettingsDetailPanel()
  } else if (this.foldableMode === FoldableMode.DUAL) {
    // 双栏布局
    Row() {
      this.GroupNavigationPanel().width('30%')
      this.SettingsDetailPanel().width('70%')
    }
  } else {
    // 三栏布局
    Row() {
      this.TabCompactPanel().width('20%')
      this.GroupNavigationPanel().width('30%')
      this.SettingsDetailPanel().width('50%')
    }
  }
}
```

### @Builder 方法拆分
- `GroupNavigationPanel()`：设置分组导航面板
- `SettingsDetailPanel()`：设置详情面板（包含 Scroll）
- `VideoSettings()`：画面设置内容
- `InputSettings()`：输入设备内容
- `AudioSettings()`：音频音量内容
- `SystemSettings()`：系统信息内容
- `TabItemCompact()`：紧凑 Tab 项（三折态使用）

## 响应式设计

### 间距调整
- 单折态：padding 24px（紧凑）
- 双折态 / 三折态：padding 24px（保持一致）

### 字体大小
- 保持原有字体大小（EmuTypography tokens）
- 不同折叠态下字体大小一致

### 组件宽度
- 单折态：maxWidth 460px（居中）
- 双折态：左侧 30% / 右侧 70%
- 三折态：左侧 20% / 中间 30% / 右侧 50%

## 验证结果

### quick_signals 检查
```
==== ALL PASS / SKIP ====
  regression   PASS  (22s)
  hygiene      PASS  (9s)
  ui-fixes     PASS  (17s)
  skill-contract PASS  (29s)
  cxx-build    PASS  (1s)
```

### 编译状态
- ✅ TypeScript 语法检查通过
- ⚠️ 需要 DevEco Studio 完整编译验证（ArkTS 编译器）
- ⚠️ 需要真机 / 模拟器测试折叠态切换

## 验收标准

### 已完成
- [x] 支持三种折叠态切换（单折 / 双折 / 三折）
- [x] 布局清晰，易于导航（分组导航 + 详情面板）
- [x] quick_signals PASS
- [x] 代码结构清晰（@Builder 方法拆分）

### 待验证
- [ ] DevEco Studio 编译通过
- [ ] 真机 / 模拟器折叠态切换流畅
- [ ] 设置项可正常修改（Slider / Select / Button）
- [ ] 状态保持（切换折叠态时，activeGroup / activeTab 保持）

## 风险与注意事项

### 风险 1：display.FoldStatus API 兼容性
- **描述**：部分设备可能不支持 `display.getFoldStatus()` / `display.on('foldStatusChange')`
- **缓解措施**：使用 try-catch 捕获异常，回退到单折态布局

### 风险 2：状态同步
- **描述**：切换折叠态时，activeGroup 可能不同步（单折态不使用 activeGroup）
- **缓解措施**：单折态显示所有分组内容（垂直滚动），双折态 / 三折态根据 activeGroup 过滤

### 风险 3：性能
- **描述**：三栏布局可能增加渲染负担
- **缓解措施**：使用 @Builder 延迟构建，只渲染当前选中的分组内容

## 后续优化建议

### 优化 1：动画过渡
- 添加折叠态切换时的布局动画（animateTo）
- 左侧导航栏展开 / 收起动画

### 优化 2：手势支持
- 双折态 / 三折态支持左右滑动切换分组
- 单折态支持下拉刷新

### 优化 3：状态持久化
- 记住用户最后选中的分组（activeGroup）
- 下次打开页面时恢复

## 参考资料
- [HarmonyOS 折叠屏开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/foldable-screen-development-V5)
- [display.FoldStatus API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-display-V5#foldstatus)
- [M7 折叠屏适配页面清单](./m7-foldable-adaptation-checklist.md)

## 更新日志
- 2026-05-31: 初始版本，完成 SettingsPage 折叠屏适配
