import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import {
  InputDeviceInfo,
  InputSourceType
} from '../common/InputPortRouting'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'

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

interface TelemetryBarItem {
  id: string
  height: number
  isPrimary: boolean
}

@Entry
@Component
struct MultiplayerInputPage {
  @State private deviceNamesText: string = 'NO_EXTERNAL_DEVICE'
  @State private deviceCountText: string = '0'
  @State private selectedRoomId: string = 'local'
  @State private localLatencyText: string = 'FRAME_SYNC'
  @State private adapterStatusText: string = 'LOCAL_ONLY'

  private readonly telemetryBars: TelemetryBarItem[] = [
    { id: 'j-01', height: 24, isPrimary: false },
    { id: 'j-02', height: 30, isPrimary: false },
    { id: 'j-03', height: 18, isPrimary: true },
    { id: 'j-04', height: 22, isPrimary: true },
    { id: 'j-05', height: 26, isPrimary: true },
    { id: 'j-06', height: 44, isPrimary: false },
    { id: 'j-07', height: 16, isPrimary: true },
    { id: 'j-08', height: 20, isPrimary: true },
    { id: 'j-09', height: 34, isPrimary: false },
    { id: 'j-10', height: 14, isPrimary: true },
    { id: 'j-11', height: 18, isPrimary: true },
    { id: 'j-12', height: 20, isPrimary: true },
    { id: 'j-13', height: 28, isPrimary: false },
    { id: 'j-14', height: 23, isPrimary: true },
    { id: 'j-15', height: 17, isPrimary: true },
    { id: 'j-16', height: 21, isPrimary: true },
    { id: 'j-17', height: 24, isPrimary: false },
    { id: 'j-18', height: 22, isPrimary: true },
    { id: 'j-19', height: 30, isPrimary: false },
    { id: 'j-20', height: 16, isPrimary: true },
    { id: 'j-21', height: 14, isPrimary: true },
    { id: 'j-22', height: 20, isPrimary: true },
    { id: 'j-23', height: 40, isPrimary: false },
    { id: 'j-24', height: 18, isPrimary: true }
  ]

  private readonly inputLogs: InputLogItem[] = [
    { id: 'l-01', time: '[00:48:12]', eventName: 'P1_BTN_A', state: 'PRESS', isPrimary: true },
    { id: 'l-02', time: '[00:48:12]', eventName: 'P1_DIR_RT', state: 'HOLD', isPrimary: false },
    { id: 'l-03', time: '[00:48:13]', eventName: 'P1_BTN_A', state: 'RELEASE', isPrimary: false },
    { id: 'l-04', time: '[00:48:14]', eventName: 'P2_BTN_ST', state: 'WAIT', isPrimary: false },
    { id: 'l-05', time: '[00:48:14]', eventName: 'P1_DIR_UP', state: 'PRESS', isPrimary: true },
    { id: 'l-06', time: '[00:48:15]', eventName: 'P1_BTN_B', state: 'PRESS', isPrimary: true }
  ]

  aboutToAppear(): void {
    this.refreshInputDevices()
  }

  private refreshInputDevices(): void {
    const devices: InputDeviceInfo[] = runtimeInputPortController.listInputDevices()
    this.deviceCountText = `${devices.length}`
    this.deviceNamesText = this.buildDeviceNamesText(devices)
    this.localLatencyText = devices.length > 0 ? 'INPUT_QUEUE' : 'FRAME_SYNC'
    this.adapterStatusText = devices.length > 0 ? 'DEVICE_ROUTE_READY' : 'LOCAL_ONLY'
  }

  private buildDeviceNamesText(devices: InputDeviceInfo[]): string {
    if (devices.length === 0) {
      return 'NO_EXTERNAL_DEVICE'
    }
    const names: string[] = []
    devices.forEach((device: InputDeviceInfo) => {
      names.push(this.buildDeviceLabel(device))
    })
    return names.join(' / ')
  }

  private buildDeviceLabel(device: InputDeviceInfo): string {
    if (device.sourceType === InputSourceType.Keyboard) {
      return `KEYBOARD:${device.name}`
    }
    if (device.sourceType === InputSourceType.Mouse) {
      return `MOUSE:${device.name}`
    }
    if (device.sourceType === InputSourceType.Gamepad) {
      return `GAMEPAD:${device.name}`
    }
    if (device.sourceType === InputSourceType.BluetoothGamepad) {
      return `BT_PAD:${device.name}`
    }
    return device.name.length > 0 ? device.name : device.deviceId
  }

  private getControllerSlots(): ControllerSlotItem[] {
    return [
      {
        id: 'p1',
        label: 'Controller 01',
        name: 'Virtual Pad P1',
        deviceId: 'RETRO_PAD_TOUCH',
        status: 'CONNECTED',
        powerText: 'LOCAL',
        pollingRate: 'FRAME',
        latency: this.localLatencyText,
        protocol: 'RETRO_PAD',
        isActive: true
      },
      {
        id: 'p2',
        label: 'Controller 02',
        name: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? 'External Device' : this.deviceNamesText,
        deviceId: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? 'WAITING_FOR_HID' : `${this.deviceCountText}_DEVICE(S)`,
        status: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? 'UNBOUND' : 'CONNECTED',
        powerText: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? 'NO DEVICE' : 'INPUT BUS',
        pollingRate: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? '--' : 'DEVICE',
        latency: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? '--' : 'NATIVE',
        protocol: this.deviceNamesText === 'NO_EXTERNAL_DEVICE' ? 'HID_WAIT' : 'HID',
        isActive: this.deviceNamesText !== 'NO_EXTERNAL_DEVICE'
      }
    ]
  }

  private getLobbyRooms(): LobbyRoomItem[] {
    return [
      {
        id: 'local',
        title: 'Local Session',
        game: 'Current Runtime Input Bridge',
        latency: '0ms',
        players: '1 / 1',
        status: 'READY',
        color: EmuColors.primary
      },
      {
        id: 'adapter',
        title: 'Netplay Adapter',
        game: 'Remote lobby service not configured',
        latency: '--',
        players: 'OFFLINE',
        status: this.adapterStatusText,
        color: EmuColors.error
      },
      {
        id: 'layout',
        title: 'Layout Editor',
        game: 'Touch buttons and hot zone calibration',
        latency: 'LOCAL',
        players: 'P1',
        status: 'EDITABLE',
        color: EmuColors.secondary
      }
    ]
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'input')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[MultiplayerInputPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[MultiplayerInputPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  private openInputLayoutEditor(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/InputLayoutPage' }).catch((err: Error) => {
      console.error(`[MultiplayerInputPage] pushUrl InputLayoutPage failed: ${err.message}`)
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
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(1.4)
        }
        .alignItems(VerticalAlign.Center)

        Text(item.status)
          .fontSize(10)
          .fontFamily('monospace')
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
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#666666')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text(item.powerText)
            .fontSize(10)
            .fontFamily('monospace')
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
        this.MetricBox('Polling Rate', item.pollingRate, false)
        this.MetricBox('Latency', item.latency, item.isActive)
        this.MetricBox('Protocol', item.protocol, false)
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
        .fontSize(12)
        .fontFamily('monospace')
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
          Text('Netplay Lobby')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Text(`Devices: ${this.deviceCountText}`)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#777777')

          Button('Create Room')
            .height(30)
            .fontSize(10)
            .fontColor(EmuColors.onSurface)
            .backgroundColor(Color.Transparent)
            .border({ width: 0.5, color: EmuColors.outline, style: BorderStyle.Solid })
            .borderRadius(0)
            .onClick(() => {
              this.selectedRoomId = 'adapter'
            })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 1 }) {
        ForEach(this.getLobbyRooms(), (room: LobbyRoomItem) => {
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
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
        Text(`Game: ${room.game}`)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor('#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('Latency')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.latency)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(room.color)
      }
      .alignItems(HorizontalAlign.End)

      Column({ space: 4 }) {
        Text('Players')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.players)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurface)
      }
      .alignItems(HorizontalAlign.End)

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
          Text('Buffer Jitter Telemetry')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(EmuColors.onSurface)
            .letterSpacing(1.2)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text('REAL-TIME')
            .fontSize(8)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#1800FF41')
            .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })

          Text('INTERVAL: 16.6ms')
            .fontSize(8)
            .fontFamily('monospace')
            .fontColor('#777777')
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        EmuPrecisionGridBackdrop()
          .opacity(0.26)

        Row({ space: 2 }) {
          ForEach(this.telemetryBars, (item: TelemetryBarItem) => {
            Row()
              .layoutWeight(1)
              .height(item.height)
              .backgroundColor(item.isPrimary ? EmuColors.primary : EmuColors.surfaceContainerHighest)
              .opacity(item.isPrimary ? 0.5 : 1)
          }, (item: TelemetryBarItem) => item.id)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 10, bottom: 10 })
        .alignItems(VerticalAlign.Bottom)

        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#3300FF41')
          .align(Alignment.Center)

        Text('Jitter Variance: LOCAL_SAMPLE')
          .fontSize(8)
          .fontFamily('monospace')
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
        Text('Input Log')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurface)
          .letterSpacing(1.2)
      }
      .alignItems(VerticalAlign.Center)

      Column({ space: 6 }) {
        ForEach(this.inputLogs, (item: InputLogItem) => {
          Row() {
            Text(`${item.time} ${item.eventName}`)
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor('#777777')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.state)
              .fontSize(10)
              .fontFamily('monospace')
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
          this.refreshInputDevices()
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
        titleText: 'OS_EMU_v2.4.1',
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
            ForEach(this.getControllerSlots(), (item: ControllerSlotItem) => {
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
        items: createEmuBottomNavItems('input'),
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
