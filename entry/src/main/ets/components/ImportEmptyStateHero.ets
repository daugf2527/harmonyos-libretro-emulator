import { EmuColors, EmuRadius, EmuSpacing, EmuTypography } from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

@ComponentV2
export struct ImportEmptyStateHero {
  @Param isScanning: boolean = false
  @Param scanProgress: number = 0
  @Param buttonPressed: boolean = false
  @Param scanStatusText: string = '正在扫描本地文件...'
  @Param particleBoosted: boolean = false
  @Param titleText: string = '一键导入游戏，重温经典'
  @Param descriptionText: string = '请选择本地 ROM 或 ISO 文件开始导入。'
  @Param footnoteText: string = '仅支持你合法拥有的游戏'
  @Event onPrimaryAction?: () => void
  @Event onPrimaryTouch?: (pressed: boolean) => void

  build() {
    Column() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#101010')
          .borderRadius(EmuRadius.sm)
          .border({
            width: 1,
            color: '#FF2A2A2A',
            style: BorderStyle.Solid
          })

        Column()
          .width('75%')
          .aspectRatio(90 / 82)
          .border({
            width: 1,
            color: '#66484848',
            style: BorderStyle.Dashed
          })
          .align(Alignment.Center)

        EmuIcon({
          name: 'eject',
          tone: 'outline',
          iconSize: 38
        })
          .opacity(0.72)
          .align(Alignment.Center)

        Row()
          .width(5)
          .height(5)
          .borderRadius(2.5)
          .backgroundColor(EmuColors.primary)
          .align(Alignment.TopEnd)

        Row()
          .width(3)
          .height(3)
          .borderRadius(1.5)
          .backgroundColor('#66484848')
          .align(Alignment.BottomStart)
      }
      .width('48%')
      .constraintSize({ minWidth: 156, maxWidth: 196 })
      .aspectRatio(170 / 202)
      .margin({ bottom: 56 })
      .shadow({
        radius: this.particleBoosted ? 12 : 4,
        color: this.particleBoosted ? '#1800FF41' : '#0800FF41',
        offsetX: 0,
        offsetY: 0
      })

      Text(this.titleText)
        .fontSize(31)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 18 })

      Text(this.descriptionText)
        .fontSize(EmuTypography.lg)
        .lineHeight(28)
        .fontColor('#CCABABAB')
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 440 })
        .margin({ bottom: 48 })

      if (this.isScanning) {
        Column({ space: 8 }) {
          Row() {
            Text(this.scanStatusText)
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.primary)
              .fontFamily('monospace')
              .letterSpacing(1.2)

            Text(`${Math.floor(this.scanProgress)}%`)
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.primary)
              .fontFamily('monospace')
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          Stack() {
            Row()
              .width('100%')
              .height(2)
              .backgroundColor('#1A1A1A')

            Row()
              .width(`${this.scanProgress}%`)
              .height(2)
              .backgroundColor(EmuColors.primary)
              .shadow({ radius: 8, color: '#6600FF41', offsetX: 0, offsetY: 0 })
              .align(Alignment.Start)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: 280 })
        .margin({ bottom: 18 })
      }

      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(EmuColors.primary)

          Text('选择游戏文件导入')
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)

          EmuIcon({
            name: 'add_circle',
            iconSize: 18
          })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('74%')
      .constraintSize({ minWidth: 260, maxWidth: 430 })
      .height(48)
      .padding({ left: 28, right: 28 })
      .backgroundColor(this.buttonPressed ? EmuColors.surfaceContainerHighest : Color.Transparent)
      .border({ width: 1, color: '#AA757575', style: BorderStyle.Solid })
      .borderRadius(EmuRadius.sm)
      .enabled(!this.isScanning)
      .onTouch((event: TouchEvent) => {
        const eventType = Number(event.type)
        if (eventType === TouchType.Down) {
          this.onPrimaryTouch?.(true)
          return
        }
        if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
          this.onPrimaryTouch?.(false)
        }
      })
      .onClick(() => {
        this.onPrimaryAction?.()
      })

      Text(this.footnoteText)
        .fontSize(EmuTypography.xs)
        .fontColor('#555555')
        .letterSpacing(1.2)
        .margin({ top: 48 })
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}
