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
  writeArrayBufferToFile(targetPath, data)
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
  const stat = fs.statSync(targetPath)
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
  } finally {
    if (file) {
      fs.closeSync(file.fd)
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
    const message = (err as Error).message || String(err)
    LogHelper.warn('SaveStateRepository', 'Delete', `删除存档文件失败: ${message}`)
  }
  const document = await loadManifest(context)
  const nextItems = document.items.filter((item: SaveStateManifestItem) => item.fileName !== safeName)
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
    entries.forEach((fileName: string) => {
      if (!fileName.endsWith('.state')) {
        return
      }
      const path = buildSaveFilePath(context.filesDir, fileName)
      const stat = fs.statSync(path)
      items.push({
        id: fileName,
        fileName: fileName,
        romFile: '',
        createdAt: readTimestampFromFileName(fileName),
        byteLength: Number(stat.size)
      })
    })
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
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(buildManifestPath(context.filesDir), fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(document, null, 2))
  } finally {
    if (file) {
      await fs.close(file.fd)
    }
  }
}

function writeArrayBufferToFile(path: string, data: ArrayBuffer): void {
  let file: fs.File | undefined = undefined
  try {
    file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const writeOptions: WriteOptions = {
      length: data.byteLength
    }
    fs.writeSync(file.fd, data, writeOptions)
  } finally {
    if (file) {
      fs.closeSync(file.fd)
    }
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
