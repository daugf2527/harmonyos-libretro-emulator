import { router } from '@kit.ArkUI'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuBottomNav } from '../components/EmuBottomNav'
import { PlatformChipBar } from '../components/PlatformChipBar'
import { GameCard } from '../components/GameCard'
import { EmuIcon } from '../components/EmuIcon'
import { LibrarySection } from '../components/LibrarySection'
import { EmuColors } from '../common/EmuUiTokens'

interface LibraryGameItem {
  id: string
  title: string
  subtitle: string
  platform: string
  coverColor: string
  coverKey: string
}

@Entry
@Component
struct LibraryPage {
  @State private selectedPlatform: string = 'FC'
  @State private searchKeyword: string = ''
  @State private selectedGameId: string = 'metroid-fusion'
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: 'LIBRARY', isActive: true },
    { key: 'engine', iconName: 'terminal', label: 'ENGINE', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: 'INPUT', isActive: false },
    { key: 'system', iconName: 'tune', label: 'SYSTEM', isActive: false }
  ]
  private readonly platforms: string[] = ['FC', 'GBA', 'SNES', 'MD']
  private readonly recentGames: LibraryGameItem[] = [
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
  private readonly allGames: LibraryGameItem[] = [
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

  private get filteredGames(): LibraryGameItem[] {
    const keyword = this.searchKeyword.trim().toLowerCase()
    return this.allGames.filter((item: LibraryGameItem) => {
      const matchedPlatform = this.selectedPlatform === 'FC' || item.platform === this.selectedPlatform
      if (!matchedPlatform) {
        return false
      }
      if (keyword.length === 0) {
        return true
      }
      return item.title.toLowerCase().indexOf(keyword) >= 0 ||
        item.subtitle.toLowerCase().indexOf(keyword) >= 0
    })
  }

  @Builder
  private SearchAndFilter() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        EmuIcon({
          name: 'search',
          tone: 'muted',
          size: 18,
          opacityValue: 0.9
        })

        Text('搜索游戏库')
          .fontSize(14)
          .fontColor('#80ABABAB')
      }
        .height(48)
        .backgroundColor(EmuColors.surfaceContainerLow)
        .borderRadius(8)
        .padding({ left: 16, right: 16 })
        .width('100%')
        .alignItems(VerticalAlign.Center)

      Row() {
        Row({ space: 16 }) {
          this.TelemetryCell('CPU Load', '12.4%')
          this.TelemetryCell('FPS', '60.0')
          this.TelemetryCell('Memory', '1.2GB')
        }

        Row({ space: 2 }) {
          Column().width(4).height(12).backgroundColor('#3300FF41')
          Column().width(4).height(18).backgroundColor('#6600FF41')
          Column().width(4).height(14).backgroundColor('#4D00FF41')
          Column().width(4).height(24).backgroundColor(EmuColors.primary)
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .borderRadius(8)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.SpaceBetween)

      PlatformChipBar({
        items: this.platforms,
        selected: this.selectedPlatform,
        onChange: (value: string) => {
          this.selectedPlatform = value
        }
      })
    }
  }

  @Builder
  private TelemetryCell(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(9)
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1)

      Row({ space: 6 }) {
        Row()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(EmuColors.primary)

        Text(value)
          .fontSize(11)
          .fontColor(EmuColors.onSurface)
          .fontFamily('monospace')
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RecentContent() {
    Scroll() {
      Row({ space: 16 }) {
        ForEach(this.recentGames, (item: LibraryGameItem) => {
          GameCard({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            isActive: item.id === this.selectedGameId,
            variant: 'recent',
            onCardClick: () => {
              this.selectedGameId = item.id
            }
          })
        }, (item: LibraryGameItem) => item.id)
      }
      .padding({ left: 4, right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private AllGamesContent() {
    Column({ space: 8 }) {
      ForEach(this.filteredGames, (item: LibraryGameItem) => {
        GameCard({
          title: item.title,
          subtitle: item.subtitle,
          platform: item.platform,
          coverColor: item.coverColor,
          coverKey: item.coverKey,
          variant: 'list',
          onCardClick: () => {
            router.pushUrl({ url: 'pages/LibretroGamePage' })
          }
        })
      }, (item: LibraryGameItem) => item.id)
    }
    .width('100%')
  }

  @Builder
  private MainContent() {
    Scroll() {
      Column({ space: 28 }) {
        this.SearchAndFilter()

        Column({ space: 16 }) {
          LibrarySection({
            title: '最近运行',
            codeLabel: 'History_Log'
          })
          this.RecentContent()
        }

        Column({ space: 16 }) {
          LibrarySection({
            title: '全部游戏',
            codeLabel: 'Sort: Name'
          })
          this.AllGamesContent()
        }
      }
      .width('100%')
      .padding({ top: 24, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: 'EMU_OS // 0.1',
        titleIcon: 'terminal',
        rightIcon: 'settings_input_component'
      })

      Stack() {
        EmuPrecisionGridBackdrop()

        Column() {
          this.MainContent()
        }
        .width('100%')
        .constraintSize({ maxWidth: 460 })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24 })

      EmuBottomNav({
        items: this.navItems
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
