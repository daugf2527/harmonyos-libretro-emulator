import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

export interface RuntimeStatsPayload {
  videoNullFrames: number | string
  videoDupeFrames: number | string
  audioUnderruns: number | string
  audioOverruns: number | string
  audioBufferUsage: number | string
}

export interface RuntimeSoakStatsReader {
  refactoredResetStats(): boolean
  refactoredGetStats(): RuntimeStatsPayload
}

export interface RuntimeSoakState {
  running: boolean
  secondsLeft: number
  summaryText: string
}

interface RuntimeSoakStartStats {
  videoNullFrames: number
  videoDupeFrames: number
  audioUnderruns: number
  audioOverruns: number
}

const nativeApi = testNapi as RuntimeSoakStatsReader

export class RuntimeSoakTestController {
  private readonly reader: RuntimeSoakStatsReader
  private timer: number = -1
  private running: boolean = false
  private secondsLeft: number = 0
  private summaryText: string = ''
  private startStats: RuntimeSoakStartStats | undefined = undefined
  private minAudioUsage: number = 1.0
  private maxAudioUsage: number = 0.0

  constructor() {
    this.reader = nativeApi
  }

  start(
    durationSeconds: number,
    gameRunning: boolean,
    onChange: (state: RuntimeSoakState) => void
  ): void {
    if (this.running) {
      return
    }
    if (!gameRunning) {
      this.summaryText = '请先启动游戏'
      onChange(this.createState())
      return
    }

    if (!testNapi) {
      this.summaryText = '运行时未就绪'
      onChange(this.createState())
      return
    }

    try {
      if (!this.reader.refactoredResetStats()) {
        this.summaryText = 'resetStats 失败'
        onChange(this.createState())
        return
      }
      this.startStats = readStartStats(this.reader.refactoredGetStats())
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSoakTest', 'Stats', `启动 soak test 失败: ${message}`)
      this.running = false
      this.secondsLeft = 0
      this.summaryText = '获取初始 Stats 失败'
      onChange(this.createState())
      return
    }

    this.running = true
    this.secondsLeft = durationSeconds
    this.summaryText = ''
    this.minAudioUsage = 1.0
    this.maxAudioUsage = 0.0
    onChange(this.createState())

    this.clearTimer()
    this.timer = setInterval(() => {
      this.tick(onChange)
    }, 1000)
  }

  stop(onChange?: (state: RuntimeSoakState) => void): void {
    this.clearTimer()
    this.running = false
    this.secondsLeft = 0
    if (onChange) {
      onChange(this.createState())
    }
  }

  clearSummary(onChange: (state: RuntimeSoakState) => void): void {
    this.summaryText = ''
    onChange(this.createState())
  }

  private tick(onChange: (state: RuntimeSoakState) => void): void {
    this.secondsLeft -= 1
    try {
      const usage = Number(this.reader.refactoredGetStats().audioBufferUsage)
      if (usage > 0) {
        this.minAudioUsage = Math.min(this.minAudioUsage, usage)
        this.maxAudioUsage = Math.max(this.maxAudioUsage, usage)
      }
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSoakTest', 'Stats', `轮询运行统计失败: ${message}`)
    }

    if (this.secondsLeft <= 0) {
      this.finish(onChange)
      return
    }
    onChange(this.createState())
  }

  private finish(onChange: (state: RuntimeSoakState) => void): void {
    this.clearTimer()
    this.running = false
    this.secondsLeft = 0
    try {
      const end = this.reader.refactoredGetStats()
      const start = this.startStats
      if (!start) {
        onChange(this.createState())
        return
      }

      const dNull = Number(end.videoNullFrames) - start.videoNullFrames
      const dDupe = Number(end.videoDupeFrames) - start.videoDupeFrames
      const dUnder = Number(end.audioUnderruns) - start.audioUnderruns
      const dOver = Number(end.audioOverruns) - start.audioOverruns
      this.summaryText =
        `Null:${dNull} Dupe:${dDupe} U:${dUnder} O:${dOver} ` +
        `Buf:[${this.minAudioUsage.toFixed(2)}-${this.maxAudioUsage.toFixed(2)}]`
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeSoakTest', 'Stats', `生成 soak test 摘要失败: ${message}`)
      this.summaryText = '统计失败'
    }
    onChange(this.createState())
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private createState(): RuntimeSoakState {
    return {
      running: this.running,
      secondsLeft: this.secondsLeft,
      summaryText: this.summaryText
    }
  }
}

function readStartStats(stats: RuntimeStatsPayload): RuntimeSoakStartStats {
  return {
    videoNullFrames: Number(stats.videoNullFrames),
    videoDupeFrames: Number(stats.videoDupeFrames),
    audioUnderruns: Number(stats.audioUnderruns),
    audioOverruns: Number(stats.audioOverruns)
  }
}
