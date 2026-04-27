import { EmuColors } from '../common/EmuUiTokens'

export interface EmuTelemetryCellItem {
  label: string
  value: string
}

export interface EmuTelemetryBarItem {
  id: string
  height: number
  color: string
}

@Component
export struct EmuTelemetryPanel {
  @Prop cells: EmuTelemetryCellItem[] = []
  @Prop bars: EmuTelemetryBarItem[] = []

  @Builder
  private TelemetryCell(item: EmuTelemetryCellItem) {
    Column({ space: 6 }) {
      Text(item.label)
        .fontSize(9)
        .fontColor(EmuColors.onSurfaceVariant)
        .fontFamily('monospace')
        .letterSpacing(1.2)

      Row({ space: 8 }) {
        Row()
          .width(5)
          .height(5)
          .borderRadius(2.5)
          .backgroundColor(EmuColors.primary)

        Text(item.value)
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
      .height(34)
      .backgroundColor('#26484848')
      .margin({ left: 10, right: 10 })
  }

  build() {
    Row({ space: 0 }) {
      ForEach(this.cells, (item: EmuTelemetryCellItem, index: number) => {
        if (index > 0) {
          this.TelemetryDivider()
        }
        this.TelemetryCell(item)
      }, (item: EmuTelemetryCellItem) => item.label)

      Column({ space: 3 }) {
        Row({ space: 2 }) {
          ForEach(this.bars, (item: EmuTelemetryBarItem) => {
            Row()
              .width(10)
              .height(item.height)
              .backgroundColor(item.color)
          }, (item: EmuTelemetryBarItem) => item.id)
        }
        .alignItems(VerticalAlign.Bottom)
      }
      .padding({ left: 18 })
      .margin({ left: 14 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor('#050505')
    .borderRadius(8)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .alignItems(VerticalAlign.Center)
  }
}
