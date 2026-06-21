import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeCoreDiagnosticNapi {
  testCoreLoader(path: string): Promise<string>
  refactoredGetState(): number
  refactoredHasCoreLoaded(): boolean
  refactoredHasGameLoaded(): boolean
  refactoredGetSaveStateSizeAsync(): Promise<number>
  refactoredGetInputDebugStats(): RuntimeInputDebugStats
}

export interface RuntimeCoreCapabilities {
  supportsReset: boolean
  supportsRegion: boolean
  supportsCheatReset: boolean
  supportsCheatSet: boolean
  report: string
}

export interface RuntimeInputDebugStats {
  touchCount: number
  mouseCount: number
  keyCount: number
  hasFocus: boolean
  mouseDown: boolean
  lastTouchType: number
  lastMouseAction: number
  lastKeyAction: number
}

export interface RuntimeStatusSnapshot {
  state: number
  coreLoaded: boolean
  gameLoaded: boolean
  saveStateSizeBytes: number
  inputDebugStats: RuntimeInputDebugStats
}

const nativeApi = testNapi as RuntimeCoreDiagnosticNapi

export class RuntimeCoreDiagnosticController {
  private capabilityCache: Map<string, RuntimeCoreCapabilities> = new Map()

  async testCoreLoader(path: string): Promise<string> {
    if (!testNapi) {
      return 'Error: engine not ready'
    }
    try {
      return await nativeApi.testCoreLoader(path)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Core', `核心符号探测失败: ${message}`)
      return `Error: ${message}`
    }
  }

  async inspectCoreCapabilities(
    path: string,
    forceRefresh: boolean = false
  ): Promise<RuntimeCoreCapabilities> {
    const cached = this.capabilityCache.get(path)
    if (!forceRefresh && cached) {
      return cached
    }

    const report = await this.testCoreLoader(path)
    const capabilities = this.parseCapabilities(report)
    this.capabilityCache.set(path, capabilities)
    return capabilities
  }

  async readRuntimeStatusSnapshot(): Promise<RuntimeStatusSnapshot> {
    if (!testNapi) {
      return buildDefaultRuntimeStatusSnapshot()
    }
    try {
      const stateValue = Number(nativeApi.refactoredGetState())
      const saveStateSizeValue = Number(await nativeApi.refactoredGetSaveStateSizeAsync())
      return {
        state: Number.isFinite(stateValue) ? stateValue : 0,
        coreLoaded: Boolean(nativeApi.refactoredHasCoreLoaded()),
        gameLoaded: Boolean(nativeApi.refactoredHasGameLoaded()),
        saveStateSizeBytes: Number.isFinite(saveStateSizeValue) && saveStateSizeValue > 0
          ? Math.round(saveStateSizeValue)
          : 0,
        inputDebugStats: normalizeRuntimeInputDebugStats(nativeApi.refactoredGetInputDebugStats())
      }
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Runtime', `读取运行态快照失败: ${message}`)
      return buildDefaultRuntimeStatusSnapshot()
    }
  }

  private parseCapabilities(report: string): RuntimeCoreCapabilities {
    const normalized = report.toLowerCase()
    const failed = normalized.indexOf('failed:') >= 0 || normalized.indexOf('error:') >= 0

    return {
      supportsReset: !failed && normalized.indexOf('retro_reset missing') < 0,
      supportsRegion: !failed && normalized.indexOf('retro_get_region not provided') < 0,
      supportsCheatReset: !failed && normalized.indexOf('retro_cheat_reset not provided') < 0,
      supportsCheatSet: !failed && normalized.indexOf('retro_cheat_set not provided') < 0,
      report
    }
  }
}

function buildDefaultRuntimeStatusSnapshot(): RuntimeStatusSnapshot {
  return {
    state: 0,
    coreLoaded: false,
    gameLoaded: false,
    saveStateSizeBytes: 0,
    inputDebugStats: createDefaultRuntimeInputDebugStats()
  }
}

function createDefaultRuntimeInputDebugStats(): RuntimeInputDebugStats {
  return {
    touchCount: 0,
    mouseCount: 0,
    keyCount: 0,
    hasFocus: false,
    mouseDown: false,
    lastTouchType: -1,
    lastMouseAction: -1,
    lastKeyAction: -1
  }
}

function normalizeRuntimeInputDebugStats(
  value: RuntimeInputDebugStats | undefined
): RuntimeInputDebugStats {
  const fallback = createDefaultRuntimeInputDebugStats()
  if (!value) {
    return fallback
  }
  return {
    touchCount: normalizeRuntimeDebugNumber(value.touchCount, 0),
    mouseCount: normalizeRuntimeDebugNumber(value.mouseCount, 0),
    keyCount: normalizeRuntimeDebugNumber(value.keyCount, 0),
    hasFocus: Boolean(value.hasFocus),
    mouseDown: Boolean(value.mouseDown),
    lastTouchType: normalizeRuntimeDebugNumber(value.lastTouchType, -1),
    lastMouseAction: normalizeRuntimeDebugNumber(value.lastMouseAction, -1),
    lastKeyAction: normalizeRuntimeDebugNumber(value.lastKeyAction, -1)
  }
}

function normalizeRuntimeDebugNumber(value: number, fallback: number): number {
  const normalized = Number(value)
  return Number.isFinite(normalized) ? Math.round(normalized) : fallback
}

export const runtimeCoreDiagnosticController: RuntimeCoreDiagnosticController =
  new RuntimeCoreDiagnosticController()
