import { common } from '@kit.AbilityKit'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuHeaderBar, ScanlineBackground } from '../components/EmuAppShell'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'
import {
  createDefaultRuntimeVisualSettingsProfile,
  describeRuntimeAspectMode,
  loadRuntimeVisualSettingsProfile,
  RuntimeAspectMode,
  RuntimeVisualSettingsProfile,
  saveRuntimeVisualSettingsProfile
} from '../common/RuntimeVisualSettingsRepository'

interface ShaderAspectOptionItem {
  key: RuntimeAspectMode
  label: string
}

@ComponentV2
struct ShaderSliderRow {
  @Param label: string = ''
  @Param value: number = 0
  @Param suffix: string = ''
  @Param min: number = 0
  @Param max: number = 100
  @Event onChange?: (value: number) => void

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
@ComponentV2
struct ShaderPreviewPage {
  @Local private draftProfile: RuntimeVisualSettingsProfile = createDefaultRuntimeVisualSettingsProfile()
  @Local private statusText: string = '读取视觉配置中'
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')
  private readonly aspectOptions: ShaderAspectOptionItem[] = [
    { key: '4:3', label: '4:3' },
    { key: '16:9', label: '16:9' },
    { key: 'native', label: 'NATIVE' }
  ]
  private pageActive: boolean = false
  private taskToken: number = 0

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadSavedProfile()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.taskToken += 1
  }

  private beginTask(): number {
    this.taskToken += 1
    return this.taskToken
  }

  private isCurrentTask(token: number): boolean {
    return this.pageActive && token === this.taskToken
  }

  private cloneProfile(): RuntimeVisualSettingsProfile {
    return {
      version: this.draftProfile.version,
      aspectMode: this.draftProfile.aspectMode,
      scanlineIntensity: this.draftProfile.scanlineIntensity,
      curvature: this.draftProfile.curvature,
      saturation: this.draftProfile.saturation,
      updatedAt: this.draftProfile.updatedAt
    }
  }

  private applyProfile(profile: RuntimeVisualSettingsProfile, statusText: string): void {
    this.draftProfile = {
      version: profile.version,
      aspectMode: profile.aspectMode,
      scanlineIntensity: profile.scanlineIntensity,
      curvature: profile.curvature,
      saturation: profile.saturation,
      updatedAt: profile.updatedAt
    }
    this.statusText = statusText
  }

  private async loadSavedProfile(): Promise<void> {
    const token = this.beginTask()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.statusText = '上下文不可用'
      return
    }
    try {
      const profile = await loadRuntimeVisualSettingsProfile(context)
      if (!this.isCurrentTask(token)) {
        return
      }
      this.applyProfile(profile, '视觉配置已载入')
    } catch (err) {
      if (!this.isCurrentTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ShaderPreviewPage', 'Visual', `读取视觉配置失败: ${message}`)
      this.statusText = '读取视觉配置失败'
    }
  }

  private async persistProfile(profile: RuntimeVisualSettingsProfile, successText: string): Promise<void> {
    const token = this.beginTask()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.statusText = '上下文不可用'
      return
    }
    try {
      const saved = await saveRuntimeVisualSettingsProfile(context, profile)
      if (!this.isCurrentTask(token)) {
        return
      }
      this.applyProfile(saved, successText)
    } catch (err) {
      if (!this.isCurrentTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ShaderPreviewPage', 'Visual', `保存视觉配置失败: ${message}`)
      this.statusText = '保存视觉配置失败'
    }
  }

  private resetPreset(): void {
    void this.persistProfile(createDefaultRuntimeVisualSettingsProfile(), '已重置视觉配置')
  }

  private savePreviewConfig(): void {
    void this.persistProfile(this.cloneProfile(), '已保存视觉配置')
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(200, Math.round(value)))
  }

  private onScanlineIntensityChange = (value: number): void => {
    const nextProfile = this.cloneProfile()
    nextProfile.scanlineIntensity = Math.max(0, Math.min(100, Math.round(value)))
    this.draftProfile = nextProfile
    this.statusText = '有未保存改动'
  }

  private onCurvatureChange = (value: number): void => {
    const nextProfile = this.cloneProfile()
    nextProfile.curvature = Math.max(0, Math.min(100, Math.round(value)))
    this.draftProfile = nextProfile
    this.statusText = '有未保存改动'
  }

  private onSaturationChange = (value: number): void => {
    const nextProfile = this.cloneProfile()
    nextProfile.saturation = this.clampPercent(value)
    this.draftProfile = nextProfile
    this.statusText = '有未保存改动'
  }

  private isAspectActive(mode: RuntimeAspectMode): boolean {
    return this.draftProfile.aspectMode === mode
  }

  private onAspectModeChange(mode: RuntimeAspectMode): void {
    const nextProfile = this.cloneProfile()
    nextProfile.aspectMode = mode
    this.draftProfile = nextProfile
    this.statusText = '有未保存改动'
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        LogHelper.error('ShaderPreviewPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('ShaderPreviewPage', 'Route', `pushUrl ${route} failed: ${err.message}`)
    })
  }

  private getPreviewBorderRadius(): number {
    return 6 + Math.round(this.draftProfile.curvature * 0.22)
  }

  private getPreviewScanlineOpacity(): number {
    if (this.draftProfile.scanlineIntensity <= 0) {
      return 0
    }
    return Math.min(0.42, 0.08 + this.draftProfile.scanlineIntensity * 0.0034)
  }

  private getPreviewScanlineSpacing(): number {
    if (this.draftProfile.scanlineIntensity >= 70) {
      return 1
    }
    if (this.draftProfile.scanlineIntensity >= 35) {
      return 2
    }
    return 3
  }

  private getPreviewSaturationFactor(): number {
    return Math.max(0, this.draftProfile.saturation / 100)
  }

  private getPreviewBars(): number[] {
    return [
      10 + Math.round(this.draftProfile.scanlineIntensity * 0.34),
      10 + Math.round(this.draftProfile.curvature * 0.34),
      10 + Math.round(this.draftProfile.saturation * 0.17)
    ]
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
        .saturate(processed ? this.getPreviewSaturationFactor() : 1)

      if (processed && this.draftProfile.scanlineIntensity > 0) {
        ScanlineBackground({
          lineColor: '#2400FF41',
          lineSpacing: this.getPreviewScanlineSpacing(),
          alternateColor: '#0F000000'
        })
          .width('100%')
          .height('100%')
          .opacity(this.getPreviewScanlineOpacity())
          .hitTestBehavior(HitTestMode.None)
      }

      Column({ space: 10 }) {
        Text(title)
          .fontSize(11)
                    .fontColor(processed ? '#00131313' : EmuColors.onSurfaceVariant)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(1.8)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(processed ? EmuColors.primary : '#CC000000')
        Text(processed ? `${mode} / 保存后返回运行页生效` : mode)
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
    .borderRadius(processed ? this.getPreviewBorderRadius() : 6)
    .clip(true)
  }

  @Builder
  private SplitPreview() {
    Stack() {
      Row({ space: 1 }) {
        this.PreviewPane('原始画面', '原始输出', false)
        this.PreviewPane('滤镜预览', '运行页效果', true)
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
  private AspectModeControl() {
    Row({ space: 0 }) {
      ForEach(this.aspectOptions, (item: ShaderAspectOptionItem) => {
        Row() {
          Text(item.label)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isAspectActive(item.key) ? EmuColors.onSurface : '#B3ABABAB')
        }
        .layoutWeight(1)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(
          this.isAspectActive(item.key) ? EmuColors.surfaceContainerHighest : EmuColors.surfaceContainerHigh
        )
        .onClick(() => {
          this.onAspectModeChange(item.key)
        })
      }, (item: ShaderAspectOptionItem) => item.key)
    }
    .width('100%')
    .clip(true)
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

      Column({ space: 10 }) {
        Text('显示比例 display_aspect')
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurfaceVariant)
        this.AspectModeControl()
      }
      .width('100%')

      Text(`显示比例 ${describeRuntimeAspectMode(this.draftProfile.aspectMode)} · 保存后返回运行页按该配置渲染`)
        .fontSize(9)
        .fontColor(EmuColors.onSurfaceVariant)
        .width('100%')

      ShaderSliderRow({
        label: '扫描线强度',
        value: this.draftProfile.scanlineIntensity,
        suffix: '%',
        min: 0,
        max: 100,
        onChange: this.onScanlineIntensityChange
      })
      ShaderSliderRow({
        label: 'CRT 曲率',
        value: this.draftProfile.curvature,
        suffix: '%',
        min: 0,
        max: 100,
        onChange: this.onCurvatureChange
      })
      ShaderSliderRow({
        label: '色彩饱和度',
        value: this.draftProfile.saturation,
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
  private PreviewStatsOverlay() {
    Column({ space: 12 }) {
      Row() {
        Text('显示比例')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text(describeRuntimeAspectMode(this.draftProfile.aspectMode))
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
        Text('运行页应用')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.4)
        Text('扫描线 / 曲率 / 饱和度')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 3 }) {
        ForEach(this.getPreviewBars(), (heightValue: number) => {
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
