import testNapi from 'libentry.so'
import { resourceManager } from '@kit.LocalizationKit'
import { EngineErrorInfo } from './LibretroEventHub'
import { NapiErrorResult } from './ErrorCodes'

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
  refactoredSaveStateAsync(): Promise<ArrayBuffer | null>
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

export class RuntimeSessionController {
  clearLastError(): boolean {
    return nativeApi.refactoredClearLastErrorInfo()
  }

  saveState(): ArrayBuffer | null {
    return nativeApi.refactoredSaveState()
  }

  loadState(data: ArrayBuffer): boolean {
    return nativeApi.refactoredLoadState(data)
  }

  // Async versions — offload heavy serialization/deserialization to
  // napi_async_work so the main thread is never blocked >500ms.
  async saveStateAsync(): Promise<ArrayBuffer | null> {
    return nativeApi.refactoredSaveStateAsync()
  }

  async saveStateBundleAsync(): Promise<RuntimeSaveStateBundle> {
    return nativeApi.refactoredSaveStateBundleAsync()
  }

  async loadStateAsync(data: ArrayBuffer): Promise<boolean> {
    return nativeApi.refactoredLoadStateAsync(data)
  }

  pause(): boolean {
    return nativeApi.refactoredPauseEngine()
  }

  resume(): boolean {
    return nativeApi.refactoredResumeEngine()
  }

  stopAsync(): Promise<boolean> {
    return nativeApi.refactoredStopEngineAsync()
  }

  async switchGame(request: RuntimeSwitchRequest): Promise<NapiErrorResult> {
    if (request.resourceManager) {
      return nativeApi.refactoredSwitchGameAsync(
        request.corePath,
        request.romPath,
        request.filesDir,
        request.resourceManager,
        request.timeoutMs,
        request.token,
        request.progressCallback
      )
    }
    return nativeApi.refactoredSwitchGameAsync(
      request.corePath,
      request.romPath,
      request.filesDir,
      request.timeoutMs,
      request.token,
      request.progressCallback
    )
  }

  cancelSwitch(): boolean {
    return nativeApi.refactoredCancelSwitch()
  }

  formatLastError(prefix: string): string {
    const err: EngineErrorInfo = nativeApi.refactoredGetLastErrorInfo()
    if (!err || !err.reason) {
      return `${prefix} failed: unknown_error`
    }
    const step = err.step ? ` step=${err.step}` : ''
    const message = err.message ? ` message=${err.message}` : ''
    return `${prefix} failed: reason=${err.reason}${step}${message}`
  }

  getStats(): RuntimePerformanceStats {
    return nativeApi.refactoredGetStats()
  }

  getAVInfo(): RuntimeAVInfo {
    return nativeApi.refactoredGetAVInfo()
  }
}

export const runtimeSessionController: RuntimeSessionController = new RuntimeSessionController()
