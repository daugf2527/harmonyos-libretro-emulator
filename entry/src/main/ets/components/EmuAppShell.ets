import {
  EmuColors,
  EmuMetrics
} from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

@Component
export struct EmuHeaderBar {
  @Prop titleText: string = 'EMU_CORE_v1.0'
  @Prop titleIcon: string = 'memory'
  @Prop rightLabel: string = ''
  @Prop rightIcon: string = 'settings_input_component'
  @Prop activeTextColor: string = ''
  @Prop mutedTextColor: string = '#888888'
  @Prop iconSize: number = 18
  @Prop rightIconSize: number = 20
  onRightClick?: () => void

  build() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: this.titleIcon,
          iconSize: this.iconSize
        })

        Text(this.titleText)
          .fontFamily('monospace')
          .fontSize(13)
          .fontColor(this.activeTextColor.length > 0 ? this.activeTextColor : EmuColors.primary)
          .letterSpacing(2.2)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        if (this.rightLabel.length > 0) {
          Text(this.rightLabel)
            .fontSize(10)
            .fontColor(this.mutedTextColor)
            .letterSpacing(0.8)
        }

        EmuIcon({
          name: this.rightIcon,
          iconSize: this.rightIconSize
        })
      }
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onRightClick?.()
      })
    }
    .width('100%')
    .height(EmuMetrics.headerHeight)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backdropBlur(24)
    .backgroundColor('#D9000000')
    .border({
      width: { bottom: 1 },
      color: EmuMetrics.panelBorderColor,
      style: BorderStyle.Solid
    })
  }
}

@Component
export struct EmuPrecisionGridBackdrop {
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .opacity(0.8)
      .onReady(() => {
        this.drawGrid()
      })
  }

  private drawGrid(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    const gridSize = EmuMetrics.gridSize
    ctx.strokeStyle = EmuMetrics.gridLineColor
    ctx.lineWidth = 1
    ctx.beginPath()
    for (let y = gridSize; y < h; y += gridSize) {
      ctx.moveTo(0, y)
      ctx.lineTo(w, y)
    }
    for (let x = gridSize; x < w; x += gridSize) {
      ctx.moveTo(x, 0)
      ctx.lineTo(x, h)
    }
    ctx.stroke()
  }
}

@Component
export struct ScanlineBackground {
  @Prop lineColor: string = '#1400FF41'
  @Prop lineSpacing: number = 2
  @Prop alternateColor: string = ''
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawScanlines()
      })
  }

  private drawScanlines(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    const step = 1 + this.lineSpacing
    ctx.lineWidth = 1
    let row = 0
    for (let y = 0; y < h; y += step) {
      ctx.strokeStyle = this.alternateColor.length > 0 && row % 2 !== 0
        ? this.alternateColor
        : this.lineColor
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(w, y)
      ctx.stroke()
      row++
    }
  }
}

@Component
export struct GridBackground {
  @Prop gridSize: number = 40
  @Prop lineColor: string = '#1A484848'
  @Prop lineWidth: number = 1
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawGrid()
      })
  }

  private drawGrid(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    ctx.strokeStyle = this.lineColor
    ctx.lineWidth = this.lineWidth
    ctx.beginPath()
    for (let y = this.gridSize; y < h; y += this.gridSize) {
      ctx.moveTo(0, y)
      ctx.lineTo(w, y)
    }
    for (let x = this.gridSize; x < w; x += this.gridSize) {
      ctx.moveTo(x, 0)
      ctx.lineTo(x, h)
    }
    ctx.stroke()
  }
}
