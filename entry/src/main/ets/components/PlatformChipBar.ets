import { EmuColors } from '../common/EmuUiTokens'

@Component
export struct PlatformChipBar {
  @Prop items: string[] = []
  @Prop @Watch('onSelectedChange') selected: string = ''
  onChange?: (value: string) => void
  private scroller: Scroller = new Scroller()
  private readonly estimatedChipWidth: number = 64

  private isSelected(item: string): boolean {
    return item === this.selected
  }

  private getDisplayLabel(item: string): string {
    if (item === 'ALL') {
      return 'ALL'
    }
    return item
  }

  private onSelectedChange(): void {
    const idx = this.items.findIndex((item: string) => item === this.selected)
    if (idx <= 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 })
      return
    }
    const target = Math.max(0, idx * this.estimatedChipWidth - this.estimatedChipWidth)
    this.scroller.scrollTo({ xOffset: target, yOffset: 0 })
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      Scroll(this.scroller) {
        Row({ space: 8 }) {
          ForEach(this.items, (item: string) => {
            Button(this.getDisplayLabel(item))
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(this.isSelected(item) ? '#FF000000' : '#FF9D9E9E')
              .padding({ top: 6, bottom: 6, left: 14, right: 14 })
              .backgroundColor(this.isSelected(item) ? EmuColors.primary : '#171717')
              .borderRadius(16)
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
        .padding({ top: 2, bottom: 2, left: 4, right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)

      Column()
        .width(20)
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [[0x00000000, 0.0], [EmuColors.background, 1.0]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
  }
}
