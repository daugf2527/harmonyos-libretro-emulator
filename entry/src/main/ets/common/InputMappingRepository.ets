import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface KeyMapping {
  keyCode: string  // e.g., "KEY_Z", "KEY_X", "KEY_DPAD_UP"
  joypadId: number // RETRO_DEVICE_ID_JOYPAD_* (0-15)
}

export interface InputMappingProfile {
  version: number
  name: string
  mappings: KeyMapping[]
}

const MAPPING_VERSION = 1
const MAPPING_DIR_NAME = 'input'
const MAPPING_FILE_NAME = 'key_mapping.json'

function isMissingFileError(message: string): boolean {
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}

export function createDefaultInputMappingProfile(): InputMappingProfile {
  return {
    version: MAPPING_VERSION,
    name: 'default',
    mappings: [
      { keyCode: 'KEY_DPAD_UP', joypadId: 4 },
      { keyCode: 'KEY_DPAD_DOWN', joypadId: 5 },
      { keyCode: 'KEY_DPAD_LEFT', joypadId: 6 },
      { keyCode: 'KEY_DPAD_RIGHT', joypadId: 7 },
      { keyCode: 'KEY_ENTER', joypadId: 3 },      // Start
      { keyCode: 'KEY_SPACE', joypadId: 2 },      // Select
      { keyCode: 'KEY_ESCAPE', joypadId: 0 },     // B
      { keyCode: 'KEY_Z', joypadId: 0 },          // B
      { keyCode: 'KEY_X', joypadId: 8 },          // A
      { keyCode: 'KEY_A', joypadId: 1 },          // Y
      { keyCode: 'KEY_S', joypadId: 9 }           // X
    ]
  }
}

export async function loadInputMappingProfile(
  context: common.UIAbilityContext
): Promise<InputMappingProfile> {
  const path = buildMappingPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createDefaultInputMappingProfile()
  }
  try {
    const parsed = JSON.parse(text) as Partial<InputMappingProfile> | null
    return {
      version: MAPPING_VERSION,
      name: parsed?.name || 'default',
      mappings: normalizeMappings(parsed?.mappings)
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('InputMappingRepository', 'Load', `按键映射配置损坏，已回退默认值: ${message}`)
    return createDefaultInputMappingProfile()
  }
}

function normalizeMappings(mappings: KeyMapping[] | undefined): KeyMapping[] {
  if (!mappings) {
    return []
  }
  return mappings
    .filter((item: KeyMapping) => item.keyCode.length > 0)
    .map((item: KeyMapping): KeyMapping => {
      return {
        keyCode: item.keyCode,
        joypadId: Math.max(0, Math.min(15, Math.floor(Number(item.joypadId) || 0)))
      }
    })
}

export async function saveInputMappingProfile(
  context: common.UIAbilityContext,
  profile: InputMappingProfile
): Promise<void> {
  const dirPath = buildMappingDirPath(context.filesDir)
  try {
    await fs.mkdir(dirPath, true)
  } catch (err) {
    // Directory may already exist
  }
  const path = buildMappingPath(context.filesDir)
  const text = JSON.stringify(profile, null, 2)
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, text)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('InputMappingRepository', 'Save', `保存配置失败: ${message}`)
    throw err as Error
  } finally {
    if (file) {
      try {
        await fs.close(file.fd)
      } catch (_closeErr) {
      }
    }
  }
  LogHelper.info('InputMappingRepository', 'Save', `配置已保存: ${profile.mappings.length} 个映射`)
}

function buildMappingDirPath(filesDir: string): string {
  return `${filesDir}/${MAPPING_DIR_NAME}`
}

function buildMappingPath(filesDir: string): string {
  return `${filesDir}/${MAPPING_DIR_NAME}/${MAPPING_FILE_NAME}`
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (_err) {
    return false
  }
}

async function readOptionalText(path: string): Promise<string> {
  if (!(await fileExists(path))) {
    return ''
  }
  try {
    return await fs.readText(path)
  } catch (err) {
    const message = (err as Error).message || String(err)
    if (isMissingFileError(message)) {
      return ''
    }
    return ''
  }
}
