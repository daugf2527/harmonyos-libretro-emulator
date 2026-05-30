import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
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
  @Prop @Watch('onHighlightChanged') isHighlighted: boolean = false
  onCardClick?: () => void
  @State private scannerOffset: number = -120
  @State private glowOpacity: number = 0.28
  private scannerTimer: number = -1
  private scannerFrame: number = 0
  private isOnScreen: boolean = true

  aboutToAppear(): void {
    this.syncScannerLoop()
  }

  aboutToDisappear(): void {
    this.stopScannerLoop()
  }

  private onHighlightChanged(): void {
    this.syncScannerLoop()
  }

  private onVisibilityChanged(visible: boolean): void {
    if (this.isOnScreen === visible) {
      return
    }
    this.isOnScreen = visible
    this.syncScannerLoop()
  }

  private startScannerLoop(): void {
    if (!this.isHighlighted || !this.isOnScreen || this.scannerTimer !== -1) {
      return
    }
    this.scannerTimer = setInterval(() => {
      this.scannerFrame = (this.scannerFrame + 1) % 90
      this.scannerOffset = -120 + this.scannerFrame * 4
      this.glowOpacity = 0.2 + (Math.sin(this.scannerFrame / 5) + 1) * 0.18
    }, 90)
  }

  private stopScannerLoop(): void {
    if (this.scannerTimer !== -1) {
      clearInterval(this.scannerTimer)
      this.scannerTimer = -1
    }
    this.scannerFrame = 0
    this.scannerOffset = -120
    this.glowOpacity = 0.28
  }

  private syncScannerLoop(): void {
    if (this.isHighlighted && this.isOnScreen) {
      this.startScannerLoop()
      return
    }
    this.stopScannerLoop()
  }

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
        .fontSize(EmuTypography.xs)
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
          .height('100%')
          .backgroundColor(this.coverColor)
          .borderRadius(14)
          .border({
            width: this.isHighlighted ? 1.5 : 0.5,
            color: this.isHighlighted ? '#6600FF41' : '#33484848',
            style: BorderStyle.Solid
          })
          .clip(true)
          .shadow(this.isHighlighted ? {
            radius: 22,
            color: '#5500FF41',
            offsetX: 0,
            offsetY: 0
          } : {
            radius: 0,
            color: '#00000000',
            offsetX: 0,
            offsetY: 0
          })

        EmuCoverArt({
          coverKey: this.coverKey,
          variant: 'recent'
        })
          .width('100%')
          .height('100%')
          .scale({ x: this.isHighlighted ? 1.02 : 1, y: this.isHighlighted ? 1.02 : 1 })
          .clip(true)
          .borderRadius(14)

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.isHighlighted ? '#12000000' : '#55000000')

        if (this.isHighlighted) {
          Column()
            .width('100%')
            .height(2)
            .linearGradient({
              angle: 0,
              colors: [
                ['#0000FF41', 0],
                ['#EE00FF41', 0.5],
                ['#0000FF41', 1]
              ]
            })
            .shadow({ radius: 12, color: '#8800FF41', offsetX: 0, offsetY: 0 })
            .translate({ y: this.scannerOffset })
            .opacity(this.glowOpacity)
        }

        this.CoverBadge()
      }
      .width('100%')
      .aspectRatio(3 / 4)

      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(13)
          .fontWeight(this.isHighlighted ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.isHighlighted ? 1 : 0.78)

        Text(this.subtitle)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(0.6)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.isHighlighted ? 1 : 0.72)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .opacity(1)
    .onClick(() => {
      this.onCardClick?.()
    })
    .onVisibleAreaChange([0.0, 0.1], (isVisible: boolean, currentRatio: number) => {
      this.onVisibilityChanged(isVisible || currentRatio > 0)
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
      .width('28%')
      .aspectRatio(4 / 3)

      Column({ space: 6 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.subtitle)
          .fontSize(EmuTypography.xs)
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
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onCardClick?.()
    })
  }
}
