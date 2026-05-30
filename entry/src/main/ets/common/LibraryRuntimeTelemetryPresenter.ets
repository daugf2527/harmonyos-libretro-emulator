import { LibraryRecord } from './LibraryRepository'

export interface LibraryTelemetryCell {
  label: string
  value: string
  progress: number
  progressColor: string
}

export interface LibraryTelemetryBar {
  id: string
  height: number
  color: string
}

export function getLibraryTelemetryCells(records: LibraryRecord[]): LibraryTelemetryCell[] {
  const latest = getLatestRuntimeRecord(records)
  const fps = latest ? latest.lastRuntimeFps : 0
  const audioPercent = latest ? toPercent(latest.lastRuntimeAudioBufferUsage) : 0
  return [
    {
      label: 'SESSION',
      value: latest ? 'LAST RUN' : 'NO DATA',
      progress: latest ? 100 : 4,
      progressColor: latest ? '#8800FF41' : '#22484848'
    },
    {
      label: 'FPS',
      value: fps > 0 ? fps.toFixed(1) : '--.-',
      progress: clampPercent((fps / 60) * 100),
      progressColor: fps > 0 ? '#8800FF41' : '#22484848'
    },
    {
      label: 'AUDIO',
      value: latest ? `${Math.round(audioPercent)}%` : '--',
      progress: clampPercent(audioPercent),
      progressColor: latest ? '#6600FF41' : '#22484848'
    }
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

export function hasLibraryTelemetryData(records: LibraryRecord[]): boolean {
  return getLatestRuntimeRecord(records) !== undefined
}

export function getLastPlayedLibraryRecord(records: LibraryRecord[]): LibraryRecord | undefined {
  return getLatestRuntimeRecord(records)
}

export function formatLastPlayedRelative(timestampMs: number): string {
  if (!Number.isFinite(timestampMs) || timestampMs <= 0) {
    return ''
  }
  const deltaSec = Math.max(0, Math.floor((Date.now() - timestampMs) / 1000))
  if (deltaSec < 60) {
    return '刚刚'
  }
  const minutes = Math.floor(deltaSec / 60)
  if (minutes < 60) {
    return `${minutes} 分钟前`
  }
  const hours = Math.floor(minutes / 60)
  if (hours < 24) {
    return `${hours} 小时前`
  }
  const days = Math.floor(hours / 24)
  if (days < 30) {
    return `${days} 天前`
  }
  const months = Math.floor(days / 30)
  if (months < 12) {
    return `${months} 个月前`
  }
  return `${Math.floor(months / 12)} 年前`
}

function toPercent(value: number): number {
  const safeValue = Math.max(0, Number(value) || 0)
  return safeValue <= 1 ? safeValue * 100 : safeValue
}

function clampPercent(value: number): number {
  if (!Number.isFinite(value) || value < 0) {
    return 0
  }
  if (value > 100) {
    return 100
  }
  return value
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
