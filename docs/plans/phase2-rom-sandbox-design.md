# Phase 2.2: ROM 沙盒统一策略设计

## 当前问题总结（来自 phase2-rom-path-audit.md）

### P0 问题
1. **Rawfile ROM 不支持 need_fullpath core** — PlayStation (pcsx_rearmed) 等 core 无法加载内置 ROM
2. **沙箱 CUE 文件无依赖自动解析** — 用户导入 PS1 游戏时必须手动选中所有 `.bin` 文件

### P1 改进
- 路径处理逻辑分散在 ArkTS 和 C++ 两层
- 临时文件目录 `temp_roms/` 无自动清理机制
- CUE 依赖缺失时用户提示不友好

---

## 统一沙盒策略设计

### 目标
1. 所有 ROM 最终都在 `{filesDir}/roms/` 下，libretro core 可用标准文件系统访问
2. 内置 ROM 按需解包，避免首次启动慢
3. CUE 多文件依赖自动解析，用户无需手动选择所有文件
4. 临时文件自动清理，避免磁盘占用

### 目录结构

```
{filesDir}/roms/
├── builtin/          # 内置 ROM 解包目录
│   ├── gba/
│   │   └── metroid_fusion.gba
│   ├── gb/
│   │   └── tetris.gb
│   └── ps1/
│       ├── game.cue
│       └── game.bin
├── imported/         # 用户导入 ROM
│   ├── pokemon_red.gb
│   └── sonic.md
└── temp/             # 临时文件（会话结束清理）
    └── [session_id]/
        └── extracted_files
```

### 实现方案

#### 2.3 内置 ROM 按需解包

**触发时机**: 用户首次启动某个内置 ROM 时

**流程**:
1. 检查 `{filesDir}/roms/builtin/{platform}/{filename}` 是否存在
2. 不存在 → 从 rawfile 读取 → 写入目标路径
3. 存在 → 直接使用

**代码位置**: `RomImportService.ets` 新增 `extractBuiltinRomIfNeeded(romPath: string): Promise<string>`

**优化**: 
- 使用 `fs.stat()` 检查文件是否存在，避免重复解包
- 解包失败时回退到内存加载（非 need_fullpath core）

#### 2.4 下载 ROM 拷贝

**触发时机**: 用户通过 DocumentPicker 选择 ROM 文件时

**流程**:
1. 用户选择文件 → 获取 URI
2. 读取文件内容 → 写入 `{filesDir}/roms/imported/{filename}`
3. 记录到 LibraryRepository

**代码位置**: `RomImportService.ets` 修改 `importRomFromPicker()`

**注意事项**:
- 检查文件名冲突，自动重命名（如 `game_1.gba`）
- 显示导入进度（大文件如 PS1 ISO 可能几百 MB）

#### 2.5 CUE 多文件依赖

**触发时机**: 用户导入 `.cue` 文件时

**流程**:
1. 解析 `.cue` 文件，提取所有 `FILE` 引用（如 `game_track01.bin`）
2. 检查依赖文件是否在同一目录
3. 全部拷贝到 `{filesDir}/roms/imported/` 同一目录
4. 更新 `.cue` 文件中的路径引用（如果需要）

**代码位置**: `RomImportService.ets` 新增 `parseCueDependencies(cueContent: string): string[]`

**错误处理**:
- 依赖文件缺失 → 提示用户"需要同时选择 .cue 和 .bin 文件"
- 依赖文件过大 → 显示总大小和预计时间

#### 2.6 临时文件清理

**触发时机**: 
- 应用启动时清理上次会话的 `temp/` 目录
- 应用退出时清理当前会话的 `temp/` 目录

**代码位置**: `EntryAbility.ets` 的 `onCreate()` 和 `onDestroy()`

---

## 实施顺序

1. **2.3 内置 ROM 按需解包** (P0, 修复 need_fullpath core)
2. **2.4 下载 ROM 拷贝** (P0, 基础功能)
3. **2.5 CUE 多文件依赖** (P0, 修复 PS1 游戏)
4. **临时文件清理** (P1, 优化)
5. **2.6 测试 3 种场景** (验证)
6. **2.7 Commit** (收口)

---

## 测试用例

### 场景 1: 内置 ROM (GBA)
- 启动 Metroid Fusion → 检查 `builtin/gba/metroid_fusion.gba` 创建
- 再次启动 → 不重复解包

### 场景 2: 下载 ROM (GB)
- DocumentPicker 选择 `pokemon_red.gb` → 拷贝到 `imported/`
- 启动游戏 → 正常运行

### 场景 3: CUE 多文件 (PS1)
- DocumentPicker 选择 `game.cue` → 自动检测 `game.bin` 依赖
- 全部拷贝到 `imported/` → 启动游戏 → 正常运行

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| 解包失败导致游戏无法启动 | 回退到内存加载（非 need_fullpath core） |
| 大文件拷贝阻塞 UI | 使用 `taskpool.execute()` 后台拷贝 + 进度条 |
| CUE 依赖文件缺失 | 明确提示用户需要选择所有文件 |
| 磁盘空间不足 | 检查可用空间，提示用户清理 |

---

## 下一步

开始实施 2.3: 内置 ROM 按需解包
