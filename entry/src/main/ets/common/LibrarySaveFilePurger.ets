import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'
import {
  ERR_CODE_ENOENT,
  ERR_CODE_ENOENT_NUM,
  ErrorWithCode,
  listSaveStateItems,
  pruneManifestForFileNames,
  SaveStateManifestItem
} from './SaveStateRepository'

export interface LibrarySavePurgeResult {
  deletedCount: number
  cancelled: boolean
}

export async function purgeSaveFilesForBaseName(
  context: common.UIAbilityContext,
  baseName: string,
  shouldContinue: () => boolean
): Promise<LibrarySavePurgeResult> {
  // T8-C-F3+F7: 基于 manifest.items[].romFile 过滤,替代旧的"按文件名前缀匹配"逻辑。
  // 旧实现按存档文件名 (state_<timestamp>.state) 前缀匹配 ROM 名,永远 0 命中,
  // 且即便命中也不更新 manifest,导致 SaveStatePage 仍显示已删存档。
  const normalizedBaseName = normalizeContentKey(baseName)
  if (normalizedBaseName.length === 0) {
    return { deletedCount: 0, cancelled: false }
  }
  if (!shouldContinue()) {
    return { deletedCount: 0, cancelled: true }
  }
  const items = await listSaveStateItems(context)
  const candidates = items.filter((item: SaveStateManifestItem) => matchesBaseName(item.romFile, normalizedBaseName))
  if (candidates.length === 0) {
    return { deletedCount: 0, cancelled: false }
  }
  const saveDir = `${context.filesDir}/saves`
  const removedFileNames: string[] = []
  for (let index = 0; index < candidates.length; index += 1) {
    if (!shouldContinue()) {
      // 已删的必须同步 manifest,否则磁盘与 manifest 不一致
      await pruneManifestForFileNames(context, removedFileNames)
      return { deletedCount: removedFileNames.length, cancelled: true }
    }
    const targetName = candidates[index].fileName
    try {
      await fs.unlink(`${saveDir}/${targetName}`)
      removedFileNames.push(targetName)
    } catch (err) {
      const errno = (err as ErrorWithCode).code
      if (errno === ERR_CODE_ENOENT || errno === ERR_CODE_ENOENT_NUM) {
        // 文件已不存在,继续清理 manifest 中的孤立记录
        removedFileNames.push(targetName)
        continue
      }
      // 非 ENOENT 错误: 把已删的 manifest 同步,再抛
      await pruneManifestForFileNames(context, removedFileNames)
      const message = (err as Error).message || String(err)
      LogHelper.error('LibrarySaveFilePurger', 'Purge', `删除存档失败 (code=${errno}): ${message}`)
      throw err as Error
    }
  }
  await pruneManifestForFileNames(context, removedFileNames)
  if (!shouldContinue()) {
    return { deletedCount: removedFileNames.length, cancelled: true }
  }
  return { deletedCount: removedFileNames.length, cancelled: false }
}

function matchesBaseName(romFile: string, normalizedBaseName: string): boolean {
  // T8-C-F7: manifest.romFile 可能为 "Super Mario Bros.nes" 或 "roms/Super Mario Bros.nes",
  // baseName 可能为 "Super Mario Bros.nes" (LibraryPage) 或 "Super Mario Bros" (LibraryDetailPage 经 cleanLibraryFileName).
  // 提取 basename + 去扩展名后 normalize 比较, 避免:
  //   - indexOf === 0 永远 false (因为路径前缀如 "roms" 把 ROM 名顶到中间)
  //   - includes 太宽松 ("Mario" 会误删 "Super Mario Bros")
  const romStem = extractRomStem(romFile)
  return romStem.length > 0 && normalizeContentKey(romStem) === normalizedBaseName
}

function extractRomStem(romFile: string): string {
  // 取 basename
  const slashIdx = Math.max(romFile.lastIndexOf('/'), romFile.lastIndexOf('\\'))
  const fileNameOnly = slashIdx >= 0 ? romFile.substring(slashIdx + 1) : romFile
  // 去扩展名
  const dotIdx = fileNameOnly.lastIndexOf('.')
  return dotIdx > 0 ? fileNameOnly.substring(0, dotIdx) : fileNameOnly
}

function normalizeContentKey(value: string): string {
  // T8-C-F7: normalize 前先去扩展名, 否则 ".nes" / ".gba" 会污染对比.
  return extractRomStem(value).toLowerCase().replace(/[^a-z0-9]+/g, '')
}
