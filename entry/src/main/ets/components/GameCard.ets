import { EmuColors } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'

export type GameCardVariant = 'recent' | 'list'

@Component
export struct GameCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop platform: string = ''
  @Prop coverColor: string = '#2C2C2C'
  @Prop coverKey: string = ''
  @Prop variant: GameCardVariant = 'recent'
  onCardClick?: () => void

  build() {
    if (this.variant === 'recent') {
      this.RecentCard()
    } else {
      this.ListCard()
    }
  }

  @Builder
  private CoverBadge() {
    Row() {
      Text(this.platform)
        .fontSize(10)
        .fontColor(EmuColors.primary)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#D9000000')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(4)
    .align(Alignment.TopEnd)
    .margin({ top: 12, right: 12 })
  }

  @Builder
  private RecentCard() {
    Column({ space: 12 }) {
      Stack() {
        Column()
          .width('100%')
          .aspectRatio(3 / 4)
          .backgroundColor(this.coverColor)
          .borderRadius(14)
          .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
          .clip(true)

        EmuCoverArt({
          coverKey: this.coverKey,
          variant: 'recent'
        })
          .width('100%')
          .aspectRatio(3 / 4)
          .clip(true)
          .borderRadius(14)

        this.CoverBadge()
      }
      .width('100%')

      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.subtitle)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(0.6)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .onClick(() => {
      this.onCardClick?.()
    })
  }

  @Builder
  private ListCard() {
    Row({ space: 18 }) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.coverColor)
          .borderRadius(10)
          .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
          .clip(true)

        EmuCoverArt({
          coverKey: this.coverKey,
          variant: 'list'
        })
          .width('100%')
          .height('100%')
          .clip(true)
          .borderRadius(10)
      }
      .width(110)
      .height(82)

      Column({ space: 6 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.subtitle)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(0.3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      Text(this.platform)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
    }
    .width('100%')
    .height(82)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onCardClick?.()
    })
  }
}
