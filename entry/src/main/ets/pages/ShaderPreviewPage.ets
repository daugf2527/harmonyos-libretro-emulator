import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

@Component
struct ShaderSliderRow {
  @Prop label: string = ''
  @Prop value: number = 0
  @Prop suffix: string = ''
  @Prop min: number = 0
  @Prop max: number = 100
  onChange?: (value: number) => void

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.label)
          .fontSize(9)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)
        Text(`${this.value}${this.suffix}`)
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurface)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Slider({
        value: this.value,
        min: this.min,
        max: this.max,
        step: 1
      })
        .width('100%')
        .blockColor(EmuColors.onSurface)
        .trackColor(EmuColors.outlineVariant)
        .selectedColor(EmuColors.primary)
        .showSteps(false)
        .showTips(false)
        .onChange((next: number) => {
          const clamped = Math.max(this.min, Math.min(this.max, Math.round(next)))
          this.onChange?.(clamped)
        })
    }
    .width('100%')
  }
}

@Entry
@Component
struct ShaderPreviewPage {
  @State private scanlineIntensity: number = 65
  @State private curvature: number = 12
  @State private saturation: number = 115
  @State private selectedMode: string = 'STATIC_PREVIEW'
  @State private statusText: string = '滤镜运行时未接入'
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
    this.statusText = '已重置本地预设'
  }

  private savePreviewConfig(): void {
    this.statusText = '已保存预览预设'
  }

  private getSliderTrackValue(value: number): number {
    return Math.max(0, Math.min(100, value))
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(200, Math.round(value)))
  }

  private onScanlineIntensityChange = (value: number): void => {
    this.scanlineIntensity = Math.max(0, Math.min(100, Math.round(value)))
  }

  private onCurvatureChange = (value: number): void => {
    this.curvature = Math.max(0, Math.min(100, Math.round(value)))
  }

  private onSaturationChange = (value: number): void => {
    this.saturation = this.clampPercent(value)
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
                    .fontColor(processed ? '#00131313' : EmuColors.onSurfaceVariant)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(1.8)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(processed ? EmuColors.primary : '#CC000000')
        Text(processed ? `${mode} / 未应用到游戏` : mode)
          .fontSize(EmuTypography.xs)
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
        this.PreviewPane('原始画面', '原始输出', false)
        this.PreviewPane('滤镜预览', this.selectedMode, true)
      }
      .width('100%')
      .height('100%')

      Row() {
        Text('↕')
          .fontSize(EmuTypography.xl)
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
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .letterSpacing(1.4)
        Text(this.statusText)
          .fontSize(9)
                    .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      ShaderSliderRow({
        label: '扫描线强度',
        value: this.scanlineIntensity,
        suffix: '%',
        min: 0,
        max: 100,
        onChange: this.onScanlineIntensityChange
      })
      ShaderSliderRow({
        label: 'CRT 曲率',
        value: this.curvature,
        suffix: '%',
        min: 0,
        max: 100,
        onChange: this.onCurvatureChange
      })
      ShaderSliderRow({
        label: '色彩饱和度',
        value: this.saturation,
        suffix: '%',
        min: 0,
        max: 200,
        onChange: this.onSaturationChange
      })

      Row({ space: 12 }) {
        Button('重置')
          .layoutWeight(1)
          .height(36)
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: EmuColors.outline, style: BorderStyle.Solid })
          .onClick(() => {
            this.resetPreset()
          })
        Button('保存预设')
          .layoutWeight(1)
          .height(36)
          .fontSize(EmuTypography.xs)
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
  private SliderRow(
    label: string,
    value: number,
    suffix: string,
    min: number,
    max: number,
    onChange: (value: number) => void
  ) {
    Column({ space: 8 }) {
      Row() {
        Text(label)
          .fontSize(9)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)
        Text(`${value}${suffix}`)
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurface)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Slider({
        value: value,
        min: min,
        max: max,
        step: 1
      })
        .width('100%')
        .blockColor(EmuColors.onSurface)
        .trackColor(EmuColors.outlineVariant)
        .selectedColor(EmuColors.primary)
        .showSteps(false)
        .showTips(false)
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  private PreviewStatsOverlay() {
    Column({ space: 12 }) {
      Row() {
        Text('GPU 负载')
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text('未接入')
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row()
        .width('100%')
        .height(2)
        .backgroundColor('#3300FF41')

      Row() {
        Text('延迟')
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text('仅预览')
          .fontSize(EmuTypography.xs)
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
    .width('72%')
    .constraintSize({ maxWidth: 250 })
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
        titleText: '碳影',
        titleIcon: 'terminal',
        rightLabel: '滤镜预览',
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
