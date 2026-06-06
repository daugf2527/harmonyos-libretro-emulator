import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface RuntimeAudioSettingsProfile {
  version: number
  latencyMs: number
  updatedAt: number
}

const RUNTIME_AUDIO_SETTINGS_VERSION = 1
const RUNTIME_AUDIO_SETTINGS_DIR_NAME = 'runtime'
const RUNTIME_AUDIO_SETTINGS_FILE_NAME = 'audio_settings.json'

// 音频缓冲延迟预设档位（ms）：0=低延迟（高端真机），1=标准（默认，兼顾），2=高缓冲（模拟器/低端机抗抖动）。
// 越大缓冲越深、抗 callback 抖动越强，但按键到出声的延迟越明显。默认 48ms 在真机手感损失小、
// 又能吸收模拟器 ~100ms 音频 callback 抖动（见 tech-debt D019 / 模拟器 audio_server overTime）。
export const AUDIO_LATENCY_PRESETS: number[] = [16, 48, 96]
const DEFAULT_AUDIO_LATENCY_MS = 48
const MAX_AUDIO_LATENCY_MS = 200

export function createDefaultRuntimeAudioSettingsProfile(): RuntimeAudioSettingsProfile {
  return {
    version: RUNTIME_AUDIO_SETTINGS_VERSION,
    latencyMs: DEFAULT_AUDIO_LATENCY_MS,
    updatedAt: 0
  }
}

export async function loadRuntimeAudioSettingsProfile(
  context: common.UIAbilityContext
): Promise<RuntimeAudioSettingsProfile> {
  const path = buildRuntimeAudioSettingsPath(context.filesDir)
  try {
    const text = await fs.readText(path)
    if (!text || text.length === 0) {
      return createDefaultRuntimeAudioSettingsProfile()
    }
    const parsed = JSON.parse(text) as Partial<RuntimeAudioSettingsProfile> | null
    return normalizeRuntimeAudioSettingsProfile(parsed)
  } catch (_err) {
    return createDefaultRuntimeAudioSettingsProfile()
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
    updatedAt: Number(profile?.updatedAt) || 0
  }
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

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (_err) {
    return
  }
}
