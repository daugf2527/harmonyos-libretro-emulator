import { BarChartBackground, BarChartItem, EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { InputDeviceInfo } from '../common/InputPortRouting'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'
import LogHelper from '../common/LogHelper'

interface ControllerSlotItem {
  id: string
  label: string
  name: string
  deviceId: string
  status: string
  powerText: string
  pollingRate: string
  latency: string
  protocol: string
  isActive: boolean
}

interface LobbyRoomItem {
  id: string
  title: string
  game: string
  latency: string
  players: string
  status: string
  color: string
}

interface InputLogItem {
  id: string
  time: string
  eventName: string
  state: string
  isPrimary: boolean
}


@Entry
@Component
struct MultiplayerInputPage {
  @State private deviceNamesText: string = ''
  @State private deviceCountText: string = '0'
  @State private selectedRoomId: string = 'local'
  @State private localLatencyText: string = '本地触控'
  @State private inputLogTitleText: string = '等待输入'
  @State private inputLogDetailText: string = '刷新设备后可查看当前外接手柄状态'
  private readonly navItems = createEmuBottomNavItems('input')

  private readonly lobbyRooms: LobbyRoomItem[] = [
    {
      id: 'local',
      title: '本地游玩',
      game: '当前运行输入桥',
      latency: '0ms',
      players: '1 / 1',
      status: 'READY',
      color: EmuColors.primary
    },
    {
      id: 'adapter',
      title: 'Netplay 联机',
      game: '中继 / 房间服务未配置',
      latency: '--',
      players: 'OFFLINE',
      status: '未配置',
      color: EmuColors.error
    },
    {
      id: 'layout',
      title: '按键布局编辑',
      game: '触控按键与热区校准',
      latency: '本地',
      players: 'P1',
      status: '可编辑',
      color: EmuColors.secondary
    }
  ]
  @State private controllerSlots: ControllerSlotItem[] = []

  private readonly telemetryBars: BarChartItem[] = [
    { height: 24, isPrimary: false }, { height: 30, isPrimary: false },
    { height: 18, isPrimary: true },  { height: 22, isPrimary: true },
    { height: 26, isPrimary: true },  { height: 44, isPrimary: false },
    { height: 16, isPrimary: true },  { height: 20, isPrimary: true },
    { height: 34, isPrimary: false }, { height: 14, isPrimary: true },
    { height: 18, isPrimary: true },  { height: 20, isPrimary: true },
    { height: 28, isPrimary: false }, { height: 23, isPrimary: true },
    { height: 17, isPrimary: true },  { height: 21, isPrimary: true },
    { height: 24, isPrimary: false }, { height: 22, isPrimary: true },
    { height: 30, isPrimary: false }, { height: 16, isPrimary: true },
    { height: 14, isPrimary: true },  { height: 20, isPrimary: true },
    { height: 40, isPrimary: false }, { height: 18, isPrimary: true }
  ]

  @State private inputLogs: InputLogItem[] = []

  aboutToAppear(): void {
    void this.refreshDevices()  // Audit C-F5: async fire-and-forget; yields main thread before NAPI call
  }

  private buildControllerSlots(): ControllerSlotItem[] {
    const hasExternal = this.deviceNamesText.length > 0
    return [
      {
        id: 'p1',
        label: '玩家 1',
        name: '虚拟手柄 P1',
        deviceId: 'RETRO_PAD_TOUCH',
        status: '已连接',
        powerText: '本地',
        pollingRate: 'FRAME',
        latency: this.localLatencyText,
        protocol: 'RETRO_PAD',
        isActive: true
      },
      {
        id: 'p2',
        label: '外接手柄',
        name: hasExternal ? this.deviceNamesText : '等待连接手柄',
        deviceId: hasExternal ? `${this.deviceCountText} 个输入设备` : '等待 HID / 蓝牙手柄',
        status: hasExternal ? '已连接' : '未绑定',
        powerText: hasExternal ? '输入总线' : '无设备',
        pollingRate: hasExternal ? '设备轮询' : '--',
        latency: hasExternal ? '系统直连' : '--',
        protocol: hasExternal ? 'HID' : '等待接入',
        isActive: hasExternal
      }
    ]
  }

  private async refreshDevices(): Promise<void> {
    await Promise.resolve();  // Audit C-F5: yield main thread before NAPI call
    const devices: InputDeviceInfo[] = runtimeInputPortController.listInputDevices()
    const names: string[] = []
    const logs: InputLogItem[] = [
      {
        id: 'local-touch',
        time: '[本地]',
        eventName: '触控布局',
        state: '就绪',
        isPrimary: true
      }
    ]
    devices.forEach((item: InputDeviceInfo, index: number) => {
      const deviceName = `${item.name}`.trim()
      if (deviceName.length > 0) {
        names.push(deviceName)
      }
      logs.push({
        id: `device-${index}`,
        time: '[设备]',
        eventName: deviceName.length > 0 ? deviceName : `设备 ${index + 1}`,
        state: `${item.deviceId}`.trim().length > 0 ? '已识别' : '已连接',
        isPrimary: true
      })
    })
    this.deviceNamesText = names.join(' / ')
    this.deviceCountText = `${devices.length}`
    this.localLatencyText = devices.length > 0 ? '多源输入' : '本地触控'
    this.controllerSlots = this.buildControllerSlots()
    this.inputLogs = logs
    this.inputLogTitleText = devices.length > 0 ? `已识别 ${devices.length} 个外接设备` : '未检测到外接手柄'
    this.inputLogDetailText = devices.length > 0 ?
      '当前已读取本机输入设备列表' :
      '当前仅启用本地触控布局'
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'input')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('MultiplayerInputPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
    })
  }

  private openInputLayoutEditor(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/InputLayoutPage' }).catch((err: Error) => {
      LogHelper.error('MultiplayerInputPage', 'Route', `pushUrl InputLayoutPage failed: ${err.message}`)
    })
  }

  @Builder
  private ControllerCard(item: ControllerSlotItem) {
    Column({ space: 16 }) {
      Row() {
        Row({ space: 8 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(item.isActive ? EmuColors.primary : EmuColors.outline)

          Text(item.label)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(1.4)
        }
        .alignItems(VerticalAlign.Center)

        Text(item.status)
          .fontSize(EmuTypography.xs)
                    .fontColor(item.isActive ? EmuColors.primary : EmuColors.onSurfaceVariant)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(item.isActive ? '#1800FF41' : EmuColors.surfaceContainerHigh)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Column({ space: 5 }) {
          Text(item.name)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`ID: ${item.deviceId}`)
            .fontSize(EmuTypography.xs)
                        .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text(item.powerText)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurfaceVariant)

          Row()
            .width(64)
            .height(2)
            .backgroundColor(item.isActive ? EmuColors.primary : EmuColors.outlineVariant)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Row({ space: 8 }) {
        this.MetricBox('轮询', item.pollingRate, false)
        this.MetricBox('延迟', item.latency, item.isActive)
        this.MetricBox('协议', item.protocol, false)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private MetricBox(label: string, value: string, highlight: boolean) {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(8)
        .fontColor('#777777')
        .letterSpacing(0.5)
        .maxLines(1)

      Text(value)
        .fontSize(EmuTypography.sm)
                .fontColor(highlight ? EmuColors.primary : EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(EmuColors.surfaceContainerLowest)
    .border({ width: 0.5, color: '#22333333', style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LobbySection() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 8 }) {
          EmuIcon({ name: 'explore', tone: 'muted', iconSize: 18 })
          Text('NETPLAY\n联机')
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)
            .lineHeight(20)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Text('中继：未配置')
            .fontSize(EmuTypography.xs)
                        .fontColor('#777777')

          Button('创建\n房间')
            .height(44)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurface)
            .backgroundColor(Color.Transparent)
            .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
            .borderRadius(0)
            .opacity(0.45)
            .enabled(false)
            .onClick(() => {
              this.selectedRoomId = 'adapter'
            })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 1 }) {
        ForEach(this.lobbyRooms, (room: LobbyRoomItem) => {
          this.RoomRow(room)
        }, (room: LobbyRoomItem) => room.id)
      }
      .width('100%')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    }
    .width('100%')
  }

  @Builder
  private RoomRow(room: LobbyRoomItem) {
    Row({ space: 16 }) {
      Stack() {
        EmuPrecisionGridBackdrop()
          .opacity(0.24)
        Row()
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(room.color)
          .opacity(0.32)
      }
      .width(48)
      .height(48)
      .backgroundColor(EmuColors.surfaceContainer)
      .border({ width: 0.5, color: this.selectedRoomId === room.id ? room.color : '#22484848', style: BorderStyle.Solid })
      .clip(true)

      Column({ space: 4 }) {
        Text(room.title)
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(room.game)
          .fontSize(EmuTypography.xs)
                    .fontColor('#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('延迟')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.latency)
          .fontSize(EmuTypography.sm)
                    .fontColor(room.color)
      }
      .alignItems(HorizontalAlign.End)

      Column({ space: 4 }) {
        Text('人数')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.players)
          .fontSize(EmuTypography.sm)
                    .fontColor(EmuColors.onSurface)
      }
      .alignItems(HorizontalAlign.End)

      Text(room.status)
        .fontSize(9)
                .fontColor(room.status === '未配置' ? EmuColors.error : room.color)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor(room.status === '未配置' ? '#227E2B17' : '#1800FF41')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.selectedRoomId === room.id ? '●' : '›')
        .fontSize(this.selectedRoomId === room.id ? 12 : 24)
        .fontColor(this.selectedRoomId === room.id ? room.color : EmuColors.onSurfaceVariant)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.selectedRoomId === room.id ? EmuColors.surfaceContainerLow : EmuColors.surfaceContainerLowest)
    .onClick(() => {
      this.selectedRoomId = room.id
      if (room.id === 'layout') {
        this.openInputLayoutEditor()
      }
    })
  }

  @Builder
  private TelemetrySection() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 8 }) {
          EmuIcon({ name: 'equalizer', iconSize: 16 })
          Text('输入延迟抖动')
            .fontSize(11)
                        .fontColor(EmuColors.onSurface)
            .letterSpacing(1.2)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text('实时')
            .fontSize(8)
                        .fontColor(EmuColors.primary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#1800FF41')
            .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })

          Text('采样：16.6ms')
            .fontSize(8)
                        .fontColor('#777777')
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        EmuPrecisionGridBackdrop()
          .opacity(0.26)

        BarChartBackground({
          bars: this.telemetryBars,
          primaryColor: EmuColors.primary,
          secondaryColor: EmuColors.surfaceContainerHighest,
          barGap: 2
        })
          .width('100%')
          .height('100%')
          .padding({ left: 10, right: 10, bottom: 10 })

        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#3300FF41')
          .align(Alignment.Center)

        Text('抖动样本：本地输入')
          .fontSize(8)
                    .fontColor('#777777')
          .align(Alignment.TopStart)
          .margin({ left: 12, top: 10 })
      }
      .width('100%')
      .height(132)
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: 0.5, color: '#22333333', style: BorderStyle.Solid })
      .clip(true)
    }
    .layoutWeight(2)
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private InputLogSection() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        EmuIcon({ name: 'info', tone: 'muted', iconSize: 16 })
        Text('输入检测')
          .fontSize(11)
                    .fontColor(EmuColors.onSurface)
          .letterSpacing(1.2)
      }
      .alignItems(VerticalAlign.Center)

      Text(this.inputLogTitleText)
        .fontSize(EmuTypography.sm)
        .fontColor(EmuColors.onSurface)
        .width('100%')

      Text(this.inputLogDetailText)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .width('100%')

      Column({ space: 6 }) {
        ForEach(this.inputLogs, (item: InputLogItem) => {
          Row() {
            Text(`${item.time} ${item.eventName}`)
              .fontSize(EmuTypography.xs)
                            .fontColor('#777777')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.state)
              .fontSize(EmuTypography.xs)
                            .fontColor(item.isPrimary ? EmuColors.primary : EmuColors.onSurfaceVariant)
          }
          .width('100%')
        }, (item: InputLogItem) => item.id)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private ActionStrip() {
    Row({ space: 10 }) {
      Button('刷新设备')
        .height(40)
        .fontSize(13)
        .fontColor(EmuColors.onSurface)
        .backgroundColor(EmuColors.surfaceContainerHigh)
        .borderRadius(0)
        .onClick(() => {
          this.refreshDevices()
        })

      Button('编辑按键布局')
        .height(40)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#004C0C')
        .backgroundColor(EmuColors.primary)
        .borderRadius(0)
        .onClick(() => {
          this.openInputLayoutEditor()
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: '碳影 / Carbon Shade',
        titleIcon: 'terminal',
        rightLabel: '输入映射与联机中心',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 18,
        onRightClick: () => {
          this.openInputLayoutEditor()
        }
      })

      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 14 }) {
            ForEach(this.controllerSlots, (item: ControllerSlotItem) => {
              this.ControllerCard(item)
            }, (item: ControllerSlotItem) => item.id)
          }
          .width('100%')

          this.LobbySection()

          Column({ space: 14 }) {
            this.TelemetrySection()
            this.InputLogSection()
          }
          .width('100%')

          this.ActionStrip()
        }
        .width('100%')
        .constraintSize({ maxWidth: 780 })
        .padding({ left: 24, right: 24, top: 24, bottom: 32 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

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
