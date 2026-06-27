import { common } from '@kit.AbilityKit'
import { LibraryRomFileSource } from './LibraryRecordFactory'
import {
  buildImportedRomFilePath,
  listSandboxRomFiles
} from './RomImportService'
import { RuntimeRomSourceItem } from './RuntimeRomCatalog'

export async function scanRuntimeRomSources(
  context: common.UIAbilityContext,
  shouldContinue: () => boolean
): Promise<RuntimeRomSourceItem[] | undefined> {
  const sources: RuntimeRomSourceItem[] = []
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
