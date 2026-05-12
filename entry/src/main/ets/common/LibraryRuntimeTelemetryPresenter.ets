import { LibraryRecord } from './LibraryRepository'

export interface LibraryTelemetryCell {
  label: string
  value: string
}

export interface LibraryTelemetryBar {
  id: string
  height: number
  color: string
}

export function getLibraryTelemetryCells(records: LibraryRecord[]): LibraryTelemetryCell[] {
  const latest = getLatestRuntimeRecord(records)
  return [
    { label: 'SESSION', value: latest ? 'LAST RUN' : 'NO DATA' },
    { label: 'FPS', value: latest && latest.lastRuntimeFps > 0 ? latest.lastRuntimeFps.toFixed(1) : '--.-' },
    { label: 'AUDIO', value: latest ? formatTelemetryPercent(latest.lastRuntimeAudioBufferUsage) : '--' }
  ]
}

export function getLibraryTelemetryBars(records: LibraryRecord[]): LibraryTelemetryBar[] {
  const latest = getLatestRuntimeRecord(records)
  return [
    {
      id: 'fps',
      height: getRuntimeBarHeight(latest, 'fps'),
      color: latest ? '#8800FF41' : '#22484848'
    },
    {
      id: 'audio',
      height: getRuntimeBarHeight(latest, 'audio'),
      color: latest ? '#6600FF41' : '#22484848'
    },
    {
      id: 'drops',
      height: getRuntimeBarHeight(latest, 'drops'),
      color: latest ? '#4A00FF41' : '#22484848'
    },
    {
      id: 'underruns',
      height: getRuntimeBarHeight(latest, 'underruns'),
      color: latest ? '#3300FF41' : '#22484848'
    }
  ]
}

function getLatestRuntimeRecord(records: LibraryRecord[]): LibraryRecord | undefined {
  const runtimeRecords = records.filter((item: LibraryRecord) => {
    return item.lastRuntimeUpdatedAt > 0 || item.lastSessionDurationMs > 0
  })
  if (runtimeRecords.length === 0) {
    return undefined
  }
  runtimeRecords.sort((left: LibraryRecord, right: LibraryRecord) => {
    return right.lastRuntimeUpdatedAt - left.lastRuntimeUpdatedAt
  })
  return runtimeRecords[0]
}

function formatTelemetryPercent(value: number): string {
  const safeValue = Math.max(0, Number(value) || 0)
  const percent = safeValue <= 1 ? safeValue * 100 : safeValue
  return `${Math.round(percent)}%`
}

function getRuntimeBarHeight(record: LibraryRecord | undefined, key: string): number {
  if (!record) {
    return 4
  }
  if (key === 'fps') {
    return Math.max(4, Math.min(24, record.lastRuntimeFps / 60 * 24))
  }
  if (key === 'audio') {
    const value = record.lastRuntimeAudioBufferUsage <= 1 ?
      record.lastRuntimeAudioBufferUsage * 100 : record.lastRuntimeAudioBufferUsage
    return Math.max(4, Math.min(24, value / 100 * 24))
  }
  if (key === 'drops') {
    return Math.max(4, Math.min(24, record.lastRuntimeVideoDrops * 4))
  }
  return Math.max(4, Math.min(24, record.lastRuntimeAudioUnderruns * 4))
}
