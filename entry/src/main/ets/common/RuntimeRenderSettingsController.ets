import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeRenderSettingsNapi {
  refactoredResetStats(): boolean
  refactoredSetScalingMode(mode: number): boolean
  refactoredSetSwapInterval(interval: number): boolean
  refactoredSetSoftwareMaxResolution(width: number, height: number): boolean
  refactoredSetAIUpscale(enabled: boolean): boolean
  refactoredSetHwRenderAllowed(allowed: boolean): boolean
}

const nativeApi = testNapi as RuntimeRenderSettingsNapi

export class RuntimeRenderSettingsController {
  resetStats(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '重置统计跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredResetStats()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `重置统计失败: ${message}`)
      return false
    }
  }

  setScalingMode(mode: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '设置缩放模式跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetScalingMode(mode)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `设置缩放模式失败: ${message}`)
      return false
    }
  }

  setSwapInterval(interval: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '设置 VSync 跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetSwapInterval(interval)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `设置 VSync 失败: ${message}`)
      return false
    }
  }

  setSoftwareMaxResolution(width: number, height: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '设置软件分辨率跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetSoftwareMaxResolution(width, height)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `设置软件分辨率失败: ${message}`)
      return false
    }
  }

  setAIUpscale(enabled: boolean): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '设置 AI 超分跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetAIUpscale(enabled)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `设置 AI 超分失败: ${message}`)
      return false
    }
  }

  setHwRenderAllowed(allowed: boolean): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeRenderSettings', 'Render', '设置硬件渲染开关跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetHwRenderAllowed(allowed)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeRenderSettings', 'Render', `设置硬件渲染开关失败: ${message}`)
      return false
    }
  }
}

export const runtimeRenderSettingsController: RuntimeRenderSettingsController =
  new RuntimeRenderSettingsController()
