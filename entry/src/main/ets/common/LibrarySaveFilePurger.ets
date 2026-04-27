import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface LibrarySavePurgeResult {
  deletedCount: number
  cancelled: boolean
}

export async function purgeSaveFilesForBaseName(
  context: common.UIAbilityContext,
  baseName: string,
  shouldContinue: () => boolean
): Promise<LibrarySavePurgeResult> {
  const saveDir = `${context.filesDir}/saves`
  const normalizedBaseName = normalizeContentKey(baseName)
  const entries = await fs.listFile(saveDir)
  if (!shouldContinue()) {
    return { deletedCount: 0, cancelled: true }
  }
  const candidates = entries.filter((item: string) => isSaveCandidate(item, normalizedBaseName))
  if (candidates.length === 0) {
    return { deletedCount: 0, cancelled: false }
  }
  for (let index = 0; index < candidates.length; index += 1) {
    if (!shouldContinue()) {
      return { deletedCount: index, cancelled: true }
    }
    await fs.unlink(`${saveDir}/${candidates[index]}`)
  }
  if (!shouldContinue()) {
    return { deletedCount: candidates.length, cancelled: true }
  }
  return { deletedCount: candidates.length, cancelled: false }
}

function isSaveCandidate(fileName: string, normalizedBaseName: string): boolean {
  const normalized = normalizeContentKey(fileName)
  return normalized.indexOf(normalizedBaseName) === 0
}

function normalizeContentKey(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '')
}
