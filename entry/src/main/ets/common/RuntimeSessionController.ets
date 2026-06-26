import testNapi from 'libentry.so'
import { resourceManager } from '@kit.LocalizationKit'
import LogHelper from './LogHelper'
import { EngineErrorInfo } from './LibretroEventHub'
import { EngineErrorCodes, NapiErrorResult } from './ErrorCodes'

export type SwitchProgressCallback = (progress: number, message: string) => void

export interface RuntimeAVInfo {
  videoWidth: number
  videoHeight: number
  fps: number
  audioSampleRate: number
}

export interface RuntimePerformanceStats {
  videoRefreshCalls: number
  videoNullFrames: number
  videoDupeFrames: number
  videoDroppedFrames: number
  audioBatchCalls: number
  audioFramesIn: number
  frameCount: number
  frameTimeMin: number
  frameTimeMax: number
  frameTimeSum: number
  queueDepthMax: number
  renderThreadDroppedFrames: number
  renderThreadRenderedFrames: number
  vsyncCallbacks: number
  vsyncFallbackTicks: number
  vsyncRequestFailures: number
  audioBufferUsage: number
  audioUnderruns: number
  audioOverruns: number
}

export interface RuntimeSaveStateBundle {
  stateData: ArrayBuffer
  thumbnailRgba: ArrayBuffer | null
  thumbnailWidth: number
  thumbnailHeight: number
}

interface RuntimeSessionNapi {
  refactoredStopEngineAsync(): Promise<boolean>
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    resMgr: resourceManager.ResourceManager,
    timeoutMs: number,
    token?: number,
    progressCallback?: SwitchProgressCallback
  ): Promise<NapiErrorResult>
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    timeoutMs: number,
    token?: number,
    progressCallback?: SwitchProgressCallback
  ): Promise<NapiErrorResult>
  refactoredCancelSwitch(): boolean
  refactoredPauseEngine(): boolean
  refactoredResumeEngine(): boolean
  refactoredSaveState(): ArrayBuffer | null
  refactoredLoadState(data: ArrayBuffer): boolean
  refactoredSaveStateAsync(): Promise<ArrayBuffer>
  refactoredSaveStateBundleAsync(): Promise<RuntimeSaveStateBundle>
  refactoredLoadStateAsync(data: ArrayBuffer): Promise<boolean>
  refactoredGetLastErrorInfo(): EngineErrorInfo
  refactoredClearLastErrorInfo(): boolean
  refactoredGetStats(): RuntimePerformanceStats
  refactoredGetAVInfo(): RuntimeAVInfo
}

export interface RuntimeSwitchRequest {
  corePath: string
  romPath: string
  filesDir: string
  timeoutMs: number
  token: number
  resourceManager?: resourceManager.ResourceManager
  progressCallback?: SwitchProgressCallback
}

const nativeApi = testNapi as RuntimeSessionNapi

function createDefaultRuntimePerformanceStats(): RuntimePerformanceStats {
  return {
    videoRefreshCalls: 0,
    videoNullFrames: 0,
    videoDupeFrames: 0,
    videoDroppedFrames: 0,
    audioBatchCalls: 0,
    audioFramesIn: 0,
    frameCount: 0,
    frameTimeMin: 0,
    frameTimeMax: 0,
    frameTimeSum: 0,
    queueDepthMax: 0,
    renderThreadDroppedFrames: 0,
    renderThreadRenderedFrames: 0,
    vsyncCallbacks: 0,
    vsyncFallbackTicks: 0,
    vsyncRequestFailures: 0,
    audioBufferUsage: 0,
    audioUnderruns: 0,
    audioOverruns: 0
  }
}

function createDefaultRuntimeAVInfo(): RuntimeAVInfo {
  return {
    videoWidth: 0,
    videoHeight: 0,
    fps: 0,
    audioSampleRate: 0
  }
}

function buildSessionErrorResult(
  errorCode: number,
  message: string
): NapiErrorResult {
  return {
    success: false,
    errorCode,
    message
  }
}

export class RuntimeSessionController {
  clearLastError(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Engine', '清理错误状态跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredClearLastErrorInfo()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `清理错误状态失败: ${message}`)
      return false
    }
  }

  saveState(): ArrayBuffer | null {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Save', '同步存档跳过: engine not ready')
        return null
      }
      return nativeApi.refactoredSaveState()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Save', `同步存档失败: ${message}`)
      return null
    }
  }

  loadState(data: ArrayBuffer): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Save', '同步读档跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredLoadState(data)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Save', `同步读档失败: ${message}`)
      return false
    }
  }

  // Async versions — offload heavy serialization/deserialization to
  // napi_async_work so the main thread is never blocked >500ms.
  async saveStateAsync(): Promise<ArrayBuffer> {
    if (!testNapi) {
      LogHelper.warn('RuntimeSession', 'Save', '异步存档跳过: engine not ready')
      throw new Error('engine not ready')
    }
    return nativeApi.refactoredSaveStateAsync()
  }

  async saveStateBundleAsync(): Promise<RuntimeSaveStateBundle> {
    if (!testNapi) {
      LogHelper.warn('RuntimeSession', 'Save', '异步存档包跳过: engine not ready')
      throw new Error('engine not ready')
    }
    return nativeApi.refactoredSaveStateBundleAsync()
  }

  async loadStateAsync(data: ArrayBuffer): Promise<boolean> {
    if (!testNapi) {
      LogHelper.warn('RuntimeSession', 'Save', '异步读档跳过: engine not ready')
      throw new Error('engine not ready')
    }
    return nativeApi.refactoredLoadStateAsync(data)
  }

  pause(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Engine', '暂停跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredPauseEngine()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `暂停失败: ${message}`)
      return false
    }
  }

  resume(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Engine', '恢复跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredResumeEngine()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `恢复失败: ${message}`)
      return false
    }
  }

  async stopAsync(): Promise<boolean> {
    if (!testNapi) {
      LogHelper.warn('RuntimeSession', 'Engine', '停止跳过: engine not ready')
      return false
    }
    try {
      return await nativeApi.refactoredStopEngineAsync()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `停止失败: ${message}`)
      return false
    }
  }

  async switchGame(request: RuntimeSwitchRequest): Promise<NapiErrorResult> {
    if (!testNapi) {
      LogHelper.warn('RuntimeSession', 'Engine', '切换游戏跳过: engine not ready')
      return buildSessionErrorResult(
        EngineErrorCodes.ENGINE_START_FAILED.numericCode,
        'engine not ready'
      )
    }
    try {
      if (request.resourceManager) {
        return await nativeApi.refactoredSwitchGameAsync(
          request.corePath,
          request.romPath,
          request.filesDir,
          request.resourceManager,
          request.timeoutMs,
          request.token,
          request.progressCallback
        )
      }
      return await nativeApi.refactoredSwitchGameAsync(
        request.corePath,
        request.romPath,
        request.filesDir,
        request.timeoutMs,
        request.token,
        request.progressCallback
      )
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `切换游戏失败: ${message}`)
      return buildSessionErrorResult(
        EngineErrorCodes.STATE_TRANSITION_FAILED.numericCode,
        message
      )
    }
  }

  cancelSwitch(): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeSession', 'Engine', '取消切换跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredCancelSwitch()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `取消切换失败: ${message}`)
      return false
    }
  }

  formatLastError(prefix: string): string {
    try {
      if (!testNapi) {
        return `${prefix} failed: engine_not_ready`
      }
      const err: EngineErrorInfo = nativeApi.refactoredGetLastErrorInfo()
      if (!err || !err.reason) {
        return `${prefix} failed: unknown_error`
      }
      const step = err.step ? ` step=${err.step}` : ''
      const message = err.message ? ` message=${err.message}` : ''
      return `${prefix} failed: reason=${err.reason}${step}${message}`
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `读取最近错误失败: ${message}`)
      return `${prefix} failed: last_error_unavailable`
    }
  }

  getStats(): RuntimePerformanceStats {
    try {
      if (!testNapi) {
        return createDefaultRuntimePerformanceStats()
      }
      return nativeApi.refactoredGetStats()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `读取运行时统计失败: ${message}`)
      return createDefaultRuntimePerformanceStats()
    }
  }

  getAVInfo(): RuntimeAVInfo {
    try {
      if (!testNapi) {
        return createDefaultRuntimeAVInfo()
      }
      return nativeApi.refactoredGetAVInfo()
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSession', 'Engine', `读取音视频信息失败: ${message}`)
      return createDefaultRuntimeAVInfo()
    }
  }
}

export const runtimeSessionController: RuntimeSessionController = new RuntimeSessionController()
