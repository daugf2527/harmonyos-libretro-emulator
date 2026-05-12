import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface InputLayoutButton {
  id: string
  label: string
  caption: string
  x: number
  y: number
  size: number
  shape: string
}

export interface InputLayoutProfile {
  version: number
  mode: string
  updatedAt: number
  buttons: InputLayoutButton[]
}

const INPUT_LAYOUT_VERSION = 1
const INPUT_LAYOUT_DIR_NAME = 'input'
const INPUT_LAYOUT_FILE_NAME = 'input_layout.json'

export function createDefaultInputLayoutProfile(): InputLayoutProfile {
  return {
    version: INPUT_LAYOUT_VERSION,
    mode: 'RETRO_PAD_TOUCH',
    updatedAt: 0,
    buttons: [
      { id: 'up', label: 'UP', caption: 'Directional_Up', x: 48, y: 136, size: 48, shape: 'square' },
      { id: 'left', label: 'LEFT', caption: 'Directional_Left', x: 0, y: 184, size: 48, shape: 'square' },
      { id: 'right', label: 'RIGHT', caption: 'Directional_Right', x: 96, y: 184, size: 48, shape: 'square' },
      { id: 'down', label: 'DOWN', caption: 'Directional_Down', x: 48, y: 232, size: 48, shape: 'square' },
      { id: 'select', label: 'SELECT', caption: 'Select', x: 154, y: 226, size: 54, shape: 'function' },
      { id: 'start', label: 'START', caption: 'Start', x: 222, y: 226, size: 54, shape: 'function' },
      { id: 'b', label: 'B', caption: 'Secondary', x: 252, y: 204, size: 62, shape: 'circle' },
      { id: 'a', label: 'A', caption: 'Primary', x: 330, y: 180, size: 62, shape: 'circle' },
      { id: 'l', label: 'L', caption: 'Left_Shoulder', x: 24, y: 78, size: 86, shape: 'shoulder' },
      { id: 'r', label: 'R', caption: 'Right_Shoulder', x: 292, y: 78, size: 86, shape: 'shoulder' }
    ]
  }
}

export async function loadInputLayoutProfile(context: common.UIAbilityContext): Promise<InputLayoutProfile> {
  const path = buildInputLayoutPath(context.filesDir)
  try {
    const text = await fs.readText(path)
    if (!text || text.length === 0) {
      return createDefaultInputLayoutProfile()
    }
    const parsed = JSON.parse(text) as InputLayoutProfile
    return normalizeProfile(parsed)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('InputLayoutRepository', 'Load', `读取输入布局失败: ${message}`)
    return createDefaultInputLayoutProfile()
  }
}

export async function saveInputLayoutProfile(
  context: common.UIAbilityContext,
  profile: InputLayoutProfile
): Promise<InputLayoutProfile> {
  await ensureDirExists(buildInputLayoutDirPath(context.filesDir))
  const normalized = normalizeProfile(profile)
  const nextProfile: InputLayoutProfile = {
    version: INPUT_LAYOUT_VERSION,
    mode: normalized.mode,
    updatedAt: Date.now(),
    buttons: normalized.buttons
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(buildInputLayoutPath(context.filesDir), fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(nextProfile, null, 2))
  } finally {
    if (file) {
      await fs.close(file.fd)
    }
  }
  return nextProfile
}

export async function resetInputLayoutProfile(context: common.UIAbilityContext): Promise<InputLayoutProfile> {
  const profile = createDefaultInputLayoutProfile()
  return await saveInputLayoutProfile(context, profile)
}

function normalizeProfile(profile: InputLayoutProfile): InputLayoutProfile {
  const buttons: InputLayoutButton[] = []
  if (profile.buttons) {
    profile.buttons.forEach((button: InputLayoutButton) => {
      buttons.push(normalizeButton(button))
    })
  }
  if (buttons.length === 0) {
    return createDefaultInputLayoutProfile()
  }
  return {
    version: INPUT_LAYOUT_VERSION,
    mode: normalizeText(profile.mode, 'RETRO_PAD_TOUCH'),
    updatedAt: normalizeNumber(profile.updatedAt),
    buttons: buttons
  }
}

function normalizeButton(button: InputLayoutButton): InputLayoutButton {
  return {
    id: normalizeText(button.id, 'button'),
    label: normalizeText(button.label, 'BTN'),
    caption: normalizeText(button.caption, 'Input_Button'),
    x: normalizeNumber(button.x),
    y: normalizeNumber(button.y),
    size: Math.max(32, Math.min(96, normalizeNumber(button.size))),
    shape: normalizeText(button.shape, 'square')
  }
}

function normalizeText(value: string, fallback: string): string {
  if (!value || value.trim().length === 0) {
    return fallback
  }
  return value.trim()
}

function normalizeNumber(value: number): number {
  if (!Number.isFinite(value)) {
    return 0
  }
  return Math.floor(value)
}

function buildInputLayoutDirPath(filesDir: string): string {
  return `${filesDir}/${INPUT_LAYOUT_DIR_NAME}`
}

function buildInputLayoutPath(filesDir: string): string {
  return `${buildInputLayoutDirPath(filesDir)}/${INPUT_LAYOUT_FILE_NAME}`
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (err) {
    return
  }
}
