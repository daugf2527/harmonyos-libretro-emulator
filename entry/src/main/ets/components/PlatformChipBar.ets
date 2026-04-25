import { EmuColors } from '../common/EmuUiTokens'

@Component
export struct PlatformChipBar {
  @Prop items: string[] = []
  @Prop selected: string = ''
  onChange?: (value: string) => void

  private isSelected(item: string): boolean {
    return item === this.selected
  }

  build() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(this.items, (item: string) => {
          Button(item)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .fontColor(this.isSelected(item) ? '#FF000000' : '#FF9D9E9E')
            .width(102)
            .height(42)
            .backgroundColor(this.isSelected(item) ? EmuColors.primary : '#171717')
            .borderRadius(18)
            .border({
              width: this.isSelected(item) ? 0 : 0.5,
              color: '#44757575',
              style: BorderStyle.Solid
            })
            .onClick(() => {
              this.onChange?.(item)
            })
        }, (item: string) => item)
      }
      .padding({ top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }
}
