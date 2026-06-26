/**
 * M1 Phase 3: GameMetadataRepository → LibraryRepository 数据迁移
 *
 * 目标：将 GameMetadataRepository 的 3 个字段合并到 LibraryRepository
 * - releaseYear
 * - publisher
 * - overview (暂不合并，保留在 metadata 作为扩展字段)
 *
 * 冲突解决策略：
 * - 优先保留 LibraryRecord 中已有的非空值（用户可能手动编辑过）
 * - GameMetadataRecord 的值作为补充
 */

import { common } from '@kit.AbilityKit'
import LogHelper from './LogHelper'
import {
  GameMetadataRecord,
  loadGameMetadataIndex
} from './GameMetadataRepository'
import {
  LibraryRecord,
  loadAllLibraryRecords,
  upsertLibraryRecord
} from './LibraryRepository'

export interface MigrationResult {
  totalLibraryRecords: number
  totalMetadataRecords: number
  migratedCount: number
  skippedCount: number
  errorCount: number
  errors: string[]
}

/**
 * 执行数据迁移
 * @param context UIAbilityContext
 * @param dryRun 是否为试运行（不实际写入）
 * @returns 迁移结果统计
 */
export async function migrateGameMetadataToLibrary(
  context: common.UIAbilityContext,
  dryRun: boolean = false
): Promise<MigrationResult> {
  const result: MigrationResult = {
    totalLibraryRecords: 0,
    totalMetadataRecords: 0,
    migratedCount: 0,
    skippedCount: 0,
    errorCount: 0,
    errors: []
  }

  try {
    // 1. 加载两个 Repository 的数据
    const libraryRecords = await loadAllLibraryRecords(context)
    const metadataRecords = await loadGameMetadataIndex(context)

    result.totalLibraryRecords = libraryRecords.length
    result.totalMetadataRecords = metadataRecords.length

    LogHelper.info(
      `[Migration] Start: ${result.totalLibraryRecords} library records, ${result.totalMetadataRecords} metadata records, dryRun=${dryRun}`
    )

    // 2. 构建 romFile → GameMetadataRecord 映射
    const metadataMap = new Map<string, GameMetadataRecord>()
    metadataRecords.forEach((metadata: GameMetadataRecord) => {
      const key = normalizeRomFileKey(metadata.romFile)
      metadataMap.set(key, metadata)
    })

    // 3. 遍历 LibraryRecord，合并 metadata 字段
    for (const record of libraryRecords) {
      const key = normalizeRomFileKey(record.romFile)
      const metadata = metadataMap.get(key)

      if (!metadata) {
        // 没有对应的 metadata，跳过
        result.skippedCount++
        continue
      }

      // 检查是否需要迁移
      const needsMigration = shouldMigrateRecord(record, metadata)
      if (!needsMigration) {
        result.skippedCount++
        continue
      }

      // 合并字段
      const mergedRecord = mergeMetadataIntoLibraryRecord(record, metadata)

      // 写入（如果不是 dryRun）
      if (!dryRun) {
        try {
          await upsertLibraryRecord(context, mergedRecord)
          result.migratedCount++
          LogHelper.info(
            `[Migration] Migrated: ${record.romFile} (releaseYear=${mergedRecord.releaseYear}, publisher=${mergedRecord.publisher})`
          )
        } catch (err) {
          result.errorCount++
          const errorMsg = `Failed to migrate ${record.romFile}: ${(err as Error).message}`
          result.errors.push(errorMsg)
          LogHelper.error(`[Migration] ${errorMsg}`)
        }
      } else {
        result.migratedCount++
        LogHelper.info(
          `[Migration] [DRY-RUN] Would migrate: ${record.romFile} (releaseYear=${mergedRecord.releaseYear}, publisher=${mergedRecord.publisher})`
        )
      }
    }

    LogHelper.info(
      `[Migration] Complete: migrated=${result.migratedCount}, skipped=${result.skippedCount}, errors=${result.errorCount}`
    )
  } catch (err) {
    const errorMsg = `Migration failed: ${(err as Error).message}`
    result.errors.push(errorMsg)
    result.errorCount++
    LogHelper.error(`[Migration] ${errorMsg}`)
  }

  return result
}

/**
 * 判断是否需要迁移
 */
function shouldMigrateRecord(record: LibraryRecord, metadata: GameMetadataRecord): boolean {
  // 如果 LibraryRecord 已有非空值，且与 metadata 一致，则跳过
  const hasReleaseYear = record.releaseYear !== undefined && record.releaseYear > 0
  const hasPublisher = record.publisher !== undefined && record.publisher.length > 0

  const metadataHasReleaseYear = metadata.releaseYear > 0
  const metadataHasPublisher = metadata.publisher.length > 0

  // 如果 metadata 没有任何有效值，跳过
  if (!metadataHasReleaseYear && !metadataHasPublisher) {
    return false
  }

  // 如果 LibraryRecord 已有值且与 metadata 一致，跳过
  if (hasReleaseYear && hasPublisher) {
    if (record.releaseYear === metadata.releaseYear && record.publisher === metadata.publisher) {
      return false
    }
  }

  // 需要迁移
  return true
}

/**
 * 合并 metadata 字段到 LibraryRecord
 * 冲突解决：优先保留 LibraryRecord 中已有的非空值
 */
function mergeMetadataIntoLibraryRecord(
  record: LibraryRecord,
  metadata: GameMetadataRecord
): LibraryRecord {
  const hasReleaseYear = record.releaseYear !== undefined && record.releaseYear > 0
  const hasPublisher = record.publisher !== undefined && record.publisher.length > 0

  // ArkTS 禁对象 spread（arkts-no-spread）：原 `{ ...record, ... }` 改为
  // 直接在 record 上按相同逻辑赋值后返回。语义即“把 metadata 合并进 record”；
  // 调用方后续仅读 record.romFile，mutate 这几个字段无外部副作用。
  record.releaseYear = hasReleaseYear
    ? record.releaseYear
    : (metadata.releaseYear > 0 ? metadata.releaseYear : undefined)
  record.publisher = hasPublisher
    ? record.publisher
    : (metadata.publisher.length > 0 ? metadata.publisher : undefined)
  // genre 暂时不迁移（GameMetadataRecord 中没有此字段）
  record.updatedAt = Date.now()
  return record
}

/**
 * 规范化 romFile 键（用于映射匹配）
 */
function normalizeRomFileKey(romFile: string): string {
  return romFile.trim().toLowerCase()
}
