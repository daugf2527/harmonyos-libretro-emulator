import testNapi from 'libentry.so'
import { resourceManager } from '@kit.LocalizationKit'
import { EngineErrorInfo } from './LibretroEventHub'

interface RuntimeSessionNapi {
  refactoredStopEngineAsync(): boolean
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    resMgr: resourceManager.ResourceManager,
    timeoutMs: number,
    token?: number
  ): Promise<boolean>
  refactoredSwitchGameAsync(
    corePath: string,
    romPath: string,
    filesDir: string,
    timeoutMs: number,
    token?: number
  ): Promise<boolean>
  refactoredPauseEngine(): boolean
  refactoredResumeEngine(): boolean
  refactoredSaveState(): ArrayBuffer | null
  refactoredLoadState(data: ArrayBuffer): boolean
  refactoredGetLastErrorInfo(): EngineErrorInfo
  refactoredClearLastErrorInfo(): boolean
}

export interface RuntimeSwitchRequest {
  corePath: string
  romPath: string
  filesDir: string
  timeoutMs: number
  token: number
  resourceManager?: resourceManager.ResourceManager
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

  pause(): boolean {
    return nativeApi.refactoredPauseEngine()
  }

  resume(): boolean {
    return nativeApi.refactoredResumeEngine()
  }

  stopAsync(): boolean {
    return nativeApi.refactoredStopEngineAsync()
  }

  async switchGame(request: RuntimeSwitchRequest): Promise<boolean> {
    if (request.resourceManager) {
      return nativeApi.refactoredSwitchGameAsync(
        request.corePath,
        request.romPath,
        request.filesDir,
        request.resourceManager,
        request.timeoutMs,
        request.token
      )
    }
    return nativeApi.refactoredSwitchGameAsync(
      request.corePath,
      request.romPath,
      request.filesDir,
      request.timeoutMs,
      request.token
    )
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
}

export const runtimeSessionController: RuntimeSessionController = new RuntimeSessionController()
