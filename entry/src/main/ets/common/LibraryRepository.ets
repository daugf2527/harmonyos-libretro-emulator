import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import relationalStore from '@ohos.data.relationalStore'
import LogHelper from './LogHelper'

export type LibrarySourceType = 'BUNDLED' | 'IMPORTED'
export type LibraryRecordStatus = 'READY' | 'MISSING'

export interface LibraryRecord {
  id: string
  title: string
  subtitle: string
  platform: string
  coverColor: string
  coverKey: string
  romFile: string
  preferredCoreId: string
  fileName: string
  sourceType: LibrarySourceType
  status: LibraryRecordStatus
  createdAt: number
  importedAt: number
  updatedAt: number
  lastSeenAt: number
  lastPlayedAt: number
  playCount: number
  totalPlayTimeMs: number
  lastSessionDurationMs: number
  lastRuntimeUpdatedAt: number
  lastRuntimeFps: number
  lastRuntimeAudioBufferUsage: number
  lastRuntimeAudioUnderruns: number
  lastRuntimeAudioOverruns: number
  lastRuntimeVideoDrops: number
  lastRuntimeVideoDupes: number
  lastRuntimeVideoNulls: number
}

export interface LibraryRuntimeSnapshot {
  durationMs: number
  fps: number
  audioBufferUsage: number
  audioUnderruns: number
  audioOverruns: number
  videoDrops: number
  videoDupes: number
  videoNulls: number
}

interface LibraryIndexDocument {
  version: number
  records: LibraryRecord[]
}

const LIBRARY_INDEX_VERSION = 2
const LIBRARY_DB_NAME = 'libretro_library.db'
const LIBRARY_TABLE_NAME = 'library_records'
const LIBRARY_DB_VERSION = 2
const LIBRARY_META_TABLE_NAME = 'library_meta'
const LIBRARY_SCHEMA_VERSION_KEY = 'schema_version'

interface RdbStoreCompat {
  executeSql(sql: string): Promise<void>
  querySql(sql: string): Promise<RdbResultSetCompat>
  beginTransaction?(): Promise<void> | void
  commit?(): Promise<void> | void
  rollBack?(): Promise<void> | void
}

interface RdbResultSetCompat {
  goToNextRow(): boolean
  getColumnIndex(name: string): number
  getString(index: number): string
  getLong(index: number): number
  close(): void
}

interface StoreConfigCompat {
  name: string
  securityLevel: number
}

interface RuntimeColumnDefinition {
  name: string
  definition: string
}

let cachedStore: RdbStoreCompat | undefined = undefined
let storePromise: Promise<RdbStoreCompat | undefined> | undefined = undefined
let preferJsonFallback: boolean = false

const RUNTIME_COLUMN_DEFINITIONS: RuntimeColumnDefinition[] = [
  { name: 'total_play_time_ms', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_session_duration_ms', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_updated_at', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_fps', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_audio_buffer_usage', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_audio_underruns', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_audio_overruns', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_video_drops', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_video_dupes', definition: 'INTEGER NOT NULL DEFAULT 0' },
  { name: 'last_runtime_video_nulls', definition: 'INTEGER NOT NULL DEFAULT 0' }
]

export async function syncLibraryIndex(
  context: common.UIAbilityContext,
  discoveredRecords: LibraryRecord[]
): Promise<LibraryRecord[]> {
  const existingRecords = await loadLibraryIndex(context)
  const now = Date.now()
  const existingMap: Map<string, LibraryRecord> = new Map()
  existingRecords.forEach((record: LibraryRecord) => {
    existingMap.set(record.romFile, record)
  })

  const syncedRecords: LibraryRecord[] = []
  discoveredRecords.forEach((record: LibraryRecord) => {
    const existing = existingMap.get(record.romFile)
    syncedRecords.push({
      id: existing?.id ?? record.id,
      title: record.title,
      subtitle: record.subtitle,
      platform: record.platform,
      coverColor: existing?.coverColor ?? record.coverColor,
      coverKey: existing?.coverKey ?? record.coverKey,
      romFile: record.romFile,
      preferredCoreId: record.preferredCoreId,
      fileName: record.fileName,
      sourceType: record.sourceType,
      status: 'READY',
      createdAt: existing?.createdAt ?? now,
      importedAt: existing?.importedAt ?? record.importedAt,
      updatedAt: now,
      lastSeenAt: now,
      lastPlayedAt: existing?.lastPlayedAt ?? 0,
      playCount: existing?.playCount ?? 0,
      totalPlayTimeMs: existing?.totalPlayTimeMs ?? 0,
      lastSessionDurationMs: existing?.lastSessionDurationMs ?? 0,
      lastRuntimeUpdatedAt: existing?.lastRuntimeUpdatedAt ?? 0,
      lastRuntimeFps: existing?.lastRuntimeFps ?? 0,
      lastRuntimeAudioBufferUsage: existing?.lastRuntimeAudioBufferUsage ?? 0,
      lastRuntimeAudioUnderruns: existing?.lastRuntimeAudioUnderruns ?? 0,
      lastRuntimeAudioOverruns: existing?.lastRuntimeAudioOverruns ?? 0,
      lastRuntimeVideoDrops: existing?.lastRuntimeVideoDrops ?? 0,
      lastRuntimeVideoDupes: existing?.lastRuntimeVideoDupes ?? 0,
      lastRuntimeVideoNulls: existing?.lastRuntimeVideoNulls ?? 0
    })
  })

  existingRecords.forEach((record: LibraryRecord) => {
    const stillExists = syncedRecords.findIndex((item: LibraryRecord) => item.romFile === record.romFile) >= 0
    if (stillExists) {
      return
    }
    syncedRecords.push({
      id: record.id,
      title: record.title,
      subtitle: record.subtitle,
      platform: record.platform,
      coverColor: record.coverColor,
      coverKey: record.coverKey,
      romFile: record.romFile,
      preferredCoreId: record.preferredCoreId,
      fileName: record.fileName,
      sourceType: record.sourceType,
      status: 'MISSING',
      createdAt: record.createdAt,
      importedAt: record.importedAt,
      updatedAt: now,
      lastSeenAt: record.lastSeenAt,
      lastPlayedAt: record.lastPlayedAt,
      playCount: record.playCount,
      totalPlayTimeMs: record.totalPlayTimeMs,
      lastSessionDurationMs: record.lastSessionDurationMs,
      lastRuntimeUpdatedAt: record.lastRuntimeUpdatedAt,
      lastRuntimeFps: record.lastRuntimeFps,
      lastRuntimeAudioBufferUsage: record.lastRuntimeAudioBufferUsage,
      lastRuntimeAudioUnderruns: record.lastRuntimeAudioUnderruns,
      lastRuntimeAudioOverruns: record.lastRuntimeAudioOverruns,
      lastRuntimeVideoDrops: record.lastRuntimeVideoDrops,
      lastRuntimeVideoDupes: record.lastRuntimeVideoDupes,
      lastRuntimeVideoNulls: record.lastRuntimeVideoNulls
    })
  })

  await saveLibraryIndex(context, syncedRecords)
  return syncedRecords
}

export function getReadyLibraryRecords(records: LibraryRecord[]): LibraryRecord[] {
  return records.filter((record: LibraryRecord) => record.status === 'READY')
}

export function sortAllLibraryRecords(records: LibraryRecord[]): LibraryRecord[] {
  const copied = [...records]
  copied.sort((left: LibraryRecord, right: LibraryRecord) => {
    if (right.lastPlayedAt !== left.lastPlayedAt) {
      return right.lastPlayedAt - left.lastPlayedAt
    }
    if (right.importedAt !== left.importedAt) {
      return right.importedAt - left.importedAt
    }
    if (right.updatedAt !== left.updatedAt) {
      return right.updatedAt - left.updatedAt
    }
    return left.title.localeCompare(right.title)
  })
  return copied
}

export function buildRecentLibraryRecords(records: LibraryRecord[], count: number): LibraryRecord[] {
  const copied = [...records]
  copied.sort((left: LibraryRecord, right: LibraryRecord) => {
    if (right.lastPlayedAt !== left.lastPlayedAt) {
      return right.lastPlayedAt - left.lastPlayedAt
    }
    if (right.updatedAt !== left.updatedAt) {
      return right.updatedAt - left.updatedAt
    }
    return left.title.localeCompare(right.title)
  })
  return copied.slice(0, count)
}

export async function markLibraryRecordPlayed(
  context: common.UIAbilityContext,
  romFile: string
): Promise<void> {
  const records = await loadLibraryIndex(context)
  const now = Date.now()
  let changed = false
  const nextRecords = records.map((record: LibraryRecord): LibraryRecord => {
    if (record.romFile !== romFile) {
      return record
    }
    changed = true
    return {
      id: record.id,
      title: record.title,
      subtitle: record.subtitle,
      platform: record.platform,
      coverColor: record.coverColor,
      coverKey: record.coverKey,
      romFile: record.romFile,
      preferredCoreId: record.preferredCoreId,
      fileName: record.fileName,
      sourceType: record.sourceType,
      status: record.status,
      createdAt: record.createdAt,
      importedAt: record.importedAt,
      updatedAt: now,
      lastSeenAt: record.lastSeenAt,
      lastPlayedAt: now,
      playCount: record.playCount + 1,
      totalPlayTimeMs: record.totalPlayTimeMs,
      lastSessionDurationMs: record.lastSessionDurationMs,
      lastRuntimeUpdatedAt: record.lastRuntimeUpdatedAt,
      lastRuntimeFps: record.lastRuntimeFps,
      lastRuntimeAudioBufferUsage: record.lastRuntimeAudioBufferUsage,
      lastRuntimeAudioUnderruns: record.lastRuntimeAudioUnderruns,
      lastRuntimeAudioOverruns: record.lastRuntimeAudioOverruns,
      lastRuntimeVideoDrops: record.lastRuntimeVideoDrops,
      lastRuntimeVideoDupes: record.lastRuntimeVideoDupes,
      lastRuntimeVideoNulls: record.lastRuntimeVideoNulls
    }
  })
  if (!changed) {
    return
  }
  await saveLibraryIndex(context, nextRecords)
}

export async function updateLibraryRuntimeSnapshot(
  context: common.UIAbilityContext,
  romFile: string,
  snapshot: LibraryRuntimeSnapshot
): Promise<void> {
  const records = await loadLibraryIndex(context)
  const now = Date.now()
  let changed = false
  const safeDurationMs = Math.max(0, Math.floor(Number(snapshot.durationMs) || 0))
  const nextRecords = records.map((record: LibraryRecord): LibraryRecord => {
    if (record.romFile !== romFile) {
      return record
    }
    changed = true
    return {
      id: record.id,
      title: record.title,
      subtitle: record.subtitle,
      platform: record.platform,
      coverColor: record.coverColor,
      coverKey: record.coverKey,
      romFile: record.romFile,
      preferredCoreId: record.preferredCoreId,
      fileName: record.fileName,
      sourceType: record.sourceType,
      status: record.status,
      createdAt: record.createdAt,
      importedAt: record.importedAt,
      updatedAt: now,
      lastSeenAt: record.lastSeenAt,
      lastPlayedAt: record.lastPlayedAt,
      playCount: record.playCount,
      totalPlayTimeMs: record.totalPlayTimeMs + safeDurationMs,
      lastSessionDurationMs: safeDurationMs,
      lastRuntimeUpdatedAt: now,
      lastRuntimeFps: Number(snapshot.fps) || 0,
      lastRuntimeAudioBufferUsage: Number(snapshot.audioBufferUsage) || 0,
      lastRuntimeAudioUnderruns: Math.max(0, Math.floor(Number(snapshot.audioUnderruns) || 0)),
      lastRuntimeAudioOverruns: Math.max(0, Math.floor(Number(snapshot.audioOverruns) || 0)),
      lastRuntimeVideoDrops: Math.max(0, Math.floor(Number(snapshot.videoDrops) || 0)),
      lastRuntimeVideoDupes: Math.max(0, Math.floor(Number(snapshot.videoDupes) || 0)),
      lastRuntimeVideoNulls: Math.max(0, Math.floor(Number(snapshot.videoNulls) || 0))
    }
  })
  if (!changed) {
    return
  }
  await saveLibraryIndex(context, nextRecords)
}

export async function removeLibraryRecord(
  context: common.UIAbilityContext,
  romFile: string
): Promise<void> {
  const records = await loadLibraryIndex(context)
  const nextRecords = records.filter((record: LibraryRecord) => record.romFile !== romFile)
  await saveLibraryIndex(context, nextRecords)
}

export async function getLibraryRecordByRomFile(
  context: common.UIAbilityContext,
  romFile: string
): Promise<LibraryRecord | undefined> {
  const records = await loadLibraryIndex(context)
  return records.find((record: LibraryRecord) => record.romFile === romFile)
}

export async function updateLibraryRecordCover(
  context: common.UIAbilityContext,
  romFile: string,
  coverKey: string,
  coverColor: string
): Promise<LibraryRecord | undefined> {
  const records = await loadLibraryIndex(context)
  let targetRecord: LibraryRecord | undefined = undefined
  const nextRecords = records.map((record: LibraryRecord): LibraryRecord => {
    if (record.romFile !== romFile) {
      return record
    }
    const nextRecord: LibraryRecord = {
      id: record.id,
      title: record.title,
      subtitle: record.subtitle,
      platform: record.platform,
      coverColor: coverColor,
      coverKey: coverKey,
      romFile: record.romFile,
      preferredCoreId: record.preferredCoreId,
      fileName: record.fileName,
      sourceType: record.sourceType,
      status: record.status,
      createdAt: record.createdAt,
      importedAt: record.importedAt,
      updatedAt: Date.now(),
      lastSeenAt: record.lastSeenAt,
      lastPlayedAt: record.lastPlayedAt,
      playCount: record.playCount,
      totalPlayTimeMs: record.totalPlayTimeMs,
      lastSessionDurationMs: record.lastSessionDurationMs,
      lastRuntimeUpdatedAt: record.lastRuntimeUpdatedAt,
      lastRuntimeFps: record.lastRuntimeFps,
      lastRuntimeAudioBufferUsage: record.lastRuntimeAudioBufferUsage,
      lastRuntimeAudioUnderruns: record.lastRuntimeAudioUnderruns,
      lastRuntimeAudioOverruns: record.lastRuntimeAudioOverruns,
      lastRuntimeVideoDrops: record.lastRuntimeVideoDrops,
      lastRuntimeVideoDupes: record.lastRuntimeVideoDupes,
      lastRuntimeVideoNulls: record.lastRuntimeVideoNulls
    }
    targetRecord = nextRecord
    return nextRecord
  })
  if (!targetRecord) {
    return undefined
  }
  await saveLibraryIndex(context, nextRecords)
  return targetRecord
}

async function loadLibraryIndex(context: common.UIAbilityContext): Promise<LibraryRecord[]> {
  const store = await getLibraryStore(context)
  if (store) {
    return loadRecordsFromRdb(store)
  }
  return loadLibraryIndexFromJson(context.filesDir)
}

async function saveLibraryIndex(context: common.UIAbilityContext, records: LibraryRecord[]): Promise<void> {
  const store = await getLibraryStore(context)
  if (store) {
    await replaceRecordsInRdb(store, records)
    return
  }
  await saveLibraryIndexToJson(context.filesDir, records)
}

async function getLibraryStore(context: common.UIAbilityContext): Promise<RdbStoreCompat | undefined> {
  if (preferJsonFallback) {
    return undefined
  }
  if (cachedStore) {
    return cachedStore
  }
  if (!storePromise) {
    storePromise = openLibraryStore(context)
  }
  const store = await storePromise
  if (store) {
    cachedStore = store
  }
  return store
}

async function openLibraryStore(context: common.UIAbilityContext): Promise<RdbStoreCompat | undefined> {
  const config: StoreConfigCompat = {
    name: LIBRARY_DB_NAME,
    securityLevel: Number(relationalStore.SecurityLevel.S1)
  }
  try {
    const store = await createLibraryStore(context, config)
    await ensureLibrarySchema(store)
    return store
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('LibraryRepository', 'Rdb', `RDB 初始化失败，回退 JSON: ${message}`)
    preferJsonFallback = true
    return undefined
  }
}

async function createLibraryStore(
  context: common.UIAbilityContext,
  config: StoreConfigCompat
): Promise<RdbStoreCompat> {
  return new Promise<RdbStoreCompat>((resolve: (store: RdbStoreCompat) => void, reject: (err: Error) => void) => {
    relationalStore.getRdbStore(context, config, (err, store) => {
      if (err) {
        const businessError = err as BusinessError
        reject(new Error(businessError.message))
        return
      }
      resolve(store as RdbStoreCompat)
    })
  })
}

async function ensureLibrarySchema(store: RdbStoreCompat): Promise<void> {
  const createMetaSql = `
    CREATE TABLE IF NOT EXISTS ${LIBRARY_META_TABLE_NAME} (
      meta_key TEXT PRIMARY KEY,
      meta_value TEXT NOT NULL
    )
  `
  await store.executeSql(createMetaSql)

  const createSql = `
    CREATE TABLE IF NOT EXISTS ${LIBRARY_TABLE_NAME} (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      subtitle TEXT NOT NULL,
      platform TEXT NOT NULL,
      cover_color TEXT NOT NULL,
      cover_key TEXT NOT NULL,
      rom_file TEXT NOT NULL UNIQUE,
      preferred_core_id TEXT NOT NULL,
      file_name TEXT NOT NULL,
      source_type TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      imported_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      last_played_at INTEGER NOT NULL,
      play_count INTEGER NOT NULL,
      total_play_time_ms INTEGER NOT NULL DEFAULT 0,
      last_session_duration_ms INTEGER NOT NULL DEFAULT 0,
      last_runtime_updated_at INTEGER NOT NULL DEFAULT 0,
      last_runtime_fps INTEGER NOT NULL DEFAULT 0,
      last_runtime_audio_buffer_usage INTEGER NOT NULL DEFAULT 0,
      last_runtime_audio_underruns INTEGER NOT NULL DEFAULT 0,
      last_runtime_audio_overruns INTEGER NOT NULL DEFAULT 0,
      last_runtime_video_drops INTEGER NOT NULL DEFAULT 0,
      last_runtime_video_dupes INTEGER NOT NULL DEFAULT 0,
      last_runtime_video_nulls INTEGER NOT NULL DEFAULT 0
    )
  `
  await store.executeSql(createSql)
  await ensureRuntimeColumns(store)

  const clearVersionSql = `DELETE FROM ${LIBRARY_META_TABLE_NAME} WHERE meta_key = '${LIBRARY_SCHEMA_VERSION_KEY}'`
  const insertVersionSql = `
    INSERT INTO ${LIBRARY_META_TABLE_NAME} (meta_key, meta_value)
    VALUES ('${LIBRARY_SCHEMA_VERSION_KEY}', '${LIBRARY_DB_VERSION}')
  `
  await store.executeSql(clearVersionSql)
  await store.executeSql(insertVersionSql)
}

async function ensureRuntimeColumns(store: RdbStoreCompat): Promise<void> {
  const existingColumns: Set<string> = new Set()
  let resultSet: RdbResultSetCompat | undefined = undefined
  try {
    resultSet = await store.querySql(`PRAGMA table_info(${LIBRARY_TABLE_NAME})`)
    while (resultSet.goToNextRow()) {
      existingColumns.add(resultSet.getString(resultSet.getColumnIndex('name')))
    }
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('LibraryRepository', 'Rdb', `读取表结构失败: ${message}`)
  } finally {
    if (resultSet) {
      resultSet.close()
    }
  }
  for (let index = 0; index < RUNTIME_COLUMN_DEFINITIONS.length; index += 1) {
    const column = RUNTIME_COLUMN_DEFINITIONS[index]
    if (existingColumns.has(column.name)) {
      continue
    }
    try {
      await store.executeSql(`ALTER TABLE ${LIBRARY_TABLE_NAME} ADD COLUMN ${column.name} ${column.definition}`)
    } catch (err) {
      const message = (err as Error).message || String(err)
      if (message.toLowerCase().indexOf('duplicate') < 0) {
        throw new Error(message)
      }
    }
  }
}

async function loadRecordsFromRdb(store: RdbStoreCompat): Promise<LibraryRecord[]> {
  let resultSet: RdbResultSetCompat | undefined = undefined
  try {
    resultSet = await store.querySql(`SELECT * FROM ${LIBRARY_TABLE_NAME}`)
    const records: LibraryRecord[] = []
    while (resultSet.goToNextRow()) {
      records.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        title: resultSet.getString(resultSet.getColumnIndex('title')),
        subtitle: resultSet.getString(resultSet.getColumnIndex('subtitle')),
        platform: resultSet.getString(resultSet.getColumnIndex('platform')),
        coverColor: resultSet.getString(resultSet.getColumnIndex('cover_color')),
        coverKey: resultSet.getString(resultSet.getColumnIndex('cover_key')),
        romFile: resultSet.getString(resultSet.getColumnIndex('rom_file')),
        preferredCoreId: resultSet.getString(resultSet.getColumnIndex('preferred_core_id')),
        fileName: resultSet.getString(resultSet.getColumnIndex('file_name')),
        sourceType: resultSet.getString(resultSet.getColumnIndex('source_type')) as LibrarySourceType,
        status: resultSet.getString(resultSet.getColumnIndex('status')) as LibraryRecordStatus,
        createdAt: Number(resultSet.getLong(resultSet.getColumnIndex('created_at'))),
        importedAt: Number(resultSet.getLong(resultSet.getColumnIndex('imported_at'))),
        updatedAt: Number(resultSet.getLong(resultSet.getColumnIndex('updated_at'))),
        lastSeenAt: Number(resultSet.getLong(resultSet.getColumnIndex('last_seen_at'))),
        lastPlayedAt: Number(resultSet.getLong(resultSet.getColumnIndex('last_played_at'))),
        playCount: Number(resultSet.getLong(resultSet.getColumnIndex('play_count'))),
        totalPlayTimeMs: Number(resultSet.getLong(resultSet.getColumnIndex('total_play_time_ms'))),
        lastSessionDurationMs: Number(resultSet.getLong(resultSet.getColumnIndex('last_session_duration_ms'))),
        lastRuntimeUpdatedAt: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_updated_at'))),
        lastRuntimeFps: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_fps'))) / 100,
        lastRuntimeAudioBufferUsage: Number(
          resultSet.getLong(resultSet.getColumnIndex('last_runtime_audio_buffer_usage'))
        ) / 100,
        lastRuntimeAudioUnderruns: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_audio_underruns'))),
        lastRuntimeAudioOverruns: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_audio_overruns'))),
        lastRuntimeVideoDrops: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_video_drops'))),
        lastRuntimeVideoDupes: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_video_dupes'))),
        lastRuntimeVideoNulls: Number(resultSet.getLong(resultSet.getColumnIndex('last_runtime_video_nulls')))
      })
    }
    return records
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('LibraryRepository', 'Rdb', `读取 RDB 失败，返回空记录: ${message}`)
    return []
  } finally {
    if (resultSet) {
      resultSet.close()
    }
  }
}

async function replaceRecordsInRdb(store: RdbStoreCompat, records: LibraryRecord[]): Promise<void> {
  try {
    if (store.beginTransaction && store.commit && store.rollBack) {
      await store.beginTransaction()
      try {
        await replaceRecordsInRdbInternal(store, records)
        await store.commit()
        return
      } catch (err) {
        await store.rollBack()
        const rollbackMessage = (err as Error).message || String(err)
        LogHelper.error('LibraryRepository', 'Rdb', `事务写入回滚: ${rollbackMessage}`)
        return
      }
    }
    await replaceRecordsInRdbInternal(store, records)
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('LibraryRepository', 'Rdb', `写入 RDB 失败: ${message}`)
  }
}

async function replaceRecordsInRdbInternal(store: RdbStoreCompat, records: LibraryRecord[]): Promise<void> {
  await store.executeSql(`DELETE FROM ${LIBRARY_TABLE_NAME}`)
  for (let index = 0; index < records.length; index += 1) {
    const record = records[index]
    await store.executeSql(buildInsertSql(record))
  }
}

function buildInsertSql(record: LibraryRecord): string {
  return `
    INSERT INTO ${LIBRARY_TABLE_NAME} (
      id, title, subtitle, platform, cover_color, cover_key, rom_file,
      preferred_core_id, file_name, source_type, status, created_at,
      imported_at, updated_at, last_seen_at, last_played_at, play_count,
      total_play_time_ms, last_session_duration_ms, last_runtime_updated_at,
      last_runtime_fps, last_runtime_audio_buffer_usage,
      last_runtime_audio_underruns, last_runtime_audio_overruns,
      last_runtime_video_drops, last_runtime_video_dupes, last_runtime_video_nulls
    ) VALUES (
      '${escapeSql(record.id)}',
      '${escapeSql(record.title)}',
      '${escapeSql(record.subtitle)}',
      '${escapeSql(record.platform)}',
      '${escapeSql(record.coverColor)}',
      '${escapeSql(record.coverKey)}',
      '${escapeSql(record.romFile)}',
      '${escapeSql(record.preferredCoreId)}',
      '${escapeSql(record.fileName)}',
      '${escapeSql(record.sourceType)}',
      '${escapeSql(record.status)}',
      ${record.createdAt},
      ${record.importedAt},
      ${record.updatedAt},
      ${record.lastSeenAt},
      ${record.lastPlayedAt},
      ${record.playCount},
      ${record.totalPlayTimeMs},
      ${record.lastSessionDurationMs},
      ${record.lastRuntimeUpdatedAt},
      ${Math.round(record.lastRuntimeFps * 100)},
      ${Math.round(record.lastRuntimeAudioBufferUsage * 100)},
      ${record.lastRuntimeAudioUnderruns},
      ${record.lastRuntimeAudioOverruns},
      ${record.lastRuntimeVideoDrops},
      ${record.lastRuntimeVideoDupes},
      ${record.lastRuntimeVideoNulls}
    )
  `
}

function escapeSql(value: string): string {
  return value.replace(/'/g, "''")
}

async function loadLibraryIndexFromJson(filesDir: string): Promise<LibraryRecord[]> {
  const indexPath = buildIndexPath(filesDir)
  try {
    const text = await fs.readText(indexPath)
    if (!text || text.length === 0) {
      return []
    }
    const parsed = JSON.parse(text) as LibraryIndexDocument
    if (!parsed.records || parsed.records.length === 0) {
      return []
    }
    return parsed.records.map((record: LibraryRecord) => normalizeRecord(record))
  } catch (err) {
    return []
  }
}

async function saveLibraryIndexToJson(filesDir: string, records: LibraryRecord[]): Promise<void> {
  const dirPath = `${filesDir}/library`
  await ensureDirExists(dirPath)
  const indexPath = buildIndexPath(filesDir)
  const document: LibraryIndexDocument = {
    version: LIBRARY_INDEX_VERSION,
    records: records
  }
  let file: fs.File | undefined = undefined
  try {
    file = await fs.open(indexPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    await fs.write(file.fd, JSON.stringify(document, null, 2))
  } catch (err) {
    const message = (err as Error).message || String(err)
    LogHelper.error('LibraryRepository', 'Save', `保存 JSON 索引失败: ${message}`)
  } finally {
    if (file) {
      await fs.close(file.fd)
    }
  }
}

function normalizeRecord(record: LibraryRecord): LibraryRecord {
  return {
    id: record.id,
    title: record.title,
    subtitle: record.subtitle,
    platform: record.platform,
    coverColor: record.coverColor,
    coverKey: record.coverKey,
    romFile: record.romFile,
    preferredCoreId: record.preferredCoreId,
    fileName: record.fileName,
    sourceType: record.sourceType,
    status: record.status,
    createdAt: Number(record.createdAt) || 0,
    importedAt: Number(record.importedAt) || 0,
    updatedAt: Number(record.updatedAt) || 0,
    lastSeenAt: Number(record.lastSeenAt) || 0,
    lastPlayedAt: Number(record.lastPlayedAt) || 0,
    playCount: Number(record.playCount) || 0,
    totalPlayTimeMs: Number(record.totalPlayTimeMs) || 0,
    lastSessionDurationMs: Number(record.lastSessionDurationMs) || 0,
    lastRuntimeUpdatedAt: Number(record.lastRuntimeUpdatedAt) || 0,
    lastRuntimeFps: Number(record.lastRuntimeFps) || 0,
    lastRuntimeAudioBufferUsage: Number(record.lastRuntimeAudioBufferUsage) || 0,
    lastRuntimeAudioUnderruns: Number(record.lastRuntimeAudioUnderruns) || 0,
    lastRuntimeAudioOverruns: Number(record.lastRuntimeAudioOverruns) || 0,
    lastRuntimeVideoDrops: Number(record.lastRuntimeVideoDrops) || 0,
    lastRuntimeVideoDupes: Number(record.lastRuntimeVideoDupes) || 0,
    lastRuntimeVideoNulls: Number(record.lastRuntimeVideoNulls) || 0
  }
}

function buildIndexPath(filesDir: string): string {
  return `${filesDir}/library/library_index.json`
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fs.mkdir(path)
  } catch (err) {
    return
  }
}
