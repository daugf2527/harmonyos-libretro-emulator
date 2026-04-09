import { EmuColors } from '../common/EmuUiTokens'

@Component
export struct LibrarySection {
  @Prop title: string = ''
  @Prop codeLabel: string = ''

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      if (this.codeLabel.length > 0) {
        Text(this.codeLabel)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.1)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Bottom)
  }
}
