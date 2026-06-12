import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { InputSourceType, PortAssignState } from '../common/InputPortRouting'
import { RuntimeCheatItem } from '../common/RuntimeCheatRepository'
import { RuntimeCoreOptionItem, RuntimeCoreOptionValue } from '../common/RuntimeCoreOptionsController'
import {
  describeRuntimeControllerPortDevice,
  RUNTIME_CONTROLLER_PORT_DEVICE_OPTIONS,
  RuntimeControllerPortDeviceOption
} from '../common/RuntimeInputPortController'
import { RuntimeSramBackupListItem } from '../common/RuntimeSramController'
import { RuntimeSaveStateListItem } from '../common/RuntimeSaveStateController'

interface RuntimePauseAction {
  title: string
  code: string
  iconText: string
  actionCode: string
}

@ComponentV2
export struct RuntimePauseOverlay {
  @Param processText: string = ''
  @Param saveStatusText: string = '存档就绪'
  @Param fpsText: string = '--.-'
  @Param cpuLoadText: string = '--'
  @Param perfStatsText: string = ''
  @Param audioStatusText: string = ''
  @Param geometryText: string = ''
  @Param regionText: string = ''
  @Param runtimeStateText: string = ''
  @Param runtimeLoadStateText: string = ''
  @Param runtimeSaveStateSizeText: string = ''
  @Param runtimeInputDebugText: string = ''
  @Param diskControlVisible: boolean = false
  @Param diskControlModeText: string = ''
  @Param diskControlStatusText: string = ''
  @Param diskImageIndex: number = 0
  @Param diskImageCount: number = 0
  @Param diskEjected: boolean = false
  @Param diskControlBusy: boolean = false
  @Param saveManagerVisible: boolean = false
  @Param saveManagerBusy: boolean = false
  @Param saveManagerSummaryText: string = ''
  @Param saveManagerItems: RuntimeSaveStateListItem[] = []
  @Param sramManagerVisible: boolean = false
  @Param sramManagerBusy: boolean = false
  @Param sramManagerSummaryText: string = ''
  @Param sramManagerItems: RuntimeSramBackupListItem[] = []
  @Param cheatManagerVisible: boolean = false
  @Param cheatManagerBusy: boolean = false
  @Param cheatManagerSupported: boolean = false
  @Param cheatManagerSummaryText: string = ''
  @Param cheatManagerItems: RuntimeCheatItem[] = []
  @Param cheatDraftName: string = ''
  @Param cheatDraftCode: string = ''
  @Param coreOptionsVisible: boolean = false
  @Param coreOptionsBusy: boolean = false
  @Param coreOptionsSummaryText: string = ''
  @Param coreOptionsItems: RuntimeCoreOptionItem[] = []
  @Param portControlVisible: boolean = false
  @Param portControlSummaryText: string = ''
  @Param portAssignments: PortAssignState[] = []
  @Param selectedPortIndex: number = 0
  @Param selectedControllerDevice: number = 1
  @Event onResume?: () => void
  @Event onTerminate?: () => void
  @Event onAction?: (actionCode: string) => void
  @Event onDiskToggleEject?: () => void
  @Event onDiskSelectPrevious?: () => void
  @Event onDiskSelectNext?: () => void
  @Event onDiskRefresh?: () => void
  @Event onDiskReplaceCurrent?: () => void
  @Event onDiskAppendImage?: () => void
  @Event onSaveManagerToggle?: () => void
  @Event onSaveManagerCreate?: () => void
  @Event onSaveManagerRefresh?: () => void
  @Event onSaveManagerLoad?: (fileName: string) => void
  @Event onSaveManagerDelete?: (fileName: string) => void
  @Event onSramManagerToggle?: () => void
  @Event onSramManagerCreate?: () => void
  @Event onSramManagerRefresh?: () => void
  @Event onSramManagerLoad?: (fileName: string) => void
  @Event onSramManagerDelete?: (fileName: string) => void
  @Event onCheatManagerToggle?: () => void
  @Event onCheatManagerRefresh?: () => void
  @Event onCheatManagerAdd?: () => void
  @Event onCheatManagerDisableAll?: () => void
  @Event onCheatManagerDraftNameChange?: (value: string) => void
  @Event onCheatManagerDraftCodeChange?: (value: string) => void
  @Event onCheatManagerToggleItem?: (id: string) => void
  @Event onCheatManagerDelete?: (id: string) => void
  @Event onCoreOptionsToggle?: () => void
  @Event onCoreOptionsRefresh?: () => void
  @Event onCoreOptionAdvance?: (key: string, value: string) => void
  @Event onPortControlToggle?: () => void
  @Event onVirtualPortSelect?: (portId: number) => void
  @Event onControllerDeviceSelect?: (device: number) => void

  private readonly actions: RuntimePauseAction[] = [
    { title: '快速存档', code: '当前进度落盘', iconText: '▣', actionCode: 'quick_save' },
    { title: '快速读档', code: '加载上次存档', iconText: '◫', actionCode: 'quick_load' },
    { title: '重启游戏', code: '从头开始本局', iconText: '↻', actionCode: 'restart_game' },
    { title: '存档管理', code: '查看全部即时存档', iconText: '▤', actionCode: 'save_manager' },
    { title: '电池存档', code: '导出与载入 SRAM', iconText: '◈', actionCode: 'sram_manager' },
    { title: '金手指', code: '添加、启停与删除', iconText: '⌘', actionCode: 'cheat_manager' },
    { title: '核心选项', code: '查看并切换核心变量', iconText: '◎', actionCode: 'core_options' },
    { title: '端口控制', code: '切换虚拟端口/设备', iconText: '◬', actionCode: 'port_control' },
    { title: '按键映射', code: '自定义虚拟按键', iconText: '▥', actionCode: 'input_mapping' },
    { title: '画面风格', code: '切换滤镜与配色', iconText: '▧', actionCode: 'visual_filters' }
  ]
  private readonly waveformVerticalIndexes: number[] = [0, 1, 2, 3, 4, 5, 6, 7]
  private readonly waveformHorizontalIndexes: number[] = [0, 1, 2, 3, 4]

  @Builder
  private TopTelemetryBar() {
    Row() {
      Row({ space: 10 }) {
        Text('▣')
          .fontSize(EmuTypography.md)
          .fontColor(EmuColors.primary)

        Text('碳影 / Carbon Shade')
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.6)
      }
      .alignItems(VerticalAlign.Center)

      Text(`${this.fpsText} FPS | LOAD ${this.cpuLoadText}`)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#B3ABABAB')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(44)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#E6000000')
    .backdropBlur(22)
    .border({
      width: { bottom: 0.5 },
      color: '#22484848',
      style: BorderStyle.Solid
    })
    .align(Alignment.Top)
  }

  @Builder
  private ResumeAction() {
    Row() {
      Column({ space: 4 }) {
        Text('准备就绪')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(1.2)

        Row({ space: 8 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(EmuColors.primary)
            .shadow({ radius: 12, color: '#8800FF41', offsetX: 0, offsetY: 0 })

          Text('继续游戏')
            .fontSize(EmuTypography.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(EmuTypography.display)
        .fontColor('#88757575')
    }
    .width('100%')
    .height(72)
    .padding({ left: 20, right: 18 })
    .backgroundColor('#2200FF41')
    .border({ width: 1, color: EmuColors.primary, style: BorderStyle.Solid })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onResume?.()
    })
  }

  @Builder
  private PauseTile(item: RuntimePauseAction) {
    Column({ space: 6 }) {
      Text(item.iconText)
        .fontSize(EmuTypography.xxl)
        .fontColor('#B3E5E5E5')
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 6 })

      Text(item.title)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.code)
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontColor('#99ABABAB')
        .letterSpacing(0.4)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(96)
    .padding({ left: 14, right: 12, top: 14, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F0161616')
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(8)
    .onClick(() => {
      this.onAction?.(item.actionCode)
    })
  }

  @Builder
  private ActionGrid() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.PauseTile(this.actions[0])
        this.PauseTile(this.actions[1])
      }

      Row({ space: 12 }) {
        this.PauseTile(this.actions[2])
        this.PauseTile(this.actions[3])
      }

      Row({ space: 12 }) {
        this.PauseTile(this.actions[4])
        this.PauseTile(this.actions[5])
      }

      if (this.actions.length > 6) {
        Row({ space: 12 }) {
          this.PauseTile(this.actions[6])

          if (this.actions.length > 7) {
            this.PauseTile(this.actions[7])
          } else {
            Column()
              .layoutWeight(1)
              .height(96)
          }
        }
      }

      if (this.actions.length > 8) {
        Row({ space: 12 }) {
          this.PauseTile(this.actions[8])

          if (this.actions.length > 9) {
            this.PauseTile(this.actions[9])
          } else {
            Column()
              .layoutWeight(1)
              .height(96)
          }
        }
      }
    }
    .width('100%')
  }

  private getPortAssignmentsForPanel(): PortAssignState[] {
    if (this.portAssignments.length > 0) {
      return this.portAssignments
    }
    return [
      { portId: 0, sourceType: InputSourceType.Virtual, deviceId: '', isActive: true },
      { portId: 1, sourceType: InputSourceType.None, deviceId: '', isActive: false },
      { portId: 2, sourceType: InputSourceType.None, deviceId: '', isActive: false },
      { portId: 3, sourceType: InputSourceType.None, deviceId: '', isActive: false }
    ]
  }

  private describePortAssignmentSource(assignment: PortAssignState): string {
    if (assignment.sourceType === InputSourceType.Virtual) {
      return '虚拟手柄'
    }
    if (assignment.sourceType === InputSourceType.Keyboard) {
      return '键盘'
    }
    if (assignment.sourceType === InputSourceType.Mouse) {
      return '鼠标'
    }
    if (assignment.sourceType === InputSourceType.Gamepad) {
      return '手柄'
    }
    if (assignment.sourceType === InputSourceType.BluetoothGamepad) {
      return '蓝牙手柄'
    }
    return '未分配'
  }

  @Builder
  private PortControlPortButton(item: PortAssignState) {
    Column({ space: 4 }) {
      Text(`P${item.portId + 1}`)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.portId === this.selectedPortIndex ? EmuColors.primary : EmuColors.onSurface)

      Text(this.describePortAssignmentSource(item))
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontColor(item.sourceType === InputSourceType.Virtual ? EmuColors.primary : '#9AAEAEAE')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(72)
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(item.portId === this.selectedPortIndex ? '#1600FF41' : '#14141414')
    .border({
      width: 0.5,
      color: item.portId === this.selectedPortIndex ? EmuColors.primary : '#33484848',
      style: BorderStyle.Solid
    })
    .borderRadius(8)
    .onClick(() => {
      this.onVirtualPortSelect?.(item.portId)
    })
  }

  @Builder
  private ControllerDeviceButton(item: RuntimeControllerPortDeviceOption) {
    Column({ space: 4 }) {
      Text(item.label)
        .fontSize(EmuTypography.sm)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.device === this.selectedControllerDevice ? EmuColors.primary : EmuColors.onSurface)

      Text(item.detail)
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontColor('#9AAEAEAE')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(72)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(item.device === this.selectedControllerDevice ? '#1600FF41' : '#14141414')
    .border({
      width: 0.5,
      color: item.device === this.selectedControllerDevice ? EmuColors.primary : '#33484848',
      style: BorderStyle.Solid
    })
    .borderRadius(8)
    .onClick(() => {
      this.onControllerDeviceSelect?.(item.device)
    })
  }

  @Builder
  private PortControlPanel() {
    if (this.portControlVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('端口控制')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Button('收起')
            .width(72)
            .height(32)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onPortControlToggle?.()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.portControlSummaryText.length > 0
            ? this.portControlSummaryText
            : `当前虚拟端口 P${this.selectedPortIndex + 1}，设备 ${describeRuntimeControllerPortDevice(this.selectedControllerDevice)}。`
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text('切换端口会把虚拟手柄改绑到对应玩家口；设备类型请求是否生效取决于核心支持。')
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#88A0A0A0')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text('虚拟端口')
          .fontSize(10)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor('#99ABABAB')
          .letterSpacing(1.2)

        Row({ space: 8 }) {
          ForEach(this.getPortAssignmentsForPanel(), (item: PortAssignState) => {
            this.PortControlPortButton(item)
          }, (item: PortAssignState) => `port-${item.portId}`)
        }
        .width('100%')

        Text('手柄类型')
          .fontSize(10)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor('#99ABABAB')
          .letterSpacing(1.2)

        Row({ space: 10 }) {
          ForEach(RUNTIME_CONTROLLER_PORT_DEVICE_OPTIONS, (item: RuntimeControllerPortDeviceOption) => {
            this.ControllerDeviceButton(item)
          }, (item: RuntimeControllerPortDeviceOption) => `device-${item.device}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  @Builder
  private SaveManagerRow(item: RuntimeSaveStateListItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(item.slotLabel)
              .fontSize(EmuTypography.sm)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)

            if (item.isLatest) {
              Text('LATEST')
                .fontSize(9)
                .fontFamily('monospace')
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.primary)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#1600FF41')
                .borderRadius(8)
            }
          }
          .alignItems(VerticalAlign.Center)

          Text(item.detail)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#AEB8B8B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(item.createdLabel)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#7EA0A0A0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Button('读档')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .onClick(() => {
              this.onSaveManagerLoad?.(item.fileName)
            })

          Button('删除')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.error)
            .backgroundColor('#1AED7F64')
            .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSaveManagerDelete?.(item.fileName)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#14141414')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
  }

  @Builder
  private SaveManagerPanel() {
    if (this.saveManagerVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('存档管理')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Button('收起')
            .width(72)
            .height(32)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSaveManagerToggle?.()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.saveManagerSummaryText.length > 0
            ? this.saveManagerSummaryText
            : '当前游戏的即时存档列表。'
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Button('新建存档')
            .layoutWeight(1)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .onClick(() => {
              this.onSaveManagerCreate?.()
            })

          Button('刷新')
            .width(88)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSaveManagerRefresh?.()
            })
        }
        .width('100%')

        if (this.saveManagerBusy) {
          Text('正在同步存档...')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .width('100%')
        }

        if (!this.saveManagerBusy && this.saveManagerItems.length === 0) {
          Text('当前 ROM 还没有即时存档。')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')
        }

        if (this.saveManagerItems.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.saveManagerItems, (item: RuntimeSaveStateListItem) => {
              this.SaveManagerRow(item)
            }, (item: RuntimeSaveStateListItem) => item.id)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  @Builder
  private SramManagerRow(item: RuntimeSramBackupListItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(item.slotLabel)
              .fontSize(EmuTypography.sm)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)

            if (item.isLatest) {
              Text('LATEST')
                .fontSize(9)
                .fontFamily('monospace')
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.primary)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#1600FF41')
                .borderRadius(8)
            }
          }
          .alignItems(VerticalAlign.Center)

          Text(item.detail)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#AEB8B8B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(item.createdLabel)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#7EA0A0A0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Button('载入')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .onClick(() => {
              this.onSramManagerLoad?.(item.fileName)
            })

          Button('删除')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.error)
            .backgroundColor('#1AED7F64')
            .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSramManagerDelete?.(item.fileName)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#14141414')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
  }

  @Builder
  private SramManagerPanel() {
    if (this.sramManagerVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('电池存档')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Button('收起')
            .width(72)
            .height(32)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSramManagerToggle?.()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.sramManagerSummaryText.length > 0
            ? this.sramManagerSummaryText
            : '当前游戏的电池存档备份列表。'
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Button('导出当前')
            .layoutWeight(1)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .onClick(() => {
              this.onSramManagerCreate?.()
            })

          Button('刷新')
            .width(88)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onSramManagerRefresh?.()
            })
        }
        .width('100%')

        if (this.sramManagerBusy) {
          Text('正在同步电池存档...')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .width('100%')
        }

        if (!this.sramManagerBusy && this.sramManagerItems.length === 0) {
          Text('当前 ROM 还没有电池存档备份。')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')
        }

        if (this.sramManagerItems.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.sramManagerItems, (item: RuntimeSramBackupListItem) => {
              this.SramManagerRow(item)
            }, (item: RuntimeSramBackupListItem) => item.id)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  @Builder
  private CheatManagerRow(item: RuntimeCheatItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(item.label)
              .fontSize(EmuTypography.sm)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.enabled ? 'ON' : 'OFF')
              .fontSize(9)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor(item.enabled ? EmuColors.primary : '#B3ABABAB')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(item.enabled ? '#1600FF41' : '#14000000')
              .borderRadius(8)
          }
          .alignItems(VerticalAlign.Center)

          Text(item.code)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#AEB8B8B8')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Button(item.enabled ? '关闭' : '启用')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor(item.enabled ? '#D7D7D7' : '#004C0C')
            .backgroundColor(item.enabled ? '#14141414' : EmuColors.primary)
            .border({
              width: 0.5,
              color: item.enabled ? '#33484848' : '#6600FF41',
              style: BorderStyle.Solid
            })
            .borderRadius(8)
            .enabled(this.cheatManagerSupported)
            .onClick(() => {
              this.onCheatManagerToggleItem?.(item.id)
            })

          Button('删除')
            .width(74)
            .height(34)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.error)
            .backgroundColor('#1AED7F64')
            .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onCheatManagerDelete?.(item.id)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#14141414')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
  }

  @Builder
  private CheatManagerPanel() {
    if (this.cheatManagerVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('金手指管理')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Button('收起')
            .width(72)
            .height(32)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onCheatManagerToggle?.()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.cheatManagerSummaryText.length > 0
            ? this.cheatManagerSummaryText
            : '当前游戏的运行态金手指列表。'
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Column({ space: 8 }) {
          Text('名称')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')

          TextInput({
            text: this.cheatDraftName,
            placeholder: '例如：无限生命'
          })
            .width('100%')
            .height(40)
            .fontSize(13)
            .fontColor(EmuColors.onSurface)
            .placeholderColor('#66757575')
            .backgroundColor(EmuColors.surfaceContainerLowest)
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onChange((value: string) => {
              this.onCheatManagerDraftNameChange?.(value)
            })

          Text('代码')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')

          TextInput({
            text: this.cheatDraftCode,
            placeholder: '例如：0123-ABCD'
          })
            .width('100%')
            .height(44)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor(EmuColors.onSurface)
            .placeholderColor('#66757575')
            .backgroundColor(EmuColors.surfaceContainerLowest)
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onChange((value: string) => {
              this.onCheatManagerDraftCodeChange?.(value)
            })
        }
        .width('100%')

        Row({ space: 10 }) {
          Button('添加并启用')
            .layoutWeight(1)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .enabled(this.cheatManagerSupported)
            .onClick(() => {
              this.onCheatManagerAdd?.()
            })

          Button('全部关闭')
            .width(96)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(this.cheatManagerSupported && this.cheatManagerItems.length > 0)
            .onClick(() => {
              this.onCheatManagerDisableAll?.()
            })

          Button('刷新')
            .width(72)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onCheatManagerRefresh?.()
            })
        }
        .width('100%')

        if (this.cheatManagerBusy) {
          Text('正在同步金手指...')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .width('100%')
        }

        if (!this.cheatManagerBusy && this.cheatManagerItems.length === 0) {
          Text(
            this.cheatManagerSupported
              ? '当前 ROM 还没有运行态金手指。'
              : '当前核心未提供完整的运行态金手指接口。'
          )
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')
        }

        if (this.cheatManagerItems.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.cheatManagerItems, (item: RuntimeCheatItem) => {
              this.CheatManagerRow(item)
            }, (item: RuntimeCheatItem) => item.id)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  private getCoreOptionCurrentLabel(item: RuntimeCoreOptionItem): string {
    const values = Array.isArray(item.values) ? item.values : []
    const currentValue = typeof item.value === 'string' ? item.value.trim() : ''
    const current = values.find((value: RuntimeCoreOptionValue) => value.value === currentValue)
    const currentLabel = current?.label?.trim() ?? ''
    if (currentLabel.length > 0) {
      return currentLabel
    }
    if (currentValue.length > 0) {
      return currentValue
    }
    return '未设置'
  }

  private getCoreOptionValueDisplayText(item: RuntimeCoreOptionItem): string {
    const currentValue = typeof item.value === 'string' ? item.value.trim() : ''
    const currentLabel = this.getCoreOptionCurrentLabel(item)
    if (currentValue.length > 0 && currentLabel !== currentValue) {
      return `${currentLabel} (${currentValue})`
    }
    return currentLabel
  }

  private getNextCoreOptionValue(item: RuntimeCoreOptionItem): RuntimeCoreOptionValue | undefined {
    const values = Array.isArray(item.values) ? item.values : []
    if (values.length <= 1) {
      return undefined
    }

    const currentValue = typeof item.value === 'string' ? item.value.trim() : ''
    const currentIndex = values.findIndex((value: RuntimeCoreOptionValue) => value.value === currentValue)
    if (currentIndex < 0) {
      return values[0]
    }
    return values[(currentIndex + 1) % values.length]
  }

  private getCoreOptionNextText(item: RuntimeCoreOptionItem): string {
    const next = this.getNextCoreOptionValue(item)
    if (!next) {
      return '没有其他候选值'
    }
    const nextLabel = typeof next.label === 'string' ? next.label.trim() : ''
    if (nextLabel.length > 0 && nextLabel !== next.value) {
      return `下一项: ${nextLabel} (${next.value})`
    }
    return `下一项: ${next.value}`
  }

  @Builder
  private CoreOptionsRow(item: RuntimeCoreOptionItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 4 }) {
          Text(item.desc.length > 0 ? item.desc : item.key)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(item.key)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`当前: ${this.getCoreOptionValueDisplayText(item)}`)
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#AEB8B8B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getCoreOptionNextText(item))
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#7EA0A0A0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('切换')
          .width(74)
          .height(34)
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
          .fontColor('#004C0C')
          .backgroundColor(EmuColors.primary)
          .borderRadius(8)
          .enabled(!this.coreOptionsBusy && this.getNextCoreOptionValue(item) !== undefined)
          .onClick(() => {
            const next = this.getNextCoreOptionValue(item)
            if (next) {
              this.onCoreOptionAdvance?.(item.key, next.value)
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#14141414')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
  }

  @Builder
  private CoreOptionsPanel() {
    if (this.coreOptionsVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('核心选项')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Button('收起')
            .width(72)
            .height(32)
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .onClick(() => {
              this.onCoreOptionsToggle?.()
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.coreOptionsSummaryText.length > 0
            ? this.coreOptionsSummaryText
            : '当前核心的运行时可调参数。'
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Button('刷新')
            .width(88)
            .height(40)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(!this.coreOptionsBusy)
            .onClick(() => {
              this.onCoreOptionsRefresh?.()
            })
        }
        .width('100%')

        if (this.coreOptionsBusy) {
          Text('正在同步核心选项...')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .width('100%')
        }

        if (!this.coreOptionsBusy && this.coreOptionsItems.length === 0) {
          Text('当前核心没有运行时选项。')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor('#8AAEAEAE')
            .width('100%')
        }

        if (this.coreOptionsItems.length > 0) {
          Column({ space: 10 }) {
            ForEach(this.coreOptionsItems, (item: RuntimeCoreOptionItem) => {
              this.CoreOptionsRow(item)
            }, (item: RuntimeCoreOptionItem) => item.key)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  @Builder
  private DiskControlPanel() {
    if (this.diskControlVisible) {
      Column({ space: 10 }) {
        Row() {
          Text('换盘控制')
            .fontSize(11)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .letterSpacing(1.6)

          Text(this.diskControlModeText.length > 0 ? this.diskControlModeText : 'READY')
            .fontSize(10)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#1A00FF41')
            .borderRadius(10)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)

        Text(
          this.diskControlStatusText.length > 0
            ? this.diskControlStatusText
            : '当前核心已声明换盘接口。'
        )
          .fontSize(EmuTypography.xs)
          .fontFamily('monospace')
          .fontColor('#AEB8B8B8')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Button(this.diskEjected ? '插回光盘' : '弹出光盘')
            .layoutWeight(1)
            .height(42)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.diskEjected ? EmuColors.primary : EmuColors.onSurface)
            .backgroundColor(this.diskEjected ? '#1600FF41' : '#14141414')
            .border({
              width: 0.5,
              color: this.diskEjected ? '#6600FF41' : '#33484848',
              style: BorderStyle.Solid
            })
            .borderRadius(8)
            .enabled(!this.diskControlBusy)
            .onClick(() => {
              this.onDiskToggleEject?.()
            })

          Button('刷新')
            .width(88)
            .height(42)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#D7D7D7')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(!this.diskControlBusy)
            .onClick(() => {
              this.onDiskRefresh?.()
            })
        }
        .width('100%')

        Row({ space: 10 }) {
          Button('上一张')
            .layoutWeight(1)
            .height(48)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.diskImageCount > 1 && this.diskImageIndex > 0 ? EmuColors.onSurface : '#668A8A8A')
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(!this.diskControlBusy && this.diskImageCount > 1 && this.diskImageIndex > 0)
            .onClick(() => {
              this.onDiskSelectPrevious?.()
            })

          Column({ space: 4 }) {
            Text(
              this.diskImageCount > 0
                ? `第 ${this.diskImageIndex + 1} / ${this.diskImageCount} 张`
                : '未报告磁盘映像'
            )
              .fontSize(EmuTypography.md)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.diskEjected ? '磁盘已弹出' : '磁盘已插入')
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor(this.diskEjected ? '#FFEEB66A' : EmuColors.primary)
              .textAlign(TextAlign.Center)
          }
          .layoutWeight(1)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 6, right: 6 })
          .backgroundColor('#0D0D0D0D')
          .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
          .borderRadius(8)

          Button('下一张')
            .layoutWeight(1)
            .height(48)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(
              this.diskImageCount > 1 && this.diskImageIndex < this.diskImageCount - 1
                ? EmuColors.onSurface
                : '#668A8A8A'
            )
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(
              !this.diskControlBusy &&
                this.diskImageCount > 1 &&
                this.diskImageIndex < this.diskImageCount - 1
            )
            .onClick(() => {
              this.onDiskSelectNext?.()
            })
        }
        .width('100%')

        Row({ space: 10 }) {
          Button('替换当前盘')
            .layoutWeight(1)
            .height(42)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
            .backgroundColor('#14141414')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
            .borderRadius(8)
            .enabled(!this.diskControlBusy && this.diskImageCount > 0)
            .onClick(() => {
              this.onDiskReplaceCurrent?.()
            })

          Button('新增一张')
            .layoutWeight(1)
            .height(42)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
            .backgroundColor(EmuColors.primary)
            .borderRadius(8)
            .enabled(!this.diskControlBusy)
            .onClick(() => {
              this.onDiskAppendImage?.()
            })
        }
        .width('100%')

        if (this.diskControlBusy) {
          Text('正在导入磁盘镜像...')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#CC050505')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
      .borderRadius(8)
    }
  }

  @Builder
  private TerminateAction() {
    Row() {
      Text('⏻')
        .fontSize(EmuTypography.xxl)
        .fontColor(EmuColors.error)

      Text('结束运行')
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.error)
        .layoutWeight(1)
        .margin({ left: 10 })

      Text('终止会话')
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#AAED7F64')
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 18 })
    .backgroundColor('#1AED7F64')
    .border({ width: 0.5, color: '#66ED7F64', style: BorderStyle.Solid })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onTerminate?.()
    })
  }

  @Builder
  private PauseTelemetry() {
    Column({ space: 12 }) {
      Row() {
        Text('实时遥测')
          .fontSize(11)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCABABAB')
          .letterSpacing(1.6)

        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(EmuColors.primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .height(36)
      .padding({ left: 18, right: 18 })
      .backgroundColor(EmuColors.surfaceContainerHigh)

      Row() {
        Column({ space: 4 }) {
          Text('帧负载')
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(this.cpuLoadText)
            .fontSize(EmuTypography.lg)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('帧率')
            .fontSize(EmuTypography.xs)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B3ABABAB')
          Text(`${this.fpsText} FPS`)
            .fontSize(EmuTypography.lg)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 18, right: 18 })
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.perfStatsText.length > 0 || this.audioStatusText.length > 0 ||
        this.geometryText.length > 0 || this.regionText.length > 0 ||
        this.runtimeStateText.length > 0 || this.runtimeLoadStateText.length > 0 ||
        this.runtimeSaveStateSizeText.length > 0 || this.runtimeInputDebugText.length > 0) {
        Column({ space: 4 }) {
          if (this.perfStatsText.length > 0) {
            Text(this.perfStatsText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#B3ABABAB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.audioStatusText.length > 0) {
            Text(this.audioStatusText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#99ABABAB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.geometryText.length > 0) {
            Text(this.geometryText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#8AAEAEAE')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.regionText.length > 0) {
            Text(this.regionText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#92C0C0C0')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.runtimeStateText.length > 0) {
            Text(this.runtimeStateText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#C8E8E8E8')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.runtimeLoadStateText.length > 0) {
            Text(this.runtimeLoadStateText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#9FD0D0D0')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.runtimeSaveStateSizeText.length > 0) {
            Text(this.runtimeSaveStateSizeText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#9ACACA9A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }

          if (this.runtimeInputDebugText.length > 0) {
            Text(this.runtimeInputDebugText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontColor('#8FB8B8B8')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }

      Stack() {
        this.WaveformGrid()

        Path({
          width: 320,
          height: 64,
          commands: 'M0 40 Q20 16 40 40 T80 40 T120 40 T160 40 T200 40 T240 40 T320 40'
        })
          .fillOpacity(0)
          .stroke(EmuColors.primary)
          .strokeWidth(1.6)
          .strokeOpacity(0.72)
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
    }
    .width('100%')
    .padding({ top: 0, bottom: 18 })
    .backgroundColor('#CC050505')
    .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    .borderRadius(8)
  }

  @Builder
  private WaveformGrid() {
    Stack() {
      Row({ space: 19 }) {
        ForEach(this.waveformVerticalIndexes, (item: number) => {
          Column()
            .width(1)
            .height('100%')
            .backgroundColor('#1600FF41')
        }, (item: number) => `v-${item}`)
      }
      .width('100%')
      .height('100%')

      Column({ space: 19 }) {
        ForEach(this.waveformHorizontalIndexes, (item: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor('#1600FF41')
        }, (item: number) => `h-${item}`)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .backdropBlur(18)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [
            ['#00000000', 0],
            ['#00000000', 0.76],
            ['#1100FF41', 1]
          ]
        })

      this.TopTelemetryBar()

      Scroll() {
        Row() {
          Column({ space: 14 }) {
            Column({ space: 4 }) {
              Text('碳影 已暂停')
                .fontSize(EmuTypography.xl)
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.onSurface)

              Text(`进程：${this.processText}`)
                .fontSize(EmuTypography.xs)
                .fontFamily('monospace')
                .fontColor('#B3ABABAB')
                .letterSpacing(1.4)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 16 })
            .border({ width: { left: 3 }, color: EmuColors.primary, style: BorderStyle.Solid })
            .alignItems(HorizontalAlign.Start)

            this.ResumeAction()
            this.ActionGrid()
            this.SaveManagerPanel()
            this.SramManagerPanel()
            this.CheatManagerPanel()
            this.CoreOptionsPanel()
            this.PortControlPanel()
            this.DiskControlPanel()

            Text(this.saveStatusText)
              .fontSize(EmuTypography.xs)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Bold)
              .fontColor('#99ABABAB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            this.TerminateAction()
            this.PauseTelemetry()
          }
          .width('100%')
          .constraintSize({ maxWidth: 460 })
          .padding({ left: 24, right: 24, top: 76, bottom: 56 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}
