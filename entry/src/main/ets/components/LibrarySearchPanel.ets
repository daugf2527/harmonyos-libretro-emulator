import { EmuColors } from '../common/EmuUiTokens'
import { LibraryRecord } from '../common/LibraryRepository'
import { EmuIcon } from './EmuIcon'
import {
  EmuTelemetryBarItem,
  EmuTelemetryCellItem,
  EmuTelemetryPanel
} from './EmuTelemetryPanel'
import { PlatformChipBar } from './PlatformChipBar'

export interface LibrarySearchPanelState {
  keyword: string
  searchBusy: boolean
  showSearchResults: boolean
  searchResults: LibraryRecord[]
  telemetryCells: EmuTelemetryCellItem[]
  telemetryBars: EmuTelemetryBarItem[]
  platforms: string[]
  selectedPlatform: string
  spinnerAngle: number
}

@Component
export struct LibrarySearchPanel {
  @Prop state: LibrarySearchPanelState = {
    keyword: '',
    searchBusy: false,
    showSearchResults: false,
    searchResults: [],
    telemetryCells: [],
    telemetryBars: [],
    platforms: ['ALL'],
    selectedPlatform: 'ALL',
    spinnerAngle: 0
  }
  onKeywordChange?: (value: string) => void
  onSearchResultLaunch?: (item: LibraryRecord) => void
  onPlatformChange?: (value: string) => void

  build() {
    Column({ space: 16 }) {
      Row({ space: 14 }) {
        EmuIcon({
          name: 'search',
          tone: 'muted',
          iconSize: 20,
          opacityValue: 0.9
        })

        Stack() {
          if (this.state.keyword.trim().length === 0) {
            Text('搜索游戏库')
              .fontSize(15)
              .fontColor('#66484848')
              .align(Alignment.Start)
          }

          TextInput({ text: this.state.keyword, placeholder: '' })
            .width('100%')
            .fontSize(15)
            .fontColor(EmuColors.onSurface)
            .backgroundColor(Color.Transparent)
            .border({ width: 0 })
            .padding({ left: 0, right: 0 })
            .onChange((value: string) => {
              this.onKeywordChange?.(value)
            })
        }
        .layoutWeight(1)

        if (this.state.searchBusy) {
          this.Spinner(16, 1.5, EmuColors.primary, '#2200FF41')
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 15, bottom: 15 })
      .backgroundColor('#0A0A0A')
      .borderRadius(8)
      .border({ width: 0.5, color: '#44757575', style: BorderStyle.Solid })
      .alignItems(VerticalAlign.Center)

      if (this.state.showSearchResults) {
        this.SearchResults()
      }

      EmuTelemetryPanel({
        cells: this.state.telemetryCells,
        bars: this.state.telemetryBars
      })

      PlatformChipBar({
        items: this.state.platforms,
        selected: this.state.selectedPlatform,
        onChange: (value: string) => {
          this.onPlatformChange?.(value)
        }
      })
    }
  }

  @Builder
  private SearchResults() {
    Column({ space: 2 }) {
      if (this.state.searchResults.length > 0) {
        ForEach(this.state.searchResults, (item: LibraryRecord) => {
          Row() {
            Text(item.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.platform)
              .fontSize(10)
              .fontColor('#A000FF41')
              .fontFamily('monospace')
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(4)
              .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })
          }
          .width('100%')
          .height(42)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .onClick(() => {
            this.onSearchResultLaunch?.(item)
          })
        }, (item: LibraryRecord) => item.id)
      } else {
        Text('无匹配结果')
          .fontSize(12)
          .fontColor(EmuColors.onSurfaceVariant)
          .fontStyle(FontStyle.Italic)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor('#F2141414')
    .backdropBlur(20)
    .borderRadius(12)
    .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
  }

  @Builder
  private Spinner(size: number, borderWidth: number, activeColor: string, trackColor: string) {
    Stack() {
      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .border({ width: borderWidth, color: trackColor, style: BorderStyle.Solid })

      Row()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .border({
          width: { top: borderWidth, right: borderWidth },
          color: activeColor,
          style: BorderStyle.Solid
        })
        .rotate({ angle: this.state.spinnerAngle })
    }
  }
}
