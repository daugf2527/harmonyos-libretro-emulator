# M1 ROM/I-O Governance Epic - Closure Report

**Epic ID**: M1  
**Status**: Partial Completion (Phase 1 完成，Phase 2-3 设计完成但实施 BLOCKED)  
**Date**: 2026-05-30  
**Duration**: ~4 hours (Phase 1 + 审计设计)

---

## Executive Summary

M1 epic 旨在统一 ROM 路径管理、完善 Library metadata、建立 I-O 治理规范。**Phase 1 (收口脏改动) 已完成并验证通过**，Phase 2-3 因架构重构工作量超出单会话限制而 BLOCKED，建议作为独立 epic 规划。

### 完成情况

| Phase | 状态 | 完成度 | 说明 |
|-------|------|--------|------|
| Phase 1: 收口脏改动 | ✅ 完成 | 100% | 8 个文件改动已提交，quick_signals ALL PASS |
| Phase 2: ROM 沙盒统一 | ⚠️ 设计完成 | 40% | 审计+设计完成，实施 BLOCKED (C++/ArkTS 跨层) |
| Phase 3: Library metadata | ⚠️ 审计完成 | 14% | 审计完成，实施 BLOCKED (双 Repository 合并) |
| Phase 4: M1 closure | ✅ 完成 | 100% | 本文档 |

---

## Phase 1: 收口脏改动 ✅

### 完成内容

1. **审查 8 个脏改动 diff** (commit: `2e96b42`)
   - 文档文件过滤 (RomImportService + RuntimeRomCatalog)
   - GameCard 可见性优化 (CPU 占用预期降低 30-50%)
   - LibraryPage 滚动重构 (为可折叠设备适配准备)
   - 布局修正 (PlatformChipBar/GameCard)
   - CLAUDE.md 更新 (fast-context 评估结果)

2. **验证通过**
   - quick_signals: ALL PASS (regression/hygiene/ui-fixes/skill-contract/cxx-build)
   - 无 TODO/FIXME/HACK 标记
   - trailing whitespace 已清理

3. **提交记录**
   - Commit: `2e96b42` - feat(library): UI polish for foldable devices
   - Files: 10 changed, 1028 insertions(+), 499 deletions(-)

### 技术亮点

- **性能优化**: GameCard 只在可见时运行扫描线动画，避免离屏渲染浪费
- **代码重复识别**: 文档过滤逻辑在 2 个文件重复，已标记为 P2 重构项
- **配置修正**: .claude/settings.json 的 model 从 opus 改回 sonnet (成本优化)

---

## Phase 2: ROM 沙盒统一 ⚠️

### 完成内容

1. **审计当前 ROM 路径** (commit: `d7284fd`)
   - 识别 3 种 ROM 来源：rawfile (内置) / sandbox (导入) / CUE (多文件)
   - 发现 P0 问题：rawfile ROM 不支持 need_fullpath core (PS1 等)
   - 发现 P1 问题：CUE 依赖文件需用户手动选择所有 .bin

2. **设计统一沙盒策略** (commit: `d7284fd`)
   - 目录结构：`{filesDir}/roms/{builtin|imported|temp}/`
   - 内置 ROM 按需解包到 builtin/ (持久化)
   - 下载 ROM 拷贝到 imported/
   - CUE 依赖自动解析 (C++ 侧已实现)

### BLOCKED 原因

**工作量**: 2-3 小时 (超过单任务 30 分钟限制)

**技术复杂度**:
- 跨 C++/ArkTS 两层修改
- 需要修改 `rawfile_rom_processor.cpp` (从 temp_roms 改为 builtin)
- 需要扩展 `RomImportService.ets` (DocumentPicker 导入)
- 需要完整的 3 种场景测试 (内置/下载/CUE)

**风险**:
- 修改 C++ 侧需要重新编译 HAP
- 可能影响现有 ROM 加载逻辑
- 数据迁移风险 (现有用户的 temp_roms 文件)

### 建议

**推荐方案**: 作为独立 epic (M1.2) 规划，预留 1-2 天开发时间

**实施路径**:
1. 先修改 C++ 侧目录路径 (temp_roms → builtin)
2. 添加 ArkTS 侧目录初始化
3. 实现 DocumentPicker 导入到 imported/
4. 验证 CUE 依赖 (已在 C++ 侧实现)
5. 完整测试 3 种场景

---

## Phase 3: Library metadata ⚠️

### 完成内容

1. **审计 LibraryRepository 字段** (commit: `27ce056`)
   - 当前 28 个字段 (基础标识/封面/ROM 信息/时间戳/统计/遥测)
   - playCount 已存在 ✅
   - releaseYear/publisher 在独立的 `GameMetadataRepository` ❌
   - genre 完全缺失 ❌

### BLOCKED 原因

**工作量**: 7.5-10.5 小时 (远超单任务限制)

**架构问题**: 双 Repository 架构
- `LibraryRepository` (library/library_index.json)
- `GameMetadataRepository` (metadata/game_metadata.json)
- 6 个文件存在跨 Repository 依赖
- 数据一致性依赖外部同步逻辑

**技术复杂度**:
- 需要合并两个独立存储
- 数据迁移脚本 (处理冲突、优先保留手动编辑值)
- 重构 `LibraryDetailPresenter` (移除 GameMetadataRepository 依赖)
- UI 组件改动 (6 个文件)

### 建议

**推荐方案**: 作为独立 epic (M1.3) 规划，预留 2-3 天开发时间

**实施路径**:
1. 扩展 `LibraryRecord` 接口 (新增 3 个字段)
2. 数据库 Schema 扩展 (利用 `ensureRuntimeColumns` 机制)
3. 数据迁移脚本 (GameMetadataRecord → LibraryRecord)
4. 重构 UI 组件 (移除双 Repository 依赖)
5. 废弃 `GameMetadataRepository` (单一数据源)

---

## Phase 4: M1 Closure ✅

本文档即为 M1 closure 报告。

---

## 技术债清单

### P0 (阻塞性)
1. **Rawfile ROM 不支持 need_fullpath core** (Phase 2)
   - 影响: PS1/N64 等 core 无法加载内置 ROM
   - 解决方案: 实施 Phase 2.3 (按需解包到 builtin/)

2. **双 Repository 架构** (Phase 3)
   - 影响: 数据一致性风险、维护成本高
   - 解决方案: 实施 Phase 3.2 (合并为单一 Repository)

### P1 (改进性)
1. **文档过滤逻辑重复** (Phase 1)
   - 位置: RomImportService.ets + RuntimeRomCatalog.ets
   - 解决方案: 抽取到共享模块

2. **CUE 依赖文件手动选择** (Phase 2)
   - 影响: 用户体验差
   - 解决方案: 实施 Phase 2.5 (自动解析依赖)

3. **临时文件无自动清理** (Phase 2)
   - 影响: 磁盘占用
   - 解决方案: EntryAbility 生命周期清理

---

## 验证结果

### Phase 1 验证 ✅

```bash
==== quick_signals summary ====
  regression   PASS  (27s)
  hygiene      PASS  (9s)
  ui-fixes     PASS  (15s)
  skill-contract PASS  (37s)
  cxx-build    PASS  (1s)

==== ALL PASS / SKIP ====
```

### Phase 2-3 验证 ⚠️

未实施，无法验证。建议在独立 epic 中完整测试：
- Phase 2: 内置/下载/CUE 三种 ROM 加载场景
- Phase 3: Library UI 显示 metadata 字段、搜索筛选功能

---

## 产出物清单

### 代码提交
1. `2e96b42` - feat(library): UI polish for foldable devices
2. `d7284fd` - docs(m1): add Phase 2 ROM sandbox audit and design
3. `27ce056` - docs(m1): add Phase 3 metadata audit, mark Phase 2-3 BLOCKED

### 文档
1. `docs/plans/2026-05-31-m1-rom-io-closure-progress.md` - 进度跟踪
2. `docs/plans/phase1-dirty-changes-audit.md` - Phase 1 审计日志
3. `docs/plans/phase2-rom-path-audit.md` - Phase 2 路径审计
4. `docs/plans/phase2-rom-sandbox-design.md` - Phase 2 沙盒设计
5. `docs/plans/phase3-library-metadata-audit.md` - Phase 3 metadata 审计
6. `docs/blockers.md` - 阻塞项记录
7. `docs/plans/2026-05-31-m1-rom-io-closure.md` - 本文档

---

## 后续行动

### 立即行动
1. ✅ 提交本 closure 报告
2. ✅ 更新 Roadmap.md (标记 M1 为 Partial)

### 后续规划
1. **M1.2 epic**: ROM 沙盒统一 (预计 1-2 天)
2. **M1.3 epic**: Library metadata 扩展 (预计 2-3 天)
3. **M2 epic**: 技术债清理 (P1 优先级)

---

## 经验教训

### 成功经验
1. **分阶段审计**: Phase 1-3 先审计再设计，避免盲目实施
2. **及时 BLOCKED**: 识别超时任务立即标记，不强行推进
3. **文档先行**: 设计文档完整，后续实施有据可依

### 改进建议
1. **任务拆分**: 单任务预估时间应 ≤30 分钟，Phase 2-3 应拆分为更小粒度
2. **架构审计前置**: 应在 epic 规划阶段识别双 Repository 等架构问题
3. **跨层改动独立规划**: C++/ArkTS 跨层任务应作为独立 epic，预留编译测试时间

---

## 结论

M1 epic **Phase 1 完成度 100%**，Phase 2-3 因架构重构复杂度而 BLOCKED。建议：
1. **Phase 1 成果可直接合并主分支** (已验证通过)
2. **Phase 2-3 作为独立 epic 重新规划** (M1.2/M1.3)
3. **本次会话产出的审计和设计文档** 为后续实施提供完整技术方案

**M1 epic 状态**: Partial Completion → 建议拆分为 M1 (Phase 1) + M1.2 (Phase 2) + M1.3 (Phase 3)
