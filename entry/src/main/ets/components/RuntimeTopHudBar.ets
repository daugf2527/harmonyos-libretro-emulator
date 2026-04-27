import { EmuColors } from '../common/EmuUiTokens'

export interface RuntimeHudMetric {
  label: string
  value: string
}

@Component
export struct RuntimeTopHudBar {
  @Prop titleText: string = 'TELEMETRY_V1.0.4'
  @Prop metrics: RuntimeHudMetric[] = []

  @Builder
  private MetricCell(item: RuntimeHudMetric) {
    Column({ space: 2 }) {
      Text(item.label)
        .fontSize(9)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#88757575')

      Text(item.value)
        .fontSize(14)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
    }
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Row() {
      Row({ space: 8 }) {
        Text('◉')
          .fontSize(12)
          .fontColor(EmuColors.primary)

        Text(this.titleText)
          .fontSize(14)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(1.8)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 16 }) {
        ForEach(this.metrics, (item: RuntimeHudMetric) => {
          this.MetricCell(item)
        }, (item: RuntimeHudMetric) => item.label)
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(70)
    .padding({ left: 30, right: 30 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor('#E6000000')
    .border({ width: { bottom: 0.5 }, color: '#33484848', style: BorderStyle.Solid })
    .hitTestBehavior(HitTestMode.None)
    .align(Alignment.Top)
  }
}
