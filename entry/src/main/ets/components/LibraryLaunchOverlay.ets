import { createIndexRange, EmuColors } from '../common/EmuUiTokens'
import { EmuCoverArt } from './EmuCoverArt'
import { EmuIcon } from './EmuIcon'

export interface LibraryLaunchOverlayState {
  coverKey: string
  progress: number
  statusText: string
  cpuText: string
  runtimeStatusText: string
  fileLabel: string
}

@Component
export struct LibraryLaunchOverlay {
  @Prop state: LibraryLaunchOverlayState = {
    coverKey: '',
    progress: 0,
    statusText: 'READY_TO_HANDOFF',
    cpuText: 'FPS: --',
    runtimeStatusText: 'NO DATA',
    fileLabel: ''
  }

  build() {
    Stack() {
      Column({ space: 2 }) {
        ForEach(createIndexRange(90), (_: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor('#1400FF41')
        }, (index: number) => index.toString())
      }
      .width('100%')
      .height('100%')
      .opacity(0.12)

      Column() {
        this.Header()
        this.Body()

        Text('Kinetic Obsidian // Virtual_Core_v0.1')
          .fontSize(10)
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

        Text('EMU_OS // KERNEL.LOAD')
          .fontSize(11)
          .fontColor(EmuColors.primary)
          .fontFamily('monospace')
          .letterSpacing(1.8)
      }

      Row({ space: 10 }) {
        this.StatusPill(this.state.cpuText)
        this.StatusPill(this.state.runtimeStatusText)
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
          Text('System Status')
            .fontSize(9)
            .fontColor('#ABABAB')
            .fontFamily('monospace')
            .letterSpacing(2.2)

          Row()
            .width(1)
            .height(12)
            .backgroundColor('#3300FF41')

          Text(this.state.statusText)
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
        coverKey: this.state.coverKey,
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
          .rotate({ angle: this.state.progress * 3.6 })

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
          .width(`${this.state.progress}%`)
          .height(2)
          .backgroundColor(EmuColors.primary)
          .shadow({ radius: 10, color: '#5500FF41', offsetX: 0, offsetY: 0 })
          .align(Alignment.Start)
      }
      .width('100%')

      Row() {
        Text(this.state.fileLabel)
          .fontSize(9)
          .fontColor('#666666')
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(`${this.state.progress}%`)
          .fontSize(10)
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
