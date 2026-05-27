import { common } from '@kit.AbilityKit'
import { fileIo as fs, ReadOptions, WriteOptions } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface SaveStateManifestItem {
  id: string
  fileName: string
  romFile: string
  createdAt: number
  byteLength: number
}

interface SaveStateManifestDocument {
  version: number
  items: SaveStateManifestItem[]
}

const SAVE_STATE_VERSION = 1
const SAVE_STATE_DIR_NAME = 'saves'
const SAVE_STATE_MANIFEST_FILE = 'manifest.json'

export async function listSaveStateItems(context: common.UIAbilityContext): Promise<SaveStateManifestItem[]> {
  const document = await loadManifest(context)
  const items: SaveStateManifestItem[] = []
  document.items.forEach((item: SaveStateManifestItem) => {
    items.push(normalizeManifestItem(item))
  })
  items.sort((left: SaveStateManifestItem, right: SaveStateManifestItem) => right.createdAt - left.createdAt)
  return items
}

export async function saveStateData(
  context: common.UIAbilityContext,
  data: ArrayBuffer,
  romFile: string
): Promise<SaveStateManifestItem> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  const createdAt = Date.now()
  const fileName = `state_${createdAt}.state`
  const targetPath = buildSaveFilePath(context.filesDir, fileName)
  // T6-F4: .state written before manifest; crash here leaves an orphan .state (no romFile association).
  // Mitigated by T6-F3 (both writes are atomic), but a process kill between the two steps is still possible.
  // T8-C-F1: writeArrayBufferToFile 改 async, 避免 PS1/GBA 等大存档 (128KB-1MB) 阻塞主线程。
  await writeArrayBufferToFile(targetPath, data)
  const item: SaveStateManifestItem = {
    id: fileName,
    fileName: fileName,
    romFile: romFile,
    createdAt: createdAt,
    byteLength: data.byteLength
  }
  const document = await loadManifest(context)
  const nextItems: SaveStateManifestItem[] = [item]
  document.items.forEach((existing: SaveStateManifestItem) => {
    if (existing.fileName !== fileName) {
      nextItems.push(normalizeManifestItem(existing))
    }
  })
  await saveManifest(context, {
    version: SAVE_STATE_VERSION,
    items: nextItems
  })
  return item
}

export function readSaveStateData(
  context: common.UIAbilityContext,
  fileName: string
): ArrayBuffer {
  const targetPath = buildSaveFilePath(context.filesDir, sanitizeFileName(fileName))
  let stat: fs.Stat
  try {
    stat = fs.statSync(targetPath)
  } catch (err) {
    throw err as Error
  }
  const byteLength = Number(stat.size)
  const data = new ArrayBuffer(byteLength)
  let file: fs.File | undefined = undefined
  try {
    file = fs.openSync(targetPath, fs.OpenMode.READ_ONLY)
    const readOptions: ReadOptions = {
      offset: 0,
      length: byteLength
    }
    const readLength = fs.readSync(file.fd, data, readOptions)
    if (readLength >= byteLength) {
      return data
    }
    return data.slice(0, Math.max(0, readLength))
  } catch (err) {
    throw err as Error
  } finally {
    if (file) {
      try {
        fs.closeSync(file.fd)
      } catch (_closeErr) {
      }
    }
  }
}

export async function deleteSaveStateItem(
  context: common.UIAbilityContext,
  fileName: string
): Promise<void> {
  const safeName = sanitizeFileName(fileName)
  try {
    await fs.unlink(buildSaveFilePath(context.filesDir, safeName))
  } catch (err) {
    // T8-C-F2: ENOENT (文件已不存在) 容忍——继续更新 manifest 清理孤立记录。
    // 其他错误 (EACCES / EBUSY / EIO) 必须 rethrow,不能静默吞掉后更新 manifest,
    // 否则会导致文件残留在磁盘但 manifest 已无记录 → 永久孤立文件,用户数据丢失。
    const errno = (err as ErrorWithCode).code
    const message = (err as Error).message || String(err)
    if (errno !== undefined && errno !== ERR_CODE_ENOENT && errno !== ERR_CODE_ENOENT_NUM) {
      LogHelper.error('SaveStateRepository', 'Delete', `删除存档文件失败 (code=${errno}): ${message}`)
      throw err as Error
    }
    // 文件本就不存在,或 errno 不明: 走容忍路径,清理 manifest
    LogHelper.warn('SaveStateRepository', 'Delete', `删除存档文件: ${message} (按文件不存在处理)`)
  }
  const document = await loadManifest(context)
  const nextItems = document.items.filter((item: SaveStateManifestItem) => item.fileName !== safeName)
  await saveManifest(context, {
    version: SAVE_STATE_VERSION,
    items: nextItems
  })
}

// T8-C-F2: HarmonyOS @kit.CoreFileKit 错误码类型 (file/cstd ENOENT 为 13900002, posix ENOENT 为 2).
export interface ErrorWithCode {
  code?: string | number
}
export const ERR_CODE_ENOENT = '13900002'
export const ERR_CODE_ENOENT_NUM: string | number = 13900002

// T8-C-F3: 提供给 LibrarySaveFilePurger 调用,删除文件后同步更新 manifest。
// 否则 SaveStatePage 仍显示已删存档条目,点击读档才报错。
export async function pruneManifestForFileNames(
  context: common.UIAbilityContext,
  removedFileNames: string[]
): Promise<void> {
  if (removedFileNames.length === 0) {
    return
  }
  const removedSet = new Set<string>()
  removedFileNames.forEach((name: string) => { removedSet.add(sanitizeFileName(name)) })
  const document = await loadManifest(context)
  const nextItems = document.items.filter((item: SaveStateManifestItem) => !removedSet.has(item.fileName))
  await saveManifest(context, {
    version: SAVE_STATE_VERSION,
    items: nextItems
  })
}

async function loadManifest(context: common.UIAbilityContext): Promise<SaveStateManifestDocument> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  const manifestPath = buildManifestPath(context.filesDir)
  try {
    const text = await fs.readText(manifestPath)
    if (!text || text.length === 0) {
      return createEmptyManifest()
    }
    const parsed = JSON.parse(text) as SaveStateManifestDocument
    const items: SaveStateManifestItem[] = []
    if (parsed.items) {
      parsed.items.forEach((item: SaveStateManifestItem) => {
        items.push(normalizeManifestItem(item))
      })
    }
    return {
      version: SAVE_STATE_VERSION,
      items: items
    }
  } catch (err) {
    return await buildManifestFromDirectory(context)
  }
}

async function buildManifestFromDirectory(context: common.UIAbilityContext): Promise<SaveStateManifestDocument> {
  const saveDir = buildSaveDirPath(context.filesDir)
  const items: SaveStateManifestItem[] = []
  try {
    const entries = await fs.listFile(saveDir)
    for (let index = 0; index < entries.length; index += 1) {
      const fileName = entries[index]
      if (!fileName.endsWith('.state')) {
        continue
      }
      const path = buildSaveFilePath(context.filesDir, fileName)
      const stat = await fs.stat(path)
      items.push({
        id: fileName,
        fileName: fileName,
        romFile: '',
        createdAt: readTimestampFromFileName(fileName),
        byteLength: Number(stat.size)
      })
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Index', `扫描存档目录失败: ${message}`)
  }
  return {
    version: SAVE_STATE_VERSION,
    items: items
  }
}

async function saveManifest(
  context: common.UIAbilityContext,
  document: SaveStateManifestDocument
): Promise<void> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  // Audit T6-F3: tmp+rename atomic write — crash during write leaves .tmp, not a corrupt manifest
  const manifestPath = buildManifestPath(context.filesDir)
  const tmpPath = manifestPath + '.tmp'
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(tmpPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(document, null, 2))
    await fs.close(file.fd)
    file = undefined
    await fs.rename(tmpPath, manifestPath)
  } catch (err) {
    if (file) {
      try { await fs.close(file.fd) } catch (_) {}
    }
    try { fs.unlinkSync(tmpPath) } catch (_) {}
    throw err as Error
  }
}

async function writeArrayBufferToFile(path: string, data: ArrayBuffer): Promise<void> {
  // Audit T6-F3: tmp+rename atomic write — crash during write leaves .tmp, not a corrupt .state
  // T8-C-F1: async fs.* avoids blocking main thread on 128KB-1MB save serialization.
  const tmpPath = path + '.tmp'
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const writeOptions: WriteOptions = {
      length: data.byteLength
    }
    await fs.write(file.fd, data, writeOptions)
    await fs.close(file.fd)
    file = undefined
    await fs.rename(tmpPath, path)
  } catch (err) {
    if (file) {
      try { await fs.close(file.fd) } catch (_) {}
    }
    try { await fs.unlink(tmpPath) } catch (_) {}
    throw err as Error
  }
}

function normalizeManifestItem(item: SaveStateManifestItem): SaveStateManifestItem {
  return {
    id: sanitizeFileName(item.id.length > 0 ? item.id : item.fileName),
    fileName: sanitizeFileName(item.fileName),
    romFile: item.romFile ?? '',
    createdAt: normalizeNumber(item.createdAt),
    byteLength: normalizeNumber(item.byteLength)
  }
}

function createEmptyManifest(): SaveStateManifestDocument {
  return {
    version: SAVE_STATE_VERSION,
    items: []
  }
}

function readTimestampFromFileName(fileName: string): number {
  const matches = fileName.match(/[0-9]{10,}/)
  if (!matches || matches.length === 0) {
    return 0
  }
  return normalizeNumber(Number(matches[0]))
}

function normalizeNumber(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0
  }
  return Math.floor(value)
}

function sanitizeFileName(fileName: string): string {
  return fileName.replace(/[\\\/]/g, '').trim()
}

function buildSaveDirPath(filesDir: string): string {
  return `${filesDir}/${SAVE_STATE_DIR_NAME}`
}

function buildManifestPath(filesDir: string): string {
  return `${buildSaveDirPath(filesDir)}/${SAVE_STATE_MANIFEST_FILE}`
}

function buildSaveFilePath(filesDir: string, fileName: string): string {
  return `${buildSaveDirPath(filesDir)}/${fileName}`
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (err) {
    return
  }
}
