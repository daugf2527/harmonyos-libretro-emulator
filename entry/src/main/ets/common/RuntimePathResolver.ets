import { deviceInfo } from '@kit.BasicServicesKit'
import { resourceManager } from '@kit.LocalizationKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import LogHelper from './LogHelper'
import { isNoGameRuntimeRomFile } from './RuntimeRomCatalog'

export interface RuntimeRomPathResolution {
  romPath: string
  useResMgr: boolean
}

export interface RuntimeCorePathResolution {
  corePath: string
  found: boolean
  abi: string
  expectedAbis: string[]
}

export async function resolveRuntimeCorePathInfo(
  bundleCodeDir: string,
  soFile: string
): Promise<RuntimeCorePathResolution> {
  const abiCandidates = buildCoreAbiCandidates()
  for (let index = 0; index < abiCandidates.length; index += 1) {
    const abi = abiCandidates[index]
    const path = `${bundleCodeDir}/libs/${abi}/${soFile}`
    if (await fileExists(path)) {
      LogHelper.info(
        'LibretroGame',
        'Engine',
        `Core path resolved: abi=${abi}, path=${LogHelper.describePathForLog(path)}`
          )
      return {
        corePath: path,
        found: true,
        abi,
        expectedAbis: abiCandidates
      }
    }
  }
  const fallbackAbi = abiCandidates.length > 0 ? abiCandidates[0] : 'arm64'
  const fallback = `${bundleCodeDir}/libs/${fallbackAbi}/${soFile}`
  LogHelper.warn(
    'LibretroGame',
    'Engine',
    `Core path missing for current ABI: ${LogHelper.describePathForLog(fallback)}, abiList=${String(deviceInfo.abiList ?? '')}`
  )
  return {
    corePath: fallback,
    found: false,
    abi: fallbackAbi,
    expectedAbis: abiCandidates
  }
}

export async function resolveRuntimeCorePath(bundleCodeDir: string, soFile: string): Promise<string> {
  const resolved = await resolveRuntimeCorePathInfo(bundleCodeDir, soFile)
  return resolved.corePath
}

export function resolveRuntimeRomPathForSwitch(
  romPath: string,
  resMgr: resourceManager.ResourceManager,
  filesDir: string
): RuntimeRomPathResolution {
  if (!romPath) {
    return { romPath: '', useResMgr: false }
  }
  if (isNoGameRuntimeRomFile(romPath)) {
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

  const hasX64 = rawAbiList.indexOf('x86_64') >= 0
  const hasArm64 = rawAbiList.indexOf('arm64') >= 0 || rawAbiList.indexOf('aarch64') >= 0
  if (hasX64 && !hasArm64) {
    addCandidate('x86_64')
  } else if (hasArm64) {
    addCandidate('arm64')
    addCandidate('arm64-v8a')
  } else {
    addCandidate('arm64')
    addCandidate('arm64-v8a')
    addCandidate('x86_64')
  }
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
