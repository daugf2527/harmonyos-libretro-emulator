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
    Column({ space: 1 }) {
      Text(item.label)
        .fontSize(7)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#88757575')
        .maxLines(1)

      Text(item.value)
        .fontSize(11)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Row() {
      Row({ space: 10 }) {
        Text('⚙')
          .fontSize(15)
          .fontColor(EmuColors.primary)

        Text(this.titleText)
          .fontSize(13)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(2.6)
          .maxLines(1)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 18 }) {
        ForEach(this.metrics, (item: RuntimeHudMetric) => {
          this.MetricCell(item)
        }, (item: RuntimeHudMetric) => item.label)

        Row()
          .width(1)
          .height(20)
          .backgroundColor('#33484848')

        Text('◥')
          .fontSize(16)
          .fontColor(EmuColors.primary)
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(40)
    .padding({ left: 28, right: 28 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor('#F0000000')
    .backdropBlur(18)
    .border({ width: { bottom: 0.5 }, color: '#33484848', style: BorderStyle.Solid })
    .hitTestBehavior(HitTestMode.None)
    .align(Alignment.Top)
  }
}
