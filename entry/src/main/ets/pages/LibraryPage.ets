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

@Entry
@Component
struct LibraryPage {
  @State private selectedPlatform: string = 'FC'
  @State private searchKeyword: string = ''
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
    if (keyword.length === 0) {
      return this.allGames
    }
    return this.allGames.filter((item: LibraryGameItem) => {
      return item.title.toLowerCase().indexOf(keyword) >= 0 ||
        item.subtitle.toLowerCase().indexOf(keyword) >= 0 ||
        item.platform.toLowerCase().indexOf(keyword) >= 0
    })
  }

  @Builder
  private SearchAndTelemetry() {
    Column({ space: 20 }) {
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
              this.searchKeyword = value
            })
        }
        .layoutWeight(1)
        .height(28)
      }
      .width('100%')
      .height(64)
      .padding({ left: 18, right: 18 })
      .backgroundColor('#0A0A0A')
      .borderRadius(8)
      .border({ width: 0.5, color: '#44757575', style: BorderStyle.Solid })
      .alignItems(VerticalAlign.Center)

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
      ForEach(this.recentGames, (item: LibraryGameItem) => {
        Column() {
          GameCard({
            title: item.title,
            subtitle: item.subtitle,
            platform: item.platform,
            coverColor: item.coverColor,
            coverKey: item.coverKey,
            variant: 'recent',
            onCardClick: () => {
              router.pushUrl({ url: 'pages/LibretroGamePage' })
            }
          })
        }
        .layoutWeight(1)
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

        Column({ space: 3 }) {
          Row().width(16).height(2).backgroundColor(EmuColors.onSurfaceVariant)
          Row().width(12).height(2).backgroundColor(EmuColors.onSurfaceVariant)
          Row().width(8).height(2).backgroundColor(EmuColors.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.End)
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
  private BottomLoader() {
    Column({ space: 10 }) {
      Stack() {
        Row()
          .width(30)
          .height(30)
          .borderRadius(15)
          .border({ width: 1.5, color: '#2F484848', style: BorderStyle.Solid })

        Row()
          .width(30)
          .height(30)
          .borderRadius(15)
          .border({
            width: { top: 2, right: 2 },
            color: EmuColors.primary,
            style: BorderStyle.Solid
          })
          .rotate({ angle: 16 })
      }

      Text('LOADING_ASSETS')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1.6)
    }
    .width('100%')
    .padding({ top: 26, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private MainContent() {
    Scroll() {
      Column({ space: 34 }) {
        this.SearchAndTelemetry()

        Column({ space: 18 }) {
          LibrarySection({
            title: '最近运行',
            codeLabel: 'HISTORY_LOG'
          })
          this.RecentContent()
        }

        Column({ space: 18 }) {
          this.AllGamesHeader()
          this.AllGamesContent()
          this.BottomLoader()
        }
      }
      .width('100%')
      .padding({ top: 20, bottom: 40 })
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
  }

  build() {
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
        panelBackgroundColor: '#FF000000'
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
