import { EmuColors } from '../common/EmuUiTokens'
import { InputLayoutButton } from '../common/InputLayoutRepository'
import { AnalogStickControl } from './VirtualController'

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

      this.buildPersistedInputLayout()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPersistedInputLayout() {
    Stack() {
      ForEach(this.state.buttons, (button: InputLayoutButton) => {
        this.RuntimeInputButton(button)
      }, (button: InputLayoutButton) => button.id)

      Row() {
        this.buildAnalogStick(0, 140, 60)
        Blank()
        this.buildAnalogStick(1, 120, 50)
          .margin({ right: 20 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 36, right: 36, bottom: 24 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .constraintSize({ maxWidth: 520, maxHeight: 400 })
    .aspectRatio(this.getLayoutAspectRatio())
    .align(Alignment.Bottom)
    .padding({ left: 24, right: 24, bottom: 20 })
  }

  @Builder
  private RuntimeInputButton(button: InputLayoutButton) {
    Button(this.getRuntimeButtonLabel(button))
      .width(this.getRuntimeButtonWidth(button))
      .height(this.getRuntimeButtonHeight(button))
      .fontSize(button.shape === 'function' ? 11 : 16)
      .fontWeight(FontWeight.Bold)
      .fontColor(button.id === 'a' ? EmuColors.primary : EmuColors.onSurface)
      .backgroundColor('#CC0B0D0C')
      .border({
        width: button.id === 'a' ? 1 : 0.5,
        color: button.id === 'a' ? EmuColors.primary : '#66757575',
        style: BorderStyle.Solid
      })
      .borderRadius(this.getRuntimeButtonRadius(button))
      .align(Alignment.TopStart)
      .position({
        x: this.getRuntimeInputPercentX(button.x),
        y: this.getRuntimeInputPercentY(button.y)
      })
      .onTouch((event) => {
        const keyId = this.getRetroButtonId(button.id)
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

  @Builder
  private buildAnalogStick(index: number, baseSize: number, knobSize: number) {
    AnalogStickControl({
      index,
      baseSize,
      knobSize,
      onAnalogChange: (stickIndex: number, x: number, y: number) => {
        if (this.onAnalogChange) {
          this.onAnalogChange(stickIndex, x, y)
        }
      }
    })
    .margin({ top: 20 })
  }

  private getLayoutAspectRatio(): number {
    if (this.state.layoutWidth <= 0 || this.state.layoutHeight <= 0) {
      return 2
    }
    return this.state.layoutWidth / this.state.layoutHeight
  }

  private getRuntimeButtonLabel(button: InputLayoutButton): string {
    if (button.id === 'up') {
      return '↑'
    }
    if (button.id === 'down') {
      return '↓'
    }
    if (button.id === 'left') {
      return '←'
    }
    if (button.id === 'right') {
      return '→'
    }
    return button.label
  }

  private getRuntimeButtonWidth(button: InputLayoutButton): number {
    if (button.shape === 'shoulder') {
      return 86
    }
    if (button.shape === 'function') {
      return 64
    }
    return button.size
  }

  private getRuntimeButtonHeight(button: InputLayoutButton): number {
    if (button.shape === 'shoulder') {
      return 34
    }
    if (button.shape === 'function') {
      return 34
    }
    return button.size
  }

  private getRuntimeButtonRadius(button: InputLayoutButton): number {
    if (button.shape === 'circle') {
      return button.size / 2
    }
    if (button.shape === 'function') {
      return 8
    }
    return 4
  }

  private getRuntimeInputPercentX(value: number): string {
    return `${this.clampRuntimeInputPercent((value / this.state.layoutWidth) * 100)}%`
  }

  private getRuntimeInputPercentY(value: number): string {
    return `${this.clampRuntimeInputPercent((value / this.state.layoutHeight) * 100)}%`
  }

  private clampRuntimeInputPercent(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 100) {
      return 100
    }
    return value
  }

  private getRetroButtonId(buttonId: string): number {
    if (buttonId === 'b') {
      return 0
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
    if (buttonId === 'l') {
      return 10
    }
    if (buttonId === 'r') {
      return 11
    }
    return -1
  }
}
