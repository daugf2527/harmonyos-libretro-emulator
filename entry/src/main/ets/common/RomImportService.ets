import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs, picker, ReadOptions, WriteOptions } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface RomImportResult {
  selectedCount: number
  importedCount: number
  overwrittenCount: number
  skippedCount: number
  failedCount: number
  canceled: boolean
  importedNames: string[]
  overwrittenNames: string[]
  skippedNames: string[]
  failedNames: string[]
  items: RomImportItemResult[]
}

export type RomImportItemStatus = 'IMPORTED' | 'OVERWRITTEN' | 'SKIPPED' | 'FAILED' | 'CANCELED'

export interface RomImportItemResult {
  fileName: string
  status: RomImportItemStatus
  detail: string
}

export interface RomImportProgress {
  totalCount: number
  completedCount: number
  currentFileIndex: number
  currentFileName: string
  stage: string
  totalBytes: number
  completedBytes: number
  currentFileTotalBytes: number
  currentFileCompletedBytes: number
  hasAccurateByteProgress: boolean
}

export interface RomImportOptions {
  overwriteExisting?: boolean
  shouldCancel?: () => boolean
}

export interface RomImportConflictSummary {
  conflictCount: number
  conflictNames: string[]
}

const DEFAULT_IMPORT_RESULT: RomImportResult = {
  selectedCount: 0,
  importedCount: 0,
  overwrittenCount: 0,
  skippedCount: 0,
  failedCount: 0,
  canceled: false,
  importedNames: [],
  overwrittenNames: [],
  skippedNames: [],
  failedNames: [],
  items: []
}

interface ImportFilePlan {
  uri: string
  fileName: string
  fileBytes: number
  progressBytes: number
}

interface FileStatCompat {
  size?: number
}

interface FileIoCompat {
  statSync(path: string): FileStatCompat
  stat(path: string): Promise<FileStatCompat>
}

interface PickerSelectOptionsCompat {
  maxSelectNumber: number
}

class ImportCanceledError extends Error {
  copiedBytes: number

  constructor(copiedBytes: number) {
    super('IMPORT_CANCELED')
    this.copiedBytes = copiedBytes
  }
}

const GAMBATTE_EXTENSIONS: string[] = ['gb', 'gbc', 'dmg']
const MGBA_EXTENSIONS: string[] = ['gba', 'agb']
const NESTOPIA_EXTENSIONS: string[] = ['nes', 'fds', 'unf', 'unif']
const SNES9X_EXTENSIONS: string[] = ['smc', 'sfc', 'swc', 'fig', 'bs', 'st']
const SNES9X2010_EXTENSIONS: string[] = ['gd3', 'gd7', 'dx2', 'bsx']
const GENESIS_PLUS_GX_EXTENSIONS: string[] = [
  'mdx', 'md', 'smd', 'gen', 'sms', 'bms', 'gg', 'sg', '68k', 'sgd'
]
const MELONDS_EXTENSIONS: string[] = ['nds', 'ids', 'dsi']
const PCSX_REARMED_EXTENSIONS: string[] = ['cue', 'toc', 'ccd', 'pbp', 'chd', 'iso', 'm3u', 'cbn']
const FBNEO_EXTENSIONS: string[] = ['zip', '7z']
const MEDNAFEN_NGP_EXTENSIONS: string[] = ['ngp', 'ngc', 'ngpc', 'npc']
const FREEINTV_EXTENSIONS: string[] = ['int']
const POTATOR_EXTENSIONS: string[] = ['sv']
const RETRO8_EXTENSIONS: string[] = ['p8', 'png']
const VICE_X64_EXTENSIONS: string[] = [
  'd64', 'd71', 'd80', 'd81', 'd82', 'g64', 'g41', 'x64', 't64', 'tap',
  'prg', 'p00', 'crt', 'd6z', 'd7z', 'd8z', 'g6z', 'g4z', 'x6z', 'cmd',
  'vfl', 'vsf', 'nib', 'nbz', 'd2m', 'd4m'
]
const MINIVMAC_EXTENSIONS: string[] = ['dsk', 'hvf']
const CROCODS_EXTENSIONS: string[] = ['kcr', 'sna']

export function getRomFileExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return ''
  }
  return fileName.substring(dotIndex + 1).toLowerCase()
}

export function getPreferredCoreIdForFile(fileName: string): string {
  const ext = getRomFileExtension(fileName)
  if (GAMBATTE_EXTENSIONS.includes(ext)) {
    return 'gambatte'
  }
  if (MGBA_EXTENSIONS.includes(ext)) {
    return 'mgba'
  }
  if (NESTOPIA_EXTENSIONS.includes(ext)) {
    return 'nestopia'
  }
  if (SNES9X_EXTENSIONS.includes(ext)) {
    return 'snes9x'
  }
  if (SNES9X2010_EXTENSIONS.includes(ext)) {
    return 'snes9x2010'
  }
  if (GENESIS_PLUS_GX_EXTENSIONS.includes(ext)) {
    return 'genesis_plus_gx'
  }
  if (MELONDS_EXTENSIONS.includes(ext)) {
    return 'melonds'
  }
  if (PCSX_REARMED_EXTENSIONS.includes(ext)) {
    return 'pcsx_rearmed'
  }
  if (FBNEO_EXTENSIONS.includes(ext)) {
    return 'fbneo'
  }
  if (MEDNAFEN_NGP_EXTENSIONS.includes(ext)) {
    return 'mednafen_ngp'
  }
  if (FREEINTV_EXTENSIONS.includes(ext)) {
    return 'freeintv'
  }
  if (POTATOR_EXTENSIONS.includes(ext)) {
    return 'potator'
  }
  if (RETRO8_EXTENSIONS.includes(ext)) {
    return 'retro8'
  }
  if (VICE_X64_EXTENSIONS.includes(ext)) {
    return 'vice_x64'
  }
  if (MINIVMAC_EXTENSIONS.includes(ext)) {
    return 'minivmac'
  }
  if (CROCODS_EXTENSIONS.includes(ext)) {
    return 'crocods'
  }
  return ''
}

export function listSupportedSandboxRomFiles(files: string[]): string[] {
  return files.filter((fileName: string) => getPreferredCoreIdForFile(fileName).length > 0)
}

export async function listSandboxRomFiles(filesDir: string): Promise<string[]> {
  const romDir = `${filesDir}/roms`
  try {
    const entries = await fs.listFile(romDir)
    if (!entries || entries.length === 0) {
      return []
    }
    const names = entries.filter((item: string) => item.length > 0 && item.indexOf('/') < 0)
    names.sort((left: string, right: string) => left.localeCompare(right))
    return listSupportedSandboxRomFiles(names)
  } catch (err) {
    return []
  }
}

export async function pickRomUris(context: common.UIAbilityContext): Promise<string[]> {
  const documentSelectOptions = new picker.DocumentSelectOptions() as PickerSelectOptionsCompat
  documentSelectOptions.maxSelectNumber = 30
  const documentPicker = new picker.DocumentViewPicker(context)
  try {
    const uris = await documentPicker.select(documentSelectOptions)
    return uris ?? []
  } catch (err) {
    const pickerError = err as BusinessError
    LogHelper.warn('RomImport', 'Picker', `选择文件取消或失败: ${pickerError.code}, ${pickerError.message}`)
    return []
  }
}

export async function importRomUris(
  context: common.UIAbilityContext,
  uris: string[],
  onProgress?: (progress: RomImportProgress) => void,
  options?: RomImportOptions
): Promise<RomImportResult> {
  const result = createEmptyImportResult()
  if (!uris || uris.length === 0) {
    result.canceled = true
    return result
  }
  result.selectedCount = uris.length
  const romDir = `${context.filesDir}/roms`
  await ensureDirExists(romDir)
  const importPlans = await buildImportFilePlans(uris)
  const totalBytes = importPlans.reduce((sum: number, item: ImportFilePlan) => sum + item.progressBytes, 0)
  const hasAccurateByteProgress = importPlans.every((item: ImportFilePlan) => item.fileBytes > 0)
  let completedBytes = 0

  for (let index = 0; index < uris.length; index += 1) {
    const currentPlan = importPlans[index]
    const fileName = currentPlan?.fileName ?? getFileNameFromUri(uris[index], index)
    const currentFileTotalBytes = currentPlan?.fileBytes ?? 0
    const currentProgressBytes = currentPlan?.progressBytes ?? 1
    if (options?.shouldCancel?.()) {
        result.canceled = true
        appendImportItemResult(result, fileName, 'CANCELED', '任务在复制开始前取消')
        onProgress?.({
          totalCount: uris.length,
          completedCount: index,
        currentFileIndex: index,
        currentFileName: '',
        stage: 'CANCELED',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: 0,
        currentFileCompletedBytes: 0,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
      break
    }

    const uri = currentPlan?.uri ?? uris[index]
    onProgress?.({
      totalCount: uris.length,
      completedCount: index,
      currentFileIndex: index + 1,
      currentFileName: fileName,
      stage: 'COPYING',
      totalBytes: totalBytes,
      completedBytes: completedBytes,
      currentFileTotalBytes: currentFileTotalBytes,
      currentFileCompletedBytes: 0,
      hasAccurateByteProgress: hasAccurateByteProgress
    })
    if (getPreferredCoreIdForFile(fileName).length === 0) {
      result.skippedCount += 1
      result.skippedNames.push(fileName)
      appendImportItemResult(result, fileName, 'SKIPPED', '不支持的文件格式')
      completedBytes += currentProgressBytes
      onProgress?.({
        totalCount: uris.length,
        completedCount: index + 1,
        currentFileIndex: index + 1,
        currentFileName: fileName,
        stage: 'SKIPPED',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: currentFileTotalBytes,
        currentFileCompletedBytes: currentFileTotalBytes,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
      continue
    }

    const destPath = `${romDir}/${fileName}`
    if (await pathExists(destPath)) {
      if (options?.overwriteExisting) {
        const tempOverwritePath = `${destPath}.importing`
        await deletePathIfExists(tempOverwritePath)
        onProgress?.({
          totalCount: uris.length,
          completedCount: index,
          currentFileIndex: index + 1,
          currentFileName: fileName,
          stage: 'OVERWRITING',
          totalBytes: totalBytes,
          completedBytes: completedBytes,
          currentFileTotalBytes: currentFileTotalBytes,
          currentFileCompletedBytes: 0,
          hasAccurateByteProgress: hasAccurateByteProgress
        })
        let copiedBytesForFile = 0
        try {
          copyFileFromUri(uri, tempOverwritePath, (nextCopiedBytes: number) => {
            copiedBytesForFile = nextCopiedBytes
            onProgress?.({
              totalCount: uris.length,
              completedCount: index,
              currentFileIndex: index + 1,
              currentFileName: fileName,
              stage: 'OVERWRITING',
              totalBytes: totalBytes,
              completedBytes: completedBytes + nextCopiedBytes,
              currentFileTotalBytes: currentFileTotalBytes,
              currentFileCompletedBytes: nextCopiedBytes,
              hasAccurateByteProgress: hasAccurateByteProgress
            })
          }, options?.shouldCancel)
          copyFileFromUri(tempOverwritePath, destPath)
          await deletePathIfExists(tempOverwritePath)
          result.overwrittenCount += 1
          result.overwrittenNames.push(fileName)
          appendImportItemResult(result, fileName, 'OVERWRITTEN', '已覆盖写入目标文件')
          completedBytes += currentProgressBytes
          onProgress?.({
            totalCount: uris.length,
            completedCount: index + 1,
            currentFileIndex: index + 1,
            currentFileName: fileName,
            stage: 'OVERWRITTEN',
            totalBytes: totalBytes,
            completedBytes: completedBytes,
            currentFileTotalBytes: currentFileTotalBytes,
            currentFileCompletedBytes: copiedBytesForFile,
            hasAccurateByteProgress: hasAccurateByteProgress
          })
        } catch (err) {
          if (err instanceof ImportCanceledError) {
            result.canceled = true
            await deletePathIfExists(tempOverwritePath)
            appendImportItemResult(result, fileName, 'CANCELED', '覆盖过程中取消，原文件已保留')
            onProgress?.({
              totalCount: uris.length,
              completedCount: index,
              currentFileIndex: index + 1,
              currentFileName: fileName,
              stage: 'CANCELED',
              totalBytes: totalBytes,
              completedBytes: completedBytes + err.copiedBytes,
              currentFileTotalBytes: currentFileTotalBytes,
              currentFileCompletedBytes: err.copiedBytes,
              hasAccurateByteProgress: hasAccurateByteProgress
            })
            break
          }
          await deletePathIfExists(tempOverwritePath)
          const overwriteMessage = (err as Error).message || String(err)
          LogHelper.error('RomImport', 'Copy', `覆盖文件失败 ${fileName}: ${overwriteMessage}`)
          result.failedCount += 1
          result.failedNames.push(fileName)
          appendImportItemResult(result, fileName, 'FAILED', overwriteMessage)
          completedBytes += currentProgressBytes
          onProgress?.({
            totalCount: uris.length,
            completedCount: index + 1,
            currentFileIndex: index + 1,
            currentFileName: fileName,
            stage: 'FAILED',
            totalBytes: totalBytes,
            completedBytes: completedBytes,
            currentFileTotalBytes: currentFileTotalBytes,
            currentFileCompletedBytes: copiedBytesForFile,
            hasAccurateByteProgress: hasAccurateByteProgress
          })
        }
        continue
      }
      result.skippedCount += 1
      result.skippedNames.push(fileName)
      appendImportItemResult(result, fileName, 'SKIPPED', '目标文件已存在')
      completedBytes += currentProgressBytes
      onProgress?.({
        totalCount: uris.length,
        completedCount: index + 1,
        currentFileIndex: index + 1,
        currentFileName: fileName,
        stage: 'EXISTS',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: currentFileTotalBytes,
        currentFileCompletedBytes: currentFileTotalBytes,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
      continue
    }

    let copiedBytesForFile = 0
    try {
      copyFileFromUri(uri, destPath, (nextCopiedBytes: number) => {
        copiedBytesForFile = nextCopiedBytes
        onProgress?.({
          totalCount: uris.length,
          completedCount: index,
          currentFileIndex: index + 1,
          currentFileName: fileName,
          stage: 'COPYING',
          totalBytes: totalBytes,
          completedBytes: completedBytes + nextCopiedBytes,
          currentFileTotalBytes: currentFileTotalBytes,
          currentFileCompletedBytes: nextCopiedBytes,
          hasAccurateByteProgress: hasAccurateByteProgress
        })
      }, options?.shouldCancel)
      result.importedCount += 1
      result.importedNames.push(fileName)
      appendImportItemResult(result, fileName, 'IMPORTED', '已成功写入游戏库目录')
      completedBytes += currentProgressBytes
      onProgress?.({
        totalCount: uris.length,
        completedCount: index + 1,
        currentFileIndex: index + 1,
        currentFileName: fileName,
        stage: 'DONE',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: currentFileTotalBytes,
        currentFileCompletedBytes: copiedBytesForFile,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
    } catch (err) {
      if (err instanceof ImportCanceledError) {
        result.canceled = true
        await deletePathIfExists(destPath)
        appendImportItemResult(result, fileName, 'CANCELED', '复制过程中取消，已清理未完成文件')
        onProgress?.({
          totalCount: uris.length,
          completedCount: index,
          currentFileIndex: index + 1,
          currentFileName: fileName,
          stage: 'CANCELED',
          totalBytes: totalBytes,
          completedBytes: completedBytes + err.copiedBytes,
          currentFileTotalBytes: currentFileTotalBytes,
          currentFileCompletedBytes: err.copiedBytes,
          hasAccurateByteProgress: hasAccurateByteProgress
        })
        break
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('RomImport', 'Copy', `复制文件失败 ${fileName}: ${message}`)
      result.failedCount += 1
      result.failedNames.push(fileName)
      appendImportItemResult(result, fileName, 'FAILED', message)
      completedBytes += currentProgressBytes
      onProgress?.({
        totalCount: uris.length,
        completedCount: index + 1,
        currentFileIndex: index + 1,
        currentFileName: fileName,
        stage: 'FAILED',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: currentFileTotalBytes,
        currentFileCompletedBytes: copiedBytesForFile,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
    }
  }

  return result
}

export async function inspectRomImportConflicts(
  context: common.UIAbilityContext,
  uris: string[]
): Promise<RomImportConflictSummary> {
  const romDir = `${context.filesDir}/roms`
  await ensureDirExists(romDir)
  const plans = await buildImportFilePlans(uris)
  const conflictNames: string[] = []
  for (let index = 0; index < plans.length; index += 1) {
    const plan = plans[index]
    if (getPreferredCoreIdForFile(plan.fileName).length === 0) {
      continue
    }
    const destPath = `${romDir}/${plan.fileName}`
    if (await pathExists(destPath)) {
      conflictNames.push(plan.fileName)
    }
  }
  return {
    conflictCount: conflictNames.length,
    conflictNames: conflictNames
  }
}

export function createEmptyImportResult(): RomImportResult {
  return {
    selectedCount: DEFAULT_IMPORT_RESULT.selectedCount,
    importedCount: DEFAULT_IMPORT_RESULT.importedCount,
    overwrittenCount: DEFAULT_IMPORT_RESULT.overwrittenCount,
    skippedCount: DEFAULT_IMPORT_RESULT.skippedCount,
    failedCount: DEFAULT_IMPORT_RESULT.failedCount,
    canceled: DEFAULT_IMPORT_RESULT.canceled,
    importedNames: [],
    overwrittenNames: [],
    skippedNames: [],
    failedNames: [],
    items: []
  }
}

function appendImportItemResult(
  result: RomImportResult,
  fileName: string,
  status: RomImportItemStatus,
  detail: string
): void {
  result.items.push({
    fileName: fileName,
    status: status,
    detail: detail
  })
}

function getFileNameFromUri(uri: string, index: number): string {
  const sanitizedUri = uri.split('?')[0]
  const lastSlash = sanitizedUri.lastIndexOf('/')
  const encodedName = lastSlash >= 0 ? sanitizedUri.substring(lastSlash + 1) : sanitizedUri
  if (encodedName.length === 0) {
    return `imported_${Date.now()}_${index}.rom`
  }
  try {
    return decodeURIComponent(encodedName)
  } catch (err) {
    return encodedName
  }
}

async function buildImportFilePlans(uris: string[]): Promise<ImportFilePlan[]> {
  const plans: ImportFilePlan[] = []
  for (let index = 0; index < uris.length; index += 1) {
    const uri = uris[index]
    const fileName = getFileNameFromUri(uri, index)
    const fileBytes = await resolveFileSize(uri)
    plans.push({
      uri: uri,
      fileName: fileName,
      fileBytes: fileBytes,
      progressBytes: fileBytes > 0 ? fileBytes : 1
    })
  }
  return plans
}

async function resolveFileSize(path: string): Promise<number> {
  try {
    const syncStatSize: number = Number(fs.statSync(path).size)
    return normalizeFileSize(syncStatSize)
  } catch (err) {
    LogHelper.warn('RomImport', 'Stat', `statSync 读取文件大小失败: ${(err as Error).message || String(err)}`)
  }

  try {
    const statSize: number = Number((await fs.stat(path)).size)
    return normalizeFileSize(statSize)
  } catch (err) {
    LogHelper.warn('RomImport', 'Stat', `stat 读取文件大小失败: ${(err as Error).message || String(err)}`)
  }
  return 0
}

function normalizeFileSize(size: number): number {
  if (!Number.isFinite(size) || size <= 0) {
    return 0
  }
  return Math.floor(size)
}

function copyFileFromUri(
  sourceUri: string,
  destPath: string,
  onChunkCopied?: (copiedBytes: number) => void,
  shouldCancel?: () => boolean
): void {
  let srcFile: fs.File | undefined = undefined
  let destFile: fs.File | undefined = undefined
  try {
    srcFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY)
    destFile = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const bufSize = 64 * 1024
    const buf = new ArrayBuffer(bufSize)
    let readSize = 0
    const readOptions: ReadOptions = {
      offset: readSize,
      length: bufSize
    }
    let readLen = fs.readSync(srcFile.fd, buf, readOptions)
    while (readLen > 0) {
      if (shouldCancel?.()) {
        throw new ImportCanceledError(readSize)
      }
      readSize += readLen
      const writeOptions: WriteOptions = {
        length: readLen
      }
      fs.writeSync(destFile.fd, buf, writeOptions)
      onChunkCopied?.(readSize)
      if (shouldCancel?.()) {
        throw new ImportCanceledError(readSize)
      }
      readOptions.offset = readSize
      readLen = fs.readSync(srcFile.fd, buf, readOptions)
    }
  } finally {
    if (srcFile) {
      fs.closeSync(srcFile.fd)
    }
    if (destFile) {
      fs.closeSync(destFile.fd)
    }
  }
}

async function deletePathIfExists(path: string): Promise<void> {
  try {
    await fs.unlink(path)
  } catch (err) {
    return
  }
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path)
  } catch (err) {
    return
  }
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (err) {
    return false
  }
}
