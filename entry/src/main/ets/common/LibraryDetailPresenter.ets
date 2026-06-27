import { CoreConfig, LIBRETRO_CORE_CATALOG } from './LibretroCoreCatalog'
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

export function getLibraryDetailDisplayTitle(record: LibraryRecord): string {
  return record.title.toUpperCase()
}

export function getLibraryDetailConsoleLabel(record: LibraryRecord): string {
  if (record.platform === 'SNES') {
    return 'SFC'
  }
  if (record.platform === 'FC') {
    return 'NES'
  }
  return record.platform
}

export function getLibraryDetailYearLabel(record: LibraryRecord): string {
  // 优先使用 LibraryRecord 中的 releaseYear
  if (record.releaseYear !== undefined && record.releaseYear > 0) {
    return String(record.releaseYear)
  }
  // 其次从文件名提取标签
  const tag = extractTaggedTokens(record.fileName).find((item: string) => /^[12][0-9]{3}$/.test(item))
  if (tag) {
    return tag
  }
  // 最后使用导入年份
  if (record.importedAt > 0) {
    return String(new Date(record.importedAt).getFullYear())
  }
  return '--'
}

export function getLibraryDetailOverviewText(record: LibraryRecord): string {
  if (record.overview !== undefined && record.overview.length > 0) {
    return record.overview
  }
  return '当前还没有本地简介，可在资料编辑里补充。'
}

export function getLibraryDetailRuntimeSummaryText(record: LibraryRecord): string {
  const segments: string[] = [
    `该条目来自${getLibraryDetailSourceLabel(record)}，当前状态为${getLibraryDetailStatusLabel(record)}。`,
    `当前库记录的平台标记为 ${record.platform}，核心偏好为 ${getLibraryDetailEngineLabel(record)}。`,
    `ROM 文件名为 ${record.fileName}。`
  ]
  const region = getLibraryDetailRegionLabel(record)
  if (region !== '未从文件标签识别到区域') {
    segments.push(`文件标签中识别到区域信息 ${region}。`)
  }
  if (record.publisher !== undefined && record.publisher.length > 0) {
    segments.push(`发行商为 ${record.publisher}。`)
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
  return segments.join('')
}

export function getLibraryDetailRegionLabel(record: LibraryRecord): string {
  const tokens = extractTaggedTokens(record.fileName).map((item: string) => item.toUpperCase())
  const joined = tokens.join(' ')
  if (joined.indexOf('NTSC-J') >= 0 || joined.indexOf('JAPAN') >= 0 || joined.indexOf('JP') >= 0) {
    return '日版 / NTSC'
  }
  if (joined.indexOf('NTSC-U') >= 0 || joined.indexOf('USA') >= 0 || joined.indexOf('US') >= 0) {
    return '美版 / NTSC'
  }
  if (joined.indexOf('PAL') >= 0 || joined.indexOf('EU') >= 0 || joined.indexOf('EUR') >= 0 ||
    joined.indexOf('EUROPE') >= 0) {
    return '欧版 / PAL'
  }
  if (joined.indexOf('WORLD') >= 0) {
    return '全球版'
  }
  return '未从文件标签识别到区域'
}

export function getLibraryDetailEngineLabel(record: LibraryRecord): string {
  if (record.preferredCoreId.length === 0) {
    return '未匹配核心'
  }
  const matchedCore = LIBRETRO_CORE_CATALOG.find((item: CoreConfig) => item.id === record.preferredCoreId)
  if (matchedCore) {
    return matchedCore.name
  }
  return record.preferredCoreId.replace(/_/g, ' ')
}

export function getLibraryDetailPublisherLabel(record: LibraryRecord): string {
  if (record.publisher !== undefined && record.publisher.length > 0) {
    return record.publisher
  }
  return '未填写'
}

export function getLibraryDetailPlaytimeLabel(record: LibraryRecord): string {
  if (record.totalPlayTimeMs <= 0) {
    return '0h 00m'
  }
  return formatLibraryDetailDuration(record.totalPlayTimeMs)
}

export function getLibraryDetailRomVersionLabel(record: LibraryRecord): string {
  const taggedTokens = extractTaggedTokens(record.fileName)
  const matchedTag = taggedTokens.find((item: string) => /(^|[\s_-])(rev|v)\s*[a-z0-9.]+/i.test(item))
  if (matchedTag) {
    return matchedTag.trim()
  }
  const cleanedFileName = cleanLibraryFileName(record.fileName)
  const inlineMatch = cleanedFileName.match(/\b(Rev\.?\s*[A-Z0-9]+|v\s*\d+(?:\.\d+)*)\b/i)
  if (inlineMatch && inlineMatch[1]) {
    return inlineMatch[1].trim()
  }
  return '未标注'
}

export function getLibraryDetailMemoryModeLabel(record: LibraryRecord): string {
  return record.sourceType === 'IMPORTED' ? '应用沙箱文件' : '应用内置资源'
}

export function getLibraryDetailStatusLabel(record: LibraryRecord): string {
  return record.lastPlayedAt > 0 ? '已产生启动记录' : '尚未产生启动记录'
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
  return record.sourceType === 'IMPORTED' ? '用户导入文件' : '应用内置资源'
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
