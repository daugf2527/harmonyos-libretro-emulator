import { EmuColors, EmuRadius, EmuSpacing } from '../common/EmuUiTokens'

@Component
export struct ImportEmptyStateHero {
  @Prop isScanning: boolean = false
  @Prop scanProgress: number = 0
  @Prop buttonPressed: boolean = false
  @Prop scanStatusText: string = '正在扫描本地文件...'
  @Prop particleBoosted: boolean = false
  onPrimaryAction?: () => void
  onPrimaryTouch?: (pressed: boolean) => void

  build() {
    Column() {
      Stack() {
        Column()
          .width(112)
          .height(132)
          .backgroundColor(EmuColors.background)
          .borderRadius(EmuRadius.sm)
          .border({
            width: 1,
            color: '#FF2A2A2A',
            style: BorderStyle.Solid
          })

        Column()
          .width(78)
          .height(72)
          .border({
            width: 1,
            color: '#66484848',
            style: BorderStyle.Dashed
          })
          .align(Alignment.Center)
          .margin({ bottom: 16 })

        Text('\uE164')
          .fontFamily('MaterialSymbolsOutlined')
          .fontSize(34)
          .fontColor('#665E5E5E')
          .align(Alignment.Center)

        Row()
          .width(5)
          .height(5)
          .borderRadius(2.5)
          .backgroundColor(EmuColors.primary)
          .position({ x: 109, y: -3 })

        Row()
          .width(3)
          .height(3)
          .borderRadius(1.5)
          .backgroundColor('#66484848')
          .position({ x: -1, y: 130 })
      }
      .width(112)
      .height(132)
      .margin({ bottom: 54 })
      .shadow({
        radius: this.particleBoosted ? 12 : 4,
        color: this.particleBoosted ? '#1800FF41' : '#0800FF41',
        offsetX: 0,
        offsetY: 0
      })

      Text('一键导入游戏，重温经典')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 10 })

      Text('系统未检测到可用镜像。请选择本地 ROM 或 ISO 文件开始模拟。')
        .fontSize(12)
        .lineHeight(19)
        .fontColor(EmuColors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 304 })
        .margin({ bottom: 34 })

      if (this.isScanning) {
        Column({ space: 8 }) {
          Row() {
            Text(this.scanStatusText)
              .fontSize(10)
              .fontColor(EmuColors.primary)
              .fontFamily('monospace')
              .letterSpacing(1.2)

            Text(`${Math.floor(this.scanProgress)}%`)
              .fontSize(10)
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
            .fontSize(14)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)

          Text('\uE145')
            .fontFamily('MaterialSymbolsOutlined')
            .fontSize(18)
            .fontColor(EmuColors.primary)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
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

      Text('仅支持你合法拥有的游戏')
        .fontSize(9)
        .fontColor('#454545')
        .letterSpacing(1.2)
        .margin({ top: 44 })
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
  }
}
