import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import type { resourceManager } from '@kit.LocalizationKit'
import { LibraryRomFileSource } from './LibraryRecordFactory'
import LogHelper from './LogHelper'
import {
  buildImportedRomFilePath,
  getPreferredCoreIdForFile,
  listSandboxRomFiles
} from './RomImportService'
import {
  buildNoGameRuntimeRomFile,
  RuntimeRomSourceItem
} from './RuntimeRomCatalog'

interface RuntimeRomSourceNapi {
  refactoredGetRawFileListAsync(resMgr: resourceManager.ResourceManager, dir?: string): Promise<string[]>
}

interface BundledRomEntry {
  fileName: string
  relativePath: string
}

interface BundledNoGameSource {
  title: string
  fileName: string
  coreId: string
  platform: string
}

const nativeApi = testNapi as RuntimeRomSourceNapi
const BUNDLED_ROM_ROOT_DIR = 'roms'
const BUNDLED_ROM_SUBDIRS: string[] = ['', 'gba', 'nes', 'snes', 'gb_gbc', 'md', 'nds', 'misc', 'arcade']

const BUNDLED_NO_GAME_SOURCES: BundledNoGameSource[] = [
  { title: '2048', fileName: '2048 内置测试', coreId: '2048', platform: 'PUZZLE' },
  { title: 'Mr.Boom', fileName: 'Mr.Boom 内置测试', coreId: 'mrboom', platform: 'ARCADE' }
]

function normalizeBundledRawPath(path: string): string {
  const normalized = path.replace(/\\/g, '/').trim()
  if (normalized.length === 0 || normalized.startsWith('/') || normalized.includes('..')) {
    return ''
  }
  return normalized
}

function getFileNameFromRelativePath(path: string): string {
  const slash = path.lastIndexOf('/')
  return slash >= 0 ? path.substring(slash + 1) : path
}

async function listBundledRomEntries(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<BundledRomEntry[] | undefined> {
  const result: BundledRomEntry[] = []
  const seenRelativePaths: Set<string> = new Set()
  const groupedEntries: Map<string, BundledRomEntry[]> = new Map()
  BUNDLED_ROM_SUBDIRS.forEach((dir: string) => {
    groupedEntries.set(dir, [])
  })
  let rawList: string[] = []
  try {
    rawList = await nativeApi.refactoredGetRawFileListAsync(context.resourceManager, BUNDLED_ROM_ROOT_DIR)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeRomSourceScanner', 'Scan', `扫描内置 ROM 失败 ${BUNDLED_ROM_ROOT_DIR}: ${message}`)
    return result
  }
  if (!shouldContinue()) {
    return undefined
  }

  rawList.forEach((item: string) => {
    const relativePath = normalizeBundledRawPath(item)
    if (relativePath.length === 0 || seenRelativePaths.has(relativePath)) {
      return
    }
    seenRelativePaths.add(relativePath)
    const fileName = getFileNameFromRelativePath(relativePath)
    if (getPreferredCoreIdForFile(fileName).length === 0) {
      return
    }
    const entry: BundledRomEntry = {
      fileName,
      relativePath
    }
    const slash = relativePath.indexOf('/')
    const subDir = slash >= 0 ? relativePath.substring(0, slash) : ''
    const bucket = groupedEntries.get(subDir)
    if (bucket) {
      bucket.push(entry)
      return
    }
    result.push(entry)
  })
  BUNDLED_ROM_SUBDIRS.forEach((subDir: string) => {
    const bucket = groupedEntries.get(subDir) || []
    LogHelper.info(
      'RuntimeRomSourceScanner',
      'Scan',
      `${BUNDLED_ROM_ROOT_DIR}/${subDir.length > 0 ? subDir : '.'}: ${bucket.length} 个候选 ROM`
    )
    bucket.forEach((entry: BundledRomEntry) => {
      result.push(entry)
    })
  })
  LogHelper.info(
    'RuntimeRomSourceScanner',
    'Scan',
    `${BUNDLED_ROM_ROOT_DIR}: 发现 ${result.length} 个 ROM (原始返回 ${rawList.length})`
  )
  return result
}

export async function scanRuntimeRomSources(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<RuntimeRomSourceItem[] | undefined> {
  const sources: RuntimeRomSourceItem[] = []
  const bundled = await listBundledRomEntries(context, shouldContinue)
  if (!bundled) {
    return undefined
  }
  bundled.forEach((item: BundledRomEntry) => {
    sources.push({
      fileName: item.fileName,
      launchPath: `${BUNDLED_ROM_ROOT_DIR}/${item.relativePath}`
    })
  })
  const localFiles: string[] = await listSandboxRomFiles(context.filesDir)
  if (!shouldContinue()) {
    return undefined
  }
  localFiles.forEach((fileName: string) => {
    const launchPath = buildImportedRomFilePath(context.filesDir, fileName)
    if (launchPath.length === 0) {
      return
    }
    sources.push({
      fileName: fileName,
      launchPath: launchPath
    })
  })
  return sources
}

export async function scanLibraryRomSources(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<LibraryRomFileSource[] | undefined> {
  const sources: LibraryRomFileSource[] = []
  const bundled = await listBundledRomEntries(context, shouldContinue)
  if (!bundled) {
    return undefined
  }
  bundled.forEach((item: BundledRomEntry) => {
    sources.push({
      fileName: item.fileName,
      romFile: `${BUNDLED_ROM_ROOT_DIR}/${item.relativePath}`,
      sourceType: 'BUNDLED'
    })
  })
  BUNDLED_NO_GAME_SOURCES.forEach((item: BundledNoGameSource) => {
    sources.push({
      fileName: item.fileName,
      romFile: buildNoGameRuntimeRomFile(item.coreId),
      sourceType: 'BUNDLED',
      preferredCoreId: item.coreId,
      title: item.title,
      platform: item.platform
    })
  })
  const localFiles: string[] = await listSandboxRomFiles(context.filesDir)
  if (!shouldContinue()) {
    return undefined
  }
  localFiles.forEach((fileName: string) => {
    const romFile = buildImportedRomFilePath(context.filesDir, fileName)
    if (romFile.length === 0) {
      return
    }
    sources.push({
      fileName: fileName,
      romFile: romFile,
      sourceType: 'IMPORTED'
    })
  })
  return sources
}
