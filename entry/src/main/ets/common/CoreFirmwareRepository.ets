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

export const CORE_FIRMWARE_DEPENDENCY_RULES: CoreFirmwareDependencyRule[] = [
  {
    coreId: 'melonds',
    coreName: 'melonDS',
    requiredFiles: ['bios7.bin', 'bios9.bin', 'firmware.bin'],
    hint: '建议放入 filesDir/system/ 下的 BIOS 与固件文件'
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
  try {
    return await fs.listFile(systemDir)
  } catch (_err) {
    return []
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
      detailText: '当前核心未配置额外 BIOS / firmware 依赖',
      foundFilesText: '未命中依赖规则',
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
    `固件就绪 ${foundFiles.length}/${rule.requiredFiles.length}` :
    (foundFiles.length > 0 ?
      `部分缺失 ${foundFiles.length}/${rule.requiredFiles.length}` :
      `缺少固件 0/${rule.requiredFiles.length}`)

  return {
    coreId: rule.coreId,
    coreName: rule.coreName,
    statusText: statusText,
    detailText: rule.hint,
    foundFilesText: foundFiles.length > 0 ? `已发现: ${foundFiles.join(', ')}` : '未发现对应 BIOS / firmware 文件',
    missingFilesText: missingFiles.length > 0 ? `缺少: ${missingFiles.join(', ')}` : '无缺失项',
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
