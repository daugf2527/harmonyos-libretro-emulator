import { common } from '@kit.AbilityKit'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuButton, EmuButtonKind, EmuButtonSize, EmuButtonShape } from '../components/EmuButton'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { BarChartBackground, BarChartItem, EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { loadInputLayoutProfile } from '../common/InputLayoutRepository'
import { runtimeRenderSettingsController } from '../common/RuntimeRenderSettingsController'
import {
  createDefaultRuntimeRenderSettingsProfile,
  describeRenderMode,
  describeSoftwareResolutionPreset,
  loadRuntimeRenderSettingsProfile,
  RuntimeRenderSettingsProfile,
  saveRuntimeRenderSettingsProfile
} from '../common/RuntimeRenderSettingsRepository'
import {
  createDefaultRuntimeInputPreferencesProfile,
  loadRuntimeInputPreferencesProfile,
  RuntimeInputPreferencesProfile,
  saveRuntimeInputPreferencesProfile
} from '../common/RuntimeInputPreferencesRepository'
import {
  getLibraryTelemetryBars,
  getLibraryTelemetryCells,
  LibraryTelemetryBar,
  LibraryTelemetryCell
} from '../common/LibraryRuntimeTelemetryPresenter'
import { LibraryRecord, loadAllLibraryRecords } from '../common/LibraryRepository'
import { InputDeviceInfo } from '../common/InputPortRouting'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'

interface SettingOptionItem {
  key: string
  label: string
  isActive: boolean
}

interface SoftwareResolutionPreset {
  width: number
  height: number
}

@Component
struct LinearSettingRow {
  @Prop label: string = ''
  @Prop code: string = ''
  @Prop value: number = 0
  @Prop min: number = 0
  @Prop max: number = 100
  onChange?: (value: number) => void

  build() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 4 }) {
          Text(this.label)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#C8ABABAB')

          Text(this.code)
            .fontSize(9)
            .fontColor('#77666666')
        }
        .alignItems(VerticalAlign.Bottom)

        Text(`${this.value}%`)
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 6 }) {
        Slider({
          value: this.value,
          min: this.min,
          max: this.max,
          step: 1
        })
          .width('100%')
          .blockColor(EmuColors.onSurface)
          .trackColor('#66757575')
          .selectedColor(EmuColors.primary)
          .showSteps(false)
          .showTips(false)
          .onChange((next: number) => {
            const clamped = Math.max(this.min, Math.min(this.max, Math.round(next)))
            this.onChange?.(clamped)
          })

        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#26333333')
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Entry
@Component
struct SettingsPage {
  @State private activeTab: string = 'basic'
  @State private aspectMode: string = '4:3'
  @State private scanlineIntensity: number = 64
  @State private masterVolume: number = 80
  @State private inputDeviceStatus: string = '正在读取'
  @State private inputLayoutSummaryText: string = '正在读取布局信息'
  @State private inputLayoutDetailText: string = '正在读取本地触控布局'
  @State private telemetryPrimaryLabel: string = '最近一次运行'
  @State private telemetryPrimaryValue: string = '--'
  @State private telemetrySecondaryLabel: string = '音频缓冲'
  @State private telemetrySecondaryValue: string = '--'
  @State private telemetryFooterLeft: string = '尚无运行记录'
  @State private telemetryFooterRight: string = '进入游戏后会更新摘要'
  @State private telemetryBars: BarChartItem[] = this.createEmptyTelemetryBars()
  @State private renderProfile: RuntimeRenderSettingsProfile = createDefaultRuntimeRenderSettingsProfile()
  @State private inputPreferences: RuntimeInputPreferencesProfile = createDefaultRuntimeInputPreferencesProfile()
  @State private advancedStatusText: string = '运行时设置尚未读取'
  @State private runtimeApplyStatusText: string = '尚未执行运行时写入'
  private pageActive: boolean = false
  private refreshToken: number = 0

  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')

  private readonly aspectOptions: SettingOptionItem[] = [
    { key: '4:3', label: '4:3', isActive: true },
    { key: '16:9', label: '16:9', isActive: false },
    { key: 'native', label: 'NATIVE', isActive: false }
  ]

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      console.error(`[SettingsPage] replaceUrl ${route} failed: ${err.message}`)
    })
  }

  private openPage(url: string, label: string): void {
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((err: Error) => {
      console.error(`[SettingsPage] pushUrl ${label} failed: ${err.message}`)
    })
  }

  private isBasicTab(): boolean {
    return this.activeTab === 'basic'
  }

  private isAspectActive(key: string): boolean {
    return this.aspectMode === key
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(100, Math.round(value)))
  }

  private onScanlineIntensityChange = (value: number): void => {
    this.scanlineIntensity = this.clampPercent(value)
  }

  private onMasterVolumeChange = (value: number): void => {
    this.masterVolume = this.clampPercent(value)
  }

  private get gpuBackendText(): string {
    return this.renderProfile.hwRenderAllowed ? '已允许硬件渲染' : '仅软件路径'
  }

  private get renderModeText(): string {
    const modeText = describeRenderMode(this.renderProfile.scalingMode)
    if (this.renderProfile.scalingMode === 1) {
      return `${modeText} · ${describeSoftwareResolutionPreset(this.renderProfile.softwareMaxPresetIndex)}`
    }
    return modeText
  }

  private get softwareResolutionText(): string {
    return describeSoftwareResolutionPreset(this.renderProfile.softwareMaxPresetIndex)
  }

  private get audioBufferSummaryText(): string {
    const bufferValue = this.telemetrySecondaryValue && this.telemetrySecondaryValue !== '--' ?
      this.telemetrySecondaryValue :
      '暂无记录'
    const footer = this.telemetryFooterRight.length > 0 ? this.telemetryFooterRight : '进入游戏后会更新摘要'
    return `${bufferValue} · ${footer}`
  }

  private get shaderModeSummaryText(): string {
    return '仅打开本地滤镜预览，不会写入当前运行时 shader preset'
  }

  private cloneRenderProfile(): RuntimeRenderSettingsProfile {
    return {
      version: this.renderProfile.version,
      scalingMode: this.renderProfile.scalingMode,
      softwareMaxPresetIndex: this.renderProfile.softwareMaxPresetIndex,
      hwRenderAllowed: this.renderProfile.hwRenderAllowed,
      updatedAt: this.renderProfile.updatedAt
    }
  }

  aboutToAppear(): void {
    this.pageActive = true
    void this.refreshPageData()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.refreshToken += 1
  }

  private beginRefresh(): number {
    this.refreshToken += 1
    return this.refreshToken
  }

  private isCurrentRefresh(token: number): boolean {
    return this.pageActive && token === this.refreshToken
  }

  private async refreshPageData(): Promise<void> {
    const token = this.beginRefresh()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.inputDeviceStatus = '上下文不可用'
      this.inputLayoutSummaryText = '无法读取布局信息'
      this.inputLayoutDetailText = '请重新进入页面'
      this.renderProfile = createDefaultRuntimeRenderSettingsProfile()
      this.inputPreferences = createDefaultRuntimeInputPreferencesProfile()
      this.advancedStatusText = '上下文不可用'
      this.applyEmptyTelemetry()
      return
    }

    const renderProfile = await loadRuntimeRenderSettingsProfile(context)
    if (!this.isCurrentRefresh(token)) {
      return
    }
    this.renderProfile = renderProfile
    const inputPreferences = await loadRuntimeInputPreferencesProfile(context)
    if (!this.isCurrentRefresh(token)) {
      return
    }
    this.inputPreferences = inputPreferences
    this.refreshAdvancedStatus()

    const inputDevices: InputDeviceInfo[] = runtimeInputPortController.listInputDevices()
    const externalNames: string[] = []
    inputDevices.forEach((item: InputDeviceInfo) => {
      const label = `${item.name}`.trim()
      if (label.length > 0) {
        externalNames.push(label)
      }
    })

    if (!this.isCurrentRefresh(token)) {
      return
    }

    this.inputDeviceStatus = externalNames.length > 0 ? `已连接 ${externalNames.length} 个设备` : '仅本地触控'

    try {
      const profile = await loadInputLayoutProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputLayoutSummaryText = `本地触控布局 · ${profile.buttons.length} 个按键`
      this.inputLayoutDetailText = externalNames.length > 0 ?
        `外接设备：${externalNames.join(' / ')}` :
        '未检测到外接手柄，当前使用本地触控方案'
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputLayoutSummaryText = '本地触控布局'
      this.inputLayoutDetailText = '布局读取失败，已回退默认布局'
    }

    try {
      const records = await loadAllLibraryRecords(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.applyTelemetry(records)
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.applyEmptyTelemetry()
    }
  }

  private refreshAdvancedStatus(): void {
    const backendText = this.renderProfile.hwRenderAllowed ? 'HW_RENDER 已允许' : 'HW_RENDER 已关闭'
    const softwareText = this.renderProfile.scalingMode === 1 ?
      ` / 软件分辨率上限 ${this.softwareResolutionText}` :
      ''
    this.advancedStatusText = `${backendText} / ${describeRenderMode(this.renderProfile.scalingMode)}${softwareText}`
  }

  private async persistRenderProfile(profile: RuntimeRenderSettingsProfile): Promise<void> {
    const token = this.beginRefresh()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    const savedProfile = await saveRuntimeRenderSettingsProfile(context, profile)
    if (!this.isCurrentRefresh(token)) {
      return
    }
    this.renderProfile = savedProfile
    this.refreshAdvancedStatus()
  }

  private setRuntimeApplyStatus(actionLabel: string, ok: boolean): void {
    this.runtimeApplyStatusText = ok ?
      `${actionLabel} 已写入运行时` :
      `${actionLabel} 写入失败，当前页未更新运行时状态`
  }

  private async toggleHwRenderAllowed(): Promise<void> {
    const nextValue = !this.renderProfile.hwRenderAllowed
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.hwRenderAllowed = nextValue
    const ok = runtimeRenderSettingsController.setHwRenderAllowed(nextValue)
    this.setRuntimeApplyStatus('GPU Backend', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private async toggleHideVirtualController(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.setRuntimeApplyStatus('虚拟手柄显示', false)
      return
    }
    const nextProfile: RuntimeInputPreferencesProfile = {
      version: this.inputPreferences.version,
      hideVirtualController: !this.inputPreferences.hideVirtualController,
      hideUndeclaredKeys: this.inputPreferences.hideUndeclaredKeys,
      updatedAt: this.inputPreferences.updatedAt
    }
    try {
      const saved = await saveRuntimeInputPreferencesProfile(context, nextProfile)
      this.inputPreferences = saved
      this.setRuntimeApplyStatus('虚拟手柄显示', true)
    } catch (_err) {
      this.setRuntimeApplyStatus('虚拟手柄显示', false)    }
  }

  private async toggleHideUndeclaredKeys(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.setRuntimeApplyStatus('按 core 隐藏未声明键', false)
      return
    }
    const nextProfile: RuntimeInputPreferencesProfile = {
      version: this.inputPreferences.version,
      hideVirtualController: this.inputPreferences.hideVirtualController,
      hideUndeclaredKeys: !this.inputPreferences.hideUndeclaredKeys,
      updatedAt: this.inputPreferences.updatedAt
    }
    try {
      const saved = await saveRuntimeInputPreferencesProfile(context, nextProfile)
      this.inputPreferences = saved
      this.setRuntimeApplyStatus('按 core 隐藏未声明键', true)
    } catch (_err) {
      this.setRuntimeApplyStatus('按 core 隐藏未声明键', false)
    }
  }

  private async cycleRenderMode(): Promise<void> {
    const nextMode = (this.renderProfile.scalingMode + 1) % 3
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.scalingMode = nextMode
    const okMode = runtimeRenderSettingsController.setScalingMode(nextMode)
    let okResolution = true
    if (nextMode === 1) {
      const resolution = this.getSoftwareResolutionForPreset(nextProfile.softwareMaxPresetIndex)
      okResolution = runtimeRenderSettingsController.setSoftwareMaxResolution(resolution.width, resolution.height)
    }
    const ok = okMode && okResolution
    this.setRuntimeApplyStatus('缩放 / 呈现模式', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private async cycleSoftwareResolutionPreset(): Promise<void> {
    const nextPreset = (this.renderProfile.softwareMaxPresetIndex + 1) % 3
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.scalingMode = 1
    nextProfile.softwareMaxPresetIndex = nextPreset
    const resolution = this.getSoftwareResolutionForPreset(nextPreset)
    const okMode = runtimeRenderSettingsController.setScalingMode(1)
    const okResolution = runtimeRenderSettingsController.setSoftwareMaxResolution(
      resolution.width,
      resolution.height
    )
    const ok = okMode && okResolution
    this.setRuntimeApplyStatus('软件分辨率上限', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private getSoftwareResolutionForPreset(index: number): SoftwareResolutionPreset {
    if (index === 0) {
      return { width: 640, height: 480 }
    }
    if (index === 2) {
      return { width: 1920, height: 1080 }
    }
    return { width: 1280, height: 720 }
  }

  private createEmptyTelemetryBars(): BarChartItem[] {
    return [
      { height: 8, isPrimary: false },
      { height: 8, isPrimary: false },
      { height: 8, isPrimary: false },
      { height: 8, isPrimary: false }
    ]
  }

  private applyEmptyTelemetry(): void {
    this.telemetryPrimaryLabel = '最近一次运行'
    this.telemetryPrimaryValue = '--'
    this.telemetrySecondaryLabel = '音频缓冲'
    this.telemetrySecondaryValue = '--'
    this.telemetryFooterLeft = '尚无运行记录'
    this.telemetryFooterRight = '进入游戏后会更新摘要'
    this.telemetryBars = this.createEmptyTelemetryBars()
  }

  private applyTelemetry(records: LibraryRecord[]): void {
    const telemetryCells: LibraryTelemetryCell[] = getLibraryTelemetryCells(records)
    const telemetryBars: LibraryTelemetryBar[] = getLibraryTelemetryBars(records)
    this.telemetryPrimaryLabel = telemetryCells[0]?.label ?? '最近一次运行'
    this.telemetryPrimaryValue = telemetryCells[1]?.value ?? '--.-'
    this.telemetrySecondaryLabel = telemetryCells[2]?.label ?? '音频缓冲'
    this.telemetrySecondaryValue = telemetryCells[2]?.value ?? '--'
    this.telemetryFooterLeft = telemetryCells[0]?.value === 'NO DATA' ? '尚无运行记录' : `会话状态：${telemetryCells[0]?.value ?? 'LAST RUN'}`
    this.telemetryFooterRight = telemetryCells[1]?.value && telemetryCells[1]?.value !== '--.-' ?
      `最近 FPS：${telemetryCells[1].value}` :
      '运行后将生成性能摘要'
    if (telemetryBars.length === 0) {
      this.telemetryBars = this.createEmptyTelemetryBars()
      return
    }
    const mappedBars: BarChartItem[] = telemetryBars.map((item: LibraryTelemetryBar): BarChartItem => {
      const nextBar: BarChartItem = {
        height: item.height * 3.5,
        isPrimary: item.color !== '#22484848'
      }
      return nextBar
    })
    this.telemetryBars = mappedBars
  }

  @Builder
  private TabHeader() {
    Row() {
      this.TabItem('basic', '基础设置', 'BASIC')
      this.TabItem('advanced', '高级设置', 'ADVANCED')
    }
    .width('100%')
    .height(84)
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
  }

  @Builder
  private TabItem(key: string, title: string, code: string) {
    Stack() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(EmuTypography.lg)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.activeTab === key ? EmuColors.onSurface : '#88757575')

        Text(code)
          .fontSize(EmuTypography.xs)
                    .fontWeight(FontWeight.Bold)
          .fontColor(this.activeTab === key ? '#B3ABABAB' : '#666666')
          .letterSpacing(1.8)
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .height('100%')

      if (this.activeTab === key) {
        Row()
          .width('100%')
          .height(2)
          .backgroundColor(EmuColors.primary)
          .align(Alignment.Bottom)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .onClick(() => {
      this.activeTab = key
    })
  }

  @Builder
  private SectionTitle(title: string, code: string) {
    Row({ space: 8 }) {
      Row()
        .width(3)
        .height(18)
        .backgroundColor(EmuColors.primary)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)

      Text(code)
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
                .fontColor('#88757575')
        .letterSpacing(1.2)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SegmentedAspectControl() {
    Row({ space: 0 }) {
      ForEach(this.aspectOptions, (item: SettingOptionItem) => {
        Row() {
          Text(item.label)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isAspectActive(item.key) ? EmuColors.onSurface : '#B3ABABAB')
        }
        .layoutWeight(1)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.isAspectActive(item.key) ? EmuColors.surfaceContainerHighest : EmuColors.surfaceContainerHigh)
        .onClick(() => {
          this.aspectMode = item.key
        })
      }, (item: SettingOptionItem) => item.key)
    }
    .width('100%')
    .clip(true)
  }

  @Builder
  private LinearSettingBlock(
    label: string,
    code: string,
    value: number,
    onChange: (value: number) => void
  ) {
    LinearSettingRow({
      label: label,
      code: code,
      value: value,
      min: 0,
      max: 100,
      onChange: onChange
    })
  }

  @Builder
  private LinearSetting(
    label: string,
    code: string,
    value: number,
    onChange: (value: number) => void
  ) {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 4 }) {
          Text(label)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#C8ABABAB')

          Text(code)
            .fontSize(9)
                        .fontColor('#77666666')
        }
        .alignItems(VerticalAlign.Bottom)

        Text(`${value}%`)
          .fontSize(EmuTypography.sm)
                    .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 6 }) {
        Slider({
          value: value,
          min: 0,
          max: 100,
          step: 1
        })
          .width('100%')
          .blockColor(EmuColors.onSurface)
          .trackColor('#66757575')
          .selectedColor(EmuColors.primary)
          .showSteps(false)
          .showTips(false)
          .onChange(onChange)

        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#26333333')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private InputDeviceCard() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 6 }) {
          Text('本地触控手柄')
            .fontSize(EmuTypography.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)

          Text(this.inputLayoutSummaryText)
            .fontSize(EmuTypography.xs)
                        .fontColor('#B3ABABAB')
        }
        .alignItems(HorizontalAlign.Start)

        Text(this.inputDeviceStatus)
          .fontSize(EmuTypography.xs)
                    .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .border({ width: 0.5, color: '#6600FF41', style: BorderStyle.Solid })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        EmuPrecisionGridBackdrop()
          .opacity(0.42)

        Row({ space: 8 }) {
          Row()
            .width(7)
            .height(7)
            .borderRadius(3.5)
            .backgroundColor(EmuColors.primary)

          Text('L: 左肩键')
            .fontSize(EmuTypography.xs)
                        .fontColor('#B3ABABAB')

          Text('R: 右肩键')
            .fontSize(EmuTypography.xs)
                        .fontColor('#B3ABABAB')
        }
        .align(Alignment.TopStart)
        .margin({ left: 24, top: 24 })

        Row({ space: 18 }) {
          this.ControllerDot(18)
          this.ControllerDot(28)
          this.ControllerDot(18)
        }
        .align(Alignment.Center)
      }
      .width('100%')
      .height(190)
      .backgroundColor('#0B0B0B')
      .clip(true)

      Text(this.inputLayoutDetailText)
        .fontSize(EmuTypography.xs)
                .fontColor('#88757575')
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private ControllerDot(size: number) {
    Row()
      .width(size)
      .height(size)
      .borderRadius(size / 2)
      .backgroundColor('#B3E5E5E5')
      .shadow({ radius: 18, color: '#66808080', offsetX: 0, offsetY: 0 })
  }

  @Builder
  private TelemetryPanel() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 8 }) {
          Text(this.telemetryPrimaryLabel)
            .fontSize(EmuTypography.xs)
                        .fontColor('#B3ABABAB')
          Text(this.telemetryPrimaryValue)
            .fontSize(24)
                        .fontColor(EmuColors.primary)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Text(this.telemetrySecondaryLabel)
            .fontSize(EmuTypography.xs)
                        .fontColor('#B3ABABAB')
          Text(this.telemetrySecondaryValue)
            .fontSize(EmuTypography.xxl)
                        .fontColor(EmuColors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      BarChartBackground({
        bars: this.telemetryBars,
        primaryColor: EmuColors.primary,
        secondaryColor: EmuColors.primary,
        barGap: 7
      })
        .height(92)
        .width('100%')

      Row() {
        Text(this.telemetryFooterLeft)
          .fontSize(9)
                    .fontColor('#88757575')
        Text(this.telemetryFooterRight)
          .fontSize(9)
                    .fontColor('#88757575')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 18 })
    .backgroundColor('#050505')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private AdvancedActionButton(label: string, onClick: () => void) {
    EmuButton({
      label: label,
      kind: EmuButtonKind.SECONDARY,
      buttonSize: EmuButtonSize.MD,
      shape: EmuButtonShape.PILL,
      accent: 'primary',
      onTap: () => { onClick() }
    })
  }

  @Builder
  private AdvancedControlsCard() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        this.AdvancedActionButton(
          this.renderProfile.hwRenderAllowed ? '关闭硬件渲染' : '开启硬件渲染',
          () => {
            void this.toggleHwRenderAllowed()
          }
        )
        this.AdvancedActionButton('切换缩放模式', () => {
          void this.cycleRenderMode()
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.AdvancedActionButton('切换软件分辨率上限', () => {
          void this.cycleSoftwareResolutionPreset()
        })
        this.AdvancedActionButton('打开滤镜预览', () => {
          this.openPage('pages/ShaderPreviewPage', '滤镜预览')
        })
      }
      .width('100%')

      Text('当前页会把 GPU Backend、缩放/呈现模式与软件分辨率上限写入运行时；Audio Buffer 为运行期只读摘要，滤镜预览不会写入 shader preset。')
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private AdvancedSettingRow(
    label: string,
    value: string,
    actionLabel?: string,
    onClick?: () => void
  ) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(label)
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.onSurface)
        Text(value)
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (actionLabel && onClick) {
        EmuButton({
          label: actionLabel,
          kind: EmuButtonKind.SECONDARY,
          buttonSize: EmuButtonSize.SM,
          shape: EmuButtonShape.PILL,
          accent: 'primary',
          onTap: () => { onClick() }
        })
      } else {
        Text('只读')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.primary)
      }
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
  }

  @Builder
  private BasicSettings() {
    Column({ space: 34 }) {
      Column({ space: 18 }) {
        this.SectionTitle('画面设置', 'VIDEO_PROCESSING')

        Column({ space: 12 }) {
          Text('画面比例 aspect_ratio')
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#9AABABAB')
          this.SegmentedAspectControl()
        }
        .width('100%')

        this.LinearSettingBlock('CRT 复古扫描线强度', 'scanline_intensity', this.scanlineIntensity, this.onScanlineIntensityChange)
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('输入设备', 'INPUT_INTERFACE')
        this.InputDeviceCard()
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('音频音量', 'AUDIO_VOLUME')
        this.LinearSettingBlock('主音量', 'master_volume', this.masterVolume, this.onMasterVolumeChange)
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('最近一次运行摘要', 'LAST_RUNTIME')
        this.TelemetryPanel()
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private AdvancedSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('高级设置', 'ADVANCED_RUNTIME')
      this.AdvancedControlsCard()
      this.AdvancedSettingRow(
        '虚拟手柄显示',
        this.inputPreferences.hideVirtualController ? '当前隐藏 · 运行时不渲染屏上手柄' : '当前显示 · 运行时叠加屏上手柄',
        this.inputPreferences.hideVirtualController ? '显示' : '隐藏',
        () => {
          void this.toggleHideVirtualController()
        }
      )
      this.AdvancedSettingRow(
        '按 core 隐藏未声明键',
        this.inputPreferences.hideUndeclaredKeys ? '当前开启 · 仅显示当前 core 声明使用的按键' : '当前关闭 · 显示完整虚拟手柄按键集',
        this.inputPreferences.hideUndeclaredKeys ? '关闭' : '开启',
        () => {
          void this.toggleHideUndeclaredKeys()
        }
      )
      this.AdvancedSettingRow(
        'GPU Backend',
        this.gpuBackendText,
        this.renderProfile.hwRenderAllowed ? '关闭' : '开启',
        () => {
          void this.toggleHwRenderAllowed()
        }
      )
      this.AdvancedSettingRow(
        'Scaling / Render Mode',
        `${this.renderModeText} · 当前项真实映射到 scalingMode`,
        '切换',
        () => {
          void this.cycleRenderMode()
        }
      )
      this.AdvancedSettingRow(
        'Software Resolution',
        `${this.softwareResolutionText} · 仅软件渲染路径会使用该上限`,
        '切换',
        () => {
          void this.cycleSoftwareResolutionPreset()
        }
      )
      this.AdvancedSettingRow('Audio Buffer', `最近一次运行摘要 · ${this.audioBufferSummaryText}`)
      this.AdvancedSettingRow(
        'Shader Mode',
        this.shaderModeSummaryText,
        '预览',
        () => {
          this.openPage('pages/ShaderPreviewPage', '滤镜预览')
        }
      )
      this.AdvancedSettingRow('当前运行时状态', this.advancedStatusText)
      this.AdvancedSettingRow('最近一次应用', this.runtimeApplyStatusText)
      this.NavigationRow('Input / Netplay Center', '手柄与联机', 'pages/MultiplayerInputPage')
      this.NavigationRow('Input Layout Editor', '触控布局', 'pages/InputLayoutPage')
      this.NavigationRow('Core / Firmware Manager', 'Core 与固件', 'pages/CoreManagerPage')
      this.NavigationRow('滤镜预览', '画面滤镜预览', 'pages/ShaderPreviewPage')
      this.NavigationRow('About / Help', '关于与帮助', 'pages/AboutHelpPage')
    }
    .width('100%')
  }

  @Builder
  private NavigationRow(label: string, value: string, url: string) {
    Row() {
      Column({ space: 4 }) {
        Text(label)
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.onSurface)
        Text(value)
          .fontSize(9)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(EmuTypography.xxl)
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
    .onClick(() => {
      this.openPage(url, label)
    })
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: '碳影 / Carbon Shade',
        titleIcon: 'terminal',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 20
      })

      Scroll() {
        Column({ space: 34 }) {
          this.TabHeader()
          if (this.isBasicTab()) {
            this.BasicSettings()
          } else {
            this.AdvancedSettings()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 460 })
        .padding({ left: 24, right: 24, bottom: 34 })
      }
      .layoutWeight(1)
      .width('100%')

      EmuBottomNav({
        items: this.navItems,
        activeFontColor: EmuColors.primary,
        inactiveFontColor: '#FF666666',
        indicatorStyle: 'line',
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
