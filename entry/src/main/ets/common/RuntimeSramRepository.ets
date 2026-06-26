import { common } from '@kit.AbilityKit'
import { fileIo as fs, ReadOptions, WriteOptions } from '@kit.CoreFileKit'

export interface RuntimeSramBackupItem {
  id: string
  fileName: string
  romFile: string
  createdAt: number
  byteLength: number
}

export interface RuntimeSramWriteOptions {
  shouldCancel?: () => boolean
}

interface RuntimeSramErrorWithCode {
  code?: string | number
}

class RuntimeSramCanceledError extends Error {
  constructor() {
    super('RUNTIME_SRAM_CANCELED')
  }
}

const RUNTIME_SRAM_DIR_NAME = 'runtime/sram'
const RUNTIME_SRAM_FILE_PREFIX = 'sram_'
const RUNTIME_SRAM_FILE_SUFFIX = '.srm'
const ERR_CODE_ENOENT = '13900002'
const ERR_CODE_ENOENT_NUM: string | number = 13900002
const MAX_SRAM_FILE_NAME_LENGTH = 120
const MAX_SRAM_ROM_STEM_LENGTH = 48

export async function listRuntimeSramBackupsForRom(
  context: common.UIAbilityContext,
  romFile: string
): Promise<RuntimeSramBackupItem[]> {
  const normalizedRomFile = normalizeRomFile(romFile)
  if (normalizedRomFile.length === 0) {
    return []
  }

  const romDirPath = buildRuntimeSramRomDirPath(context.filesDir, normalizedRomFile)
  const items: RuntimeSramBackupItem[] = []
  try {
    const entries = await fs.listFile(romDirPath)
    for (let index = 0; index < entries.length; index += 1) {
      const fileName = entries[index]
      if (!fileName.endsWith(RUNTIME_SRAM_FILE_SUFFIX)) {
        continue
      }
      const stat = await fs.stat(buildRuntimeSramBackupPath(context.filesDir, normalizedRomFile, fileName))
      items.push({
        id: fileName,
        fileName,
        romFile: normalizedRomFile,
        createdAt: readTimestampFromFileName(fileName),
        byteLength: Number(stat.size) || 0
      })
    }
  } catch (_err) {
    return []
  }

  items.sort((left: RuntimeSramBackupItem, right: RuntimeSramBackupItem) => right.createdAt - left.createdAt)
  return items
}

export async function saveRuntimeSramBackup(
  context: common.UIAbilityContext,
  romFile: string,
  data: ArrayBuffer,
  options?: RuntimeSramWriteOptions
): Promise<RuntimeSramBackupItem> {
  const normalizedRomFile = normalizeRomFile(romFile)
  if (normalizedRomFile.length === 0) {
    throw new Error('rom context missing')
  }
  if (data.byteLength <= 0) {
    throw new Error('sram data missing')
  }

  const romDirPath = buildRuntimeSramRomDirPath(context.filesDir, normalizedRomFile)
  await ensureDirExists(romDirPath)
  throwIfRuntimeSramCanceled(options)

  const createdAt = Date.now()
  const fileName = `${RUNTIME_SRAM_FILE_PREFIX}${createdAt}${RUNTIME_SRAM_FILE_SUFFIX}`
  await writeArrayBufferToFile(
    buildRuntimeSramBackupPath(context.filesDir, normalizedRomFile, fileName),
    data,
    options?.shouldCancel
  )
  return {
    id: fileName,
    fileName,
    romFile: normalizedRomFile,
    createdAt,
    byteLength: data.byteLength
  }
}

export async function readRuntimeSramBackup(
  context: common.UIAbilityContext,
  romFile: string,
  fileName: string
): Promise<ArrayBuffer> {
  const normalizedRomFile = normalizeRomFile(romFile)
  const safeFileName = sanitizeFileName(fileName)
  if (normalizedRomFile.length === 0 || safeFileName.length === 0) {
    throw new Error('sram backup context missing')
  }
  return await readArrayBufferFromFile(
    buildRuntimeSramBackupPath(context.filesDir, normalizedRomFile, safeFileName)
  )
}

export async function deleteRuntimeSramBackup(
  context: common.UIAbilityContext,
  romFile: string,
  fileName: string
): Promise<void> {
  const normalizedRomFile = normalizeRomFile(romFile)
  const safeFileName = sanitizeFileName(fileName)
  if (normalizedRomFile.length === 0 || safeFileName.length === 0) {
    throw new Error('sram backup context missing')
  }

  try {
    await fs.unlink(buildRuntimeSramBackupPath(context.filesDir, normalizedRomFile, safeFileName))
  } catch (err) {
    const errorCode = (err as RuntimeSramErrorWithCode).code
    if (errorCode === ERR_CODE_ENOENT || errorCode === ERR_CODE_ENOENT_NUM) {
      return
    }
    throw err as Error
  }
}

function normalizeRomFile(romFile: string | undefined): string {
  return typeof romFile === 'string' ? romFile.trim() : ''
}

function buildRuntimeSramRomDirPath(filesDir: string, romFile: string): string {
  return `${filesDir}/${RUNTIME_SRAM_DIR_NAME}/${buildRuntimeSramRomDirName(romFile)}`
}

function buildRuntimeSramBackupPath(filesDir: string, romFile: string, fileName: string): string {
  return `${buildRuntimeSramRomDirPath(filesDir, romFile)}/${sanitizeFileName(fileName)}`
}

function buildRuntimeSramRomDirName(romFile: string): string {
  const baseName = extractRomBaseName(romFile)
  const hash = computeStableHash(normalizeRomFile(romFile))
  return `${baseName}_${hash}`
}

function extractRomBaseName(romFile: string): string {
  const normalizedPath = romFile.replace(/\\/g, '/')
  const slashIndex = normalizedPath.lastIndexOf('/')
  const fileName = slashIndex >= 0 ? normalizedPath.substring(slashIndex + 1) : normalizedPath
  const dotIndex = fileName.lastIndexOf('.')
  const stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
  const sanitized = sanitizeFileName(stem)
  if (sanitized.length === 0) {
    return 'rom'
  }
  return sanitized.length > MAX_SRAM_ROM_STEM_LENGTH
    ? sanitized.substring(0, MAX_SRAM_ROM_STEM_LENGTH)
    : sanitized
}

function computeStableHash(value: string): string {
  let hash = 2166136261
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  const normalized = hash >>> 0
  return normalized.toString(16).padStart(8, '0')
}

function sanitizeFileName(fileName: string | undefined): string {
  const decoded = typeof fileName === 'string' ? fileName.trim() : ''
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
  return truncateSramFileName(normalized)
}

function readTimestampFromFileName(fileName: string): number {
  const matched = /^sram_(\d+)\.srm$/i.exec(fileName)
  if (!matched || matched.length < 2) {
    return 0
  }
  const timestamp = Math.floor(Number(matched[1]) || 0)
  return timestamp > 0 ? timestamp : 0
}

function truncateSramFileName(fileName: string): string {
  if (fileName.length <= MAX_SRAM_FILE_NAME_LENGTH) {
    return fileName
  }
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex > 0 && dotIndex < fileName.length - 1) {
    const extension = fileName.substring(dotIndex)
    if (extension.length < MAX_SRAM_FILE_NAME_LENGTH - 1) {
      return `${fileName.substring(0, MAX_SRAM_FILE_NAME_LENGTH - extension.length)}${extension}`
    }
  }
  return fileName.substring(0, MAX_SRAM_FILE_NAME_LENGTH)
}

async function readArrayBufferFromFile(path: string): Promise<ArrayBuffer> {
  let file: fs.File | undefined = undefined
  try {
    const stat = await fs.stat(path)
    const byteLength = Number(stat.size) || 0
    const data = new ArrayBuffer(byteLength)
    file = await fs.open(path, fs.OpenMode.READ_ONLY)
    const readOptions: ReadOptions = {
      offset: 0,
      length: byteLength
    }
    const readLength = await fs.read(file.fd, data, readOptions)
    if (readLength >= byteLength) {
      return data
    }
    return data.slice(0, Math.max(0, readLength))
  } catch (err) {
    throw err as Error
  } finally {
    if (file) {
      try {
        await fs.close(file.fd)
      } catch (_closeErr) {
      }
    }
  }
}

async function writeArrayBufferToFile(path: string, data: ArrayBuffer, shouldCancel?: () => boolean): Promise<void> {
  const tmpPath = `${path}.tmp`
  let file: fs.File | undefined = undefined
  try {
    if (shouldCancel?.()) {
      throw new RuntimeSramCanceledError()
    }
    file = await fs.open(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const writeOptions: WriteOptions = {
      length: data.byteLength
    }
    await fs.write(file.fd, data, writeOptions)
    await fs.close(file.fd)
    file = undefined
    if (shouldCancel?.()) {
      throw new RuntimeSramCanceledError()
    }
    await fs.rename(tmpPath, path)
  } catch (err) {
    if (file) {
      try {
        await fs.close(file.fd)
      } catch (_closeErr) {
      }
    }
    try {
      await fs.unlink(tmpPath)
    } catch (_unlinkErr) {
    }
    throw err as Error
  }
}

function throwIfRuntimeSramCanceled(options?: RuntimeSramWriteOptions): void {
  if (options?.shouldCancel?.()) {
    throw new RuntimeSramCanceledError()
  }
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (_err) {
    return
  }
}
