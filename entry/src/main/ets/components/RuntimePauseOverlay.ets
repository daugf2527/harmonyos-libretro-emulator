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
    { title: '快速读档', code: 'QUICK_LOAD', iconText: '▤', actionCode: 'quick_load' },
    { title: '按键映射', code: 'INPUT_MAPPING', iconText: '≡', actionCode: 'input_mapping' },
    { title: '画面风格', code: 'VISUAL_FILTERS', iconText: '▥', actionCode: 'visual_filters' }
  ]

  @Builder
  private ResumeAction() {
    Row() {
      Column({ space: 6 }) {
        Text('EXECUTION_READY')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)

        Row({ space: 8 }) {
          Row()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(EmuColors.primary)
            .shadow({ radius: 16, color: '#8800FF41', offsetX: 0, offsetY: 0 })

          Text('继续游戏 RESUME_EXECUTION')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(34)
        .fontColor('#88757575')
    }
    .width('100%')
    .height(112)
    .padding({ left: 26, right: 26 })
    .backgroundColor('#2400FF41')
    .border({ width: 1, color: EmuColors.primary, style: BorderStyle.Solid })
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
        .fontSize(28)
        .fontColor('#B3E5E5E5')
        .margin({ bottom: 34 })

      Text(item.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Text(item.code)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)
        .letterSpacing(0.6)
    }
    .layoutWeight(1)
    .height(140)
    .padding(22)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F0141414')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(6)
    .onClick(() => {
      this.onAction?.(item.actionCode)
    })
  }

  @Builder
  private ActionGrid() {
    Column({ space: 14 }) {
      Row({ space: 14 }) {
        this.PauseTile(this.actions[0])
        this.PauseTile(this.actions[1])
      }

      Row({ space: 14 }) {
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
        .fontSize(26)
        .fontColor(EmuColors.error)

      Text('结束运行 TERMINATE_SESSION')
        .fontSize(16)
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
    .height(76)
    .padding({ left: 22, right: 22 })
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
      }
      .width('100%')
      .height(86)
    }
    .width('100%')
    .padding(22)
    .backgroundColor('#CC050505')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(4)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .backdropBlur(18)

      Column({ space: 22 }) {
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
        .padding({ left: 18 })
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
      .constraintSize({ maxWidth: 540 })
      .padding({ left: 34, right: 34, top: 94, bottom: 110 })
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}
