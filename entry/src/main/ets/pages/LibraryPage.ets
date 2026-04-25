import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { GameCard } from '../components/GameCard'
import { LibrarySection } from '../components/LibrarySection'
import { PlatformChipBar } from '../components/PlatformChipBar'
import { getPreferredCoreIdForFile, listSandboxRomFiles } from '../common/RomImportService'
import { EmuColors } from '../common/EmuUiTokens'
import { setPendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import {
  buildRecentLibraryRecords,
  getReadyLibraryRecords,
  LibraryRecord,
  LibrarySourceType,
  removeLibraryRecord,
  sortAllLibraryRecords,
  syncLibraryIndex,
  updateLibraryRecordCover
} from '../common/LibraryRepository'
import { setPendingLibraryDetailRequest } from '../common/LibraryDetailBridge'
import LogHelper from '../common/LogHelper'

interface LibretroLibraryNapi {
  refactoredGetRawFileListAsync(resMgr: object, dir?: string): Promise<string[]>
}

interface LibraryRomFileSource {
  fileName: string
  romFile: string
  sourceType: LibrarySourceType
}

const nativeApi = testNapi as LibretroLibraryNapi

interface TouchPoint {
  x: number
  y: number
}

@Entry
@Component
struct LibraryPage {
  @State private selectedPlatform: string = 'ALL'
  @State private searchKeyword: string = ''
  @State private navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: 'LIBRARY', isActive: true },
    { key: 'engine', iconName: 'terminal', label: 'ENGINE', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: 'INPUT', isActive: false },
    { key: 'system', iconName: 'tune', label: 'SYSTEM', isActive: false }
  ]
  @State private recentGames: LibraryRecord[] = []
  @State private allGames: LibraryRecord[] = []
  @State private searchBusy: boolean = false
  @State private showSearchResults: boolean = false
  @State private searchResults: LibraryRecord[] = []
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
  @State private platforms: string[] = ['ALL']
  private scroller: Scroller = new Scroller()
  private searchTimer: number = -1
  private spinnerTimer: number = -1
  private toastTimer: number = -1
  private refreshTimer: number = -1
  private bottomLoaderTimer: number = -1
  private longPressTimer: number = -1
  private libraryRefreshToken: number = 0
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
    this.navItems = this.navItems.map((item: EmuBottomNavItem): EmuBottomNavItem => {
      return { key: item.key, iconName: item.iconName, label: item.label, isActive: item.key === 'library' }
    })
    this.refreshLibraryGames()
    this.updateSpinnerLoop()
  }

  aboutToDisappear(): void {
    this.libraryRefreshToken += 1
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

  private get filteredGames(): LibraryRecord[] {
    const keyword = this.searchKeyword.trim().toLowerCase()
    return this.allGames.filter((item: LibraryRecord) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, keyword)
    })
  }

  private get filteredRecentGames(): LibraryRecord[] {
    const keyword = this.searchKeyword.trim().toLowerCase()
    return this.recentGames.filter((item: LibraryRecord) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, keyword)
    })
  }

  private isPlatformMatched(item: LibraryRecord): boolean {
    return this.selectedPlatform === 'ALL' || item.platform === this.selectedPlatform
  }

  private matchesKeyword(item: LibraryRecord, keyword: string): boolean {
    if (keyword.length === 0) {
      return true
    }
    return item.title.toLowerCase().indexOf(keyword) >= 0 ||
      item.subtitle.toLowerCase().indexOf(keyword) >= 0 ||
      item.platform.toLowerCase().indexOf(keyword) >= 0
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

  private getSearchSource(): LibraryRecord[] {
    const merged: LibraryRecord[] = [...this.recentGames, ...this.allGames]
    return merged.filter((item: LibraryRecord, index: number) => {
      return merged.findIndex((candidate: LibraryRecord) => candidate.id === item.id) === index
    })
  }

  private buildSearchResults(query: string): LibraryRecord[] {
    const normalized = query.toLowerCase()
    return this.getSearchSource().filter((item: LibraryRecord) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, normalized)
    })
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

    const sources: LibraryRomFileSource[] = []
    try {
      const rawList: string[] = await nativeApi.refactoredGetRawFileListAsync(context.resourceManager, 'roms')
      if (refreshToken !== this.libraryRefreshToken) {
        return
      }
      rawList.filter((item: string) => item.length > 0).forEach((fileName: string) => {
        sources.push({
          fileName: fileName,
          romFile: `roms/${fileName}`,
          sourceType: 'BUNDLED'
        })
      })
      const localFiles = await listSandboxRomFiles(context.filesDir)
      if (refreshToken !== this.libraryRefreshToken) {
        return
      }
      localFiles.forEach((fileName: string) => {
        sources.push({
          fileName: fileName,
          romFile: `${context.filesDir}/roms/${fileName}`,
          sourceType: 'IMPORTED'
        })
      })
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryPage', 'ROM', `刷新库列表失败: ${message}`)
      if (refreshToken !== this.libraryRefreshToken) {
        return
      }
      if (showToast) {
        this.showToastMessage('刷新失败 LIB_SCAN_ERROR')
      }
      return
    }

    if (refreshToken !== this.libraryRefreshToken) {
      return
    }

    const syncedRecords = await syncLibraryIndex(context, this.buildLibraryGames(sources))
    if (refreshToken !== this.libraryRefreshToken) {
      return
    }
    this.applyLibraryGames(getReadyLibraryRecords(syncedRecords))
    if (showToast) {
      this.showToastMessage('已刷新库 SYNCED')
    }
  }

  private applyLibraryGames(games: LibraryRecord[]): void {
    this.allGames = sortAllLibraryRecords(games)
    this.recentGames = buildRecentLibraryRecords(games, 2)
    if (this.highlightedRecentGameId.length > 0 &&
      this.recentGames.findIndex((item: LibraryRecord) => item.id === this.highlightedRecentGameId) < 0) {
      this.highlightedRecentGameId = ''
    }
    this.platforms = this.buildPlatforms(this.allGames)
    if (this.selectedPlatform !== 'ALL' && !this.platforms.includes(this.selectedPlatform)) {
      this.selectedPlatform = 'ALL'
    }
    this.refreshSearchResultsIfNeeded()
  }

  private buildPlatforms(games: LibraryRecord[]): string[] {
    const platformSet: Set<string> = new Set()
    games.forEach((item: LibraryRecord) => {
      if (item.platform.length > 0) {
        platformSet.add(item.platform)
      }
    })
    return ['ALL', ...Array.from(platformSet).sort((left: string, right: string) => left.localeCompare(right))]
  }

  private buildLibraryGames(sources: LibraryRomFileSource[]): LibraryRecord[] {
    const uniqueSources = sources.filter((item: LibraryRomFileSource, index: number) => {
      return item.fileName.length > 0 &&
        sources.findIndex((candidate: LibraryRomFileSource) => candidate.romFile === item.romFile) === index
    })
    uniqueSources.sort((left: LibraryRomFileSource, right: LibraryRomFileSource) => left.fileName.localeCompare(right.fileName))
    const now = Date.now()
    const games: LibraryRecord[] = []
    uniqueSources.forEach((source: LibraryRomFileSource, index: number) => {
      const preferredCoreId = this.resolvePreferredCoreId(source.fileName)
      if (preferredCoreId.length === 0) {
        return
      }
      games.push({
        id: source.romFile,
        title: this.buildGameTitle(source.fileName),
        subtitle: source.fileName,
        platform: this.resolvePlatform(source.fileName),
        coverColor: this.buildCoverColor(index),
        coverKey: this.resolveCoverKey(source.fileName),
        romFile: source.romFile,
        preferredCoreId: preferredCoreId,
        fileName: source.fileName,
        sourceType: source.sourceType,
        status: 'READY',
        createdAt: now,
        importedAt: source.sourceType === 'IMPORTED' ? now : 0,
        updatedAt: now,
        lastSeenAt: now,
        lastPlayedAt: 0,
        playCount: 0,
        totalPlayTimeMs: 0,
        lastSessionDurationMs: 0,
        lastRuntimeUpdatedAt: 0,
        lastRuntimeFps: 0,
        lastRuntimeAudioBufferUsage: 0,
        lastRuntimeAudioUnderruns: 0,
        lastRuntimeAudioOverruns: 0,
        lastRuntimeVideoDrops: 0,
        lastRuntimeVideoDupes: 0,
        lastRuntimeVideoNulls: 0
      })
    })
    return games
  }

  private buildGameTitle(fileName: string): string {
    let nameOnly = fileName
    const slashIndex = fileName.lastIndexOf('/')
    if (slashIndex >= 0) {
      nameOnly = fileName.substring(slashIndex + 1)
    }
    const dotIndex = nameOnly.lastIndexOf('.')
    const baseName = dotIndex > 0 ? nameOnly.substring(0, dotIndex) : nameOnly
    return baseName.replace(/[_-]+/g, ' ')
  }

  private resolvePlatform(fileName: string): string {
    const ext = this.getFileExtension(fileName.toLowerCase())
    switch (ext) {
      case 'gb':
      case 'gbc':
      case 'dmg':
        return 'GB'
      case 'gba':
      case 'agb':
        return 'GBA'
      case 'nes':
      case 'fds':
      case 'unf':
      case 'unif':
        return 'FC'
      case 'smc':
      case 'sfc':
      case 'swc':
      case 'fig':
      case 'bs':
      case 'st':
      case 'gd3':
      case 'gd7':
      case 'dx2':
      case 'bsx':
        return 'SNES'
      case 'mdx':
      case 'md':
      case 'smd':
      case 'gen':
      case 'sms':
      case 'bms':
      case 'gg':
      case 'sg':
      case '68k':
      case 'sgd':
        return 'MD'
      case 'nds':
      case 'ids':
      case 'dsi':
        return 'NDS'
      case 'cue':
      case 'toc':
      case 'ccd':
      case 'pbp':
      case 'chd':
      case 'iso':
      case 'm3u':
      case 'cbn':
        return 'PS'
      case 'zip':
      case '7z':
        return 'ARCADE'
      default:
        return ext.length > 0 ? ext.toUpperCase() : 'ROM'
    }
  }

  private resolvePreferredCoreId(fileName: string): string {
    return getPreferredCoreIdForFile(fileName.toLowerCase())
  }

  private getFileExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    if (dotIndex < 0 || dotIndex === fileName.length - 1) {
      return ''
    }
    return fileName.substring(dotIndex + 1)
  }

  private buildCoverColor(index: number): string {
    const palette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331', '#2E4A52', '#4F2F2A', '#314B63']
    return palette[index % palette.length]
  }

  private resolveCoverKey(fileName: string): string {
    const normalized = fileName.toLowerCase()
    if (normalized.indexOf('metroid') >= 0 || normalized.indexOf('castlevania') >= 0 || normalized.indexOf('aria') >= 0) {
      return 'metroid_fusion'
    }
    if (normalized.indexOf('zelda') >= 0 || normalized.indexOf('chrono') >= 0 || normalized.indexOf('final fantasy') >= 0) {
      return 'zelda_triforce'
    }
    return ''
  }

  private refreshSearchResultsIfNeeded(): void {
    const query = this.searchKeyword.trim()
    if (query.length === 0) {
      this.searchResults = []
      this.showSearchResults = false
      this.searchBusy = false
      return
    }
    this.searchResults = this.buildSearchResults(query)
    this.showSearchResults = true
  }

  private onSearchKeywordChange(value: string): void {
    this.searchKeyword = value
    const trimmed = value.trim()
    this.clearSearchTimer()
    if (trimmed.length === 0) {
      this.searchBusy = false
      this.showSearchResults = false
      this.searchResults = []
      this.updateSpinnerLoop()
      return
    }
    this.searchBusy = true
    this.updateSpinnerLoop()
    this.searchTimer = setTimeout(() => {
      this.searchResults = this.buildSearchResults(trimmed)
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
      this.refreshTimer = -1
      this.finishPullRefresh()
    }, 300)
  }

  private async finishPullRefresh(): Promise<void> {
    await this.refreshLibraryGames(true)
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
      this.bottomLoaderActive = false
      this.bottomLoaderTimer = -1
      this.updateSpinnerLoop()
    }, 1200)
  }

  private onBottomNavClick(key: string): void {
    this.navItems = this.navItems.map((item: EmuBottomNavItem): EmuBottomNavItem => {
      return { key: item.key, iconName: item.iconName, label: item.label, isActive: item.key === key }
    })

    if (key === 'engine' || key === 'input') {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/LibretroGamePage' }).catch((err: Error) => {
        console.error(`[LibraryPage] 底部导航跳转失败: ${err.message}`)
      })
      return
    }

    if (key === 'system') {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/OnboardingPage' }).catch((err: Error) => {
        console.error(`[LibraryPage] 底部导航跳转失败: ${err.message}`)
      })
    }
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
    await removeLibraryRecord(context, item.romFile)
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
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('封面更新失败 CONTEXT_MISSING')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
    if (!updated) {
      this.showToastMessage('封面更新失败 COVER_WRITE_FAIL')
      return
    }
    this.highlightedRecentGameId = updated.id
    await this.refreshLibraryGames()
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

  private normalizeContentKey(value: string): string {
    return value.toLowerCase().replace(/[^a-z0-9]+/g, '')
  }

  private isSaveCandidate(fileName: string, baseName: string): boolean {
    const normalized = this.normalizeContentKey(fileName)
    return normalized.indexOf(baseName) === 0
  }

  private async deleteSaveFilesFromContext(target: LibraryRecord): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('存档删除失败 CONTEXT_MISSING')
      return
    }
    const saveDir = `${context.filesDir}/saves`
    const baseName = this.normalizeContentKey(target.fileName)
    try {
      const entries = await fs.listFile(saveDir)
      const candidates = entries.filter((item: string) => this.isSaveCandidate(item, baseName))
      if (candidates.length === 0) {
        this.showToastMessage('未找到对应存档 SAVE_EMPTY')
        return
      }
      for (let index = 0; index < candidates.length; index += 1) {
        await fs.unlink(`${saveDir}/${candidates[index]}`)
      }
      this.showToastMessage(`已删除 ${candidates.length} 个存档 SAVE_PURGED`)
    } catch (err) {
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

      Text(this.refreshing ? 'SYNCING_LIBRARY' : 'SYNC_INDEX')
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
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        EmuIcon({
          name: 'search',
          tone: 'muted',
          iconSize: 20,
          opacityValue: 0.9
        })

        Stack() {
          if (this.searchKeyword.trim().length === 0) {
            Text('搜索游戏库')
              .fontSize(15)
              .fontColor('#66484848')
              .align(Alignment.Start)
          }

          TextInput({ text: this.searchKeyword, placeholder: '' })
            .width('100%')
            .height(28)
            .fontSize(15)
            .fontColor(EmuColors.onSurface)
            .backgroundColor(Color.Transparent)
            .border({ width: 0 })
            .padding({ left: 0, right: 0 })
            .margin({ top: -1 })
            .onChange((value: string) => {
              this.onSearchKeywordChange(value)
            })
        }
        .layoutWeight(1)
        .height(28)

        if (this.searchBusy) {
          this.Spinner(16, 1.5, EmuColors.primary, '#2200FF41')
        }
      }
      .width('100%')
      .height(64)
      .padding({ left: 18, right: 18 })
      .backgroundColor('#0A0A0A')
      .borderRadius(8)
      .border({ width: 0.5, color: '#44757575', style: BorderStyle.Solid })
      .alignItems(VerticalAlign.Center)

      if (this.showSearchResults) {
        Column({ space: 2 }) {
          if (this.searchResults.length > 0) {
            ForEach(this.searchResults, (item: LibraryRecord) => {
              Row() {
                Text(item.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(EmuColors.onSurface)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(item.platform)
                  .fontSize(10)
                  .fontColor('#A000FF41')
                  .fontFamily('monospace')
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .borderRadius(4)
                  .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })
              }
              .width('100%')
              .height(42)
              .padding({ left: 12, right: 12 })
              .borderRadius(8)
              .onClick(() => {
                this.searchKeyword = item.title
                this.hideSearchResults()
                this.openGame(item)
              })
            }, (item: LibraryRecord) => item.id)
          } else {
            Text('无匹配结果')
              .fontSize(12)
              .fontColor(EmuColors.onSurfaceVariant)
              .fontStyle(FontStyle.Italic)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 12 })
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor('#F2141414')
        .backdropBlur(20)
        .borderRadius(12)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
      }

      Row({ space: 0 }) {
        this.TelemetryCell('CPU LOAD', '12.4%')
        this.TelemetryDivider()
        this.TelemetryCell('FPS', '60.0')
        this.TelemetryDivider()
        this.TelemetryCell('MEMORY', '1.2GB')

        Column({ space: 3 }) {
          Row({ space: 2 }) {
            Row().width(16).height(8).backgroundColor('#3300FF41')
            Row().width(16).height(12).backgroundColor('#5500FF41')
            Row().width(16).height(10).backgroundColor('#4A00FF41')
            Row().width(16).height(24).backgroundColor('#8800FF41')
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .padding({ left: 18 })
        .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .backgroundColor('#050505')
      .borderRadius(8)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .alignItems(VerticalAlign.Center)

      PlatformChipBar({
        items: this.platforms,
        selected: this.selectedPlatform,
        onChange: (value: string) => {
          this.selectedPlatform = value
          this.refreshSearchResultsIfNeeded()
        }
      })
    }
  }

  @Builder
  private TelemetryCell(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(9)
        .fontColor(EmuColors.onSurfaceVariant)
        .fontFamily('monospace')
        .letterSpacing(1.2)

      Row({ space: 8 }) {
        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(EmuColors.primary)

        Text(value)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurface)
      }
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TelemetryDivider() {
    Column()
      .width(1)
      .height(44)
      .backgroundColor('#26484848')
      .margin({ left: 12, right: 12 })
  }

  @Builder
  private RecentContent() {
    const featuredId = this.getHighlightedRecentGameId()
    Row({ space: 16 }) {
      ForEach(this.filteredRecentGames, (item: LibraryRecord) => {
        Column() {
          GameCard({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            variant: 'recent',
            isHighlighted: item.id === featuredId
          })
        }
        .layoutWeight(1)
        .onTouch((event: TouchEvent) => {
          this.onCardTouch(event, item)
        })
      }, (item: LibraryRecord) => item.id)
    }
    .width('100%')
  }

  private getHighlightedRecentGameId(): string {
    if (this.highlightedRecentGameId.length > 0) {
      return this.highlightedRecentGameId
    }
    return this.filteredRecentGames.length > 0 ? this.filteredRecentGames[0].id : ''
  }

  @Builder
  private AllGamesHeader() {
    Row() {
      Text('全部游戏')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Row({ space: 12 }) {
        Text('SORT: NAME')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)

        EmuIcon({
          name: 'tune',
          tone: 'muted',
          iconSize: 14,
          opacityValue: 0.85
        })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Bottom)
  }

  @Builder
  private AllGamesContent() {
    Column({ space: 18 }) {
      ForEach(this.filteredGames, (item: LibraryRecord) => {
        GameCard({
          title: item.title,
          subtitle: item.subtitle,
          platform: item.platform,
          coverColor: item.coverColor,
          coverKey: item.coverKey,
          variant: 'list'
        })
        .onTouch((event: TouchEvent) => {
          this.onCardTouch(event, item)
        })
      }, (item: LibraryRecord) => item.id)
    }
    .width('100%')
  }

  @Builder
  private BottomLoader() {
    Column({ space: 10 }) {
      this.Spinner(30, 2, EmuColors.primary, '#2F484848')

      Text(this.bottomLoaderActive ? 'RETRIEVING_MORE...' : 'LOADING_ASSETS')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(this.bottomLoaderActive ? EmuColors.primary : EmuColors.onSurfaceVariant)
        .letterSpacing(1.6)
    }
    .width('100%')
    .padding({ top: 26, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private MainContent() {
    Scroll(this.scroller) {
      Column({ space: 34 }) {
        this.PullRefreshArea()

        this.SearchAndTelemetry()

        Column({ space: 18 }) {
          LibrarySection({
            title: '最近运行',
            codeLabel: 'HISTORY_LOG'
          })
          this.RecentContent()
        }
        .onClick(() => {
          this.hideSearchResultsIfOpened()
        })

        Column({ space: 18 }) {
          this.AllGamesHeader()
          this.AllGamesContent()
          this.BottomLoader()
        }
        .onClick(() => {
          this.hideSearchResultsIfOpened()
        })
      }
      .width('100%')
      .padding({ top: 20, bottom: 40 })
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

  @Builder
  private ContextMenuOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#B8000000')
        .backdropBlur(14)
        .onClick(() => {
          this.closeContextMenu()
        })

      Column({ space: 18 }) {
        Column({ space: 0 }) {
          Row() {
            Text('启动游戏')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)
              .fontFamily('monospace')
              .letterSpacing(1)

            EmuIcon({
              name: 'play_arrow',
              tone: 'primary',
              iconSize: 20
            })
          }
          .width('100%')
          .height(54)
          .padding({ left: 18, right: 18 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.launchFromContext()
          })

          this.ActionMenuDivider()

          Row() {
            Text('查看详情')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)
              .fontFamily('monospace')
              .letterSpacing(0.8)

            EmuIcon({
              name: 'info',
              tone: 'on_surface',
              iconSize: 20
            })
          }
          .width('100%')
          .height(54)
          .padding({ left: 18, right: 18 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.showDetailsFromContext()
          })

          this.ActionMenuDivider()

          Row() {
            Text('修改封面')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)
              .fontFamily('monospace')
              .letterSpacing(0.8)

            EmuIcon({
              name: 'image_edit_auto',
              tone: 'on_surface',
              iconSize: 20
            })
          }
          .width('100%')
          .height(54)
          .padding({ left: 18, right: 18 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            void this.cycleCoverFromContext()
          })

          this.ActionMenuDivider()

          Row() {
            Text('删除存档')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.error)
              .fontFamily('monospace')
              .letterSpacing(0.8)

            EmuIcon({
              name: 'delete_forever',
              tone: 'outline',
              iconSize: 20
            })
          }
          .width('100%')
          .height(54)
          .padding({ left: 18, right: 18 })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.deleteFromContext()
          })
        }
        .width('100%')
        .backgroundColor('#F0141414')
        .backdropBlur(24)
        .borderRadius(16)
        .border({ width: 0.8, color: '#33FFFFFF', style: BorderStyle.Solid })
        .shadow({ radius: 30, color: '#99000000', offsetX: 0, offsetY: 10 })

        Row() {
          Text('取消 CANCEL')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .fontFamily('monospace')
            .letterSpacing(1.2)
        }
        .width('100%')
        .height(54)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC1A1A1A')
        .borderRadius(14)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
        .onClick(() => {
          this.closeContextMenu()
        })
      }
      .width(240)
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ActionMenuDivider() {
    Row()
      .width('100%')
      .height(1)
      .backgroundColor('#14FFFFFF')
      .margin({ left: 12, right: 12 })
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
        this.ContextMenuOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
