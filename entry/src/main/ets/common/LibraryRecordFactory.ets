import { getPreferredCoreIdForFile } from './RomImportService'
import {
  LibraryRecord,
  LibrarySourceType
} from './LibraryRepository'

export interface LibraryRomFileSource {
  fileName: string
  romFile: string
  sourceType: LibrarySourceType
}

export function buildLibraryRecordsFromSources(sources: LibraryRomFileSource[]): LibraryRecord[] {
  const uniqueSources = sources.filter((item: LibraryRomFileSource, index: number) => {
    return item.fileName.length > 0 &&
      sources.findIndex((candidate: LibraryRomFileSource) => candidate.romFile === item.romFile) === index
  })
  uniqueSources.sort((left: LibraryRomFileSource, right: LibraryRomFileSource) => {
    return left.fileName.localeCompare(right.fileName)
  })
  const now = Date.now()
  const games: LibraryRecord[] = []
  uniqueSources.forEach((source: LibraryRomFileSource, index: number) => {
    const preferredCoreId = getPreferredCoreIdForFile(source.fileName.toLowerCase())
    if (preferredCoreId.length === 0) {
      return
    }
    games.push({
      id: source.romFile,
      title: buildGameTitle(source.fileName),
      subtitle: source.fileName,
      platform: resolvePlatform(source.fileName),
      coverColor: buildCoverColor(index),
      coverKey: resolveCoverKey(source.fileName),
      romFile: source.romFile,
      preferredCoreId: preferredCoreId,
      fileName: source.fileName,
      sourceType: source.sourceType,
      status: 'READY',
      createdAt: now,
      importedAt: source.sourceType === 'IMPORTED' ? now : 0,
      updatedAt: now,
      lastSeenAt: now,
      lastPlayedAt: 0,
      playCount: 0,
      totalPlayTimeMs: 0,
      lastSessionDurationMs: 0,
      lastRuntimeUpdatedAt: 0,
      lastRuntimeFps: 0,
      lastRuntimeAudioBufferUsage: 0,
      lastRuntimeAudioUnderruns: 0,
      lastRuntimeAudioOverruns: 0,
      lastRuntimeVideoDrops: 0,
      lastRuntimeVideoDupes: 0,
      lastRuntimeVideoNulls: 0
    })
  })
  return games
}

function buildGameTitle(fileName: string): string {
  let nameOnly = fileName
  const slashIndex = fileName.lastIndexOf('/')
  if (slashIndex >= 0) {
    nameOnly = fileName.substring(slashIndex + 1)
  }
  const dotIndex = nameOnly.lastIndexOf('.')
  const baseName = dotIndex > 0 ? nameOnly.substring(0, dotIndex) : nameOnly
  return baseName.replace(/[_-]+/g, ' ')
}

function resolvePlatform(fileName: string): string {
  const ext = getFileExtension(fileName.toLowerCase())
  switch (ext) {
    case 'gb':
    case 'gbc':
    case 'dmg':
      return 'GB'
    case 'gba':
    case 'agb':
      return 'GBA'
    case 'nes':
    case 'fds':
    case 'unf':
    case 'unif':
      return 'FC'
    case 'smc':
    case 'sfc':
    case 'swc':
    case 'fig':
    case 'bs':
    case 'st':
    case 'gd3':
    case 'gd7':
    case 'dx2':
    case 'bsx':
      return 'SNES'
    case 'mdx':
    case 'md':
    case 'smd':
    case 'gen':
    case 'sms':
    case 'bms':
    case 'gg':
    case 'sg':
    case '68k':
    case 'sgd':
      return 'MD'
    case 'nds':
    case 'ids':
    case 'dsi':
      return 'NDS'
    case 'n64':
    case 'z64':
    case 'v64':
    case 'rom':
      return 'N64'
    case 'cue':
    case 'toc':
    case 'ccd':
    case 'pbp':
    case 'chd':
    case 'iso':
    case 'm3u':
    case 'cbn':
      return 'PS'
    case 'zip':
    case '7z':
      return 'ARCADE'
    default:
      return ext.length > 0 ? ext.toUpperCase() : 'ROM'
  }
}

function getFileExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return ''
  }
  return fileName.substring(dotIndex + 1)
}

function buildCoverColor(index: number): string {
  const palette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331', '#2E4A52', '#4F2F2A', '#314B63']
  return palette[index % palette.length]
}

function resolveCoverKey(fileName: string): string {
  const normalized = fileName.toLowerCase()
  if (normalized.indexOf('metroid') >= 0 || normalized.indexOf('castlevania') >= 0 ||
    normalized.indexOf('aria') >= 0) {
    return 'metroid_fusion'
  }
  if (normalized.indexOf('zelda') >= 0 || normalized.indexOf('chrono') >= 0 ||
    normalized.indexOf('final fantasy') >= 0) {
    return 'zelda_triforce'
  }
  return ''
}
