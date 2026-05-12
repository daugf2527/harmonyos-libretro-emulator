import { common } from '@kit.AbilityKit'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { LibraryDetailActionKey, LibraryDetailActionMenu } from '../components/LibraryDetailActionMenu'
import { LibraryDetailHeroPanel } from '../components/LibraryDetailHeroPanel'
import { LibraryDetailInfoPanel } from '../components/LibraryDetailInfoPanel'
import { LibraryLaunchOverlay } from '../components/LibraryLaunchOverlay'
import { KeyValueSpecItem, KeyValueSpecList } from '../components/KeyValueSpecList'
import {
  EmuColors,
  EmuMetrics
} from '../common/EmuUiTokens'
import { consumePendingLibraryDetailRequest } from '../common/LibraryDetailBridge'
import { setPendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import {
  getLibraryRecordByRomFile,
  LibraryRecord,
  updateLibraryRecordCover
} from '../common/LibraryRepository'
import {
  LibrarySavePurgeResult,
  purgeSaveFilesForBaseName
} from '../common/LibrarySaveFilePurger'
import {
  GameMetadataRecord,
  getGameMetadataByRomFile
} from '../common/GameMetadataRepository'
import {
  buildLibraryDetailTelemetrySnapshot,
  cleanLibraryFileName,
  getLibraryDetailConsoleLabel,
  getLibraryDetailDisplayTitle,
  getLibraryDetailEngineLabel,
  getLibraryDetailLocalizedTitle,
  getLibraryDetailMemoryModeLabel,
  getLibraryDetailOverviewText,
  getLibraryDetailPlaytimeLabel,
  getLibraryDetailPublisherLabel,
  getLibraryDetailRegionLabel,
  getLibraryDetailRomVersionLabel,
  getLibraryDetailRuntimeSummaryText,
  getLibraryDetailYearLabel,
  getLibraryLaunchFileLabel,
  hasLibraryDetailRuntimeSnapshot,
  LibraryDetailTelemetrySnapshot
} from '../common/LibraryDetailPresenter'
import LogHelper from '../common/LogHelper'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

interface LibraryDetailRouteParams {
  romFile?: string
}

interface LibraryLaunchRouteParams {
  coreId?: string
  romFile?: string
  autoStart?: boolean
}

@Entry
@Component
struct LibraryDetailPage {
  @State private libraryRecord: LibraryRecord | undefined = undefined
  @State private metadataRecord: GameMetadataRecord | undefined = undefined
  @State private showExtendedDetails: boolean = false
  @State private showActionMenu: boolean = false
  @State private showToast: boolean = false
  @State private toastMessage: string = ''
  @State private isLaunching: boolean = false
  @State private launchProgress: number = 0
  @State private launchStatusText: string = 'READY_TO_HANDOFF'
  @State private heroScale: number = 1.04
  @State private telemetryScanOffset: number = -180
  @State private telemetryGlowOpacity: number = 0.2
  private readonly coverCycleKeys: string[] = ['', 'metroid_fusion', 'zelda_triforce']
  private readonly coverPalette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331']
  private toastTimer: number = -1
  private visualTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadRecord()
    this.startVisualLoop()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
    this.stopVisualLoop()
  }

  private beginPageTask(): number {
    this.pageTaskToken += 1
    return this.pageTaskToken
  }

  private isCurrentPageTask(token: number): boolean {
    return this.pageActive && token === this.pageTaskToken
  }

  private async loadRecord(): Promise<void> {
    const token = this.beginPageTask()
    const romFile = this.resolveRequestedRomFile()
    if (romFile.length === 0) {
      this.showToastMessage('未找到详情上下文 DETAIL_MISSING')
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('上下文不可用 CONTEXT_MISSING')
      return
    }
    const record = await getLibraryRecordByRomFile(context, romFile)
    if (!this.isCurrentPageTask(token)) {
      return
    }
    if (!record) {
      this.showToastMessage('条目不存在 RECORD_NOT_FOUND')
      return
    }
    const metadata = await getGameMetadataByRomFile(context, record.romFile)
    if (!this.isCurrentPageTask(token)) {
      return
    }
    this.libraryRecord = record
    this.metadataRecord = metadata
    this.applyTelemetrySnapshot(record)
  }

  private resolveRequestedRomFile(): string {
    const params = this.getUIContext().getRouter().getParams() as LibraryDetailRouteParams
    if (typeof params?.romFile === 'string' && params.romFile.length > 0) {
      return params.romFile
    }
    const request = consumePendingLibraryDetailRequest()
    if (request?.romFile && request.romFile.length > 0) {
      return request.romFile
    }
    return this.libraryRecord?.romFile ?? ''
  }

  private showToastMessage(message: string): void {
    this.toastMessage = message
    this.showToast = true
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
    }
    this.toastTimer = setTimeout(() => {
      this.showToast = false
      this.toastTimer = -1
    }, 2600)
  }

  private applyTelemetrySnapshot(_record: LibraryRecord): void {
  }

  private startVisualLoop(): void {
    if (this.visualTimer !== -1) {
      return
    }
    let frame = 0
    this.visualTimer = setInterval(() => {
      frame += 1
      this.heroScale = 1.08 + Math.sin(frame / 18) * 0.035
      this.telemetryScanOffset = -180 + (frame % 100) * 5
      this.telemetryGlowOpacity = 0.14 + (Math.sin(frame / 6) + 1) * 0.1
    }, 90)
  }

  private stopVisualLoop(): void {
    if (this.visualTimer !== -1) {
      clearInterval(this.visualTimer)
      this.visualTimer = -1
    }
  }

  private get launchCpuText(): string {
    const snapshot = buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord)
    return `FPS: ${snapshot.fpsText}`
  }
  private get telemetryFpsText(): string {
    const snapshot = buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord)
    return snapshot.fpsText
  }
  private get telemetryCpuText(): string {
    const snapshot = buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord)
    return snapshot.audioText
  }
  private get telemetryGpuText(): string {
    const snapshot = buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord)
    return snapshot.dropText
  }

  private async beginLaunchSequence(record: LibraryRecord): Promise<void> {
    if (this.isLaunching) {
      return
    }
    const token = this.beginPageTask()
    this.showActionMenu = false
    this.isLaunching = true
    this.applyTelemetrySnapshot(record)
    this.launchProgress = 100
    this.launchStatusText = 'HANDOFF_TO_ENGINE_PAGE'
    await Promise.resolve()
    if (!this.isCurrentPageTask(token)) {
      return
    }
    this.commitLaunchNavigation(record)
  }

  private commitLaunchNavigation(record: LibraryRecord): void {
    const routeParams: LibraryLaunchRouteParams = {
      coreId: record.preferredCoreId,
      romFile: record.romFile,
      autoStart: true
    }
    setPendingLibraryLaunchRequest({
      coreId: record.preferredCoreId,
      romFile: record.romFile,
      autoStart: true
    })
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LibretroGamePage',
      params: routeParams
    }).catch((err: Error) => {
      this.isLaunching = false
      LogHelper.error('LibraryDetailPage', 'Route', `跳转游戏页失败: ${err.message}`)
      this.showToastMessage('启动失败 ROUTE_PUSH_FAIL')
    })
  }

  private getNextCoverKey(record: LibraryRecord): string {
    const currentIndex = this.coverCycleKeys.findIndex((item: string) => item === record.coverKey)
    if (currentIndex < 0) {
      return this.coverCycleKeys[1]
    }
    return this.coverCycleKeys[(currentIndex + 1) % this.coverCycleKeys.length]
  }

  private resolveCoverColorByKey(key: string): string {
    if (key === 'metroid_fusion') {
      return '#274530'
    }
    if (key === 'zelda_triforce') {
      return '#27405E'
    }
    return this.coverPalette[0]
  }

  private launchGame(): void {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    this.beginLaunchSequence(target)
  }

  private async cycleCoverPreset(): Promise<void> {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    const token = this.beginPageTask()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('封面更新失败 CONTEXT_MISSING')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
    if (!this.isCurrentPageTask(token)) {
      return
    }
    if (!updated) {
      this.showToastMessage('封面更新失败 COVER_WRITE_FAIL')
      return
    }
    this.libraryRecord = updated
    this.applyTelemetrySnapshot(updated)
    this.showActionMenu = false
    this.showToastMessage('已切换内置封面 COVER_UPDATED')
  }

  private async deleteSaveFiles(): Promise<void> {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    const token = this.beginPageTask()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('存档删除失败 CONTEXT_MISSING')
      return
    }
    try {
      const result: LibrarySavePurgeResult = await purgeSaveFilesForBaseName(
        context,
        cleanLibraryFileName(target.fileName),
        () => this.isCurrentPageTask(token)
      )
      if (result.cancelled) {
        return
      }
      if (result.deletedCount === 0) {
        this.showToastMessage('未找到对应存档 SAVE_EMPTY')
        this.showActionMenu = false
        return
      }
      this.showActionMenu = false
      this.showToastMessage(`已删除 ${result.deletedCount} 个存档 SAVE_PURGED`)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryDetailPage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('存档删除失败 SAVE_PURGE_FAIL')
    }
  }

  private openLibraryPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
      LogHelper.error('LibraryDetailPage', 'Route', `返回库页失败: ${err.message}`)
    })
  }

  private onBottomNavClick(key: string): void {
    if (key === 'library') {
      this.openLibraryPage()
      return
    }
    if (key === 'engine') {
      this.launchGame()
      return
    }
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[LibraryDetailPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  private handleActionMenuClick(actionKey: LibraryDetailActionKey): void {
    if (actionKey === 'launch') {
      this.launchGame()
      return
    }
    if (actionKey === 'details') {
      const record = this.libraryRecord
      this.showActionMenu = false
      this.showToastMessage(record ? `当前已在 ${record.title} 详情页` : '当前已在详情页')
      return
    }
    if (actionKey === 'cover') {
      void this.cycleCoverPreset()
      return
    }
    if (actionKey === 'metadata') {
      const record = this.libraryRecord
      this.showActionMenu = false
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/MetadataEditPage',
        params: {
          romFile: record ? record.romFile : ''
        } as LibraryDetailRouteParams
      }).catch((err: Error) => {
        LogHelper.error('LibraryDetailPage', 'Route', `跳转资料编辑失败: ${err.message}`)
      })
      return
    }
    if (actionKey === 'save_manager') {
      const record = this.libraryRecord
      this.showActionMenu = false
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/SaveStatePage',
        params: {
          romFile: record ? record.romFile : ''
        } as LibraryDetailRouteParams
      }).catch((err: Error) => {
        LogHelper.error('LibraryDetailPage', 'Route', `跳转存档管理失败: ${err.message}`)
      })
      return
    }
    if (actionKey === 'purge_save') {
      void this.deleteSaveFiles()
    }
  }

  @Builder
  private TopBar() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: 'terminal',
          iconSize: 15
        })

        Text('EMU_OS // 0.1')
          .fontFamily('monospace')
          .fontSize(13)
          .fontColor(EmuColors.primary)
          .letterSpacing(2.2)
      }

      Blank()
        .layoutWeight(1)

      this.LocalStatusPill()

      Blank()
        .layoutWeight(1)

      Row() {
        EmuIcon({
          name: 'settings_input_component',
          iconSize: 20
        })
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.showActionMenu = true
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: 390 })
    .height(EmuMetrics.headerHeight)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#E6000000')
    .backdropBlur(22)
    .border({
      width: { bottom: 0.5 },
      color: '#26262626',
      style: BorderStyle.Solid
    })
  }

  @Builder
  private LocalStatusPill() {
    Row({ space: 7 }) {
      Row()
        .width(14)
        .height(14)
        .borderRadius(7)
        .backgroundColor('#FF0E0E0E')

      Text(this.getLocalStatusText())
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF0E0E0E')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(34)
    .constraintSize({ maxWidth: 142 })
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(EmuColors.primary)
    .borderRadius(18)
    .shadow({ radius: 18, color: '#6600FF41', offsetX: 0, offsetY: 0 })
  }

  private getCoreSpecItems(record: LibraryRecord): KeyValueSpecItem[] {
    return [
      { label: 'ROM Version', value: getLibraryDetailRomVersionLabel(record, this.metadataRecord) },
      { label: 'Processor Cluster', value: getLibraryDetailEngineLabel(record) },
      { label: 'Memory Mode', value: getLibraryDetailMemoryModeLabel(record) }
    ]
  }

  private getLocalStatusText(): string {
    if (!this.libraryRecord) {
      return '本地资料加载中'
    }
    if (hasLibraryDetailRuntimeSnapshot(this.libraryRecord as LibraryRecord)) {
      return '本地运行记录'
    }
    return '本地资料已加载'
  }

  private getLaunchRuntimeStatusText(): string {
    if (!this.libraryRecord) {
      return 'NO DATA'
    }
    return hasLibraryDetailRuntimeSnapshot(this.libraryRecord as LibraryRecord) ? 'RECORDED' : 'NO DATA'
  }

  @Builder
  private SuccessToast() {
    Row({ space: 8 }) {
      Row()
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(EmuColors.primary)

      Text(this.toastMessage)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#FF0E0E0E')
        .letterSpacing(0.8)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#E600FF41')
    .borderRadius(999)
    .shadow({ radius: 18, color: '#5500FF41', offsetX: 0, offsetY: 0 })
    .align(Alignment.Top)
    .margin({ top: 68 })
  }

  @Builder
  private EmptyState() {
    Column({ space: 18 }) {
      Text('未找到详情页数据')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)

      Text('请从游戏库条目的“查看详情”进入。')
        .fontSize(14)
        .fontColor('#CCABABAB')

      Row() {
        Text('返回游戏库')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
      }
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .backgroundColor(EmuColors.surfaceContainer)
      .border({ width: 1, color: '#6600FF41', style: BorderStyle.Solid })
      .borderRadius(6)
      .onClick(() => {
        this.openLibraryPage()
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        Row() {
          if (this.libraryRecord) {
            Scroll() {
              Column({ space: 32 }) {
                LibraryDetailHeroPanel({
                  coverKey: (this.libraryRecord as LibraryRecord).coverKey,
                  heroScale: this.heroScale,
                  displayTitle: getLibraryDetailDisplayTitle(this.libraryRecord as LibraryRecord, this.metadataRecord),
                  localizedTitle: getLibraryDetailLocalizedTitle(this.libraryRecord as LibraryRecord),
                  coreLabel: (this.libraryRecord as LibraryRecord).preferredCoreId.toUpperCase(),
                  onLaunch: () => {
                    this.beginLaunchSequence(this.libraryRecord as LibraryRecord)
                  },
                  onQuickAction: (message: string) => {
                    this.showToastMessage(message)
                  }
                })
                LibraryDetailInfoPanel({
                  showExtendedDetails: this.showExtendedDetails,
                  primaryCells: [
                    { title: 'CN NAME', value: getLibraryDetailLocalizedTitle(this.libraryRecord as LibraryRecord) },
                    { title: 'YEAR', value: getLibraryDetailYearLabel(this.libraryRecord as LibraryRecord, this.metadataRecord) },
                    { title: 'CONSOLE', value: getLibraryDetailConsoleLabel(this.libraryRecord as LibraryRecord, this.metadataRecord) }
                  ],
                  extendedCells: [
                    { title: 'PUBLISHER', value: getLibraryDetailPublisherLabel(this.metadataRecord) },
                    { title: 'PLAYTIME', value: getLibraryDetailPlaytimeLabel(this.libraryRecord as LibraryRecord) },
                    { title: 'ENGINE', value: getLibraryDetailEngineLabel(this.libraryRecord as LibraryRecord) },
                    { title: 'REGION', value: getLibraryDetailRegionLabel(this.libraryRecord as LibraryRecord) }
                  ],
                  hasRuntimeSnapshot: hasLibraryDetailRuntimeSnapshot(this.libraryRecord as LibraryRecord),
                  telemetryFpsText: this.telemetryFpsText,
                  telemetryAudioText: this.telemetryCpuText,
                  telemetryDropText: this.telemetryGpuText,
                  telemetryProfile: buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord).profile,
                  telemetryScanOffset: this.telemetryScanOffset,
                  telemetryGlowOpacity: this.telemetryGlowOpacity,
                  overviewText: getLibraryDetailOverviewText(this.metadataRecord),
                  runtimeSummaryText: getLibraryDetailRuntimeSummaryText(this.libraryRecord as LibraryRecord, this.metadataRecord),
                  onToggleDetails: () => {
                    this.showExtendedDetails = !this.showExtendedDetails
                  }
                })
                KeyValueSpecList({
                  title: 'CORE SPECIFICATIONS',
                  items: this.getCoreSpecItems(this.libraryRecord as LibraryRecord)
                })
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 26, bottom: 42 })
            }
            .width('100%')
            .constraintSize({ maxWidth: 390 })
            .scrollBar(BarState.Off)
          } else {
            Column() {
              this.EmptyState()
            }
            .width('100%')
            .constraintSize({ maxWidth: 390 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)

        EmuBottomNav({
          items: createEmuBottomNavItems('library'),
          activeFontColor: EmuColors.primary,
          inactiveFontColor: '#665E5E67',
          indicatorStyle: 'dot',
          overallOpacity: 1,
          panelBackgroundColor: '#F2000000',
          onItemClick: (key: string) => {
            this.onBottomNavClick(key)
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(EmuColors.background)

      if (this.showToast) {
        this.SuccessToast()
      }

      if (this.showActionMenu && this.libraryRecord) {
        LibraryDetailActionMenu({
          onClose: () => {
            this.showActionMenu = false
          },
          onAction: (actionKey: LibraryDetailActionKey) => {
            this.handleActionMenuClick(actionKey)
          }
        })
      }

      if (this.isLaunching && this.libraryRecord) {
        LibraryLaunchOverlay({
          coverKey: (this.libraryRecord as LibraryRecord).coverKey,
          progress: this.launchProgress,
          statusText: this.launchStatusText,
          cpuText: this.launchCpuText,
          runtimeStatusText: this.getLaunchRuntimeStatusText(),
          fileLabel: getLibraryLaunchFileLabel(this.libraryRecord as LibraryRecord)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
