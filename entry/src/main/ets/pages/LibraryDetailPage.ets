import { common } from '@kit.AbilityKit'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { LibraryDetailActionKey, LibraryDetailActionMenu } from '../components/LibraryDetailActionMenu'
import { LibraryDetailHeroPanel } from '../components/LibraryDetailHeroPanel'
import {
  LibraryDetailInfoPanel,
  LibraryDetailSummaryCellData
} from '../components/LibraryDetailInfoPanel'
import { LibraryLaunchOverlay } from '../components/LibraryLaunchOverlay'
import { KeyValueSpecItem, KeyValueSpecList } from '../components/KeyValueSpecList'
import {
  EmuColors,
  EmuMetrics, EmuTypography } from '../common/EmuUiTokens'
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

@ComponentV2
struct AnimatedDetailBody {
  @Param coverKey: string = ''
  @Param displayTitle: string = ''
  @Param localizedTitle: string = ''
  @Param coreLabel: string = ''
  @Param showExtendedDetails: boolean = false
  @Param primaryCells: LibraryDetailSummaryCellData[] = []
  @Param extendedCells: LibraryDetailSummaryCellData[] = []
  @Param hasRuntimeSnapshot: boolean = false
  @Param telemetryFpsText: string = ''
  @Param telemetryAudioText: string = ''
  @Param telemetryDropText: string = ''
  @Param overviewText: string = ''
  @Param runtimeSummaryText: string = ''
  @Param coreSpecItems: KeyValueSpecItem[] = []
  @Event onLaunch?: () => void
  @Event onToggleDetails?: () => void
  @Local private heroScale: number = 1.04
  private visualTimer: number = -1

  aboutToAppear(): void {
    if (this.visualTimer !== -1) {
      return
    }
    let frame = 0
    this.visualTimer = setInterval(() => {
      frame += 1
      this.heroScale = 1.08 + Math.sin(frame / 18) * 0.035
    }, 90)
  }

  aboutToDisappear(): void {
    if (this.visualTimer !== -1) {
      clearInterval(this.visualTimer)
      this.visualTimer = -1
    }
  }

  build() {
    Scroll() {
      Column({ space: 32 }) {
        LibraryDetailHeroPanel({
          coverKey: this.coverKey,
          heroScale: this.heroScale,
          displayTitle: this.displayTitle,
          localizedTitle: this.localizedTitle,
          coreLabel: this.coreLabel,
          onLaunch: () => {
            if (this.onLaunch) {
              this.onLaunch()
            }
          }
        })
        LibraryDetailInfoPanel({
          showExtendedDetails: this.showExtendedDetails,
          primaryCells: this.primaryCells,
          extendedCells: this.extendedCells,
          hasRuntimeSnapshot: this.hasRuntimeSnapshot,
          telemetryFpsText: this.telemetryFpsText,
          telemetryAudioText: this.telemetryAudioText,
          telemetryDropText: this.telemetryDropText,
          overviewText: this.overviewText,
          runtimeSummaryText: this.runtimeSummaryText,
          onToggleDetails: () => {
            if (this.onToggleDetails) {
              this.onToggleDetails()
            }
          }
        })
        KeyValueSpecList({
          title: '核心信息',
          items: this.coreSpecItems
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 26, bottom: 42 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 390 })
    .scrollBar(BarState.Off)
  }
}

@Entry
@ComponentV2
struct LibraryDetailPage {
  @Local private libraryRecord: LibraryRecord | undefined = undefined
  @Local private detailLoadFailed: boolean = false
  @Local private showExtendedDetails: boolean = false
  @Local private showActionMenu: boolean = false
  @Local private showToast: boolean = false
  @Local private toastMessage: string = ''
  @Local private isLaunching: boolean = false
  @Local private launchStatusText: string = '准备启动游戏'
  private readonly coverCycleKeys: string[] = ['', 'moss_signal', 'aurora_grid', 'ember_glow']
  private readonly coverPalette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331']
  private readonly navItems = createEmuBottomNavItems('library')
  private toastTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0
  private cachedSnapshot: LibraryDetailTelemetrySnapshot | undefined = undefined
  private cachedSnapshotRomFile: string = ''
  private cachedCoreSpecItems: KeyValueSpecItem[] = []
  private cachedCoreSpecRomFile: string = ''

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadRecord()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
  }

  private invalidateDerivedCaches(): void {
    this.cachedSnapshot = undefined
    this.cachedSnapshotRomFile = ''
    this.cachedCoreSpecItems = []
    this.cachedCoreSpecRomFile = ''
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
      this.libraryRecord = undefined
      this.invalidateDerivedCaches()
      this.detailLoadFailed = false
      this.showToastMessage('没有找到要查看的游戏')
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.libraryRecord = undefined
      this.invalidateDerivedCaches()
      this.detailLoadFailed = true
      this.showToastMessage('现在还拿不到这条游戏的本地资料，请回到游戏库后重试')
      return
    }
    try {
      const record = await getLibraryRecordByRomFile(context, romFile)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      if (!record) {
        this.libraryRecord = undefined
        this.invalidateDerivedCaches()
        this.detailLoadFailed = false
        this.showToastMessage('这条游戏已经不在当前游戏库里了')
        return
      }
      this.libraryRecord = record
      this.detailLoadFailed = false
      this.invalidateDerivedCaches()
      this.applyTelemetrySnapshot(record)
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryDetailPage', 'Data', `读取详情条目失败: ${message}`)
      this.libraryRecord = undefined
      this.invalidateDerivedCaches()
      this.detailLoadFailed = true
      this.showToastMessage('这条游戏详情没有读出来，请稍后重试')
    }
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
      if (!this.pageActive) {
        return
      }
      this.showToast = false
      this.toastTimer = -1
    }, 2600)
  }

  private applyTelemetrySnapshot(_record: LibraryRecord): void {
  }

  private getSnapshot(): LibraryDetailTelemetrySnapshot {
    const romFile = this.libraryRecord?.romFile ?? ''
    if (romFile.length > 0 && romFile === this.cachedSnapshotRomFile && this.cachedSnapshot) {
      return this.cachedSnapshot
    }
    const snapshot = buildLibraryDetailTelemetrySnapshot(this.libraryRecord as LibraryRecord)
    this.cachedSnapshot = snapshot
    this.cachedSnapshotRomFile = romFile
    return snapshot
  }

  private get launchCpuText(): string {
    return `帧率: ${this.getSnapshot().fpsText}`
  }
  private get telemetryFpsText(): string {
    return this.getSnapshot().fpsText
  }
  private get telemetryCpuText(): string {
    return this.getSnapshot().audioText
  }
  private get telemetryGpuText(): string {
    return this.getSnapshot().dropText
  }

  private async beginLaunchSequence(record: LibraryRecord): Promise<void> {
    if (this.isLaunching) {
      return
    }
    const token = this.beginPageTask()
    this.showActionMenu = false
    this.isLaunching = true
    this.applyTelemetrySnapshot(record)
    this.launchStatusText = '正在切换到运行页'
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
      this.showToastMessage('这款游戏现在还打不开，请稍后再试')
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
    if (key === 'moss_signal') {
      return '#274530'
    }
    if (key === 'aurora_grid') {
      return '#27405E'
    }
    if (key === 'ember_glow') {
      return '#5A4331'
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
      this.showToastMessage('现在还不能切换封面样式，请稍后再试')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    try {
      const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      if (!updated) {
        this.showToastMessage('没有找到要更新的游戏条目')
        return
      }
      this.libraryRecord = updated
      this.invalidateDerivedCaches()
      this.applyTelemetrySnapshot(updated)
      this.showActionMenu = false
      this.showToastMessage('已切换封面样式')
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryDetailPage', 'Cover', `更新封面失败: ${message}`)
      this.showToastMessage('封面样式没有更新成功，请稍后重试')
    }
  }

  private async deleteSaveFiles(): Promise<void> {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    const token = this.beginPageTask()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('现在还不能管理这款游戏的存档，请稍后再试')
      return
    }
    try {
      const result: LibrarySavePurgeResult = await purgeSaveFilesForBaseName(
        context,
        cleanLibraryFileName(target.fileName),
        () => this.isCurrentPageTask(token)
      )
      if (!this.isCurrentPageTask(token)) {
        return
      }
      if (result.cancelled) {
        return
      }
      if (result.deletedCount === 0) {
        this.showToastMessage('这款游戏还没有可删除的存档')
        this.showActionMenu = false
        return
      }
      this.showActionMenu = false
      this.showToastMessage(`已删除 ${result.deletedCount} 个存档`)
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryDetailPage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('存档没有删除成功，请稍后重试')
    }
  }

  private openLibraryPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
      LogHelper.error('LibraryDetailPage', 'Route', `返回库页失败: ${err.message}`)
      this.showToastMessage('现在还回不到游戏库，请稍后再试')
    })
  }

  private onBottomNavClick(key: string): void {
    if (key === 'library') {
      this.openLibraryPage()
      return
    }
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('LibraryDetailPage', 'Route', `pushUrl ${route} failed: ${err.message}`)
      this.showToastMessage('这个页面现在还打不开，请稍后再试')
    })
  }

  private handleActionMenuClick(actionKey: LibraryDetailActionKey): void {
    if (actionKey === 'launch') {
      this.launchGame()
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
        this.showToastMessage('资料编辑页现在还打不开，请稍后再试')
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
        this.showToastMessage('存档管理页现在还打不开，请稍后再试')
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

        Text('碳影 / Carbon Shade')
          .fontSize(13)
          .fontColor(EmuColors.primary)
          .letterSpacing(1.2)
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
        .fontSize(EmuTypography.xs)
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
    if (record.romFile === this.cachedCoreSpecRomFile && this.cachedCoreSpecItems.length > 0) {
      return this.cachedCoreSpecItems
    }
    this.cachedCoreSpecItems = [
      { label: 'ROM 版本', value: getLibraryDetailRomVersionLabel(record) },
      { label: '核心引擎', value: getLibraryDetailEngineLabel(record) },
      { label: '内存模式', value: getLibraryDetailMemoryModeLabel(record) }
    ]
    this.cachedCoreSpecRomFile = record.romFile
    return this.cachedCoreSpecItems
  }

  private buildPrimaryCells(record: LibraryRecord): LibraryDetailSummaryCellData[] {
    return [
      { title: '本地名称', value: getLibraryDetailLocalizedTitle(record) },
      { title: '年份', value: getLibraryDetailYearLabel(record) },
      { title: '平台', value: getLibraryDetailConsoleLabel(record) }
    ]
  }

  private buildExtendedCells(record: LibraryRecord): LibraryDetailSummaryCellData[] {
    return [
      { title: '发行方', value: getLibraryDetailPublisherLabel(record) },
      { title: '累计时长', value: getLibraryDetailPlaytimeLabel(record) },
      { title: '核心引擎', value: getLibraryDetailEngineLabel(record) },
      { title: '区域', value: getLibraryDetailRegionLabel(record) }
    ]
  }

  @Builder
  private DetailContent(record: LibraryRecord) {
    AnimatedDetailBody({
      coverKey: record.coverKey,
      displayTitle: getLibraryDetailDisplayTitle(record),
      localizedTitle: getLibraryDetailLocalizedTitle(record),
      coreLabel: getLibraryDetailEngineLabel(record),
      showExtendedDetails: this.showExtendedDetails,
      primaryCells: this.buildPrimaryCells(record),
      extendedCells: this.buildExtendedCells(record),
      hasRuntimeSnapshot: hasLibraryDetailRuntimeSnapshot(record),
      telemetryFpsText: this.telemetryFpsText,
      telemetryAudioText: this.telemetryCpuText,
      telemetryDropText: this.telemetryGpuText,
      overviewText: getLibraryDetailOverviewText(record),
      runtimeSummaryText: getLibraryDetailRuntimeSummaryText(record),
      coreSpecItems: this.getCoreSpecItems(record),
      onLaunch: () => {
        this.beginLaunchSequence(record)
      },
      onToggleDetails: () => {
        this.showExtendedDetails = !this.showExtendedDetails
      }
    })
  }

  private getLocalStatusText(): string {
    if (!this.libraryRecord) {
      return '本地资料未读取'
    }
    if (hasLibraryDetailRuntimeSnapshot(this.libraryRecord as LibraryRecord)) {
      return '本地运行记录'
    }
    return '本地资料已读到'
  }

  private getLaunchRuntimeStatusText(): string {
    if (!this.libraryRecord) {
      return '运行记录未读取'
    }
    return hasLibraryDetailRuntimeSnapshot(this.libraryRecord as LibraryRecord) ? '已有记录' : '还没有运行记录'
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
      Text(this.detailLoadFailed ? '这条游戏详情暂时没有读出来' : '当前没有可显示的游戏详情')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)

      Text(this.detailLoadFailed ?
        '本地资料这次没有加载成功，请稍后重试，或先回到游戏库重新进入。' :
        '请回到游戏库，从具体条目的“查看详情”进入。')
        .fontSize(EmuTypography.md)
        .fontColor('#CCABABAB')

      Row() {
        Text('返回游戏库')
          .fontSize(EmuTypography.md)
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
            this.DetailContent(this.libraryRecord as LibraryRecord)
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
          items: this.navItems,
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
          statusText: this.launchStatusText,
          cpuText: this.launchCpuText,
          runtimeStatusText: this.getLaunchRuntimeStatusText(),
          fileLabel: getLibraryDetailLocalizedTitle(this.libraryRecord as LibraryRecord)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
