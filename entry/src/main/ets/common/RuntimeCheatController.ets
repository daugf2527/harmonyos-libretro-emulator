import testNapi from 'libentry.so'
import LogHelper from './LogHelper'
import { RuntimeCheatItem } from './RuntimeCheatRepository'

interface RuntimeCheatNapi {
  refactoredCheatReset(): boolean
  refactoredCheatSet(index: number, enabled: boolean, code: string): boolean
}

const nativeApi = testNapi as RuntimeCheatNapi

export class RuntimeCheatController {
  resetAll(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeCheat', 'Engine', '金手指重置跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredCheatReset() === true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCheat', 'Engine', `金手指重置失败: ${message}`)
      return false
    }
  }

  setCheat(index: number, enabled: boolean, code: string): boolean {
    const safeCode = typeof code === 'string' ? code.trim() : ''
    if (safeCode.length === 0) {
      LogHelper.warn('RuntimeCheat', 'Engine', '金手指代码为空，跳过写入')
      return false
    }

    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeCheat', 'Engine', '金手指写入跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredCheatSet(
        this.normalizeIndex(index),
        enabled,
        safeCode
      ) === true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCheat', 'Engine', `金手指写入失败: ${message}`)
      return false
    }
  }

  applyCheatEntries(items: RuntimeCheatItem[]): boolean {
    if (!this.resetAll()) {
      return false
    }

    for (let index = 0; index < items.length; index++) {
      const item = items[index]
      if (!this.setCheat(index, item.enabled, item.code)) {
        LogHelper.warn(
          'RuntimeCheat',
          'Engine',
          `金手指同步中断: index=${index} label=${item.label}`
        )
        return false
      }
    }

    LogHelper.info('RuntimeCheat', 'Engine', `已同步 ${items.length} 条金手指`)
    return true
  }

  private normalizeIndex(index: number): number {
    if (!Number.isFinite(index) || index < 0) {
      return 0
    }
    return Math.floor(index)
  }
}

export const runtimeCheatController: RuntimeCheatController =
  new RuntimeCheatController()
