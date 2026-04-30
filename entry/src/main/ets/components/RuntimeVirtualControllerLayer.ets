import { EmuColors, createIndexRange } from '../common/EmuUiTokens'
import { InputLayoutButton } from '../common/InputLayoutRepository'

export interface RuntimeVirtualControllerState {
  buttons: InputLayoutButton[]
  layoutWidth: number
  layoutHeight: number
}

@Component
export struct RuntimeVirtualControllerLayer {
  @Prop state: RuntimeVirtualControllerState = {
    buttons: [],
    layoutWidth: 720,
    layoutHeight: 360
  }
  onButtonChange?: (keyId: number, pressed: boolean) => void
  onAnalogChange?: (index: number, x: number, y: number) => void
  onQuickSave?: () => void

  private readonly scanlineIndexes: number[] = createIndexRange(160)
  private readonly quickSaveLetters: string[] = ['Q', 'U', 'I', 'C', 'K', 'S', 'A', 'V', 'E']

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[0x00131313, 0.0], [0x66131313, 0.62], [0xCC000000, 1.0]]
        })
        .hitTestBehavior(HitTestMode.None)

      Column({ space: 1 }) {
        ForEach(this.scanlineIndexes, (index: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor(index % 2 === 0 ? '#1000FF41' : '#10000000')
        }, (index: number) => `scanline-${index}`)
      }
      .width('100%')
      .height('100%')
      .opacity(0.32)
      .hitTestBehavior(HitTestMode.None)

      this.buildControllerDeck()
      this.buildQuickSaveRail()
      this.buildSystemTriggers()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildControllerDeck() {
    Row({ space: 0 }) {
      this.buildMovementPanel()
      this.buildActionPanel()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28, top: 48, bottom: 96 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildMovementPanel() {
    Column({ space: 13 }) {
      Column({ space: 1 }) {
        Row() {
          Blank()
            .layoutWeight(1)
          this.RuntimeInputButtonById('up', '▲', '', 24, 24, 3)
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        Row({ space: 0 }) {
          this.RuntimeInputButtonById('left', '◀', '', 24, 24, 3)
          Stack() {
            Row()
              .width(43)
              .height(43)
              .backgroundColor('#66131313')
              .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
              .borderRadius(2)

            Row()
              .width(7)
              .height(7)
              .borderRadius(4)
              .backgroundColor('#CC00FF41')
              .shadow({ radius: 7, color: '#6600FF41', offsetX: 0, offsetY: 0 })
          }
          .width(43)
          .height(43)
          this.RuntimeInputButtonById('right', '▶', '', 24, 24, 3)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        Row() {
          Blank()
            .layoutWeight(1)
          this.RuntimeInputButtonById('down', '▼', '', 24, 24, 3)
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')

      Text('M O V E M E N T')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor('#88757575')
        .maxLines(1)
    }
    .width('34%')
    .constraintSize({ minWidth: 100, maxWidth: 118 })
    .height(176)
    .padding({ left: 14, right: 14, top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#E8000000')
    .backdropBlur(24)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(8)
    .shadow({ radius: 16, color: '#99000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildActionPanel() {
    Stack() {
      Column({ space: 11 }) {
        Row() {
          Blank()
            .layoutWeight(1)
          this.RuntimeInputButtonById('y', 'Y', '', 44, 44, 22)
          Blank()
            .layoutWeight(1)
        }
        .width('100%')

        Row() {
          this.RuntimeInputButtonById('x', 'X', '', 44, 44, 22)
          Blank()
            .layoutWeight(1)
          this.RuntimeInputButtonById('b', 'B', '返回', 58, 44, 22)
        }
        .width('100%')

        Row() {
          Blank()
            .layoutWeight(1)
          this.RuntimeInputButtonById('a', 'A', '确认 (Confirm)', 112, 34, 8)
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ left: 29, right: 29, top: 27, bottom: 27 })
      .justifyContent(FlexAlign.Center)
    }
    .width('58%')
    .constraintSize({ minWidth: 190, maxWidth: 214 })
    .height(204)
    .margin({ left: 0 })
    .backgroundColor('#E8000000')
    .backdropBlur(24)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(8)
    .shadow({ radius: 18, color: '#99000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildQuickSaveRail() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Text('▣')
          .fontSize(22)
          .fontColor(EmuColors.primary)

        Column({ space: 1 }) {
          ForEach(this.quickSaveLetters, (letter: string) => {
            Text(letter)
              .fontSize(8)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.primary)
              .maxLines(1)
          }, (letter: string) => letter)
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(57)
    .height(157)
    .fontColor(EmuColors.primary)
    .backgroundColor('#E8000000')
    .backdropBlur(24)
    .border({ width: 1, color: EmuColors.primary, style: BorderStyle.Solid })
    .borderRadius(16)
    .shadow({ radius: 14, color: '#5500FF41', offsetX: 0, offsetY: 0 })
    .align(Alignment.TopEnd)
    .margin({ right: 22, top: 164 })
    .onClick(() => {
      this.onQuickSave?.()
    })
  }

  @Builder
  private buildSystemTriggers() {
    Row({ space: 14 }) {
      this.RuntimeInputButtonById('select', 'SELECT', '', 77, 30, 6)
      this.RuntimeInputButtonById('start', 'START', '', 72, 30, 6)
    }
    .align(Alignment.Bottom)
    .margin({ bottom: 100 })
  }

  @Builder
  private RuntimeInputButtonById(
    buttonId: string,
    labelText: string,
    captionText: string,
    buttonWidth: number,
    buttonHeight: number,
    radius: number
  ) {
    Button({ type: ButtonType.Normal }) {
      if (captionText.length > 0) {
        Row({ space: 6 }) {
          Text(labelText)
            .fontSize(buttonId === 'a' ? 20 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor(buttonId === 'a' ? EmuColors.primary : EmuColors.onSurface)
            .fontFamily('monospace')
            .maxLines(1)

          Text(captionText)
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor(buttonId === 'a' ? EmuColors.primary : '#AAED7F64')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      } else {
        Text(labelText)
          .fontSize(buttonId === 'select' || buttonId === 'start' ? 10 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isPrimaryRuntimeButton(buttonId) ? EmuColors.primary : EmuColors.onSurface)
          .fontFamily('monospace')
          .letterSpacing(buttonId === 'select' || buttonId === 'start' ? 0.8 : 0)
          .maxLines(1)
      }
    }
    .width(buttonWidth)
    .height(buttonHeight)
    .backgroundColor('#D9000000')
    .border({
      width: this.isPrimaryRuntimeButton(buttonId) ? 1.2 : 0.5,
      color: this.isPrimaryRuntimeButton(buttonId) ? EmuColors.primary : '#66484848',
      style: BorderStyle.Solid
    })
    .borderRadius(radius)
    .shadow({
      radius: this.isPrimaryRuntimeButton(buttonId) ? 18 : 10,
      color: this.isPrimaryRuntimeButton(buttonId) ? '#4400FF41' : '#99000000',
      offsetX: 0,
      offsetY: 4
    })
    .onTouch((event) => {
      const keyId = this.getRetroButtonId(buttonId)
      if (keyId < 0 || !this.onButtonChange) {
        return
      }
      if (event.type === TouchType.Down) {
        this.onButtonChange(keyId, true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onButtonChange(keyId, false)
      }
    })
  }

  private isPrimaryRuntimeButton(buttonId: string): boolean {
    return buttonId === 'a' || buttonId === 'quick_save'
  }

  private getRetroButtonId(buttonId: string): number {
    if (buttonId === 'b') {
      return 0
    }
    if (buttonId === 'x') {
      return 1
    }
    if (buttonId === 'select') {
      return 2
    }
    if (buttonId === 'start') {
      return 3
    }
    if (buttonId === 'up') {
      return 4
    }
    if (buttonId === 'down') {
      return 5
    }
    if (buttonId === 'left') {
      return 6
    }
    if (buttonId === 'right') {
      return 7
    }
    if (buttonId === 'a') {
      return 8
    }
    if (buttonId === 'y') {
      return 9
    }
    if (buttonId === 'l') {
      return 10
    }
    if (buttonId === 'r') {
      return 11
    }
    return -1
  }
}
