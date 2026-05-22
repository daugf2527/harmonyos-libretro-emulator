import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface RuntimeRenderSettingsProfile {
  version: number
  scalingMode: number
  softwareMaxPresetIndex: number
  hwRenderAllowed: boolean
  updatedAt: number
}

const RUNTIME_RENDER_SETTINGS_VERSION = 1
const RUNTIME_RENDER_SETTINGS_DIR_NAME = 'runtime'
const RUNTIME_RENDER_SETTINGS_FILE_NAME = 'render_settings.json'

export function createDefaultRuntimeRenderSettingsProfile(): RuntimeRenderSettingsProfile {
  return {
    version: RUNTIME_RENDER_SETTINGS_VERSION,
    scalingMode: 2,
    softwareMaxPresetIndex: 1,
    hwRenderAllowed: true,
    updatedAt: 0
  }
}

export async function loadRuntimeRenderSettingsProfile(
  context: common.UIAbilityContext
): Promise<RuntimeRenderSettingsProfile> {
  const path = buildRuntimeRenderSettingsPath(context.filesDir)
  try {
    const text = await fs.readText(path)
    if (!text || text.length === 0) {
      return createDefaultRuntimeRenderSettingsProfile()
    }
    return normalizeRuntimeRenderSettingsProfile(JSON.parse(text) as RuntimeRenderSettingsProfile)
  } catch (_err) {
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
    softwareMaxPresetIndex: normalized.softwareMaxPresetIndex,
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
  } finally {
    if (file) {
      await fs.close(file.fd)
    }
  }
  return nextProfile
}

export function normalizeRuntimeRenderSettingsProfile(
  profile: RuntimeRenderSettingsProfile
): RuntimeRenderSettingsProfile {
  return {
    version: RUNTIME_RENDER_SETTINGS_VERSION,
    scalingMode: clampRenderMode(profile.scalingMode),
    softwareMaxPresetIndex: clampSoftwarePresetIndex(profile.softwareMaxPresetIndex),
    hwRenderAllowed: Boolean(profile.hwRenderAllowed),
    updatedAt: Number(profile.updatedAt) || 0
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

function clampRenderMode(mode: number): number {
  const safeMode = Math.floor(Number(mode) || 0)
  if (safeMode < 0) {
    return 0
  }
  if (safeMode > 2) {
    return 2
  }
  return safeMode
}

function clampSoftwarePresetIndex(index: number): number {
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
