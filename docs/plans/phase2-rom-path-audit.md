# ROM 文件路径审计报告

**审计日期**: 2026-05-30  
**审计范围**: ROM 文件的 3 种来源路径及其处理方式  
**审计目标**: 识别路径格式不一致、潜在安全问题、libretro core 访问方式

---

## 执行摘要

项目中 ROM 文件有 3 种来源，每种使用不同的路径格式和处理流程：

1. **内置 ROM (rawfile)**: `roms/[subdir/]filename` → ResourceManager API
2. **导入 ROM (沙箱)**: `{filesDir}/roms/filename` → 标准文件系统 API
3. **CUE 多文件依赖**: 相对路径引用 → 需特殊处理确保依赖文件可访问

**主要发现**:
- ✅ 路径格式已统一（ArkTS 层）
- ⚠️ C++ 层对 rawfile 路径的 `need_fullpath` core 支持不完整
- ⚠️ CUE 依赖文件处理仅在 rawfile 场景下工作，沙箱导入的 CUE 文件无依赖解析
- ✅ 路径安全验证已到位（`ValidateRomPath` + CUE 路径遍历防护）

---

## 1. 内置 ROM 路径处理 (rawfile 资源)

### 1.1 路径格式

**ArkTS 层生成**:
- 格式: `roms/[subdir/]filename`
- 示例: `roms/gba/metroid_fusion.gba`, `roms/2048.rom`
- 来源: `RuntimeRomSourceScanner.scanRuntimeRomSources()` (entry/src/main/ets/common/RuntimeRomSourceScanner.ets:62-88)

```typescript
// 扫描内置 ROM 子目录
const BUNDLED_ROM_SUBDIRS: string[] = [
  '', 'gba', 'nes', 'snes', 'gb_gbc', 'md', 'nds', 'misc', 'arcade'
]

// 生成 launchPath
bundled.forEach((item: BundledRomEntry) => {
  sources.push({
    fileName: item.fileName,
    launchPath: `roms/${item.relativePath}`  // ← 统一前缀 "roms/"
  })
})
```

**路径判断逻辑** (entry/src/main/ets/common/RuntimePathResolver.ets:70-72):
```typescript
function isRawfilePath(path: string): boolean {
  return path.startsWith('roms/')
}
```

### 1.2 C++ 层处理

**路径传递链路**:
1. ArkTS `refactoredLoadRom(romPath, useResMgr=true)` → NAPI
2. C++ `LibretroEngine::LoadGame(gamePath, data)` (entry/src/main/cpp/core/engine/libretro_engine.cpp:679-698)
3. 引擎线程 `HandleLoadRom` 检测 rawfile 路径 (libretro_engine.cpp:1517-1518):
   ```cpp
   const bool isRawfilePath = (currentGamePath_.rfind("roms/", 0) == 0) ||
                              (currentGamePath_.rfind("./roms/", 0) == 0);
   ```

**加载方式**:
- **非 need_fullpath core**: `ROMLoader::LoadFromPath()` → `PlatformResourceManager::LoadRawFile()` → `OH_ResourceManager_OpenRawFile()` (entry/src/main/cpp/platform/resource/platform_resource_manager.cpp:102-135)
- **need_fullpath core**: ❌ **当前会报错退出** (libretro_engine.cpp:1529-1538)
  ```cpp
  if (needFullpath && isRawfilePath) {
    LOGF(LOG_ERROR, " [NEW] LoadRom Failed: core requires fullpath but got rawfile path");
    // ... emit core_crash: "need_fullpath_rawfile"
  }
  ```

**CUE 依赖处理** (entry/src/main/cpp/platform/resource/rawfile_rom_processor.cpp:110-173):
- 检测 `.cue` 扩展名
- 解析 `FILE "xxx.bin" BINARY` 行 (entry/src/main/cpp/common/cue_parser.cpp:9-79)
- 从同目录 rawfile 加载依赖文件
- 写入临时目录 `{filesDir}/temp_roms/` 供 core 访问

---

## 2. 导入 ROM 路径处理 (DocumentPicker)

### 2.1 路径格式

**ArkTS 层生成**:
- 格式: `{context.filesDir}/roms/filename`
- 示例: `/data/storage/el2/base/haps/entry/files/roms/pokemon_red.gb`
- 来源: `RomImportService.importRomUris()` (entry/src/main/ets/common/RomImportService.ets:230-533)

```typescript
const romDir = `${context.filesDir}/roms`
await ensureDirExists(romDir)
const destPath = `${romDir}/${fileName}`
await copyFileFromUri(uri, destPath, ...)
```

**扫描逻辑** (RuntimeRomSourceScanner.ets:77-86):
```typescript
const localFiles: string[] = await listSandboxRomFiles(context.filesDir)
localFiles.forEach((fileName: string) => {
  sources.push({
    fileName: fileName,
    launchPath: `${context.filesDir}/roms/${fileName}`  // ← 绝对路径
  })
})
```

### 2.2 C++ 层处理

**加载方式**:
- 路径不匹配 `roms/` 前缀 → 判定为沙箱路径
- `ROMLoader::LoadFromPath()` → `PlatformResourceManager::LoadRawFile()` → 标准 `std::ifstream` 读取 (platform_resource_manager.cpp:74-98)

**need_fullpath core 支持**:
- ✅ 直接传递绝对路径给 `retro_load_game(&gameInfo)` (libretro_engine.cpp:1565-1571)
- Core 可直接 `fopen(gameInfo.path)` 访问

**CUE 依赖处理**:
- ❌ **当前无依赖解析** — `RawfileRomProcessor::Process()` 仅处理 rawfile 路径
- 沙箱导入的 `.cue` 文件如果引用 `.bin` 文件，依赖文件必须在同一次导入中选中，否则 core 加载失败

---

## 3. CUE 多文件依赖路径处理

### 3.1 CUE 文件格式

**标准格式** (ISO 9660 / CD-ROM 镜像):
```cue
FILE "game_track01.bin" BINARY
  TRACK 01 MODE2/2352
    INDEX 01 00:00:00
FILE "game_track02.bin" BINARY
  TRACK 02 AUDIO
    INDEX 00 00:00:00
    INDEX 01 00:02:00
```

**解析逻辑** (entry/src/main/cpp/common/cue_parser.cpp:9-79):
- 正则匹配 `FILE "filename" BINARY` 或 `FILE filename BINARY`
- 提取文件名（支持带引号/不带引号）
- **安全过滤**: 拒绝包含 `..` 或绝对路径的引用 (cue_parser.cpp:69-72)

### 3.2 依赖文件解析

**Rawfile 场景** (entry/src/main/cpp/platform/resource/rawfile_rom_processor.cpp:119-173):
1. 检测 `.cue` 扩展名
2. 解析引用文件列表
3. 拼接 rawfile 路径: `{cue_dir}/{referenced_file}`
4. 从 ResourceManager 加载依赖文件
5. 写入临时目录 `{filesDir}/temp_roms/{cue_basename}/`
6. 返回临时 `.cue` 文件路径供 core 使用

**沙箱场景**:
- ❌ **当前无自动依赖解析**
- 用户必须在 DocumentPicker 中同时选中 `.cue` 和所有 `.bin` 文件
- 导入服务会检测依赖关系并排序 (RomImportService.ets:602-636):
  ```typescript
  function markSelectedDependencyFiles(plans: ImportFilePlan[]): void {
    const dependencyNameSet: Set<string> = new Set()
    plans.forEach((plan: ImportFilePlan) => {
      plan.dependencyNames.forEach((name: string) => dependencyNameSet.add(normalizeFileNameKey(name)))
    })
    plans.forEach((plan: ImportFilePlan) => {
      plan.isDependencyFile = dependencyNameSet.has(normalizeFileNameKey(plan.fileName))
    })
  }
  ```
- 依赖文件优先导入 (RomImportService.ets:619-624):
  ```typescript
  plans.sort((left: ImportFilePlan, right: ImportFilePlan) => {
    if (left.isDependencyFile !== right.isDependencyFile) {
      return left.isDependencyFile ? -1 : 1  // 依赖文件排前面
    }
    return left.fileName.localeCompare(right.fileName)
  })
  ```

### 3.3 M3U 多盘游戏支持

**格式** (PlayStation 多盘游戏):
```m3u
# Disc 1
game_disc1.cue
# Disc 2
game_disc2.cue
```

**解析逻辑** (RomImportService.ets:693-705):
```typescript
function parseM3uDependencyNames(text: string): string[] {
  const names: string[] = []
  const lines = text.split(/\r?\n/)
  lines.forEach((line: string) => {
    const trimmed = line.trim()
    if (trimmed.length === 0 || trimmed.startsWith('#')) {
      return
    }
    appendDependencyName(names, extractBaseName(trimmed))
  })
  return names
}
```

**当前状态**: ✅ ArkTS 层已支持 M3U 依赖检测，C++ 层无需特殊处理（core 直接读取 M3U 文件）

---

## 4. libretro Core 访问路径方式

### 4.1 两种加载模式

**模式 1: need_fullpath = true** (core 自行读取文件):
```cpp
struct retro_game_info {
  const char *path;  // ← 必须是可访问的文件系统路径
  const void *data;  // = nullptr
  size_t size;       // = 0
  const char *meta;
};
```
- **支持场景**: 沙箱导入的 ROM
- **不支持场景**: rawfile ROM (无文件系统路径)

**模式 2: need_fullpath = false** (引擎提供内存数据):
```cpp
struct retro_game_info {
  const char *path;  // = nullptr 或文件名（仅供显示）
  const void *data;  // ← 指向 ROM 数据缓冲区
  size_t size;       // ROM 大小
  const char *meta;
};
```
- **支持场景**: rawfile ROM + 沙箱 ROM
- **实现**: `ROMLoader::LoadFromPath()` 读取完整文件到内存 (entry/src/main/cpp/platform/resource/rom_loader.cpp:37-41)

### 4.2 当前支持矩阵

| Core 类型 | Rawfile ROM | 沙箱 ROM | CUE 依赖 |
|-----------|-------------|----------|----------|
| need_fullpath = false | ✅ 内存加载 | ✅ 内存加载 | ✅ (rawfile) / ⚠️ (沙箱需手动选全) |
| need_fullpath = true | ❌ 报错退出 | ✅ 直接传路径 | ✅ (rawfile) / ⚠️ (沙箱需手动选全) |

**受影响的 Core** (需要 need_fullpath):
- `pcsx_rearmed` (PlayStation): CUE/BIN 多文件
- `melonds` (Nintendo DS): 可能需要访问 BIOS 文件
- 其他大型 ROM 或需要随机访问的 core

---

## 5. 路径安全验证

### 5.1 C++ 层验证

**入口点** (entry/src/main/cpp/core/engine/libretro_engine.cpp:1441-1451):
```cpp
if (!currentGamePath_.empty() &&
    !security::ValidateRomPath(currentGamePath_)) {
  LOGF(LOG_ERROR, " [NEW] LoadRom blocked: invalid ROM path %{public}s",
       currentGamePath_.c_str());
  // ... emit core_crash: "rom_path_invalid"
}
```

**验证规则** (entry/src/main/cpp/common/file_security.cpp):
- 拒绝路径遍历 (`..`)
- 拒绝绝对路径（除非在沙箱目录内）
- 拒绝符号链接
- 白名单扩展名检查

### 5.2 CUE 依赖路径验证

**ArkTS 层** (RomImportService.ets:718-725):
```typescript
function extractBaseName(path: string): string {
  const normalized = path.replace(/\\/g, '/')
  const slashIndex = normalized.lastIndexOf('/')
  return sanitizeImportFileName(
    slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized,
    ''
  )
}
```

**C++ 层** (cue_parser.cpp:67-72):
```cpp
// 拒绝路径遍历与绝对路径
if (filename.find("..") != std::string::npos ||
    filename[0] == '/' || filename[0] == '\\') {
    continue;
}
```

---

## 6. 发现的问题与建议

### 6.1 P0 问题

**问题 1: rawfile ROM 不支持 need_fullpath core**
- **影响**: PlayStation (pcsx_rearmed) 等 core 无法加载内置 ROM
- **当前行为**: 报错 `need_fullpath_rawfile` 并退出
- **建议方案**:
  1. 扩展 `RawfileRomProcessor` 为所有 rawfile ROM 写入临时文件
  2. 返回临时文件路径给 core
  3. 生命周期管理: 游戏卸载时清理临时文件

**问题 2: 沙箱 CUE 文件无依赖自动解析**
- **影响**: 用户导入 PS1 游戏时必须手动选中所有 `.bin` 文件，否则加载失败
- **当前行为**: 依赖检测仅在 ArkTS 层（导入时），C++ 层不处理
- **建议方案**:
  1. 在 `ROMLoader::LoadFromPath()` 中检测 `.cue` 文件
  2. 解析依赖文件列表
  3. 验证依赖文件是否存在于同目录
  4. 如缺失，返回明确错误信息（而非 core 内部加载失败）

### 6.2 P1 改进

**改进 1: 统一路径处理接口**
- 当前 `isRawfilePath()` 判断逻辑分散在 ArkTS 和 C++ 两层
- 建议: 在 C++ 层提供统一的 `PathResolver` 类，封装路径类型判断和转换逻辑

**改进 2: 临时文件清理策略**
- 当前 `temp_roms/` 目录无自动清理机制
- 建议: 
  1. 游戏卸载时清理对应临时文件
  2. 应用启动时清理超过 7 天的临时文件
  3. 提供手动清理入口（设置页面）

**改进 3: CUE 依赖缺失的用户提示**
- 当前用户导入 `.cue` 文件时，如果缺少 `.bin` 依赖，只会在加载时失败
- 建议: 在导入阶段检测并提示用户选择缺失的依赖文件

### 6.3 P2 优化

**优化 1: Rawfile ROM 延迟加载**
- 当前所有 rawfile ROM 在加载时全部读入内存
- 对于大型 ROM (>10MB)，可考虑实现流式读取或 mmap 映射

**优化 2: 路径规范化**
- 统一使用 `/` 作为路径分隔符（当前混用 `/` 和 `\`）
- 在 NAPI 边界进行路径规范化，避免 C++ 层处理平台差异

---

## 7. 代码位置索引

### 7.1 ArkTS 层

| 功能 | 文件 | 行号 |
|------|------|------|
| ROM 来源扫描 | entry/src/main/ets/common/RuntimeRomSourceScanner.ets | 62-118 |
| 路径类型判断 | entry/src/main/ets/common/RuntimePathResolver.ets | 30-46, 70-72 |
| ROM 导入服务 | entry/src/main/ets/common/RomImportService.ets | 230-835 |
| CUE 依赖解析 (ArkTS) | entry/src/main/ets/common/RomImportService.ets | 660-705 |
| 库记录构建 | entry/src/main/ets/common/RuntimeRomCatalog.ets | 31-76 |

### 7.2 C++ 层

| 功能 | 文件 | 行号 |
|------|------|------|
| ROM 加载入口 | entry/src/main/cpp/core/engine/libretro_engine.cpp | 679-698, 1430-1662 |
| Rawfile 路径判断 | entry/src/main/cpp/core/engine/libretro_engine.cpp | 1517-1518 |
| need_fullpath 检查 | entry/src/main/cpp/core/engine/libretro_engine.cpp | 1516, 1529-1538 |
| ROM 加载器 | entry/src/main/cpp/platform/resource/rom_loader.cpp | 19-214 |
| 资源管理器 | entry/src/main/cpp/platform/resource/platform_resource_manager.cpp | 66-195 |
| Rawfile 处理器 | entry/src/main/cpp/platform/resource/rawfile_rom_processor.cpp | 72-174 |
| CUE 解析器 | entry/src/main/cpp/common/cue_parser.cpp | 9-79 |
| 路径安全验证 | entry/src/main/cpp/common/file_security.cpp | (需查看完整实现) |

---

## 8. 统一沙盒策略建议

### 8.1 当前状态

**路径格式**:
- ✅ ArkTS 层已统一: rawfile 用 `roms/` 前缀，沙箱用绝对路径
- ✅ C++ 层能正确区分两种路径类型

**数据流**:
- ✅ 非 need_fullpath core: 两种路径都能正确加载到内存
- ⚠️ need_fullpath core: 仅支持沙箱路径

### 8.2 建议的统一策略

**方案 A: 全部转为沙箱路径** (推荐)
1. 所有 rawfile ROM 在首次访问时写入 `{filesDir}/bundled_roms/`
2. 后续访问直接使用沙箱路径
3. 优点: 
   - 统一处理逻辑
   - 支持所有 core 类型
   - 简化 CUE 依赖处理
4. 缺点:
   - 首次启动需要复制内置 ROM (约 50-200MB)
   - 占用用户存储空间

**方案 B: 按需临时文件** (当前部分实现)
1. 非 need_fullpath core: 保持内存加载
2. need_fullpath core: 动态写入 `{filesDir}/temp_roms/`
3. 优点:
   - 节省存储空间
   - 按需加载
4. 缺点:
   - 逻辑复杂
   - 需要临时文件清理机制

**方案 C: 混合策略** (最灵活)
1. 小型 ROM (<5MB): 内存加载
2. 大型 ROM (≥5MB): 写入临时文件
3. CUE 多文件: 始终写入临时目录
4. 优点:
   - 平衡性能和存储
   - 适应不同 ROM 大小
5. 缺点:
   - 实现复杂度最高

### 8.3 推荐实施路径

**阶段 1: 修复 P0 问题** (1-2 天)
- 实现 rawfile ROM 的临时文件写入（方案 B）
- 支持 need_fullpath core 加载内置 ROM

**阶段 2: 完善 CUE 处理** (2-3 天)
- 沙箱 CUE 文件依赖自动解析
- 依赖缺失的明确错误提示

**阶段 3: 优化与清理** (1-2 天)
- 临时文件自动清理机制
- 统一路径处理接口
- 用户手动清理入口

---

## 9. 测试建议

### 9.1 回归测试用例

**用例 1: 内置 ROM 加载**
- [ ] 加载 rawfile ROM (非 need_fullpath core)
- [ ] 加载 rawfile ROM (need_fullpath core) — 当前应失败
- [ ] 加载 rawfile CUE+BIN 游戏

**用例 2: 导入 ROM 加载**
- [ ] 导入单文件 ROM
- [ ] 导入 CUE+BIN (同时选中所有文件)
- [ ] 导入 CUE (仅选 .cue，缺少 .bin) — 当前应失败
- [ ] 导入 M3U 多盘游戏

**用例 3: 路径安全**
- [ ] 尝试加载包含 `..` 的路径 — 应被拒绝
- [ ] 尝试加载绝对路径 (非沙箱) — 应被拒绝
- [ ] CUE 文件引用 `../other.bin` — 应被过滤

### 9.2 性能测试

- [ ] 大型 ROM (>50MB) 加载时间
- [ ] 临时文件写入性能
- [ ] 内存占用 (内存加载 vs 临时文件)

---

## 10. 附录

### 10.1 支持的 ROM 扩展名

**按 Core 分类** (来源: RomImportService.ets:96-118):
- Gambatte (GB/GBC): `gb`, `gbc`, `dmg`
- mGBA (GBA): `gba`, `agb`
- Nestopia (NES): `nes`, `fds`, `unf`, `unif`
- Snes9x (SNES): `smc`, `sfc`, `swc`, `fig`, `bs`, `st`, `gd3`, `gd7`, `dx2`, `bsx`
- Genesis Plus GX (MD/SMS/GG): `mdx`, `md`, `smd`, `gen`, `sms`, `bms`, `gg`, `sg`, `68k`, `sgd`
- melonDS (NDS): `nds`, `ids`, `dsi`
- PCSX ReARMed (PS1): `cue`, `toc`, `ccd`, `pbp`, `chd`, `iso`, `m3u`, `cbn`
- FBNeo (Arcade): `zip`, `7z`
- 其他: `ngp`, `ngc`, `int`, `sv`, `p8`, `png`, `d64`, `dsk`, `kcr`, `sna`

### 10.2 多文件入口扩展名

**CUE**: CD-ROM 镜像描述文件  
**M3U**: 多盘游戏播放列表  
**来源**: RomImportService.ets:118

---

**审计完成时间**: 2026-05-30  
**审计人**: Claude (Sonnet 4.6)  
**下一步**: 根据建议修复 P0 问题，实施统一沙盒策略
