import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuColors, EmuSpacing, EmuTypography, EmuStateColors } from '../common/EmuUiTokens'
import {
  LibraryRecord,
  loadAllLibraryRecords,
  removeLibraryRecord,
  syncLibraryIndex
} from '../common/LibraryRepository'
import {
  buildLibraryRecordsFromSources,
  LibraryRomFileSource
} from '../common/LibraryRecordFactory'
import { scanLibraryRomSources } from '../common/RuntimeRomSourceScanner'
import {
  pickRomUris,
  importRomUris,
  deleteImportedRomFile,
  RomImportProgress,
  RomImportResult
} from '../common/RomImportService'
import LogHelper from '../common/LogHelper'

interface RomListItem {
  fileName: string
  filePath: string
  fileSize: number
  platform: string
  sourceType: 'BUNDLED' | 'IMPORTED'
  importedAt: number
  isDeletable: boolean
  record?: LibraryRecord
}

interface StorageStats {
  totalUsed: number
  totalAvailable: number | undefined
  platformBreakdown: PlatformStorageItem[]
}

interface PlatformStorageItem {
  platform: string
  size: number
  count: number
}

@ComponentV2
struct SpinnerLine {
  @Param active: boolean = false
  @Local angle: number = 0
  private timer: number = -1

  @Monitor('active')
  onActiveChange(monitor: IMonitor): void {
    this.syncSpinner()
  }

  private syncSpinner(): void {
    if (this.active && this.timer === -1) {
      this.timer = setInterval(() => {
        this.angle = (this.angle + 14) % 360
      }, 40)
    } else if (!this.active && this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  aboutToAppear(): void {
    this.syncSpinner()
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  build() {
    Stack() {
      Row()
        .width(26)
        .height(26)
        .borderRadius(13)
        .border({ width: 2, color: '#3300FF41', style: BorderStyle.Solid })

      Row()
        .width(26)
        .height(26)
        .borderRadius(13)
        .border({
          width: { top: 2, right: 2 },
          color: EmuColors.primary,
          style: BorderStyle.Solid
        })
        .rotate({ angle: this.angle })
    }
  }
}

@Entry
@ComponentV2
struct RomManagerPage {
  @Local private allRoms: RomListItem[] = []
  @Local private selectedPlatform: string = 'ALL'
  @Local private loading: boolean = false
  @Local private showToast: boolean = false
  @Local private toastMessage: string = ''
  @Local private showImportProgress: boolean = false
  @Local private importProgress: number = 0
  @Local private importProgressText: string = ''
  @Local private importStage: string = ''
  @Local private storageStats: StorageStats = {
    totalUsed: 0,
    totalAvailable: undefined,
    platformBreakdown: []
  }
  @Local private showDeleteConfirm: boolean = false
  @Local private deleteTargetItem: RomListItem | undefined = undefined
  private toastTimer: number = -1
  private pageActive: boolean = false
  private pageActionToken: number = 0
  private importCancelRequested: boolean = false

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadRomList()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.importCancelRequested = true
    this.pageActionToken += 1
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
  }

  private beginPageAction(): number {
    this.pageActionToken += 1
    return this.pageActionToken
  }

  private isCurrentPageAction(token: number): boolean {
    return this.pageActive && token === this.pageActionToken
  }

  private async loadRomList(): Promise<void> {
    const actionToken = this.beginPageAction()
    this.loading = true
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.allRoms = []
      this.storageStats = {
        totalUsed: 0,
        totalAvailable: undefined,
        platformBreakdown: []
      }
      this.loading = false
      this.showToastMessage('现在还读不到游戏文件列表，请稍后再试')
      return
    }

    try {
      const sources = await scanLibraryRomSources(context, () => this.isCurrentPageAction(actionToken))
      if (!sources || !this.isCurrentPageAction(actionToken)) {
        return
      }

      const records = await loadAllLibraryRecords(context)
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }

      const items: RomListItem[] = []
      for (const source of sources) {
        const record = records.find((r: LibraryRecord) => r.romFile === source.romFile)
        const fileSize = await this.readFileSize(source.romFile)
        items.push({
          fileName: source.fileName,
          filePath: source.romFile,
          fileSize: fileSize,
          platform: this.normalizePlatformLabel(record?.platform),
          sourceType: source.sourceType,
          importedAt: record?.importedAt ?? 0,
          isDeletable: source.sourceType === 'IMPORTED',
          record: record
        })
      }

      items.sort((a: RomListItem, b: RomListItem) => {
        if (a.sourceType !== b.sourceType) {
          return a.sourceType === 'BUNDLED' ? -1 : 1
        }
        return b.importedAt - a.importedAt
      })

      this.allRoms = items
      await this.updateStorageStats(context)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RomManagerPage', 'Load', `加载 ROM 列表失败: ${message}`)
      if (this.isCurrentPageAction(actionToken)) {
        this.allRoms = []
        this.storageStats = {
          totalUsed: 0,
          totalAvailable: undefined,
          platformBreakdown: []
        }
        this.showToastMessage('游戏文件列表暂时没有读出来，请稍后重试')
      }
    } finally {
      if (this.isCurrentPageAction(actionToken)) {
        this.loading = false
      }
    }
  }

  private async updateStorageStats(_context: common.UIAbilityContext): Promise<void> {
    const platformMap: Map<string, PlatformStorageItem> = new Map()
    let totalUsed = 0

    this.allRoms.forEach((item: RomListItem) => {
      const existing = platformMap.get(item.platform)
      if (existing) {
        existing.count += 1
        existing.size += item.fileSize
      } else {
        platformMap.set(item.platform, {
          platform: item.platform,
          size: item.fileSize,
          count: 1
        })
      }
      totalUsed += item.fileSize
    })

    const breakdown: PlatformStorageItem[] = []
    platformMap.forEach((value: PlatformStorageItem) => {
      breakdown.push(value)
    })
    breakdown.sort((a: PlatformStorageItem, b: PlatformStorageItem) => b.size - a.size)

    this.storageStats = {
      totalUsed: totalUsed,
      totalAvailable: undefined,
      platformBreakdown: breakdown
    }
  }

  private applyLocalDeleteResult(targetPath: string): void {
    const nextItems = this.allRoms.filter((item: RomListItem) => item.filePath !== targetPath)
    this.allRoms = nextItems
    void this.updateStorageStats(this.getUIContext().getHostContext() as common.UIAbilityContext)
  }

  private async readFileSize(path: string): Promise<number> {
    try {
      const stat = await fs.stat(path)
      const size = Number(stat.size)
      return Number.isFinite(size) && size > 0 ? size : 0
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RomManagerPage', 'Load', `读取文件大小失败: ${path} / ${message}`)
      return 0
    }
  }

  private normalizePlatformLabel(platform: string | undefined): string {
    const value = (platform ?? '').trim()
    return value.length > 0 ? value : '未识别'
  }

  private get filteredRoms(): RomListItem[] {
    if (this.selectedPlatform === 'ALL') {
      return this.allRoms
    }
    return this.allRoms.filter((item: RomListItem) => item.platform === this.selectedPlatform)
  }

  private get platformFilters(): string[] {
    const platforms: Set<string> = new Set()
    platforms.add('ALL')
    this.allRoms.forEach((item: RomListItem) => {
      platforms.add(item.platform)
    })
    const result: string[] = []
    platforms.forEach((value: string) => {
      result.push(value)
    })
    return result
  }

  private formatFileSize(bytes: number): string {
    if (bytes === 0) {
      return '大小未知'
    }
    if (bytes < 1024) {
      return `${bytes} B`
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  private formatDate(timestamp: number): string {
    if (timestamp === 0) {
      return '未记录'
    }
    const date = new Date(timestamp)
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
  }

  private showToastMessage(message: string): void {
    this.toastMessage = message
    this.showToast = true
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
    }
    this.toastTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.showToast = false
      this.toastTimer = -1
    }, 3000)
  }

  private onImportClick(): void {
    void this.startImport()
  }

  private async startImport(): Promise<void> {
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('现在还不能导入游戏文件，请稍后再试')
      return
    }

    try {
      const selection = await pickRomUris(context)
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      if (selection.failed) {
        this.showToastMessage(selection.message.length > 0 ? selection.message : '系统文件选择器这次没有成功返回文件，请稍后再试')
        return
      }
      if (selection.uris.length === 0) {
        return
      }

      this.importCancelRequested = false
      this.showImportProgress = true
      this.importProgress = 0
      this.importProgressText = '准备导入...'
      this.importStage = 'PREPARING'

      const result: RomImportResult = await importRomUris(
        context,
        selection.uris,
        (progress: RomImportProgress) => {
          if (!this.isCurrentPageAction(actionToken)) {
            return
          }
          const percent = progress.totalBytes > 0
            ? (progress.completedBytes / progress.totalBytes)
            : (progress.completedCount / progress.totalCount)
          this.importProgress = percent
          this.importProgressText = `${progress.currentFileName} (${progress.completedCount}/${progress.totalCount})`
          this.importStage = progress.stage
        },
        {
          overwriteExisting: false,
          shouldCancel: () => this.importCancelRequested || !this.isCurrentPageAction(actionToken)
        }
      )

      if (!this.isCurrentPageAction(actionToken)) {
        return
      }

      this.showImportProgress = false

      if (result.canceled) {
        this.showToastMessage('导入已取消')
      } else if (result.importedCount === 0 && result.overwrittenCount === 0 && result.failedCount === 0 && result.skippedCount > 0) {
        this.showToastMessage('没有导入新文件，所选内容已存在或当前格式不支持')
      } else if (result.failedCount > 0 && result.importedCount + result.overwrittenCount > 0) {
        this.showToastMessage(`已写入 ${result.importedCount + result.overwrittenCount} 个文件，另有 ${result.failedCount} 个还没写进本地目录`)
      } else if (result.failedCount > 0) {
        this.showToastMessage(`还有 ${result.failedCount} 个文件没有写进本地目录`)
      } else if (result.overwrittenCount > 0 && result.importedCount === 0) {
        this.showToastMessage(`已替换 ${result.overwrittenCount} 个已有文件`)
      } else if (result.overwrittenCount > 0) {
        this.showToastMessage(`已写入 ${result.importedCount} 个文件，并替换 ${result.overwrittenCount} 个已有文件`)
      } else {
        this.showToastMessage(`已写入 ${result.importedCount} 个游戏文件`)
      }

      const sources = await scanLibraryRomSources(context, () => this.isCurrentPageAction(actionToken))
      if (!sources || !this.isCurrentPageAction(actionToken)) {
        return
      }
      const sourceRecords = buildLibraryRecordsFromSources(sources)
      await syncLibraryIndex(context, sourceRecords)

      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      await this.loadRomList()
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('RomManagerPage', 'Import', `导入 ROM 失败: ${message}`)
      this.showImportProgress = false
      if (message.startsWith('IMPORT_MULTIFILE_ENTRY_READ_FAILED:')) {
        const fileName = message.substring('IMPORT_MULTIFILE_ENTRY_READ_FAILED:'.length).trim()
        this.showToastMessage(fileName.length > 0 ?
          `${fileName} 没有读出来，请确认文件仍可访问后再试` :
          '多文件入口没有读出来，请确认文件仍可访问后再试')
      } else {
        this.showToastMessage('这批文件没有导入成功，请稍后重试')
      }
    }
  }

  private onDeleteClick(item: RomListItem): void {
    if (!item.isDeletable) {
      this.showToastMessage('内置游戏文件不支持删除')
      return
    }
    this.deleteTargetItem = item
    this.showDeleteConfirm = true
  }

  private closeDeleteConfirm(): void {
    this.showDeleteConfirm = false
    this.deleteTargetItem = undefined
  }

  private confirmDelete(): void {
    const target = this.deleteTargetItem
    this.closeDeleteConfirm()
    if (!target) {
      return
    }
    void this.executeDelete(target)
  }

  private async executeDelete(item: RomListItem): Promise<void> {
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('现在还不能删除游戏文件，请稍后再试')
      return
    }

    try {
      await deleteImportedRomFile(context, item.filePath)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RomManagerPage', 'Delete', `删除文件失败: ${message}`)
      if (this.isCurrentPageAction(actionToken)) {
        this.showToastMessage('游戏文件没有删除成功，请稍后重试')
      }
      return
    }

    if (!this.isCurrentPageAction(actionToken)) {
      return
    }

    try {
      await removeLibraryRecord(context, item.filePath)
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }

      await this.loadRomList()
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }

      this.showToastMessage('游戏文件已删除')
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RomManagerPage', 'Delete', `删除索引刷新失败: ${message}`)
      if (this.isCurrentPageAction(actionToken)) {
        this.applyLocalDeleteResult(item.filePath)
        this.showToastMessage('游戏文件已删掉，列表已按当前结果更新')
      }
    }
  }

  private onBackClick(): void {
    this.getUIContext().getRouter().back()
  }

  @Builder
  private StorageStatsCard() {
    Column({ space: EmuSpacing.sm }) {
      Text('存储统计')
        .fontSize(EmuTypography.md)
        .fontColor(EmuColors.onSurface)
        .fontWeight(FontWeight.Medium)

      Row({ space: EmuSpacing.xs }) {
        Text(`已用 ${this.formatFileSize(this.storageStats.totalUsed)}`)
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurfaceVariant)

        if (this.storageStats.totalAvailable !== undefined) {
          Text('/')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.outlineVariant)

          Text(`剩余可用 ${this.formatFileSize(this.storageStats.totalAvailable)}`)
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
        } else {
          Text('仅统计已写入应用沙箱的文件')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
        }
      }

      Row()
        .width('100%')
        .height(4)
        .backgroundColor(EmuColors.surfaceContainerHigh)
        .borderRadius(2)
        .overlay(
          Row()
            .width(`${this.storageStats.totalAvailable && this.storageStats.totalAvailable > 0 ? (this.storageStats.totalUsed / this.storageStats.totalAvailable * 100) : 0}%`)
            .height(4)
            .backgroundColor(EmuColors.primary)
            .borderRadius(2)
        , { align: Alignment.Start })

      if (this.storageStats.platformBreakdown.length > 0) {
        Column({ space: EmuSpacing.xs }) {
          ForEach(this.storageStats.platformBreakdown.slice(0, 5), (item: PlatformStorageItem) => {
            Row({ space: EmuSpacing.sm }) {
              Text(item.platform)
                .fontSize(EmuTypography.sm)
                .fontColor(EmuColors.onSurface)
                .width(60)

              Text(`${this.formatFileSize(item.size)} (${item.count} 个)`)
                .fontSize(EmuTypography.sm)
                .fontColor(EmuColors.onSurfaceVariant)
                .layoutWeight(1)
            }
            .width('100%')
          }, (item: PlatformStorageItem) => item.platform)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(EmuSpacing.md)
    .backgroundColor(EmuColors.surfaceContainerLow)
    .borderRadius(8)
    .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
  }

  @Builder
  private PlatformFilter() {
    Scroll() {
      Row({ space: EmuSpacing.xs }) {
        ForEach(this.platformFilters, (platform: string) => {
          Text(platform)
            .fontSize(EmuTypography.sm)
            .fontColor(this.selectedPlatform === platform ? EmuColors.onPrimary : EmuColors.onSurface)
            .fontWeight(this.selectedPlatform === platform ? FontWeight.Bold : FontWeight.Regular)
            .padding({ left: EmuSpacing.sm, right: EmuSpacing.sm, top: 6, bottom: 6 })
            .backgroundColor(this.selectedPlatform === platform ? EmuColors.primary : EmuColors.surfaceContainer)
            .borderRadius(4)
            .onClick(() => {
              this.selectedPlatform = platform
            })
        }, (platform: string) => platform)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private RomListItem(item: RomListItem) {
    Column({ space: EmuSpacing.xs }) {
      Row({ space: EmuSpacing.sm }) {
        Text('☰')
          .fontSize(EmuTypography.lg)
          .fontColor(EmuColors.outlineVariant)

        Column({ space: 4 }) {
          Text(item.fileName)
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.onSurface)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(item.filePath)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .opacity(0.6)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.formatFileSize(item.fileSize))
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: EmuSpacing.sm }) {
        Text(item.sourceType === 'BUNDLED' ? '[内置]' : '[导入]')
          .fontSize(EmuTypography.xxs)
          .fontColor(item.sourceType === 'BUNDLED' ? EmuColors.primary : EmuColors.secondary)
          .fontFamily('monospace')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .backgroundColor(item.sourceType === 'BUNDLED' ? '#1A00FF41' : '#1A9D9E9E')
          .borderRadius(2)

        Text(`${item.platform} · ${this.formatDate(item.importedAt)}`)
          .fontSize(EmuTypography.xxs)
          .fontColor(EmuColors.onSurfaceVariant)
          .fontFamily('monospace')
          .layoutWeight(1)

        if (item.isDeletable) {
          Text('删除')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuStateColors.onDanger)
            .fontWeight(FontWeight.Medium)
            .padding({ left: EmuSpacing.sm, right: EmuSpacing.sm, top: 4, bottom: 4 })
            .backgroundColor(EmuStateColors.dangerDefault)
            .borderRadius(4)
            .onClick(() => {
              this.onDeleteClick(item)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(EmuSpacing.md)
    .backgroundColor(EmuColors.surfaceContainerLow)
    .borderRadius(8)
    .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
  }

  @Builder
  private RomList() {
    if (this.filteredRoms.length === 0) {
      Column({ space: EmuSpacing.md }) {
        Text('暂无游戏文件')
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.onSurfaceVariant)

        Text('点击右上角导入按钮添加游戏文件')
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurfaceVariant)
          .opacity(0.6)
      }
      .width('100%')
      .padding(EmuSpacing.xxl)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: EmuSpacing.sm }) {
        ForEach(this.filteredRoms, (item: RomListItem) => {
          ListItem() {
            this.RomListItem(item)
          }
        }, (item: RomListItem) => item.filePath)
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  private ImportProgressOverlay() {
    Column({ space: EmuSpacing.md }) {
      Column({ space: EmuSpacing.lg }) {
        SpinnerLine({ active: true })

        Column({ space: EmuSpacing.xs }) {
          Text('正在导入')
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.onSurface)
            .fontWeight(FontWeight.Medium)

          Text(this.importProgressText)
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row()
          .width('100%')
          .height(4)
          .backgroundColor(EmuColors.surfaceContainerHigh)
          .borderRadius(2)
          .overlay(
            Row()
              .width(`${this.importProgress * 100}%`)
              .height(4)
              .backgroundColor(EmuColors.primary)
              .borderRadius(2)
          , { align: Alignment.Start })

        Text(`${(this.importProgress * 100).toFixed(0)}%`)
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.primary)
          .fontFamily('monospace')
      }
      .width('100%')
      .padding(EmuSpacing.lg)
      .backgroundColor(EmuColors.surfaceContainer)
      .borderRadius(8)
      .border({ width: 1, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
    }
    .width('100%')
    .height('100%')
    .padding(EmuSpacing.lg)
    .backgroundColor('#CC000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // Prevent click through
    })
  }

  @Builder
  private DeleteConfirmDialog() {
    Column({ space: EmuSpacing.md }) {
      Column({ space: EmuSpacing.lg }) {
        Text('确认删除')
          .fontSize(EmuTypography.lg)
          .fontColor(EmuColors.onSurface)
          .fontWeight(FontWeight.Bold)

        if (this.deleteTargetItem) {
          Column({ space: EmuSpacing.xs }) {
            Text(this.deleteTargetItem.fileName)
              .fontSize(EmuTypography.md)
              .fontColor(EmuColors.onSurface)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text('此操作不可恢复')
              .fontSize(EmuTypography.sm)
              .fontColor(EmuStateColors.dangerDefault)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Row({ space: EmuSpacing.sm }) {
          Text('取消')
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.onSurface)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding(EmuSpacing.sm)
            .backgroundColor(EmuColors.surfaceContainerHigh)
            .borderRadius(4)
            .onClick(() => {
              this.closeDeleteConfirm()
            })

          Text('删除')
            .fontSize(EmuTypography.md)
            .fontColor(EmuStateColors.onDanger)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding(EmuSpacing.sm)
            .backgroundColor(EmuStateColors.dangerDefault)
            .borderRadius(4)
            .onClick(() => {
              this.confirmDelete()
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(EmuSpacing.lg)
      .backgroundColor(EmuColors.surfaceContainer)
      .borderRadius(8)
      .border({ width: 1, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
    }
    .width('100%')
    .height('100%')
    .padding(EmuSpacing.lg)
    .backgroundColor('#CC000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.closeDeleteConfirm()
    })
  }

  @Builder
  private Toast() {
    Row({ space: EmuSpacing.xs }) {
      Row()
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(EmuColors.primary)

      Text(this.toastMessage)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
        .letterSpacing(0.8)
    }
    .padding({ left: EmuSpacing.md, right: EmuSpacing.md, top: 10, bottom: 10 })
    .backgroundColor('#2200FF41')
    .border({ width: 0.5, color: '#6600FF41', style: BorderStyle.Solid })
    .borderRadius(999)
    .align(Alignment.Top)
    .margin({ top: 86 })
  }

  build() {
    Stack() {
      Column() {
        EmuHeaderBar({
          titleText: '游戏文件',
          titleIcon: 'folder',
          rightIcon: 'add',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18,
          onRightClick: () => {
            this.onImportClick()
          }
        })

        Row() {
          Column({ space: EmuSpacing.lg }) {
            if (this.loading) {
              Column({ space: EmuSpacing.md }) {
                SpinnerLine({ active: true })
                Text('加载中...')
                  .fontSize(EmuTypography.sm)
                  .fontColor(EmuColors.onSurfaceVariant)
              }
              .width('100%')
              .padding(EmuSpacing.xxl)
              .justifyContent(FlexAlign.Center)
            } else {
              this.StorageStatsCard()

              this.PlatformFilter()

              this.RomList()
            }
          }
          .width('100%')
          .height('100%')
          .constraintSize({ maxWidth: 460 })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: EmuSpacing.lg, right: EmuSpacing.lg, top: EmuSpacing.lg })
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')

      if (this.showToast) {
        this.Toast()
      }

      if (this.showImportProgress) {
        this.ImportProgressOverlay()
      }

      if (this.showDeleteConfirm) {
        this.DeleteConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
