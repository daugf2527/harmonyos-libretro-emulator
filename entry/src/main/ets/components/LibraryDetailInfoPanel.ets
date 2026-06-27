import { EmuColors, EmuTypography } from '../common/EmuUiTokens'

export interface LibraryDetailSummaryCellData {
  title: string
  value: string
}

@ComponentV2
export struct LibraryDetailInfoPanel {
  @Param showExtendedDetails: boolean = false
  @Param hasRuntimeSnapshot: boolean = false
  @Param telemetryFpsText: string = '--.-'
  @Param telemetryAudioText: string = '--'
  @Param telemetryDropText: string = '--'
  @Param overviewText: string = '暂无本地简介，可在资料编辑中补充。'
  @Param runtimeSummaryText: string = ''
  @Param primaryCells: LibraryDetailSummaryCellData[] = []
  @Param extendedCells: LibraryDetailSummaryCellData[] = []
  @Event onToggleDetails?: () => void

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
      Text(this.showExtendedDetails ? '收起详情' : '展开详情')
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
        }, (cell: LibraryDetailSummaryCellData, index: number) => `primary:${index}:${cell.title}:${cell.value}`)
      }
      .width('100%')

      this.DetailToggleRow()

      if (this.showExtendedDetails) {
        Column({ space: 1 }) {
          Row({ space: 1 }) {
            ForEach(this.extendedCells.slice(0, 2), (cell: LibraryDetailSummaryCellData) => {
              this.SummaryCell(cell, true)
            }, (cell: LibraryDetailSummaryCellData, index: number) => `extended-a:${index}:${cell.title}:${cell.value}`)
          }
          .width('100%')

          Row({ space: 1 }) {
            ForEach(this.extendedCells.slice(2, 4), (cell: LibraryDetailSummaryCellData) => {
              this.SummaryCell(cell, true)
            }, (cell: LibraryDetailSummaryCellData, index: number) => `extended-b:${index}:${cell.title}:${cell.value}`)
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
    Column({ space: 6 }) {
      Text(label)
        .fontSize(9)
        .fontColor('#889D9E9E')
        .fontFamily('monospace')

      Text(value)
        .fontSize(EmuTypography.sm)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(EmuColors.surfaceContainerLow)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TelemetrySection() {
    Column({ space: 12 }) {
      Row() {
        Text('最近一次运行摘要')
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

      Column({ space: 12 }) {
        Row({ space: 8 }) {
          this.TelemetryMeta('最近帧率', this.telemetryFpsText)
          this.TelemetryMeta('音频缓冲', this.telemetryAudioText)
          this.TelemetryMeta('掉帧', this.telemetryDropText)
        }
        .width('100%')

        Text(this.buildTelemetryNoteText())
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .fontFamily('monospace')
          .width('100%')
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .backgroundColor(EmuColors.surfaceContainer)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    }
    .width('100%')
  }

  private buildTelemetryStatusText(): string {
    return this.hasRuntimeSnapshot ? '历史记录摘要' : '暂无运行记录'
  }

  private buildTelemetryNoteText(): string {
    if (!this.hasRuntimeSnapshot) {
      return '当前还没有可展示的运行记录。'
    }
    return '以下数据来自最近一次运行记录，仅用于回顾，不会在当前页面实时刷新。'
  }

  @Builder
  private OverviewSection() {
    Column({ space: 12 }) {
      Text('简介')
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

}
