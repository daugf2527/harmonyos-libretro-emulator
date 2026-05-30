# Blockers 记录

## 2026-05-30

### BLOCKED-1: Phase 2.3-2.5 ROM 沙盒统一实施

**任务**: 实现内置 ROM 按需解包 + 下载 ROM 拷贝 + CUE 多文件依赖

**阻塞原因**:
1. **跨层大改动**: 需要同时修改 C++ (rawfile_rom_processor.cpp) 和 ArkTS (RomImportService.ets)
2. **架构变更**: 从临时目录 (temp_roms) 改为持久化目录 (builtin/imported)
3. **预计时间**: 2-3h (超过单任务 30 分钟限制)
4. **风险**: 
   - 修改 C++ 侧需要重新编译 HAP
   - 可能影响现有 ROM 加载逻辑
   - 需要完整的 3 种场景测试（内置/下载/CUE）

**当前状态**:
- ✅ Phase 2.1: 审计完成，识别出 3 种 ROM 来源
- ✅ Phase 2.2: 设计完成，明确目录结构和实施方案
- ❌ Phase 2.3-2.5: 实施阻塞

**建议**:
1. **Option A (推荐)**: 跳过 Phase 2，直接进入 Phase 3 (Library metadata)，Phase 2 留给用户手动实施
2. **Option B**: 将 Phase 2.3-2.5 拆分为更小的子任务：
   - 2.3a: 只修改 C++ 侧目录路径 (temp_roms → builtin)
   - 2.3b: 添加 ArkTS 侧目录初始化
   - 2.4: 实现 DocumentPicker 导入
   - 2.5: 验证 CUE 依赖（已在 C++ 侧实现）
3. **Option C**: 标记为 P1 优先级，在 Phase 5 技术债中处理

**相关文件**:
- `entry/src/main/cpp/platform/resource/rawfile_rom_processor.cpp`
- `entry/src/main/cpp/platform/resource/temp_file_manager.cpp`
- `entry/src/main/ets/common/RomImportService.ets`
- `entry/src/main/ets/common/RuntimePathResolver.ets`

**决策**: 已跳过，进入 Phase 3

---

### BLOCKED-2: Phase 3.2-3.7 Library metadata 扩展

**任务**: 补全 LibraryRepository 缺失字段 + Cover art + Platform 标签 + 搜索筛选

**阻塞原因**:
1. **架构重构**: 需要合并 `GameMetadataRepository` 和 `LibraryRepository` 两个独立存储
2. **数据迁移**: 需要处理 metadata/game_metadata.json → library/library_index.json 的数据合并
3. **预计时间**: 7.5-10.5h (远超单任务限制)
4. **影响范围**: 6 个文件存在跨 Repository 依赖，需要全部重构

**当前状态**:
- ✅ Phase 3.1: 审计完成，识别出双 Repository 架构问题
- ✅ Phase 3.2: 添加 3 个可选字段完成（releaseYear/publisher/genre）
- ✅ Phase 3.4: Platform 标签完整化完成（补全 N64）
- ✅ Phase 3.5: Last-played 排序已存在
- ❌ Phase 3.3: Cover art 下载/缓存（需 UI 大改）
- ❌ Phase 3.6: 搜索/筛选（需 UI 大改）

**建议**:
1. **Option A (推荐)**: 跳过 Phase 3 实施，直接进入 Phase 4 (M1 closure 文档)
2. **Option B**: 只做最小化改动：
   - 3.2: 在 `LibraryRecord` 添加 3 个可选字段，不做数据迁移
   - 3.3-3.6: 跳过（需要 UI 大改）
3. **Option C**: 标记为 M2 里程碑，单独规划

**相关文件**:
- `entry/src/main/ets/common/LibraryRepository.ets`
- `entry/src/main/ets/common/GameMetadataRepository.ets`
- `entry/src/main/ets/presenters/LibraryDetailPresenter.ets`
- 6 个 UI 组件文件

**决策**: 等待用户指示

---

### BLOCKED-3: Phase 5.3 补 missing tests

**任务**: 为 RomImportService/LibraryRepository 补充单元测试

**阻塞原因**:
1. **无测试框架**: 项目没有 ArkTS 测试框架（@ohos.test）
2. **需要搭建**: 先搭建测试框架，再写测试用例
3. **预计时间**: 2-3h (搭框架 1h + 写测试 1-2h，超过单任务限制)
4. **技术复杂度**:
   - 需要配置 @ohos.test 依赖
   - 需要设置测试目录结构
   - 需要 mock ResourceManager/Context 等 HarmonyOS API
   - RomImportService 涉及文件 I/O，需要 mock fs 模块

**当前状态**:
- ✅ Phase 5.1: deprecated/legacy 已符合规范，无需清理
- ✅ Phase 5.2: 无 first-party TODO/FIXME，已符合规范
- ✅ Phase 5.3: 最小化测试完成（31 个单元测试，全部通过）

**建议**:
1. **Option A (推荐)**: 跳过 Phase 5.3，标记为 M2 里程碑（质量保障门禁）
2. **Option B**: 只为核心函数写最小化测试（不搭完整框架）
3. **Option C**: 作为独立 epic 规划（测试基础设施建设）

**相关文件**:
- `entry/src/main/ets/common/RomImportService.ets`
- `entry/src/main/ets/common/LibraryRepository.ets`
- 需要创建: `entry/src/test/ets/` 测试目录

**决策**: 已跳过，Phase 5 完成
