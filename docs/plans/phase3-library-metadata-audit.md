# Phase 3: Library Metadata Audit Report

**审计日期**: 2026-05-30  
**审计范围**: LibraryRepository 字段定义与使用情况  
**审计目标**: 识别当前字段、缺失字段、扩展影响范围

---

## 1. 当前字段定义

### 1.1 LibraryRecord 接口（entry/src/main/ets/common/LibraryRepository.ets:10-38）

```typescript
export interface LibraryRecord {
  // 基础标识
  id: string
  title: string
  subtitle: string
  platform: string
  
  // 封面与视觉
  coverColor: string
  coverKey: string
  
  // ROM 文件信息
  romFile: string
  preferredCoreId: string
  fileName: string
  
  // 来源与状态
  sourceType: LibrarySourceType  // 'BUNDLED' | 'IMPORTED'
  status: LibraryRecordStatus    // 'READY' | 'MISSING'
  
  // 时间戳（毫秒）
  createdAt: number
  importedAt: number
  updatedAt: number
  lastSeenAt: number
  lastPlayedAt: number
  
  // 使用统计
  playCount: number
  totalPlayTimeMs: number
  lastSessionDurationMs: number
  
  // 运行时遥测（最后一次会话）
  lastRuntimeUpdatedAt: number
  lastRuntimeFps: number
  lastRuntimeAudioBufferUsage: number
  lastRuntimeAudioUnderruns: number
  lastRuntimeAudioOverruns: number
  lastRuntimeVideoDrops: number
  lastRuntimeVideoDupes: number
  lastRuntimeVideoNulls: number
}
```

**字段总数**: 28 个

---

## 2. 缺失字段分析

### 2.1 用户需求字段清单

| 字段名 | 类型 | 用途 | 当前状态 |
|--------|------|------|----------|
| `releaseYear` | `number` | 发行年份，用于排序/筛选 | ❌ **缺失** |
| `publisher` | `string` | 发行商，用于展示/筛选 | ❌ **缺失** |
| `genre` | `string` | 游戏类型，用于分类/筛选 | ❌ **缺失** |
| `playCount` | `number` | 启动次数 | ✅ **已存在** (line 27) |

### 2.2 现有替代方案

#### releaseYear 的当前实现
- **位置**: `GameMetadataRepository.ets:10` 定义，`LibraryDetailPresenter.ets:43-59` 使用
- **实现方式**: 
  1. 优先从 `GameMetadataRecord.releaseYear` 读取（用户手动编辑）
  2. 回退到文件名标签提取（正则 `/^[12][0-9]{3}$/`）
  3. 最终回退到 `record.importedAt` 年份
- **问题**: 
  - `GameMetadataRecord` 与 `LibraryRecord` 是**两个独立存储**（metadata/game_metadata.json vs library/library_index.json）
  - UI 组件需要同时加载两个 Repository 才能获取完整信息
  - 数据一致性依赖外部同步逻辑

#### publisher 的当前实现
- **位置**: `GameMetadataRepository.ets:8` 定义，`LibraryDetailPresenter.ets:120-128` 使用
- **实现方式**: 仅从 `GameMetadataRecord.publisher` 读取，无回退逻辑
- **问题**: 同上，需要跨 Repository 查询

#### genre 的当前实现
- **状态**: ❌ **完全缺失**，无任何实现

---

## 3. 字段使用位置分析

### 3.1 LibraryRecord 核心使用位置

| 文件 | 使用字段 | 用途 |
|------|----------|------|
| `components/GameCard.ets` | `title`, `subtitle`, `platform`, `coverColor`, `coverKey` | 卡片渲染 |
| `components/LibraryGameSections.ets` | 同上 | LazyForEach 数据源 |
| `pages/LibraryPage.ets` | `lastPlayedAt`, `title`, `platform` | 最近运行展示 |
| `common/LibraryDetailPresenter.ets` | `platform`, `lastPlayedAt`, `playCount`, `totalPlayTimeMs`, `fileName`, `importedAt` | 详情页数据计算 |
| `common/LibraryRuntimeTelemetryPresenter.ets` | `lastRuntimeFps`, `lastRuntimeAudioBufferUsage`, `lastRuntimeVideoDrops`, `lastRuntimeAudioUnderruns` | 遥测数据展示 |

### 3.2 GameMetadataRecord 使用位置

| 文件 | 使用字段 | 用途 |
|------|----------|------|
| `common/LibraryDetailPresenter.ets:47-59` | `releaseYear` | 年份标签计算 |
| `common/LibraryDetailPresenter.ets:120-128` | `publisher` | 发行商标签 |
| `pages/MetadataEditPage.ets:92-94` | `publisher`, `releaseYear` | 元数据编辑表单 |

---

## 4. 数据库 Schema 分析

### 4.1 RDB 表结构（LibraryRepository.ets:474-503）

```sql
CREATE TABLE IF NOT EXISTS library_records (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  subtitle TEXT NOT NULL,
  platform TEXT NOT NULL,
  cover_color TEXT NOT NULL,
  cover_key TEXT NOT NULL,
  rom_file TEXT NOT NULL UNIQUE,
  preferred_core_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  source_type TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  last_played_at INTEGER NOT NULL,
  play_count INTEGER NOT NULL,
  total_play_time_ms INTEGER NOT NULL DEFAULT 0,
  last_session_duration_ms INTEGER NOT NULL DEFAULT 0,
  last_runtime_updated_at INTEGER NOT NULL DEFAULT 0,
  last_runtime_fps INTEGER NOT NULL DEFAULT 0,
  last_runtime_audio_buffer_usage INTEGER NOT NULL DEFAULT 0,
  last_runtime_audio_underruns INTEGER NOT NULL DEFAULT 0,
  last_runtime_audio_overruns INTEGER NOT NULL DEFAULT 0,
  last_runtime_video_drops INTEGER NOT NULL DEFAULT 0,
  last_runtime_video_dupes INTEGER NOT NULL DEFAULT 0,
  last_runtime_video_nulls INTEGER NOT NULL DEFAULT 0
)
```

**关键特性**:
- 支持动态列扩展（`ensureRuntimeColumns` 函数，line 517-547）
- 已有 9 个运行时列通过 `ALTER TABLE ADD COLUMN` 动态添加（`RUNTIME_COLUMN_DEFINITIONS`, line 93-104）
- JSON 回退机制（`preferJsonFallback`, line 91）

### 4.2 扩展字段的数据库影响

**新增字段建议**:
```typescript
const NEW_METADATA_COLUMNS: RuntimeColumnDefinition[] = [
  { name: 'release_year', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'publisher', definition: 'TEXT NOT NULL DEFAULT ""' },
  { name: 'genre', definition: 'TEXT NOT NULL DEFAULT ""' }
]
```

**迁移策略**:
1. 追加到 `RUNTIME_COLUMN_DEFINITIONS` 数组
2. `ensureRuntimeColumns` 会自动检测并添加缺失列
3. 现有数据使用 DEFAULT 值填充
4. JSON 回退路径自动兼容（`normalizeRecord` 函数会处理缺失字段）

---

## 5. 扩展字段影响范围

### 5.1 必须修改的文件（P0）

| 文件 | 修改内容 | 工作量 |
|------|----------|--------|
| `common/LibraryRepository.ets` | 1. 扩展 `LibraryRecord` 接口（+3 字段）<br>2. 追加 `RUNTIME_COLUMN_DEFINITIONS`（+3 列定义）<br>3. 更新所有 CRUD 函数的字段映射（~10 处） | 中 |
| `common/LibraryDetailPresenter.ets` | 1. 移除 `GameMetadataRecord` 依赖<br>2. 直接从 `LibraryRecord` 读取 `releaseYear`/`publisher`<br>3. 新增 `getLibraryDetailGenreLabel` 函数 | 小 |
| `pages/LibraryDetailPage.ets` | 1. 移除 `GameMetadataRepository` 导入<br>2. 简化数据加载逻辑（单一数据源） | 小 |

### 5.2 可选修改的文件（P1）

| 文件 | 修改内容 | 收益 |
|------|----------|------|
| `components/GameCard.ets` | 添加 `genre` 标签展示 | 增强卡片信息密度 |
| `pages/LibraryPage.ets` | 添加按年份/类型筛选 | 增强筛选能力 |
| `common/LibraryPagePresenter.ets` | 扩展 `filterLibraryGames` 支持新字段 | 支持新筛选维度 |

### 5.3 需要废弃的文件（P2）

| 文件 | 废弃原因 | 迁移策略 |
|------|----------|----------|
| `common/GameMetadataRepository.ets` | 功能被 `LibraryRepository` 吸收 | 1. 一次性迁移脚本：读取 `game_metadata.json` → 合并到 `library_records` 表<br>2. 保留文件 3 个版本（标记 `@deprecated`）<br>3. 删除前确认无外部引用 |
| `pages/MetadataEditPage.ets` | 编辑逻辑需重构为直接修改 `LibraryRecord` | 重构为 `LibraryRecordEditPage`，直接调用 `LibraryRepository` 更新函数 |

---

## 6. 数据迁移风险评估

### 6.1 风险点

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **双存储不一致** | 用户已在 `GameMetadataRecord` 中手动编辑的数据可能丢失 | 迁移脚本必须优先保留 `GameMetadataRecord` 的值 |
| **RDB 初始化失败回退 JSON** | 新字段在 JSON 模式下需要手动处理 | `normalizeRecord` 函数添加新字段的默认值逻辑 |
| **现有 UI 组件依赖 `GameMetadataRecord`** | 6 个文件直接导入 `GameMetadataRepository` | 逐文件重构，确保测试覆盖 |

### 6.2 回滚策略

1. **数据库版本号递增**: `LIBRARY_DB_VERSION = 3`（当前为 2）
2. **保留旧 JSON 文件**: 迁移前备份 `game_metadata.json` 到 `game_metadata.json.v1.backup`
3. **降级路径**: 如果 RDB 初始化失败，`preferJsonFallback` 机制自动回退到 JSON 模式

---

## 7. 实施建议

### 7.1 优先级划分

| 阶段 | 任务 | 预估工作量 | 风险 |
|------|------|------------|------|
| **P0** | 扩展 `LibraryRecord` 接口 + 数据库 Schema | 2-3 小时 | 低（已有动态列扩展机制） |
| **P0** | 编写数据迁移脚本（`GameMetadataRecord` → `LibraryRecord`） | 1-2 小时 | 中（需要处理数据冲突） |
| **P0** | 重构 `LibraryDetailPresenter` 移除双 Repository 依赖 | 1 小时 | 低 |
| **P1** | 重构 `MetadataEditPage` 为 `LibraryRecordEditPage` | 2 小时 | 中（UI 逻辑变更） |
| **P1** | 扩展筛选/排序功能支持新字段 | 1-2 小时 | 低 |
| **P2** | 废弃 `GameMetadataRepository`（标记 `@deprecated`） | 0.5 小时 | 低 |

**总工作量**: 7.5-10.5 小时

### 7.2 关键决策点

#### 决策 1: 是否保留 `GameMetadataRepository`？
- **方案 A（推荐）**: 废弃，合并到 `LibraryRepository`
  - ✅ 优点: 单一数据源，消除同步问题
  - ❌ 缺点: 需要迁移脚本，短期工作量增加
- **方案 B**: 保留，仅在 UI 层做数据合并
  - ✅ 优点: 改动最小
  - ❌ 缺点: 长期维护成本高，数据一致性问题持续存在

#### 决策 2: `genre` 字段类型？
- **方案 A（推荐）**: `string`（自由文本）
  - ✅ 优点: 灵活，支持多语言/自定义标签
  - ❌ 缺点: 筛选需要模糊匹配
- **方案 B**: `string[]`（标签数组）
  - ✅ 优点: 支持多类型游戏（如 "RPG, Action"）
  - ❌ 缺点: RDB 存储需要序列化为 JSON 字符串，查询复杂度增加

**建议**: 先用方案 A（单字符串），后续需要时再扩展为数组

---

## 8. 测试覆盖建议

### 8.1 单元测试

- [ ] `LibraryRepository.syncLibraryIndex` 处理新字段的默认值
- [ ] `normalizeRecord` 兼容缺失新字段的旧数据
- [ ] `ensureRuntimeColumns` 正确添加新列

### 8.2 集成测试

- [ ] 数据迁移脚本：`GameMetadataRecord` → `LibraryRecord`（优先保留手动编辑值）
- [ ] RDB 模式与 JSON 回退模式的新字段读写一致性
- [ ] `LibraryDetailPage` 在无 `GameMetadataRepository` 依赖下正常渲染

### 8.3 回归测试

- [ ] 现有 28 个字段的 CRUD 操作不受影响
- [ ] `playCount` 自增逻辑不受新字段影响
- [ ] 运行时遥测数据更新不受影响

---

## 9. 附录：关键代码位置索引

### 9.1 数据模型定义
- `LibraryRecord` 接口: `LibraryRepository.ets:10-38`
- `GameMetadataRecord` 接口: `GameMetadataRepository.ets:5-13`
- RDB Schema: `LibraryRepository.ets:474-503`

### 9.2 CRUD 操作
- `syncLibraryIndex`: `LibraryRepository.ets:106-189`
- `markLibraryRecordPlayed`: `LibraryRepository.ets:226-272`
- `updateLibraryRuntimeSnapshot`: `LibraryRepository.ets:274-322`
- `updateLibraryRecordCover`: `LibraryRepository.ets:347-396`

### 9.3 UI 组件
- `GameCard`: `components/GameCard.ets:6-77`
- `LibraryGameSections`: `components/LibraryGameSections.ets:48-100`
- `LibraryDetailPage`: `pages/LibraryDetailPage.ets`

### 9.4 数据展示逻辑
- `LibraryDetailPresenter`: `common/LibraryDetailPresenter.ets`
- `LibraryRuntimeTelemetryPresenter`: `common/LibraryRuntimeTelemetryPresenter.ets`

---

**审计完成时间**: 2026-05-30  
**下一步行动**: 等待用户确认实施方案（方案 A vs 方案 B）
