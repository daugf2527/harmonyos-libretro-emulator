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
import { RuntimeRomSourceItem } from './RuntimeRomCatalog'

interface RuntimeRomSourceNapi {
  refactoredGetRawFileListAsync(resMgr: resourceManager.ResourceManager, dir?: string): Promise<string[]>
}

interface BundledRomEntry {
  fileName: string
  relativePath: string
}

const nativeApi = testNapi as RuntimeRomSourceNapi

const BUNDLED_ROM_ROOT_DIR = 'roms'

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
    result.push({
      fileName,
      relativePath
    })
  })
  LogHelper.info(
    'RuntimeRomSourceScanner',
    'Scan',
    `${BUNDLED_ROM_ROOT_DIR}: 发现 ${result.length} 个 ROM (原始返回 ${rawList.length})`
  )
  LogHelper.info('RuntimeRomSourceScanner', 'Scan', `内置 ROM 扫描完成，共 ${result.length} 个`)
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
      launchPath: `roms/${item.relativePath}`
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
      romFile: `roms/${item.relativePath}`,
      sourceType: 'BUNDLED'
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
