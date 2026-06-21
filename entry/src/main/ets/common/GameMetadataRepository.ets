import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface GameMetadataRecord {
  romFile: string
  title: string
  publisher: string
  overview: string
  releaseYear: number
  platform: string
  coverKey: string
}

interface GameMetadataDocument {
  version: number
  records: GameMetadataRecord[]
}

const METADATA_VERSION = 1
const METADATA_DIR_NAME = 'metadata'
const METADATA_FILE_NAME = 'game_metadata.json'

export async function loadGameMetadataIndex(context: common.UIAbilityContext): Promise<GameMetadataRecord[]> {
  const document = await loadMetadataDocument(context)
  return document.records
}

export async function getGameMetadataByRomFile(
  context: common.UIAbilityContext,
  romFile: string
): Promise<GameMetadataRecord | undefined> {
  const records = await loadGameMetadataIndex(context)
  return records.find((record: GameMetadataRecord) => normalizeKey(record.romFile) === normalizeKey(romFile))
}

export async function upsertGameMetadata(
  context: common.UIAbilityContext,
  record: GameMetadataRecord
): Promise<void> {
  const document = await loadMetadataDocument(context)
  const nextRecords: GameMetadataRecord[] = []
  let updated = false
  document.records.forEach((item: GameMetadataRecord) => {
    if (normalizeKey(item.romFile) === normalizeKey(record.romFile)) {
      nextRecords.push(normalizeMetadataRecord(record))
      updated = true
    } else {
      nextRecords.push(normalizeMetadataRecord(item))
    }
  })
  if (!updated) {
    nextRecords.push(normalizeMetadataRecord(record))
  }
  await saveMetadataDocument(context, {
    version: METADATA_VERSION,
    records: nextRecords
  })
}

async function loadMetadataDocument(context: common.UIAbilityContext): Promise<GameMetadataDocument> {
  const path = buildMetadataPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createEmptyMetadataDocument()
  }
  try {
    const parsed = JSON.parse(text) as Partial<GameMetadataDocument> | null
    const records: GameMetadataRecord[] = []
    if (parsed?.records) {
      parsed.records.forEach((record: GameMetadataRecord) => {
        records.push(normalizeMetadataRecord(record))
      })
    }
    return {
      version: METADATA_VERSION,
      records: records
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('GameMetadataRepository', 'Load', `metadata 索引损坏，已回退为空: ${message}`)
    return createEmptyMetadataDocument()
  }
}

async function saveMetadataDocument(
  context: common.UIAbilityContext,
  document: GameMetadataDocument
): Promise<void> {
  const dirPath = buildMetadataDirPath(context.filesDir)
  await ensureDirExists(dirPath)
  const path = buildMetadataPath(context.filesDir)
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(document, null, 2))
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('GameMetadataRepository', 'Save', `保存本地 metadata 失败: ${message}`)
  } finally {
    if (file) {
      try {
        await fs.close(file.fd)
      } catch (_closeErr) {
      }
    }
  }
}

function createEmptyMetadataDocument(): GameMetadataDocument {
  return {
    version: METADATA_VERSION,
    records: []
  }
}

function normalizeMetadataRecord(record: Partial<GameMetadataRecord>): GameMetadataRecord {
  return {
    romFile: normalizeText(record.romFile),
    title: normalizeText(record.title),
    publisher: normalizeText(record.publisher),
    overview: normalizeText(record.overview),
    releaseYear: normalizeNumber(record.releaseYear),
    platform: normalizeText(record.platform),
    coverKey: normalizeText(record.coverKey)
  }
}

function normalizeText(value: string | undefined): string {
  if (!value || value.length === 0) {
    return ''
  }
  return value.trim()
}

function normalizeNumber(value: number | undefined): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0
  }
  return Math.floor(value)
}

function normalizeKey(value: string | undefined): string {
  return normalizeText(value).toLowerCase()
}

function buildMetadataDirPath(filesDir: string): string {
  return `${filesDir}/${METADATA_DIR_NAME}`
}

function buildMetadataPath(filesDir: string): string {
  return `${buildMetadataDirPath(filesDir)}/${METADATA_FILE_NAME}`
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
