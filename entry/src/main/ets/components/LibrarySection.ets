import { EmuColors, EmuTypography } from '../common/EmuUiTokens'

@Component
export struct LibrarySection {
  @Prop title: string = ''
  @Prop codeLabel: string = ''

  build() {
    Row() {
      Text(this.title)
        .fontSize(EmuTypography.xl)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      if (this.codeLabel.length > 0) {
        Text(this.codeLabel)
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.4)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Bottom)
  }
}
