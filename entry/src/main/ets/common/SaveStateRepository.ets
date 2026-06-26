import { common } from '@kit.AbilityKit'
import { fileIo as fs, fileUri, ReadOptions, WriteOptions } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import LogHelper from './LogHelper'

export interface SaveStateManifestItem {
  id: string
  fileName: string
  romFile: string
  createdAt: number
  byteLength: number
  thumbnailFileName?: string
  thumbnailWidth?: number
  thumbnailHeight?: number
}

export interface SaveStateManifestItemThumbnail {
  rgba: ArrayBuffer
  width: number
  height: number
}

interface SaveStateManifestDocument {
  version: number
  items: SaveStateManifestItem[]
}

export interface SaveStateWriteOptions {
  thumbnail?: SaveStateManifestItemThumbnail
  shouldCancel?: () => boolean
}

interface PersistedSaveStateThumbnail {
  fileName: string
  width: number
  height: number
}

class SaveStateCanceledError extends Error {
  constructor() {
    super('SAVE_STATE_CANCELED')
  }
}

const SAVE_STATE_VERSION = 2
const SAVE_STATE_DIR_NAME = 'saves'
const SAVE_STATE_MANIFEST_FILE = 'manifest.json'
const SAVE_STATE_THUMBNAIL_SUFFIX = '.thumb.jpg'
const SAVE_STATE_THUMBNAIL_FORMAT = 'image/jpeg'
const SAVE_STATE_THUMBNAIL_QUALITY = 90
const MAX_SAVE_FILE_NAME_LENGTH = 120

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
  romFile: string,
  options?: SaveStateWriteOptions
): Promise<SaveStateManifestItem> {
  throwIfSaveStateCanceled(options)
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  const createdAt = Date.now()
  const fileName = `state_${createdAt}.state`
  const targetPath = buildSaveFilePath(context.filesDir, fileName)
  let thumbnail: PersistedSaveStateThumbnail | undefined = undefined
  try {
    // T6-F4: .state written before manifest; crash here leaves an orphan .state (no romFile association).
    // Mitigated by T6-F3 (both writes are atomic), but a process kill between the two steps is still possible.
    // T8-C-F1: writeArrayBufferToFile 改 async, 避免 PS1/GBA 等大存档 (128KB-1MB) 阻塞主线程。
    await writeArrayBufferToFile(targetPath, data, options?.shouldCancel)
    throwIfSaveStateCanceled(options)
    thumbnail = await tryPersistSaveStateThumbnail(context.filesDir, fileName, options?.thumbnail, options?.shouldCancel)
    throwIfSaveStateCanceled(options)
    const item: SaveStateManifestItem = {
      id: fileName,
      fileName: fileName,
      romFile: romFile,
      createdAt: createdAt,
      byteLength: data.byteLength
    }
    if (thumbnail) {
      item.thumbnailFileName = thumbnail.fileName
      item.thumbnailWidth = thumbnail.width
      item.thumbnailHeight = thumbnail.height
    }
    const document = await loadManifest(context)
    throwIfSaveStateCanceled(options)
    const nextItems: SaveStateManifestItem[] = [item]
    document.items.forEach((existing: SaveStateManifestItem) => {
      if (existing.fileName !== fileName) {
        nextItems.push(normalizeManifestItem(existing))
      }
    })
    await saveManifest(context, {
      version: SAVE_STATE_VERSION,
      items: nextItems
    }, options?.shouldCancel)
    return item
  } catch (err) {
    if (err instanceof SaveStateCanceledError) {
      await deletePathBestEffort(targetPath)
      if (thumbnail) {
        await deletePathBestEffort(buildSaveFilePath(context.filesDir, thumbnail.fileName))
      }
    }
    throw err as Error
  }
}

export function readSaveStateData(
  context: common.UIAbilityContext,
  fileName: string
): ArrayBuffer {
  const safeName = sanitizeFileName(fileName)
  if (safeName.length === 0) {
    throw new Error('invalid_save_state_file_name')
  }
  const targetPath = buildSaveFilePath(context.filesDir, safeName)
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
  if (safeName.length === 0) {
    throw new Error('invalid_save_state_file_name')
  }
  const document = await loadManifest(context)
  const targetItem = document.items.find((item: SaveStateManifestItem) => item.fileName === safeName)
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
  await deleteThumbnailFileBestEffort(context.filesDir, targetItem?.thumbnailFileName)
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
  for (let index = 0; index < document.items.length; index += 1) {
    const item = document.items[index]
    if (removedSet.has(item.fileName)) {
      await deleteThumbnailFileBestEffort(context.filesDir, item.thumbnailFileName)
    }
  }
  const nextItems = document.items.filter((item: SaveStateManifestItem) => !removedSet.has(item.fileName))
  await saveManifest(context, {
    version: SAVE_STATE_VERSION,
    items: nextItems
  })
}

async function loadManifest(context: common.UIAbilityContext): Promise<SaveStateManifestDocument> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  const manifestPath = buildManifestPath(context.filesDir)
  const text = await readOptionalText(manifestPath)
  if (!text || text.length === 0) {
    return await buildManifestFromDirectory(context)
  }
  try {
    const parsed = JSON.parse(text) as Partial<SaveStateManifestDocument> | null
    const items: SaveStateManifestItem[] = []
    if (parsed?.items) {
      parsed.items.forEach((item: SaveStateManifestItem) => {
        items.push(normalizeManifestItem(item))
      })
    }
    // D002: manifest 与磁盘 reconciliation。覆盖 saveStateData 写 .state 与写 manifest
    // 两步之间崩溃留下的孤儿文件，以及 manifest 残留指向已删文件的条目。
    const reconciled = await reconcileManifestItems(context, items)
    return {
      version: SAVE_STATE_VERSION,
      items: reconciled
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Load', `存档索引损坏，已按目录重建: ${message}`)
    return await buildManifestFromDirectory(context)
  }
}

// D002: 对账 manifest 条目与 saves/ 目录实际文件，消除两类孤儿：
//   (a) manifest 有条目但 .state 文件不存在 → 裁剪（如 deleteSaveStateItem unlink 后崩溃）
//   (b) .state 文件存在但 manifest 无条目 → 补充（romFile='' 待后续编辑补全；
//       如 saveStateData 写完 .state 但写 manifest 前崩溃，避免用户存档丢失）
// 写操作本身是 tmp+rename 原子写，半写文件以 .tmp 结尾不被本对账拾取。
async function reconcileManifestItems(
  context: common.UIAbilityContext,
  manifestItems: SaveStateManifestItem[]
): Promise<SaveStateManifestItem[]> {
  const validItems: SaveStateManifestItem[] = []
  const knownFileNames = new Set<string>()
  // (a) 逐条 stat：文件不存在则裁剪
  for (let index = 0; index < manifestItems.length; index += 1) {
    let item = manifestItems[index]
    knownFileNames.add(item.fileName)
    const path = buildSaveFilePath(context.filesDir, item.fileName)
    try {
      await fs.stat(path)
      item = await reconcileThumbnailMetadata(context.filesDir, item)
      validItems.push(item)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn(
        'SaveStateRepository',
        'Reconcile',
        `裁剪不存在的存档条目 ${LogHelper.describePathForLog(item.fileName)}: ${message}`
      )
    }
  }
  // (b) 扫描目录：磁盘上有但 manifest 无的 .state 文件补充为孤儿条目
  try {
    const saveDir = buildSaveDirPath(context.filesDir)
    const entries = await fs.listFile(saveDir)
    for (let index = 0; index < entries.length; index += 1) {
      const fileName = entries[index]
      if (!fileName.endsWith('.state') || knownFileNames.has(fileName)) {
        continue
      }
      const path = buildSaveFilePath(context.filesDir, fileName)
      const stat = await fs.stat(path)
      validItems.push({
        id: fileName,
        fileName: fileName,
        romFile: '',
        createdAt: readTimestampFromFileName(fileName),
        byteLength: Number(stat.size)
      })
      LogHelper.warn(
        'SaveStateRepository',
        'Reconcile',
        `补充孤儿存档文件到清单: ${LogHelper.describePathForLog(fileName)}`
      )
    }
  } catch (err) {
    // 目录扫描失败不阻塞主流程，仅丢失孤儿补充能力
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Reconcile', `扫描孤儿存档失败: ${message}`)
  }
  return validItems
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
  document: SaveStateManifestDocument,
  shouldCancel?: () => boolean
): Promise<void> {
  await ensureDirExists(buildSaveDirPath(context.filesDir))
  // Audit T6-F3: tmp+rename atomic write — crash during write leaves .tmp, not a corrupt manifest
  const manifestPath = buildManifestPath(context.filesDir)
  const tmpPath = manifestPath + '.tmp'
  let file: fs.File | undefined = undefined
  try {
    if (shouldCancel?.()) {
      throw new SaveStateCanceledError()
    }
    file = await fs.open(tmpPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(document, null, 2))
    await fs.close(file.fd)
    file = undefined
    if (shouldCancel?.()) {
      throw new SaveStateCanceledError()
    }
    await fs.rename(tmpPath, manifestPath)
  } catch (err) {
    if (file) {
      try { await fs.close(file.fd) } catch (_) {}
    }
    try { fs.unlinkSync(tmpPath) } catch (_) {}
    throw err as Error
  }
}

async function writeArrayBufferToFile(path: string, data: ArrayBuffer, shouldCancel?: () => boolean): Promise<void> {
  // Audit T6-F3: tmp+rename atomic write — crash during write leaves .tmp, not a corrupt .state
  // T8-C-F1: async fs.* avoids blocking main thread on 128KB-1MB save serialization.
  const tmpPath = path + '.tmp'
  let file: fs.File | undefined = undefined
  try {
    if (shouldCancel?.()) {
      throw new SaveStateCanceledError()
    }
    file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const writeOptions: WriteOptions = {
      length: data.byteLength
    }
    await fs.write(file.fd, data, writeOptions)
    await fs.close(file.fd)
    file = undefined
    if (shouldCancel?.()) {
      throw new SaveStateCanceledError()
    }
    await fs.rename(tmpPath, path)
  } catch (err) {
    if (file) {
      try { await fs.close(file.fd) } catch (_) {}
    }
    try { await fs.unlink(tmpPath) } catch (_) {}
    throw err as Error
  }
}

export function buildSaveStateThumbnailUri(filesDir: string, thumbnailFileName?: string): string {
  const safeName = sanitizeOptionalFileName(thumbnailFileName)
  if (safeName.length === 0) {
    return ''
  }
  return fileUri.getUriFromPath(buildSaveFilePath(filesDir, safeName))
}

async function tryPersistSaveStateThumbnail(
  filesDir: string,
  stateFileName: string,
  thumbnail?: SaveStateManifestItemThumbnail,
  shouldCancel?: () => boolean
): Promise<PersistedSaveStateThumbnail | undefined> {
  if (!thumbnail || thumbnail.width <= 0 || thumbnail.height <= 0 || thumbnail.rgba.byteLength === 0) {
    return undefined
  }
  try {
    return await persistSaveStateThumbnail(filesDir, stateFileName, thumbnail, shouldCancel)
  } catch (err) {
    if (err instanceof SaveStateCanceledError) {
      throw err
    }
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Thumbnail', `写入存档缩略图失败: ${message}`)
    return undefined
  }
}

async function persistSaveStateThumbnail(
  filesDir: string,
  stateFileName: string,
  thumbnail: SaveStateManifestItemThumbnail,
  shouldCancel?: () => boolean
): Promise<PersistedSaveStateThumbnail> {
  const encoded = await encodeSaveStateThumbnail(thumbnail)
  if (shouldCancel?.()) {
    throw new SaveStateCanceledError()
  }
  const thumbnailFileName = buildThumbnailFileName(stateFileName)
  await writeArrayBufferToFile(buildSaveFilePath(filesDir, thumbnailFileName), encoded, shouldCancel)
  return {
    fileName: thumbnailFileName,
    width: thumbnail.width,
    height: thumbnail.height
  }
}

async function encodeSaveStateThumbnail(
  thumbnail: SaveStateManifestItemThumbnail
): Promise<ArrayBuffer> {
  const expectedByteLength = thumbnail.width * thumbnail.height * 4
  if (thumbnail.rgba.byteLength < expectedByteLength) {
    throw new Error(`thumbnail_rgba_too_small:${thumbnail.rgba.byteLength}/${expectedByteLength}`)
  }
  const rgbaData = thumbnail.rgba.byteLength === expectedByteLength
    ? thumbnail.rgba
    : thumbnail.rgba.slice(0, expectedByteLength)
  const options: image.InitializationOptions = {
    size: {
      width: thumbnail.width,
      height: thumbnail.height
    },
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.OPAQUE,
    editable: false
  }
  const pixelMap = image.createPixelMapSync(rgbaData, options)
  const imagePacker = image.createImagePacker()
  const packingOption: image.PackingOption = {
    format: SAVE_STATE_THUMBNAIL_FORMAT,
    quality: SAVE_STATE_THUMBNAIL_QUALITY
  }
  try {
    return await imagePacker.packToData(pixelMap, packingOption)
  } catch (err) {
    throw err as Error
  } finally {
    await pixelMap.release()
    await imagePacker.release()
  }
}

async function reconcileThumbnailMetadata(
  filesDir: string,
  item: SaveStateManifestItem
): Promise<SaveStateManifestItem> {
  const thumbnailFileName = sanitizeOptionalFileName(item.thumbnailFileName)
  if (thumbnailFileName.length === 0) {
    return clearThumbnailMetadata(item)
  }
  try {
    await fs.stat(buildSaveFilePath(filesDir, thumbnailFileName))
    return item
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Reconcile', `裁剪不存在的缩略图 ${thumbnailFileName}: ${message}`)
    return clearThumbnailMetadata(item)
  }
}

async function deleteThumbnailFileBestEffort(filesDir: string, thumbnailFileName?: string): Promise<void> {
  const safeName = sanitizeOptionalFileName(thumbnailFileName)
  if (safeName.length === 0) {
    return
  }
  try {
    await fs.unlink(buildSaveFilePath(filesDir, safeName))
  } catch (err) {
    const errno = (err as ErrorWithCode).code
    const message = (err as Error).message || String(err)
    if (errno === ERR_CODE_ENOENT || errno === ERR_CODE_ENOENT_NUM) {
      return
    }
    LogHelper.warn('SaveStateRepository', 'Thumbnail', `删除缩略图失败 (保留孤儿图): ${message}`)
  }
}

async function deletePathBestEffort(path: string): Promise<void> {
  try {
    await fs.unlink(path)
  } catch (_err) {
  }
}

function throwIfSaveStateCanceled(options?: SaveStateWriteOptions): void {
  if (options?.shouldCancel?.()) {
    throw new SaveStateCanceledError()
  }
}

function normalizeManifestItem(item: SaveStateManifestItem): SaveStateManifestItem {
  const normalizedId = typeof item.id === 'string' && item.id.length > 0 ? item.id : item.fileName
  const normalized: SaveStateManifestItem = {
    id: sanitizeFileName(normalizedId),
    fileName: sanitizeFileName(item.fileName),
    romFile: item.romFile ?? '',
    createdAt: normalizeNumber(item.createdAt),
    byteLength: normalizeNumber(item.byteLength)
  }
  const thumbnailFileName = sanitizeOptionalFileName(item.thumbnailFileName)
  const thumbnailWidth = normalizeNumber(item.thumbnailWidth ?? 0)
  const thumbnailHeight = normalizeNumber(item.thumbnailHeight ?? 0)
  if (thumbnailFileName.length > 0 && thumbnailWidth > 0 && thumbnailHeight > 0) {
    normalized.thumbnailFileName = thumbnailFileName
    normalized.thumbnailWidth = thumbnailWidth
    normalized.thumbnailHeight = thumbnailHeight
  }
  return normalized
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
  const decoded = fileName.trim()
  let normalized = ''
  for (let index = 0; index < decoded.length; index += 1) {
    const char = decoded.charAt(index)
    const code = decoded.charCodeAt(index)
    if (code < 32 || code === 127 || char === '/' || char === '\\') {
      continue
    }
    normalized += ':*?"<>|'.includes(char) ? '_' : char
  }
  normalized = normalized.replace(/\.\.+/g, '.').replace(/^\.+/, '').trim()
  return truncateSaveFileName(normalized)
}

function sanitizeOptionalFileName(fileName?: string): string {
  if (typeof fileName !== 'string') {
    return ''
  }
  return sanitizeFileName(fileName)
}

function clearThumbnailMetadata(item: SaveStateManifestItem): SaveStateManifestItem {
  const nextItem: SaveStateManifestItem = {
    id: item.id,
    fileName: item.fileName,
    romFile: item.romFile,
    createdAt: item.createdAt,
    byteLength: item.byteLength
  }
  return nextItem
}

function truncateSaveFileName(fileName: string): string {
  if (fileName.length <= MAX_SAVE_FILE_NAME_LENGTH) {
    return fileName
  }
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex > 0 && dotIndex < fileName.length - 1) {
    const extension = fileName.substring(dotIndex)
    if (extension.length < MAX_SAVE_FILE_NAME_LENGTH - 1) {
      return `${fileName.substring(0, MAX_SAVE_FILE_NAME_LENGTH - extension.length)}${extension}`
    }
  }
  return fileName.substring(0, MAX_SAVE_FILE_NAME_LENGTH)
}

function buildThumbnailFileName(stateFileName: string): string {
  const safeName = sanitizeFileName(stateFileName)
  const suffixIndex = safeName.lastIndexOf('.state')
  if (suffixIndex > 0) {
    return `${safeName.substring(0, suffixIndex)}${SAVE_STATE_THUMBNAIL_SUFFIX}`
  }
  return `${safeName}${SAVE_STATE_THUMBNAIL_SUFFIX}`
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

async function fileExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (_err) {
    return false
  }
}

async function readOptionalText(path: string): Promise<string> {
  if (!(await fileExists(path))) {
    return ''
  }
  try {
    return await fs.readText(path)
  } catch (_err) {
    return ''
  }
}
