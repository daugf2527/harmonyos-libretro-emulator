import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'
import { EmuIcon } from './EmuIcon'
import { ScanlineBackground } from './EmuAppShell'

@ComponentV2
export struct LibraryLaunchOverlay {
  @Param coverKey: string = ''
  @Param statusText: string = '准备启动游戏'
  @Param cpuText: string = '帧率: --'
  @Param runtimeStatusText: string = '暂无记录'
  @Param fileLabel: string = ''
  @Local private spinnerAngle: number = 0
  @Local private barOffset: number = -96
  private animationTimer: number = -1

  aboutToAppear(): void {
    if (this.animationTimer !== -1) {
      return
    }
    this.spinnerAngle = 0
    this.barOffset = -96
    this.animationTimer = setInterval(() => {
      this.spinnerAngle = (this.spinnerAngle + 18) % 360
      const nextOffset = this.barOffset + 12
      this.barOffset = nextOffset > 280 ? -96 : nextOffset
    }, 60)
  }

  aboutToDisappear(): void {
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer)
      this.animationTimer = -1
    }
  }

  build() {
    Stack() {
      ScanlineBackground({ lineColor: '#1400FF41', lineSpacing: 2 })
        .width('100%')
        .height('100%')
        .opacity(0.12)

      Column() {
        this.Header()
        this.Body()

        Text('本地游戏运行')
          .fontSize(EmuTypography.xs)
          .fontColor('#666666')
          .fontFamily('monospace')
          .letterSpacing(3.6)
          .margin({ bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F2000000')
      .backdropBlur(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Header() {
    Row() {
      Row({ space: 8 }) {
        EmuIcon({
          name: 'terminal',
          tone: 'primary',
          iconSize: 14,
          opacityValue: 1
        })

        Text('正在打开游戏')
          .fontSize(11)
          .fontColor(EmuColors.primary)
          .fontFamily('monospace')
          .letterSpacing(1.8)
      }

      Row({ space: 10 }) {
        this.StatusPill(this.cpuText)
        this.StatusPill(this.runtimeStatusText)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .justifyContent(FlexAlign.SpaceBetween)
    .border({
      width: { bottom: 0.5 },
      color: '#26262626',
      style: BorderStyle.Solid
    })
  }

  @Builder
  private StatusPill(text: string) {
    Row({ space: 6 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(EmuColors.primary)

      Text(text)
        .fontSize(9)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
    }
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#161616')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private Body() {
    Column({ space: 24 }) {
      this.CoverLoadingCard()

      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Text('当前状态')
            .fontSize(9)
            .fontColor('#ABABAB')
            .fontFamily('monospace')
            .letterSpacing(2.2)

          Row()
            .width(1)
            .height(12)
            .backgroundColor('#3300FF41')

          Text(this.statusText)
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
            .fontFamily('monospace')
            .letterSpacing(1.4)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#171717')
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

        Text('正在加载你的童年')
          .fontSize(26)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)

        this.ProgressBar()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 28, right: 28, top: 24, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private CoverLoadingCard() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(EmuColors.surfaceContainerLow)
        .borderRadius(8)
        .border({ width: 1, color: '#33FFFFFF', style: BorderStyle.Solid })
        .clip(true)

      EmuCoverArt({
        coverKey: this.coverKey,
        variant: 'recent'
      })
        .width('100%')
        .height('100%')
        .scale({ x: 1.08, y: 1.08 })
        .borderRadius(8)
        .clip(true)

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#8C000000')

      this.LoadingScreenCorner(Alignment.TopStart, 28)
      this.LoadingScreenCorner(Alignment.BottomEnd, 28)

      Stack() {
        Row()
          .width(80)
          .height(80)
          .borderRadius(40)
          .border({ width: 2, color: '#2200FF41', style: BorderStyle.Solid })

        Row()
          .width(80)
          .height(80)
          .borderRadius(40)
          .border({
            width: { top: 2, right: 2 },
            color: EmuColors.primary,
            style: BorderStyle.Solid
          })
          .rotate({ angle: this.spinnerAngle })

        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(EmuColors.primary)
          .shadow({ radius: 8, color: '#8800FF41', offsetX: 0, offsetY: 0 })
      }
      .align(Alignment.Center)
    }
    .width('68%')
    .constraintSize({ maxWidth: 256 })
    .aspectRatio(3 / 4)
    .alignContent(Alignment.Center)
  }

  @Builder
  private ProgressBar() {
    Column({ space: 8 }) {
      Stack() {
        Row()
          .width('100%')
          .height(2)
          .backgroundColor('#222222')

        Row()
          .width(96)
          .height(2)
          .backgroundColor(EmuColors.primary)
          .shadow({ radius: 10, color: '#5500FF41', offsetX: 0, offsetY: 0 })
          .align(Alignment.Start)
          .translate({ x: this.barOffset })
      }
      .width('100%')

      Row() {
        Text(this.fileLabel)
          .fontSize(9)
          .fontColor('#666666')
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text('正在打开')
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .fontFamily('monospace')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private LoadingScreenCorner(alignment: Alignment, size: number) {
    Stack() {
      Row()
        .width(size)
        .height(2)
        .backgroundColor(EmuColors.primary)
      Row()
        .width(2)
        .height(size)
        .backgroundColor(EmuColors.primary)
    }
    .align(alignment)
  }
}
