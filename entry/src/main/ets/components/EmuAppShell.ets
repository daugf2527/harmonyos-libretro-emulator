import {
  EmuColors,
  EmuMetrics,
  createIndexRange
} from '../common/EmuUiTokens'

@Component
export struct EmuHeaderBar {
  @Prop titleText: string = 'EMU_CORE_v1.0'
  @Prop titleIcon: string = '\uE322'
  @Prop rightLabel: string = ''
  @Prop rightIcon: string = '\uE8B8'
  @Prop activeTextColor: string = ''
  @Prop mutedTextColor: string = '#888888'
  @Prop iconSize: number = 18
  @Prop rightIconSize: number = 20

  build() {
    Row() {
      Row({ space: 6 }) {
        Text(this.titleIcon)
          .fontFamily('MaterialSymbolsOutlined')
          .fontColor(this.activeTextColor.length > 0 ? this.activeTextColor : EmuColors.primary)
          .fontSize(this.iconSize)

        Text(this.titleText)
          .fontFamily('monospace')
          .fontSize(13)
          .fontColor(this.activeTextColor.length > 0 ? this.activeTextColor : EmuColors.primary)
          .letterSpacing(2.2)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        if (this.rightLabel.length > 0) {
          Text(this.rightLabel)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(this.mutedTextColor)
            .letterSpacing(0.8)
        }

        Text(this.rightIcon)
          .fontFamily('MaterialSymbolsOutlined')
          .fontColor(this.activeTextColor.length > 0 ? this.activeTextColor : EmuColors.primary)
          .fontSize(this.rightIconSize)
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(EmuMetrics.headerHeight)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backdropBlur(24)
    .backgroundColor('#D9000000')
    .border({
      width: { bottom: 1 },
      color: EmuMetrics.panelBorderColor,
      style: BorderStyle.Solid
    })
  }
}

@Component
export struct EmuPrecisionGridBackdrop {
  private readonly horizontalGridIndexes: number[] = createIndexRange(120)
  private readonly verticalGridIndexes: number[] = createIndexRange(120)

  build() {
    Stack() {
      Column({ space: Math.max(0, EmuMetrics.gridSize - 1) }) {
        ForEach(this.horizontalGridIndexes, (item: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor(EmuMetrics.gridLineColor)
        }, (item: number) => `h-${item}`)
      }
      .width('100%')
      .height('100%')

      Row({ space: Math.max(0, EmuMetrics.gridSize - 1) }) {
        ForEach(this.verticalGridIndexes, (item: number) => {
          Column()
            .width(1)
            .height('100%')
            .backgroundColor(EmuMetrics.gridLineColor)
        }, (item: number) => `v-${item}`)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .opacity(0.8)
  }
}
