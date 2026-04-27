import { common } from '@kit.AbilityKit'
import LogHelper from './LogHelper'
import {
  LibraryRuntimeSnapshot,
  updateLibraryRuntimeSnapshot
} from './LibraryRepository'

export class RuntimeLibrarySessionTracker {
  private activeRomFileValue: string = ''
  private activeSessionStartedAtMs: number = 0
  private latestFps: number = 0
  private latestAudioBufferUsage: number = 0
  private latestAudioUnderruns: number = 0
  private latestAudioOverruns: number = 0
  private latestVideoDrops: number = 0
  private latestVideoDupes: number = 0
  private latestVideoNulls: number = 0

  get activeRomFile(): string {
    return this.activeRomFileValue
  }

  get audioBufferUsage(): number {
    return this.latestAudioBufferUsage
  }

  begin(romFile: string): void {
    this.activeRomFileValue = romFile
    this.activeSessionStartedAtMs = Date.now()
    this.resetSnapshot()
  }

  updateFrameStats(
    fps: number,
    drops: number,
    dupes: number,
    nulls: number,
    underruns: number,
    overruns: number,
    audioBufferUsage: number
  ): void {
    if (!Number.isNaN(fps)) {
      this.latestFps = fps
    }
    this.latestVideoDrops = drops
    this.latestVideoDupes = dupes
    this.latestVideoNulls = nulls
    this.latestAudioUnderruns = underruns
    this.latestAudioOverruns = overruns
    this.latestAudioBufferUsage = audioBufferUsage
  }

  updateAudioStatus(occupancy: number, underruns: number, overruns: number): void {
    this.latestAudioBufferUsage = occupancy
    this.latestAudioUnderruns = underruns
    this.latestAudioOverruns = Number(overruns) || this.latestAudioOverruns
  }

  async finalize(context: common.UIAbilityContext | undefined): Promise<void> {
    if (this.activeRomFileValue.length === 0 || this.activeSessionStartedAtMs <= 0) {
      return
    }
    const romFile = this.activeRomFileValue
    const startedAt = this.activeSessionStartedAtMs
    const snapshot = this.createSnapshot(startedAt)
    this.clearActiveSession()
    if (!context) {
      return
    }
    try {
      await updateLibraryRuntimeSnapshot(context, romFile, snapshot)
    } catch (e) {
      LogHelper.warn('LibretroGame', 'Library', `写入运行摘要失败: ${(e as Error).message}`)
    }
  }

  private createSnapshot(startedAt: number): LibraryRuntimeSnapshot {
    return {
      durationMs: Math.max(0, Date.now() - startedAt),
      fps: this.latestFps,
      audioBufferUsage: this.latestAudioBufferUsage,
      audioUnderruns: this.latestAudioUnderruns,
      audioOverruns: this.latestAudioOverruns,
      videoDrops: this.latestVideoDrops,
      videoDupes: this.latestVideoDupes,
      videoNulls: this.latestVideoNulls
    }
  }

  private clearActiveSession(): void {
    this.activeRomFileValue = ''
    this.activeSessionStartedAtMs = 0
  }

  private resetSnapshot(): void {
    this.latestFps = 0
    this.latestAudioBufferUsage = 0
    this.latestAudioUnderruns = 0
    this.latestAudioOverruns = 0
    this.latestVideoDrops = 0
    this.latestVideoDupes = 0
    this.latestVideoNulls = 0
  }
}
