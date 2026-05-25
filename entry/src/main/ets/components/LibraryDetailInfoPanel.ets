import { createIndexRange, EmuColors, EmuTypography } from '../common/EmuUiTokens'

interface TelemetryPoint {
  x: number
  y: number
}

export interface LibraryDetailSummaryCellData {
  title: string
  value: string
}

@Component
export struct LibraryDetailInfoPanel {
  @Prop showExtendedDetails: boolean = false
  @Prop hasRuntimeSnapshot: boolean = false
  @Prop telemetryFpsText: string = '--.-'
  @Prop telemetryAudioText: string = '--'
  @Prop telemetryDropText: string = '--'
  @Prop telemetryScanOffset: number = -180
  @Prop telemetryGlowOpacity: number = 0.2
  @Prop overviewText: string = 'Unknown'
  @Prop runtimeSummaryText: string = ''
  @Prop primaryCells: LibraryDetailSummaryCellData[] = []
  @Prop extendedCells: LibraryDetailSummaryCellData[] = []
  @Prop telemetryProfile: number[] = []
  onToggleDetails?: () => void
  private readonly telemetryVerticalLines: number[] = createIndexRange(13)
  private readonly telemetryHorizontalLines: number[] = createIndexRange(4)

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
    .height(isLarge ? 76 : 60)
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
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor('#B3B3B3')
        .fontFamily('monospace')
        .letterSpacing(1.6)

      Text(this.showExtendedDetails ? '˄' : '˅')
        .fontSize(EmuTypography.xs)
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
        ForEach(this.primaryCells, (cell: LibraryDetailSummaryCellData) => {
          this.SummaryCell(cell)
        }, (cell: LibraryDetailSummaryCellData) => cell.title)
      }
      .width('100%')

      this.DetailToggleRow()

      if (this.showExtendedDetails) {
        Column({ space: 1 }) {
          Row({ space: 1 }) {
            ForEach(this.extendedCells.slice(0, 2), (cell: LibraryDetailSummaryCellData) => {
              this.SummaryCell(cell, true)
            }, (cell: LibraryDetailSummaryCellData) => cell.title)
          }
          .width('100%')

          Row({ space: 1 }) {
            ForEach(this.extendedCells.slice(2, 4), (cell: LibraryDetailSummaryCellData) => {
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
        .fontSize(EmuTypography.xs)
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

          Text(this.buildTelemetryStatusText())
            .fontSize(EmuTypography.xs)
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
        Row({ space: 23 }) {
          ForEach(this.telemetryVerticalLines, (_: number) => {
            Column()
              .width(1)
              .height('100%')
              .backgroundColor('#112C2C2C')
          }, (index: number) => `v-${index}`)
        }
        .width('100%')
        .height('100%')

        Column({ space: 16 }) {
          ForEach(this.telemetryHorizontalLines, (_: number) => {
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
          .opacity(this.telemetryGlowOpacity + 0.12)

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
          .translate({ y: this.telemetryScanOffset })
          .opacity(0.72)

        Row({ space: 26 }) {
          this.TelemetryMeta('AUDIO', this.telemetryAudioText)
          this.TelemetryMeta('DROPS', this.telemetryDropText)
        }
        .align(Alignment.TopStart)
        .margin({ left: 12, top: 10 })
      }
      .width('100%')
      .height(92)
      .backgroundColor('#060606')
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .clip(true)
    }
    .width('100%')
  }

  private buildTelemetryStatusText(): string {
    const sessionText = this.hasRuntimeSnapshot ? 'LAST SESSION' : 'NO SESSION DATA'
    return `${this.telemetryFpsText} FPS // ${sessionText}`
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
          Text(this.overviewText)
            .fontSize(EmuTypography.md)
            .lineHeight(26)
            .fontColor('#E6E5E5E5')

          if (this.showExtendedDetails) {
            Text(this.runtimeSummaryText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .lineHeight(18)
              .fontColor(EmuColors.onSurfaceVariant)
              .margin({ top: 12 })
          }
        }
        .width('100%')
        .padding({ left: 22, right: 20, top: 20, bottom: 20 })
        .backgroundColor(EmuColors.surfaceContainer)
        .border({
          width: { left: 1.5 },
          color: '#6600FF41',
          style: BorderStyle.Solid
        })

        Text('◢')
          .fontSize(EmuTypography.xl)
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
    this.telemetryProfile.forEach((height: number, index: number) => {
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
