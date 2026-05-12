import testNapi from 'libentry.so'

export interface RuntimeInputDebugPayload {
  touchCount: number
  mouseCount: number
  keyCount: number
  hasFocus: boolean
  mouseDown: boolean
  lastTouchType: number
  lastMouseAction: number
  lastKeyAction: number
}

export interface RuntimeInputDebugReader {
  refactoredGetInputDebugStats(): RuntimeInputDebugPayload
}

export interface RuntimeInputDebugTextState {
  inputDebugText: string
  inputFocusText: string
  uiInputDebugText: string
}

const nativeApi = testNapi as RuntimeInputDebugReader

export class RuntimeInputDebugTracker {
  private readonly reader: RuntimeInputDebugReader
  private timer: number = -1
  private uiTouchCount: number = 0
  private uiMouseCount: number = 0
  private uiKeyCount: number = 0
  private uiLastTouchType: number = -1
  private uiLastMouseAction: number = -1
  private uiLastKeyType: number = -1

  constructor() {
    this.reader = nativeApi
  }

  recordTouch(eventType: number): void {
    this.uiTouchCount += 1
    this.uiLastTouchType = eventType
  }

  recordMouse(action: number): void {
    this.uiMouseCount += 1
    this.uiLastMouseAction = action
  }

  recordKey(eventType: number): void {
    this.uiKeyCount += 1
    this.uiLastKeyType = eventType
  }

  start(onChange: (state: RuntimeInputDebugTextState) => void): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
    }
    onChange(this.readState())
    this.timer = setInterval(() => {
      onChange(this.readState())
    }, 500)
  }

  stop(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private readState(): RuntimeInputDebugTextState {
    try {
      const stats = this.reader.refactoredGetInputDebugStats()
      const touchCount = normalizeNumber(stats.touchCount, 0)
      const mouseCount = normalizeNumber(stats.mouseCount, 0)
      const keyCount = normalizeNumber(stats.keyCount, 0)
      const lastTouch = normalizeNumber(stats.lastTouchType, -1)
      const lastMouse = normalizeNumber(stats.lastMouseAction, -1)
      const lastKey = normalizeNumber(stats.lastKeyAction, -1)
      const hasFocus = Boolean(stats.hasFocus)
      const mouseDown = Boolean(stats.mouseDown)

      return {
        inputDebugText: `Touch:${touchCount}(${lastTouch}) Mouse:${mouseCount}(${lastMouse}) Key:${keyCount}(${lastKey})`,
        inputFocusText: `Focus:${hasFocus ? 'Y' : 'N'} MouseDown:${mouseDown ? 'Y' : 'N'}`,
        uiInputDebugText:
          `UI Touch:${this.uiTouchCount}(${this.uiLastTouchType}) ` +
          `Mouse:${this.uiMouseCount}(${this.uiLastMouseAction}) ` +
          `Key:${this.uiKeyCount}(${this.uiLastKeyType})`
      }
    } catch (_) {
      return {
        inputDebugText: '',
        inputFocusText: '',
        uiInputDebugText: ''
      }
    }
  }
}

function normalizeNumber(value: number, fallback: number): number {
  const normalized = Number(value)
  return Number.isFinite(normalized) ? normalized : fallback
}
