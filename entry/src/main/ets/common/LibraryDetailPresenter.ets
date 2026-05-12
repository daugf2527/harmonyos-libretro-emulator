import { GameMetadataRecord } from './GameMetadataRepository'
import { LibraryRecord } from './LibraryRepository'

export interface LibraryDetailTelemetrySnapshot {
  fpsText: string
  audioText: string
  dropText: string
  profile: number[]
}

export function getLibraryDetailLocalizedTitle(record: LibraryRecord): string {
  return cleanLibraryFileName(record.fileName)
}

export function getLibraryDetailDisplayTitle(
  record: LibraryRecord,
  metadata: GameMetadataRecord | undefined
): string {
  const metadataTitle = getMetadataTitle(metadata)
  if (metadataTitle !== 'Unknown') {
    return metadataTitle.toUpperCase()
  }
  return record.title.toUpperCase()
}

export function getLibraryDetailConsoleLabel(
  record: LibraryRecord,
  metadata: GameMetadataRecord | undefined
): string {
  const metadataPlatform = getMetadataPlatform(metadata)
  if (metadataPlatform !== 'Unknown') {
    return metadataPlatform
  }
  if (record.platform === 'SNES') {
    return 'SFC'
  }
  if (record.platform === 'FC') {
    return 'NES'
  }
  return record.platform
}

export function getLibraryDetailYearLabel(
  record: LibraryRecord,
  metadata: GameMetadataRecord | undefined
): string {
  const releaseYear = getMetadataReleaseYear(metadata)
  if (releaseYear.length > 0) {
    return releaseYear
  }
  const tag = extractTaggedTokens(record.fileName).find((item: string) => /^[12][0-9]{3}$/.test(item))
  if (tag) {
    return tag
  }
  if (record.importedAt > 0) {
    return String(new Date(record.importedAt).getFullYear())
  }
  return '--'
}

export function getLibraryDetailOverviewText(metadata: GameMetadataRecord | undefined): string {
  const metadataOverview = getMetadataOverview(metadata)
  if (metadataOverview !== 'Unknown') {
    return metadataOverview
  }
  return 'Unknown'
}

export function getLibraryDetailRuntimeSummaryText(
  record: LibraryRecord,
  metadata: GameMetadataRecord | undefined
): string {
  const segments: string[] = [
    `该条目来自${getLibraryDetailSourceLabel(record)} ROM 库，当前库状态为 ${getLibraryDetailStatusLabel(record)}。`,
    `系统识别平台为 ${record.platform}，默认核心为 ${record.preferredCoreId.toUpperCase()}。`,
    `ROM 文件名为 ${record.fileName}。`
  ]
  const region = getLibraryDetailRegionLabel(record)
  if (region !== 'AUTO / UNKNOWN') {
    segments.push(`文件标签中识别到区域信息 ${region}。`)
  }
  if (record.importedAt > 0) {
    segments.push(`导入时间 ${formatLibraryDetailDate(record.importedAt)}。`)
  }
  if (record.lastPlayedAt > 0) {
    segments.push(`最近一次启动时间 ${formatLibraryDetailDate(record.lastPlayedAt)}，累计启动 ${record.playCount} 次。`)
    if (record.totalPlayTimeMs > 0) {
      segments.push(`真实累计运行时长 ${formatLibraryDetailDuration(record.totalPlayTimeMs)}。`)
    }
  } else {
    segments.push('该条目尚未产生启动记录。')
  }
  void metadata
  return segments.join('')
}

export function getLibraryDetailRegionLabel(record: LibraryRecord): string {
  const tokens = extractTaggedTokens(record.fileName).map((item: string) => item.toUpperCase())
  const joined = tokens.join(' ')
  if (joined.indexOf('NTSC-J') >= 0 || joined.indexOf('JAPAN') >= 0 || joined.indexOf('JP') >= 0) {
    return 'JP / NTSC'
  }
  if (joined.indexOf('NTSC-U') >= 0 || joined.indexOf('USA') >= 0 || joined.indexOf('US') >= 0) {
    return 'US / NTSC'
  }
  if (joined.indexOf('PAL') >= 0 || joined.indexOf('EU') >= 0 || joined.indexOf('EUR') >= 0 ||
    joined.indexOf('EUROPE') >= 0) {
    return 'EU / PAL'
  }
  if (joined.indexOf('WORLD') >= 0) {
    return 'WORLD'
  }
  return 'AUTO / UNKNOWN'
}

export function getLibraryDetailEngineLabel(record: LibraryRecord): string {
  return `EMU_CORE_${record.preferredCoreId.toUpperCase()}`
}

export function getLibraryDetailPublisherLabel(
  metadata: GameMetadataRecord | undefined
): string {
  const metadataPublisher = getMetadataPublisher(metadata)
  if (metadataPublisher !== 'Unknown') {
    return metadataPublisher
  }
  return 'Unknown'
}

export function getLibraryDetailPlaytimeLabel(record: LibraryRecord): string {
  if (record.totalPlayTimeMs <= 0) {
    return '0h 00m'
  }
  return formatLibraryDetailDuration(record.totalPlayTimeMs)
}

export function getLibraryDetailRomVersionLabel(
  record: LibraryRecord,
  metadata: GameMetadataRecord | undefined
): string {
  const platform = getLibraryDetailConsoleLabel(record, metadata)
  const fileBase = cleanLibraryFileName(record.fileName).replace(/\s+/g, '_').toUpperCase()
  return `${platform}_v1.0_${fileBase.substring(0, Math.min(16, fileBase.length))}`
}

export function getLibraryDetailMemoryModeLabel(record: LibraryRecord): string {
  return record.sourceType === 'IMPORTED' ? 'DIRECT_MAPPING_L2' : 'BUNDLE_MOUNT_RO'
}

export function getLibraryDetailStatusLabel(record: LibraryRecord): string {
  return record.lastPlayedAt > 0 ? 'PLAYED' : 'READY'
}

export function getLibraryLaunchFileLabel(record: LibraryRecord): string {
  return record.fileName.replace(/\s+/g, '_').toUpperCase()
}

export function hasLibraryDetailRuntimeSnapshot(record: LibraryRecord): boolean {
  return record.lastRuntimeUpdatedAt > 0 || record.lastSessionDurationMs > 0
}

export function buildLibraryDetailTelemetrySnapshot(record: LibraryRecord): LibraryDetailTelemetrySnapshot {
  if (!hasLibraryDetailRuntimeSnapshot(record)) {
    return {
      fpsText: '--.-',
      audioText: '--',
      dropText: '--',
      profile: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    }
  }
  return {
    fpsText: record.lastRuntimeFps > 0 ? record.lastRuntimeFps.toFixed(1) : '--.-',
    audioText: formatPercent(record.lastRuntimeAudioBufferUsage),
    dropText: `${record.lastRuntimeVideoDrops}`,
    profile: buildRuntimeProfile(record)
  }
}

export function cleanLibraryFileName(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  const withoutExt = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
  return withoutExt.replace(/[_-]+/g, ' ')
}

function getLibraryDetailSourceLabel(record: LibraryRecord): string {
  return record.sourceType === 'IMPORTED' ? 'USER IMPORT' : 'BUNDLED'
}

function formatLibraryDetailDuration(durationMs: number): string {
  const totalMinutes = Math.floor(Math.max(0, durationMs) / 60000)
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  return `${hours}h ${minutes.toString().padStart(2, '0')}m`
}

function formatLibraryDetailDate(timestamp: number): string {
  const date = new Date(timestamp)
  const month = `${date.getMonth() + 1}`.padStart(2, '0')
  const day = `${date.getDate()}`.padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function formatPercent(value: number): string {
  if (value <= 0) {
    return '--'
  }
  const percent = value <= 1 ? value * 100 : value
  return `${percent.toFixed(0)}%`
}

function buildRuntimeProfile(record: LibraryRecord): number[] {
  const fpsLevel = Math.min(52, Math.max(0, record.lastRuntimeFps / 60 * 52))
  const audioLevel = Math.min(52, Math.max(0, (record.lastRuntimeAudioBufferUsage <= 1 ?
    record.lastRuntimeAudioBufferUsage * 100 : record.lastRuntimeAudioBufferUsage) / 100 * 52))
  const dropLevel = Math.min(52, record.lastRuntimeVideoDrops * 4)
  const dupeLevel = Math.min(52, record.lastRuntimeVideoDupes * 3)
  const nullLevel = Math.min(52, record.lastRuntimeVideoNulls * 3)
  const underrunLevel = Math.min(52, record.lastRuntimeAudioUnderruns * 4)
  const overrunLevel = Math.min(52, record.lastRuntimeAudioOverruns * 4)
  return [
    fpsLevel,
    audioLevel,
    52 - dropLevel,
    52 - dupeLevel,
    52 - nullLevel,
    52 - underrunLevel,
    52 - overrunLevel,
    audioLevel,
    fpsLevel,
    52 - dropLevel,
    52 - dupeLevel,
    audioLevel,
    fpsLevel
  ]
}

function extractTaggedTokens(fileName: string): string[] {
  const matches = fileName.match(/[\(\[]([^\)\]]+)[\)\]]/g) ?? []
  return matches.map((item: string) => {
    return item.substring(1, item.length - 1).trim()
  })
}

function getMetadataTitle(metadata: GameMetadataRecord | undefined): string {
  const value = metadata?.title
  return value && value.length > 0 ? value : 'Unknown'
}

function getMetadataPublisher(metadata: GameMetadataRecord | undefined): string {
  const value = metadata?.publisher
  return value && value.length > 0 ? value : 'Unknown'
}

function getMetadataOverview(metadata: GameMetadataRecord | undefined): string {
  const value = metadata?.overview
  return value && value.length > 0 ? value : 'Unknown'
}

function getMetadataPlatform(metadata: GameMetadataRecord | undefined): string {
  const value = metadata?.platform
  return value && value.length > 0 ? value : 'Unknown'
}

function getMetadataReleaseYear(metadata: GameMetadataRecord | undefined): string {
  const value = metadata?.releaseYear
  return value && value > 0 ? `${value}` : ''
}
