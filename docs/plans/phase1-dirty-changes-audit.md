# Phase 1 脏改动审查报告

**审查时间**: 2026-05-30  
**审查范围**: 8 个脏改动文件  
**审查目标**: 确认功能意图、检查未完成标记、识别半成品代码

---

## 审查摘要

**总体改动性质**: UI 优化 + 性能优化（可折叠设备适配准备）  
**未完成功能数量**: 0  
**阻塞性问题**: 无  
**建议下一步**: 可安全提交，建议验证 GameCard 可见性优化在真机上的效果

---

## 详细审查

### 1. `.claude/settings.json`

**改动摘要**:
```diff
- "model": "sonnet",
+ "model": "opus",
```

**功能意图**: 临时切换到 Opus 模型（可能用于复杂推理任务）

**问题**: 无。这是配置文件，不影响代码功能。

**建议**: 提交前考虑是否需要恢复为 `sonnet`（Opus 成本更高）。

---

### 2. `CLAUDE.md`

**改动摘要**: 新增"代码搜索工具策略"章节（19 行）

**功能意图**: 记录 fast-context MCP 工具在本仓库的实测结果（三连败），建议直接用 Grep + Glob

**关键内容**:
- 对比表格：fast-context vs Grep 在 3 个查询场景的表现
- 失败原因分析：Devstral 训练语料对 libretro + 鸿蒙 NAPI 覆盖低
- 关键命名提醒：项目 NAPI 入口用 `napi_module`（全小写），不是常见的 `NAPI_MODULE` 宏

**问题**: 无。纯文档改动，有助于后续开发决策。

---

### 3. `entry/src/main/ets/common/RomImportService.ets`

**改动摘要**: 新增文档文件过滤逻辑（18 行）

**功能意图**: 
- 定义 `DOCUMENTATION_BASENAMES` 常量（readme/license/changelog 等 13 个常见文档文件名）
- 新增 `isLikelyDocumentationFile()` 函数：提取文件名 stem（去路径、去扩展名）并匹配文档列表
- 在 `getPreferredCoreIdForFile()` 入口处提前返回空字符串，避免文档文件被识别为 ROM

**代码质量**:
- 路径分隔符处理：同时支持 `/` 和 `\`（Windows 兼容）
- 大小写不敏感：`stem.toLowerCase()`
- 边界处理：`dotIndex > 0` 避免隐藏文件（如 `.gitignore`）被误判

**问题**: 无。逻辑完整，无半成品代码。

---

### 4. `entry/src/main/ets/common/RuntimeRomCatalog.ets`

**改动摘要**: 新增文档文件过滤逻辑（18 行，与 RomImportService 重复定义）

**功能意图**: 
- 在 `buildRuntimeRomConfigs()` 中过滤文档文件，避免它们出现在运行时 ROM 列表

**代码质量**: 与 RomImportService 中的实现完全一致

**问题**: 
- **代码重复**: `DOCUMENTATION_BASENAMES` 和 `isLikelyDocumentationFile()` 在两个文件中重复定义
- **建议**: 抽取到共享工具模块（如 `common/FileUtils.ets`），但不阻塞提交

---

### 5. `entry/src/main/ets/components/GameCard.ets`

**改动摘要**: 新增可见性检测 + 扫描线动画优化（40 行改动）

**功能意图**:
1. **可见性检测**: 
   - 新增 `isOnScreen` 状态（默认 `true`）
   - 新增 `onVisibilityChanged()` 方法
   - 使用 `.onVisibleAreaChange([0.0, 0.1], ...)` 监听卡片进入/离开视口
   - 只在卡片可见时运行扫描线动画（节省 CPU）

2. **扫描线动画优化**:
   - 将局部变量 `frame` 提升为成员变量 `scannerFrame`（避免闭包捕获问题）
   - 在 `stopScannerLoop()` 中重置 `scannerFrame = 0`（确保下次启动从头开始）

3. **布局修正**:
   - 将 `aspectRatio(3/4)` 从内层 Column 移到外层 Stack（修复布局塌陷问题）
   - 内层 Column 改为 `height('100%')`

**代码质量**:
- 可见性判断：`isVisible || currentRatio > 0`（容错处理）
- 动画同步逻辑：`syncScannerLoop()` 统一处理 `isHighlighted && isOnScreen` 条件

**问题**: 无。逻辑完整，性能优化合理。

---

### 6. `entry/src/main/ets/components/PlatformChipBar.ets`

**改动摘要**: 新增固定高度（2 行）

**功能意图**: 
- 为 Scroll 和外层 Column 设置 `height(40)`，避免高度塌陷

**问题**: 无。简单的布局修正。

---

### 7. `entry/src/main/ets/components/LibraryGameSections.ets`

**改动摘要**: 重构滚动逻辑（248 行，大部分是缩进变化）

**功能意图**:
- 将 `Scroll` 组件从 `LibraryGameSections` 移到父组件 `LibraryPage`
- 新增 3 个回调接口：
  - `onListScrolled?: (yOffset: number) => void`
  - `onListReachEnd?: () => void`
  - `onListTouched?: (event: TouchEvent, yOffset: number) => void`
- 内部使用 `List` 组件替代 `Scroll`（支持 LazyForEach 优化）

**代码质量**:
- 回调接口设计清晰，职责分离
- 保留了 `LazyForEach` 优化（`LibraryDataSource`）

**问题**: 无。这是架构重构，为后续可折叠设备适配做准备。

---

### 8. `entry/src/main/ets/pages/LibraryPage.ets`

**改动摘要**: 配合 LibraryGameSections 重构（60 行改动）

**功能意图**:
1. **移除 Scroller 实例**: 
   - 删除 `private scroller: Scroller = new Scroller()`
   - 删除 `Scroll(this.scroller)` 包裹

2. **缓存变量改为 @State**:
   - `cachedFilteredGames`、`cachedFilteredRecentGames`、`cachedSearchResults`、`cachedDisplayPlatformFilters` 从 `private` 改为 `@State`
   - 原因：这些变量现在直接传给子组件，需要响应式更新

3. **简化滚动回调**:
   - `onMainWillScroll()` 从 4 参数简化为 1 参数（只需 `yOffset`）
   - 通过 `LibraryGameSections` 的回调接口传递滚动事件

4. **布局调整**:
   - `MainContent` 从 `Scroll` 改为 `Column`
   - 移除 `.onWillScroll()` / `.onReachEnd()` / `.onTouch()` 监听（移到子组件）
   - 新增 `.layoutWeight(1)` 确保 `GameSections` 占满剩余空间

**代码质量**:
- 职责分离清晰：滚动逻辑下沉到 `LibraryGameSections`
- 响应式状态管理正确：缓存变量改为 `@State` 确保 UI 更新

**问题**: 无。架构重构完整，无半成品代码。

---

## 未完成标记检查

**检查结果**: 未发现 `TODO` / `FIXME` / `HACK` / `XXX` 标记

**注释代码检查**: 未发现注释掉的代码块

---

## 代码重复问题

**位置**: `RomImportService.ets` 和 `RuntimeRomCatalog.ets`

**重复内容**:
- `DOCUMENTATION_BASENAMES` 常量（13 个文档文件名）
- `isLikelyDocumentationFile()` 函数（10 行逻辑）

**影响**: 
- 维护成本：修改文档过滤规则需要同步两处
- 不阻塞提交：功能完整，可后续重构

**建议**: 
- 抽取到 `common/FileUtils.ets` 或 `common/RomFileUtils.ets`
- 优先级：P2（非阻塞）

---

## 性能优化验证建议

### GameCard 可见性优化

**优化点**: 只在卡片可见时运行扫描线动画

**验证方法**:
1. 在真机上打开 LibraryPage（包含 100+ 游戏卡片）
2. 使用 DevEco Profiler 监控 CPU 使用率
3. 对比优化前后的 CPU 占用（预期降低 30-50%）

**预期效果**:
- 屏幕外卡片不再执行 `setInterval` 动画
- 滚动流畅度提升（尤其在低端设备）

---

## 结论

**改动性质**: 功能完整的 UI 优化 + 性能优化

**代码质量**: 
- ✅ 无未完成标记
- ✅ 无半成品代码
- ✅ 无注释代码
- ⚠️ 存在代码重复（非阻塞）

**提交建议**: 
1. **可安全提交**：所有改动功能完整，无阻塞性问题
2. **提交前检查**：确认 `.claude/settings.json` 的 `model: opus` 是否需要恢复为 `sonnet`
3. **后续优化**：抽取重复的文档过滤逻辑到共享模块（P2）

**测试建议**:
- 真机验证 GameCard 可见性优化效果
- 验证文档文件（README.txt / LICENSE.md 等）不再出现在 ROM 列表
- 验证 LibraryPage 滚动性能（尤其在大列表场景）
