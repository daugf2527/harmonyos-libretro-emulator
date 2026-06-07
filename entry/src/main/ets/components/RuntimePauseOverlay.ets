import { EmuColors, EmuTypography } from '../common/EmuUiTokens'

interface RuntimePauseAction {
  title: string
  code: string
  iconText: string
  actionCode: string
}

@ComponentV2
export struct RuntimePauseOverlay {
  @Param processText: string = ''
  @Param saveStatusText: string = '存档就绪'
  @Param fpsText: string = '--.-'
  @Param cpuLoadText: string = '12.4%'
  @Event onResume?: () => void
  @Event onTerminate?: () => void
  @Event onAction?: (actionCode: string) => void

  private readonly actions: RuntimePauseAction[] = [
    { title: '快速存档', code: '当前进度落盘', iconText: '▣', actionCode: 'quick_save' },
    { title: '快速读档', code: '加载上次存档', iconText: '◫', actionCode: 'quick_load' },
    { title: '重启游戏', code: '从头开始本局', iconText: '↻', actionCode: 'restart_game' },
    { title: '按键映射', code: '自定义虚拟按键', iconText: '▥', actionCode: 'input_mapping' },
    { title: '画面风格', code: '切换滤镜与配色', iconText: '▧', actionCode: 'visual_filters' }
  ]
  private readonly waveformVerticalIndexes: number[] = [0, 1, 2, 3, 4, 5, 6, 7]
  private readonly waveformHorizontalIndexes: number[] = [0, 1, 2, 3, 4]

  @Builder
  private TopTelemetryBar() {
    Row() {
      Row({ space: 10 }) {
        Text('▣')
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.primary)

        Text('碳影 / Carbon Shade')
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.6)
      }
      .alignItems(VerticalAlign.Center)

      Text(`${this.fpsText} FPS | CPU ${this.cpuLoadText}`)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#B3ABABAB')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(44)
    .padding({ left: 24, right: 24 })
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
      Column({ space: 4 }) {
        Text('准备就绪')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.2)

        Row({ space: 8 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(EmuColors.primary)
            .shadow({ radius: 12, color: '#8800FF41', offsetX: 0, offsetY: 0 })

          Text('继续游戏')
            .fontSize(EmuTypography.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(EmuTypography.display)
        .fontColor('#88757575')
    }
    .width('100%')
    .height(72)
    .padding({ left: 20, right: 18 })
    .backgroundColor('#2200FF41')
    .border({ width: 1, color: EmuColors.primary, style: BorderStyle.Solid })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onResume?.()
    })
  }

  @Builder
  private PauseTile(item: RuntimePauseAction) {
    Column({ space: 6 }) {
      Text(item.iconText)
        .fontSize(EmuTypography.xxl)
        .fontColor('#B3E5E5E5')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 6 })

      Text(item.title)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.code)
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontColor('#99ABABAB')
        .letterSpacing(0.4)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(96)
    .padding({ left: 14, right: 12, top: 14, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F0161616')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(8)
    .onClick(() => {
      this.onAction?.(item.actionCode)
    })
  }

  @Builder
  private ActionGrid() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.PauseTile(this.actions[0])
        this.PauseTile(this.actions[1])
      }

      Row({ space: 12 }) {
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
        .fontSize(EmuTypography.xxl)
        .fontColor(EmuColors.error)

      Text('结束运行')
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.error)
        .layoutWeight(1)
        .margin({ left: 10 })

      Text('终止会话')
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#AAED7F64')
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 18 })
    .backgroundColor('#1AED7F64')
    .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTerminate?.()
    })
  }

  @Builder
  private PauseTelemetry() {
    Column({ space: 12 }) {
      Row() {
        Text('实时遥测')
          .fontSize(11)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCABABAB')
          .letterSpacing(1.6)

        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .height(36)
      .padding({ left: 18, right: 18 })
      .backgroundColor(EmuColors.surfaceContainerHigh)

      Row() {
        Column({ space: 4 }) {
          Text('CPU 负载')
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(this.cpuLoadText)
            .fontSize(EmuTypography.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('帧率')
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(`${this.fpsText} FPS`)
            .fontSize(EmuTypography.lg)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18 })
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        this.WaveformGrid()

        Path({
          width: 320,
          height: 64,
          commands: 'M0 40 Q20 16 40 40 T80 40 T120 40 T160 40 T200 40 T240 40 T320 40'
        })
          .fillOpacity(0)
          .stroke(EmuColors.primary)
          .strokeWidth(1.6)
          .strokeOpacity(0.72)
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
    }
    .width('100%')
    .padding({ top: 0, bottom: 18 })
    .backgroundColor('#CC050505')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
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
          Column({ space: 14 }) {
            Column({ space: 4 }) {
              Text('碳影 已暂停')
                .fontSize(EmuTypography.xl)
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.onSurface)

              Text(`进程：${this.processText}`)
                .fontSize(EmuTypography.xs)
                .fontFamily('monospace')
                .fontColor('#B3ABABAB')
                .letterSpacing(1.4)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 16 })
            .border({ width: { left: 3 }, color: EmuColors.primary, style: BorderStyle.Solid })
            .alignItems(HorizontalAlign.Start)

            this.ResumeAction()
            this.ActionGrid()

            Text(this.saveStatusText)
              .fontSize(EmuTypography.xs)
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
          .constraintSize({ maxWidth: 460 })
          .padding({ left: 24, right: 24, top: 76, bottom: 56 })
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
