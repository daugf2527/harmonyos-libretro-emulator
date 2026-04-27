import {
  LIBRETRO_CORE_EXTENSION_RULES,
  NO_GAME_CORE_IDS
} from './LibretroCoreCatalog'

export interface RuntimeRomConfig {
  id: string
  name: string
  file: string
  coreId: string
}

export interface RuntimeRomSourceItem {
  fileName: string
  launchPath: string
}

export function buildRuntimeRomConfigs(sources: RuntimeRomSourceItem[]): RuntimeRomConfig[] {
  const uniqueSources = sources.filter((item: RuntimeRomSourceItem, index: number) => {
    return item.fileName.length > 0 &&
      sources.findIndex((candidate: RuntimeRomSourceItem) => candidate.launchPath === item.launchPath) === index
  })

  uniqueSources.sort((left: RuntimeRomSourceItem, right: RuntimeRomSourceItem) => {
    return left.fileName.localeCompare(right.fileName)
  })

  const roms: RuntimeRomConfig[] = []
  uniqueSources.forEach((source: RuntimeRomSourceItem) => {
    const fileName = source.fileName
    const lowerName = fileName.toLowerCase()
    const ext = getFileExtension(lowerName)
    if (!ext) {
      return
    }
    const coreIds = matchCoreIds(ext, lowerName)
    if (coreIds.length === 0) {
      return
    }
    coreIds.forEach((coreId: string) => {
      roms.push({
        id: `${coreId}:${source.launchPath}`,
        name: fileName,
        file: source.launchPath,
        coreId: coreId
      })
    })
  })

  NO_GAME_CORE_IDS.forEach((coreId: string) => {
    roms.push({
      id: `nogame:${coreId}`,
      name: '无需 ROM',
      file: '',
      coreId: coreId
    })
  })

  return roms
}

export function getFileNameFromPath(path: string): string {
  const normalizedPath = path.split('?')[0]
  const slashIndex = normalizedPath.lastIndexOf('/')
  if (slashIndex >= 0 && slashIndex < normalizedPath.length - 1) {
    return normalizedPath.substring(slashIndex + 1)
  }
  return normalizedPath
}

function matchCoreIds(ext: string, fileName: string): string[] {
  const matched: string[] = []
  LIBRETRO_CORE_EXTENSION_RULES.forEach((rule) => {
    if (rule.coreId === 'mrboom') {
      return
    }
    if (rule.requiresExactName && getFileNameFromPath(fileName) !== rule.requiresExactName) {
      return
    }
    if (hasExtension(rule.extensions, ext)) {
      matched.push(rule.coreId)
    }
  })
  return matched
}

function hasExtension(extensions: string[], ext: string): boolean {
  return extensions.includes(ext)
}

function getFileExtension(fileName: string): string {
  const dotIndex = fileName.lastIndexOf('.')
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return ''
  }
  return fileName.slice(dotIndex + 1)
}
