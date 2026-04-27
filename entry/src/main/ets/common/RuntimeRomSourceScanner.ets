import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import { LibraryRomFileSource } from './LibraryRecordFactory'
import { listSandboxRomFiles } from './RomImportService'
import { RuntimeRomSourceItem } from './RuntimeRomCatalog'

interface RuntimeRomSourceNapi {
  refactoredGetRawFileListAsync(resMgr: object, dir?: string): Promise<string[]>
}

const nativeApi = testNapi as RuntimeRomSourceNapi

export async function scanRuntimeRomSources(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<RuntimeRomSourceItem[] | undefined> {
  const sources: RuntimeRomSourceItem[] = []
  const rawList: string[] = await nativeApi.refactoredGetRawFileListAsync(context.resourceManager, 'roms')
  if (!shouldContinue()) {
    return undefined
  }
  rawList.filter((item: string) => item.length > 0).forEach((fileName: string) => {
    sources.push({
      fileName: fileName,
      launchPath: `roms/${fileName}`
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
  const rawList: string[] = await nativeApi.refactoredGetRawFileListAsync(context.resourceManager, 'roms')
  if (!shouldContinue()) {
    return undefined
  }
  rawList.filter((item: string) => item.length > 0).forEach((fileName: string) => {
    sources.push({
      fileName: fileName,
      romFile: `roms/${fileName}`,
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
