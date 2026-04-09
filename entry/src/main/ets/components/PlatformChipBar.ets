import { EmuColors, EmuRadius } from '../common/EmuUiTokens'

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
      Row({ space: 8 }) {
        ForEach(this.items, (item: string) => {
          Button(item)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isSelected(item) ? '#000000' : EmuColors.onSurfaceVariant)
            .padding({ left: 24, right: 24, top: 6, bottom: 6 })
            .height(32)
            .backgroundColor(this.isSelected(item) ? EmuColors.primary : EmuColors.surfaceContainerHigh)
            .borderRadius(EmuRadius.pill)
            .border({
              width: this.isSelected(item) ? 0 : 0.5,
              color: EmuColors.outlineVariant,
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
