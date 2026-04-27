import { EmuColors } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'
import { EmuIcon } from './EmuIcon'

export interface LibraryDetailHeroPanelState {
  coverKey: string
  heroScale: number
  displayTitle: string
  localizedTitle: string
  coreLabel: string
}

@Component
export struct LibraryDetailHeroPanel {
  @Prop state: LibraryDetailHeroPanelState = {
    coverKey: '',
    heroScale: 1,
    displayTitle: '',
    localizedTitle: '',
    coreLabel: ''
  }
  onLaunch?: () => void
  onQuickAction?: (message: string) => void

  build() {
    Column({ space: 30 }) {
      this.HeroSection()
      this.PrimaryActions()
    }
    .width('100%')
  }

  @Builder
  private HeroSection() {
    Column({ space: 18 }) {
      Stack() {
        Column()
          .width('100%')
          .aspectRatio(3 / 4)
          .backgroundColor(EmuColors.surfaceContainerLow)
          .borderRadius(8)
          .border({ width: 1, color: '#33484848', style: BorderStyle.Solid })
          .clip(true)

        EmuCoverArt({
          coverKey: this.state.coverKey,
          variant: 'recent'
        })
          .width('100%')
          .aspectRatio(3 / 4)
          .scale({ x: this.state.heroScale, y: this.state.heroScale })
          .borderRadius(8)
          .clip(true)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              ['#11000000', 0],
              ['#05050505', 0.45],
              ['#99000000', 1]
            ]
          })
      }
      .width('100%')
      .shadow({ radius: 28, color: '#4400FF41', offsetX: 0, offsetY: 0 })

      Column({ space: 4 }) {
        Text(this.state.displayTitle)
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.state.localizedTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#CCABABAB')
          .letterSpacing(1.4)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  private PrimaryActions() {
    Column({ space: 12 }) {
      Column({ space: 2 }) {
        Text('启动游戏')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(0.8)

        Text('LAUNCH GAME')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CC00FF41')
          .fontFamily('monospace')
          .letterSpacing(2.4)
      }
      .width('100%')
      .height(98)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#1900FF41')
      .border({ width: 1.5, color: '#6600FF41', style: BorderStyle.Solid })
      .shadow({ radius: 18, color: '#5500FF41', offsetX: 0, offsetY: 0 })
      .onClick(() => {
        this.onLaunch?.()
      })

      Row({ space: 12 }) {
        this.QuickActionButton('按键布局', 'videogame_asset', '游戏页控制面板即将收口到这里')
        this.QuickActionButton('画面风格', 'palette', `当前核心: ${this.state.coreLabel}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private QuickActionButton(label: string, iconName: string, toastMessage: string) {
    Row({ space: 8 }) {
      EmuIcon({
        name: iconName,
        tone: 'on_surface',
        iconSize: 18,
        opacityValue: 0.86
      })

      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(EmuColors.surfaceContainerHigh)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(4)
    .onClick(() => {
      this.onQuickAction?.(toastMessage)
    })
  }
}
