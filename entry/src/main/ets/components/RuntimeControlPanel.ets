export interface RuntimeControlPanelState {
  portOptions: SelectOption[]
  selectedPortIndex: number
  currentPortLabel: ResourceStr
  inputSourceOptions: SelectOption[]
  selectedInputSourceIndex: number
  currentInputSourceLabel: ResourceStr
  coreOptions: SelectOption[]
  selectedCoreIndex: number
  currentCoreLabel: ResourceStr
  romOptions: SelectOption[]
  selectedRomIndex: number
  currentRomLabel: ResourceStr
  hasRomOptions: boolean
  switching: boolean
  coreCheckRunning: boolean
  coreCheckText: string
  scalingMode: number
  softwareMaxPresetIndex: number
  hwRenderAllowed: boolean
  hideVirtualController: boolean
  gameRunning: boolean
  gamePaused: boolean
  runtimeSaveStatusText: string
  soakRunning: boolean
  soakSecondsLeft: number
  soakSummaryText: string
  switchError: string
}

@Component
export struct RuntimeControlPanel {
  @Prop state: RuntimeControlPanelState = {
    portOptions: [],
    selectedPortIndex: 0,
    currentPortLabel: 'P1',
    inputSourceOptions: [],
    selectedInputSourceIndex: 0,
    currentInputSourceLabel: '未分配',
    coreOptions: [],
    selectedCoreIndex: 0,
    currentCoreLabel: '无',
    romOptions: [],
    selectedRomIndex: 0,
    currentRomLabel: '无',
    hasRomOptions: false,
    switching: false,
    coreCheckRunning: false,
    coreCheckText: '',
    scalingMode: 2,
    softwareMaxPresetIndex: 1,
    hwRenderAllowed: true,
    hideVirtualController: false,
    gameRunning: false,
    gamePaused: false,
    runtimeSaveStatusText: 'SAVE_IDLE',
    soakRunning: false,
    soakSecondsLeft: 0,
    soakSummaryText: '',
    switchError: ''
  }
  onClose?: () => void
  onPortSelect?: (index: number) => void
  onInputSourceSelect?: (index: number) => void
  onCoreSelect?: (index: number) => void
  onRomSelect?: (index: number) => void
  onCoreCheck?: () => void
  onRenderModeSelect?: (index: number) => void
  onSoftwareResolutionSelect?: (index: number) => void
  onHwRenderChange?: (value: boolean) => void
  onHideVirtualControllerChange?: (value: boolean) => void
  onStartGame?: () => void
  onResumeGame?: () => void
  onPauseGame?: () => void
  onRestartGame?: () => void
  onStopGame?: () => void
  onQuickSave?: () => void
  onQuickLoad?: () => void
  onSoakToggle?: () => void

  @Builder
  private SelectBlock(
    label: string,
    options: SelectOption[],
    selectedIndex: number,
    value: ResourceStr,
    enabled: boolean,
    onSelect: (index: number) => void
  ) {
    ListItem() {
      Column({ space: 8 }) {
        Text(label)
          .fontSize(14)
          .fontColor('#AAAAAA')

        Select(options)
          .selected(selectedIndex)
          .value(value)
          .font({ size: 16 })
          .fontColor(Color.White)
          .selectedOptionFont({ size: 16 })
          .optionFont({ size: 16 })
          .width('100%')
          .height(44)
          .backgroundColor('#333333')
          .borderRadius(8)
          .enabled(enabled)
          .onSelect((index: number) => {
            onSelect(index)
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  @Builder
  private CoreCheckBlock() {
    ListItem() {
      Column({ space: 8 }) {
        Button(this.state.coreCheckRunning ? '验证中...' : '验证核心符号')
          .fontSize(16)
          .height(44)
          .width('100%')
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.state.coreCheckRunning ? '#607D8B' : '#546E7A')
          .enabled(!this.state.coreCheckRunning && !this.state.switching)
          .onClick(() => {
            this.onCoreCheck?.()
          })

        if (this.state.coreCheckText) {
          Text(this.state.coreCheckText)
            .fontSize(12)
            .fontColor(Color.White)
            .padding(4)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private RenderModeBlock() {
    this.SelectBlock(
      '渲染模式',
      [
        { value: '硬件渲染 (Buffer Map)' },
        { value: '软件渲染 (CPU)' },
        { value: 'GLES渲染 (GPU)' }
      ],
      this.state.scalingMode,
      ['硬件渲染', '软件渲染', 'GLES渲染'][this.state.scalingMode],
      !this.state.switching,
      (index: number) => {
        this.onRenderModeSelect?.(index)
      }
    )
  }

  @Builder
  private SoftwareResolutionBlock() {
    if (this.state.scalingMode === 1) {
      this.SelectBlock(
        '软件分辨率',
        [
          { value: '480p (640x480)' },
          { value: '720p (1280x720)' },
          { value: '1080p (1920x1080)' }
        ],
        this.state.softwareMaxPresetIndex,
        ['480p', '720p', '1080p'][this.state.softwareMaxPresetIndex],
        !this.state.switching,
        (index: number) => {
          this.onSoftwareResolutionSelect?.(index)
        }
      )
    }
  }

  @Builder
  private SwitchOptionsBlock() {
    ListItem() {
      Column({ space: 12 }) {
        Row() {
          Column() {
            Text('允许 HW_RENDER')
              .fontSize(16)
              .fontColor(Color.White)
            Text('需核心支持，重启生效')
              .fontSize(12)
              .fontColor('#888888')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.state.hwRenderAllowed })
            .enabled(!this.state.switching)
            .onChange((value: boolean) => {
              this.onHwRenderChange?.(value)
            })
        }
        .width('100%')

        Row() {
          Column() {
            Text('隐藏虚拟手柄')
              .fontSize(16)
              .fontColor(Color.White)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.state.hideVirtualController })
            .onChange((value: boolean) => {
              this.onHideVirtualControllerChange?.(value)
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
    }
  }

  @Builder
  private GameActionsBlock() {
    ListItem() {
      Column({ space: 12 }) {
        if (!this.state.gameRunning) {
          Button('开始游戏')
            .fontSize(18)
            .height(50)
            .width('100%')
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor('#4CAF50')
            .enabled(!this.state.switching)
            .onClick(() => {
              this.onStartGame?.()
            })
        } else {
          Row({ space: 10 }) {
            if (this.state.gamePaused) {
              Button('继续')
                .fontSize(20)
                .height(50)
                .layoutWeight(1)
                .type(ButtonType.Normal)
                .borderRadius(8)
                .backgroundColor('#4CAF50')
                .onClick(() => {
                  this.onResumeGame?.()
                })
            } else {
              Button('暂停')
                .fontSize(20)
                .height(50)
                .layoutWeight(1)
                .type(ButtonType.Normal)
                .borderRadius(8)
                .backgroundColor('#FF9800')
                .onClick(() => {
                  this.onPauseGame?.()
                })
            }

            Button('重启')
              .fontSize(20)
              .height(50)
              .layoutWeight(1)
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor('#2196F3')
              .enabled(!this.state.switching)
              .onClick(() => {
                this.onRestartGame?.()
              })

            Button('停止')
              .fontSize(20)
              .height(50)
              .layoutWeight(1)
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor('#F44336')
              .margin({ left: 10 })
              .onClick(() => {
                this.onStopGame?.()
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Button('即时存档')
              .fontSize(16)
              .height(44)
              .layoutWeight(1)
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor('#2E7D32')
              .enabled(!this.state.switching)
              .onClick(() => {
                this.onQuickSave?.()
              })

            Button('即时读档')
              .fontSize(16)
              .height(44)
              .layoutWeight(1)
              .type(ButtonType.Normal)
              .borderRadius(8)
              .backgroundColor('#1565C0')
              .enabled(!this.state.switching)
              .onClick(() => {
                this.onQuickLoad?.()
              })
          }
          .width('100%')
        }

        Text(this.state.runtimeSaveStatusText)
          .fontSize(12)
          .fontColor('#AAAAAA')
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private SoakBlock() {
    ListItem() {
      Column({ space: 8 }) {
        Button(this.state.soakRunning ? `压力测试中 ${this.state.soakSecondsLeft}s` : '压力测试 (10min)')
          .fontSize(14)
          .height(40)
          .width('100%')
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.state.soakRunning ? '#607D8B' : '#455A64')
          .enabled(!this.state.switching)
          .onClick(() => {
            this.onSoakToggle?.()
          })

        if (this.state.soakSummaryText) {
          Text(this.state.soakSummaryText)
            .fontSize(12)
            .fontColor('#CCCCCC')
            .width('100%')
        }
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      Row() {
        Text('菜单 (New Arch)')
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)

        Blank()

        Button('关闭')
          .fontSize(14)
          .height(32)
          .onClick(() => {
            this.onClose?.()
          })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#E6000000')
      .alignItems(VerticalAlign.Center)

      List({ space: 16 }) {
        this.SelectBlock('选择端口', this.state.portOptions, this.state.selectedPortIndex,
          this.state.currentPortLabel, !this.state.switching, (index: number) => {
            this.onPortSelect?.(index)
          })
        this.SelectBlock('输入来源', this.state.inputSourceOptions, this.state.selectedInputSourceIndex,
          this.state.currentInputSourceLabel, !this.state.switching, (index: number) => {
            this.onInputSourceSelect?.(index)
          })
        this.SelectBlock('选择核心', this.state.coreOptions, this.state.selectedCoreIndex,
          this.state.currentCoreLabel, !this.state.switching, (index: number) => {
            this.onCoreSelect?.(index)
          })
        this.SelectBlock('选择 ROM', this.state.romOptions, this.state.selectedRomIndex,
          this.state.currentRomLabel, this.state.hasRomOptions && !this.state.switching, (index: number) => {
            this.onRomSelect?.(index)
          })
        this.CoreCheckBlock()
        this.RenderModeBlock()
        this.SoftwareResolutionBlock()
        this.SwitchOptionsBlock()
        this.GameActionsBlock()
        this.SoakBlock()

        if (this.state.switchError) {
          ListItem() {
            Text(this.state.switchError)
              .fontSize(12)
              .fontColor('#FF5252')
              .width('100%')
              .padding(8)
              .backgroundColor('#33FF0000')
              .borderRadius(4)
          }
        }

        ListItem() {
          Column().height(40).width('100%')
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Auto)
    }
    .width('86%')
    .constraintSize({ maxWidth: 360 })
    .height('100%')
    .backgroundColor('#1F1F1F')
    .shadow({ radius: 30, color: Color.Black, offsetX: -10, offsetY: 0 })
    .align(Alignment.TopEnd)
  }
}
