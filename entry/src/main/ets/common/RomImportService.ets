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

interface RomImportFileErrorWithCode {
  code?: string | number
}

export interface RomImportOptions {
  overwriteExisting?: boolean
  shouldCancel?: () => boolean
}

export interface RomImportConflictSummary {
  conflictCount: number
  conflictNames: string[]
}

export interface DocumentPickerSelectionResult {
  uris: string[]
  canceled: boolean
  failed: boolean
  message: string
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
  dependencyNames: string[]
  isDependencyFile: boolean
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
const MULTIFILE_ENTRY_EXTENSIONS: string[] = ['cue', 'm3u']

const DOCUMENTATION_BASENAMES: string[] = [
  'readme', 'license', 'licence', 'copying', 'changelog', 'changes', 'notes',
  'authors', 'contributors', 'install', 'todo', 'history', 'news', 'credits'
]
const MAX_IMPORT_FILE_NAME_LENGTH = 120
const IMPORTED_ROM_RELATIVE_DIR = 'roms/imported'

export function getRomFileExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return ''
  }
  return fileName.substring(dotIndex + 1).toLowerCase()
}

function isLikelyDocumentationFile(fileName: string): boolean {
  const slashIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'))
  const base = slashIndex >= 0 ? fileName.substring(slashIndex + 1) : fileName
  const dotIndex = base.lastIndexOf('.')
  const stem = dotIndex > 0 ? base.substring(0, dotIndex) : base
  return DOCUMENTATION_BASENAMES.includes(stem.toLowerCase())
}

export function getPreferredCoreIdForFile(fileName: string): string {
  if (isLikelyDocumentationFile(fileName)) {
    return ''
  }
  if (fileName.toLowerCase() === 'data.zip') {
    return 'xrick'
  }
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
  const romDir = buildImportedRomDir(filesDir)
  if (romDir.length === 0) {
    return []
  }
  try {
    const entries = await fs.listFile(romDir)
    if (!entries || entries.length === 0) {
      return []
    }
    const names = entries.filter((item: string) => item.length > 0 && item.indexOf('/') < 0)
    names.sort((left: string, right: string) => left.localeCompare(right))
    return listSupportedSandboxRomFiles(names)
  } catch (err) {
    if (isMissingFileError(err)) {
      return []
    }
    throw err as Error
  }
}

export function buildImportedRomFilePath(filesDir: string, fileName: string): string {
  const romDir = buildImportedRomDir(filesDir)
  const safeName = sanitizeImportFileName(fileName, '')
  if (romDir.length === 0 || safeName.length === 0 || safeName !== fileName.trim()) {
    return ''
  }
  return `${romDir}/${safeName}`
}

export async function deleteImportedRomFile(context: common.UIAbilityContext, romPath: string): Promise<void> {
  const safePath = resolveImportedRomDeletePath(context.filesDir, romPath)
  if (safePath.length === 0) {
    throw new Error('ROM_DELETE_PATH_REJECTED')
  }
  try {
    await fs.unlink(safePath)
  } catch (err) {
    if (isMissingFileError(err as Error | BusinessError | RomImportFileErrorWithCode)) {
      return
    }
    throw err as Error
  }
}

export async function pickRomUris(context: common.UIAbilityContext): Promise<DocumentPickerSelectionResult> {
  const documentSelectOptions = new picker.DocumentSelectOptions() as PickerSelectOptionsCompat
  documentSelectOptions.maxSelectNumber = 30
  const documentPicker = new picker.DocumentViewPicker(context)
  try {
    const uris = await documentPicker.select(documentSelectOptions)
    const safeUris = uris ?? []
    return {
      uris: safeUris,
      canceled: safeUris.length === 0,
      failed: false,
      message: safeUris.length === 0 ? '这次没有选中文件' : ''
    }
  } catch (err) {
    const pickerError = err as BusinessError
    LogHelper.warn('RomImport', 'Picker', `选择文件取消或失败: ${pickerError.code}, ${pickerError.message}`)
    return {
      uris: [],
      canceled: false,
      failed: true,
      message: '系统文件选择器这次没有成功返回文件，请稍后再试'
    }
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
  const romDir = buildImportedRomDir(context.filesDir)
  if (romDir.length === 0) {
    result.failedCount = uris.length
    result.failedNames = uris.map((uri: string, index: number) => getFileNameFromUri(uri, index))
    result.items = result.failedNames.map((fileName: string): RomImportItemResult => ({
      fileName: fileName,
      status: 'FAILED',
      detail: 'IMPORT_DIR_REJECTED'
    }))
    return result
  }
  await ensureDirExists(romDir)
  const importPlans = await buildImportFilePlans(uris)
  const totalBytes = importPlans.reduce((sum: number, item: ImportFilePlan) => sum + item.progressBytes, 0)
  const hasAccurateByteProgress = importPlans.every((item: ImportFilePlan) => item.fileBytes > 0)
  let completedBytes = 0
  const completedNameSet: Set<string> = new Set()

  for (let index = 0; index < uris.length; index += 1) {
    const currentPlan = importPlans[index]
    const fileName = currentPlan?.fileName ?? getFileNameFromUri(uris[index], index)
    const currentFileTotalBytes = currentPlan?.fileBytes ?? 0
    const currentProgressBytes = currentPlan?.progressBytes ?? 1
    const isDependencyFile = currentPlan?.isDependencyFile ?? false
    const dependencyNames = currentPlan?.dependencyNames ?? []
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
    const missingDependencyNames = await findMissingDependencyNames(romDir, completedNameSet, dependencyNames)
    if (missingDependencyNames.length > 0) {
      result.failedCount += 1
      result.failedNames.push(fileName)
      appendImportItemResult(
        result,
        fileName,
        'FAILED',
        `MISSING_DEPENDENCY: ${missingDependencyNames.join(', ')}`
      )
      completedBytes += currentProgressBytes
      onProgress?.({
        totalCount: uris.length,
        completedCount: index + 1,
        currentFileIndex: index + 1,
        currentFileName: fileName,
        stage: 'MISSING_DEPENDENCY',
        totalBytes: totalBytes,
        completedBytes: completedBytes,
        currentFileTotalBytes: currentFileTotalBytes,
        currentFileCompletedBytes: 0,
        hasAccurateByteProgress: hasAccurateByteProgress
      })
      continue
    }

    if (getPreferredCoreIdForFile(fileName).length === 0 && !isDependencyFile) {
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
          await copyFileFromUri(uri, tempOverwritePath, (nextCopiedBytes: number) => {
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
          if (options?.shouldCancel?.()) {
            throw new ImportCanceledError(copiedBytesForFile)
          }
          await deletePathIfExists(destPath)
          await fs.rename(tempOverwritePath, destPath)
          result.overwrittenCount += 1
          result.overwrittenNames.push(fileName)
          completedNameSet.add(normalizeFileNameKey(fileName))
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
          LogHelper.error('RomImport', 'Copy', `覆盖文件失败 ${LogHelper.describePathForLog(fileName)}: ${overwriteMessage}`)
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
      completedNameSet.add(normalizeFileNameKey(fileName))
      appendImportItemResult(result, fileName, 'SKIPPED', isDependencyFile ? '依赖文件已存在' : '目标文件已存在')
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
    const tempImportPath = `${destPath}.importing`
    try {
      await deletePathIfExists(tempImportPath)
      await copyFileFromUri(uri, tempImportPath, (nextCopiedBytes: number) => {
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
      if (options?.shouldCancel?.()) {
        throw new ImportCanceledError(copiedBytesForFile)
      }
      await fs.rename(tempImportPath, destPath)
      result.importedCount += 1
      result.importedNames.push(fileName)
      completedNameSet.add(normalizeFileNameKey(fileName))
      appendImportItemResult(
        result,
        fileName,
        'IMPORTED',
        isDependencyFile ? '已作为多文件依赖写入本地游戏目录' : '已成功写入本地游戏目录'
      )
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
        await deletePathIfExists(tempImportPath)
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
      await deletePathIfExists(tempImportPath)
      LogHelper.error('RomImport', 'Copy', `复制文件失败 ${LogHelper.describePathForLog(fileName)}: ${message}`)
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
  const romDir = buildImportedRomDir(context.filesDir)
  if (romDir.length === 0) {
    return {
      conflictCount: 0,
      conflictNames: []
    }
  }
  await ensureDirExists(romDir)
  const plans = await buildImportFilePlans(uris)
  const conflictNames: string[] = []
  for (let index = 0; index < plans.length; index += 1) {
    const plan = plans[index]
    if (getPreferredCoreIdForFile(plan.fileName).length === 0 && !plan.isDependencyFile) {
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
    return sanitizeImportFileName(decodeURIComponent(encodedName), `imported_${Date.now()}_${index}.rom`)
  } catch (err) {
    return sanitizeImportFileName(encodedName, `imported_${Date.now()}_${index}.rom`)
  }
}

async function buildImportFilePlans(uris: string[]): Promise<ImportFilePlan[]> {
  const plans: ImportFilePlan[] = []
  for (let index = 0; index < uris.length; index += 1) {
    const uri = uris[index]
    const fileName = getFileNameFromUri(uri, index)
    const fileBytes = await resolveFileSize(uri)
    const dependencyNames = await resolveMultiFileDependencyNames(uri, fileName)
    plans.push({
      uri: uri,
      fileName: fileName,
      fileBytes: fileBytes,
      progressBytes: fileBytes > 0 ? fileBytes : 1,
      dependencyNames: dependencyNames,
      isDependencyFile: false
    })
  }
  markSelectedDependencyFiles(plans)
  plans.sort((left: ImportFilePlan, right: ImportFilePlan) => {
    if (left.isDependencyFile !== right.isDependencyFile) {
      return left.isDependencyFile ? -1 : 1
    }
    return left.fileName.localeCompare(right.fileName)
  })
  return plans
}

function markSelectedDependencyFiles(plans: ImportFilePlan[]): void {
  const dependencyNameSet: Set<string> = new Set()
  plans.forEach((plan: ImportFilePlan) => {
    plan.dependencyNames.forEach((name: string) => dependencyNameSet.add(normalizeFileNameKey(name)))
  })
  plans.forEach((plan: ImportFilePlan) => {
    plan.isDependencyFile = dependencyNameSet.has(normalizeFileNameKey(plan.fileName))
  })
}

async function findMissingDependencyNames(
  romDir: string,
  completedNameSet: Set<string>,
  dependencyNames: string[]
): Promise<string[]> {
  if (dependencyNames.length === 0) {
    return []
  }
  const missingNames: string[] = []
  for (let index = 0; index < dependencyNames.length; index += 1) {
    const dependencyName = dependencyNames[index]
    if (completedNameSet.has(normalizeFileNameKey(dependencyName))) {
      continue
    }
    if (await pathExists(`${romDir}/${dependencyName}`)) {
      continue
    }
    missingNames.push(dependencyName)
  }
  return missingNames
}

async function resolveMultiFileDependencyNames(uri: string, fileName: string): Promise<string[]> {
  const ext = getRomFileExtension(fileName)
  if (!MULTIFILE_ENTRY_EXTENSIONS.includes(ext)) {
    return []
  }
  let text = ''
  try {
    text = await fs.readText(uri)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn(
      'RomImport',
      'Dependency',
      `读取多文件入口失败 ${LogHelper.describePathForLog(fileName)}: ${message}`
    )
    throw new Error(`IMPORT_MULTIFILE_ENTRY_READ_FAILED:${fileName}`)
  }
  if (ext === 'cue') {
    return parseCueDependencyNames(text)
  }
  if (ext === 'm3u') {
    return parseM3uDependencyNames(text)
  }
  return []
}

function parseCueDependencyNames(text: string): string[] {
  const names: string[] = []
  const lines = text.split(/\r?\n/)
  lines.forEach((line: string) => {
    const match = /^\s*FILE\s+"?([^"]+?)"?\s+/i.exec(line)
    if (!match || match.length < 2) {
      return
    }
    appendDependencyName(names, extractBaseName(match[1]))
  })
  return names
}

function parseM3uDependencyNames(text: string): string[] {
  const names: string[] = []
  const lines = text.split(/\r?\n/)
  lines.forEach((line: string) => {
    const trimmed = line.trim()
    if (trimmed.length === 0 || trimmed.startsWith('#')) {
      return
    }
    appendDependencyName(names, extractBaseName(trimmed))
  })
  return names
}

function appendDependencyName(names: string[], name: string): void {
  if (name.length === 0) {
    return
  }
  const key = normalizeFileNameKey(name)
  const exists = names.findIndex((item: string) => normalizeFileNameKey(item) === key) >= 0
  if (!exists) {
    names.push(name)
  }
}

function extractBaseName(path: string): string {
  const normalized = path.replace(/\\/g, '/')
  const slashIndex = normalized.lastIndexOf('/')
  return sanitizeImportFileName(
    slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized,
    ''
  )
}

function normalizeFileNameKey(fileName: string): string {
  return fileName.toLowerCase()
}

async function resolveFileSize(path: string): Promise<number> {
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

async function copyFileFromUri(
  sourceUri: string,
  destPath: string,
  onChunkCopied?: (copiedBytes: number) => void,
  shouldCancel?: () => boolean
): Promise<void> {
  let srcFile: fs.File | undefined = undefined
  let destFile: fs.File | undefined = undefined
  try {
    srcFile = await fs.open(sourceUri, fs.OpenMode.READ_ONLY)
    destFile = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const bufSize = 64 * 1024
    let readSize = 0
    while (true) {
      if (shouldCancel?.()) {
        throw new ImportCanceledError(readSize)
      }
      const chunk = new ArrayBuffer(bufSize)
      const readOptions: ReadOptions = {
        length: bufSize
      }
      const readLen = await fs.read(srcFile.fd, chunk, readOptions)
      if (readLen <= 0) {
        break
      }
      readSize += readLen
      const chunkToWrite = readLen >= chunk.byteLength ? chunk : chunk.slice(0, readLen)
      await fs.write(destFile.fd, chunkToWrite)
      onChunkCopied?.(readSize)
      if (readSize % (1024 * 1024) === 0) {
        await Promise.resolve()
      }
      if (shouldCancel?.()) {
        throw new ImportCanceledError(readSize)
      }
    }
  } catch (err) {
    throw err as Error
  } finally {
    if (srcFile) {
      try {
        await fs.close(srcFile.fd)
      } catch (_closeErr) {
      }
    }
    if (destFile) {
      try {
        await fs.close(destFile.fd)
      } catch (_closeErr) {
      }
    }
  }
}

function sanitizeImportFileName(fileName: string, fallback: string): string {
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
  normalized = truncateImportFileName(normalized)
  return normalized.length > 0 ? normalized : fallback
}

function truncateImportFileName(fileName: string): string {
  if (fileName.length <= MAX_IMPORT_FILE_NAME_LENGTH) {
    return fileName
  }
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex > 0 && dotIndex < fileName.length - 1) {
    const extension = fileName.substring(dotIndex)
    if (extension.length < MAX_IMPORT_FILE_NAME_LENGTH - 1) {
      return `${fileName.substring(0, MAX_IMPORT_FILE_NAME_LENGTH - extension.length)}${extension}`
    }
  }
  return fileName.substring(0, MAX_IMPORT_FILE_NAME_LENGTH)
}

function buildImportedRomDir(filesDir: string): string {
  const normalized = normalizeFsPath(filesDir)
  if (normalized.length === 0 || normalized.includes('..')) {
    return ''
  }
  return `${normalized}/${IMPORTED_ROM_RELATIVE_DIR}`
}

function resolveImportedRomDeletePath(filesDir: string, romPath: string): string {
  const romDir = buildImportedRomDir(filesDir)
  const normalizedPath = normalizeFsPath(romPath)
  if (romDir.length === 0 || normalizedPath.length === 0) {
    return ''
  }
  const rootPrefix = `${romDir}/`
  if (!normalizedPath.startsWith(rootPrefix)) {
    return ''
  }
  const fileName = normalizedPath.substring(rootPrefix.length)
  if (
    fileName.length === 0 ||
    fileName.includes('/') ||
    fileName.includes('\\') ||
    fileName.includes('..') ||
    fileName.endsWith('.importing')
  ) {
    return ''
  }
  const safeName = sanitizeImportFileName(fileName, '')
  if (safeName.length === 0 || safeName !== fileName.trim()) {
    return ''
  }
  return `${rootPrefix}${safeName}`
}

function normalizeFsPath(path: string): string {
  let normalized = path.replace(/\\/g, '/').trim()
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1)
  }
  return normalized
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
    await fs.mkdir(path, true)
  } catch (err) {
    return
  }
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (err) {
    if (isMissingFileError(err)) {
      return false
    }
    throw err as Error
  }
}

function isMissingFileError(err: Error | BusinessError | RomImportFileErrorWithCode): boolean {
  const errorCode = (err as RomImportFileErrorWithCode).code
  if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
    return true
  }
  const message = (err as Error).message || String(err)
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}
