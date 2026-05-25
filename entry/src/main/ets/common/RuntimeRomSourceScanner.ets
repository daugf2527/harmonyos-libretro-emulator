import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import { LibraryRomFileSource } from './LibraryRecordFactory'
import LogHelper from './LogHelper'
import { listSandboxRomFiles } from './RomImportService'
import { RuntimeRomSourceItem } from './RuntimeRomCatalog'

interface RuntimeRomSourceNapi {
  refactoredGetRawFileListAsync(resMgr: object, dir?: string): Promise<string[]>
}

interface BundledRomEntry {
  fileName: string
  relativePath: string
}

const nativeApi = testNapi as RuntimeRomSourceNapi

const BUNDLED_ROM_SUBDIRS: string[] = [
  '', 'gba', 'nes', 'snes', 'gb_gbc', 'md', 'nds', 'misc', 'arcade'
]

function hasFileExtension(name: string): boolean {
  const dot = name.lastIndexOf('.')
  return dot > 0 && dot < name.length - 1
}

async function listBundledRomEntries(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<BundledRomEntry[] | undefined> {
  const result: BundledRomEntry[] = []
  for (let i = 0; i < BUNDLED_ROM_SUBDIRS.length; i += 1) {
    const subdir = BUNDLED_ROM_SUBDIRS[i]
    const dir = subdir.length > 0 ? `roms/${subdir}` : 'roms'
    let rawList: string[] = []
    try {
      rawList = await nativeApi.refactoredGetRawFileListAsync(context.resourceManager, dir)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRomSourceScanner', 'Scan', `扫描子目录失败 ${dir}: ${message}`)
      continue
    }
    if (!shouldContinue()) {
      return undefined
    }
    let added = 0
    rawList.filter((item: string) => item.length > 0 && hasFileExtension(item)).forEach((fileName: string) => {
      const entry: BundledRomEntry = {
        fileName: fileName,
        relativePath: subdir.length > 0 ? `${subdir}/${fileName}` : fileName
      }
      result.push(entry)
      added += 1
    })
    LogHelper.info('RuntimeRomSourceScanner', 'Scan', `${dir}: 发现 ${added} 个 ROM (原始返回 ${rawList.length})`)
  }
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
    sources.push({
      fileName: fileName,
      launchPath: `${context.filesDir}/roms/${fileName}`
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
    sources.push({
      fileName: fileName,
      romFile: `${context.filesDir}/roms/${fileName}`,
      sourceType: 'IMPORTED'
    })
  })
  return sources
}
