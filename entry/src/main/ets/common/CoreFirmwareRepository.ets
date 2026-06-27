import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface CoreFirmwareDependencyRule {
  coreId: string
  coreName: string
  requiredFiles: string[]
  hint: string
}

export interface CoreFirmwareDependencyState {
  coreId: string
  coreName: string
  statusText: string
  detailText: string
  foundFilesText: string
  missingFilesText: string
  hasDependencies: boolean
}

interface CoreFirmwareFileErrorWithCode {
  code?: string | number
}

export const CORE_FIRMWARE_DEPENDENCY_RULES: CoreFirmwareDependencyRule[] = [
  {
    coreId: 'melonds',
    coreName: 'melonDS',
    requiredFiles: ['bios7.bin', 'bios9.bin', 'firmware.bin'],
    hint: '建议把 BIOS 与固件文件放到应用的固件目录'
  },
  {
    coreId: 'mednafen_psx_hw',
    coreName: 'Beetle PSX HW',
    requiredFiles: ['scph5500.bin', 'scph5501.bin', 'scph5502.bin'],
    hint: '至少准备一份有效的 PS1 BIOS'
  },
  {
    coreId: 'pcsx_rearmed',
    coreName: 'PCSX-ReARMed',
    requiredFiles: ['scph5500.bin', 'scph5501.bin', 'scph5502.bin'],
    hint: '建议准备 PS1 BIOS 以提升兼容性'
  }
]

export async function loadSystemFirmwareEntries(context: common.UIAbilityContext): Promise<string[]> {
  const systemDir = buildSystemFirmwareDir(context.filesDir)
  if (!(await pathExists(systemDir))) {
    return []
  }
  try {
    return await fs.listFile(systemDir)
  } catch (err) {
    throw err as Error
  }
}

export function buildCoreFirmwareDependencyState(
  coreId: string,
  systemEntries: string[]
): CoreFirmwareDependencyState {
  const rule = CORE_FIRMWARE_DEPENDENCY_RULES.find((item: CoreFirmwareDependencyRule) => item.coreId === coreId)
  if (!rule) {
    return {
      coreId: coreId,
      coreName: coreId,
      statusText: '无需额外固件',
      detailText: '当前核心不依赖额外 BIOS 或固件',
      foundFilesText: '不需要额外固件文件',
      missingFilesText: '无',
      hasDependencies: false
    }
  }

  const availableEntries = new Set<string>()
  systemEntries.forEach((entry: string) => {
    availableEntries.add(normalizeFirmwareName(entry))
  })

  const foundFiles: string[] = []
  const missingFiles: string[] = []
  rule.requiredFiles.forEach((fileName: string) => {
    const normalized = normalizeFirmwareName(fileName)
    if (availableEntries.has(normalized)) {
      foundFiles.push(fileName)
      return
    }
    missingFiles.push(fileName)
  })

  const statusText = missingFiles.length === 0 ?
    `固件文件名已配齐 ${foundFiles.length}/${rule.requiredFiles.length}` :
    (foundFiles.length > 0 ?
      `文件名部分匹配 ${foundFiles.length}/${rule.requiredFiles.length}` :
      `缺少固件文件名 0/${rule.requiredFiles.length}`)

  return {
    coreId: rule.coreId,
    coreName: rule.coreName,
    statusText: statusText,
    detailText: rule.hint,
    foundFilesText: foundFiles.length > 0 ? `已检测到: ${foundFiles.join(', ')}` : '暂未检测到对应 BIOS 或固件文件',
    missingFilesText: missingFiles.length > 0 ? `仍需补充: ${missingFiles.join(', ')}` : '无缺失项',
    hasDependencies: true
  }
}

export function formatCoreFirmwarePathList(files: string[]): string {
  if (files.length === 0) {
    return '无'
  }
  return files.map((fileName: string) => `system/${fileName}`).join(' / ')
}

function buildSystemFirmwareDir(filesDir: string): string {
  return `${filesDir}/system`
}

function normalizeFirmwareName(value: string): string {
  return `${value}`.trim().toLowerCase()
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (err) {
    if (isMissingFileError(err)) {
      return false
    }
    throw err as Error
  }
}

function isMissingFileError(err: unknown): boolean {
  const errorCode = (err as CoreFirmwareFileErrorWithCode).code
  if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
    return true
  }
  const message = (err as Error).message || String(err)
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}
