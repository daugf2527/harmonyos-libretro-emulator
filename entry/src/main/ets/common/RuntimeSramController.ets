import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import LogHelper from './LogHelper'
import {
  deleteRuntimeSramBackup,
  listRuntimeSramBackupsForRom,
  readRuntimeSramBackup,
  RuntimeSramBackupItem,
  saveRuntimeSramBackup
} from './RuntimeSramRepository'

export interface RuntimeSramBackupListItem {
  id: string
  fileName: string
  slotLabel: string
  detail: string
  createdLabel: string
  isLatest: boolean
}

interface RuntimeSramNapi {
  refactoredGetSRAM(): ArrayBuffer | null
  refactoredSetSRAM(data: ArrayBuffer): boolean
  refactoredGetSRAMAsync(): Promise<ArrayBuffer | null>
  refactoredSetSRAMAsync(data: ArrayBuffer): Promise<boolean>
}

const nativeApi = testNapi as RuntimeSramNapi

export class RuntimeSramController {
  async exportCurrentSramBackup(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中导出电池存档'
    }
    if (!context) {
      return '上下文缺失'
    }
    if (romFile.trim().length === 0) {
      return 'ROM 上下文缺失'
    }

    try {
      const data = await this.getCurrentSramAsync()
      if (!data || data.byteLength <= 0) {
        return '当前核心未暴露 SRAM'
      }
      const saved = await saveRuntimeSramBackup(context, romFile, data)
      LogHelper.info(
        'RuntimeSram',
        'SRAM',
        `运行态 SRAM 备份已写入: rom=${LogHelper.describePathForLog(romFile)} file=${LogHelper.describePathForLog(saved.fileName)} bytes=${saved.byteLength}`
      )
      return '电池存档已导出'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSram', 'SRAM', `导出运行态 SRAM 失败: ${message}`)
      return '导出电池存档失败'
    }
  }

  async listBackupItemsForRom(
    context: common.UIAbilityContext | undefined,
    romFile: string
  ): Promise<RuntimeSramBackupListItem[]> {
    if (!context || romFile.trim().length === 0) {
      return []
    }
    const items = await listRuntimeSramBackupsForRom(context, romFile)
    const listItems: RuntimeSramBackupListItem[] = []
    items.forEach((item: RuntimeSramBackupItem, index: number) => {
      listItems.push(buildRuntimeSramBackupListItem(item, index))
    })
    return listItems
  }

  async loadBackupByFileName(
    context: common.UIAbilityContext | undefined,
    gameRunning: boolean,
    romFile: string,
    fileName: string
  ): Promise<string> {
    if (!gameRunning) {
      return '需在运行中载入电池存档'
    }
    if (!context) {
      return '上下文缺失'
    }
    if (romFile.trim().length === 0) {
      return 'ROM 上下文缺失'
    }
    if (fileName.trim().length === 0) {
      return '电池存档文件无效'
    }

    try {
      const data = await readRuntimeSramBackup(context, romFile, fileName)
      const applied = await this.setCurrentSramAsync(data)
      LogHelper.info('RuntimeSram', 'SRAM', `运行态 SRAM 载入: file=${LogHelper.describePathForLog(fileName)} ok=${applied}`)
      return applied ? '电池存档已载入' : '当前核心未接受 SRAM 写入'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSram', 'SRAM', `载入运行态 SRAM 失败: ${message}`)
      return '载入电池存档失败'
    }
  }

  async deleteBackupByFileName(
    context: common.UIAbilityContext | undefined,
    romFile: string,
    fileName: string
  ): Promise<string> {
    if (!context) {
      return '上下文缺失'
    }
    if (romFile.trim().length === 0) {
      return 'ROM 上下文缺失'
    }
    if (fileName.trim().length === 0) {
      return '电池存档文件无效'
    }

    try {
      await deleteRuntimeSramBackup(context, romFile, fileName)
      LogHelper.info('RuntimeSram', 'SRAM', `运行态 SRAM 备份已删除: file=${LogHelper.describePathForLog(fileName)}`)
      return '电池存档已删除'
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RuntimeSram', 'SRAM', `删除运行态 SRAM 备份失败: ${message}`)
      return '删除电池存档失败'
    }
  }

  private async getCurrentSramAsync(): Promise<ArrayBuffer | undefined> {
    try {
      if (!testNapi) {
        return undefined
      }
      const data = await nativeApi.refactoredGetSRAMAsync()
      if (!data || data.byteLength <= 0) {
        return undefined
      }
      return data
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSram', 'SRAM', `读取运行态 SRAM 失败: ${message}`)
      return undefined
    }
  }

  private async setCurrentSramAsync(data: ArrayBuffer): Promise<boolean> {
    if (!data || data.byteLength <= 0) {
      return false
    }
    try {
      if (!testNapi) {
        return false
      }
      return await nativeApi.refactoredSetSRAMAsync(data)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSram', 'SRAM', `写入运行态 SRAM 失败: ${message}`)
      return false
    }
  }
}

function buildRuntimeSramBackupListItem(
  item: RuntimeSramBackupItem,
  index: number
): RuntimeSramBackupListItem {
  const slotNumber = (index + 1).toString().padStart(3, '0')
  return {
    id: item.id,
    fileName: item.fileName,
    slotLabel: `电池位_${slotNumber}`,
    detail: `${normalizeRuntimeSramTitle(item.fileName)} | ${formatRuntimeSramBytes(item.byteLength)}`,
    createdLabel: item.createdAt > 0 ? formatRuntimeSramDateTime(item.createdAt) : '本地',
    isLatest: index === 0
  }
}

function normalizeRuntimeSramTitle(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
  const cleaned = baseName.replace(/[_-]+/g, ' ')
  return cleaned.length > 0 ? cleaned : '未知电池存档'
}

function formatRuntimeSramBytes(byteLength: number): string {
  if (byteLength <= 0) {
    return '0 B'
  }
  if (byteLength < 1024) {
    return `${byteLength} B`
  }
  return `${Math.floor(byteLength / 1024)} KB`
}

function formatRuntimeSramDateTime(timestamp: number): string {
  const date = new Date(timestamp)
  const month = `${date.getMonth() + 1}`.padStart(2, '0')
  const day = `${date.getDate()}`.padStart(2, '0')
  const hour = `${date.getHours()}`.padStart(2, '0')
  const minute = `${date.getMinutes()}`.padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`
}
