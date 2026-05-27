# T8-C ArkTS 持久化层审计 (SaveState / SRAM / Disk I/O)

**审计时间**: 2026-05-27  
**审计范围**: ArkTS SaveState / SRAM 持久化层  
**审计员**: T8-C 子代理  
**状态**: 完成

---

## 审计文件

| 文件 | 简述 |
|------|------|
| `entry/src/main/ets/common/SaveStateRepository.ets` | 存档文件 I/O、manifest 管理 |
| `entry/src/main/ets/common/RuntimeSaveStateController.ets` | 运行态快速存/读档控制器 |
| `entry/src/main/ets/common/RuntimeSessionController.ets` | NAPI 桥接层（saveState/loadState） |
| `entry/src/main/ets/common/LibrarySaveFilePurger.ets` | 按 ROM 清除所有存档文件 |
| `entry/src/main/ets/pages/SaveStatePage.ets` | 存档管理 UI 页面 |
| `entry/src/main/ets/pages/LibretroGamePage.ets` | 游戏运行页（quickSave/quickLoad） |
| `entry/src/main/ets/pages/LibraryDetailPage.ets` | 库详情页（purge_save 入口） |
| `entry/src/main/ets/common/LibretroEventHub.ets` | 事件总线（SaveState 相关事件：无命中） |

---

## Findings 汇总

| ID | 严重性 | 文件 | 问题 | 状态 |
|----|--------|------|------|------|
| T8C-F1 | P1 | `SaveStateRepository.ets` L43 | `writeArrayBufferToFile` 同步阻塞主线程 | REAL |
| T8C-F2 | P1 | `SaveStateRepository.ets` L102-118 | `deleteSaveStateItem` 删除文件失败后静默继续更新 manifest | REAL |
| T8C-F3 | P1 | `LibrarySaveFilePurger.ets` L34+L41 | `purgeSaveFilesForBaseName` 删除文件后不更新 manifest，导致 manifest 与磁盘不一致 | REAL |
| T8C-F4 | P1 | `SaveStatePage.ets` L270-285 | `loadSave()` 缺 token 检查，离页后仍可向 native 注入存档数据 | REAL |
| T8C-F5 | P1 | `LibretroGamePage.ets` L301-317 | `quickSaveRuntimeState` / `quickLoadRuntimeState` 无 token 检查，await 后无保护回写 `@State` | REAL |
| T8C-F6 | P2 | `SaveStateRepository.ets` L37-43 | `.state` 文件写入在 manifest 更新之前（orphan 窗口），进程崩溃留下孤立文件 | REAL（已有注释记录，未修复） |
| T8C-F7 | P2 | `LibrarySaveFilePurger.ets` L45-47 | `isSaveCandidate` 基于前缀匹配，`normalizeContentKey` 可能误删 baseName 为另一 ROM 前缀时的存档 | REAL |
| T8C-F8 | P2 | `SaveStatePage.ets` L248-249 | `quickSave()` 使用同步 `nativeApi.refactoredSaveState()`（阻塞主线程），而 `RuntimeSaveStateController` 已切到 async | REAL |

---

## Findings 详细分析

### T8C-F1 — `writeArrayBufferToFile` 同步阻塞主线程（P1）

**文件**: `entry/src/main/ets/common/SaveStateRepository.ets` L43, L199-218

**问题描述**:  
`saveStateData()` 是一个 `async` 函数，但在内部直接调用了同步版本的 `writeArrayBufferToFile()`（L43），该函数内部使用 `fs.openSync`、`fs.writeSync`、`fs.renameSync`。GameBoy/GBA 等核心的存档数据可达 128 KB ~ 512 KB，在主线程同步写入会阻塞帧渲染，导致 UI 卡顿甚至触发 ArkUI 主线程超时警告。

**evidence_excerpt** (L37-43):
```typescript
export async function saveStateData(
  context: common.UIAbilityContext,
  data: ArrayBuffer,
  romFile: string
): Promise<SaveStateManifestItem> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  const createdAt = Date.now()
  const fileName = `state_${createdAt}.state`
  const targetPath = buildSaveFilePath(context.filesDir, fileName)
  // T6-F4: .state written before manifest; crash here leaves an orphan .state
  writeArrayBufferToFile(targetPath, data)  // ← 同步写入，无 await
```

**evidence_excerpt** (L199-218):
```typescript
function writeArrayBufferToFile(path: string, data: ArrayBuffer): void {
  const tmpPath = path + '.tmp'
  let file: fs.File | undefined = undefined
  try {
    file = fs.openSync(tmpPath, ...)    // 同步
    fs.writeSync(file.fd, data, ...)   // 同步
    fs.closeSync(file.fd)              // 同步
    file = undefined
    fs.renameSync(tmpPath, path)       // 同步
```

**对比**: 同一文件的 `saveManifest()` 已使用 async/await 版本（`fs.open`、`fs.write`、`fs.close`、`fs.rename`），`writeArrayBufferToFile` 遗漏了同样的迁移。

**修复方向**: 将 `writeArrayBufferToFile` 改为 `async`，内部用 `await fs.open`/`await fs.write`/`await fs.close`/`await fs.rename`，并在 `saveStateData` 中 `await writeArrayBufferToFile(...)`.

---

### T8C-F2 — `deleteSaveStateItem` 文件删除失败后静默继续更新 manifest（P1）

**文件**: `entry/src/main/ets/common/SaveStateRepository.ets` L102-119

**问题描述**:  
`deleteSaveStateItem()` 先 `await fs.unlink(...)` 删除文件，失败时仅 `LogHelper.warn` 然后**继续执行** `await saveManifest()`，将该条目从 manifest 中删除。结果是：文件仍在磁盘（可能是权限问题或路径错误），但 manifest 已不含该记录。下次 `listSaveStateItems()` 将无法找到该文件，形成永久孤立文件，用户数据永久不可访问。

**evidence_excerpt** (L102-119):
```typescript
export async function deleteSaveStateItem(
  context: common.UIAbilityContext,
  fileName: string
): Promise<void> {
  const safeName = sanitizeFileName(fileName)
  try {
    await fs.unlink(buildSaveFilePath(context.filesDir, safeName))
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Delete', `删除存档文件失败: ${message}`)
    // ← 此处没有 return 或 throw，继续执行 manifest 更新！
  }
  const document = await loadManifest(context)
  const nextItems = document.items.filter((item: SaveStateManifestItem) => item.fileName !== safeName)
  await saveManifest(context, { version: SAVE_STATE_VERSION, items: nextItems })
}
```

**修复方向**: 捕获 unlink 错误后应 re-throw（或至少对 `ENOENT` 容忍、其他错误 throw），不应无条件继续更新 manifest。只有文件确实不存在（`ENOENT`）时才安全地从 manifest 删除条目。

---

### T8C-F3 — `purgeSaveFilesForBaseName` 删除文件后不更新 manifest（P1）

**文件**: `entry/src/main/ets/common/LibrarySaveFilePurger.ets` L9-43

**问题描述**:  
该函数批量 `fs.unlink` 删除匹配的 `.state` 文件，但完全不调用 `SaveStateRepository` 的 manifest 更新逻辑。删除完成后，`manifest.json` 仍保留这些条目。之后 `SaveStatePage` 的 `listSaveStateItems()` 读取 manifest，会列出已删除的存档条目，点击"读档"时才会得到文件不存在错误，用户看到的是"存档列表不为空但读档失败"的混乱状态。

**evidence_excerpt** (L29-42):
```typescript
  for (let index = 0; index < candidates.length; index += 1) {
    if (!shouldContinue()) {
      return { deletedCount: index, cancelled: true }
    }
    try {
      await fs.unlink(`${saveDir}/${candidates[index]}`)
    } catch (err) {
      throw err as Error
    }
  }
  if (!shouldContinue()) {
    return { deletedCount: candidates.length, cancelled: true }
  }
  return { deletedCount: candidates.length, cancelled: false }
  // ← 返回前无 manifest 清理
```

**修复方向**: purge 完成后调用 `deleteSaveStateItem` 或自行调用 `SaveStateRepository` 内的 manifest 更新逻辑；或在 `LibraryDetailPage.deleteSaveFiles()` 调用后补一次 manifest reconcile。

---

### T8C-F4 — `loadSave()` 缺 PageLifecycleGuard token 检查（P1）

**文件**: `entry/src/main/ets/pages/SaveStatePage.ets` L270-285

**问题描述**:  
`loadSave()` 是 async 方法（虽然此处实际上没有 await，全部是同步调用），但其调用的 `readSaveStateData()` 是一个**同步文件 I/O 调用**，而 `nativeApi.refactoredLoadState(stateData)` 是同步 NAPI 调用。虽然当前路径全同步无挂起点，但有两个问题：

1. **`readSaveStateData` 大文件场景**：对大文件（PS1/GBA 存档可达 1MB+），同步 `fs.readSync` 可阻塞主线程。
2. **缺少 token 防护**：如果将来任何 await 插入（比如将 `readSaveStateData` 异步化），方法签名已是 `async` 但无 token 检查，会遗漏保护。与 `quickSave`/`confirmDelete`/`refreshSaveItems` 三个方法相比，`loadSave` 是唯一一个没有 token 检查的异步路径。

**evidence_excerpt** (L270-285):
```typescript
private async loadSave(fileName: string): Promise<void> {
  const context = this.getContext()
  if (!context) {
    this.showToastMessage('CONTEXT_MISSING')
    return
  }
  try {
    const stateData = readSaveStateData(context, fileName)  // 同步 I/O，无 token
    const loaded = nativeApi.refactoredLoadState(stateData) // 同步 NAPI，无 token
    this.showToastMessage(loaded ? 'SAVE_STATE_LOADED' : 'LOAD_STATE_REJECTED')
  } catch (err) {
    ...
  }
}
```

对比同一文件的 `quickSave()`（L241-268）有完整 `token = this.beginPageTask()` 和 `if (!this.isCurrentPageTask(token)) return` 保护。

**修复方向**: 在 `loadSave()` 头部加 `const token = this.beginPageTask()`，在 `readSaveStateData` 调用后（若异步化）和 `showToastMessage` 写 `@State` 前加 token 检查；或将 `readSaveStateData` 迁移为 async 并补齐 token 检查。

---

### T8C-F5 — `quickSaveRuntimeState` / `quickLoadRuntimeState` 无 token 检查（P1）

**文件**: `entry/src/main/ets/pages/LibretroGamePage.ets` L301-317

**问题描述**:  
这两个方法在 `await runtimeSaveStateController.quickSave/quickLoad(...)` 完成后会回写 `this.runtimeSaveStatusText`（`@State` 变量）。如果用户在 await 挂起期间离开页面（`aboutToDisappear()` 被调用），`pageActive` 已置 false，但代码没有检查 `pageActive`，仍然执行回写。虽然写一个 `@State` 字符串不会崩溃，但：

1. 对已销毁的页面实例写 `@State` 在 HarmonyOS 实测中可能触发 UI 更新异常。
2. 与页面其他所有 async 方法（如 `switchGame` 用 `switchToken` + `isCurrentSwitchTask`）形成不一致风格。
3. `quickSave` 链路包含多个 await（`saveStateAsync` + `saveStateData` + `loadManifest` + `saveManifest`），挂起窗口明显。

**evidence_excerpt** (L301-317):
```typescript
private async quickSaveRuntimeState(): Promise<void> {
  const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  this.runtimeSaveStatusText = await this.runtimeSaveStateController.quickSave(
    context,
    this.gameRunning,
    this.getCurrentRuntimeRomFile()
  );
  // ← await 后无 pageActive 检查，直接回写 @State
}

private async quickLoadRuntimeState(): Promise<void> {
  const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  this.runtimeSaveStatusText = await this.runtimeSaveStateController.quickLoad(
    context,
    this.gameRunning,
    this.getCurrentRuntimeRomFile()
  );
  // ← 同样缺少检查
}
```

**修复方向**: 在 await 后加 `if (!this.pageActive) return` 检查，再写 `this.runtimeSaveStatusText`。

---

### T8C-F6 — `.state` 文件先写、manifest 后更新的孤立文件窗口（P2）

**文件**: `entry/src/main/ets/common/SaveStateRepository.ets` L36-62

**问题描述**:  
`saveStateData()` 先调用 `writeArrayBufferToFile(targetPath, data)` 写入 `.state` 文件（L43），然后才 `await loadManifest(context)` 并 `await saveManifest(...)` 更新 manifest（L51-62）。两步之间存在进程崩溃窗口：`.state` 文件写完、manifest 未更新，导致孤立存档文件（代码注释 L41-42 已记录此风险，但未修复）。

孤立文件的影响：不出现在存档列表，占用存储空间，`buildManifestFromDirectory` 恢复路径可以扫描到但 `romFile` 为空字符串，用户无法判断该存档属于哪个 ROM。

**evidence_excerpt** (L41-43):
```typescript
// T6-F4: .state written before manifest; crash here leaves an orphan .state (no romFile association).
// Mitigated by T6-F3 (both writes are atomic), but a process kill between the two steps is still possible.
writeArrayBufferToFile(targetPath, data)
```

**修复方向**（中等代价）：将写入顺序颠倒——先更新 manifest（加入待写条目但标记为 `pending`），再写 `.state`，成功后 manifest 状态改为 `complete`；或接受当前设计（先写文件）但在 `buildManifestFromDirectory` 恢复路径中通过文件名时间戳匹配 romFile。

---

### T8C-F7 — `isSaveCandidate` 前缀匹配可能误删存档（P2）

**文件**: `entry/src/main/ets/common/LibrarySaveFilePurger.ets` L45-47

**问题描述**:  
`isSaveCandidate` 判断一个存档文件是否属于某个 ROM，使用 `normalizeContentKey(fileName).indexOf(normalizedBaseName) === 0`（前缀匹配）。`normalizeContentKey` 会将文件名转小写、去掉所有非字母数字字符（`.`, `_`, `-`, 空格均被删除）。

**场景举例**：  
- ROM A：`Super Mario Bros.nes` → `supermariobros`  
- ROM B：`Super Mario Bros 3.nes` → `supermariobros3`  
- ROM C：`Super Mario Bros - Japan.nes` → `supermariobrosjapan`

当调用 `purgeSaveFilesForBaseName(context, "Super Mario Bros", ...)` 时，`normalizedBaseName = "supermariobros"`，文件 `state_1234567890.state`（存档文件名包含时间戳，不含 ROM 名）实际上不会匹配——**因为当前存档文件名格式是 `state_<timestamp>.state`**，`normalizeContentKey("state_1234567890.state") = "state1234567890state"`，不以 `"supermariobros"` 开头。

**实际影响**：`purgeSaveFilesForBaseName` 可能永远匹配不到任何文件（返回 `deletedCount: 0`），因为存档文件名 `state_<timestamp>.state` 和 `baseName`（来自 ROM 文件名）之间没有关联。这导致"清除存档"功能实际上**总是静默失败**，向用户展示 `SAVE_EMPTY` 的假状态。

**evidence_excerpt** (L45-51):
```typescript
function isSaveCandidate(fileName: string, normalizedBaseName: string): boolean {
  const normalized = normalizeContentKey(fileName)
  return normalized.indexOf(normalizedBaseName) === 0
}

function normalizeContentKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '')
}
```

存档文件名格式（`SaveStateRepository.ets` L39）：
```typescript
const fileName = `state_${createdAt}.state`  // 如: state_1748339000000.state
```

**修复方向**：`purgeSaveFilesForBaseName` 应该基于 manifest（`listSaveStateItems`）的 `romFile` 字段过滤存档，而非文件名前缀匹配。正确路径：加载 manifest → 过滤 `item.romFile` 匹配的条目 → 删除对应文件 → 更新 manifest。

---

### T8C-F8 — `SaveStatePage.quickSave()` 使用同步 NAPI 而非 async 版本（P2）

**文件**: `entry/src/main/ets/pages/SaveStatePage.ets` L249

**问题描述**:  
`SaveStatePage.quickSave()` 使用 `nativeApi.refactoredSaveState()`（同步版本，L249），该调用会在主线程序列化存档数据，阻塞时间与 ROM core 存档大小成正比（PS1 saves 可达 1MB+）。

对比 `RuntimeSaveStateController.quickSave()` 已使用 `runtimeSessionController.saveStateAsync()`（L25，异步版本）。`SaveStatePage` 和 `RuntimeSaveStateController` 有功能重叠但实现不一致。

**evidence_excerpt** (L248-254):
```typescript
try {
  const stateData = nativeApi.refactoredSaveState()  // ← 同步！阻塞主线程
  if (!stateData || stateData.byteLength <= 0) {
    this.showToastMessage('SAVE_STATE_UNAVAILABLE')
    return
  }
  await saveStateData(context, stateData, this.currentRomFile)
```

对比 `RuntimeSaveStateController` (L25):
```typescript
const stateData = await runtimeSessionController.saveStateAsync()  // ← 异步
```

**修复方向**: 将 `SaveStatePage.quickSave()` 的 NAPI 调用改为 `nativeApi.refactoredSaveStateAsync()` 并 await，需在 SaveStatePage 中引入 `RuntimeSessionNapi` 接口的 async 方法声明，或直接复用 `RuntimeSaveStateController.quickSave()`。

---

## 不计入 findings 的已知情况

| 项 | 说明 |
|----|------|
| `saveManifest` 原子写（tmp+rename） | 已正确实现，`saveManifest()` 和 `writeArrayBufferToFile()` 均用 tmp+rename 模式，manifest 不会被半写 |
| `readSaveStateData` fd 资源清理 | 有 `try/finally` + `fs.closeSync`，无 fd leak |
| `sanitizeFileName` 路径注入防护 | `replace(/[\\\/]/g, '')` 去除 `\` 和 `/`，防止目录遍历；`buildSaveFilePath` 构造绝对路径在 `filesDir/saves/` 下，无法逃出沙箱 |
| `ensureDirExists` 异常处理 | `try/catch` 静默忽略（已有目录时 mkdir 会抛 EEXIST），行为正确 |
| `SaveStatePage` pageTaskToken lifecycle | `refreshSaveItems`/`quickSave`/`confirmDelete` 均有完整 token 保护，`aboutToDisappear` 清理 timer |
| `LibraryDetailPage.deleteSaveFiles()` | pageTaskToken + `isCurrentPageTask` 正确传给 `purgeSaveFilesForBaseName` 的 `shouldContinue` 回调 |
| `LibretroGamePage` `switchGame` 保护 | `isCurrentSwitchTask` 在每个 await 点均有检查 |
| ForEach key 稳定性 | `SaveStatePage.ArchiveList` 使用 `item.id` 作为 key（L536），id 来自 sanitizedFileName，稳定 |
| `deleteSaveStateItem` ENOENT 容忍 | 删文件失败 warn 而不 throw，对"文件已不存在"情况有一定容忍，但副作用是静默继续（见 T8C-F2） |

---

## 架构观察（非 finding，供参考）

1. **双路存档逻辑**：`SaveStatePage` 直接调用 `nativeApi.refactoredSaveState()`，`LibretroGamePage` 通过 `RuntimeSaveStateController` 调用 `saveStateAsync()`。两条路径功能相同但实现不一致（同步 vs 异步），建议统一走 `RuntimeSaveStateController`。

2. **`purgeSaveFilesForBaseName` 与 `deleteSaveStateItem` 未协作**：存档删除有两条互不知情的代码路径——`SaveStatePage.confirmDelete` 调用 `deleteSaveStateItem`（正确更新 manifest），`LibraryDetailPage.deleteSaveFiles` 调用 `purgeSaveFilesForBaseName`（不更新 manifest）。这是 T8C-F3 的根本原因。

3. **`SaveStateRepository` 无并发保护**：manifest 读-改-写是三步操作，如果 `SaveStatePage.quickSave` 和 `RuntimeSaveStateController.quickSave`（来自 `LibretroGamePage`）并发调用，两者各自 `loadManifest` → 各自写 `saveManifest`，后写者会覆盖前写者的条目。ArkTS 单线程模型下并发指的是 microtask 交错（两次 `saveStateData` 的 await 点之间），概率低但可重现。

---

## P 级别说明

- **P0（未命中）**：存档 I/O 边界无 P0 级整体数据丢失路径（原子写已实现）
- **P1（4 项）**：T8C-F1/F2/F3/F4/F5（5项 P1，F4 和 F5 均为 P1）
- **P2（3 项）**：T8C-F6/F7/F8

---

*审计完成时间: 2026-05-27T13:xx*  
*未编译，未真机运行，所有 finding 均为静态代码分析结果。*
