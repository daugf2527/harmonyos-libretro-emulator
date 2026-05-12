import { EmuColors } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'
import { EmuIcon } from './EmuIcon'

@Component
export struct LibraryDetailHeroPanel {
  @Prop coverKey: string = ''
  @Prop heroScale: number = 1
  @Prop displayTitle: string = ''
  @Prop localizedTitle: string = ''
  @Prop coreLabel: string = ''
  onLaunch?: () => void
  onQuickAction?: (message: string) => void

  build() {
    Column({ space: 28 }) {
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
          .backgroundColor('#080808')
          .borderRadius(4)
          .border({ width: 1, color: '#44484848', style: BorderStyle.Solid })
          .clip(true)

        EmuCoverArt({
          coverKey: this.coverKey,
          variant: 'recent'
        })
          .width('100%')
          .aspectRatio(3 / 4)
          .scale({ x: this.heroScale, y: this.heroScale })
          .borderRadius(4)
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
      .shadow({ radius: 22, color: '#33000000', offsetX: 0, offsetY: 10 })

      Column({ space: 4 }) {
        Text(this.displayTitle)
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.localizedTitle)
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
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(1.2)

        Text('LAUNCH GAME')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CC00FF41')
          .fontFamily('monospace')
          .letterSpacing(2.4)
      }
      .width('100%')
      .height(92)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#1F00FF41')
      .border({ width: 2, color: '#AA00FF41', style: BorderStyle.Solid })
      .shadow({ radius: 24, color: '#6600FF41', offsetX: 0, offsetY: 0 })
      .onClick(() => {
        this.onLaunch?.()
      })

      Row({ space: 12 }) {
        this.QuickActionButton('按键布局', 'videogame_asset', '游戏页控制面板即将收口到这里')
        this.QuickActionButton('画面风格', 'palette', `当前核心: ${this.coreLabel}`)
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
    .backgroundColor('#1F1F1F')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(2)
    .onClick(() => {
      this.onQuickAction?.(toastMessage)
    })
  }
}
