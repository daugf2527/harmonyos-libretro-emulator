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
      return 'SAVE_REQUIRES_RUNNING_GAME'
    }
    if (!context) {
      return 'CONTEXT_MISSING'
    }
    try {
      // Use async version to avoid blocking main thread on save serialization
      const stateData = await runtimeSessionController.saveStateAsync()
      if (!stateData || stateData.byteLength <= 0) {
        return 'SAVE_STATE_UNAVAILABLE'
      }
      await saveStateData(context, stateData, romFile)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态即时存档已写入: rom=${romFile} bytes=${stateData.byteLength}`)
      return 'SAVE_STATE_WRITTEN'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时存档失败: ${message}`)
      return 'SAVE_STATE_FAILED'
    }
  }

  async quickLoad(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string
  ): Promise<string> {
    if (!gameRunning) {
      return 'LOAD_REQUIRES_RUNNING_GAME'
    }
    if (!context) {
      return 'CONTEXT_MISSING'
    }
    try {
      const entries = await listSaveStateItems(context)
      const item = findLatestSaveForRuntimeRom(entries, romFile)
      if (!item) {
        return 'NO_SAVE_FOR_CURRENT_ROM'
      }
      const stateData = readSaveStateData(context, item.fileName)
      // Use async version to avoid blocking main thread on load deserialization
      const loaded = await runtimeSessionController.loadStateAsync(stateData)
      LogHelper.info('RuntimeSaveState', 'Save', `运行态即时读档: file=${item.fileName} ok=${loaded}`)
      return loaded ? 'SAVE_STATE_LOADED' : 'LOAD_STATE_REJECTED'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSaveState', 'Save', `运行态即时读档失败: ${message}`)
      return 'LOAD_STATE_FAILED'
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
