import {
  buildRecentLibraryRecords,
  LibraryRecord
} from './LibraryRepository'

export function filterLibraryGames(
  games: LibraryRecord[],
  selectedPlatform: string,
  keyword: string
): LibraryRecord[] {
  const normalizedKeyword = keyword.trim().toLowerCase()
  return games.filter((item: LibraryRecord) => {
    return isPlatformMatched(item, selectedPlatform) && matchesKeyword(item, normalizedKeyword)
  })
}

export function filterRecentLibraryGames(
  games: LibraryRecord[],
  selectedPlatform: string,
  keyword: string
): LibraryRecord[] {
  return filterLibraryGames(buildRecentLibraryRecords(games, 2), selectedPlatform, keyword)
}

export function buildLibrarySearchResults(
  games: LibraryRecord[],
  selectedPlatform: string,
  query: string
): LibraryRecord[] {
  const normalizedQuery = query.trim().toLowerCase()
  if (normalizedQuery.length === 0) {
    return []
  }
  return buildSearchSource(games).filter((item: LibraryRecord) => {
    return isPlatformMatched(item, selectedPlatform) && matchesKeyword(item, normalizedQuery)
  })
}

export function buildLibraryPlatforms(games: LibraryRecord[]): string[] {
  const platformSet: Set<string> = new Set()
  games.forEach((item: LibraryRecord) => {
    if (item.platform.length > 0) {
      platformSet.add(item.platform)
    }
  })
  return ['ALL', ...Array.from(platformSet).sort((left: string, right: string) => left.localeCompare(right))]
}

export function buildDisplayPlatformFilters(games: LibraryRecord[]): string[] {
  return buildLibraryPlatforms(games)
}

function buildSearchSource(games: LibraryRecord[]): LibraryRecord[] {
  const merged: LibraryRecord[] = [...buildRecentLibraryRecords(games, 2), ...games]
  return merged.filter((item: LibraryRecord, index: number) => {
    return merged.findIndex((candidate: LibraryRecord) => candidate.id === item.id) === index
  })
}

function isPlatformMatched(item: LibraryRecord, selectedPlatform: string): boolean {
  return selectedPlatform === 'ALL' || item.platform === selectedPlatform
}

function matchesKeyword(item: LibraryRecord, keyword: string): boolean {
  if (keyword.length === 0) {
    return true
  }
  return item.title.toLowerCase().indexOf(keyword) >= 0 ||
    item.subtitle.toLowerCase().indexOf(keyword) >= 0 ||
    item.platform.toLowerCase().indexOf(keyword) >= 0
}
