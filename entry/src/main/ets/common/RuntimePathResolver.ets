import { deviceInfo } from '@kit.BasicServicesKit'
import { resourceManager } from '@kit.LocalizationKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'

export interface RuntimeRomPathResolution {
  romPath: string
  useResMgr: boolean
}

export async function resolveRuntimeCorePath(bundleCodeDir: string, soFile: string): Promise<string> {
  const abiCandidates = buildCoreAbiCandidates()
  for (let index = 0; index < abiCandidates.length; index += 1) {
    const abi = abiCandidates[index]
    const path = `${bundleCodeDir}/libs/${abi}/${soFile}`
    if (await fileExists(path)) {
      LogHelper.info('LibretroGame', 'Engine', `Core path resolved: abi=${abi}, path=${path}`)
      return path
    }
  }
  const fallback = `${bundleCodeDir}/libs/${abiCandidates[0]}/${soFile}`
  LogHelper.warn(
    'LibretroGame',
    'Engine',
    `Core path fallback (not found): ${fallback}, abiList=${String(deviceInfo.abiList ?? '')}`
  )
  return fallback
}

export function resolveRuntimeRomPathForSwitch(
  romPath: string,
  resMgr: resourceManager.ResourceManager,
  filesDir: string
): RuntimeRomPathResolution {
  if (!romPath) {
    return { romPath: '', useResMgr: false }
  }
  if (!isRawfilePath(romPath)) {
    return { romPath, useResMgr: false }
  }
  // 对 rawfile ROM 一律走 native RawfileRomProcessor，避免前端落地路径不一致。
  // native 侧会按需写入 temp_roms，并返回可用的 fullpath（兼容 need_fullpath core）。
  void resMgr
  void filesDir
  return { romPath, useResMgr: true }
}

function buildCoreAbiCandidates(): string[] {
  const rawAbiList = String(deviceInfo.abiList ?? '').toLowerCase()
  const candidates: string[] = []
  const addCandidate = (abi: string) => {
    if (!abi || candidates.indexOf(abi) >= 0) {
      return
    }
    candidates.push(abi)
  }

  if (rawAbiList.indexOf('x86_64') >= 0) {
    addCandidate('x86_64')
  } else {
    addCandidate('arm64')
    addCandidate('arm64-v8a')
  }
  addCandidate('arm64')
  addCandidate('arm64-v8a')
  addCandidate('x86_64')
  return candidates
}

function isRawfilePath(path: string): boolean {
  return path.startsWith('roms/')
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await fs.access(path)
    return true
  } catch (err) {
    return false
  }
}
