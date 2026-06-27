import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'
import { EmuIcon } from './EmuIcon'

@ComponentV2
export struct LibraryDetailHeroPanel {
  @Param coverKey: string = ''
  @Param heroScale: number = 1
  @Param displayTitle: string = ''
  @Param localizedTitle: string = ''
  @Param coreLabel: string = ''
  @Event onLaunch?: () => void

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
          .fontSize(EmuTypography.md)
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

        Text('启动游戏')
          .fontSize(EmuTypography.xs)
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
        this.InfoCard('按键布局', 'videogame_asset', '请在运行页或设置页调整')
        this.InfoCard(
          '画面风格',
          'palette',
          this.coreLabel.length > 0 ? `当前匹配核心：${this.coreLabel}` : '当前还没匹配核心'
        )
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private InfoCard(label: string, iconName: string, detail: string) {
    Column({ space: 8 }) {
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
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(detail)
        .fontSize(EmuTypography.xs)
        .fontColor('#CCABABAB')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(72)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#1F1F1F')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(2)
  }
}
