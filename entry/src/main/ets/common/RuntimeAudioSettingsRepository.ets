import { deviceInfo } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface RuntimeAudioSettingsProfile {
  version: number
  latencyMs: number
  volumePercent: number
  updatedAt: number
}

interface RuntimeAudioSettingsFileErrorWithCode {
  code?: string | number
}

const RUNTIME_AUDIO_SETTINGS_VERSION = 2
const RUNTIME_AUDIO_SETTINGS_DIR_NAME = 'runtime'
const RUNTIME_AUDIO_SETTINGS_FILE_NAME = 'audio_settings.json'

// 音频缓冲延迟预设档位（ms）：0=低延迟，1=标准，2=高缓冲（模拟器抗 underrun）。
// [2026-06-08 D025/C-F1] 原 [16,48,96] 全 < C++ 端 profile 缓冲地板（device 100ms /
// emulator 250ms，见 audio_bridge.cpp kMinBufferMsDevice/Emulator）；SetMinimumLatencyMs
// 做 max(目标,地板) 只升不降 → 三档在两个平台全被地板钳死、对模拟器(underrun 发生地)
// 零影响 = placebo（连"高缓冲 模拟器抗抖动"档 96ms 都低于 250ms 地板）。
// 现把高缓冲抬到 300ms（> emulator 250 地板）使其真正生效；默认仍 48（靠地板兜底，真机低延迟
// 手感不变）；标准 128 在真机(100地板)之上加缓冲。MAX→400 给高缓冲留头寸
// （400ms=19200帧 << RingBuffer 48000帧容量，安全）。改动需 DevEco + 模拟器实测抗 underrun。
export const AUDIO_LATENCY_PRESETS: number[] = [48, 128, 300]
const DEFAULT_AUDIO_LATENCY_MS = resolveDefaultAudioLatencyMs()
const MAX_AUDIO_LATENCY_MS = 400
const DEFAULT_AUDIO_VOLUME_PERCENT = 100

export function createDefaultRuntimeAudioSettingsProfile(): RuntimeAudioSettingsProfile {
  return {
    version: RUNTIME_AUDIO_SETTINGS_VERSION,
    latencyMs: DEFAULT_AUDIO_LATENCY_MS,
    volumePercent: DEFAULT_AUDIO_VOLUME_PERCENT,
    updatedAt: 0
  }
}

export async function loadRuntimeAudioSettingsProfile(
  context: common.UIAbilityContext
): Promise<RuntimeAudioSettingsProfile> {
  const path = buildRuntimeAudioSettingsPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createDefaultRuntimeAudioSettingsProfile()
  }
  try {
    const parsed = JSON.parse(text) as Partial<RuntimeAudioSettingsProfile> | null
    if (!isRuntimeAudioSettingsProfileShapeValid(parsed)) {
      throw new Error('runtime_audio_settings_invalid')
    }
    return normalizeRuntimeAudioSettingsProfile(parsed)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.warn('RuntimeAudioSettingsRepository', 'Load', `音频配置读取失败: ${message}`)
    throw err as Error
  }
}

export async function saveRuntimeAudioSettingsProfile(
  context: common.UIAbilityContext,
  profile: RuntimeAudioSettingsProfile
): Promise<RuntimeAudioSettingsProfile> {
  await ensureDirExists(buildRuntimeAudioSettingsDirPath(context.filesDir))
  const normalized = normalizeRuntimeAudioSettingsProfile(profile)
  const nextProfile: RuntimeAudioSettingsProfile = {
    version: RUNTIME_AUDIO_SETTINGS_VERSION,
    latencyMs: normalized.latencyMs,
    volumePercent: normalized.volumePercent,
    updatedAt: Date.now()
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(
      buildRuntimeAudioSettingsPath(context.filesDir),
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

export function normalizeRuntimeAudioSettingsProfile(
  profile: Partial<RuntimeAudioSettingsProfile> | null | undefined
): RuntimeAudioSettingsProfile {
  return {
    version: RUNTIME_AUDIO_SETTINGS_VERSION,
    latencyMs: clampLatency(profile?.latencyMs),
    volumePercent: clampVolumePercent(profile?.volumePercent),
    updatedAt: Number(profile?.updatedAt) || 0
  }
}

function isRuntimeAudioSettingsProfileShapeValid(
  profile: Partial<RuntimeAudioSettingsProfile> | null | undefined
): boolean {
  if (!profile || typeof profile !== 'object') {
    return false
  }
  return profile.version !== undefined &&
    profile.updatedAt !== undefined &&
    profile.latencyMs !== undefined &&
    profile.volumePercent !== undefined
}

export function getAudioLatencyForPreset(index: number): number {
  const safeIndex = clampPresetIndex(index)
  return AUDIO_LATENCY_PRESETS[safeIndex]
}

// 把任意 latencyMs 反查到最接近的预设档位（用于 SettingsPage cycle 显示当前档）。
export function getAudioLatencyPresetIndex(latencyMs: number): number {
  const safe = clampLatency(latencyMs)
  let bestIndex = 0
  let bestDelta = Math.abs(AUDIO_LATENCY_PRESETS[0] - safe)
  for (let i = 1; i < AUDIO_LATENCY_PRESETS.length; i++) {
    const delta = Math.abs(AUDIO_LATENCY_PRESETS[i] - safe)
    if (delta < bestDelta) {
      bestDelta = delta
      bestIndex = i
    }
  }
  return bestIndex
}

export function describeAudioLatency(latencyMs: number): string {
  const safe = clampLatency(latencyMs)
  const index = getAudioLatencyPresetIndex(safe)
  if (index === 0) {
    return `低延迟 (${safe}ms)`
  }
  if (index === 2) {
    return `高缓冲 (${safe}ms)`
  }
  return `标准 (${safe}ms)`
}

function clampLatency(latencyMs: number | undefined): number {
  const safe = Math.floor(Number(latencyMs))
  if (!Number.isFinite(safe) || safe < 0) {
    return DEFAULT_AUDIO_LATENCY_MS
  }
  if (safe > MAX_AUDIO_LATENCY_MS) {
    return MAX_AUDIO_LATENCY_MS
  }
  return safe
}

function clampVolumePercent(volumePercent: number | undefined): number {
  const safe = Math.floor(Number(volumePercent))
  if (!Number.isFinite(safe)) {
    return DEFAULT_AUDIO_VOLUME_PERCENT
  }
  if (safe < 0) {
    return 0
  }
  if (safe > 100) {
    return 100
  }
  return safe
}

function clampPresetIndex(index: number | undefined): number {
  const safe = Math.floor(Number(index) || 0)
  if (safe < 0) {
    return 0
  }
  if (safe >= AUDIO_LATENCY_PRESETS.length) {
    return AUDIO_LATENCY_PRESETS.length - 1
  }
  return safe
}

function buildRuntimeAudioSettingsDirPath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_AUDIO_SETTINGS_DIR_NAME}`
}

function buildRuntimeAudioSettingsPath(filesDir: string): string {
  return `${buildRuntimeAudioSettingsDirPath(filesDir)}/${RUNTIME_AUDIO_SETTINGS_FILE_NAME}`
}

function resolveDefaultAudioLatencyMs(): number {
  const rawAbiList = String(deviceInfo.abiList ?? '').toLowerCase()
  return rawAbiList.indexOf('x86_64') >= 0 ? AUDIO_LATENCY_PRESETS[2] : AUDIO_LATENCY_PRESETS[0]
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

function isMissingFileError(err: Error | RuntimeAudioSettingsFileErrorWithCode): boolean {
  const errorCode = (err as RuntimeAudioSettingsFileErrorWithCode).code
  if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
    return true
  }
  const message = (err as Error).message || String(err)
  const normalized = message.toLowerCase()
  return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
}
