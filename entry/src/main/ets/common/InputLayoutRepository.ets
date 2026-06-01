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
  retroButtonId: number
}

export interface InputLayoutProfile {
  version: number
  mode: string
  updatedAt: number
  buttons: InputLayoutButton[]
}

export interface RetroButtonOption {
  retroButtonId: number
  label: string
  caption: string
}

export const RETRO_BUTTON_OPTIONS: RetroButtonOption[] = [
  { retroButtonId: 0, label: 'B', caption: 'B / Secondary' },
  { retroButtonId: 1, label: 'X', caption: 'X' },
  { retroButtonId: 2, label: 'SELECT', caption: 'Select' },
  { retroButtonId: 3, label: 'START', caption: 'Start' },
  { retroButtonId: 4, label: 'UP', caption: 'D-Pad Up' },
  { retroButtonId: 5, label: 'DOWN', caption: 'D-Pad Down' },
  { retroButtonId: 6, label: 'LEFT', caption: 'D-Pad Left' },
  { retroButtonId: 7, label: 'RIGHT', caption: 'D-Pad Right' },
  { retroButtonId: 8, label: 'A', caption: 'A / Primary' },
  { retroButtonId: 9, label: 'Y', caption: 'Y' },
  { retroButtonId: 10, label: 'L', caption: 'L Shoulder' },
  { retroButtonId: 11, label: 'R', caption: 'R Shoulder' },
  { retroButtonId: 12, label: 'L2', caption: 'L2 Trigger' },
  { retroButtonId: 13, label: 'R2', caption: 'R2 Trigger' },
  { retroButtonId: 14, label: 'L3', caption: 'L3 Stick' },
  { retroButtonId: 15, label: 'R3', caption: 'R3 Stick' }
]

const DEFAULT_RETRO_ID_BUTTON_PAIRS: RetroButtonOption[] = [
  { retroButtonId: 0, label: 'b', caption: 'b' },
  { retroButtonId: 9, label: 'y', caption: 'y' },
  { retroButtonId: 2, label: 'select', caption: 'select' },
  { retroButtonId: 3, label: 'start', caption: 'start' },
  { retroButtonId: 4, label: 'up', caption: 'up' },
  { retroButtonId: 5, label: 'down', caption: 'down' },
  { retroButtonId: 6, label: 'left', caption: 'left' },
  { retroButtonId: 7, label: 'right', caption: 'right' },
  { retroButtonId: 8, label: 'a', caption: 'a' },
  { retroButtonId: 1, label: 'x', caption: 'x' },
  { retroButtonId: 10, label: 'l', caption: 'l' },
  { retroButtonId: 11, label: 'r', caption: 'r' }
]

export function getDefaultRetroButtonId(buttonId: string): number {
  const found = DEFAULT_RETRO_ID_BUTTON_PAIRS.find((item: RetroButtonOption) => item.label === buttonId)
  return found ? found.retroButtonId : -1
}

export function getRetroButtonOptionLabel(retroButtonId: number): string {
  const found = RETRO_BUTTON_OPTIONS.find((item: RetroButtonOption) => item.retroButtonId === retroButtonId)
  return found ? found.label : '未绑定'
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
      { id: 'up', label: '上', caption: 'Directional_Up', x: 80, y: 130, size: 60, shape: 'square', retroButtonId: 4 },
      { id: 'left', label: '左', caption: 'Directional_Left', x: 20, y: 190, size: 60, shape: 'square', retroButtonId: 6 },
      { id: 'right', label: '右', caption: 'Directional_Right', x: 140, y: 190, size: 60, shape: 'square', retroButtonId: 7 },
      { id: 'down', label: '下', caption: 'Directional_Down', x: 80, y: 250, size: 60, shape: 'square', retroButtonId: 5 },
      { id: 'select', label: '选择', caption: 'Select', x: 156, y: 100, size: 54, shape: 'function', retroButtonId: 2 },
      { id: 'start', label: '开始', caption: 'Start', x: 228, y: 100, size: 54, shape: 'function', retroButtonId: 3 },
      { id: 'b', label: 'B', caption: 'Secondary', x: 240, y: 200, size: 72, shape: 'circle', retroButtonId: 0 },
      { id: 'a', label: 'A', caption: 'Primary', x: 332, y: 170, size: 72, shape: 'circle', retroButtonId: 8 },
      { id: 'l', label: 'L', caption: 'Left_Shoulder', x: 36, y: 50, size: 86, shape: 'shoulder', retroButtonId: 10 },
      { id: 'r', label: 'R', caption: 'Right_Shoulder', x: 318, y: 50, size: 86, shape: 'shoulder', retroButtonId: 11 }
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
    const parsed = JSON.parse(text) as Partial<InputLayoutProfile> | null
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
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('InputLayoutRepository', 'Save', `保存输入布局失败: ${message}`)
    throw err as Error
  } finally {
    if (file) {
      try {
        await fs.close(file.fd)
      } catch (_closeErr) {
      }
    }
  }
  return nextProfile
}

export async function resetInputLayoutProfile(context: common.UIAbilityContext): Promise<InputLayoutProfile> {
  const profile = createDefaultInputLayoutProfile()
  return await saveInputLayoutProfile(context, profile)
}

function normalizeProfile(profile: Partial<InputLayoutProfile> | null | undefined): InputLayoutProfile {
  const buttons: InputLayoutButton[] = []
  if (profile?.buttons) {
    profile.buttons.forEach((button: InputLayoutButton) => {
      buttons.push(normalizeButton(button))
    })
  }
  if (buttons.length === 0) {
    return createDefaultInputLayoutProfile()
  }
  return {
    version: INPUT_LAYOUT_VERSION,
    mode: normalizeText(profile?.mode, 'RETRO_PAD_TOUCH'),
    updatedAt: normalizeNumber(profile?.updatedAt),
    buttons: buttons
  }
}

function normalizeButton(button: Partial<InputLayoutButton>): InputLayoutButton {
  const safeId = normalizeText(button.id, 'button')
  const fallbackRetroId = getDefaultRetroButtonId(safeId)
  return {
    id: safeId,
    label: localizeButtonLabel(safeId, normalizeText(button.label, 'BTN')),
    caption: normalizeText(button.caption, 'Input_Button'),
    x: normalizeNumber(button.x),
    y: normalizeNumber(button.y),
    size: Math.max(32, Math.min(96, normalizeNumber(button.size))),
    shape: normalizeText(button.shape, 'square'),
    retroButtonId: normalizeRetroButtonId(button.retroButtonId, fallbackRetroId)
  }
}

// Migrate older English labels (UP / DOWN / LEFT / RIGHT / SELECT / START) saved
// in input_layout.json from previous builds. Single-character keys (A/B/L/R) and
// already-Chinese labels are preserved as-is. This keeps existing saved layouts
// readable on the narrow 48px D-pad cells without forcing the user to reset.
function localizeButtonLabel(buttonId: string, rawLabel: string): string {
  const upper = rawLabel.trim().toUpperCase()
  if (buttonId === 'up' && (upper === 'UP' || upper === 'U')) {
    return '上'
  }
  if (buttonId === 'down' && (upper === 'DOWN' || upper === 'D')) {
    return '下'
  }
  if (buttonId === 'left' && (upper === 'LEFT')) {
    return '左'
  }
  if (buttonId === 'right' && (upper === 'RIGHT')) {
    return '右'
  }
  if (buttonId === 'select' && upper === 'SELECT') {
    return '选择'
  }
  if (buttonId === 'start' && upper === 'START') {
    return '开始'
  }
  return rawLabel
}

function normalizeRetroButtonId(value: number | undefined, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback
  }
  const intValue = Math.floor(value)
  if (intValue < -1 || intValue > 15) {
    return fallback
  }
  return intValue
}

function normalizeText(value: string | undefined, fallback: string): string {
  if (!value || value.trim().length === 0) {
    return fallback
  }
  return value.trim()
}

function normalizeNumber(value: number | undefined): number {
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
