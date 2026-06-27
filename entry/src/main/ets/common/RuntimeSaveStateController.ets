import { common } from '@kit.AbilityKit'
import LogHelper from './LogHelper'
import {
  deleteSaveStateItem,
  listSaveStateItems,
  readSaveStateData,
  SaveStateManifestItem,
  SaveStateManifestItemThumbnail,
  saveStateData
} from './SaveStateRepository'
import { runtimeSessionController, RuntimeSaveStateBundle } from './RuntimeSessionController'

export interface RuntimeSaveStateListItem {
  id: string
  fileName: string
  slotLabel: string
  detail: string
  createdLabel: string
  isLatest: boolean
}

export interface RuntimeSaveStateTaskOptions {
  shouldCancel?: () => boolean
}

export class RuntimeSaveStateController {
  async quickSave(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string,
    options?: RuntimeSaveStateTaskOptions
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中存档'
    }
    if (!context) {
      return '当前页还没准备好，暂时不能存档'
    }
    try {
      const bundle = await runtimeSessionController.saveStateBundleAsync()
      if (!bundle.stateData || bundle.stateData.byteLength <= 0) {
        return '存档数据不可用'
      }
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      await saveStateData(context, bundle.stateData, romFile, {
        thumbnail: buildThumbnailPayload(bundle),
        shouldCancel: options?.shouldCancel
      })
      LogHelper.info(
        'RuntimeSaveState',
        'Save',
        `运行态即时存档已写入: rom=${LogHelper.describePathForLog(romFile)} bytes=${bundle.stateData.byteLength} thumb=${bundle.thumbnailWidth}x${bundle.thumbnailHeight}`
      )
      return '存档文件已写入'
    } catch (err) {
      const message = (err as Error).message || String(err)
      if (message === 'SAVE_STATE_CANCELED') {
        return '存档操作已取消'
      }
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时存档失败: ${message}`)
      return '存档失败'
    }
  }

  async quickLoad(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string,
    options?: RuntimeSaveStateTaskOptions
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中读档'
    }
    if (!context) {
      return '当前页还没准备好，暂时不能读档'
    }
    try {
      const entries = await listSaveStateItems(context)
      const item = findLatestSaveForRuntimeRom(entries, romFile)
      if (!item) {
        return '当前游戏还没有可读取的存档'
      }
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      const stateData = readSaveStateData(context, item.fileName)
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      // Use async version to avoid blocking main thread on load deserialization
      const loaded = await runtimeSessionController.loadStateAsync(stateData)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态即时读档: file=${LogHelper.describePathForLog(item.fileName)} ok=${loaded}`)
      return loaded ? '读档已加载' : '读档被拒绝'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时读档失败: ${message}`)
      return '读档失败'
    }
  }

  async listSaveItemsForRom(
    context: common.UIAbilityContext | undefined,
    romFile: string
  ): Promise<RuntimeSaveStateListItem[]> {
    if (!context) {
      throw new Error('runtime save state context missing')
    }
    const entries = await listSaveStateItems(context)
    const filtered = filterSaveItemsForRuntimeRom(entries, romFile)
    const items: RuntimeSaveStateListItem[] = []
    filtered.forEach((item: SaveStateManifestItem, index: number) => {
      items.push(buildRuntimeSaveStateListItem(item, index))
    })
    return items
  }

  async loadSaveByFileName(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    fileName: string,
    options?: RuntimeSaveStateTaskOptions
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中读档'
    }
    if (!context) {
      return '当前页还没准备好，暂时不能读档'
    }
    if (fileName.length === 0) {
      return '存档文件无效'
    }
    try {
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      const stateData = readSaveStateData(context, fileName)
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      const loaded = await runtimeSessionController.loadStateAsync(stateData)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态指定读档: file=${LogHelper.describePathForLog(fileName)} ok=${loaded}`)
      return loaded ? '读档已加载' : '读档被拒绝'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态指定读档失败: ${message}`)
      return '读档失败'
    }
  }

  async deleteSaveByFileName(
    context: common.UIAbilityContext | undefined,
    fileName: string,
    options?: RuntimeSaveStateTaskOptions
  ): Promise<string> {
    if (!context) {
      return '当前页还没准备好，暂时不能删除存档'
    }
    if (fileName.length === 0) {
      return '存档文件无效'
    }
    try {
      if (options?.shouldCancel?.()) {
        return '存档操作已取消'
      }
      await deleteSaveStateItem(context, fileName)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态删除存档: file=${LogHelper.describePathForLog(fileName)}`)
      return '存档文件已删除'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态删除存档失败: ${message}`)
      return '删除存档失败'
    }
  }
}

function findLatestSaveForRuntimeRom(
  items: SaveStateManifestItem[],
  romFile: string
): SaveStateManifestItem | undefined {
  if (romFile.length === 0) {
    return items.length > 0 ? items[0] : undefined
  }
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index]
    if (item.romFile === romFile) {
      return item
    }
  }
  return undefined
}

function filterSaveItemsForRuntimeRom(
  items: SaveStateManifestItem[],
  romFile: string
): SaveStateManifestItem[] {
  if (romFile.length === 0) {
    return items
  }
  const filtered: SaveStateManifestItem[] = []
  items.forEach((item: SaveStateManifestItem) => {
    if (item.romFile === romFile) {
      filtered.push(item)
    }
  })
  return filtered
}

function buildRuntimeSaveStateListItem(
  item: SaveStateManifestItem,
  index: number
): RuntimeSaveStateListItem {
  const slotNumber = (index + 1).toString().padStart(3, '0')
  return {
    id: item.id,
    fileName: item.fileName,
    slotLabel: `存档 ${slotNumber}`,
    detail: `${normalizeRuntimeSaveTitle(item.fileName)} | ${formatRuntimeSaveBytes(item.byteLength)}`,
    createdLabel: item.createdAt > 0 ? formatRuntimeSaveDateTime(item.createdAt) : '本地',
    isLatest: index === 0
  }
}

function normalizeRuntimeSaveTitle(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
  const cleaned = baseName.replace(/[_-]+/g, ' ')
  return cleaned.length > 0 ? cleaned : '未知存档'
}

function formatRuntimeSaveBytes(byteLength: number): string {
  if (byteLength <= 0) {
    return '0 B'
  }
  if (byteLength < 1024) {
    return `${byteLength} B`
  }
  return `${Math.floor(byteLength / 1024)} KB`
}

function formatRuntimeSaveDateTime(timestamp: number): string {
  const date = new Date(timestamp)
  const month = `${date.getMonth() + 1}`.padStart(2, '0')
  const day = `${date.getDate()}`.padStart(2, '0')
  const hour = `${date.getHours()}`.padStart(2, '0')
  const minute = `${date.getMinutes()}`.padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`
}

function buildThumbnailPayload(
  bundle: RuntimeSaveStateBundle
): SaveStateManifestItemThumbnail | undefined {
  if (!bundle.thumbnailRgba || bundle.thumbnailWidth <= 0 || bundle.thumbnailHeight <= 0) {
    return undefined
  }
  return {
    rgba: bundle.thumbnailRgba,
    width: bundle.thumbnailWidth,
    height: bundle.thumbnailHeight
  }
}
