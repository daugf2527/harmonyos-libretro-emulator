import { EmuColors } from '../common/EmuUiTokens'
import { LibraryRecord } from '../common/LibraryRepository'
import { EmuIcon } from './EmuIcon'
import { GameCard } from './GameCard'
import { LibrarySection } from './LibrarySection'

export interface LibraryGameSectionsState {
  recentGames: LibraryRecord[]
  games: LibraryRecord[]
  highlightedRecentGameId: string
  bottomLoaderActive: boolean
  spinnerAngle: number
}

@Component
export struct LibraryGameSections {
  @Prop recentGames: LibraryRecord[] = []
  @Prop games: LibraryRecord[] = []
  @Prop highlightedRecentGameId: string = ''
  @Prop bottomLoaderActive: boolean = false
  @Prop spinnerAngle: number = 0
  onCardTouch?: (event: TouchEvent, item: LibraryRecord) => void
  onHideSearchResults?: () => void

  build() {
    Column({ space: 28 }) {
      Column({ space: 18 }) {
        LibrarySection({
          title: '最近运行',
          codeLabel: 'HISTORY_LOG'
        })
        this.RecentContent()
      }
      .onClick(() => {
        this.onHideSearchResults?.()
      })

      Column({ space: 18 }) {
        this.AllGamesHeader()
        this.AllGamesContent()
        this.BottomLoader()
      }
      .onClick(() => {
        this.onHideSearchResults?.()
      })
    }
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
            variant: 'recent',
            isHighlighted: item.id === this.getHighlightedRecentGameId()
          })
        }
        .layoutWeight(1)
        .onTouch((event: TouchEvent) => {
          this.onCardTouch?.(event, item)
        })
      }, (item: LibraryRecord) => item.id)
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
        Text('排序：名称')
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
      ForEach(this.games, (item: LibraryRecord) => {
        GameCard({
          title: item.title,
          subtitle: item.subtitle,
          platform: item.platform,
          coverColor: item.coverColor,
          coverKey: item.coverKey,
          variant: 'list'
        })
        .onTouch((event: TouchEvent) => {
          this.onCardTouch?.(event, item)
        })
      }, (item: LibraryRecord) => item.id)
    }
    .width('100%')
  }

  @Builder
  private BottomLoader() {
    Column({ space: 10 }) {
      this.Spinner(30, 2, EmuColors.primary, '#2F484848')

      Text(this.bottomLoaderActive ? '继续加载游戏...' : '正在读取游戏库')
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
}
