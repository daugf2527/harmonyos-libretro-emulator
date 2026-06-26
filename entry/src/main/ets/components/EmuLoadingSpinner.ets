import { EmuColors, EmuMotion } from '../common/EmuUiTokens'

// 统一加载旋转指示器：1.2s/圈，符合 EmuMotion.loadingSpinMs 规范。
// 凡是关键异步操作（保存、校验、切换核心、停止游戏等）应在 loading 期间
// 显示此组件，并禁用其它按钮（disabled > loading > error > ...）。
@ComponentV2
export struct EmuLoadingSpinner {
  @Param dotSize: number = 16
  @Param trackOpacity: number = 0.2
  @Param color: string = EmuColors.primary
  @Local private angle: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.angle = 0
    const stepMs = 40
    const stepDeg = (360 * stepMs) / EmuMotion.loadingSpinMs
    this.timer = setInterval(() => {
      this.angle = (this.angle + stepDeg) % 360
    }, stepMs)
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  build() {
    Stack() {
      Row()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .border({ width: 2, color: this.color, style: BorderStyle.Solid })
        .opacity(this.trackOpacity)

      Row()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .border({
          width: { top: 2, right: 2 },
          color: this.color,
          style: BorderStyle.Solid
        })
        .rotate({ angle: this.angle })
    }
  }
}
