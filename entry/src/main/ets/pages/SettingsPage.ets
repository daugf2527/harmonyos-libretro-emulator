import { EmuColors } from '../common/EmuUiTokens'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

interface SettingOptionItem {
  key: string
  label: string
  isActive: boolean
}

interface TelemetryBarItem {
  key: string
  height: number
  opacityValue: number
}

@Entry
@Component
struct SettingsPage {
  @State private activeTab: string = 'basic'
  @State private aspectMode: string = '4:3'
  @State private scanlineIntensity: number = 64
  @State private masterVolume: number = 80
  @State private inputDeviceStatus: string = 'LOCAL_PRESET'

  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: false },
    { key: 'system', iconName: 'tune', label: '系统', isActive: true }
  ]

  private readonly aspectOptions: SettingOptionItem[] = [
    { key: '4:3', label: '4:3', isActive: true },
    { key: '16:9', label: '16:9', isActive: false },
    { key: 'native', label: 'NATIVE', isActive: false }
  ]

  private readonly telemetryBars: TelemetryBarItem[] = [
    { key: 'cpu-1', height: 32, opacityValue: 0.56 },
    { key: 'cpu-2', height: 44, opacityValue: 0.7 },
    { key: 'cpu-3', height: 38, opacityValue: 0.62 },
    { key: 'cpu-4', height: 58, opacityValue: 0.9 },
    { key: 'cpu-5', height: 52, opacityValue: 0.78 },
    { key: 'cpu-6', height: 40, opacityValue: 0.62 },
    { key: 'cpu-7', height: 46, opacityValue: 0.72 },
    { key: 'cpu-8', height: 34, opacityValue: 0.5 },
    { key: 'cpu-9', height: 28, opacityValue: 0.42 },
    { key: 'cpu-10', height: 44, opacityValue: 0.68 },
    { key: 'cpu-11', height: 74, opacityValue: 0.92 },
    { key: 'cpu-12', height: 50, opacityValue: 0.75 },
    { key: 'cpu-13', height: 40, opacityValue: 0.58 },
    { key: 'cpu-14', height: 46, opacityValue: 0.68 },
    { key: 'cpu-15', height: 56, opacityValue: 0.82 }
  ]

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[SettingsPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[SettingsPage] pushUrl ${route} failed: ${err.message}`)
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
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.activeTab === key ? EmuColors.onSurface : '#88757575')

        Text(code)
          .fontSize(10)
          .fontFamily('monospace')
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
        .fontFamily('monospace')
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
  private LinearSetting(label: string, code: string, value: number) {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 4 }) {
          Text(label)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#C8ABABAB')

          Text(code)
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor('#77666666')
        }
        .alignItems(VerticalAlign.Bottom)

        Text(`${value}%`)
          .fontSize(12)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#66757575')

        Row() {
          Row()
            .width(2)
            .height(16)
            .backgroundColor(EmuColors.onSurface)
        }
          .width(`${value}%`)
          .height(1)
          .backgroundColor(Color.Transparent)
          .justifyContent(FlexAlign.End)
          .align(Alignment.Start)

        Row()
          .width(`${value}%`)
          .height(1)
          .backgroundColor(EmuColors.primary)
          .align(Alignment.Start)
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
          Text('LOCAL TOUCH INPUT')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)

          Text('ID: RETRO_PAD_TOUCH')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#B3ABABAB')
        }
        .alignItems(HorizontalAlign.Start)

        Text(this.inputDeviceStatus)
          .fontSize(10)
          .fontFamily('monospace')
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

          Text('L: SHOULDER_LEFT')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#B3ABABAB')

          Text('R: SHOULDER_RIGHT')
            .fontSize(10)
            .fontFamily('monospace')
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

      Text('按键布局映射预览 BUTTON_LAYOUT_PREVIEW')
        .fontSize(10)
        .fontFamily('monospace')
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
          Text('CPU_LOAD')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#B3ABABAB')
          Text('42.8%')
            .fontSize(24)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Text('MEM_ALLOC')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#B3ABABAB')
          Text('1.2 GB')
            .fontSize(22)
            .fontFamily('monospace')
            .fontColor(EmuColors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 7 }) {
        ForEach(this.telemetryBars, (item: TelemetryBarItem) => {
          Row()
            .width(18)
            .height(item.height)
            .backgroundColor(EmuColors.primary)
            .opacity(item.opacityValue)
        }, (item: TelemetryBarItem) => item.key)
      }
      .height(92)
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.Center)

      Row() {
        Text('T-60S')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#88757575')
        Text('FPS_60.0_STABLE')
          .fontSize(9)
          .fontFamily('monospace')
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
  private BasicSettings() {
    Column({ space: 34 }) {
      Column({ space: 18 }) {
        this.SectionTitle('画面设置', 'VIDEO_PROCESSING')

        Column({ space: 12 }) {
          Text('画面比例 aspect_ratio')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#9AABABAB')
          this.SegmentedAspectControl()
        }
        .width('100%')

        this.LinearSetting('CRT 复古扫描线强度', 'scanline_intensity', this.scanlineIntensity)
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('输入设备', 'INPUT_INTERFACE')
        this.InputDeviceCard()
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('音频音量', 'AUDIO_VOLUME')
        this.LinearSetting('主音量', 'master_volume', this.masterVolume)
      }
      .width('100%')

      Column({ space: 18 }) {
        this.SectionTitle('系统实时监测', 'SYSTEM_TELEMETRY')
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
      this.ValueRow('GPU Backend', 'LOCAL_PRESET')
      this.ValueRow('Frame Pacing', 'LOCAL_PRESET')
      this.ValueRow('Audio Buffer', 'LOCAL_PRESET')
      this.ValueRow('Shader Mode', 'PREVIEW_ONLY')
      this.ValueRow('Telemetry Scope', 'Runtime Only')
      this.NavigationRow('Input / Netplay Center', 'LOCAL_INPUT_ROUTING', 'pages/MultiplayerInputPage')
      this.NavigationRow('Input Layout Editor', 'LOCAL_TOUCH_LAYOUT', 'pages/InputLayoutPage')
      this.NavigationRow('Core / Firmware Manager', 'LOCAL_CORE_SCAN', 'pages/CoreManagerPage')
      this.NavigationRow('Shader Preview', 'VIDEO_BRIDGE_PREVIEW', 'pages/ShaderPreviewPage')
      this.NavigationRow('About / Help', 'LOCAL_DOCUMENTATION', 'pages/AboutHelpPage')
    }
    .width('100%')
  }

  @Builder
  private NavigationRow(label: string, value: string, url: string) {
    Row() {
      Column({ space: 4 }) {
        Text(label)
          .fontSize(14)
          .fontColor(EmuColors.onSurface)
        Text(value)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(22)
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
    .onClick(() => {
      this.openPage(url, label)
    })
  }

  @Builder
  private ValueRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(EmuColors.onSurface)
      Text(value)
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: 'EMU_OS // 0.1',
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
