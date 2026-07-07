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

const DOCUMENTATION_BASENAMES: string[] = [
  'readme', 'license', 'licence', 'copying', 'changelog', 'changes', 'notes',
  'authors', 'contributors', 'install', 'todo', 'history', 'news', 'credits'
]

function isLikelyDocumentationFile(fileName: string): boolean {
  const slashIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'))
  const base = slashIndex >= 0 ? fileName.substring(slashIndex + 1) : fileName
  const dotIndex = base.lastIndexOf('.')
  const stem = dotIndex > 0 ? base.substring(0, dotIndex) : base
  return DOCUMENTATION_BASENAMES.includes(stem.toLowerCase())
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
    if (isLikelyDocumentationFile(fileName)) {
      return
    }
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
      name: getNoGameRuntimeName(coreId),
      file: buildNoGameRuntimeRomFile(coreId),
      coreId: coreId
    })
  })

  return roms
}

export function buildNoGameRuntimeRomFile(coreId: string): string {
  return `nogame:${coreId}`
}

export function isNoGameRuntimeRomFile(romFile: string): boolean {
  return romFile.startsWith('nogame:')
}

function getNoGameRuntimeName(coreId: string): string {
  if (coreId === '2048') {
    return '2048 内置测试'
  }
  if (coreId === 'mrboom') {
    return 'Mr.Boom 内置测试'
  }
  return '无需 ROM'
}

export function getFileNameFromPath(path: string): string {
  if (isNoGameRuntimeRomFile(path)) {
    return getNoGameRuntimeName(path.substring('nogame:'.length))
  }
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
