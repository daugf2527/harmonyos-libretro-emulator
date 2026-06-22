import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeCoreControlNapi {
  refactoredResetCore(): boolean
  refactoredResetCoreAsync(): Promise<boolean>
  refactoredGetRegion(): number
}

const nativeApi = testNapi as RuntimeCoreControlNapi

export class RuntimeCoreControlController {
  resetCore(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeCoreControl', 'Engine', '核心重置跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredResetCore() === true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreControl', 'Engine', `核心重置失败: ${message}`)
      return false
    }
  }

  async resetCoreAsync(): Promise<boolean> {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeCoreControl', 'Engine', '核心重置跳过: engine not ready')
        return false
      }
      return await nativeApi.refactoredResetCoreAsync()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreControl', 'Engine', `核心重置失败: ${message}`)
      return false
    }
  }

  getRegionCode(): number | undefined {
    try {
      if (!testNapi) {
        return undefined
      }
      const region = nativeApi.refactoredGetRegion()
      if (!Number.isFinite(region) || region < 0) {
        return undefined
      }
      const normalized = Math.floor(region)
      if (normalized !== 0 && normalized !== 1) {
        return undefined
      }
      return normalized
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreControl', 'Engine', `读取运行时区域失败: ${message}`)
      return undefined
    }
  }
}

export const runtimeCoreControlController: RuntimeCoreControlController =
  new RuntimeCoreControlController()
