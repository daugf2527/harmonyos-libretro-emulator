import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { LibraryContextMenuOverlay } from '../components/LibraryContextMenuOverlay'
import { LibraryGameSections } from '../components/LibraryGameSections'
import { LibrarySearchPanel } from '../components/LibrarySearchPanel'
import { EmuColors } from '../common/EmuUiTokens'
import { setPendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import {
  buildRecentLibraryRecords,
  getReadyLibraryRecords,
  LibraryRecord,
  removeLibraryRecord,
  sortAllLibraryRecords,
  syncLibraryIndex,
  updateLibraryRecordCover
} from '../common/LibraryRepository'
import {
  buildDisplayPlatformFilters,
  buildLibraryPlatforms,
  buildLibrarySearchResults,
  filterLibraryGames,
  filterRecentLibraryGames
} from '../common/LibraryPagePresenter'
import {
  buildLibraryRecordsFromSources
} from '../common/LibraryRecordFactory'
import {
  getLibraryTelemetryBars,
  getLibraryTelemetryCells
} from '../common/LibraryRuntimeTelemetryPresenter'
import {
  LibrarySavePurgeResult,
  purgeSaveFilesForBaseName
} from '../common/LibrarySaveFilePurger'
import { setPendingLibraryDetailRequest } from '../common/LibraryDetailBridge'
import { scanLibraryRomSources } from '../common/RuntimeRomSourceScanner'
import LogHelper from '../common/LogHelper'

interface TouchPoint {
  x: number
  y: number
}

@Entry
@Component
struct LibraryPage {
  @State private selectedPlatform: string = 'ALL'
  @State private searchKeyword: string = ''
  @State private allGames: LibraryRecord[] = []
  @State private searchBusy: boolean = false
  @State private showSearchResults: boolean = false
  @State private showContextMenu: boolean = false
  @State private contextMenuGame: LibraryRecord | undefined = undefined
  @State private highlightedRecentGameId: string = ''
  @State private showToast: boolean = false
  @State private toastMessage: string = '已刷新库 SYNCED'
  @State private pullRefreshHeight: number = 0
  @State private pullRefreshOpacity: number = 0
  @State private refreshing: boolean = false
  @State private bottomLoaderActive: boolean = false
  @State private spinnerAngle: number = 0
  private scroller: Scroller = new Scroller()
  private searchTimer: number = -1
  private spinnerTimer: number = -1
  private toastTimer: number = -1
  private refreshTimer: number = -1
  private bottomLoaderTimer: number = -1
  private longPressTimer: number = -1
  private pageActive: boolean = false
  private libraryRefreshToken: number = 0
  private pageActionToken: number = 0
  private readonly coverCycleKeys: string[] = ['', 'metroid_fusion', 'zelda_triforce']
  private readonly coverPalette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331']
  private pullTracking: boolean = false
  private pullStartY: number = 0
  private scrollOffsetY: number = 0
  private cardTouchStartX: number = 0
  private cardTouchStartY: number = 0
  private cardTouchMoved: boolean = false
  private cardLongPressed: boolean = false
  aboutToAppear(): void {
    this.pageActive = true
    void this.refreshLibraryGames()
    this.updateSpinnerLoop()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.libraryRefreshToken += 1
    this.pageActionToken += 1
    this.clearSearchTimer()
    this.clearLongPressTimer()
    this.stopSpinnerLoop()
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer)
      this.refreshTimer = -1
    }
    if (this.bottomLoaderTimer !== -1) {
      clearTimeout(this.bottomLoaderTimer)
      this.bottomLoaderTimer = -1
    }
  }

  private isCurrentLibraryRefresh(token: number): boolean {
    return this.pageActive && token === this.libraryRefreshToken
  }

  private beginPageAction(): number {
    this.pageActionToken += 1
    return this.pageActionToken
  }

  private isCurrentPageAction(token: number): boolean {
    return this.pageActive && token === this.pageActionToken
  }

  private get filteredGames(): LibraryRecord[] {
    return filterLibraryGames(this.allGames, this.selectedPlatform, this.searchKeyword)
  }

  private get filteredRecentGames(): LibraryRecord[] {
    return filterRecentLibraryGames(this.allGames, this.selectedPlatform, this.searchKeyword)
  }

  private get searchResults(): LibraryRecord[] {
    return buildLibrarySearchResults(this.allGames, this.selectedPlatform, this.searchKeyword)
  }

  private startSpinnerLoop(): void {
    if (this.spinnerTimer !== -1) {
      return
    }
    this.spinnerTimer = setInterval(() => {
      this.spinnerAngle = (this.spinnerAngle + 14) % 360
    }, 40)
  }

  private stopSpinnerLoop(): void {
    if (this.spinnerTimer !== -1) {
      clearInterval(this.spinnerTimer)
      this.spinnerTimer = -1
    }
    this.spinnerAngle = 0
  }

  private updateSpinnerLoop(): void {
    const shouldRun = this.searchBusy || this.refreshing || this.bottomLoaderActive || this.pullRefreshHeight > 0
    if (shouldRun) {
      this.startSpinnerLoop()
      return
    }
    this.stopSpinnerLoop()
  }

  private clearSearchTimer(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer)
      this.searchTimer = -1
    }
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimer !== -1) {
      clearTimeout(this.longPressTimer)
      this.longPressTimer = -1
    }
  }

  private resolveTouchPoint(event: TouchEvent): TouchPoint | undefined {
    const point = (event.touches && event.touches.length > 0) ?
      event.touches[0] :
      (event.changedTouches && event.changedTouches.length > 0 ? event.changedTouches[0] : undefined)
    if (!point) {
      return undefined
    }
    return {
      x: Number(point.x),
      y: Number(point.y)
    }
  }

  private async refreshLibraryGames(showToast: boolean = false): Promise<void> {
    const refreshToken = this.libraryRefreshToken + 1
    this.libraryRefreshToken = refreshToken
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.applyLibraryGames([])
      if (showToast) {
        this.showToastMessage('刷新失败 CONTEXT_MISSING')
      }
      return
    }

    let sourceRecords: LibraryRecord[] = []
    try {
      const sources = await scanLibraryRomSources(context, () => this.isCurrentLibraryRefresh(refreshToken))
      if (!sources) {
        return
      }
      sourceRecords = buildLibraryRecordsFromSources(sources)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'ROM', `刷新库列表失败: ${message}`)
      if (!this.isCurrentLibraryRefresh(refreshToken)) {
        return
      }
      if (showToast) {
        this.showToastMessage('刷新失败 LIB_SCAN_ERROR')
      }
      return
    }

    if (!this.isCurrentLibraryRefresh(refreshToken)) {
      return
    }

    const syncedRecords = await syncLibraryIndex(context, sourceRecords)
    if (!this.isCurrentLibraryRefresh(refreshToken)) {
      return
    }
    this.applyLibraryGames(getReadyLibraryRecords(syncedRecords))
    if (showToast) {
      this.showToastMessage('已刷新库 SYNCED')
    }
  }

  private applyLibraryGames(games: LibraryRecord[]): void {
    this.allGames = sortAllLibraryRecords(games)
    const recentGames = buildRecentLibraryRecords(this.allGames, 2)
    if (this.highlightedRecentGameId.length > 0 &&
      recentGames.findIndex((item: LibraryRecord) => item.id === this.highlightedRecentGameId) < 0) {
      this.highlightedRecentGameId = ''
    }
    const platforms = buildLibraryPlatforms(this.allGames)
    if (this.selectedPlatform !== 'ALL' && !platforms.includes(this.selectedPlatform)) {
      this.selectedPlatform = 'ALL'
    }
  }

  private getDisplayPlatformFilters(): string[] {
    return buildDisplayPlatformFilters(this.allGames)
  }

  private onSearchKeywordChange(value: string): void {
    this.searchKeyword = value
    const trimmed = value.trim()
    this.clearSearchTimer()
    if (trimmed.length === 0) {
      this.searchBusy = false
      this.showSearchResults = false
      this.updateSpinnerLoop()
      return
    }
    this.searchBusy = true
    this.updateSpinnerLoop()
    this.searchTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.searchBusy = false
      this.showSearchResults = true
      this.searchTimer = -1
      this.updateSpinnerLoop()
    }, 180)
  }

  private hideSearchResults(): void {
    this.showSearchResults = false
  }

  private hideSearchResultsIfOpened(): void {
    if (!this.showSearchResults) {
      return
    }
    this.hideSearchResults()
  }

  private openGame(_item: LibraryRecord): void {
    if (_item.preferredCoreId.length === 0 || _item.romFile.length === 0) {
      this.showToastMessage('当前条目暂不支持启动')
      return
    }
    this.highlightedRecentGameId = _item.id
    setPendingLibraryLaunchRequest({
      coreId: _item.preferredCoreId,
      romFile: _item.romFile,
      autoStart: true
    })
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LibretroGamePage',
      params: {
        coreId: _item.preferredCoreId,
        romFile: _item.romFile,
        autoStart: true
      }
    }).catch((err: Error) => {
      console.error(`[LibraryPage] 跳转游戏页失败: ${err.message}`)
    })
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

  private triggerRefresh(): void {
    if (this.refreshing) {
      return
    }
    this.refreshing = true
    this.pullRefreshHeight = 64
    this.pullRefreshOpacity = 1
    this.showSearchResults = false
    this.updateSpinnerLoop()
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer)
    }
    this.refreshTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.refreshTimer = -1
      this.finishPullRefresh()
    }, 300)
  }

  private async finishPullRefresh(): Promise<void> {
    await this.refreshLibraryGames(true)
    if (!this.pageActive) {
      return
    }
    this.refreshing = false
    this.pullRefreshHeight = 0
    this.pullRefreshOpacity = 0
    this.updateSpinnerLoop()
  }

  private onMainContentTouch(event: TouchEvent): void {
    const point = this.resolveTouchPoint(event)
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      if (!point) {
        return
      }
      this.pullStartY = point.y
      this.pullTracking = this.scrollOffsetY <= 1 && !this.refreshing
      return
    }
    if (!this.pullTracking || !point) {
      return
    }
    if (eventType === TouchType.Move) {
      const distance = point.y - this.pullStartY
      if (distance <= 0) {
        this.pullRefreshHeight = 0
        this.pullRefreshOpacity = 0
        this.updateSpinnerLoop()
        return
      }
      const nextHeight = Math.min(distance * 0.4, 80)
      this.pullRefreshHeight = nextHeight
      this.pullRefreshOpacity = nextHeight / 80
      this.updateSpinnerLoop()
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.pullTracking = false
      if (this.pullRefreshHeight > 60) {
        this.triggerRefresh()
      } else {
        this.pullRefreshHeight = 0
        this.pullRefreshOpacity = 0
        this.updateSpinnerLoop()
      }
    }
  }

  private onMainWillScroll(
    _xOffset: number,
    _yOffset: number,
    _scrollState: number,
    _scrollSource: number
  ): void {
    const currentOffset = Math.max(0, Number(this.scroller.currentOffset().yOffset))
    this.scrollOffsetY = currentOffset
    if (this.bottomLoaderActive && currentOffset < 360) {
      this.bottomLoaderActive = false
      if (this.bottomLoaderTimer !== -1) {
        clearTimeout(this.bottomLoaderTimer)
        this.bottomLoaderTimer = -1
      }
      this.updateSpinnerLoop()
    }
  }

  private onReachEnd(): void {
    this.bottomLoaderActive = true
    this.updateSpinnerLoop()
    if (this.bottomLoaderTimer !== -1) {
      clearTimeout(this.bottomLoaderTimer)
    }
    this.bottomLoaderTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.bottomLoaderActive = false
      this.bottomLoaderTimer = -1
      this.updateSpinnerLoop()
    }, 1200)
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[LibraryPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[LibraryPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  private onCardTouch(event: TouchEvent, item: LibraryRecord): void {
    const point = this.resolveTouchPoint(event)
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.cardLongPressed = false
      this.cardTouchMoved = false
      if (point) {
        this.cardTouchStartX = point.x
        this.cardTouchStartY = point.y
      }
      this.clearLongPressTimer()
      this.longPressTimer = setTimeout(() => {
        if (!this.pageActive) {
          return
        }
        this.cardLongPressed = true
        this.highlightedRecentGameId = item.id
        this.contextMenuGame = item
        this.showContextMenu = true
      }, 600)
      return
    }
    if (eventType === TouchType.Move) {
      if (!point) {
        return
      }
      const deltaX = Math.abs(point.x - this.cardTouchStartX)
      const deltaY = Math.abs(point.y - this.cardTouchStartY)
      if (deltaX > 10 || deltaY > 10) {
        this.cardTouchMoved = true
        this.clearLongPressTimer()
      }
      return
    }
    if (eventType === TouchType.Up) {
      this.clearLongPressTimer()
      if (!this.cardLongPressed && !this.cardTouchMoved) {
        this.openGame(item)
      }
      this.cardLongPressed = false
      this.cardTouchMoved = false
      return
    }
    if (eventType === TouchType.Cancel) {
      this.clearLongPressTimer()
      this.cardLongPressed = false
      this.cardTouchMoved = false
    }
  }

  private closeContextMenu(): void {
    this.showContextMenu = false
    this.contextMenuGame = undefined
  }

  private async deleteGame(item: LibraryRecord): Promise<void> {
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    if (item.sourceType !== 'IMPORTED') {
      this.showToastMessage('内置资源暂不支持删除')
      return
    }
    try {
      await fs.unlink(item.romFile)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Delete', `删除文件失败: ${message}`)
    }
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    await removeLibraryRecord(context, item.romFile)
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    await this.refreshLibraryGames()
  }

  private launchFromContext(): void {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    this.openGame(target)
  }

  private showDetailsFromContext(): void {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    this.openDetails(target)
  }

  private getNextCoverKey(item: LibraryRecord): string {
    const currentIndex = this.coverCycleKeys.findIndex((value: string) => value === item.coverKey)
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

  private async cycleCoverFromContext(): Promise<void> {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('封面更新失败 CONTEXT_MISSING')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    if (!updated) {
      this.showToastMessage('封面更新失败 COVER_WRITE_FAIL')
      return
    }
    this.highlightedRecentGameId = updated.id
    await this.refreshLibraryGames()
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    this.showToastMessage('已切换内置封面 COVER_UPDATED')
  }

  private openDetails(item: LibraryRecord): void {
    setPendingLibraryDetailRequest({
      romFile: item.romFile
    })
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LibraryDetailPage',
      params: {
        romFile: item.romFile
      }
    }).catch((err: Error) => {
      LogHelper.error('LibraryPage', 'Route', `跳转详情页失败: ${err.message}`)
      this.showToastMessage('详情页打开失败 DETAIL_ROUTE_FAIL')
    })
  }

  private deleteFromContext(): void {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    void this.deleteSaveFilesFromContext(target)
  }

  private async deleteSaveFilesFromContext(target: LibraryRecord): Promise<void> {
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('存档删除失败 CONTEXT_MISSING')
      return
    }
    try {
      const result: LibrarySavePurgeResult = await purgeSaveFilesForBaseName(
        context,
        target.fileName,
        () => this.isCurrentPageAction(actionToken)
      )
      if (result.cancelled) {
        return
      }
      if (result.deletedCount === 0) {
        this.showToastMessage('未找到对应存档 SAVE_EMPTY')
        return
      }
      this.showToastMessage(`已删除 ${result.deletedCount} 个存档 SAVE_PURGED`)
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('存档删除失败 SAVE_PURGE_FAIL')
    }
  }

  @Builder
  private Spinner(size: number, borderWidth: number, activeColor: string, trackColor: string) {
    Stack() {
      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .border({ width: borderWidth, color: trackColor, style: BorderStyle.Solid })

      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .border({
          width: { top: borderWidth, right: borderWidth },
          color: activeColor,
          style: BorderStyle.Solid
        })
        .rotate({ angle: this.spinnerAngle })
    }
  }

  @Builder
  private PullRefreshArea() {
    Column({ space: 6 }) {
      this.Spinner(26, 2, EmuColors.primary, '#3300FF41')

      Text(this.refreshing ? '正在扫描游戏库' : '扫描游戏库')
        .fontSize(9)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
        .letterSpacing(1.8)
    }
    .width('100%')
    .height(this.pullRefreshHeight)
    .opacity(this.pullRefreshOpacity)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .clip(true)
  }

  @Builder
  private SearchAndTelemetry() {
    LibrarySearchPanel({
      keyword: this.searchKeyword,
      searchBusy: this.searchBusy,
      showSearchResults: this.showSearchResults,
      searchResults: this.searchResults,
      telemetryCells: getLibraryTelemetryCells(this.allGames),
      telemetryBars: getLibraryTelemetryBars(this.allGames),
      platforms: this.getDisplayPlatformFilters(),
      selectedPlatform: this.selectedPlatform,
      spinnerAngle: this.spinnerAngle,
      onKeywordChange: (value: string) => {
        this.onSearchKeywordChange(value)
      },
      onSearchResultLaunch: (item: LibraryRecord) => {
        this.searchKeyword = item.title
        this.hideSearchResults()
        this.openGame(item)
      },
      onPlatformChange: (value: string) => {
        this.selectedPlatform = value
      }
    })
  }

  @Builder
  private GameSections() {
    LibraryGameSections({
      state: {
        recentGames: this.filteredRecentGames,
        games: this.filteredGames,
        highlightedRecentGameId: this.highlightedRecentGameId,
        bottomLoaderActive: this.bottomLoaderActive,
        spinnerAngle: this.spinnerAngle
      },
      onCardTouch: (event: TouchEvent, item: LibraryRecord) => {
        this.onCardTouch(event, item)
      },
      onHideSearchResults: () => {
        this.hideSearchResultsIfOpened()
      }
    })
  }

  @Builder
  private MainContent() {
    Scroll(this.scroller) {
      Column({ space: 28 }) {
        this.PullRefreshArea()

        this.SearchAndTelemetry()

        this.GameSections()
      }
      .width('100%')
      .padding({ top: 24, bottom: 40 })
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .onWillScroll((xOffset: number, yOffset: number, scrollState: number, scrollSource: number) => {
      this.onMainWillScroll(xOffset, yOffset, scrollState, scrollSource)
    })
    .onReachEnd(() => {
      this.onReachEnd()
    })
    .onTouch((event: TouchEvent) => {
      this.onMainContentTouch(event)
    })
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
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
        .letterSpacing(0.8)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
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
          titleText: 'EMU_OS // 0.1',
          titleIcon: 'terminal',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18
        })

        Row() {
          Column() {
            this.MainContent()
          }
          .width('100%')
          .constraintSize({ maxWidth: 460 })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 24, right: 24 })
        .justifyContent(FlexAlign.Center)

        EmuBottomNav({
          items: createEmuBottomNavItems('library'),
          activeFontColor: EmuColors.primary,
          inactiveFontColor: '#FF666666',
          indicatorStyle: 'dot',
          overallOpacity: 1,
          panelBackgroundColor: '#FF000000',
          onItemClick: (key: string) => {
            this.onBottomNavClick(key)
          }
        })
      }

      if (this.showToast) {
        this.SuccessToast()
      }

      if (this.showContextMenu) {
        LibraryContextMenuOverlay({
          onClose: () => {
            this.closeContextMenu()
          },
          onLaunch: () => {
            this.launchFromContext()
          },
          onDetails: () => {
            this.showDetailsFromContext()
          },
          onCoverChange: () => {
            void this.cycleCoverFromContext()
          },
          onDeleteSaves: () => {
            this.deleteFromContext()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
