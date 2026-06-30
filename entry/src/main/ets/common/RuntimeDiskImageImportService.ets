import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs, picker, ReadOptions } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface RuntimeDiskImageImportResult {
  canceled: boolean
  importedEntryName: string
  importedEntryPath: string
  copiedCount: number
  detail: string
}

export interface RuntimeDiskImageImportOptions {
  shouldCancel?: () => boolean
}

interface RuntimeDiskPickerSelectionResult {
  uris: string[]
  canceled: boolean
  failed: boolean
  message: string
}

interface RuntimeDiskImagePlan {
  uri: string
  fileName: string
  dependencyNames: string[]
  isDependencyFile: boolean
  sourceIndex: number
}

interface RuntimeDiskPrimaryPlanResult {
  plan: RuntimeDiskImagePlan | undefined
  detail: string
}

interface RuntimeDiskImageFileErrorWithCode {
  code?: string | number
}

interface PickerSelectOptionsCompat {
  maxSelectNumber: number
}

class RuntimeDiskImportCanceledError extends Error {
  constructor() {
    super('RUNTIME_DISK_IMPORT_CANCELED')
  }
}

const MULTIFILE_ENTRY_EXTENSIONS: string[] = ['cue', 'm3u']
const RUNTIME_DISK_IMAGE_IMPORT_DIR = 'runtime/disks/imported'
const MAX_IMPORT_FILE_NAME_LENGTH = 120

export async function importPickedRuntimeDiskImages(
  context: common.UIAbilityContext,
  options?: RuntimeDiskImageImportOptions
): Promise<RuntimeDiskImageImportResult> {
  const selection = await pickRuntimeDiskImageUris(context)
  if (selection.failed) {
    return {
      canceled: false,
      importedEntryName: '',
      importedEntryPath: '',
      copiedCount: 0,
      detail: selection.message
    }
  }
  return importRuntimeDiskImageUris(context, selection.uris, options, selection.canceled)
}

async function pickRuntimeDiskImageUris(
  context: common.UIAbilityContext
): Promise<RuntimeDiskPickerSelectionResult> {
  const documentSelectOptions = new picker.DocumentSelectOptions() as PickerSelectOptionsCompat
  documentSelectOptions.maxSelectNumber = 12
  const documentPicker = new picker.DocumentViewPicker(context)
  try {
    const uris = await documentPicker.select(documentSelectOptions)
    const safeUris = uris ?? []
    return {
      uris: safeUris,
      canceled: safeUris.length === 0,
      failed: false,
      message: safeUris.length === 0 ? '这次没有选中磁盘镜像' : ''
    }
  } catch (err) {
    const pickerError = err as BusinessError
    LogHelper.warn(
      'RuntimeDiskImport',
      'Picker',
      `选择磁盘镜像取消或失败: ${pickerError.code}, ${pickerError.message}`
    )
    return {
      uris: [],
      canceled: false,
      failed: true,
      message: '系统文件选择器这次没有成功返回磁盘镜像，请稍后再试'
    }
  }
}

async function importRuntimeDiskImageUris(
  context: common.UIAbilityContext,
  uris: string[],
  options?: RuntimeDiskImageImportOptions,
  selectionCanceled: boolean = false
): Promise<RuntimeDiskImageImportResult> {
  const result = createEmptyRuntimeDiskImageImportResult()
  if (!uris || uris.length === 0) {
    result.canceled = selectionCanceled
    result.detail = selectionCanceled ? '这次没有选中磁盘镜像' : '这次没有拿到可导入的磁盘镜像'
    return result
  }

  const diskDir = `${context.filesDir}/${RUNTIME_DISK_IMAGE_IMPORT_DIR}`
  await ensureDirExists(diskDir)
  if (options?.shouldCancel?.()) {
    result.canceled = true
    result.detail = '磁盘镜像导入已取消'
    return result
  }
  const plans = await buildRuntimeDiskImagePlans(uris)
  const primaryResult = resolvePrimaryRuntimeDiskPlan(plans)
  if (!primaryResult.plan) {
    result.detail = primaryResult.detail
    return result
  }

  const missingDependencyNames = await findMissingDependencyNames(
    diskDir,
    plans,
    primaryResult.plan.dependencyNames
  )
  if (missingDependencyNames.length > 0) {
    result.detail = `缺少依赖文件: ${missingDependencyNames.join(', ')}`
    return result
  }

  const orderedPlans = sortRuntimeDiskImagePlans(plans)
  for (let index = 0; index < orderedPlans.length; index += 1) {
    if (options?.shouldCancel?.()) {
      result.canceled = true
      result.detail = '磁盘镜像导入已取消'
      return result
    }
    const plan = orderedPlans[index]
    const destPath = `${diskDir}/${plan.fileName}`
    try {
      await writeRuntimeDiskImageFile(plan.uri, destPath, options?.shouldCancel)
    } catch (err) {
      if (err instanceof RuntimeDiskImportCanceledError) {
        result.canceled = true
        result.detail = '磁盘镜像导入已取消'
        return result
      }
      throw err as Error
    }
  }

  result.canceled = false
  result.importedEntryName = primaryResult.plan.fileName
  result.importedEntryPath = `${diskDir}/${primaryResult.plan.fileName}`
  result.copiedCount = orderedPlans.length
  result.detail = orderedPlans.length > 1
    ? `已写入 ${orderedPlans.length} 个磁盘镜像文件`
    : '已写入磁盘镜像文件'
  return result
}

function createEmptyRuntimeDiskImageImportResult(): RuntimeDiskImageImportResult {
  return {
    canceled: false,
    importedEntryName: '',
    importedEntryPath: '',
    copiedCount: 0,
    detail: ''
  }
}

async function buildRuntimeDiskImagePlans(
  uris: string[]
): Promise<RuntimeDiskImagePlan[]> {
  const plans: RuntimeDiskImagePlan[] = []
  for (let index = 0; index < uris.length; index += 1) {
    const uri = uris[index]
    const fileName = getFileNameFromUri(uri, index)
    const dependencyNames = await resolveMultiFileDependencyNames(uri, fileName)
    plans.push({
      uri,
      fileName,
      dependencyNames,
      isDependencyFile: false,
      sourceIndex: index
    })
  }
  markSelectedDependencyFiles(plans)
  return plans
}

function markSelectedDependencyFiles(plans: RuntimeDiskImagePlan[]): void {
  const dependencyNameSet: Set<string> = new Set()
  plans.forEach((plan: RuntimeDiskImagePlan) => {
    plan.dependencyNames.forEach((name: string) => {
      dependencyNameSet.add(normalizeFileNameKey(name))
    })
  })
  plans.forEach((plan: RuntimeDiskImagePlan) => {
    plan.isDependencyFile = dependencyNameSet.has(normalizeFileNameKey(plan.fileName))
  })
}

function resolvePrimaryRuntimeDiskPlan(
  plans: RuntimeDiskImagePlan[]
): RuntimeDiskPrimaryPlanResult {
  const nonDependencyPlans: RuntimeDiskImagePlan[] = []
  plans.forEach((plan: RuntimeDiskImagePlan) => {
    if (!plan.isDependencyFile) {
      nonDependencyPlans.push(plan)
    }
  })

  if (nonDependencyPlans.length === 0) {
    return {
      plan: plans.length > 0 ? plans[0] : undefined,
      detail: plans.length > 0 ? '' : '未选择磁盘镜像'
    }
  }

  if (nonDependencyPlans.length > 1) {
    return {
      plan: undefined,
      detail: '请一次只选择一个主磁盘入口文件，可附带其依赖文件'
    }
  }

  return {
    plan: nonDependencyPlans[0],
    detail: ''
  }
}

async function findMissingDependencyNames(
  diskDir: string,
  plans: RuntimeDiskImagePlan[],
  dependencyNames: string[]
): Promise<string[]> {
  if (dependencyNames.length === 0) {
    return []
  }

  const selectedNameSet: Set<string> = new Set()
  plans.forEach((plan: RuntimeDiskImagePlan) => {
    selectedNameSet.add(normalizeFileNameKey(plan.fileName))
  })

  const missingNames: string[] = []
  for (let index = 0; index < dependencyNames.length; index += 1) {
    const dependencyName = dependencyNames[index]
    const normalizedName = normalizeFileNameKey(dependencyName)
    if (selectedNameSet.has(normalizedName)) {
      continue
    }
    if (await pathExists(`${diskDir}/${dependencyName}`)) {
      continue
    }
    missingNames.push(dependencyName)
  }
  return missingNames
}

function sortRuntimeDiskImagePlans(
  plans: RuntimeDiskImagePlan[]
): RuntimeDiskImagePlan[] {
  const sortedPlans: RuntimeDiskImagePlan[] = []
  plans.forEach((plan: RuntimeDiskImagePlan) => {
    sortedPlans.push(plan)
  })
  sortedPlans.sort((left: RuntimeDiskImagePlan, right: RuntimeDiskImagePlan) => {
    if (left.isDependencyFile !== right.isDependencyFile) {
      return left.isDependencyFile ? -1 : 1
    }
    return left.sourceIndex - right.sourceIndex
  })
  return sortedPlans
}

function getFileNameFromUri(uri: string, index: number): string {
  const sanitizedUri = uri.split('?')[0]
  const lastSlash = sanitizedUri.lastIndexOf('/')
  const encodedName = lastSlash >= 0 ? sanitizedUri.substring(lastSlash + 1) : sanitizedUri
  if (encodedName.length === 0) {
    return `runtime_disk_${Date.now()}_${index}.img`
  }
  try {
    return sanitizeImportFileName(
      decodeURIComponent(encodedName),
      `runtime_disk_${Date.now()}_${index}.img`
    )
  } catch (_err) {
    return sanitizeImportFileName(
      encodedName,
      `runtime_disk_${Date.now()}_${index}.img`
    )
  }
}

async function resolveMultiFileDependencyNames(
  uri: string,
  fileName: string
): Promise<string[]> {
  const ext = getFileExtension(fileName)
  if (!MULTIFILE_ENTRY_EXTENSIONS.includes(ext)) {
    return []
  }
  let text = ''
  try {
    text = await fs.readText(uri)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn(
      'RuntimeDiskImport',
      'Dependency',
      `读取多文件入口失败 ${LogHelper.describePathForLog(fileName)}: ${message}`
    )
    throw new Error(`RUNTIME_DISK_MULTIFILE_ENTRY_READ_FAILED:${fileName}`)
  }

  if (ext === 'cue') {
    return parseCueDependencyNames(text)
  }
  if (ext === 'm3u') {
    return parseM3uDependencyNames(text)
  }
  return []
}

function getFileExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return ''
  }
  return fileName.substring(dotIndex + 1).toLowerCase()
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
  const normalizedName = normalizeFileNameKey(name)
  const exists = names.findIndex((item: string) => normalizeFileNameKey(item) === normalizedName) >= 0
  if (!exists) {
    names.push(name)
  }
}

function extractBaseName(path: string): string {
  const normalizedPath = path.replace(/\\/g, '/')
  const slashIndex = normalizedPath.lastIndexOf('/')
  return sanitizeImportFileName(
    slashIndex >= 0 ? normalizedPath.substring(slashIndex + 1) : normalizedPath,
    ''
  )
}

function normalizeFileNameKey(fileName: string): string {
  return fileName.toLowerCase()
}

async function writeRuntimeDiskImageFile(
  sourceUri: string,
  destPath: string,
  shouldCancel?: () => boolean
): Promise<void> {
  const tmpPath = `${destPath}.importing`
  await deletePathIfExists(tmpPath)
  try {
    await copyFileFromUri(sourceUri, tmpPath, shouldCancel)
    if (shouldCancel?.()) {
      throw new RuntimeDiskImportCanceledError()
    }
    await deletePathIfExists(destPath)
    await fs.rename(tmpPath, destPath)
  } catch (err) {
    await deletePathIfExists(tmpPath)
    throw err as Error
  }
}

async function copyFileFromUri(
  sourceUri: string,
  destPath: string,
  shouldCancel?: () => boolean
): Promise<void> {
  let srcFile: fs.File | undefined = undefined
  let destFile: fs.File | undefined = undefined
  try {
    srcFile = await fs.open(sourceUri, fs.OpenMode.READ_ONLY)
    destFile = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    const bufSize = 64 * 1024
    while (true) {
      if (shouldCancel?.()) {
        throw new RuntimeDiskImportCanceledError()
      }
      const chunk = new ArrayBuffer(bufSize)
      const readOptions: ReadOptions = {
        length: bufSize
      }
      const readLen = await fs.read(srcFile.fd, chunk, readOptions)
      if (readLen <= 0) {
        break
      }
      const chunkToWrite = readLen >= chunk.byteLength ? chunk : chunk.slice(0, readLen)
      await fs.write(destFile.fd, chunkToWrite)
      if (shouldCancel?.()) {
        throw new RuntimeDiskImportCanceledError()
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

async function deletePathIfExists(path: string): Promise<void> {
  try {
    await fs.unlink(path)
  } catch (_err) {
    return
  }
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (_err) {
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

function isMissingFileError(err: Error | BusinessError | RuntimeDiskImageFileErrorWithCode): boolean {
  const errorCode = (err as RuntimeDiskImageFileErrorWithCode).code
  if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
    return true
  }
  const message = (err as Error).message || String(err)
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}
