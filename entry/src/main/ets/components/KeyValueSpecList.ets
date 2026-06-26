import { EmuColors } from '../common/EmuUiTokens'

export interface KeyValueSpecItem {
  label: string
  value: string
}

@ComponentV2
export struct KeyValueSpecList {
  @Param title: string = ''
  @Param items: KeyValueSpecItem[] = []

  @Builder
  private SpecRow(item: KeyValueSpecItem) {
    Row() {
      Text(item.label)
        .fontSize(13)
        .fontColor('#CCABABAB')

      Text(item.value)
        .fontSize(13)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.SpaceBetween)
    .border({
      width: { bottom: 0.5 },
      color: '#1AABABAB',
      style: BorderStyle.Solid
    })
  }

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#CCABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.8)

      Column() {
        ForEach(this.items, (item: KeyValueSpecItem) => {
          this.SpecRow(item)
        }, (item: KeyValueSpecItem, index: number) => `${index}:${item.label}:${item.value}`)
      }
      .width('100%')
    }
    .width('100%')
  }
}
