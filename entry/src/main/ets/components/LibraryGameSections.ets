import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { LibraryRecord } from '../common/LibraryRepository'
import { EmuTelemetryCellItem } from './EmuTelemetryPanel'
import { EmuButton, EmuButtonKind, EmuButtonShape, EmuButtonSize } from './EmuButton'
import { EmuIcon } from './EmuIcon'
import { GameCard } from './GameCard'
import { LibrarySection } from './LibrarySection'
import { LibrarySearchPanel } from './LibrarySearchPanel'

class LibraryDataSource implements IDataSource {
  private games: LibraryRecord[] = [];
  private listeners: DataChangeListener[] = [];

  public updateGames(games: LibraryRecord[]): void {
    this.games = games;
    this.listeners.forEach((listener) => {
      listener.onDataReloaded();
    });
  }

  totalCount(): number {
    return this.games.length;
  }

  getData(index: number): LibraryRecord {
    return this.games[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }
}

function buildLibraryRecordKey(item: LibraryRecord): string {
  return `${item.sourceType}:${item.romFile}:${item.id}`
}

@ReusableV2
@ComponentV2
struct LibraryGameListItem {
  @Param title: string = ''
  @Param subtitle: string = ''
  @Param platform: string = ''
  @Param coverColor: string = '#2C2C2C'
  @Param coverKey: string = ''
  @Param coverUrl: string = ''

  build() {
    GameCard({
      title: this.title,
      subtitle: this.subtitle,
      platform: this.platform,
      coverColor: this.coverColor,
      coverKey: this.coverKey,
      coverUrl: this.coverUrl,
      variant: 'list'
    })
  }
}

export interface LibraryGameSectionsState {
  recentGames: LibraryRecord[]
  games: LibraryRecord[]
  highlightedRecentGameId: string
  bottomLoaderActive: boolean
  spinnerAngle: number
  loadFailed: boolean
}

@ComponentV2
export struct LibraryGameSections {
  @Param recentGames: LibraryRecord[] = []
  @Param games: LibraryRecord[] = []
  @Param highlightedRecentGameId: string = ''
  @Param bottomLoaderActive: boolean = false
  @Param spinnerAngle: number = 0
  @Param loadFailed: boolean = false
  @Param searchKeyword: string = ''
  @Param searchBusy: boolean = false
  @Param showSearchResults: boolean = false
  @Param selectedPlatform: string = 'ALL'
  @Param searchResults: LibraryRecord[] = []
  @Param telemetryCells: EmuTelemetryCellItem[] = []
  @Param showTelemetry: boolean = true
  @Param platforms: string[] = ['ALL']
  @Event onCardTouch?: (event: TouchEvent, item: LibraryRecord) => void
  @Event onHideSearchResults?: () => void
  @Event onListScrolled?: (yOffset: number) => void
  @Event onListReachEnd?: () => void
  @Event onListTouched?: (event: TouchEvent, yOffset: number) => void
  @Event onImportTap?: () => void
  @Event onSearchKeywordChange?: (value: string) => void
  @Event onSearchResultLaunch?: (item: LibraryRecord) => void
  @Event onPlatformChange?: (value: string) => void
  private allGamesDataSource: LibraryDataSource = new LibraryDataSource();
  private listScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.allGamesDataSource.updateGames(this.games);
  }

  build() {
    List({ space: 18, scroller: this.listScroller }) {
      ListItem() {
        LibrarySearchPanel({
          keyword: this.searchKeyword,
          searchBusy: this.searchBusy,
          showSearchResults: this.showSearchResults,
          searchResults: this.searchResults,
          telemetryCells: this.telemetryCells,
          showTelemetry: this.showTelemetry,
          platforms: this.platforms,
          selectedPlatform: this.selectedPlatform,
          onKeywordChange: (value: string) => {
            this.onSearchKeywordChange?.(value)
          },
          onSearchResultLaunch: (item: LibraryRecord) => {
            this.onSearchResultLaunch?.(item)
          },
          onPlatformChange: (value: string) => {
            this.onPlatformChange?.(value)
          }
        })
      }

      ListItem() {
        Column({ space: 18 }) {
          LibrarySection({
            title: '最近运行',
            codeLabel: 'HISTORY_LOG'
          })
          this.RecentContent()
        }
        .width('100%')
      }

      ListItem() {
        Column() {
          this.AllGamesHeader()
        }
        .width('100%')
        .padding({ top: 10 })
      }

      LazyForEach(this.allGamesDataSource, (item: LibraryRecord) => {
        ListItem() {
          LibraryGameListItem({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            coverUrl: item.coverUrl ?? ''
          })
            .onTouch((event: TouchEvent) => {
              this.onCardTouch?.(event, item)
            })
        }
      }, (item: LibraryRecord) => buildLibraryRecordKey(item))

      if (this.bottomLoaderActive || (this.games.length === 0 && this.recentGames.length === 0)) {
        ListItem() {
          this.BottomLoader()
        }
      }
    }
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .cachedCount(2)
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState) => {
      this.onListScrolled?.(Math.max(0, Number(this.listScroller.currentOffset().yOffset)))
    })
    .onReachEnd(() => {
      this.onListReachEnd?.()
    })
    .onTouch((event: TouchEvent) => {
      this.onListTouched?.(event, Math.max(0, Number(this.listScroller.currentOffset().yOffset)))
    })
    .onClick(() => {
      this.onHideSearchResults?.()
    })
  }

  @Builder
  private RecentContent() {
    Row({ space: 16 }) {
      ForEach(this.recentGames, (item: LibraryRecord) => {
        Column() {
          GameCard({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            coverUrl: item.coverUrl ?? '',
            variant: 'recent',
            isHighlighted: item.id === this.getHighlightedRecentGameId()
          })
        }
        .layoutWeight(1)
        .onTouch((event: TouchEvent) => {
          this.onCardTouch?.(event, item)
        })
      }, (item: LibraryRecord) => buildLibraryRecordKey(item))
    }
    .width('100%')
  }

  @Builder
  private AllGamesHeader() {
    Row() {
      Text('全部游戏')
        .fontSize(EmuTypography.xl)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Row({ space: 12 }) {
        Text('排序：名称')
          .fontSize(EmuTypography.xs)
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
  private BottomLoader() {
    if (this.bottomLoaderActive) {
      Column({ space: 10 }) {
        this.Spinner(30, 2, EmuColors.primary, '#2F484848')

        Text('继续加载游戏...')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.6)
      }
      .width('100%')
      .padding({ top: 26, bottom: 12 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.games.length === 0 && this.recentGames.length === 0) {
      Column({ space: 12 }) {
        Text('📁')
          .fontSize(36)
          .opacity(0.6)
        Text(this.loadFailed ? '游戏库暂时没有读出来' : '游戏库为空')
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
        Text(this.loadFailed ?
          '这次没有拿到游戏库内容，请下拉重试，或稍后再回来。' :
          '下拉刷新，或从"导入"按钮添加 ROM')
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(0.6)

        if (!this.loadFailed) {
          EmuButton({
            label: '导入 ROM',
            kind: EmuButtonKind.PRIMARY,
            buttonSize: EmuButtonSize.MD,
            shape: EmuButtonShape.PILL,
            onTap: () => {
              this.onImportTap?.()
            }
          })
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding({ top: 36, bottom: 24 })
      .alignItems(HorizontalAlign.Center)
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

  private getHighlightedRecentGameId(): string {
    if (this.highlightedRecentGameId.length > 0) {
      return this.highlightedRecentGameId
    }
    return this.recentGames.length > 0 ? this.recentGames[0].id : ''
  }

  @Monitor('games')
  private onGamesChanged(monitor: IMonitor): void {
    this.allGamesDataSource.updateGames(this.games);
  }
}
