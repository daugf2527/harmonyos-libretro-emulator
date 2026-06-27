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
  isComplete: boolean
}

const nativeApi = testNapi as RuntimeCoreDiagnosticNapi

export interface RuntimeCoreDiagnosticTaskOptions {
  shouldCancel?: () => boolean
}

export class RuntimeCoreDiagnosticController {
  private capabilityCache: Map<string, RuntimeCoreCapabilities> = new Map()

  async testCoreLoader(path: string, options?: RuntimeCoreDiagnosticTaskOptions): Promise<string> {
    if (options?.shouldCancel?.()) {
      return '操作已取消'
    }
    if (!testNapi) {
      return '当前还没连上运行中的引擎'
    }
    try {
      const report = await nativeApi.testCoreLoader(path)
      if (options?.shouldCancel?.()) {
        return '操作已取消'
      }
      return report
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Core', `核心符号探测失败: ${message}`)
      return `探测失败：${message}`
    }
  }

  async inspectCoreCapabilities(
    path: string,
    forceRefresh: boolean = false,
    options?: RuntimeCoreDiagnosticTaskOptions
  ): Promise<RuntimeCoreCapabilities> {
    if (options?.shouldCancel?.()) {
      return buildCanceledRuntimeCoreCapabilities()
    }
    const cached = this.capabilityCache.get(path)
    if (!forceRefresh && cached) {
      return cached
    }

    const report = await this.testCoreLoader(path, options)
    if (options?.shouldCancel?.()) {
      return buildCanceledRuntimeCoreCapabilities()
    }
    const capabilities = this.parseCapabilities(report)
    this.capabilityCache.set(path, capabilities)
    return capabilities
  }

  async readRuntimeStatusSnapshot(
    options?: RuntimeCoreDiagnosticTaskOptions
  ): Promise<RuntimeStatusSnapshot> {
    if (options?.shouldCancel?.()) {
      return buildDefaultRuntimeStatusSnapshot()
    }
    if (!testNapi) {
      return buildDefaultRuntimeStatusSnapshot()
    }
    const snapshot = buildDefaultRuntimeStatusSnapshot()
    let baseSnapshotReady = false
    let saveStateSizeReady = false
    let inputDebugReady = false
    try {
      const stateValue = Number(nativeApi.refactoredGetState())
      snapshot.state = Number.isFinite(stateValue) ? stateValue : 0
      snapshot.coreLoaded = Boolean(nativeApi.refactoredHasCoreLoaded())
      snapshot.gameLoaded = Boolean(nativeApi.refactoredHasGameLoaded())
      baseSnapshotReady = true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Runtime', `读取运行态基础快照失败: ${message}`)
    }

    if (options?.shouldCancel?.()) {
      return buildDefaultRuntimeStatusSnapshot()
    }

    try {
      const saveStateSizeValue = Number(await nativeApi.refactoredGetSaveStateSizeAsync())
      if (options?.shouldCancel?.()) {
        return buildDefaultRuntimeStatusSnapshot()
      }
      snapshot.saveStateSizeBytes = Number.isFinite(saveStateSizeValue) && saveStateSizeValue > 0
        ? Math.round(saveStateSizeValue)
        : 0
      saveStateSizeReady = true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Runtime', `读取运行态存档大小失败: ${message}`)
    }

    if (options?.shouldCancel?.()) {
      return buildDefaultRuntimeStatusSnapshot()
    }

    try {
      snapshot.inputDebugStats = normalizeRuntimeInputDebugStats(nativeApi.refactoredGetInputDebugStats())
      inputDebugReady = true
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeCoreDiagnostic', 'Runtime', `读取运行态输入统计失败: ${message}`)
    }

    snapshot.isComplete = baseSnapshotReady && saveStateSizeReady && inputDebugReady
    return snapshot
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

function buildCanceledRuntimeCoreCapabilities(): RuntimeCoreCapabilities {
  return {
    supportsReset: false,
    supportsRegion: false,
    supportsCheatReset: false,
    supportsCheatSet: false,
    report: '操作已取消'
  }
}

function buildDefaultRuntimeStatusSnapshot(): RuntimeStatusSnapshot {
  return {
    state: 0,
    coreLoaded: false,
    gameLoaded: false,
    saveStateSizeBytes: 0,
    inputDebugStats: createDefaultRuntimeInputDebugStats(),
    isComplete: false
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
