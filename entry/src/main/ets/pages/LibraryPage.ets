import { common } from '@kit.AbilityKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuCoverArt } from '../components/EmuCoverArt'
import { LibraryContextMenuOverlay } from '../components/LibraryContextMenuOverlay'
import { LibraryGameSections } from '../components/LibraryGameSections'
import { EmuColors } from '../common/EmuUiTokens'
import { setPendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { ErrorCodeUtils, FileErrorCodes } from '../common/ErrorCodes'
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
  formatLastPlayedRelative,
  getLastPlayedLibraryRecord,
  getLibraryTelemetryCells,
  hasLibraryTelemetryData
} from '../common/LibraryRuntimeTelemetryPresenter'
import {
  LibrarySavePurgeResult,
  purgeSaveFilesForBaseName
} from '../common/LibrarySaveFilePurger'
import { setPendingLibraryDetailRequest } from '../common/LibraryDetailBridge'
import { scanLibraryRomSources } from '../common/RuntimeRomSourceScanner'
import { deleteImportedRomFile } from '../common/RomImportService'
import LogHelper from '../common/LogHelper'

interface TouchPoint {
  x: number
  y: number
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
struct LibraryPage {
  @Local private selectedPlatform: string = 'ALL'
  @Local private searchKeyword: string = ''
  @Local private allGames: LibraryRecord[] = []
  @Local private searchBusy: boolean = false
  @Local private showSearchResults: boolean = false
  @Local private showContextMenu: boolean = false
  @Local private contextMenuGame: LibraryRecord | undefined = undefined
  @Local private highlightedRecentGameId: string = ''
  @Local private showToast: boolean = false
  @Local private toastMessage: string = '已刷新游戏库'
  @Local private pullRefreshHeight: number = 0
  @Local private pullRefreshOpacity: number = 0
  @Local private refreshing: boolean = false
  @Local private bottomLoaderActive: boolean = false
  @Local private libraryLoadFailed: boolean = false
  private searchTimer: number = -1
  private toastTimer: number = -1
  private refreshTimer: number = -1
  private bottomLoaderTimer: number = -1
  private longPressTimer: number = -1
  private pageActive: boolean = false
  private libraryRefreshToken: number = 0
  private pageActionToken: number = 0
  private readonly coverCycleKeys: string[] = ['', 'moss_signal', 'aurora_grid', 'ember_glow']
  private readonly coverPalette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331']
  private readonly navItems = createEmuBottomNavItems('library')
  private pullTracking: boolean = false
  private pullStartY: number = 0
  private scrollOffsetY: number = 0
  private cardTouchStartX: number = 0
  private cardTouchStartY: number = 0
  private cardTouchMoved: boolean = false
  private cardLongPressed: boolean = false
  @Local private cachedFilteredGames: LibraryRecord[] = []
  @Local private cachedFilteredRecentGames: LibraryRecord[] = []
  @Local private cachedSearchResults: LibraryRecord[] = []
  @Local private cachedDisplayPlatformFilters: string[] = []
  @Local private hasLastPlayed: boolean = false
  @Local private lastPlayedTitle: string = ''
  @Local private lastPlayedPlatform: string = ''
  @Local private lastPlayedRelative: string = ''
  private lastPlayedRecord: LibraryRecord | undefined = undefined
  // 折叠屏适配状态
  @Local private currentFoldMode: 'single' | 'dual' | 'triple' = 'single'
  @Local private selectedGameForDetail: LibraryRecord | undefined = undefined
  aboutToAppear(): void {
    this.pageActive = true
    void this.refreshLibraryGames()
      }

  aboutToDisappear(): void {
    this.pageActive = false
    this.libraryRefreshToken += 1
    this.pageActionToken += 1
    this.clearSearchTimer()
    this.clearLongPressTimer()
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
    return this.cachedFilteredGames
  }

  private get filteredRecentGames(): LibraryRecord[] {
    return this.cachedFilteredRecentGames
  }

  private get searchResults(): LibraryRecord[] {
    return this.cachedSearchResults
  }

  private recomputeFilteredCaches(): void {
    this.cachedFilteredGames = filterLibraryGames(this.allGames, this.selectedPlatform, this.searchKeyword)
    this.cachedFilteredRecentGames = filterRecentLibraryGames(this.allGames, this.selectedPlatform, this.searchKeyword)
    this.cachedSearchResults = buildLibrarySearchResults(this.allGames, this.selectedPlatform, this.searchKeyword)
    this.cachedDisplayPlatformFilters = buildDisplayPlatformFilters(this.allGames)
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
      this.libraryLoadFailed = true
      this.applyLibraryGames([])
      if (showToast) {
        this.showToastMessage('现在还读不到游戏库，请稍后再试')
      }
      return
    }

    let readyRecords: LibraryRecord[] | undefined = undefined
    try {
      const sources = await scanLibraryRomSources(context, () => this.isCurrentLibraryRefresh(refreshToken))
      if (!sources) {
        return
      }
      const sourceRecords = buildLibraryRecordsFromSources(sources)
      if (!this.isCurrentLibraryRefresh(refreshToken)) {
        return
      }

      const syncedRecords = await syncLibraryIndex(context, sourceRecords)
      if (!this.isCurrentLibraryRefresh(refreshToken)) {
        return
      }
      readyRecords = getReadyLibraryRecords(syncedRecords)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'ROM', `刷新库列表失败: ${message}`)
      if (!this.isCurrentLibraryRefresh(refreshToken)) {
        return
      }
      this.libraryLoadFailed = true
      this.applyLibraryGames([])
      if (showToast) {
        // 使用错误码提供用户友好的错误消息
        const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_LIST_ERROR.numericCode)
        this.showToastMessage(userMsg)
      }
      return
    }

    if (!this.isCurrentLibraryRefresh(refreshToken) || !readyRecords) {
      return
    }
    this.libraryLoadFailed = false
    this.applyLibraryGames(readyRecords)
    if (showToast) {
      this.showToastMessage('已刷新游戏库')
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
    this.refreshLastPlayedChip()
    this.recomputeFilteredCaches()
  }

  private refreshLastPlayedChip(): void {
    const record = getLastPlayedLibraryRecord(this.allGames)
    if (record && record.preferredCoreId.length > 0 && record.romFile.length > 0) {
      this.lastPlayedRecord = record
      this.lastPlayedTitle = record.title
      this.lastPlayedPlatform = record.platform
      this.lastPlayedRelative = formatLastPlayedRelative(record.lastRuntimeUpdatedAt)
      this.hasLastPlayed = true
    } else {
      this.lastPlayedRecord = undefined
      this.hasLastPlayed = false
    }
  }

  private getDisplayPlatformFilters(): string[] {
    return this.cachedDisplayPlatformFilters
  }

  private onSearchKeywordChange(value: string): void {
    this.searchKeyword = value
    this.recomputeFilteredCaches()
    const trimmed = value.trim()
    this.clearSearchTimer()
    if (trimmed.length === 0) {
      this.searchBusy = false
      this.showSearchResults = false
            return
    }
    this.searchBusy = true
        this.searchTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.searchBusy = false
      this.showSearchResults = true
      this.searchTimer = -1
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
      this.showToastMessage('当前条目缺少可启动的核心或游戏文件')
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
      LogHelper.error('LibraryPage', 'Route', `跳转游戏页失败: ${err.message}`)
      this.showToastMessage('这款游戏现在还打不开，请稍后再试')
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
    const refreshToken = this.libraryRefreshToken + 1
    await this.refreshLibraryGames(true)
    if (!this.isCurrentLibraryRefresh(refreshToken)) {
      return
    }
    this.refreshing = false
    this.pullRefreshHeight = 0
    this.pullRefreshOpacity = 0
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
                return
      }
      const nextHeight = Math.min(distance * 0.4, 80)
      this.pullRefreshHeight = nextHeight
      this.pullRefreshOpacity = nextHeight / 80
            return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.pullTracking = false
      if (this.pullRefreshHeight > 60) {
        this.triggerRefresh()
      } else {
        this.pullRefreshHeight = 0
        this.pullRefreshOpacity = 0
              }
    }
  }

  private onMainWillScroll(yOffset: number): void {
    const currentOffset = Math.max(0, yOffset)
    this.scrollOffsetY = currentOffset
    if (this.bottomLoaderActive && currentOffset < 360) {
      this.bottomLoaderActive = false
      if (this.bottomLoaderTimer !== -1) {
        clearTimeout(this.bottomLoaderTimer)
        this.bottomLoaderTimer = -1
      }
          }
  }

  private onReachEnd(): void {
    this.bottomLoaderActive = true
        if (this.bottomLoaderTimer !== -1) {
      clearTimeout(this.bottomLoaderTimer)
    }
    this.bottomLoaderTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.bottomLoaderActive = false
      this.bottomLoaderTimer = -1
          }, 1200)
  }

  private suspendBeforeRoute(): void {
    this.pageActive = false
    this.libraryRefreshToken += 1
    this.pageActionToken += 1
    this.clearSearchTimer()
    this.clearLongPressTimer()
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
    this.searchBusy = false
    this.refreshing = false
    this.bottomLoaderActive = false
    this.showSearchResults = false
    this.pullRefreshHeight = 0
    this.pullRefreshOpacity = 0
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    this.suspendBeforeRoute()
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('LibraryPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.pageActive = true
      this.showToastMessage('这个页面现在还打不开，请稍后再试')
    })
  }

  private openImportEntryPage(): void {
    const route = 'pages/ImportEntryPage'
    this.suspendBeforeRoute()
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('LibraryPage', 'Route', `pushUrl ${route} failed: ${err.message}`)
      this.pageActive = true
      this.showToastMessage('导入页面现在还打不开，请稍后再试')
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
        // 双折态/三折态：点击显示详情
        if (this.currentFoldMode === 'dual' || this.currentFoldMode === 'triple') {
          this.selectedGameForDetail = item
        } else {
          // 单折态：直接启动游戏
          this.openGame(item)
        }
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
      this.showToastMessage('内置游戏暂不支持删除')
      return
    }
    try {
      await deleteImportedRomFile(context, item.romFile)
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Delete', `删除文件失败: ${message}`)
      // 使用错误码提供具体错误信息
      const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_WRITE_ERROR.numericCode)
      this.showToastMessage(userMsg)
      return
    }
    if (!this.isCurrentPageAction(actionToken)) {
      return
    }
    try {
      await removeLibraryRecord(context, item.romFile)
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      await this.refreshLibraryGames()
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Delete', `删除库记录失败: ${message}`)
      this.showToastMessage(ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_WRITE_ERROR.numericCode))
    }
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

  private async cycleCoverFromContext(): Promise<void> {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    const actionToken = this.beginPageAction()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('现在还不能切换封面样式，请稍后再试')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    try {
      const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      if (!updated) {
        this.showToastMessage('没有找到要更新的游戏条目')
        return
      }
      this.highlightedRecentGameId = updated.id
      await this.refreshLibraryGames()
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      this.showToastMessage('已切换封面样式')
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Cover', `更新封面失败: ${message}`)
      this.showToastMessage('封面样式没有更新成功，请稍后重试')
    }
  }

  private openDetails(item: LibraryRecord): void {
    // 双折态/三折态：在右侧显示详情，不跳转
    if (this.currentFoldMode === 'dual' || this.currentFoldMode === 'triple') {
      this.selectedGameForDetail = item
      return
    }
    // 单折态：跳转到详情页
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
      this.showToastMessage('这条游戏详情现在还打不开，请稍后再试')
    })
  }

  // 折叠态检测：根据屏幕宽高比判断折叠态
  private detectFoldMode(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return
    }
    const aspectRatio = width / height
    // 折叠态判断阈值（基于华为折叠屏设备实测数据）
    // 单折态（竖屏）：宽高比 < 1.2
    // 双折态（半展开）：1.2 <= 宽高比 < 2.0
    // 三折态（全展开）：宽高比 >= 2.0
    let newMode: 'single' | 'dual' | 'triple' = 'single'
    if (aspectRatio >= 2.0) {
      newMode = 'triple'
    } else if (aspectRatio >= 1.2) {
      newMode = 'dual'
    } else {
      newMode = 'single'
    }
    if (newMode !== this.currentFoldMode) {
      LogHelper.info('LibraryPage', 'Foldable', `折叠态切换: ${this.currentFoldMode} -> ${newMode} (${width}x${height}, AR=${aspectRatio.toFixed(2)})`)
      this.currentFoldMode = newMode
      // 切换到单折态时清除详情选择
      if (newMode === 'single') {
        this.selectedGameForDetail = undefined
      }
    }
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
      this.showToastMessage('现在还不能管理这款游戏的存档，请稍后再试')
      return
    }
    try {
      const result: LibrarySavePurgeResult = await purgeSaveFilesForBaseName(
        context,
        target.fileName,
        () => this.isCurrentPageAction(actionToken)
      )
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      if (result.cancelled) {
        return
      }
      if (result.deletedCount === 0) {
        this.showToastMessage('没有找到可删除的存档')
        return
      }
      this.showToastMessage(`已删除 ${result.deletedCount} 个存档`)
    } catch (err) {
      if (!this.isCurrentPageAction(actionToken)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('存档没有删除成功，请稍后重试')
    }
  }

  @Builder
  private PullRefreshArea() {
    Column({ space: 6 }) {
      SpinnerLine({ active: this.searchBusy || this.refreshing || this.bottomLoaderActive || this.pullRefreshHeight > 0 })

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
  private LastPlayedChip() {
    Row({ space: 12 }) {
      Text('▶')
        .fontSize(18)
        .fontColor(EmuColors.primary)
        .fontWeight(FontWeight.Bold)

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text('继续')
            .fontSize(9)
            .fontColor('#000000')
            .fontWeight(FontWeight.Bold)
            .letterSpacing(1.6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(EmuColors.primary)
            .borderRadius(2)

          Text('最近继续')
            .fontSize(9)
            .fontColor(EmuColors.primary)
            .fontFamily('monospace')
            .letterSpacing(1.6)
            .opacity(0.7)
        }

        Text(`${this.lastPlayedTitle} · ${this.lastPlayedPlatform} · ${this.lastPlayedRelative}`)
          .fontSize(13)
          .fontColor(EmuColors.onSurface)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(22)
        .fontColor(EmuColors.primary)
        .opacity(0.7)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 12 })
    .backgroundColor('#0F1A0F')
    .border({ width: 0.5, color: '#5500FF41', style: BorderStyle.Solid })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.lastPlayedRecord) {
        this.openGame(this.lastPlayedRecord as LibraryRecord)
      }
    })
  }

  @Builder
  private GameSections() {
    LibraryGameSections({
      recentGames: this.cachedFilteredRecentGames,
      games: this.cachedFilteredGames,
      highlightedRecentGameId: this.highlightedRecentGameId,
      bottomLoaderActive: this.bottomLoaderActive,
      loadFailed: this.libraryLoadFailed,
      searchKeyword: this.searchKeyword,
      searchBusy: this.searchBusy,
      showSearchResults: this.showSearchResults,
      searchResults: this.cachedSearchResults,
      telemetryCells: getLibraryTelemetryCells(this.allGames),
      showTelemetry: hasLibraryTelemetryData(this.allGames),
      platforms: this.cachedDisplayPlatformFilters,
      selectedPlatform: this.selectedPlatform,
      onCardTouch: (event: TouchEvent, item: LibraryRecord) => {
        this.onCardTouch(event, item)
      },
      onHideSearchResults: () => {
        this.hideSearchResultsIfOpened()
      },
      onListScrolled: (yOffset: number) => {
        this.onMainWillScroll(yOffset)
      },
      onListReachEnd: () => {
        this.onReachEnd()
      },
      onListTouched: (event: TouchEvent, yOffset: number) => {
        this.scrollOffsetY = Math.max(0, yOffset)
        this.onMainContentTouch(event)
      },
      onImportTap: () => {
        this.openImportEntryPage()
      },
      onSearchKeywordChange: (value: string) => {
        this.onSearchKeywordChange(value)
      },
      onSearchResultLaunch: (item: LibraryRecord) => {
        this.searchKeyword = item.title
        this.recomputeFilteredCaches()
        this.hideSearchResults()
        // 双折态/三折态：显示详情
        if (this.currentFoldMode === 'dual' || this.currentFoldMode === 'triple') {
          this.selectedGameForDetail = item
        } else {
          this.openGame(item)
        }
      },
      onPlatformChange: (value: string) => {
        this.selectedPlatform = value
        this.recomputeFilteredCaches()
      }
    })
      .layoutWeight(1)
      .width('100%')
  }

  @Builder
  private MainContent() {
    Column({ space: 28 }) {
      this.PullRefreshArea()

      if (this.hasLastPlayed) {
        this.LastPlayedChip()
      }

      this.GameSections()
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 0 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private GameDetailPanel() {
    if (!this.selectedGameForDetail) {
      this.EmptyGameDetailPanel()
    } else {
      ForEach(this.getSelectedGameDetailItems(), (game: LibraryRecord) => {
        this.SelectedGameDetailPanel(game)
      }, (game: LibraryRecord) => game.id)
    }
  }

  @Builder
  private EmptyGameDetailPanel() {
    // 空状态：提示选择游戏
    Column() {
      Text('选择游戏查看详情')
        .fontSize(14)
        .fontColor('#666666')
        .fontFamily('monospace')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#0A0A0A')
  }

  @Builder
  private SelectedGameDetailPanel(game: LibraryRecord) {
    Column({ space: 16 }) {
      // 封面区域
      Stack() {
        Column()
          .width('100%')
          .height(200)
          .backgroundColor(game.coverColor || this.coverPalette[0])
          .borderRadius(8)

        EmuCoverArt({
          coverKey: game.coverKey,
          coverUrl: game.coverUrl ?? '',
          variant: 'recent'
        })
          .width('100%')
          .height(200)
          .borderRadius(8)
      }

      // 标题与平台
      Column({ space: 8 }) {
        Text(game.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(game.platform)
          .fontSize(12)
          .fontColor(EmuColors.primary)
          .fontFamily('monospace')
          .letterSpacing(1.2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 元数据
      Column({ space: 12 }) {
        if (game.fileName.length > 0) {
          this.DetailRow('文件名', game.fileName)
        }
        if (game.preferredCoreId.length > 0) {
          this.DetailRow('核心', game.preferredCoreId)
        }
        if (this.getGamePlayTimeText(game).length > 0) {
          this.DetailRow('游玩时长', this.getGamePlayTimeText(game))
        }
      }
      .width('100%')

      // 操作按钮
      Column({ space: 12 }) {
        Button('启动游戏')
          .width('100%')
          .height(44)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(EmuColors.primary)
          .fontColor('#000000')
          .onClick(() => {
            this.openGame(game)
          })

        Button('查看完整详情')
          .width('100%')
          .height(44)
          .fontSize(14)
          .backgroundColor('#1A1A1A')
          .fontColor(EmuColors.primary)
          .border({ width: 1, color: EmuColors.primary })
          .onClick(() => {
            setPendingLibraryDetailRequest({
              romFile: game.romFile
            })
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/LibraryDetailPage',
              params: {
                romFile: game.romFile
              }
            }).catch((err: Error) => {
              LogHelper.error('LibraryPage', 'Route', `跳转详情页失败: ${err.message}`)
            })
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor('#0A0A0A')
    .border({ width: { left: 0.5 }, color: '#333333' })
  }

  private getGamePlayTimeText(game: LibraryRecord): string {
    if (!Number.isFinite(game.lastRuntimeUpdatedAt) || game.lastRuntimeUpdatedAt <= 0) {
      return ''
    }
    return formatLastPlayedRelative(game.lastRuntimeUpdatedAt)
  }

  private getSelectedGameDetailItems(): LibraryRecord[] {
    const items: LibraryRecord[] = []
    if (!this.selectedGameForDetail) {
      return items
    }
    items.push(this.selectedGameForDetail)
    return items
  }

  @Builder
  private DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor('#666666')
        .fontFamily('monospace')
        .width(80)

      Text(value)
        .fontSize(11)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private PlatformFilterPanel() {
    Column({ space: 12 }) {
      Text('平台筛选')
        .fontSize(12)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
        .letterSpacing(1.2)
        .margin({ bottom: 8 })

      Column({ space: 8 }) {
        ForEach(this.getPlatformFilterItems(), (platform: string) => {
          Row() {
            Text(platform === 'ALL' ? '全部' : platform)
              .fontSize(13)
              .fontColor(this.selectedPlatform === platform ? EmuColors.primary : '#666666')
              .fontWeight(this.selectedPlatform === platform ? FontWeight.Bold : FontWeight.Normal)
          }
          .width('100%')
          .height(36)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.selectedPlatform === platform ? '#1A1A1A' : 'transparent')
          .borderRadius(4)
          .onClick(() => {
            this.selectedPlatform = platform
            this.recomputeFilteredCaches()
          })
        }, (platform: string) => platform)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#0A0A0A')
    .border({ width: { right: 0.5 }, color: '#333333' })
  }

  private getPlatformFilterItems(): string[] {
    return [...this.cachedDisplayPlatformFilters]
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
          titleText: '碳影 / Carbon Shade',
          titleIcon: 'terminal',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18
        })

        Row() {
          // 根据折叠态选择布局
          if (this.currentFoldMode === 'single') {
            // 单折态：单栏布局
            Column() {
              this.MainContent()
            }
            .width('100%')
            .height('100%')
            .constraintSize({ maxWidth: 460 })
          } else if (this.currentFoldMode === 'dual') {
            // 双折态：左侧游戏列表（40%），右侧游戏详情（60%）
            Row() {
              Column() {
                this.MainContent()
              }
              .width('40%')
              .height('100%')

              Column() {
                this.GameDetailPanel()
              }
              .width('60%')
              .height('100%')
            }
            .width('100%')
            .height('100%')
          } else {
            // 三折态：左侧平台筛选（20%），中间游戏列表（50%），右侧游戏详情（30%）
            Row() {
              Column() {
                this.PlatformFilterPanel()
              }
              .width('20%')
              .height('100%')

              Column() {
                this.MainContent()
              }
              .width('50%')
              .height('100%')

              Column() {
                this.GameDetailPanel()
              }
              .width('30%')
              .height('100%')
            }
            .width('100%')
            .height('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: this.currentFoldMode === 'single' ? 24 : 0, right: this.currentFoldMode === 'single' ? 24 : 0 })
        .justifyContent(FlexAlign.Center)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const width = Number(newValue.width)
          const height = Number(newValue.height)
          if (width > 0 && height > 0) {
            this.detectFoldMode(width, height)
          }
        })

        EmuBottomNav({
          items: this.navItems,
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
