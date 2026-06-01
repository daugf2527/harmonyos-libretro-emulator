# M6: ROM 管理器 UI 规范

## 1. 功能需求

### 1.1 核心功能
- **ROM 列表展示**: 按平台分类展示所有 ROM（builtin + imported）
- **ROM 详情查看**: 文件大小、路径、来源类型、元数据
- **ROM 删除**: 从沙盒移除（仅 imported，builtin 只读）
- **ROM 导入**: 从外部拷贝到 `{filesDir}/roms/imported/`
- **存储统计**: 显示总占用、可用空间、各平台占比

### 1.2 与 LibraryPage 的关系
| 功能 | LibraryPage | RomManagerPage |
|------|-------------|----------------|
| 游戏启动 | ✓ 主要入口 | ✗ 不提供 |
| ROM 浏览 | ✓ 按游戏卡片 | ✓ 按文件列表 |
| ROM 删除 | ✓ 长按菜单 | ✓ 批量删除 |
| ROM 导入 | ✗ | ✓ 主要入口 |
| 存储管理 | ✗ | ✓ 空间统计 |
| 元数据编辑 | ✗ | ✓ 文件属性 |

**设计原则**: LibraryPage 面向"玩游戏"，RomManagerPage 面向"管理文件"。

---

## 2. UI 设计

### 2.1 页面布局（ASCII 线框图）

```
┌─────────────────────────────────────────────────┐
│ ← ROM 管理器                          [导入] │  ← Header
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 存储统计                                │   │  ← Storage Stats
│  │ 已用 245 MB / 可用 1.2 GB              │   │
│  │ ▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ [全部] [GBA] [GB] [PS1] [MD] [NES]     │   │  ← Platform Filter
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ ☰ metroid_fusion.gba          12.5 MB  │   │  ← ROM List Item
│  │   builtin/gba/                          │   │
│  │   [内置] GBA · 2026-05-20               │   │
│  ├─────────────────────────────────────────┤   │
│  │ ☰ pokemon_red.gb               1.2 MB  │   │
│  │   imported/                             │   │
│  │   [导入] GB · 2026-05-28        [删除] │   │
│  ├─────────────────────────────────────────┤   │
│  │ ☰ sonic.md                     2.8 MB  │   │
│  │   imported/                             │   │
│  │   [导入] MD · 2026-05-30        [删除] │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  [批量删除模式]                                │  ← Batch Actions
│                                                 │
└─────────────────────────────────────────────────┘
```

### 2.2 ROM 列表项设计

#### 2.2.1 基础信息
```typescript
interface RomListItem {
  fileName: string          // "metroid_fusion.gba"
  filePath: string          // "builtin/gba/metroid_fusion.gba"
  fileSize: number          // 字节数
  platform: string          // "GBA"
  sourceType: 'BUILTIN' | 'IMPORTED'
  importedAt?: number       // 导入时间戳（仅 imported）
  isDeletable: boolean      // sourceType === 'IMPORTED'
}
```

#### 2.2.2 视觉层次
- **主标题**: 文件名（14sp, Medium）
- **副标题**: 相对路径（11sp, 60% opacity）
- **元信息**: 来源标签 + 平台 + 日期（9sp, monospace）
- **操作按钮**: 删除按钮（仅 imported，危险色）

#### 2.2.3 与 LibraryPage GameCard 的差异
| 元素 | LibraryPage | RomManagerPage |
|------|-------------|----------------|
| 封面图 | ✓ 大图 | ✗ 文件图标 |
| 标题 | 游戏名称 | 文件名 |
| 副标题 | 平台 | 文件路径 |
| 操作 | 长按菜单 | 直接删除按钮 |
| 布局 | Grid 卡片 | List 行项 |

### 2.3 导入流程

```
用户点击 [导入] 按钮
    ↓
DocumentPicker 选择文件
    ↓
检查文件类型（.gba/.gb/.cue 等）
    ↓
┌─────────────────────────────────┐
│ 如果是 .cue 文件                │
│   → 解析依赖（.bin 文件）       │
│   → 检查依赖是否存在            │
│   → 缺失 → 提示用户选择所有文件 │
└─────────────────────────────────┘
    ↓
检查文件名冲突
    ↓
┌─────────────────────────────────┐
│ 冲突 → 自动重命名               │
│   pokemon_red.gb                │
│   → pokemon_red_1.gb            │
└─────────────────────────────────┘
    ↓
后台拷贝（taskpool.execute）
    ↓
显示进度条（大文件 >10MB）
    ↓
拷贝完成 → 刷新列表 → Toast 提示
```

#### 2.3.1 进度提示 UI
```
┌─────────────────────────────────────────────────┐
│ 正在导入 sonic.md                               │
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │
│ 1.2 MB / 2.8 MB · 预计 3 秒                     │
└─────────────────────────────────────────────────┘
```

### 2.4 存储统计设计

```typescript
interface StorageStats {
  totalUsed: number         // 已用字节数
  totalAvailable: number    // 可用字节数
  platformBreakdown: {      // 各平台占比
    platform: string
    size: number
    count: number
  }[]
}
```

#### 2.4.1 视觉设计
```
┌─────────────────────────────────────────────────┐
│ 存储统计                                        │
│                                                 │
│ 已用 245 MB / 可用 1.2 GB                       │
│ ▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │
│                                                 │
│ GBA  120 MB (12 个)  ▓▓▓▓▓▓▓▓▓▓▓▓              │
│ GB    45 MB (8 个)   ▓▓▓▓                      │
│ PS1   80 MB (3 个)   ▓▓▓▓▓▓▓                   │
└─────────────────────────────────────────────────┘
```

---

## 3. 技术约束

### 3.1 ArkUI 规范遵循

#### 3.1.1 性能优化
- **LazyForEach**: ROM 列表 >50 项时使用 `LazyForEach`（参考 LibraryPage 的 `LibraryDataSource`）
- **@State 最小化**: 只对 UI 直接读取的基础类型用 `@State`
- **@Builder 提取**: 列表项、进度条等复用组件提取为 `@Builder`

#### 3.1.2 生命周期
- **aboutToAppear**: `void this.loadRomList()` 异步加载，不用 setTimeout
- **aboutToDisappear**: 清理定时器、取消进度监听

#### 3.1.3 布局约束
- **最大宽度**: `constraintSize({ maxWidth: 460 })` 与 LibraryPage 一致
- **安全区**: `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`
- **间距**: 使用 `EmuUiTokens` 定义的标准间距（24/18/12/6）

### 3.2 沙盒路径管理

#### 3.2.1 路径规则
```typescript
const ROM_BASE_DIR = `${context.filesDir}/roms`
const BUILTIN_DIR = `${ROM_BASE_DIR}/builtin`
const IMPORTED_DIR = `${ROM_BASE_DIR}/imported`
const TEMP_DIR = `${ROM_BASE_DIR}/temp`
```

#### 3.2.2 权限约束
| 目录 | 读取 | 写入 | 删除 |
|------|------|------|------|
| builtin/ | ✓ | ✗ | ✗ |
| imported/ | ✓ | ✓ | ✓ |
| temp/ | ✓ | ✓ | ✓ |

#### 3.2.3 删除确认
```typescript
// 删除前二次确认（仅 imported）
if (item.sourceType === 'IMPORTED') {
  // 显示确认对话框
  // "确定删除 pokemon_red.gb？此操作不可恢复。"
  // [取消] [删除]
}
```

### 3.3 与现有组件协调

#### 3.3.1 复用组件
- **EmuHeaderBar**: 标题栏（与 LibraryPage 一致）
- **EmuColors**: 颜色系统（primary/onSurface/background）
- **SpinnerLine**: 加载动画（导入进度）
- **Toast**: 操作反馈（导入成功/删除成功）

#### 3.3.2 新增组件
- **RomListItem**: ROM 列表项（@Component）
- **StorageStatsCard**: 存储统计卡片（@Component）
- **ImportProgressOverlay**: 导入进度浮层（@Component）

#### 3.3.3 数据层复用
- **LibraryRepository**: 读取 ROM 元数据（复用现有 `syncLibraryIndex`）
- **RuntimeRomSourceScanner**: 扫描 ROM 文件（复用 `scanLibraryRomSources`）

---

## 4. 实现建议

### 4.1 文件结构
```
entry/src/main/ets/
├── pages/
│   └── RomManagerPage.ets          # 主页面
├── components/
│   ├── RomListItem.ets             # ROM 列表项
│   ├── StorageStatsCard.ets        # 存储统计
│   └── ImportProgressOverlay.ets   # 导入进度
├── common/
│   ├── RomImportService.ets        # 导入逻辑（新增）
│   ├── RomStorageAnalyzer.ets      # 存储分析（新增）
│   └── LibraryRepository.ets       # 复用现有
```

### 4.2 关键 API

#### 4.2.1 导入 ROM
```typescript
// RomImportService.ets
export async function importRomFromPicker(
  context: common.UIAbilityContext,
  onProgress?: (current: number, total: number) => void
): Promise<ImportResult> {
  // 1. DocumentPicker 选择文件
  // 2. 检查文件类型
  // 3. 解析 CUE 依赖（如果是 .cue）
  // 4. 检查文件名冲突
  // 5. 后台拷贝（taskpool.execute）
  // 6. 更新 LibraryRepository
}
```

#### 4.2.2 删除 ROM
```typescript
// RomImportService.ets
export async function deleteImportedRom(
  context: common.UIAbilityContext,
  romPath: string
): Promise<boolean> {
  // 1. 检查 sourceType === 'IMPORTED'
  // 2. fs.unlink(romPath)
  // 3. 删除关联存档（可选）
  // 4. 更新 LibraryRepository
}
```

#### 4.2.3 存储统计
```typescript
// RomStorageAnalyzer.ets
export async function analyzeRomStorage(
  context: common.UIAbilityContext
): Promise<StorageStats> {
  // 1. 扫描 builtin/ 和 imported/
  // 2. 统计各平台文件大小
  // 3. 获取可用空间（fs.statfs）
}
```

### 4.3 异步化策略

#### 4.3.1 文件操作
```typescript
// 所有文件操作必须异步
await fs.copyFile(srcUri, destPath)  // ✓
fs.copyFileSync(srcUri, destPath)    // ✗ 阻塞 UI
```

#### 4.3.2 大文件处理
```typescript
// 大文件（>10MB）使用 taskpool
if (fileSize > 10 * 1024 * 1024) {
  await taskpool.execute(copyLargeFile, srcUri, destPath, onProgress)
} else {
  await fs.copyFile(srcUri, destPath)
}
```

#### 4.3.3 进度回调
```typescript
// 进度回调在 UI 线程更新
onProgress: (current: number, total: number) => {
  this.importProgress = current / total
  this.importProgressText = `${formatBytes(current)} / ${formatBytes(total)}`
}
```

### 4.4 错误处理

#### 4.4.1 导入失败
```typescript
try {
  await importRomFromPicker(context, onProgress)
} catch (err) {
  const message = (err as Error).message
  if (message.includes('ENOSPC')) {
    this.showToast('存储空间不足 STORAGE_FULL')
  } else if (message.includes('EEXIST')) {
    this.showToast('文件已存在 FILE_EXISTS')
  } else {
    this.showToast('导入失败 IMPORT_ERROR')
  }
}
```

#### 4.4.2 CUE 依赖缺失
```typescript
// 解析 CUE 时检查依赖
const dependencies = parseCueDependencies(cueContent)
const missingFiles = dependencies.filter(dep => !fs.accessSync(dep))
if (missingFiles.length > 0) {
  throw new Error(`缺少依赖文件: ${missingFiles.join(', ')}`)
}
```

---

## 5. 验收标准

### 5.1 功能完整性
- [ ] ROM 列表按平台分类展示
- [ ] 显示文件大小、路径、来源类型
- [ ] builtin ROM 不显示删除按钮
- [ ] imported ROM 可删除且有二次确认
- [ ] 导入流程支持单文件和 CUE 多文件
- [ ] 存储统计显示总占用和各平台占比

### 5.2 UI 规范
- [ ] 符合 ArkUI 性能规范（LazyForEach/无 setTimeout）
- [ ] 与 LibraryPage 视觉风格一致（颜色/字体/间距）
- [ ] 列表项高度适配（单行/双行文本）
- [ ] 进度条动画流畅（60fps）

### 5.3 技术约束
- [ ] 所有文件操作异步化
- [ ] 大文件（>10MB）使用 taskpool
- [ ] 路径管理符合沙盒规则
- [ ] 错误处理覆盖主要场景

### 5.4 协调性
- [ ] 不与 LibraryPage 功能重复
- [ ] 复用现有组件（EmuHeaderBar/EmuColors/Toast）
- [ ] 数据层与 LibraryRepository 同步

---

## 6. 实施建议

### 6.1 分阶段实施
1. **Phase 1**: 基础列表展示（读取 builtin + imported）
2. **Phase 2**: 导入功能（单文件）
3. **Phase 3**: CUE 多文件支持
4. **Phase 4**: 删除功能 + 存储统计
5. **Phase 5**: 批量操作 + 性能优化

### 6.2 测试场景
| 场景 | 输入 | 预期输出 |
|------|------|---------|
| 列表展示 | 打开页面 | 显示所有 ROM，builtin 无删除按钮 |
| 导入单文件 | 选择 pokemon_red.gb | 拷贝到 imported/，列表刷新 |
| 导入 CUE | 选择 game.cue | 自动拷贝 game.bin，列表刷新 |
| 删除 ROM | 点击删除按钮 | 二次确认 → 删除文件 → 列表刷新 |
| 存储统计 | 打开页面 | 显示总占用、各平台占比 |
| 文件名冲突 | 导入同名文件 | 自动重命名为 pokemon_red_1.gb |
| 空间不足 | 导入大文件 | Toast 提示"存储空间不足" |

### 6.3 性能目标
- 列表加载 <500ms（100 个 ROM）
- 导入小文件 <1s（<5MB）
- 导入大文件显示进度（>10MB）
- 删除操作 <200ms

---

## 7. 附录

### 7.1 参考文件
- `entry/src/main/ets/pages/LibraryPage.ets` — 列表展示、Toast、生命周期
- `entry/src/main/ets/components/LibraryGameSections.ets` — LazyForEach 实现
- `docs/plans/phase2-rom-sandbox-design.md` — 沙盒结构设计
- `entry/src/main/ets/CLAUDE.md` — ArkUI 性能规范

### 7.2 设计决策记录

#### 决策 1: 为什么不在 LibraryPage 加导入按钮？
**原因**: LibraryPage 面向"玩游戏"，导入是低频操作，独立页面避免主页面复杂化。

#### 决策 2: 为什么用 List 而非 Grid？
**原因**: ROM 管理需要显示详细信息（路径/大小/日期），List 布局更适合文本密度高的场景。

#### 决策 3: 为什么 builtin ROM 不可删除？
**原因**: builtin ROM 是应用内置资源，删除后无法恢复，且占用空间小（<50MB）。

#### 决策 4: 为什么不支持批量导入？
**原因**: DocumentPicker 单次只能选择一个文件（HarmonyOS 限制），批量导入需要多次调用。

### 7.3 未来扩展
- **ROM 重命名**: 允许用户修改文件名（需更新 LibraryRepository）
- **ROM 分享**: 导出 ROM 到外部存储（需权限申请）
- **ROM 校验**: 显示 MD5/SHA1 校验和（用于验证文件完整性）
- **ROM 压缩**: 支持 .zip 自动解压（需 zlib 集成）
