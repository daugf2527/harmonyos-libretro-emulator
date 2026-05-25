import { common } from '@kit.AbilityKit'
import LogHelper from './LogHelper'
import {
  listSaveStateItems,
  readSaveStateData,
  SaveStateManifestItem,
  saveStateData
} from './SaveStateRepository'
import { runtimeSessionController } from './RuntimeSessionController'

export class RuntimeSaveStateController {
  async quickSave(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中存档'
    }
    if (!context) {
      return '上下文缺失'
    }
    try {
      // Use async version to avoid blocking main thread on save serialization
      const stateData = await runtimeSessionController.saveStateAsync()
      if (!stateData || stateData.byteLength <= 0) {
        return '存档数据不可用'
      }
      await saveStateData(context, stateData, romFile)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态即时存档已写入: rom=${romFile} bytes=${stateData.byteLength}`)
      return '存档已写入'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时存档失败: ${message}`)
      return '存档失败'
    }
  }

  async quickLoad(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中读档'
    }
    if (!context) {
      return '上下文缺失'
    }
    try {
      const entries = await listSaveStateItems(context)
      const item = findLatestSaveForRuntimeRom(entries, romFile)
      if (!item) {
        return '当前 ROM 暂无存档'
      }
      const stateData = readSaveStateData(context, item.fileName)
      // Use async version to avoid blocking main thread on load deserialization
      const loaded = await runtimeSessionController.loadStateAsync(stateData)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态即时读档: file=${item.fileName} ok=${loaded}`)
      return loaded ? '读档已加载' : '读档被拒绝'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时读档失败: ${message}`)
      return '读档失败'
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
