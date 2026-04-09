import { EmuColors, EmuRadius } from '../common/EmuUiTokens'

export type GameCardVariant = 'recent' | 'list'

@Component
export struct GameCard {
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop platform: string = ''
  @Prop coverColor: string = '#2C2C2C'
  @Prop isActive: boolean = false
  @Prop variant: GameCardVariant = 'recent'
  onClick?: () => void

  build() {
    if (this.variant === 'recent') {
      this.RecentCard()
      return
    }
    this.ListCard()
  }

  @Builder
  private RecentCard() {
    Column({ space: 8 }) {
      Stack() {
        Column()
          .width(176)
          .height(234)
          .backgroundColor(this.coverColor)
          .borderRadius(EmuRadius.lg)
          .border({
            width: this.isActive ? 2 : 0.5,
            color: this.isActive ? EmuColors.primary : EmuColors.outlineVariant,
            style: BorderStyle.Solid
          })

        if (this.isActive) {
          Row()
            .width('100%')
            .height(2)
            .linearGradient({
              angle: 90,
              colors: [[0x00000000, 0], [0x00FF41FF, 0.5], [0x00000000, 1]]
            })
            .shadow({ radius: 12, color: '#6600FF41', offsetX: 0, offsetY: 0 })
            .align(Alignment.Top)
            .margin({ top: 88 })
        }

        Row() {
          Text(this.platform)
            .fontSize(9)
            .fontColor(EmuColors.primary)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
        }
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .backgroundColor('#CC000000')
        .borderRadius(EmuRadius.sm)
        .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
        .align(Alignment.TopEnd)
        .margin({ top: 8, right: 8 })
      }

      Text(this.title)
        .fontSize(11)
        .fontWeight(this.isActive ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.isActive ? EmuColors.primary : EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.subtitle)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(EmuColors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(176)
    .opacity(this.isActive ? 1 : 0.45)
    .onClick(() => {
      this.onClick?.()
    })
  }

  @Builder
  private ListCard() {
    Row({ space: 16 }) {
      Column()
        .width('28%')
        .aspectRatio(4 / 3)
        .backgroundColor(this.coverColor)
        .borderRadius(EmuRadius.md)
        .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })

      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.subtitle)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.platform)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 8, right: 8 })
    .opacity(0.45)
    .onClick(() => {
      this.onClick?.()
    })
  }
}
