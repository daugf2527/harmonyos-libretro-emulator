import { EmuColors, EmuMotion, EmuStateColors } from '../common/EmuUiTokens'
import { InputLayoutButton } from '../common/InputLayoutRepository'

// Independent button component so each press maintains its own visual state
// (pressed -> brighter background / scale-down / stronger glow). Lifting this
// out of @Builder is required because @Builder cannot own @State.
//
// State precedence (high → low): disabled > pressed > primary > default.
// Disabled wins over pressed: cannot show "pressed" feedback while disabled.
@ComponentV2
struct RuntimeKeyButton {
  @Require @Param button: InputLayoutButton
  @Param isPrimary: boolean = false
  @Param buttonWidth: number = 48
  @Param buttonHeight: number = 48
  @Param cornerRadius: number = 3
  @Param labelFontSize: number = 16
  @Param disabled: boolean = false
  @Param forcedPressed: boolean = false
  @Local private pressed: boolean = false
  @Event onPressChange?: (pressed: boolean) => void

  private isPressedNow(): boolean {
    return this.pressed || this.forcedPressed
  }

  private resolveBackground(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBackground
    }
    if (this.isPressedNow()) {
      return EmuColors.primary
    }
    return this.isPrimary ? '#1F00FF41' : '#D9000000'
  }

  private resolveBorderColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledBorder
    }
    if (this.isPressedNow()) {
      return EmuColors.primary
    }
    return this.isPrimary ? EmuColors.primary : '#66484848'
  }

  private resolveFontColor(): string {
    if (this.disabled) {
      return EmuStateColors.disabledText
    }
    if (this.isPressedNow()) {
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
      width: this.isPressedNow() && !this.disabled ? 2 : (this.isPrimary ? 1.2 : 0.5),
      color: this.resolveBorderColor(),
      style: BorderStyle.Solid
    })
    .borderRadius(this.cornerRadius)
    .shadow({
      radius: this.disabled ? 0 : (this.isPressedNow() ? 24 : (this.isPrimary ? 18 : 10)),
      color: this.disabled
        ? '#00000000'
        : (this.isPressedNow() ? '#AA00FF41' : (this.isPrimary ? '#4400FF41' : '#99000000')),
      offsetX: 0,
      offsetY: this.isPressedNow() ? 1 : 4
    })
    .scale(this.isPressedNow() && !this.disabled ? { x: 0.92, y: 0.92 } : { x: 1, y: 1 })
    .opacity(this.disabled ? 0.5 : 1)
    .animation({
      duration: EmuMotion.instantMs,
      curve: Curve.EaseOut
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

@ComponentV2
struct RuntimeFloatingFunctionButton {
  @Require @Param button: InputLayoutButton
  @Local private pressed: boolean = false
  @Event onPressChange?: (pressed: boolean) => void

  build() {
    Button({ type: ButtonType.Normal }) {
      Text(this.button.label)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(this.pressed ? EmuStateColors.onPrimary : EmuColors.primary)
        .letterSpacing(0.4)
    }
    .height(26)
    .padding({ left: 14, right: 14, top: 2, bottom: 2 })
    .backgroundColor(this.pressed ? EmuColors.primary : '#1F00FF41')
    .border({
      width: this.pressed ? 1.8 : 1.2,
      color: EmuColors.primary,
      style: BorderStyle.Solid
    })
    .borderRadius(13)
    .shadow({
      radius: this.pressed ? 14 : 8,
      color: this.pressed ? '#AA00FF41' : '#4400FF41',
      offsetX: 0,
      offsetY: this.pressed ? 1 : 2
    })
    .scale(this.pressed ? { x: 0.95, y: 0.95 } : { x: 1, y: 1 })
    .animation({ duration: EmuMotion.instantMs, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
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

@ComponentV2
export struct RuntimeVirtualControllerLayer {
  @Param buttons: InputLayoutButton[] = []
  @Param layoutWidth: number = 440
  @Param layoutHeight: number = 340
  // 16-bit mask of RETRO_DEVICE_ID_JOYPAD_* declared by the active core via
  // RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS. 0 = core hasn't declared, render
  // the full layout (fallback). Non-zero = hide buttons whose retroButtonId
  // bit is unset.
  @Param inputDescriptorMask: number = 0
  @Event onButtonChange?: (keyId: number, pressed: boolean) => void
  @Event onAnalogChange?: (index: number, x: number, y: number) => void

  // atan2-based D-pad overlay 状态:覆盖在 up/down/left/right 4 按钮 bbox 上,
  // 接管 touch 后由角度判定激活的方向(支持斜方向同时激活相邻两键)。
  // 4 个独立 @Local 而非 Object,确保单字段变更触发 re-render。
  @Local private dpadUpPressed: boolean = false
  @Local private dpadDownPressed: boolean = false
  @Local private dpadLeftPressed: boolean = false
  @Local private dpadRightPressed: boolean = false
  @Local private dpadActive: boolean = false

  // diagonal sector 比 cardinal 窄(30° vs 60°),抑制误触斜方向
  // 参考 Lemuroid 1.5 / RetroArch D-Pad Diagonal Sensitivity 默认 80% 范式
  private static readonly DIAGONAL_HALF_DEG: number = 15
  private static readonly DEADZONE_RATIO: number = 0.18

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#CC050505')
        .border({ width: { top: 1 }, color: '#3300FF41', style: BorderStyle.Solid })
        .hitTestBehavior(HitTestMode.None)

      this.buildLayoutCanvas()

      // 浮层:select/start 贴 controller 顶部居中,不挤压主按键 layout 空间
      this.buildFloatingFunctionButtons()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildLayoutCanvas() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.buttons, (button: InputLayoutButton) => {
        if (!this.isFloatingFunctionButton(button.id) && this.isButtonDeclaredByCore(button)) {
          RuntimeKeyButton({
            button: button,
            isPrimary: this.isPrimaryRuntimeButton(button.id),
            buttonWidth: this.getButtonWidth(button),
            buttonHeight: this.getButtonHeight(button),
            cornerRadius: this.getBorderRadius(button),
            labelFontSize: this.getLabelFontSize(button),
            forcedPressed: this.getDpadForcedPressed(button.id),
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

      // D-pad atan2 overlay — 覆盖 up/down/left/right 4 按钮的 bounding box,
      // 接管 touch 后按角度激活方向(支持斜方向同时按下相邻两 cardinal)。
      // disabled=true 让 4 个原 dir button 不再响应 touch,避免双触发。
      this.buildDpadOverlay()
    }
    .width(this.layoutWidth)
    .height(this.layoutHeight)
    .margin({ bottom: 16, left: 16, right: 16, top: 8 })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildDpadOverlay() {
    if (this.hasDpadButtons()) {
      Stack()
        .width(this.getDpadBboxWidth())
        .height(this.getDpadBboxHeight())
        .position({ x: this.getDpadBboxX(), y: this.getDpadBboxY() })
        .backgroundColor(this.dpadActive ? '#1A00FF41' : Color.Transparent)
        .borderRadius(this.getDpadBboxWidth() / 2)
        .animation({ duration: EmuMotion.instantMs, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          this.handleDpadTouch(event)
        })
    }
  }

  @Builder
  private buildFloatingFunctionButtons() {
    Stack({ alignContent: Alignment.Top }) {
      Row({ space: 14 }) {
        ForEach(this.buttons, (button: InputLayoutButton) => {
          if (this.isFloatingFunctionButton(button.id) && this.isButtonDeclaredByCore(button)) {
            RuntimeFloatingFunctionButton({
              button: button,
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
      .padding({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private isFloatingFunctionButton(id: string): boolean {
    return id === 'select' || id === 'start'
  }

  // mask=0 表示 core 未声明,默认显示;mask>0 时只显示 bit 命中的键。
  // retroButtonId<0 (无映射) 在 mask 模式下也隐藏。
  private isButtonDeclaredByCore(button: InputLayoutButton): boolean {
    if (this.inputDescriptorMask === 0) {
      return true
    }
    const keyId = this.getRetroButtonId(button)
    if (keyId < 0 || keyId > 15) {
      return false
    }
    return (this.inputDescriptorMask & (1 << keyId)) !== 0
  }

  private isDpadDirection(id: string): boolean {
    return id === 'up' || id === 'down' || id === 'left' || id === 'right'
  }

  private hasDpadButtons(): boolean {
    let count = 0
    this.buttons.forEach((b: InputLayoutButton) => {
      if (this.isDpadDirection(b.id) && this.isButtonDeclaredByCore(b)) {
        count++
      }
    })
    return count >= 4
  }

  private findDpadButton(id: string): InputLayoutButton | undefined {
    let found: InputLayoutButton | undefined = undefined
    this.buttons.forEach((b: InputLayoutButton) => {
      if (b.id === id) {
        found = b
      }
    })
    return found
  }

  // bbox 取 4 个 dir 按钮 union(含自身 size),稍微外扩 8px 给手指余量
  private getDpadBboxX(): number {
    const left = this.findDpadButton('left')
    if (!left) return 0
    return left.x - 8
  }

  private getDpadBboxY(): number {
    const up = this.findDpadButton('up')
    if (!up) return 0
    return up.y - 8
  }

  private getDpadBboxWidth(): number {
    const left = this.findDpadButton('left')
    const right = this.findDpadButton('right')
    if (!left || !right) return 0
    return (right.x + this.getButtonWidth(right)) - left.x + 16
  }

  private getDpadBboxHeight(): number {
    const up = this.findDpadButton('up')
    const down = this.findDpadButton('down')
    if (!up || !down) return 0
    return (down.y + this.getButtonHeight(down)) - up.y + 16
  }

  private getDpadForcedPressed(id: string): boolean {
    if (id === 'up') return this.dpadUpPressed
    if (id === 'down') return this.dpadDownPressed
    if (id === 'left') return this.dpadLeftPressed
    if (id === 'right') return this.dpadRightPressed
    return false
  }

  // 8-sector with diagonal-bias-down (diagonal half-width < cardinal half-width)
  // angle 0° = right, 90° = down (ArkUI Y-down 坐标系一致)
  // cardinal 中心在 0/90/180/270, half-width = 45° - DIAGONAL_HALF_DEG
  // diagonal 中心在 45/135/225/315, half-width = DIAGONAL_HALF_DEG
  // 返回 cardinal 集合(可能 1 或 2 个),空数组 = deadzone 内无激活
  private resolveDpadDirections(dx: number, dy: number, radiusX: number, radiusY: number): string[] {
    const radius = Math.min(radiusX, radiusY)
    const dist = Math.hypot(dx, dy)
    if (dist < radius * RuntimeVirtualControllerLayer.DEADZONE_RATIO) {
      return []
    }
    let angle = Math.atan2(dy, dx) * (180 / Math.PI)
    if (angle < 0) {
      angle += 360
    }
    const diag = RuntimeVirtualControllerLayer.DIAGONAL_HALF_DEG
    // 检查是否落在 4 个 diagonal sector(45/135/225/315 ± diag)
    if (Math.abs(angle - 45) <= diag) return ['right', 'down']
    if (Math.abs(angle - 135) <= diag) return ['left', 'down']
    if (Math.abs(angle - 225) <= diag) return ['left', 'up']
    if (Math.abs(angle - 315) <= diag) return ['right', 'up']
    // 其余落入 cardinal
    if (angle < 45 || angle >= 315) return ['right']
    if (angle < 135) return ['down']
    if (angle < 225) return ['left']
    return ['up']
  }

  private applyDpadDirections(active: string[]): void {
    const wantUp = active.indexOf('up') >= 0
    const wantDown = active.indexOf('down') >= 0
    const wantLeft = active.indexOf('left') >= 0
    const wantRight = active.indexOf('right') >= 0
    this.emitDpadKey('up', wantUp, this.dpadUpPressed)
    this.emitDpadKey('down', wantDown, this.dpadDownPressed)
    this.emitDpadKey('left', wantLeft, this.dpadLeftPressed)
    this.emitDpadKey('right', wantRight, this.dpadRightPressed)
    this.dpadUpPressed = wantUp
    this.dpadDownPressed = wantDown
    this.dpadLeftPressed = wantLeft
    this.dpadRightPressed = wantRight
  }

  private emitDpadKey(id: string, want: boolean, current: boolean): void {
    if (want === current || !this.onButtonChange) {
      return
    }
    const btn = this.findDpadButton(id)
    if (!btn) return
    const keyId = this.getRetroButtonId(btn)
    if (keyId < 0) return
    this.onButtonChange(keyId, want)
  }

  private handleDpadTouch(event: TouchEvent): void {
    if (!event.touches || event.touches.length === 0) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.applyDpadDirections([])
        this.dpadActive = false
      }
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.applyDpadDirections([])
      this.dpadActive = false
      return
    }
    const t = event.touches[0]
    const cx = this.getDpadBboxWidth() / 2
    const cy = this.getDpadBboxHeight() / 2
    const dx = t.x - cx
    const dy = t.y - cy
    const dirs = this.resolveDpadDirections(dx, dy, cx, cy)
    this.applyDpadDirections(dirs)
    this.dpadActive = event.type === TouchType.Down || event.type === TouchType.Move
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
