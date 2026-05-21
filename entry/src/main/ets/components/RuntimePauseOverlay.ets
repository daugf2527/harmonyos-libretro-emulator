import { EmuColors } from '../common/EmuUiTokens'

interface RuntimePauseAction {
  title: string
  code: string
  iconText: string
  actionCode: string
}

@Component
export struct RuntimePauseOverlay {
  @Prop processText: string = ''
  @Prop saveStatusText: string = 'SAVE_IDLE'
  @Prop fpsText: string = '--.-'
  @Prop cpuLoadText: string = '12.4%'
  onResume?: () => void
  onTerminate?: () => void
  onAction?: (actionCode: string) => void

  private readonly actions: RuntimePauseAction[] = [
    { title: '快速存档', code: 'QUICK_SAVE', iconText: '▣', actionCode: 'quick_save' },
    { title: '快速读档', code: 'QUICK_LOAD', iconText: '◫', actionCode: 'quick_load' },
    { title: '按键映射', code: 'INPUT_MAPPING', iconText: '▥', actionCode: 'input_mapping' },
    { title: '画面风格', code: 'VISUAL_FILTERS', iconText: '▧', actionCode: 'visual_filters' }
  ]
  private readonly waveformVerticalIndexes: number[] = [0, 1, 2, 3, 4, 5, 6, 7]
  private readonly waveformHorizontalIndexes: number[] = [0, 1, 2, 3, 4]

  @Builder
  private TopTelemetryBar() {
    Row() {
      Row({ space: 12 }) {
        Text('▣')
          .fontSize(17)
          .fontColor(EmuColors.primary)

        Text('TELEMETRY_v1.0.4')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(3)
      }
      .alignItems(VerticalAlign.Center)

      Text(`${this.fpsText} FPS | CPU ${this.cpuLoadText} | GPU --`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#B3ABABAB')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(56)
    .padding({ left: 38, right: 38 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#E6000000')
    .backdropBlur(22)
    .border({
      width: { bottom: 0.5 },
      color: '#22484848',
      style: BorderStyle.Solid
    })
    .align(Alignment.Top)
  }

  @Builder
  private ResumeAction() {
    Row() {
      Column({ space: 6 }) {
        Text('EXECUTION_READY')
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.4)

        Row({ space: 8 }) {
          Row()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(EmuColors.primary)
            .shadow({ radius: 16, color: '#8800FF41', offsetX: 0, offsetY: 0 })

          Text('继续游戏 RESUME_EXECUTION')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(40)
        .fontColor('#88757575')
    }
    .width('100%')
    .height(140)
    .padding({ left: 30, right: 28 })
    .backgroundColor('#2200FF41')
    .border({ width: 1.2, color: EmuColors.primary, style: BorderStyle.Solid })
    .borderRadius(6)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onResume?.()
    })
  }

  @Builder
  private PauseTile(item: RuntimePauseAction) {
    Column() {
      Text(item.iconText)
        .fontSize(34)
        .fontColor('#B3E5E5E5')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 32 })

      Text(item.title)
        .fontSize(21)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Text(item.code)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)
        .letterSpacing(0.8)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(186)
    .padding({ left: 28, right: 22, top: 28, bottom: 26 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F0161616')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(6)
    .onClick(() => {
      this.onAction?.(item.actionCode)
    })
  }

  @Builder
  private ActionGrid() {
    Column({ space: 20 }) {
      Row({ space: 20 }) {
        this.PauseTile(this.actions[0])
        this.PauseTile(this.actions[1])
      }

      Row({ space: 20 }) {
        this.PauseTile(this.actions[2])
        this.PauseTile(this.actions[3])
      }
    }
    .width('100%')
  }

  @Builder
  private TerminateAction() {
    Row() {
      Text('⏻')
        .fontSize(32)
        .fontColor(EmuColors.error)

      Text('结束运行 TERMINATE_SESSION')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.error)
        .layoutWeight(1)

      Text('ERR_HALT')
        .fontSize(11)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#AAED7F64')
    }
    .width('100%')
    .height(96)
    .padding({ left: 28, right: 24 })
    .backgroundColor('#1AED7F64')
    .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
    .borderRadius(6)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTerminate?.()
    })
  }

  @Builder
  private PauseTelemetry() {
    Column({ space: 18 }) {
      Row() {
        Text('SUBSYSTEM_TELEMETRY')
          .fontSize(13)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCABABAB')
          .letterSpacing(2)

        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .height(50)
      .padding({ left: 28, right: 28 })
      .backgroundColor(EmuColors.surfaceContainerHigh)

      Row() {
        Column({ space: 6 }) {
          Text('CPU LOAD')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(this.cpuLoadText)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          Text('FRAMERATE')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(`${this.fpsText} FPS`)
            .fontSize(26)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        this.WaveformGrid()

        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#3300FF41')
          .align(Alignment.Center)
        Row()
          .width('82%')
          .height(2)
          .backgroundColor(EmuColors.primary)
          .borderRadius(1)
          .align(Alignment.Bottom)
          .margin({ bottom: 24 })
        Row()
          .width('58%')
          .height(2)
          .backgroundColor('#9900FF41')
          .borderRadius(1)
          .align(Alignment.BottomEnd)
          .margin({ bottom: 10 })

        Path({
          width: 520,
          height: 110,
          commands: 'M0 70 Q36 28 72 70 T144 70 T216 70 T288 70 T360 70 T432 70 T520 70'
        })
          .fillOpacity(0)
          .stroke(EmuColors.primary)
          .strokeWidth(2)
          .strokeOpacity(0.72)

        Path({
          width: 520,
          height: 110,
          commands: 'M0 78 Q44 48 88 78 T176 78 T264 64 T352 78 T440 54 T520 76'
        })
          .fillOpacity(0)
          .stroke(EmuColors.primary)
          .strokeWidth(2.4)
      }
      .width('100%')
      .height(116)
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 28 })
    .backgroundColor('#CC050505')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(4)
  }

  @Builder
  private WaveformGrid() {
    Stack() {
      Row({ space: 19 }) {
        ForEach(this.waveformVerticalIndexes, (item: number) => {
          Column()
            .width(1)
            .height('100%')
            .backgroundColor('#1600FF41')
        }, (item: number) => `v-${item}`)
      }
      .width('100%')
      .height('100%')

      Column({ space: 19 }) {
        ForEach(this.waveformHorizontalIndexes, (item: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor('#1600FF41')
        }, (item: number) => `h-${item}`)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .backdropBlur(18)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [
            ['#00000000', 0],
            ['#00000000', 0.76],
            ['#1100FF41', 1]
          ]
        })

      this.TopTelemetryBar()

      Scroll() {
        Row() {
          Column({ space: 20 }) {
            Column({ space: 8 }) {
              Text('EMU_CORE 系统暂停')
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.onSurface)

              Text(`PROCESS: ${this.processText}`)
                .fontSize(13)
                .fontFamily('monospace')
                .fontColor('#B3ABABAB')
                .letterSpacing(2)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 24 })
            .border({ width: { left: 4 }, color: EmuColors.primary, style: BorderStyle.Solid })
            .alignItems(HorizontalAlign.Start)

            this.ResumeAction()
            this.ActionGrid()

            Text(this.saveStatusText)
              .fontSize(12)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor('#99ABABAB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            this.TerminateAction()
            this.PauseTelemetry()
          }
          .width('100%')
          .constraintSize({ maxWidth: 620 })
          .padding({ left: 40, right: 40, top: 132, bottom: 92 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}
