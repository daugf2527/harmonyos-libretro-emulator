import { EmuColors } from '../common/EmuUiTokens'

export interface EmuTelemetryCellItem {
  label: string
  value: string
  progress: number
  progressColor: string
}

@ComponentV2
export struct EmuTelemetryPanel {
  @Param cells: EmuTelemetryCellItem[] = []

  private clampProgress(value: number): number {
    if (!Number.isFinite(value) || value < 0) {
      return 0
    }
    if (value > 100) {
      return 100
    }
    return value
  }

  @Builder
  private TelemetryCell(item: EmuTelemetryCellItem) {
    Column({ space: 6 }) {
      Row() {
        Text(item.label)
          .fontSize(9)
          .fontColor(EmuColors.onSurfaceVariant)
          .fontFamily('monospace')
          .letterSpacing(1.2)
          .layoutWeight(1)

        Text(item.value)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(3)
          .backgroundColor('#22484848')
          .borderRadius(2)

        Row()
          .width(`${this.clampProgress(item.progress)}%`)
          .height(3)
          .backgroundColor(item.progressColor)
          .borderRadius(2)
      }
      .width('100%')
      .height(3)
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
      .margin({ left: 12, right: 12 })
  }

  build() {
    Row({ space: 0 }) {
      ForEach(this.cells, (item: EmuTelemetryCellItem, index: number) => {
        if (index > 0) {
          this.TelemetryDivider()
        }
        this.TelemetryCell(item)
      }, (item: EmuTelemetryCellItem, index: number) => `${index}:${item.label}:${item.value}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor('#050505')
    .borderRadius(8)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .alignItems(VerticalAlign.Center)
  }
}
