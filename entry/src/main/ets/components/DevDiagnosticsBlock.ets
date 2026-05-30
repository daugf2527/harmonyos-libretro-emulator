import { EmuMotion, EmuTypography } from '../common/EmuUiTokens'
import { EmuLoadingSpinner } from './EmuLoadingSpinner'

// Dev-only diagnostics: 验证核心符号 + 10 分钟压力测试。
// 挂在 LibretroNewArchTestPage / Settings 'dev' 分组。
// 生产 LibretroGamePage 不再承载这两个调试入口。
@Component
export struct DevDiagnosticsBlock {
  @Prop coreCheckRunning: boolean = false
  @Prop coreCheckText: string = ''
  @Prop soakRunning: boolean = false
  @Prop soakSecondsLeft: number = 0
  @Prop soakSummaryText: string = ''
  @Prop switching: boolean = false
  onCoreCheck?: () => void
  onSoakToggle?: () => void

  build() {
    Column({ space: 12 }) {
      this.CoreCheckRow()
      this.SoakRow()
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#1A2027')
    .borderRadius(8)
  }

  @Builder
  private CoreCheckRow() {
    Column({ space: 6 }) {
      Button() {
        Row({ space: 8 }) {
          if (this.coreCheckRunning) {
            EmuLoadingSpinner({ dotSize: 16, color: '#FFFFFF', trackOpacity: 0.25 })
          }
          Text(this.coreCheckRunning ? '验证中...' : '验证核心符号')
            .fontSize(EmuTypography.lg)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .height(44)
      .width('100%')
      .type(ButtonType.Normal)
      .borderRadius(8)
      .backgroundColor(this.coreCheckRunning ? '#607D8B' : '#546E7A')
      .opacity(this.coreCheckRunning || this.switching ? 0.75 : 1)
      .animation({ duration: EmuMotion.stateChangeMs, curve: Curve.EaseInOut })
      .enabled(!this.coreCheckRunning && !this.switching)
      .onClick(() => {
        this.onCoreCheck?.()
      })

      if (this.coreCheckText) {
        Text(this.coreCheckText)
          .fontSize(EmuTypography.sm)
          .fontColor(Color.White)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private SoakRow() {
    Column({ space: 6 }) {
      Button() {
        Row({ space: 8 }) {
          if (this.soakRunning) {
            EmuLoadingSpinner({ dotSize: 14, color: '#FFFFFF', trackOpacity: 0.25 })
          }
          Text(this.soakRunning ? `压力测试中 ${this.soakSecondsLeft}s` : '压力测试 (10min)')
            .fontSize(EmuTypography.md)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .height(40)
      .width('100%')
      .type(ButtonType.Normal)
      .borderRadius(8)
      .backgroundColor(this.soakRunning ? '#607D8B' : '#455A64')
      .opacity(this.switching ? 0.6 : 1)
      .animation({ duration: EmuMotion.stateChangeMs, curve: Curve.EaseInOut })
      .enabled(!this.switching)
      .onClick(() => {
        this.onSoakToggle?.()
      })

      if (this.soakSummaryText) {
        Text(this.soakSummaryText)
          .fontSize(EmuTypography.sm)
          .fontColor('#CCCCCC')
          .width('100%')
      }
    }
    .width('100%')
  }
}
