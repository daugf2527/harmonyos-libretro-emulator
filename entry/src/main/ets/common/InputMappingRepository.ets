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
  try {
    const text = await fs.readText(path)
    if (!text || text.length === 0) {
      return createDefaultInputMappingProfile()
    }
    const parsed = JSON.parse(text) as InputMappingProfile
    return {
      version: MAPPING_VERSION,
      name: parsed.name || 'default',
      mappings: parsed.mappings || []
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.info('InputMappingRepository', 'Load', `加载配置失败，使用默认: ${message}`)
    return createDefaultInputMappingProfile()
  }
}

export async function saveInputMappingProfile(
  context: common.UIAbilityContext,
  profile: InputMappingProfile
): Promise<void> {
  const dirPath = buildMappingDirPath(context.filesDir)
  try {
    await fs.mkdir(dirPath)
  } catch (err) {
    // Directory may already exist
  }
  const path = buildMappingPath(context.filesDir)
  const text = JSON.stringify(profile, null, 2)
  await fs.writeText(path, text)
  LogHelper.info('InputMappingRepository', 'Save', `配置已保存: ${profile.mappings.length} 个映射`)
}

function buildMappingDirPath(filesDir: string): string {
  return `${filesDir}/${MAPPING_DIR_NAME}`
}

function buildMappingPath(filesDir: string): string {
  return `${filesDir}/${MAPPING_DIR_NAME}/${MAPPING_FILE_NAME}`
}
