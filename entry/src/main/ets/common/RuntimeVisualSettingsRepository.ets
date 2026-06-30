import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export type RuntimeAspectMode = 'native' | '4:3' | '16:9'

export interface RuntimeVisualSettingsProfile {
  version: number
  aspectMode: RuntimeAspectMode
  scanlineIntensity: number
  curvature: number
  saturation: number
  updatedAt: number
}

interface RuntimeVisualSettingsFileErrorWithCode {
  code?: string | number
}

const RUNTIME_VISUAL_SETTINGS_VERSION = 1
const RUNTIME_VISUAL_SETTINGS_DIR_NAME = 'runtime'
const RUNTIME_VISUAL_SETTINGS_FILE_NAME = 'visual_settings.json'
const DEFAULT_SATURATION = 100

export function createDefaultRuntimeVisualSettingsProfile(): RuntimeVisualSettingsProfile {
  return {
    version: RUNTIME_VISUAL_SETTINGS_VERSION,
    aspectMode: 'native',
    scanlineIntensity: 0,
    curvature: 0,
    saturation: DEFAULT_SATURATION,
    updatedAt: 0
  }
}

export async function loadRuntimeVisualSettingsProfile(
  context: common.UIAbilityContext
): Promise<RuntimeVisualSettingsProfile> {
  const path = buildRuntimeVisualSettingsPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createDefaultRuntimeVisualSettingsProfile()
  }
  try {
    const parsed = JSON.parse(text) as Partial<RuntimeVisualSettingsProfile> | null
    if (!isRuntimeVisualSettingsProfileShapeValid(parsed)) {
      throw new Error('runtime_visual_settings_invalid')
    }
    return normalizeRuntimeVisualSettingsProfile(parsed)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeVisualSettingsRepository', 'Load', `视觉配置读取失败: ${message}`)
    throw err as Error
  }
}

export async function saveRuntimeVisualSettingsProfile(
  context: common.UIAbilityContext,
  profile: RuntimeVisualSettingsProfile
): Promise<RuntimeVisualSettingsProfile> {
  await ensureDirExists(buildRuntimeVisualSettingsDirPath(context.filesDir))
  const normalized = normalizeRuntimeVisualSettingsProfile(profile)
  const nextProfile: RuntimeVisualSettingsProfile = {
    version: RUNTIME_VISUAL_SETTINGS_VERSION,
    aspectMode: normalized.aspectMode,
    scanlineIntensity: normalized.scanlineIntensity,
    curvature: normalized.curvature,
    saturation: normalized.saturation,
    updatedAt: Date.now()
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(
      buildRuntimeVisualSettingsPath(context.filesDir),
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

export function normalizeRuntimeVisualSettingsProfile(
  profile: Partial<RuntimeVisualSettingsProfile> | null | undefined
): RuntimeVisualSettingsProfile {
  return {
    version: RUNTIME_VISUAL_SETTINGS_VERSION,
    aspectMode: normalizeAspectMode(profile?.aspectMode),
    scanlineIntensity: clampPercent(profile?.scanlineIntensity, 100, 0),
    curvature: clampPercent(profile?.curvature, 100, 0),
    saturation: clampPercent(profile?.saturation, 200, DEFAULT_SATURATION),
    updatedAt: Number(profile?.updatedAt) || 0
  }
}

function isRuntimeVisualSettingsProfileShapeValid(
  profile: Partial<RuntimeVisualSettingsProfile> | null | undefined
): boolean {
  if (!profile || typeof profile !== 'object') {
    return false
  }
  return profile.version !== undefined &&
    profile.updatedAt !== undefined &&
    profile.aspectMode !== undefined &&
    profile.scanlineIntensity !== undefined &&
    profile.curvature !== undefined &&
    profile.saturation !== undefined
}

export function resolveRuntimeVisualAspectRatio(
  mode: RuntimeAspectMode,
  nativeAspectRatio: number
): number {
  const safeMode = normalizeAspectMode(mode)
  const safeNativeAspectRatio = Number.isFinite(nativeAspectRatio) && nativeAspectRatio > 0 ?
    nativeAspectRatio :
    4 / 3
  if (safeMode === '4:3') {
    return 4 / 3
  }
  if (safeMode === '16:9') {
    return 16 / 9
  }
  return safeNativeAspectRatio
}

export function describeRuntimeAspectMode(mode: RuntimeAspectMode): string {
  const safeMode = normalizeAspectMode(mode)
  if (safeMode === '4:3') {
    return '4:3'
  }
  if (safeMode === '16:9') {
    return '16:9'
  }
  return 'Native'
}

function normalizeAspectMode(mode: RuntimeAspectMode | string | undefined): RuntimeAspectMode {
  if (mode === '4:3' || mode === '16:9') {
    return mode
  }
  return 'native'
}

function clampPercent(value: number | undefined, max: number, fallback: number): number {
  const safe = Math.floor(Number(value))
  if (!Number.isFinite(safe)) {
    return fallback
  }
  if (safe < 0) {
    return 0
  }
  if (safe > max) {
    return max
  }
  return safe
}

function buildRuntimeVisualSettingsDirPath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_VISUAL_SETTINGS_DIR_NAME}`
}

function buildRuntimeVisualSettingsPath(filesDir: string): string {
  return `${buildRuntimeVisualSettingsDirPath(filesDir)}/${RUNTIME_VISUAL_SETTINGS_FILE_NAME}`
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
  } catch (err) {
    if (isMissingFileError(err)) {
      return false
    }
    throw err as Error
  }
}

async function readOptionalText(path: string): Promise<string> {
  if (!(await fileExists(path))) {
    return ''
  }
  try {
    return await fs.readText(path)
  } catch (err) {
    if (isMissingFileError(err)) {
      return ''
    }
    throw err as Error
  }
}

function isMissingFileError(err: Error | RuntimeVisualSettingsFileErrorWithCode): boolean {
  const errorCode = (err as RuntimeVisualSettingsFileErrorWithCode).code
  if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
    return true
  }
  const message = (err as Error).message || String(err)
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}
