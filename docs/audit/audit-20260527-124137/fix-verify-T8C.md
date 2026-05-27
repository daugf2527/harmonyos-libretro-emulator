# fix-verify-T8C — ArkTS 持久化层 fix 验证

**验证时间**: 2026-05-27  
**验证员**: T8-F-C 子代理（只读，不改代码，不跑构建）  
**对应审计**: `agent-T8C-arkts.md`

---

## 总结

| Finding | 严重性 | 判定 | 说明 |
|---------|--------|------|------|
| T8C-F1 | P1 | **COMPLETE** | writeArrayBufferToFile 全 async，saveStateData 已 await |
| T8C-F2 | P1 | **PARTIAL** | ENOENT rethrow 逻辑正确；errno undefined 时容忍存在误容范围，见详述 |
| T8C-F3+F7 | P1+P2 | **PARTIAL** | manifest 过滤机制正确，但 matchesBaseName 前缀匹配仍无法命中完整路径格式的 romFile |
| T8C-F4 | — | **SKIP** (DESIGN) | 主 Claude 判定跳过 |
| T8C-F5 | P1 | **COMPLETE** | await 后 pageActive 检查已加，结构正确 |
| T8C-F6 | — | **SKIP** (DESIGN) | 主 Claude 判定跳过 |
| T8C-F8 | P2 | **COMPLETE** | 改 refactoredSaveStateAsync，isCurrentPageTask token 检查已加 |

---

## 逐项验证详情

---

### T8C-F1 — writeArrayBufferToFile 同步阻塞 → COMPLETE

**验证文件**: `entry/src/main/ets/common/SaveStateRepository.ets`

**验证结论**: COMPLETE

**依据**:

1. `writeArrayBufferToFile` 函数签名改为 `async function writeArrayBufferToFile(path: string, data: ArrayBuffer): Promise<void>`（L235）。
2. 内部全部改为 async 版本：`await fs.open`（L241）、`await fs.write`（L245）、`await fs.close`（L246）、`await fs.rename`（L248）。
3. `saveStateData` 调用处已改为 `await writeArrayBufferToFile(targetPath, data)`（L44），注释明确标注 `T8-C-F1`。
4. ast-grep 全扫 `fs.openSync`、`fs.writeSync`、`fs.renameSync`、`fs.closeSync` 在 `entry/src/main/ets` 下**零命中**——确认无同步残留。

**附注**: `saveManifest` 内的错误处理路径 L230 仍有 `fs.unlinkSync(tmpPath)`，这是**清理临时文件的 best-effort 调用**，发生在已 catch 的错误路径中且结果被忽略（`catch (_) {}`），不属于 T8C-F1 描述的"主路径同步 I/O 阻塞"问题，行为可接受。

---

### T8C-F2 — deleteSaveStateItem 静默继续 → PARTIAL

**验证文件**: `entry/src/main/ets/common/SaveStateRepository.ets` L103-129

**验证结论**: PARTIAL

**正确部分**:

1. catch 块不再无条件继续：当 `errno !== undefined && errno !== ERR_CODE_ENOENT && errno !== ERR_CODE_ENOENT_NUM` 时，执行 `throw err as Error`（L117-118），阻断 manifest 更新。
2. `ERR_CODE_ENOENT = '13900002'`、`ERR_CODE_ENOENT_NUM = 13900002`（L135-136）对应 HarmonyOS CoreFileKit 的字符串错误码（`'13900002'`）和数值等价形式，常见 ENOENT 场景覆盖。

**残余问题**:

注释 L120 写道：`// 文件本就不存在,或 errno 不明: 走容忍路径,清理 manifest`。

当前条件逻辑：
```typescript
if (errno !== undefined && errno !== ERR_CODE_ENOENT && errno !== ERR_CODE_ENOENT_NUM) {
  throw ...
}
// 否则：errno === undefined 或 errno === ENOENT → 容忍
```

**`errno === undefined` 时容忍并清理 manifest 存在误容风险**：  
- HarmonyOS `fs.unlink` 抛出的错误通常有 `.code` 字段（`BusinessError` 类型）；
- 但 `ErrorWithCode` 是局部定义的 `interface { code?: string | number }`，若抛出的是原生 `TypeError`（如参数类型错误）或非 `BusinessError` 对象，`code` 字段确实为 `undefined`；
- 此时代码会走容忍路径——即"按文件不存在处理"，继续清理 manifest，但文件实际上**因为 API 调用错误根本没有尝试删除**（例如路径构造 bug）。

**影响评估**: 低概率，HarmonyOS `fs.unlink` 在正常使用下始终返回 `BusinessError`；但严格来说这个容忍范围比 audit 建议的 "ENOENT 容忍、其他 rethrow" 宽了一点。这是一个可接受的 trade-off，不是完全错误，因此评为 PARTIAL 而非 REGRESSION。

---

### T8C-F3+F7 — purgeSaveFilesForBaseName manifest 过滤 → PARTIAL

**验证文件**: `entry/src/main/ets/common/LibrarySaveFilePurger.ets`

**验证结论**: PARTIAL

**正确部分 (F3 修复)**:

1. 旧实现对文件名前缀匹配（永远0命中）已被完全删除，替换为基于 `listSaveStateItems(context)` 加载 manifest 再过滤的正确架构（L33-34）。
2. 删除成功后调用 `pruneManifestForFileNames(context, removedFileNames)`（L64），解决 manifest 与磁盘不一致问题（F3 核心问题）。
3. 取消（cancel）路径 L43 也调用 `pruneManifestForFileNames`，确保中途取消时已删文件从 manifest 清除，磁盘和 manifest 保持一致。
4. 非 ENOENT 错误路径 L58 在 throw 前先调 prune，保证 partial deletion 后 manifest 同步。
5. `pruneManifestForFileNames` 已正确 export，LibrarySaveFilePurger 从 SaveStateRepository import（L9），无循环依赖（SaveStateRepository 不 import LibrarySaveFilePurger，已确认）。

**残余问题 (F7 仅部分修复)**:

`matchesBaseName` 的实现（L71-74）：
```typescript
function matchesBaseName(romFile: string, normalizedBaseName: string): boolean {
  const normalized = normalizeContentKey(romFile)
  return normalized.length > 0 && normalized.indexOf(normalizedBaseName) === 0
}
```

匹配逻辑仍是**前缀匹配**，只是比对对象从"文件名"改为了"manifest 里的 romFile 字段"。  
问题在于 manifest 里的 `item.romFile` 是存档时 `saveStateData` 调用方传入的值，而该值来自 `LibraryRecord.romFile`，格式为：
- 内置 ROM：`roms/Super_Mario_Bros.nes`
- 导入 ROM：`/data/storage/el2/base/haps/entry/files/roms/Super_Mario_Bros.nes`（绝对路径）

而两个调用方传入的 `baseName` 格式分别为：
- `LibraryDetailPage` L400：`cleanLibraryFileName(target.fileName)` = `Super Mario Bros`（去掉扩展名，`_-` 换空格）
- `LibraryPage` L669：`target.fileName` = `Super_Mario_Bros.nes`（原始文件名）

经 `normalizeContentKey` 处理后：
- baseName：`cleanLibraryFileName` 路径 → `"supermariobros"`
- baseName：`fileName` 路径 → `"supermariobroses"`（含扩展名）
- romFile：`"romssupermariobroses"` 或 `".../romssupermariobroses"`

`"romssupermariobroses".indexOf("supermariobros") === 4`，**不是 0，前缀匹配失败**。

**结论**: F3（manifest 不同步）已 COMPLETE 修复；F7（匹配逻辑）仅改了被比较的字段来源，但匹配算法（前缀匹配）和格式不兼容问题未解决。`purgeSaveFilesForBaseName` 在实际调用中**仍然会返回 `deletedCount: 0`**，功能等于未修复。

**建议修复路径**: `matchesBaseName` 应改为 `includes` 而非 `indexOf(...) === 0`；或在调用方把 `baseName` 统一传 `romFile`（完整路径），或在 `matchesBaseName` 内提取 `romFile` 的文件名部分再比较。最简单且正确的改法：
```typescript
function matchesBaseName(romFile: string, normalizedBaseName: string): boolean {
  const normalized = normalizeContentKey(romFile)
  return normalized.length > 0 && normalized.includes(normalizedBaseName)
}
```
但还需要 `LibraryPage` 侧统一去掉扩展名，与 `LibraryDetailPage` 调用形式对齐。

---

### T8C-F5 — quickSaveRuntimeState / quickLoadRuntimeState 无 token 检查 → COMPLETE

**验证文件**: `entry/src/main/ets/pages/LibretroGamePage.ets` L301-327

**验证结论**: COMPLETE

**依据**:

1. `quickSaveRuntimeState`（L301-313）：先 `const result = await ...quickSave(...)`，然后 `if (!this.pageActive) return`（L309-311），再 `this.runtimeSaveStatusText = result`（L312）。注释标注 `T8-C-F5`。
2. `quickLoadRuntimeState`（L315-327）：结构完全相同，同样有 `if (!this.pageActive) return`（L323-325）检查。
3. `result` 是局部变量，模式 `const result = await ...; if (!pageActive) return; this.xxx = result` 是标准安全的 lifecycle guard 模式——await 期间离页时 `pageActive` 置 false，检查后立即 return，不执行 `@State` 写入。

---

### T8C-F8 — SaveStatePage.quickSave 同步 NAPI → COMPLETE

**验证文件**: `entry/src/main/ets/pages/SaveStatePage.ets` L241-272

**验证结论**: COMPLETE

**依据**:

1. L17 在 `SaveStateNapi` interface 中声明 `refactoredSaveStateAsync(): Promise<ArrayBuffer | null>`，ArkTS 类型安全（不再是 `refactoredSaveState(): ArrayBuffer`）。
2. L250：`const stateData = await nativeApi.refactoredSaveStateAsync()`，已改为 async 调用。
3. L251-253：await 之后有 `if (!this.isCurrentPageTask(token)) return` 检查，防止离页后继续写 `@State`。
4. L259：`await saveStateData` 后再次有 `isCurrentPageTask` 检查（L260-262），多个 await 点均有保护。
5. `RuntimeSessionController.ets` L26 已有对应的 `refactoredSaveStateAsync` 声明（L26），SaveStatePage 侧的独立 interface 声明（L17）与之同构，不构成冲突。

---

## REGRESSION 检查

| 检查项 | 结果 |
|--------|------|
| SaveStateRepository 是否 import LibrarySaveFilePurger | 否，无循环依赖 |
| pruneManifestForFileNames 并发安全 | ArkTS 单线程，microtask 交错是已知架构观察 3（T8C 原报告），非新引入 |
| unlinkSync in saveManifest catch 路径 | 可接受（best-effort tmp 清理，在 catch 中执行且结果被忽略） |
| LibraryPage 侧调用 purgeSaveFilesForBaseName 无 token 检查 | 有 `isCurrentPageAction(actionToken)` 作为 shouldContinue 回调传入 |

---

## 状态统计

| 状态 | 数量 | Finding IDs |
|------|------|-------------|
| COMPLETE | 3 | T8C-F1, T8C-F5, T8C-F8 |
| PARTIAL | 2 | T8C-F2 (epsilon-容忍范围), T8C-F3+F7 (matchesBaseName 前缀匹配仍失效) |
| MISSING | 0 | — |
| REGRESSION | 0 | — |
| SKIP | 2 | T8C-F4, T8C-F6 |

**需要后续跟进**: T8C-F3+F7 的 `matchesBaseName` 功能性问题——purge 功能在实际场景下仍会返回 `deletedCount: 0`（`indexOf` 的 F7 前缀匹配问题未修复）。建议在 T8-G 之前补一行修复，否则"清除存档"功能对用户不可用。

---

*验证完成。未编译，未真机运行，所有判定均为静态代码分析。*  
*T8-F-C 子代理，2026-05-27*
