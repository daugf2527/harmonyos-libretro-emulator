import { router } from '@kit.ArkUI'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { GameCard } from '../components/GameCard'
import { LibrarySection } from '../components/LibrarySection'
import { PlatformChipBar } from '../components/PlatformChipBar'
import { EmuColors } from '../common/EmuUiTokens'

interface LibraryGameItem {
  id: string
  title: string
  subtitle: string
  platform: string
  coverColor: string
  coverKey: string
}

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
  @State private recentGames: LibraryGameItem[] = [
    {
      id: 'metroid-fusion',
      title: '银河战士 融合',
      subtitle: 'METROID FUSION',
      platform: 'GBA',
      coverColor: '#274530',
      coverKey: 'metroid_fusion'
    },
    {
      id: 'zelda-triforce',
      title: '塞尔达传说：众神三角',
      subtitle: 'THE LEGEND OF ZELDA',
      platform: 'SNES',
      coverColor: '#27405E',
      coverKey: 'zelda_triforce'
    }
  ]
  @State private allGames: LibraryGameItem[] = [
    {
      id: 'aria-of-sorrow',
      title: '恶魔城：晓月圆舞曲',
      subtitle: 'Castlevania: Aria of Sorrow',
      platform: 'GBA',
      coverColor: '#4E2A41',
      coverKey: 'aria_of_sorrow'
    },
    {
      id: 'chrono-trigger',
      title: '时空之轮',
      subtitle: 'Chrono Trigger',
      platform: 'SNES',
      coverColor: '#5A4331',
      coverKey: 'chrono_trigger'
    }
  ]
  @State private searchBusy: boolean = false
  @State private showSearchResults: boolean = false
  @State private searchResults: LibraryGameItem[] = []
  @State private showContextMenu: boolean = false
  @State private contextMenuGame: LibraryGameItem | undefined = undefined
  @State private showToast: boolean = false
  @State private toastMessage: string = '已刷新库 SYNCED'
  @State private pullRefreshHeight: number = 0
  @State private pullRefreshOpacity: number = 0
  @State private refreshing: boolean = false
  @State private bottomLoaderActive: boolean = false
  @State private spinnerAngle: number = 0
  private readonly platforms: string[] = ['ALL', 'FC', 'GBA', 'SNES', 'MD']
  private scroller: Scroller = new Scroller()
  private searchTimer: number = -1
  private spinnerTimer: number = -1
  private toastTimer: number = -1
  private refreshTimer: number = -1
  private bottomLoaderTimer: number = -1
  private longPressTimer: number = -1
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
    this.updateSpinnerLoop()
  }

  aboutToDisappear(): void {
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

  private get filteredGames(): LibraryGameItem[] {
    const keyword = this.searchKeyword.trim().toLowerCase()
    return this.allGames.filter((item: LibraryGameItem) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, keyword)
    })
  }

  private get filteredRecentGames(): LibraryGameItem[] {
    const keyword = this.searchKeyword.trim().toLowerCase()
    return this.recentGames.filter((item: LibraryGameItem) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, keyword)
    })
  }

  private isPlatformMatched(item: LibraryGameItem): boolean {
    return this.selectedPlatform === 'ALL' || item.platform === this.selectedPlatform
  }

  private matchesKeyword(item: LibraryGameItem, keyword: string): boolean {
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

  private getSearchSource(): LibraryGameItem[] {
    const merged: LibraryGameItem[] = [...this.recentGames, ...this.allGames]
    return merged.filter((item: LibraryGameItem, index: number) => {
      return merged.findIndex((candidate: LibraryGameItem) => candidate.id === item.id) === index
    })
  }

  private buildSearchResults(query: string): LibraryGameItem[] {
    const normalized = query.toLowerCase()
    return this.getSearchSource().filter((item: LibraryGameItem) => {
      if (!this.isPlatformMatched(item)) {
        return false
      }
      return this.matchesKeyword(item, normalized)
    })
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

  private openGame(_item: LibraryGameItem): void {
    router.pushUrl({ url: 'pages/LibretroGamePage' }).catch((err: Error) => {
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
      this.refreshing = false
      this.pullRefreshHeight = 0
      this.pullRefreshOpacity = 0
      this.showToastMessage('已刷新库 SYNCED')
      this.refreshTimer = -1
      this.updateSpinnerLoop()
    }, 1200)
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
      router.pushUrl({ url: 'pages/LibretroGamePage' }).catch((err: Error) => {
        console.error(`[LibraryPage] 底部导航跳转失败: ${err.message}`)
      })
      return
    }

    if (key === 'system') {
      router.pushUrl({ url: 'pages/OnboardingPage' }).catch((err: Error) => {
        console.error(`[LibraryPage] 底部导航跳转失败: ${err.message}`)
      })
    }
  }

  private onCardTouch(event: TouchEvent, item: LibraryGameItem): void {
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

  private deleteGame(gameId: string): void {
    this.recentGames = this.recentGames.filter((item: LibraryGameItem) => item.id !== gameId)
    this.allGames = this.allGames.filter((item: LibraryGameItem) => item.id !== gameId)
    this.refreshSearchResultsIfNeeded()
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
    this.searchKeyword = target.title
    this.showToastMessage(`已定位 ${target.title} // INFO_META`)
  }

  private deleteFromContext(): void {
    const target = this.contextMenuGame
    this.closeContextMenu()
    if (!target) {
      return
    }
    this.deleteGame(target.id)
    this.showToastMessage(`已删除 ${target.title} // PURGE_DATA`)
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
          size: 20,
          opacityValue: 0.9
        })

        Stack() {
          if (this.searchKeyword.trim().length === 0) {
            Text('搜索游戏库')
              .fontSize(15)
              .fontColor('#66484848')
              .align(Alignment.CenterStart)
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
            ForEach(this.searchResults, (item: LibraryGameItem) => {
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
            }, (item: LibraryGameItem) => item.id)
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
    Row({ space: 16 }) {
      ForEach(this.filteredRecentGames, (item: LibraryGameItem) => {
        Column() {
          GameCard({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            variant: 'recent'
          })
        }
        .layoutWeight(1)
        .onTouch((event: TouchEvent) => {
          this.onCardTouch(event, item)
        })
      }, (item: LibraryGameItem) => item.id)
    }
    .width('100%')
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
          size: 14,
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
      ForEach(this.filteredGames, (item: LibraryGameItem) => {
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
      }, (item: LibraryGameItem) => item.id)
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
        .backgroundColor('#88000000')
        .backdropBlur(8)
        .onClick(() => {
          this.closeContextMenu()
        })

      Column({ space: 8 }) {
        Column({ space: 0 }) {
          Row({ space: 12 }) {
            EmuIcon({
              name: 'folder_open',
              tone: 'primary',
              size: 20
            })

            Column({ space: 3 }) {
              Text('立即启动')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.onSurface)

              Text('LAUNCH_EXE')
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor('#8AABABAB')
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.launchFromContext()
          })

          Row({ space: 12 }) {
            EmuIcon({
              name: 'explore',
              tone: 'muted',
              size: 20
            })

            Column({ space: 3 }) {
              Text('查看详情')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(EmuColors.onSurface)

              Text('INFO_META')
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor('#8AABABAB')
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.showDetailsFromContext()
          })

          Row({ space: 12 }) {
            EmuIcon({
              name: 'warning',
              tone: 'outline',
              size: 20
            })

            Column({ space: 3 }) {
              Text('删除项目')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#ED7F64')

              Text('PURGE_DATA')
                .fontSize(10)
                .fontFamily('monospace')
                .fontColor('#9A6D5954')
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.deleteFromContext()
          })
        }
        .width('100%')
        .backgroundColor('#E6141414')
        .backdropBlur(24)
        .borderRadius(14)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })

        Row() {
          Text('取消')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
        }
        .width('100%')
        .height(50)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC1A1A1A')
        .borderRadius(14)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
        .onClick(() => {
          this.closeContextMenu()
        })
      }
      .width('85%')
      .constraintSize({ maxWidth: 360 })
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
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
