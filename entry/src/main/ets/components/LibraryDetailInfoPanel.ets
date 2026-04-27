import { createIndexRange, EmuColors } from '../common/EmuUiTokens'

interface TelemetryPoint {
  x: number
  y: number
}

export interface LibraryDetailSummaryCellData {
  title: string
  value: string
}

export interface LibraryDetailInfoPanelState {
  showExtendedDetails: boolean
  primaryCells: LibraryDetailSummaryCellData[]
  extendedCells: LibraryDetailSummaryCellData[]
  hasRuntimeSnapshot: boolean
  telemetryFpsText: string
  telemetryAudioText: string
  telemetryDropText: string
  telemetryProfile: number[]
  telemetryScanOffset: number
  telemetryGlowOpacity: number
  overviewText: string
  runtimeSummaryText: string
}

@Component
export struct LibraryDetailInfoPanel {
  @Prop state: LibraryDetailInfoPanelState = {
    showExtendedDetails: false,
    primaryCells: [],
    extendedCells: [],
    hasRuntimeSnapshot: false,
    telemetryFpsText: '--.-',
    telemetryAudioText: '--',
    telemetryDropText: '--',
    telemetryProfile: [],
    telemetryScanOffset: -180,
    telemetryGlowOpacity: 0.2,
    overviewText: 'Unknown',
    runtimeSummaryText: ''
  }
  onToggleDetails?: () => void

  build() {
    Column({ space: 30 }) {
      this.SummarySection()
      this.TelemetrySection()
      this.OverviewSection()
    }
    .width('100%')
  }

  @Builder
  private SummaryCell(cell: LibraryDetailSummaryCellData, isLarge: boolean = false) {
    Column({ space: 8 }) {
      Text(cell.title)
        .fontSize(isLarge ? 10 : 9)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8AABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.6)

      Text(cell.value)
        .fontSize(isLarge ? 14 : 12)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(isLarge ? 78 : 72)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(EmuColors.surfaceContainerLow)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private DetailToggleRow() {
    Row({ space: 4 }) {
      Text('详情 (DETAILS)')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#B3B3B3')
        .fontFamily('monospace')
        .letterSpacing(1.6)

      Text(this.state.showExtendedDetails ? '˄' : '˅')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .onClick(() => {
      this.onToggleDetails?.()
    })
  }

  @Builder
  private SummarySection() {
    Column({ space: 8 }) {
      Row({ space: 1 }) {
        ForEach(this.state.primaryCells, (cell: LibraryDetailSummaryCellData) => {
          this.SummaryCell(cell)
        }, (cell: LibraryDetailSummaryCellData) => cell.title)
      }
      .width('100%')

      this.DetailToggleRow()

      if (this.state.showExtendedDetails) {
        Column({ space: 1 }) {
          Row({ space: 1 }) {
            ForEach(this.state.extendedCells.slice(0, 2), (cell: LibraryDetailSummaryCellData) => {
              this.SummaryCell(cell, true)
            }, (cell: LibraryDetailSummaryCellData) => cell.title)
          }
          .width('100%')

          Row({ space: 1 }) {
            ForEach(this.state.extendedCells.slice(2, 4), (cell: LibraryDetailSummaryCellData) => {
              this.SummaryCell(cell, true)
            }, (cell: LibraryDetailSummaryCellData) => cell.title)
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private TelemetryMeta(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(8)
        .fontColor('#889D9E9E')
        .fontFamily('monospace')

      Text(value)
        .fontSize(10)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TelemetrySection() {
    Column({ space: 12 }) {
      Row() {
        Text('SYSTEM TELEMETRY')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCABABAB')
          .fontFamily('monospace')
          .letterSpacing(1.8)

        Row({ space: 6 }) {
          Row()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(EmuColors.primary)

          Text(`${this.state.telemetryFpsText} FPS // ${this.state.hasRuntimeSnapshot ? 'LAST SESSION' : 'NO SESSION DATA'}`)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
            .fontFamily('monospace')
            .letterSpacing(1.2)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        Column({ space: 16 }) {
          ForEach(createIndexRange(4), (_: number) => {
            Row()
              .width('100%')
              .height(1)
              .backgroundColor('#142C2C2C')
          }, (index: number) => index.toString())
        }
        .width('100%')
        .height('100%')
        .padding({ top: 16, bottom: 16 })
        .justifyContent(FlexAlign.SpaceBetween)

        Path({
          width: 440,
          height: 96,
          commands: this.buildTelemetryFillPath()
        })
          .fill('#00FF41')
          .fillOpacity(0.06)
          .strokeWidth(0)
          .opacity(this.state.telemetryGlowOpacity + 0.12)

        Path({
          width: 440,
          height: 96,
          commands: this.buildTelemetryStrokePath()
        })
          .fillOpacity(0)
          .stroke('#00FF41')
          .strokeWidth(1.6)
          .strokeOpacity(0.92)

        Column()
          .width(52)
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              ['#0000FF41', 0],
              ['#1800FF41', 0.5],
              ['#0000FF41', 1]
            ]
          })
          .align(Alignment.Start)
          .opacity(0.45)

        Column()
          .width('100%')
          .height(18)
          .linearGradient({
            angle: 180,
            colors: [
              ['#0000FF41', 0],
              ['#2200FF41', 0.52],
              ['#0000FF41', 1]
            ]
          })
          .translate({ y: this.state.telemetryScanOffset })
          .opacity(0.72)

        Row({ space: 26 }) {
          this.TelemetryMeta('AUDIO', this.state.telemetryAudioText)
          this.TelemetryMeta('DROPS', this.state.telemetryDropText)
        }
        .align(Alignment.TopStart)
        .margin({ left: 12, top: 10 })
      }
      .width('100%')
      .height(96)
      .backgroundColor('#060606')
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .clip(true)
    }
    .width('100%')
  }

  @Builder
  private OverviewSection() {
    Column({ space: 12 }) {
      Text('OVERVIEW')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#CCABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.8)

      Stack() {
        Column() {
          Text(this.state.overviewText)
            .fontSize(14)
            .lineHeight(26)
            .fontColor('#E6E5E5E5')

          Text(this.state.runtimeSummaryText)
            .fontSize(10)
            .fontFamily('monospace')
            .lineHeight(18)
            .fontColor(EmuColors.onSurfaceVariant)
            .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18, bottom: 18 })
        .backgroundColor(EmuColors.surfaceContainer)
        .border({
          width: { left: 1.5 },
          color: '#6600FF41',
          style: BorderStyle.Solid
        })

        Text('◢')
          .fontSize(18)
          .fontColor('#22FFFFFF')
          .align(Alignment.TopEnd)
          .margin({ top: 8, right: 8 })
      }
      .width('100%')
    }
    .width('100%')
  }

  private buildTelemetryPoints(): TelemetryPoint[] {
    const points: TelemetryPoint[] = []
    const spacing = 36
    const chartBottom = 76
    this.state.telemetryProfile.forEach((height: number, index: number) => {
      points.push({
        x: index * spacing,
        y: chartBottom - Math.min(52, height)
      })
    })
    return points
  }

  private buildTelemetryStrokePath(): string {
    const points = this.buildTelemetryPoints()
    if (points.length === 0) {
      return ''
    }
    let path = `M${points[0].x} ${points[0].y}`
    for (let index = 1; index < points.length; index += 1) {
      path += ` L${points[index].x} ${points[index].y}`
    }
    return path
  }

  private buildTelemetryFillPath(): string {
    const points = this.buildTelemetryPoints()
    if (points.length === 0) {
      return ''
    }
    let path = this.buildTelemetryStrokePath()
    const lastPoint = points[points.length - 1]
    path += ` L${lastPoint.x} 96 L0 96 Z`
    return path
  }
}
