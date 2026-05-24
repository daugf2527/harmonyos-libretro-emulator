import { EmuColors, EmuMotion, EmuStateColors } from '../common/EmuUiTokens'
import { InputLayoutButton } from '../common/InputLayoutRepository'

// Independent button component so each press maintains its own visual state
// (pressed -> brighter background / scale-down / stronger glow). Lifting this
// out of @Builder is required because @Builder cannot own @State.
//
// State precedence (high → low): disabled > pressed > primary > default.
// Disabled wins over pressed: cannot show "pressed" feedback while disabled.
@Component
struct RuntimeKeyButton {
  @Prop button: InputLayoutButton
  @Prop isPrimary: boolean = false
  @Prop buttonWidth: number = 48
  @Prop buttonHeight: number = 48
  @Prop cornerRadius: number = 3
  @Prop labelFontSize: number = 16
  @Prop disabled: boolean = false
  @State private pressed: boolean = false
  onPressChange?: (pressed: boolean) => void

  private resolveBackground(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBackground
    }
    if (this.pressed) {
      return EmuColors.primary
    }
    return this.isPrimary ? '#1F00FF41' : '#D9000000'
  }

  private resolveBorderColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBorder
    }
    if (this.pressed) {
      return EmuColors.primary
    }
    return this.isPrimary ? EmuColors.primary : '#66484848'
  }

  private resolveFontColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledText
    }
    if (this.pressed) {
      return EmuStateColors.onPrimary
    }
    return this.isPrimary ? EmuColors.primary : EmuColors.onSurface
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Text(this.button.label)
        .fontSize(this.labelFontSize)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.resolveFontColor())
        .letterSpacing(this.button.shape === 'function' ? 0.4 : 0)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.buttonWidth)
    .height(this.buttonHeight)
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .backgroundColor(this.resolveBackground())
    .border({
      width: this.pressed && !this.disabled ? 2 : (this.isPrimary ? 1.2 : 0.5),
      color: this.resolveBorderColor(),
      style: BorderStyle.Solid
    })
    .borderRadius(this.cornerRadius)
    .shadow({
      radius: this.disabled ? 0 : (this.pressed ? 24 : (this.isPrimary ? 18 : 10)),
      color: this.disabled
        ? '#00000000'
        : (this.pressed ? '#AA00FF41' : (this.isPrimary ? '#4400FF41' : '#99000000')),
      offsetX: 0,
      offsetY: this.pressed ? 1 : 4
    })
    .scale(this.pressed && !this.disabled ? { x: 0.92, y: 0.92 } : { x: 1, y: 1 })
    .opacity(this.disabled ? 0.5 : 1)
    .animation({
      duration: EmuMotion.stateChangeMs,
      curve: Curve.EaseInOut
    })
    .position({ x: this.button.x, y: this.button.y })
    .enabled(!this.disabled)
    .onTouch((event: TouchEvent) => {
      if (this.disabled) {
        return
      }
      if (event.type === TouchType.Down) {
        this.pressed = true
        this.onPressChange?.(true)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
        this.onPressChange?.(false)
      }
    })
  }
}

@Component
export struct RuntimeVirtualControllerLayer {
  @Prop buttons: InputLayoutButton[] = []
  @Prop layoutWidth: number = 440
  @Prop layoutHeight: number = 340
  onButtonChange?: (keyId: number, pressed: boolean) => void
  onAnalogChange?: (index: number, x: number, y: number) => void

  build() {
    // No more full-screen gradient/scanline shroud — this Component is now
    // hosted inside a bottom-half container in LibretroGamePage, so a thin
    // top border and the buttons themselves are enough. Keeps the game frame
    // crisp (no gray cast) and gives the controller area a clear separation.
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#F2050505')
        .border({ width: { top: 1 }, color: '#3300FF41', style: BorderStyle.Solid })
        .hitTestBehavior(HitTestMode.None)

      this.buildLayoutCanvas()

      // 浮层：select/start 贴 controller 顶部居中，不挤压主按键 layout 空间
      this.buildFloatingFunctionButtons()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildLayoutCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.buttons, (button: InputLayoutButton) => {
        if (!this.isFloatingFunctionButton(button.id)) {
          RuntimeKeyButton({
            button: button,
            isPrimary: this.isPrimaryRuntimeButton(button.id),
            buttonWidth: this.getButtonWidth(button),
            buttonHeight: this.getButtonHeight(button),
            cornerRadius: this.getBorderRadius(button),
            labelFontSize: this.getLabelFontSize(button),
            onPressChange: (pressed: boolean) => {
              const keyId = this.getRetroButtonId(button)
              if (keyId < 0 || !this.onButtonChange) {
                return
              }
              this.onButtonChange(keyId, pressed)
            }
          })
        }
      }, (button: InputLayoutButton) => button.id)
    }
    .width(this.layoutWidth)
    .height(this.layoutHeight)
    .margin({ bottom: 16, left: 16, right: 16, top: 8 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildFloatingFunctionButtons() {
    Stack({ alignContent: Alignment.Top }) {
      Row({ space: 14 }) {
        ForEach(this.buttons, (button: InputLayoutButton) => {
          if (this.isFloatingFunctionButton(button.id)) {
            Button({ type: ButtonType.Normal }) {
              Text(button.label)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontFamily('monospace')
                .fontColor(EmuColors.primary)
                .letterSpacing(0.4)
            }
            .height(26)
            .padding({ left: 14, right: 14, top: 2, bottom: 2 })
            .backgroundColor('#1F00FF41')
            .border({ width: 1.2, color: EmuColors.primary, style: BorderStyle.Solid })
            .borderRadius(13)
            .shadow({ radius: 8, color: '#4400FF41', offsetX: 0, offsetY: 2 })
            .onTouch((event: TouchEvent) => {
              const keyId = this.getRetroButtonId(button)
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
        }, (button: InputLayoutButton) => button.id)
      }
      .padding({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private isFloatingFunctionButton(id: string): boolean {
    return id === 'select' || id === 'start'
  }

  private getButtonWidth(button: InputLayoutButton): number {
    if (button.shape === 'shoulder') {
      return 86
    }
    if (button.shape === 'function') {
      return 64
    }
    return button.size
  }

  private getButtonHeight(button: InputLayoutButton): number {
    if (button.shape === 'shoulder') {
      return 34
    }
    if (button.shape === 'function') {
      return 28
    }
    return button.size
  }

  private getBorderRadius(button: InputLayoutButton): number {
    if (button.shape === 'circle') {
      return button.size / 2
    }
    if (button.shape === 'function') {
      return 8
    }
    if (button.shape === 'shoulder') {
      return 4
    }
    return 3
  }

  private getLabelFontSize(button: InputLayoutButton): number {
    if (button.shape === 'circle') {
      return button.id === 'a' ? 22 : 18
    }
    if (button.shape === 'function') {
      return 10
    }
    if (button.shape === 'shoulder') {
      return 14
    }
    return 16
  }

  private isPrimaryRuntimeButton(buttonId: string): boolean {
    // 所有按钮统一使用 primary 样式（半透绿底 + 1.2px 绿边框 + 阴影），
    // 否则非 primary 的 0.5px/#66484848 边框在黑底上几乎不可见。
    return true
  }

  private getRetroButtonId(button: InputLayoutButton): number {
    if (Number.isFinite(button.retroButtonId) && button.retroButtonId >= 0 && button.retroButtonId <= 15) {
      return button.retroButtonId
    }
    if (button.id === 'b') {
      return 0
    }
    if (button.id === 'x') {
      return 1
    }
    if (button.id === 'select') {
      return 2
    }
    if (button.id === 'start') {
      return 3
    }
    if (button.id === 'up') {
      return 4
    }
    if (button.id === 'down') {
      return 5
    }
    if (button.id === 'left') {
      return 6
    }
    if (button.id === 'right') {
      return 7
    }
    if (button.id === 'a') {
      return 8
    }
    if (button.id === 'y') {
      return 9
    }
    if (button.id === 'l') {
      return 10
    }
    if (button.id === 'r') {
      return 11
    }
    return -1
  }
}
