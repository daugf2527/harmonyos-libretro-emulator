import { EmuColors } from '../common/EmuUiTokens'

@Component
export struct PlatformChipBar {
  @Prop items: string[] = []
  @Prop selected: string = ''
  onChange?: (value: string) => void

  private isSelected(item: string): boolean {
    return item === this.selected
  }

  private getDisplayLabel(item: string): string {
    if (item === 'ALL') {
      return 'ALL'
    }
    return item
  }

  build() {
    Row({ space: 10 }) {
      ForEach(this.items, (item: string) => {
        Button(this.getDisplayLabel(item))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(this.isSelected(item) ? '#FF000000' : '#FF9D9E9E')
          .layoutWeight(1)
          .padding({ top: 7, bottom: 7 })
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
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }
}
