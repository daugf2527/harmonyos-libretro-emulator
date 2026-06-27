import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuButton, EmuButtonKind, EmuButtonSize, EmuButtonShape } from '../components/EmuButton'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { loadInputLayoutProfile } from '../common/InputLayoutRepository'
import { runtimeRenderSettingsController } from '../common/RuntimeRenderSettingsController'
import LogHelper from '../common/LogHelper'
import {
  createDefaultRuntimeRenderSettingsProfile,
  describeRenderMode,
  describeSoftwareResolutionPreset,
  loadRuntimeRenderSettingsProfile,
  RuntimeRenderSettingsProfile,
  saveRuntimeRenderSettingsProfile
} from '../common/RuntimeRenderSettingsRepository'
import {
  AUDIO_LATENCY_PRESETS,
  createDefaultRuntimeAudioSettingsProfile,
  describeAudioLatency,
  getAudioLatencyForPreset,
  getAudioLatencyPresetIndex,
  loadRuntimeAudioSettingsProfile,
  RuntimeAudioSettingsProfile,
  saveRuntimeAudioSettingsProfile
} from '../common/RuntimeAudioSettingsRepository'
import { runtimeAudioSettingsController } from '../common/RuntimeAudioSettingsController'
import {
  createDefaultRuntimeInputPreferencesProfile,
  loadRuntimeInputPreferencesProfile,
  RuntimeInputPreferencesProfile,
  saveRuntimeInputPreferencesProfile
} from '../common/RuntimeInputPreferencesRepository'
import {
  formatLastPlayedRelative,
  getLastPlayedLibraryRecord,
  getLibraryTelemetryCells,
  LibraryTelemetryCell
} from '../common/LibraryRuntimeTelemetryPresenter'
import { LibraryRecord, loadAllLibraryRecords } from '../common/LibraryRepository'
import { InputDeviceInfo } from '../common/InputPortRouting'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'
import { getInputMappingService, InputMappingStatusSnapshot } from '../common/InputMappingService'
import {
  createDefaultRuntimeVisualSettingsProfile,
  describeRuntimeAspectMode,
  loadRuntimeVisualSettingsProfile,
  RuntimeVisualSettingsProfile,
  saveRuntimeVisualSettingsProfile
} from '../common/RuntimeVisualSettingsRepository'

interface SettingOptionItem {
  key: string
  label: string
  isActive: boolean
}

interface SoftwareResolutionPreset {
  width: number
  height: number
}

@ComponentV2
struct LinearSettingRow {
  @Param label: string = ''
  @Param code: string = ''
  @Param value: number = 0
  @Param min: number = 0
  @Param max: number = 100
  @Event onChange?: (value: number) => void

  build() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 4 }) {
          Text(this.label)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#C8ABABAB')

          if (this.code.length > 0) {
            Text(this.code)
              .fontSize(9)
              .fontColor('#77666666')
          }
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

// 折叠态枚举
enum FoldableMode {
  SINGLE = 'single',  // 单折态（F态）
  DUAL = 'dual',      // 双折态（M态）
  TRIPLE = 'triple'   // 三折态（G态）
}

// 设置分组
interface SettingGroup {
  id: string
  label: string
  icon: string
}

@Entry
@ComponentV2
struct SettingsPage {
  @Local private activeTab: string = 'basic'
  @Local private inputDeviceStatus: string = '正在读取'
  @Local private inputLayoutSummaryText: string = '正在读取布局信息'
  @Local private inputLayoutDetailText: string = '正在读取本地触控布局'
  @Local private inputMappingSummaryText: string = '正在读取键盘映射'
  @Local private inputMappingDetailText: string = '应用启动后会读取本地键盘映射配置'
  @Local private telemetryPrimaryLabel: string = '最近一次记录'
  @Local private telemetryPrimaryValue: string = '--'
  @Local private telemetrySecondaryLabel: string = '音频缓冲'
  @Local private telemetrySecondaryValue: string = '--'
  @Local private telemetryFooterLeft: string = '尚无运行记录'
  @Local private telemetryFooterRight: string = '进入游戏后会生成历史摘要'
  @Local private telemetryReady: boolean = false
  @Local private renderProfile: RuntimeRenderSettingsProfile = createDefaultRuntimeRenderSettingsProfile()
  @Local private audioProfile: RuntimeAudioSettingsProfile = createDefaultRuntimeAudioSettingsProfile()
  @Local private inputPreferences: RuntimeInputPreferencesProfile = createDefaultRuntimeInputPreferencesProfile()
  @Local private visualProfile: RuntimeVisualSettingsProfile = createDefaultRuntimeVisualSettingsProfile()
  @Local private runtimeProfilesReady: boolean = false
  @Local private advancedStatusText: string = '正在读取运行时设置'
  @Local private runtimeApplyStatusText: string = '尚未执行运行时写入'
  @Local private foldableMode: FoldableMode = FoldableMode.SINGLE
  @Local private activeGroup: string = 'video'  // 当前选中的设置分组
  private pageActive: boolean = false
  private refreshToken: number = 0
  private visualPersistTimer: number = -1
  private audioPersistTimer: number = -1
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    if (!this.pageActive) {
      return
    }
    this.updateFoldableMode(data)
  }

  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')

  private readonly settingGroups: SettingGroup[] = [
    { id: 'video', label: '画面设置', icon: '🎮' },
    { id: 'audio', label: '音频音量', icon: '🔊' },
    { id: 'input', label: '输入设备', icon: '🎯' },
    { id: 'system', label: '系统信息', icon: '📊' }
  ]

  private readonly aspectOptions: SettingOptionItem[] = [
    { key: '4:3', label: '4:3', isActive: true },
    { key: '16:9', label: '16:9', isActive: false },
    { key: 'native', label: '原始比例', isActive: false }
  ]

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('SettingsPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.advancedStatusText = '现在还回不到其他设置页，请稍后再试'
    })
  }

  private openPage(url: string, label: string): void {
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((err: Error) => {
      LogHelper.error('SettingsPage', 'Route', `pushUrl ${label} failed: ${err.message}`)
      this.advancedStatusText = `${label}现在还打不开，请稍后再试`
    })
  }

  private isBasicTab(): boolean {
    return this.activeTab === 'basic'
  }

  private isAspectActive(key: string): boolean {
    if (!this.runtimeProfilesReady) {
      return false
    }
    return this.visualProfile.aspectMode === key
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(100, Math.round(value)))
  }

  private onScanlineIntensityChange = (value: number): void => {
    if (!this.runtimeProfilesReady) {
      this.runtimeApplyStatusText = '当前视觉配置没有读到，请先重试'
      return
    }
    const nextProfile = this.cloneVisualProfile()
    nextProfile.scanlineIntensity = this.clampPercent(value)
    this.scheduleVisualProfilePersist(nextProfile, '扫描线强度')
  }

  private onMasterVolumeChange = (value: number): void => {
    if (!this.runtimeProfilesReady) {
      this.runtimeApplyStatusText = '当前音频配置没有读到，请先重试'
      return
    }
    const nextPercent = this.clampPercent(value)
    this.scheduleAudioProfilePersist(nextPercent, '主音量')
  }

  private get gpuBackendText(): string {
    if (!this.runtimeProfilesReady) {
      return '渲染方式待确认'
    }
    return this.renderProfile.hwRenderAllowed ? '本地配置：允许硬件渲染' : '本地配置：仅软件路径'
  }

  private get renderModeText(): string {
    if (!this.runtimeProfilesReady) {
      return '渲染模式待确认'
    }
    const modeText = describeRenderMode(this.renderProfile.scalingMode)
    if (this.renderProfile.scalingMode === 1) {
      return `本地配置：${modeText} · ${describeSoftwareResolutionPreset(this.renderProfile.softwareMaxPresetIndex)}`
    }
    return `本地配置：${modeText}`
  }

  private get softwareResolutionText(): string {
    if (!this.runtimeProfilesReady) {
      return '分辨率待确认'
    }
    return describeSoftwareResolutionPreset(this.renderProfile.softwareMaxPresetIndex)
  }

  private get vsyncSummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return '垂直同步设置待确认'
    }
    return this.renderProfile.swapInterval === 0 ?
      '本地配置：关闭 · 允许非同步提交，可能减少等待但可能出现画面撕裂' :
      '本地配置：开启 · 跟随显示刷新提交，优先减少画面撕裂'
  }

  private get aiUpscaleSummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return 'AI 超分设置待确认'
    }
    return this.renderProfile.aiUpscaleEnabled ?
      '本地配置：开启 · 设备支持 XEngine 时启用 AI 超分' :
      '本地配置：关闭 · 保持原始分辨率输出，不支持设备可继续正常运行'
  }

  private get audioLatencySummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return '音频延迟待确认'
    }
    return `本地配置：${describeAudioLatency(this.audioProfile.latencyMs)}`
  }

  private get audioBufferSummaryText(): string {
    const bufferValue = this.telemetryReady && this.telemetrySecondaryValue && this.telemetrySecondaryValue !== '--' ?
      this.telemetrySecondaryValue :
      (this.telemetryReady ? '暂无记录' : '待确认')
    const footer = this.telemetryFooterRight.length > 0 ? this.telemetryFooterRight : '进入游戏后会生成历史摘要'
    return `${bufferValue} · ${footer}`
  }

  private get shaderModeSummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return '滤镜配置待确认'
    }
    return `本地配置：${describeRuntimeAspectMode(this.visualProfile.aspectMode)} · 扫描线 ${this.visualProfile.scanlineIntensity}% / 曲率 ${this.visualProfile.curvature}% / 饱和度 ${this.visualProfile.saturation}%`
  }

  private get hideVirtualControllerSummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return '屏上手柄显示设置待确认'
    }
    return this.inputPreferences.hideVirtualController ?
      '本地配置：隐藏 · 运行时不渲染屏上手柄' :
      '本地配置：显示 · 运行时叠加屏上手柄'
  }

  private get hideUndeclaredKeysSummaryText(): string {
    if (!this.runtimeProfilesReady) {
      return '按键显示范围待确认'
    }
    return this.inputPreferences.hideUndeclaredKeys ?
      '本地配置：开启 · 仅显示当前游戏实际会用到的按键' :
      '本地配置：关闭 · 显示完整虚拟手柄按键集'
  }

  private get runtimeProfilesUnavailableHintText(): string {
    return '当前运行配置还没有完整读到，请先重试后再修改'
  }

  private cloneRenderProfile(): RuntimeRenderSettingsProfile {
    return {
      version: this.renderProfile.version,
      scalingMode: this.renderProfile.scalingMode,
      swapInterval: this.renderProfile.swapInterval,
      softwareMaxPresetIndex: this.renderProfile.softwareMaxPresetIndex,
      aiUpscaleEnabled: this.renderProfile.aiUpscaleEnabled,
      hwRenderAllowed: this.renderProfile.hwRenderAllowed,
      updatedAt: this.renderProfile.updatedAt
    }
  }

  aboutToAppear(): void {
    this.pageActive = true
    this.detectFoldableMode()
    try {
      display.on('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('SettingsPage', 'Fold', `foldStatusChange on failed: ${err}`)
    }
    void this.refreshPageData()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.refreshToken += 1
    try {
      display.off('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('SettingsPage', 'Fold', `foldStatusChange off failed: ${err}`)
    }
  }

  private detectFoldableMode(): void {
    try {
      const foldStatus = display.getFoldStatus()
      this.updateFoldableMode(foldStatus)
    } catch (err) {
      LogHelper.error('SettingsPage', 'Fold', `获取折叠状态失败: ${err}`)
      this.foldableMode = FoldableMode.SINGLE
    }
  }

  private updateFoldableMode(foldStatus: display.FoldStatus): void {
    switch (foldStatus) {
      case display.FoldStatus.FOLD_STATUS_EXPANDED:
        this.foldableMode = FoldableMode.DUAL
        break
      case display.FoldStatus.FOLD_STATUS_FOLDED:
        this.foldableMode = FoldableMode.SINGLE
        break
      case display.FoldStatus.FOLD_STATUS_HALF_FOLDED:
        this.foldableMode = FoldableMode.TRIPLE
        break
      default:
        this.foldableMode = FoldableMode.SINGLE
    }
    LogHelper.info('SettingsPage', 'Fold', `折叠态切换: ${this.foldableMode}`)
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
      this.runtimeProfilesReady = false
      this.inputDeviceStatus = '现在还读不到本机设备状态，请稍后再试'
      this.inputLayoutSummaryText = '本地触控布局现在还没读到'
      this.inputLayoutDetailText = '本地触控布局信息暂时没有加载出来'
      this.applyInputMappingStatus(getInputMappingService().getStatusSnapshot())
      this.renderProfile = createDefaultRuntimeRenderSettingsProfile()
      this.inputPreferences = createDefaultRuntimeInputPreferencesProfile()
      this.visualProfile = createDefaultRuntimeVisualSettingsProfile()
      this.audioProfile = createDefaultRuntimeAudioSettingsProfile()
      this.advancedStatusText = '现在还读不到本地运行设置，请稍后再试'
      this.applyEmptyTelemetry()
      return
    }

    try {
      const renderProfile = await loadRuntimeRenderSettingsProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.renderProfile = renderProfile
      const audioProfile = await loadRuntimeAudioSettingsProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.audioProfile = audioProfile
      const visualProfile = await loadRuntimeVisualSettingsProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.visualProfile = visualProfile
      const inputPreferences = await loadRuntimeInputPreferencesProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputPreferences = inputPreferences
      this.runtimeProfilesReady = true
      this.refreshAdvancedStatus()
    } catch (err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SettingsPage', 'Settings', `读取运行时设置失败: ${message}`)
      this.renderProfile = createDefaultRuntimeRenderSettingsProfile()
      this.inputPreferences = createDefaultRuntimeInputPreferencesProfile()
      this.visualProfile = createDefaultRuntimeVisualSettingsProfile()
      this.audioProfile = createDefaultRuntimeAudioSettingsProfile()
      this.runtimeProfilesReady = false
      this.advancedStatusText = '运行时设置这次没有读出来，请先重试后再判断真实配置'
    }

    let externalNames: string[] = []
    let externalDeviceCount: number = 0
    let inputDevicesReady: boolean = true
    try {
      const inputDevices: InputDeviceInfo[] = runtimeInputPortController.listInputDevices()
      externalDeviceCount = inputDevices.length
      inputDevices.forEach((item: InputDeviceInfo) => {
        const label = `${item.name}`.trim()
        if (label.length > 0) {
          externalNames.push(label)
        }
      })
    } catch (err) {
      inputDevicesReady = false
      const message = (err as Error).message || String(err)
      LogHelper.error('SettingsPage', 'Input', `读取输入设备状态失败: ${message}`)
    }

    if (!this.isCurrentRefresh(token)) {
      return
    }

    this.inputDeviceStatus = inputDevicesReady ?
      (externalDeviceCount > 0 ? `已枚举 ${externalDeviceCount} 个外接设备` : '当前没有枚举到外接设备') :
      '本机输入设备没有读出来，请稍后重试'
    this.applyInputMappingStatus(getInputMappingService().getStatusSnapshot())

    try {
      const profile = await loadInputLayoutProfile(context)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputLayoutSummaryText = `本地触控布局 · ${profile.buttons.length} 个按键`
      this.inputLayoutDetailText = !inputDevicesReady ?
        '外接设备状态没有读出来，当前仅展示本地触控布局信息' :
        (externalNames.length > 0 ?
          `外接设备：${externalNames.join(' / ')}` :
          (externalDeviceCount > 0 ?
            `已枚举 ${externalDeviceCount} 个外接设备，但当前没有可展示的设备名称` :
            '当前没有枚举到外接设备，页面仅展示本地触控布局')))
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputLayoutSummaryText = '本地触控布局没有读到'
      this.inputLayoutDetailText = !inputDevicesReady ?
        '本地触控布局和外接设备状态都没有读出来，请稍后重试' :
        '本地触控布局没有读到，请稍后重试'
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
      this.telemetryReady = false
      this.telemetryFooterLeft = '本地运行记录没有读出来'
      this.telemetryFooterRight = '请稍后重试后再查看'
    }
  }

  private refreshAdvancedStatus(): void {
    if (!this.runtimeProfilesReady) {
      this.advancedStatusText = '当前运行设置还没完整读出来，请先重试后再判断真实配置'
      return
    }
    const backendText = this.renderProfile.hwRenderAllowed ? '本地配置里已开启硬件渲染' : '本地配置里已关闭硬件渲染'
    const softwareText = this.renderProfile.scalingMode === 1 ?
      ` / 软件分辨率上限 ${this.softwareResolutionText}` :
      ''
    const vsyncText = this.renderProfile.swapInterval === 0 ? '本地配置里已关闭垂直同步' : '本地配置里已开启垂直同步'
    const aiText = this.renderProfile.aiUpscaleEnabled ? '本地配置里已开启 AI 超分' : '本地配置里已关闭 AI 超分'
    this.advancedStatusText = `${backendText} / ${describeRenderMode(this.renderProfile.scalingMode)}${softwareText} / ${vsyncText} / ${aiText}`
  }

  private cloneVisualProfile(): RuntimeVisualSettingsProfile {
    return {
      version: this.visualProfile.version,
      aspectMode: this.visualProfile.aspectMode,
      scanlineIntensity: this.visualProfile.scanlineIntensity,
      curvature: this.visualProfile.curvature,
      saturation: this.visualProfile.saturation,
      updatedAt: this.visualProfile.updatedAt
    }
  }

  private cloneAudioProfile(): RuntimeAudioSettingsProfile {
    return {
      version: this.audioProfile.version,
      latencyMs: this.audioProfile.latencyMs,
      volumePercent: this.audioProfile.volumePercent,
      updatedAt: this.audioProfile.updatedAt
    }
  }

  private scheduleVisualProfilePersist(profile: RuntimeVisualSettingsProfile, actionLabel: string): void {
    this.visualProfile = profile
    this.runtimeApplyStatusText = `${actionLabel} 的本地配置已更新，返回运行页后生效`
    if (this.visualPersistTimer !== -1) {
      clearTimeout(this.visualPersistTimer)
    }
    this.visualPersistTimer = setTimeout(() => {
      this.visualPersistTimer = -1
      void this.persistVisualProfile(profile, actionLabel)
    }, 80)
  }

  private scheduleAudioProfilePersist(volumePercent: number, actionLabel: string): void {
    const nextProfile = this.cloneAudioProfile()
    nextProfile.volumePercent = volumePercent
    this.audioProfile = nextProfile
    const ok = runtimeAudioSettingsController.setVolumePercent(volumePercent)
    this.setRuntimeApplyStatus(actionLabel, ok)
    if (!ok) {
      return
    }
    if (this.audioPersistTimer !== -1) {
      clearTimeout(this.audioPersistTimer)
    }
    this.audioPersistTimer = setTimeout(() => {
      this.audioPersistTimer = -1
      void this.persistAudioProfile(nextProfile)
    }, 80)
  }

  private async persistVisualProfile(
    profile: RuntimeVisualSettingsProfile,
    actionLabel: string
  ): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    const token = this.beginRefresh()
    try {
      const saved = await saveRuntimeVisualSettingsProfile(context, profile)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.visualProfile = saved
      this.runtimeApplyStatusText = `${actionLabel} 的本地配置已保存，返回运行页后生效`
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.runtimeApplyStatusText = `${actionLabel} 没有保存成功，请稍后重试`
    }
  }

  private async persistRenderProfile(profile: RuntimeRenderSettingsProfile): Promise<void> {
    const token = this.beginRefresh()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    try {
      const savedProfile = await saveRuntimeRenderSettingsProfile(context, profile)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.renderProfile = savedProfile
      this.refreshAdvancedStatus()
    } catch (err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SettingsPage', 'Render', `保存运行时渲染配置失败: ${message}`)
      this.runtimeApplyStatusText = '画面设置没有保存成功，请稍后重试'
    }
  }

  private setRuntimeApplyStatus(actionLabel: string, ok: boolean): void {
    this.runtimeApplyStatusText = ok ?
      `${actionLabel} 已提交到当前运行` :
      `${actionLabel} 没有写入成功，当前运行状态保持不变`
  }

  private applyInputMappingStatus(status: InputMappingStatusSnapshot): void {
    this.inputMappingSummaryText = status.summaryText
    this.inputMappingDetailText = status.detailText
  }

  private async toggleHwRenderAllowed(): Promise<void> {
    const nextValue = !this.renderProfile.hwRenderAllowed
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.hwRenderAllowed = nextValue
    const ok = runtimeRenderSettingsController.setHwRenderAllowed(nextValue)
    this.setRuntimeApplyStatus('硬件渲染', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private async toggleSwapInterval(): Promise<void> {
    const nextValue = this.renderProfile.swapInterval === 0 ? 1 : 0
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.swapInterval = nextValue
    const ok = runtimeRenderSettingsController.setSwapInterval(nextValue)
    this.setRuntimeApplyStatus('垂直同步', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private async toggleAIUpscale(): Promise<void> {
    const nextValue = !this.renderProfile.aiUpscaleEnabled
    const nextProfile: RuntimeRenderSettingsProfile = this.cloneRenderProfile()
    nextProfile.aiUpscaleEnabled = nextValue
    const ok = runtimeRenderSettingsController.setAIUpscale(nextValue)
    this.setRuntimeApplyStatus('AI 超分', ok)
    if (!ok) {
      return
    }
    await this.persistRenderProfile(nextProfile)
  }

  private async toggleHideVirtualController(): Promise<void> {
    const token = this.beginRefresh()
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
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputPreferences = saved
      this.runtimeApplyStatusText = '虚拟手柄显示的本地配置已保存，返回运行页后生效'
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.setRuntimeApplyStatus('虚拟手柄显示', false)
    }
  }

  private async toggleHideUndeclaredKeys(): Promise<void> {
    const token = this.beginRefresh()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.setRuntimeApplyStatus('按当前游戏隐藏未使用按键', false)
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
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.inputPreferences = saved
      this.runtimeApplyStatusText = '按当前游戏隐藏未使用按键的本地配置已保存，返回运行页后生效'
    } catch (_err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.setRuntimeApplyStatus('按当前游戏隐藏未使用按键', false)
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

  private async cycleAudioLatencyPreset(): Promise<void> {
    const currentIndex = getAudioLatencyPresetIndex(this.audioProfile.latencyMs)
    const nextIndex = (currentIndex + 1) % AUDIO_LATENCY_PRESETS.length
    const nextLatency = getAudioLatencyForPreset(nextIndex)
    const ok = runtimeAudioSettingsController.setMinimumAudioLatency(nextLatency)
    this.setRuntimeApplyStatus('音频缓冲延迟', ok)
    if (!ok) {
      return
    }
    const nextProfile = this.cloneAudioProfile()
    nextProfile.latencyMs = nextLatency
    await this.persistAudioProfile(nextProfile)
  }

  private async persistAudioProfile(profile: RuntimeAudioSettingsProfile): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    const token = this.beginRefresh()
    try {
      const saved = await saveRuntimeAudioSettingsProfile(context, profile)
      if (!this.isCurrentRefresh(token)) {
        return
      }
      this.audioProfile = saved
    } catch (err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SettingsPage', 'Audio', `保存运行时音频配置失败: ${message}`)
      this.runtimeApplyStatusText = '音频设置没有保存成功，请稍后重试'
    }
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

  private applyEmptyTelemetry(): void {
    this.telemetryReady = true
    this.telemetryPrimaryLabel = '最近一次记录'
    this.telemetryPrimaryValue = '--'
    this.telemetrySecondaryLabel = '音频缓冲'
    this.telemetrySecondaryValue = '--'
    this.telemetryFooterLeft = '尚无运行记录'
    this.telemetryFooterRight = '进入游戏后会生成历史摘要'
  }

  private applyTelemetry(records: LibraryRecord[]): void {
    this.telemetryReady = true
    const telemetryCells: LibraryTelemetryCell[] = getLibraryTelemetryCells(records)
    const latestRecord = getLastPlayedLibraryRecord(records)
    const latestRunText = latestRecord ?
      formatLastPlayedRelative(latestRecord.lastRuntimeUpdatedAt) || '已有运行记录' :
      '暂无记录'
    this.telemetryPrimaryLabel = telemetryCells[0]?.label ?? '最近一次记录'
    this.telemetryPrimaryValue = latestRunText === '暂无记录' ? '--' : latestRunText
    this.telemetrySecondaryLabel = telemetryCells[2]?.label ?? '音频缓冲'
    this.telemetrySecondaryValue = telemetryCells[2]?.value ?? '--'
    this.telemetryFooterLeft = latestRunText === '暂无记录' ? '尚无运行记录' : `最近运行：${latestRunText}`
    this.telemetryFooterRight = telemetryCells[1]?.value && telemetryCells[1]?.value !== '--.-' ?
      `最近帧率：${telemetryCells[1].value}` :
      '运行后将生成历史摘要'
  }

  @Builder
  private TabItemCompact(key: string, title: string, code: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.activeTab === key ? EmuColors.primary : '#88757575')

      Text(code)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.activeTab === key ? '#B3ABABAB' : '#666666')
        .letterSpacing(1.2)
    }
    .width('100%')
    .height(72)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.activeTab === key ? EmuColors.surfaceContainerHighest : 'transparent')
    .borderRadius(8)
    .border({
      width: this.activeTab === key ? 2 : 0,
      color: EmuColors.primary,
      style: BorderStyle.Solid
    })
    .onClick(() => {
      this.activeTab = key
    })
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

      if (code.length > 0) {
        Text(code)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
                  .fontColor('#88757575')
          .letterSpacing(1.2)
      }
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
            .fontColor(this.isAspectActive(item.key) ? EmuColors.onSurface :
              (this.runtimeProfilesReady ? '#B3ABABAB' : '#66757575'))
        }
        .layoutWeight(1)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.isAspectActive(item.key) ? EmuColors.surfaceContainerHighest :
          (this.runtimeProfilesReady ? EmuColors.surfaceContainerHigh : '#14141414'))
        .onClick(() => {
          if (!this.runtimeProfilesReady) {
            this.runtimeApplyStatusText = '当前视觉配置没有读到，请先重试'
            return
          }
          const nextProfile = this.cloneVisualProfile()
          nextProfile.aspectMode = item.key === '4:3' || item.key === '16:9' ? item.key : 'native'
          this.scheduleVisualProfilePersist(nextProfile, '画面比例')
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
    const displayValue = this.runtimeProfilesReady ? value : 0
    LinearSettingRow({
      label: label,
      code: code,
      value: displayValue,
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

      Column({ space: 6 }) {
        Text(this.inputMappingSummaryText)
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .width('100%')
        Text(this.inputMappingDetailText)
          .fontSize(EmuTypography.xs)
          .fontColor('#88757575')
          .width('100%')
      }
      .width('100%')
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

      Column({ space: 8 }) {
        Text('这里展示的是最近一次运行记录，不是实时变化曲线。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')

        Text('如需判断当前运行状态，请进入游戏后以实际画面、声音和操作体验为准。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor(EmuColors.surfaceContainer)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

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
          this.runtimeProfilesReady ?
            (this.renderProfile.hwRenderAllowed ? '关闭硬件渲染' : '开启硬件渲染') :
            '重试读取配置',
          () => {
            if (!this.runtimeProfilesReady) {
              void this.refreshSettings()
              return
            }
            void this.toggleHwRenderAllowed()
          }
        )
        this.AdvancedActionButton(this.runtimeProfilesReady ? '切换缩放模式' : '重试读取配置', () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.cycleRenderMode()
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.AdvancedActionButton(this.runtimeProfilesReady ? '切换软件分辨率上限' : '重试读取配置', () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.cycleSoftwareResolutionPreset()
        })
        this.AdvancedActionButton('打开滤镜预览', () => {
          this.openPage('pages/ShaderPreviewPage', '滤镜预览')
        })
      }
      .width('100%')

      Text('当前页会把硬件渲染、缩放模式、垂直同步、AI 超分、软件分辨率上限、主音量，以及屏上手柄和视觉配置写入本地运行配置；返回运行页后会按最新配置生效。')
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .width('100%')
      if (!this.runtimeProfilesReady) {
        Text(this.runtimeProfilesUnavailableHintText)
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.error)
          .width('100%')
      }
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
  private GroupNavigationPanel() {
    Column({ space: 12 }) {
      Text('设置分类')
        .fontSize(EmuTypography.sm)
        .fontWeight(FontWeight.Bold)
        .fontColor('#88757575')
        .width('100%')
        .padding({ left: 16, bottom: 8 })

      ForEach(this.settingGroups, (group: SettingGroup) => {
        Row({ space: 12 }) {
          Text(group.icon)
            .fontSize(20)

          Text(group.label)
            .fontSize(EmuTypography.md)
            .fontWeight(this.activeGroup === group.id ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.activeGroup === group.id ? EmuColors.primary : EmuColors.onSurface)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.activeGroup === group.id ? EmuColors.surfaceContainerHighest : 'transparent')
        .borderRadius(8)
        .onClick(() => {
          this.activeGroup = group.id
        })
      }, (group: SettingGroup) => group.id)
    }
    .width('100%')
    .padding(12)
  }

  @Builder
  private SettingsDetailPanel() {
    Scroll() {
      Column({ space: 34 }) {
        if (this.isBasicTab()) {
          if (this.activeGroup === 'video' || this.foldableMode === FoldableMode.SINGLE) {
            this.VideoSettings()
          }
          if (this.activeGroup === 'input' || this.foldableMode === FoldableMode.SINGLE) {
            this.InputSettings()
          }
          if (this.activeGroup === 'audio' || this.foldableMode === FoldableMode.SINGLE) {
            this.AudioSettings()
          }
          if (this.activeGroup === 'system' || this.foldableMode === FoldableMode.SINGLE) {
            this.SystemSettings()
          }
        } else {
          this.AdvancedSettings()
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 24, bottom: 34 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private VideoSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('画面设置', '')

      Column({ space: 12 }) {
        Text('画面比例')
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontColor('#9AABABAB')
        this.SegmentedAspectControl()
        if (!this.runtimeProfilesReady) {
          Text('当前比例配置待确认，按钮样式暂不代表真实设置。')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')
          Text(this.runtimeProfilesUnavailableHintText)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.error)
            .width('100%')
        }
      }
      .width('100%')

      this.LinearSettingBlock(
        'CRT 复古扫描线强度',
        '',
        this.visualProfile.scanlineIntensity,
        this.onScanlineIntensityChange
      )
      if (!this.runtimeProfilesReady) {
        Text('扫描线强度这次没有读出来，当前滑块只是占位显示。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private InputSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('输入设备', '')
      this.InputDeviceCard()
    }
    .width('100%')
  }

  @Builder
  private AudioSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('音频音量', '')
      this.LinearSettingBlock('主音量', '', this.audioProfile.volumePercent, this.onMasterVolumeChange)
      if (!this.runtimeProfilesReady) {
        Text('主音量这次没有读出来，当前滑块只是占位显示。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')
        Text(this.runtimeProfilesUnavailableHintText)
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.error)
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private SystemSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('最近一次运行摘要', '')
      this.TelemetryPanel()
    }
    .width('100%')
  }

  @Builder
  private AdvancedSettings() {
    Column({ space: 18 }) {
      this.SectionTitle('高级设置', '')
      this.AdvancedControlsCard()
      this.AdvancedSettingRow(
        '虚拟手柄显示',
        this.hideVirtualControllerSummaryText,
        this.runtimeProfilesReady ? (this.inputPreferences.hideVirtualController ? '显示' : '隐藏') : '重试',
        () => {
          void this.toggleHideVirtualController()
        }
      )
      this.AdvancedSettingRow(
        '按当前游戏隐藏未使用按键',
        this.hideUndeclaredKeysSummaryText,
        this.runtimeProfilesReady ? (this.inputPreferences.hideUndeclaredKeys ? '关闭' : '开启') : '重试',
        () => {
          void this.toggleHideUndeclaredKeys()
        }
      )
      this.AdvancedSettingRow(
        '渲染方式',
        this.gpuBackendText,
        this.runtimeProfilesReady ? (this.renderProfile.hwRenderAllowed ? '关闭' : '开启') : '重试',
        () => {
          void this.toggleHwRenderAllowed()
        }
      )
      this.AdvancedSettingRow(
        '渲染模式',
        `${this.renderModeText} · 会影响运行页的画面呈现方式`,
        this.runtimeProfilesReady ? '切换' : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.cycleRenderMode()
        }
      )
      this.AdvancedSettingRow(
        '软件渲染分辨率',
        `${this.softwareResolutionText} · 仅软件渲染路径会使用该上限`,
        this.runtimeProfilesReady ? '切换' : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.cycleSoftwareResolutionPreset()
        }
      )
      this.AdvancedSettingRow(
        '垂直同步',
        this.vsyncSummaryText,
        this.runtimeProfilesReady ? (this.renderProfile.swapInterval === 0 ? '开启' : '关闭') : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.toggleSwapInterval()
        }
      )
      this.AdvancedSettingRow(
        'AI 超分',
        this.aiUpscaleSummaryText,
        this.runtimeProfilesReady ? (this.renderProfile.aiUpscaleEnabled ? '关闭' : '开启') : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.toggleAIUpscale()
        }
      )
      this.AdvancedSettingRow('音频缓冲', `历史运行摘要 · ${this.audioBufferSummaryText}`)
      this.AdvancedSettingRow(
        '音频延迟',
        `${this.audioLatencySummaryText} · 缓冲越大越能减少爆音和断续，代价是按键到出声延迟更高。注：低/标准档会受平台最小缓冲限制，模拟器上通常只有“高缓冲”档会更明显增加缓冲深度。`,
        this.runtimeProfilesReady ? '切换' : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          void this.cycleAudioLatencyPreset()
        }
      )
      this.AdvancedSettingRow(
        '滤镜模式',
        this.shaderModeSummaryText,
        this.runtimeProfilesReady ? '配置' : '重试',
        () => {
          if (!this.runtimeProfilesReady) {
            void this.refreshSettings()
            return
          }
          this.openPage('pages/ShaderPreviewPage', '滤镜预览')
        }
      )
      this.AdvancedSettingRow('当前运行时状态', this.advancedStatusText)
      this.AdvancedSettingRow('最近一次应用', this.runtimeApplyStatusText)
      this.NavigationRow('输入设备', '查看本机输入源和外接设备列表', 'pages/MultiplayerInputPage')
      this.NavigationRow('触控布局', '调整屏上按键布局', 'pages/InputLayoutPage')
      this.NavigationRow('核心与固件', '查看当前版本提供的核心与固件文件情况', 'pages/CoreManagerPage')
      this.NavigationRow('滤镜预览', '画面滤镜预览', 'pages/ShaderPreviewPage')
      this.NavigationRow('关于与帮助', '查看导入、合规和版本说明', 'pages/AboutHelpPage')
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

      Column({ space: 0 }) {
        this.TabHeader()

        if (this.foldableMode === FoldableMode.SINGLE) {
          // 单折态（F态）：单栏布局
          this.SettingsDetailPanel()
        } else if (this.foldableMode === FoldableMode.DUAL) {
          // 双折态（M态）：左侧导航（30%）+ 右侧详情（70%）
          Row() {
            Column() {
              this.GroupNavigationPanel()
            }
              .width('30%')
              .height('100%')
              .backgroundColor(EmuColors.surfaceContainer)
              .border({ width: { right: 0.5 }, color: '#26333333', style: BorderStyle.Solid })

            Column() {
              this.SettingsDetailPanel()
            }
              .width('70%')
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          // 三折态（G态）：左侧一级分类（20%）+ 中间二级分类（30%）+ 右侧详情（50%）
          Row() {
            // 左侧：Tab 切换（基础/高级）
            Column({ space: 12 }) {
              Text('设置类型')
                .fontSize(EmuTypography.sm)
                .fontWeight(FontWeight.Bold)
                .fontColor('#88757575')
                .width('100%')
                .padding({ left: 16, bottom: 8 })

              Column({ space: 8 }) {
                this.TabItemCompact('basic', '基础设置', 'BASIC')
                this.TabItemCompact('advanced', '高级设置', 'ADVANCED')
              }
              .width('100%')
              .padding({ left: 12, right: 12 })
            }
            .width('20%')
            .height('100%')
            .padding({ top: 12 })
            .backgroundColor(EmuColors.surfaceContainerLow)
            .border({ width: { right: 0.5 }, color: '#26333333', style: BorderStyle.Solid })

            // 中间：分组导航
            Column() {
              this.GroupNavigationPanel()
            }
              .width('30%')
              .height('100%')
              .backgroundColor(EmuColors.surfaceContainer)
              .border({ width: { right: 0.5 }, color: '#26333333', style: BorderStyle.Solid })

            // 右侧：详情
            Column() {
              this.SettingsDetailPanel()
            }
              .width('50%')
          }
          .layoutWeight(1)
          .width('100%')
        }
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
