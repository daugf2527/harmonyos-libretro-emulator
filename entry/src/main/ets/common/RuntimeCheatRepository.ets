import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'

export interface RuntimeCheatItem {
  id: string
  label: string
  code: string
  enabled: boolean
  updatedAt: number
}

interface RuntimeCheatRomEntry {
  romFile: string
  items: RuntimeCheatItem[]
  updatedAt: number
}

interface RuntimeCheatStore {
  version: number
  roms: RuntimeCheatRomEntry[]
  updatedAt: number
}

const RUNTIME_CHEAT_STORE_VERSION = 1
const RUNTIME_CHEAT_DIR_NAME = 'runtime'
const RUNTIME_CHEAT_FILE_NAME = 'cheats.json'
const MAX_RUNTIME_CHEAT_ITEMS = 1024
const MAX_RUNTIME_CHEAT_CODE_LENGTH = 240
const MAX_RUNTIME_CHEAT_LABEL_LENGTH = 80
const MAX_RUNTIME_CHEAT_ID_LENGTH = 96
const MAX_RUNTIME_CHEAT_ROM_FILE_LENGTH = 512

export function createRuntimeCheatItem(
  label: string,
  code: string,
  enabled: boolean = true
): RuntimeCheatItem {
  return normalizeRuntimeCheatItem({
    label,
    code,
    enabled,
    updatedAt: Date.now()
  }, 0)
}

export async function loadRuntimeCheatItemsForRom(
  context: common.UIAbilityContext,
  romFile: string
): Promise<RuntimeCheatItem[]> {
  const normalizedRomFile = normalizeRomFile(romFile)
  if (normalizedRomFile.length === 0) {
    return []
  }

  const store = await loadRuntimeCheatStore(context)
  const entry = store.roms.find((item: RuntimeCheatRomEntry) => item.romFile === normalizedRomFile)
  return entry ? entry.items : []
}

export async function saveRuntimeCheatItemsForRom(
  context: common.UIAbilityContext,
  romFile: string,
  items: RuntimeCheatItem[]
): Promise<RuntimeCheatItem[]> {
  const normalizedRomFile = normalizeRomFile(romFile)
  if (normalizedRomFile.length === 0) {
    throw new Error('rom context missing')
  }

  const store = await loadRuntimeCheatStore(context)
  const normalizedItems = normalizeRuntimeCheatItems(items)
  const nextEntries: RuntimeCheatRomEntry[] = []
  let replaced = false
  const nextUpdatedAt = Date.now()

  store.roms.forEach((entry: RuntimeCheatRomEntry) => {
    if (entry.romFile === normalizedRomFile) {
      if (!replaced && normalizedItems.length > 0) {
        nextEntries.push({
          romFile: normalizedRomFile,
          items: normalizedItems,
          updatedAt: nextUpdatedAt
        })
      }
      replaced = true
      return
    }
    nextEntries.push(entry)
  })

  if (!replaced && normalizedItems.length > 0) {
    nextEntries.push({
      romFile: normalizedRomFile,
      items: normalizedItems,
      updatedAt: nextUpdatedAt
    })
  }

  await ensureDirExists(buildRuntimeCheatDirPath(context.filesDir))

  const nextStore: RuntimeCheatStore = {
    version: RUNTIME_CHEAT_STORE_VERSION,
    roms: nextEntries,
    updatedAt: nextUpdatedAt
  }

  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(
      buildRuntimeCheatPath(context.filesDir),
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    )
    await fs.write(file.fd, JSON.stringify(nextStore, null, 2))
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

  return normalizedItems
}

async function loadRuntimeCheatStore(
  context: common.UIAbilityContext
): Promise<RuntimeCheatStore> {
  const path = buildRuntimeCheatPath(context.filesDir)
  const text = await readOptionalText(path)
  if (!text || text.length === 0) {
    return createDefaultRuntimeCheatStore()
  }
  try {
    const parsed = JSON.parse(text) as Partial<RuntimeCheatStore> | null
    return normalizeRuntimeCheatStore(parsed)
  } catch (_err) {
    return createDefaultRuntimeCheatStore()
  }
}

function createDefaultRuntimeCheatStore(): RuntimeCheatStore {
  return {
    version: RUNTIME_CHEAT_STORE_VERSION,
    roms: [],
    updatedAt: 0
  }
}

function normalizeRuntimeCheatStore(
  store: Partial<RuntimeCheatStore> | null | undefined
): RuntimeCheatStore {
  const normalizedEntries: RuntimeCheatRomEntry[] = []
  let entries: RuntimeCheatRomEntry[] = []
  if (store && Array.isArray(store.roms)) {
    entries = store.roms as RuntimeCheatRomEntry[]
  }
  entries.forEach((entry: RuntimeCheatRomEntry | Partial<RuntimeCheatRomEntry>, index: number) => {
    const normalizedEntry = normalizeRuntimeCheatRomEntry(entry, index)
    if (normalizedEntry) {
      normalizedEntries.push(normalizedEntry)
    }
  })

  return {
    version: RUNTIME_CHEAT_STORE_VERSION,
    roms: normalizedEntries,
    updatedAt: Number(store?.updatedAt) || 0
  }
}

function normalizeRuntimeCheatRomEntry(
  entry: RuntimeCheatRomEntry | Partial<RuntimeCheatRomEntry> | null | undefined,
  _index: number
): RuntimeCheatRomEntry | undefined {
  const romFile = normalizeRomFile(entry?.romFile)
  if (romFile.length === 0) {
    return undefined
  }

  let rawItems: RuntimeCheatItem[] = []
  if (entry && Array.isArray(entry.items)) {
    rawItems = entry.items as RuntimeCheatItem[]
  }
  const items = normalizeRuntimeCheatItems(rawItems)
  if (items.length === 0) {
    return undefined
  }

  return {
    romFile,
    items,
    updatedAt: Number(entry?.updatedAt) || 0
  }
}

function normalizeRuntimeCheatItems(items: RuntimeCheatItem[]): RuntimeCheatItem[] {
  const normalizedItems: RuntimeCheatItem[] = []
  items.forEach((item: RuntimeCheatItem, index: number) => {
    if (normalizedItems.length >= MAX_RUNTIME_CHEAT_ITEMS) {
      return
    }
    const normalized = normalizeRuntimeCheatItem(item, index)
    if (normalized.code.length > 0) {
      normalizedItems.push(normalized)
    }
  })
  return normalizedItems
}

function normalizeRuntimeCheatItem(
  item: Partial<RuntimeCheatItem> | null | undefined,
  index: number
): RuntimeCheatItem {
  const updatedAt = normalizeUpdatedAt(item?.updatedAt)
  const label = normalizeTextField(item?.label, MAX_RUNTIME_CHEAT_LABEL_LENGTH)
  const code = normalizeCheatCode(item?.code)

  return {
    id: normalizeCheatId(item?.id, index, updatedAt),
    label: label.length > 0 ? label : `金手指 ${index + 1}`,
    code,
    enabled: item?.enabled === true,
    updatedAt
  }
}

function normalizeCheatId(
  id: string | undefined,
  index: number,
  updatedAt: number
): string {
  const normalizedId = normalizeTextField(id, MAX_RUNTIME_CHEAT_ID_LENGTH)
  if (normalizedId.length > 0) {
    return normalizedId
  }
  return `runtime-cheat-${updatedAt}-${index}`
}

function normalizeUpdatedAt(updatedAt: number | undefined): number {
  const safe = Math.floor(Number(updatedAt) || 0)
  return safe > 0 ? safe : Date.now()
}

function normalizeRomFile(romFile: string | undefined): string {
  const normalized = normalizeTextField(romFile, MAX_RUNTIME_CHEAT_ROM_FILE_LENGTH)
  if (normalized.includes('\u0000') || normalized.includes('..') || normalized.includes('\\')) {
    return ''
  }
  return normalized
}

function normalizeTextField(value: string | undefined, maxLength: number): string {
  if (typeof value !== 'string') {
    return ''
  }
  const withoutControls = value.replace(/[\u0000-\u001F\u007F]/g, '').trim()
  return withoutControls.length > maxLength ? withoutControls.substring(0, maxLength) : withoutControls
}

function normalizeCheatCode(code: string | undefined): string {
  if (typeof code !== 'string') {
    return ''
  }
  let normalized = ''
  const trimmed = code.trim()
  for (let index = 0; index < trimmed.length && normalized.length < MAX_RUNTIME_CHEAT_CODE_LENGTH; index++) {
    const charCode = trimmed.charCodeAt(index)
    if (charCode >= 0x20 && charCode <= 0x7E) {
      normalized += trimmed.charAt(index)
    }
  }
  return normalized
}

function buildRuntimeCheatDirPath(filesDir: string): string {
  return `${filesDir}/${RUNTIME_CHEAT_DIR_NAME}`
}

function buildRuntimeCheatPath(filesDir: string): string {
  return `${buildRuntimeCheatDirPath(filesDir)}/${RUNTIME_CHEAT_FILE_NAME}`
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
