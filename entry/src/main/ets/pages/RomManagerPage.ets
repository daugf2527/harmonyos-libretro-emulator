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
  totalAvailable: number
  platformBreakdown: PlatformStorageItem[]
}

interface PlatformStorageItem {
  platform: string
  size: number
  count: number
}

@Component
struct SpinnerLine {
  @Prop @Watch('onActiveChange') active: boolean = false
  @State angle: number = 0
  private timer: number = -1

  onActiveChange(): void {
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
    this.onActiveChange()
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
@Component
struct RomManagerPage {
  @State private allRoms: RomListItem[] = []
  @State private selectedPlatform: string = 'ALL'
  @State private loading: boolean = false
  @State private showToast: boolean = false
  @State private toastMessage: string = ''
  @State private showImportProgress: boolean = false
  @State private importProgress: number = 0
  @State private importProgressText: string = ''
  @State private importStage: string = ''
  @State private storageStats: StorageStats = {
    totalUsed: 0,
    totalAvailable: 0,
    platformBreakdown: []
  }
  @State private showDeleteConfirm: boolean = false
  @State private deleteTargetItem: RomListItem | undefined = undefined
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
      this.loading = false
      this.showToastMessage('加载失败 CONTEXT_MISSING')
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
      sources.forEach((source: LibraryRomFileSource) => {
        const record = records.find((r: LibraryRecord) => r.romFile === source.romFile)
        const fileSize = 0
        items.push({
          fileName: source.fileName,
          filePath: source.romFile,
          fileSize: fileSize,
          platform: record?.platform ?? 'UNKNOWN',
          sourceType: source.sourceType,
          importedAt: record?.importedAt ?? 0,
          isDeletable: source.sourceType === 'IMPORTED',
          record: record
        })
      })

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
        this.showToastMessage('加载失败 LOAD_ERROR')
      }
    } finally {
      if (this.isCurrentPageAction(actionToken)) {
        this.loading = false
      }
    }
  }

  private async updateStorageStats(context: common.UIAbilityContext): Promise<void> {
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
      totalAvailable: 1024 * 1024 * 1024,
      platformBreakdown: breakdown
    }
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
      return '未知'
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
      return '未知'
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
      this.showToastMessage('导入失败 CONTEXT_MISSING')
      return
    }

    const uris = await pickRomUris(context)
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    if (uris.length === 0) {
      return
    }

    this.importCancelRequested = false
    this.showImportProgress = true
    this.importProgress = 0
    this.importProgressText = '准备导入...'
    this.importStage = 'PREPARING'

    const result: RomImportResult = await importRomUris(
      context,
      uris,
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
        shouldCancel: () => this.importCancelRequested
      }
    )

    if (!this.isCurrentPageAction(actionToken)) {
      return
    }

    this.showImportProgress = false

    if (result.canceled) {
      this.showToastMessage('导入已取消 IMPORT_CANCELED')
    } else if (result.failedCount > 0) {
      this.showToastMessage(`导入完成，${result.failedCount} 个失败 IMPORT_PARTIAL`)
    } else {
      this.showToastMessage(`成功导入 ${result.importedCount} 个 ROM IMPORT_SUCCESS`)
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
  }

  private onDeleteClick(item: RomListItem): void {
    if (!item.isDeletable) {
      this.showToastMessage('内置 ROM 不可删除 BUILTIN_READONLY')
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
      this.showToastMessage('删除失败 CONTEXT_MISSING')
      return
    }

    try {
      await fs.unlink(item.filePath)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('RomManagerPage', 'Delete', `删除文件失败: ${message}`)
      if (this.isCurrentPageAction(actionToken)) {
        this.showToastMessage('删除失败 DELETE_ERROR')
      }
      return
    }

    if (!this.isCurrentPageAction(actionToken)) {
      return
    }

    await removeLibraryRecord(context, item.filePath)
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }

    await this.loadRomList()
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }

    this.showToastMessage('已删除 ROM DELETE_SUCCESS')
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

        Text('/')
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.outlineVariant)

        Text(`可用 ${this.formatFileSize(this.storageStats.totalAvailable)}`)
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurfaceVariant)
      }

      Row()
        .width('100%')
        .height(4)
        .backgroundColor(EmuColors.surfaceContainerHigh)
        .borderRadius(2)
        .overlay(
          Row()
            .width(`${this.storageStats.totalAvailable > 0 ? (this.storageStats.totalUsed / this.storageStats.totalAvailable * 100) : 0}%`)
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
        Text('暂无 ROM')
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.onSurfaceVariant)

        Text('点击右上角导入按钮添加 ROM')
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
          titleText: 'ROM 管理器',
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
