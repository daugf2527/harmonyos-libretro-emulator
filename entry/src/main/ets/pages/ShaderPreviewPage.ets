import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuColors } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

@Entry
@Component
struct ShaderPreviewPage {
  @State private scanlineIntensity: number = 65
  @State private curvature: number = 12
  @State private saturation: number = 115
  @State private selectedMode: string = 'STATIC_PREVIEW'
  @State private statusText: string = 'SHADER_RUNTIME_NOT_CONFIGURED'
  private readonly scanlineRows: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  private readonly previewStatBars: number[] = [12, 22, 34, 18, 42, 28]
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: true },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: false },
    { key: 'system', iconName: 'tune', label: '系统', isActive: false }
  ]

  private resetPreset(): void {
    this.scanlineIntensity = 65
    this.curvature = 12
    this.saturation = 115
    this.statusText = 'LOCAL_PRESET_RESET'
  }

  private savePreviewConfig(): void {
    this.statusText = 'LOCAL_PREVIEW_CFG_SAVED'
  }

  private getSliderTrackValue(value: number): number {
    return Math.max(0, Math.min(100, value))
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'engine')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[ShaderPreviewPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[ShaderPreviewPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  @Builder
  private PreviewPane(title: string, mode: string, processed: boolean) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: processed ? 135 : 45,
          colors: processed ?
            [[0xFF133323, 0.0], [0xFF1B2856, 0.52], [0xFF2E1528, 1.0]] :
            [[0xFF101010, 0.0], [0xFF243044, 0.52], [0xFF171717, 1.0]]
        })

      if (processed) {
        Column({ space: 3 }) {
          ForEach(this.scanlineRows, (item: number) => {
            Row()
              .width('100%')
              .height(1)
              .backgroundColor('#55000000')
              .opacity(0.5)
          }, (item: number) => `scan-${item}`)
        }
        .width('100%')
        .height('100%')
      }

      Column({ space: 10 }) {
        Text(title)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(processed ? '#00131313' : EmuColors.onSurfaceVariant)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(1.8)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(processed ? EmuColors.primary : '#CC000000')
        Text(processed ? `${mode} / NOT_CONFIGURED` : mode)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(processed ? EmuColors.primary : EmuColors.onSurface)
      }
      .align(processed ? Alignment.TopEnd : Alignment.TopStart)
      .margin({ left: 18, right: 18, top: 18 })

      Row({ space: 10 }) {
        Row()
          .width(32)
          .height(32)
          .backgroundColor(processed ? EmuColors.primary : '#88E5E5E5')
        Row()
          .width(32)
          .height(32)
          .backgroundColor(processed ? '#FFED7F64' : '#88757575')
        Row()
          .width(32)
          .height(32)
          .backgroundColor(processed ? '#FF72FF70' : '#88484848')
      }
      .align(Alignment.Center)
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(EmuColors.surfaceContainerLow)
    .clip(true)
  }

  @Builder
  private SplitPreview() {
    Stack() {
      Row({ space: 1 }) {
        this.PreviewPane('SOURCE_RAW', 'NEAREST / NO_SHADER', false)
        this.PreviewPane('LIVE_SHADER', this.selectedMode, true)
      }
      .width('100%')
      .height('100%')

      Row() {
        Text('↕')
          .fontSize(18)
          .fontColor('#00131313')
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .backgroundColor(EmuColors.primary)
          .borderRadius(3)
      }
      .width(2)
      .height('100%')
      .backgroundColor(EmuColors.primary)
      .justifyContent(FlexAlign.Center)
      .align(Alignment.Center)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private ParameterPanel() {
    Column({ space: 18 }) {
      Row() {
        Text('实时视觉滤镜预览')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .letterSpacing(1.4)
        Text(this.statusText)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      this.SliderRow('SCANLINE INTENSITY', this.scanlineIntensity, '%')
      this.SliderRow('CRT CURVATURE', this.curvature, '%')
      this.SliderRow('COLOR SATURATION', this.saturation, '%')

      Row({ space: 12 }) {
        Button('RESET')
          .layoutWeight(1)
          .height(36)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: EmuColors.outline, style: BorderStyle.Solid })
          .onClick(() => {
            this.resetPreset()
          })
        Button('SAVE_CFG')
          .layoutWeight(1)
          .height(36)
          .fontSize(10)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: EmuColors.primary, style: BorderStyle.Solid })
          .onClick(() => {
            this.savePreviewConfig()
          })
      }
      .width('100%')
    }
    .width('86%')
    .constraintSize({ maxWidth: 320 })
    .padding(20)
    .backgroundColor('#F21F1F1F')
    .border({ width: 0.5, color: '#55484848', style: BorderStyle.Solid })
  }

  @Builder
  private SliderRow(label: string, value: number, suffix: string) {
    Column({ space: 8 }) {
      Row() {
        Text(label)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)
        Text(`${value}${suffix}`)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurface)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor(EmuColors.outlineVariant)
        Row()
          .width(`${this.getSliderTrackValue(value)}%`)
          .height(1)
          .backgroundColor(EmuColors.primary)
          .align(Alignment.Start)

        Row() {
          Row()
            .width(2)
            .height(12)
            .backgroundColor(EmuColors.onSurface)
        }
        .width(`${this.getSliderTrackValue(value)}%`)
        .height(1)
        .justifyContent(FlexAlign.End)
        .align(Alignment.Start)
      }
      .width('100%')
      .height(14)
    }
    .width('100%')
  }

  @Builder
  private PreviewStatsOverlay() {
    Column({ space: 12 }) {
      Row() {
        Text('GPU LOAD')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text('NOT_CONFIGURED')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row()
        .width('100%')
        .height(2)
        .backgroundColor('#3300FF41')

      Row() {
        Text('LATENCY')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text('PREVIEW_ONLY')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 3 }) {
        ForEach(this.previewStatBars, (heightValue: number) => {
          Row()
            .width(6)
            .height(heightValue)
            .backgroundColor(heightValue > 24 ? EmuColors.primary : EmuColors.surfaceContainerHighest)
        }, (heightValue: number) => `${heightValue}`)
      }
      .height(46)
      .alignItems(VerticalAlign.Bottom)
    }
    .width(250)
    .padding(18)
    .backgroundColor('#B3000000')
    .backdropBlur(12)
    .border({ width: 0.5, color: '#55484848', style: BorderStyle.Solid })
    .align(Alignment.BottomStart)
    .margin({ left: 24, bottom: 24 })
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: 'OS_EMU_v2.4.1',
        titleIcon: 'terminal',
        rightLabel: 'ENGINE_PREVIEW_MODE',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 18
      })

      Stack() {
        this.SplitPreview()
        this.PreviewStatsOverlay()
        Row() {
          Blank()
          this.ParameterPanel()
        }
        .width('100%')
        .height('100%')
        .padding({ right: 18 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)

      EmuBottomNav({
        items: this.navItems,
        activeFontColor: EmuColors.primary,
        inactiveFontColor: '#FF666666',
        indicatorStyle: 'dot',
        panelBackgroundColor: '#FF000000',
        onItemClick: (key: string) => {
          this.onBottomNavClick(key)
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
