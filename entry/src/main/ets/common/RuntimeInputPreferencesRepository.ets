import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface RuntimeInputPreferencesProfile {
  version: number
  hideVirtualController: boolean
  hideUndeclaredKeys: boolean
  updatedAt: number
}

const RUNTIME_INPUT_PREFS_VERSION = 1
const RUNTIME_INPUT_PREFS_DIR_NAME = 'runtime'
const RUNTIME_INPUT_PREFS_FILE_NAME = 'input_preferences.json'

export function createDefaultRuntimeInputPreferencesProfile(): RuntimeInputPreferencesProfile {
  return {
    version: RUNTIME_INPUT_PREFS_VERSION,
    hideVirtualController: false,
    hideUndeclaredKeys: false,
    updatedAt: 0
  }
}

export async function loadRuntimeInputPreferencesProfile(
  context: common.UIAbilityContext
): Promise<RuntimeInputPreferencesProfile> {
  const path = buildRuntimeInputPreferencesPath(context.filesDir)
  try {
    const text = await fs.readText(path)
    if (!text || text.length === 0) {
      return createDefaultRuntimeInputPreferencesProfile()
    }
    const parsed = JSON.parse(text) as Partial<RuntimeInputPreferencesProfile> | null
    return normalizeRuntimeInputPreferencesProfile(parsed)
  } catch (_err) {
    return createDefaultRuntimeInputPreferencesProfile()
  }
}

export async function saveRuntimeInputPreferencesProfile(
  context: common.UIAbilityContext,
  profile: RuntimeInputPreferencesProfile
): Promise<RuntimeInputPreferencesProfile> {
  await ensureDirExists(buildRuntimeInputPreferencesDirPath(context.filesDir))
  const normalized = normalizeRuntimeInputPreferencesProfile(profile)
  const nextProfile: RuntimeInputPreferencesProfile = {
    version: RUNTIME_INPUT_PREFS_VERSION,
    hideVirtualController: normalized.hideVirtualController,
    hideUndeclaredKeys: normalized.hideUndeclaredKeys,
    updatedAt: Date.now()
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(
      buildRuntimeInputPreferencesPath(context.filesDir),
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

export function normalizeRuntimeInputPreferencesProfile(
  profile: Partial<RuntimeInputPreferencesProfile> | null | undefined
): RuntimeInputPreferencesProfile {
  return {
    version: RUNTIME_INPUT_PREFS_VERSION,
    hideVirtualController: Boolean(profile?.hideVirtualController),
    hideUndeclaredKeys: Boolean(profile?.hideUndeclaredKeys),
    updatedAt: Number(profile?.updatedAt) || 0
  }
}

function buildRuntimeInputPreferencesDirPath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_INPUT_PREFS_DIR_NAME}`
}

function buildRuntimeInputPreferencesPath(filesDir: string): string {
  return `${buildRuntimeInputPreferencesDirPath(filesDir)}/${RUNTIME_INPUT_PREFS_FILE_NAME}`
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path, true)
  } catch (_err) {
    return
  }
}
