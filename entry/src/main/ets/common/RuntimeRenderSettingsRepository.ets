import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface RuntimeRenderSettingsProfile {
  version: number
  scalingMode: number
  swapInterval: number
  softwareMaxPresetIndex: number
  aiUpscaleEnabled: boolean
  hwRenderAllowed: boolean
  updatedAt: number
}

const RUNTIME_RENDER_SETTINGS_VERSION = 2
const RUNTIME_RENDER_SETTINGS_DIR_NAME = 'runtime'
const RUNTIME_RENDER_SETTINGS_FILE_NAME = 'render_settings.json'

export function createDefaultRuntimeRenderSettingsProfile(): RuntimeRenderSettingsProfile {
  return {
    version: RUNTIME_RENDER_SETTINGS_VERSION,
    scalingMode: 2,
    swapInterval: 1,
    softwareMaxPresetIndex: 1,
    aiUpscaleEnabled: false,
    hwRenderAllowed: true,
    updatedAt: 0
  }
}

export async function loadRuntimeRenderSettingsProfile(
  context: common.UIAbilityContext
): Promise<RuntimeRenderSettingsProfile> {
  const path = buildRuntimeRenderSettingsPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createDefaultRuntimeRenderSettingsProfile()
  }
  try {
    const parsed = JSON.parse(text) as Partial<RuntimeRenderSettingsProfile> | null
    return normalizeRuntimeRenderSettingsProfile(parsed)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeRenderSettingsRepository', 'Load', `渲染配置损坏，已回退默认值: ${message}`)
    return createDefaultRuntimeRenderSettingsProfile()
  }
}

export async function saveRuntimeRenderSettingsProfile(
  context: common.UIAbilityContext,
  profile: RuntimeRenderSettingsProfile
): Promise<RuntimeRenderSettingsProfile> {
  await ensureDirExists(buildRuntimeRenderSettingsDirPath(context.filesDir))
  const normalized = normalizeRuntimeRenderSettingsProfile(profile)
  const nextProfile: RuntimeRenderSettingsProfile = {
    version: RUNTIME_RENDER_SETTINGS_VERSION,
    scalingMode: normalized.scalingMode,
    swapInterval: normalized.swapInterval,
    softwareMaxPresetIndex: normalized.softwareMaxPresetIndex,
    aiUpscaleEnabled: normalized.aiUpscaleEnabled,
    hwRenderAllowed: normalized.hwRenderAllowed,
    updatedAt: Date.now()
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(
      buildRuntimeRenderSettingsPath(context.filesDir),
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    )
    await fs.write(file.fd, JSON.stringify(nextProfile, null, 2))
  } catch (err) {
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

export function normalizeRuntimeRenderSettingsProfile(
  profile: Partial<RuntimeRenderSettingsProfile> | null | undefined
): RuntimeRenderSettingsProfile {
  return {
    version: RUNTIME_RENDER_SETTINGS_VERSION,
    scalingMode: clampRenderMode(profile?.scalingMode),
    swapInterval: clampSwapInterval(profile?.swapInterval),
    softwareMaxPresetIndex: clampSoftwarePresetIndex(profile?.softwareMaxPresetIndex),
    aiUpscaleEnabled: profile?.aiUpscaleEnabled === true,
    hwRenderAllowed: profile?.hwRenderAllowed !== false,
    updatedAt: Number(profile?.updatedAt) || 0
  }
}

export function describeRenderMode(mode: number): string {
  const safeMode = clampRenderMode(mode)
  if (safeMode === 0) {
    return '硬件渲染'
  }
  if (safeMode === 1) {
    return '软件渲染'
  }
  return 'GLES 渲染'
}

export function describeSoftwareResolutionPreset(index: number): string {
  const safeIndex = clampSoftwarePresetIndex(index)
  if (safeIndex === 0) {
    return '640x480'
  }
  if (safeIndex === 2) {
    return '1920x1080'
  }
  return '1280x720'
}

function clampRenderMode(mode: number | undefined): number {
  const safeMode = Math.floor(Number(mode) || 0)
  if (safeMode < 0) {
    return 0
  }
  if (safeMode > 2) {
    return 2
  }
  return safeMode
}

function clampSwapInterval(interval: number | undefined): number {
  const safeInterval = Math.floor(Number(interval) || 0)
  if (safeInterval <= 0) {
    return 0
  }
  return 1
}

function clampSoftwarePresetIndex(index: number | undefined): number {
  const safeIndex = Math.floor(Number(index) || 0)
  if (safeIndex < 0) {
    return 0
  }
  if (safeIndex > 2) {
    return 2
  }
  return safeIndex
}

function buildRuntimeRenderSettingsDirPath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_RENDER_SETTINGS_DIR_NAME}`
}

function buildRuntimeRenderSettingsPath(filesDir: string): string {
  return `${buildRuntimeRenderSettingsDirPath(filesDir)}/${RUNTIME_RENDER_SETTINGS_FILE_NAME}`
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (_err) {
    return
  }
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
  } catch (_err) {
    return ''
  }
}
