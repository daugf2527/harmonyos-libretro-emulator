import {
  EmuColors,
  EmuMetrics, EmuTypography } from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

@ComponentV2
export struct EmuHeaderBar {
  @Param titleText: string = '碳影 / Carbon Shade'
  @Param titleIcon: string = 'memory'
  @Param rightLabel: string = ''
  @Param rightIcon: string = 'settings_input_component'
  @Param activeTextColor: string = ''
  @Param mutedTextColor: string = '#888888'
  @Param iconSize: number = 18
  @Param rightIconSize: number = 20
  @Event onRightClick?: () => void

  build() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: this.titleIcon,
          iconSize: this.iconSize
        })

        Text(this.titleText)
          .fontSize(13)
          .fontColor(this.activeTextColor.length > 0 ? this.activeTextColor : EmuColors.primary)
          .letterSpacing(2.2)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        if (this.rightLabel.length > 0) {
          Text(this.rightLabel)
            .fontSize(EmuTypography.xs)
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
    .backgroundColor('#D9000000')
    .border({
      width: { bottom: 1 },
      color: EmuMetrics.panelBorderColor,
      style: BorderStyle.Solid
    })
  }
}

@ComponentV2
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
      .onAreaChange((_oldValue, _newValue) => {
        this.drawGrid()
      })
  }

  private drawGrid(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    ctx.clearRect(0, 0, w, h)
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

@ComponentV2
export struct ScanlineBackground {
  @Param lineColor: string = '#1400FF41'
  @Param lineSpacing: number = 2
  @Param alternateColor: string = ''
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawScanlines()
      })
      .onAreaChange((_oldValue, _newValue) => {
        this.drawScanlines()
      })
  }

  private drawScanlines(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    ctx.clearRect(0, 0, w, h)
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

@ComponentV2
export struct GridBackground {
  @Param gridSize: number = 40
  @Param lineColor: string = '#1A484848'
  @Param lineWidth: number = 1
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawGrid()
      })
      .onAreaChange((_oldValue, _newValue) => {
        this.drawGrid()
      })
  }

  private drawGrid(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    ctx.clearRect(0, 0, w, h)
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

export interface BarChartItem {
  height: number
  isPrimary: boolean
}

@ComponentV2
export struct BarChartBackground {
  @Param bars: BarChartItem[] = []
  @Param primaryColor: string = '#00FF41'
  @Param secondaryColor: string = '#333333'
  @Param barGap: number = 2
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.drawBars()
      })
      .onAreaChange((_oldValue, _newValue) => {
        this.drawBars()
      })
  }

  private drawBars(): void {
    const ctx = this.context
    const w = ctx.width
    const h = ctx.height
    ctx.clearRect(0, 0, w, h)
    const count = this.bars.length
    if (count === 0) {
      return
    }
    const barW = (w - this.barGap * (count - 1)) / count
    for (let i = 0; i < count; i++) {
      const bar = this.bars[i]
      const x = i * (barW + this.barGap)
      ctx.fillStyle = bar.isPrimary ? this.primaryColor : this.secondaryColor
      ctx.globalAlpha = bar.isPrimary ? 0.5 : 1.0
      ctx.fillRect(x, h - bar.height, barW, bar.height)
    }
    ctx.globalAlpha = 1.0
  }
}
