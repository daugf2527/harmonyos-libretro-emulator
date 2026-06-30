import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { createEmuBottomNavItems, EmuBottomNav } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { InputDeviceInfo } from '../common/InputPortRouting'
import { runtimeInputPortController } from '../common/RuntimeInputPortController'
import LogHelper from '../common/LogHelper'
import { display } from '@kit.ArkUI'

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
  description: string
  detail: string
  actionText: string
  color: string
}

interface InputLogItem {
  id: string
  time: string
  eventName: string
  state: string
  isPrimary: boolean
}

type DeviceListState = 'loading' | 'ready' | 'error'

@Entry
@ComponentV2
struct MultiplayerInputPage {
  @Local private deviceNamesText: string = ''
  @Local private deviceCountText: string = '0'
  @Local private selectedRoomId: string = 'local'
  @Local private localLatencyText: string = '本地触控'
  @Local private inputLogTitleText: string = '等待刷新设备列表'
  @Local private inputLogDetailText: string = '刷新后可查看当前已读取到的本机输入设备'
  @Local private deviceListState: DeviceListState = 'loading'
  @Local private showToast: boolean = false
  @Local private toastMessage: string = ''
  private readonly navItems = createEmuBottomNavItems('input')
  private pageActive: boolean = false
  private refreshToken: number = 0
  private toastTimer: number = -1

  // 折叠屏状态
  @Local private foldStatus: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN
  @Local private displayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    if (!this.pageActive) {
      return
    }
    this.foldStatus = data
  }
  private displayModeListener: (data: display.FoldDisplayMode) => void = (data: display.FoldDisplayMode) => {
    if (!this.pageActive) {
      return
    }
    this.displayMode = data
  }

  private readonly lobbyRooms: LobbyRoomItem[] = [
    {
      id: 'local',
      title: '本地输入源',
      description: '当前页提供本地触控入口和本机外设枚举结果',
      detail: '下方以本机设备枚举结果和触控入口说明为准',
      actionText: '查看设备',
      color: EmuColors.primary
    },
    {
      id: 'adapter',
      title: '联网说明',
      description: '当前版本不提供房间、在线同步或联网对战',
      detail: '如需联机功能，需要后续版本单独接入',
      actionText: '仅作说明',
      color: EmuColors.error
    },
    {
      id: 'layout',
      title: '按键布局编辑',
      description: '可前往布局页调整触控按键位置与映射',
      detail: '修改后需手动保存才会生效',
      actionText: '打开编辑',
      color: EmuColors.secondary
    }
  ]
  @Local private controllerSlots: ControllerSlotItem[] = []

  @Local private inputLogs: InputLogItem[] = []

  aboutToAppear(): void {
    this.pageActive = true
    void this.refreshDevices()  // Audit C-F5: async fire-and-forget; yields main thread before NAPI call

    // 注册折叠态监听
    try {
      this.foldStatus = display.getFoldStatus()
      this.displayMode = display.getFoldDisplayMode()
      display.on('foldStatusChange', this.foldStatusListener)
      display.on('foldDisplayModeChange', this.displayModeListener)
    } catch (err) {
      LogHelper.error('MultiplayerInputPage', 'FoldableInit', `Failed to init foldable: ${err}`)
    }
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.refreshToken += 1
    try {
      display.off('foldStatusChange', this.foldStatusListener)
      display.off('foldDisplayModeChange', this.displayModeListener)
    } catch (err) {
      LogHelper.error('MultiplayerInputPage', 'FoldableCleanup', `Failed to cleanup foldable: ${err}`)
    }
  }

  private beginRefresh(): number {
    this.refreshToken += 1
    return this.refreshToken
  }

  private isCurrentRefresh(token: number): boolean {
    return this.pageActive && token === this.refreshToken
  }

  private buildControllerSlots(): ControllerSlotItem[] {
    if (this.deviceListState === 'loading') {
      return [
        {
          id: 'p1',
          label: '玩家 1',
          name: '虚拟手柄 P1',
          deviceId: '本地触控布局',
          status: '检查中',
          powerText: '读取中',
          pollingRate: '读取中',
          latency: '读取中',
          protocol: '待读取',
          isActive: false
        },
        {
          id: 'p2',
          label: '外接手柄',
          name: '正在读取设备列表',
          deviceId: '请稍候',
          status: '检查中',
          powerText: '读取中',
          pollingRate: '读取中',
          latency: '读取中',
          protocol: '待读取',
          isActive: false
        }
      ]
    }
    if (this.deviceListState === 'error') {
      return [
        {
          id: 'p1',
          label: '玩家 1',
          name: '虚拟手柄 P1',
          deviceId: '本地触控布局',
          status: '状态待确认',
          powerText: '本地入口',
          pollingRate: '待确认',
          latency: '待确认',
          protocol: '待确认',
          isActive: false
        },
        {
          id: 'p2',
          label: '外接手柄',
          name: '本机输入设备列表没有读到',
          deviceId: '请稍后重试',
          status: '待重试',
          powerText: '待重试',
          pollingRate: '待重试',
          latency: '待重试',
          protocol: '待确认',
          isActive: false
        }
      ]
    }
    const hasExternal = this.deviceNamesText.length > 0
    return [
      {
        id: 'p1',
        label: '玩家 1',
        name: '虚拟手柄 P1',
        deviceId: '本地触控布局',
        status: '本地入口',
        powerText: '触控布局',
        pollingRate: '页面说明',
        latency: this.localLatencyText,
        protocol: '需进游戏确认',
        isActive: false
      },
      {
        id: 'p2',
        label: '外接手柄',
        name: hasExternal ? this.deviceNamesText : '当前没有枚举到外接手柄',
        deviceId: hasExternal ? `${this.deviceCountText} 个外接设备` : '当前没有枚举到外接设备',
        status: hasExternal ? '已列出' : '未列出',
        powerText: hasExternal ? '设备列表' : '无设备',
        pollingRate: hasExternal ? '系统枚举' : '--',
        latency: hasExternal ? '本机设备' : '--',
        protocol: hasExternal ? '待分配' : '接入后可分配',
        isActive: hasExternal
      }
    ]
  }

  private async refreshDevices(): Promise<void> {
    const token = this.beginRefresh()
    this.deviceListState = 'loading'
    this.controllerSlots = this.buildControllerSlots()
    this.inputLogTitleText = '正在读取本机输入设备'
    this.inputLogDetailText = '当前正在刷新本机输入设备列表'
    await Promise.resolve();  // Audit C-F5: yield main thread before NAPI call
    if (!this.isCurrentRefresh(token)) {
      return
    }
    let devices: InputDeviceInfo[] = []
    try {
      devices = runtimeInputPortController.listInputDevices()
    } catch (err) {
      if (!this.isCurrentRefresh(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('MultiplayerInputPage', 'Input', `读取输入设备列表失败: ${message}`)
      this.deviceListState = 'error'
      this.deviceNamesText = ''
      this.deviceCountText = '0'
      this.localLatencyText = '待确认'
      this.controllerSlots = this.buildControllerSlots()
      this.inputLogs = [
        {
          id: 'device-read-failed',
          time: '[本地]',
          eventName: '设备列表',
          state: '待重试',
          isPrimary: false
        }
      ]
      this.inputLogTitleText = '本机输入设备没有读出来'
      this.inputLogDetailText = '请稍后重试，确认本机输入设备列表'
      return
    }
    const names: string[] = []
    const logs: InputLogItem[] = [
      {
        id: 'local-touch',
        time: '[本地]',
        eventName: '触控布局',
        state: '本地入口',
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
        state: `${item.deviceId}`.trim().length > 0 ? '已枚举' : '已读取',
        isPrimary: true
      })
    })
    if (!this.isCurrentRefresh(token)) {
      return
    }
    this.deviceListState = 'ready'
    this.deviceNamesText = names.join(' / ')
    this.deviceCountText = `${devices.length}`
    this.localLatencyText = devices.length > 0 ? '本机已枚举外设' : '当前仅本地触控入口'
    this.controllerSlots = this.buildControllerSlots()
    this.inputLogs = logs
    this.inputLogTitleText = devices.length > 0 ? `已列出 ${devices.length} 个外接设备` : '当前没有枚举到外接设备'
    this.inputLogDetailText = devices.length > 0 ?
      '当前页面展示的是本机已读取到的设备列表' :
      '当前页面仅显示本地触控布局'
  }

  private getExternalDeviceCount(): number {
    const count = Number(this.deviceCountText)
    return Number.isFinite(count) && count > 0 ? count : 0
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'input')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('MultiplayerInputPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.showToastMessage('这个页面现在还打不开，请稍后再试')
    })
  }

  private openInputLayoutEditor(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/InputLayoutPage' }).catch((err: Error) => {
      LogHelper.error('MultiplayerInputPage', 'Route', `pushUrl InputLayoutPage failed: ${err.message}`)
      this.showToastMessage('输入布局页现在还打不开，请稍后再试')
    })
  }

  private showToastMessage(message: string): void {
    this.toastMessage = message
    this.showToast = true
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
    }
    this.toastTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.showToast = false
      this.toastTimer = -1
    }, 2400)
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

          Text(`来源：${item.deviceId}`)
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
        this.MetricBox('同步', item.pollingRate, false)
        this.MetricBox('来源', item.latency, item.isActive)
        this.MetricBox('映射', item.protocol, false)
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
          Text('当前页范围')
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Text('当前页只提供本机输入说明和布局入口')
            .fontSize(EmuTypography.xs)
                        .fontColor('#777777')

          Button('打开布局')
            .height(44)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurface)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(EmuColors.surfaceContainerHigh)
            .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
            .borderRadius(0)
            .onClick(() => {
              this.openInputLayoutEditor()
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
        Text(room.description)
          .fontSize(EmuTypography.xs)
                    .fontColor('#666666')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(room.detail)
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(room.actionText)
        .fontSize(9)
                .fontColor(room.id === 'adapter' ? EmuColors.error : room.color)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor(room.id === 'adapter' ? '#227E2B17' : '#1800FF41')
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
          Text('本机枚举摘要')
            .fontSize(11)
                        .fontColor(EmuColors.onSurface)
            .letterSpacing(1.2)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text('本机枚举')
            .fontSize(8)
                        .fontColor(EmuColors.primary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#1800FF41')
            .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })

          Text('设备列表')
            .fontSize(8)
                        .fontColor('#777777')
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          this.MetricBox(
            '触控入口',
            this.deviceListState === 'ready' ? '入口已展示' :
              (this.deviceListState === 'error' ? '待确认' : '读取中'),
            this.deviceListState === 'ready'
          )
          this.MetricBox(
            '外设枚举',
            this.deviceListState === 'ready' ?
              (this.getExternalDeviceCount() > 0 ? `${this.getExternalDeviceCount()} 个` : '未枚举到') :
              (this.deviceListState === 'error' ? '待确认' : '读取中'),
            this.deviceListState === 'ready' && this.getExternalDeviceCount() > 0
          )
          this.MetricBox(
            '本机摘要',
            this.deviceListState === 'ready' ? this.localLatencyText :
              (this.deviceListState === 'error' ? '待确认' : '读取中'),
            this.deviceListState === 'ready' && this.getExternalDeviceCount() > 0
          )
        }
        .width('100%')

        Text(this.deviceListState === 'error' ?
          '本机输入设备状态这次没有读出来，请稍后重试。' :
          '设备名称以下方列表为准，当前页不展示实时延迟曲线。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')
      }
      .width('100%')
      .height(132)
      .padding(12)
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: 0.5, color: '#22333333', style: BorderStyle.Solid })
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
        Text('设备列表')
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

      Text(this.deviceListState === 'error' ?
        '当前页只拿到未读取结果，不代表设备真的没有连接。' :
        '当前页仅展示本机输入设备列表，不代表联网或多人同步状态。')
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

  // 判断当前折叠态
  private isTripleFoldExpanded(): boolean {
    // 三折态全展开（G态）：FoldStatus.EXPANDED + DisplayMode.FULL
    return this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED &&
      this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL
  }

  private isDoubleFoldExpanded(): boolean {
    // 双折态展开（M态）：FoldStatus.HALF_FOLDED 或 DisplayMode.MAIN
    return this.foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED ||
      this.displayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
      (this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED &&
        this.displayMode !== display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL)
  }

  // 单折态布局（F态）
  @Builder
  private SingleFoldLayout() {
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
  }

  // 双折态布局（M态）
  @Builder
  private DoubleFoldLayout() {
    Row({ space: 0 }) {
      // 左侧：玩家列表（40%）
      Scroll() {
        Column({ space: 14 }) {
          ForEach(this.controllerSlots, (item: ControllerSlotItem) => {
            this.ControllerCard(item)
          }, (item: ControllerSlotItem) => item.id)

          this.LobbySection()

          this.ActionStrip()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 24, bottom: 32 })
      }
      .width('40%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(EmuColors.background)

      // 右侧：设备分配 + 测试面板（60%）
      Scroll() {
        Column({ space: 14 }) {
          this.TelemetrySection()
          this.InputLogSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 24, bottom: 32 })
      }
      .width('60%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(EmuColors.surfaceContainerLowest)
    }
    .width('100%')
    .layoutWeight(1)
  }

  // 三折态布局（G态）
  @Builder
  private TripleFoldLayout() {
    Row({ space: 0 }) {
      // 左侧：玩家列表（25%）
      Scroll() {
        Column({ space: 14 }) {
          ForEach(this.controllerSlots, (item: ControllerSlotItem) => {
            this.ControllerCard(item)
          }, (item: ControllerSlotItem) => item.id)

          this.ActionStrip()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 32 })
      }
      .width('25%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(EmuColors.background)

      // 中间：设备分配（50%）
      Scroll() {
        Column({ space: 14 }) {
          this.LobbySection()
          this.TelemetrySection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 24, bottom: 32 })
      }
      .width('50%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(EmuColors.surfaceContainerLowest)

      // 右侧：输入测试面板（25%）
      Scroll() {
        Column({ space: 14 }) {
          this.InputLogSection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 32 })
      }
      .width('25%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(EmuColors.surfaceContainer)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private Toast() {
    Row({ space: 8 }) {
      EmuIcon({
        name: 'check_circle',
        iconSize: 14
      })
      Text(this.toastMessage)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor('#004C0C')
        .letterSpacing(1)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(EmuColors.primary)
    .borderRadius(999)
    .shadow({ radius: 18, color: '#6600FF41', offsetX: 0, offsetY: 0 })
    .align(Alignment.Bottom)
    .margin({ bottom: 96 })
  }

  build() {
    Stack() {
      Column() {
        EmuHeaderBar({
          titleText: '碳影 / Carbon Shade',
          titleIcon: 'terminal',
          rightLabel: '本机输入与布局',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18,
          onRightClick: () => {
            this.openInputLayoutEditor()
          }
        })

        // 根据折叠态选择布局
        if (this.isTripleFoldExpanded()) {
          // 三折态全展开（G态）
          this.TripleFoldLayout()
        } else if (this.isDoubleFoldExpanded()) {
          // 双折态展开（M态）
          this.DoubleFoldLayout()
        } else {
          // 单折态/折叠态（F态）
          this.SingleFoldLayout()
        }

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

      if (this.showToast) {
        this.Toast()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
