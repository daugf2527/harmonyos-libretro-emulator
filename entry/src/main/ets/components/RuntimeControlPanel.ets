@Component
export struct RuntimeControlPanel {
  @Prop selectedPortIndex: number = 0
  @Prop currentPortLabel: ResourceStr = 'P1'
  @Prop selectedInputSourceIndex: number = 0
  @Prop currentInputSourceLabel: ResourceStr = '未分配'
  @Prop selectedCoreIndex: number = 0
  @Prop currentCoreLabel: ResourceStr = '无'
  @Prop selectedRomIndex: number = 0
  @Prop currentRomLabel: ResourceStr = '无'
  @Prop hasRomOptions: boolean = false
  @Prop switching: boolean = false
  @Prop coreCheckRunning: boolean = false
  @Prop coreCheckText: string = ''
  @Prop scalingMode: number = 2
  @Prop softwareMaxPresetIndex: number = 1
  @Prop hwRenderAllowed: boolean = true
  @Prop hideVirtualController: boolean = false
  @Prop gameRunning: boolean = false
  @Prop gamePaused: boolean = false
  @Prop runtimeSaveStatusText: string = 'SAVE_IDLE'
  @Prop soakRunning: boolean = false
  @Prop soakSecondsLeft: number = 0
  @Prop soakSummaryText: string = ''
  @Prop switchError: string = ''

  private portOptions: SelectOption[] = []
  private inputSourceOptions: SelectOption[] = []
  private coreOptions: SelectOption[] = []
  private romOptions: SelectOption[] = []
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
        Button(this.coreCheckRunning ? '验证中...' : '验证核心符号')
          .fontSize(16)
          .height(44)
          .width('100%')
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.coreCheckRunning ? '#607D8B' : '#546E7A')
          .enabled(!this.coreCheckRunning && !this.switching)
          .onClick(() => {
            this.onCoreCheck?.()
          })

        if (this.coreCheckText) {
          Text(this.coreCheckText)
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
      this.scalingMode,
      ['硬件渲染', '软件渲染', 'GLES渲染'][this.scalingMode],
      !this.switching,
      (index: number) => {
        this.onRenderModeSelect?.(index)
      }
    )
  }

  @Builder
  private SoftwareResolutionBlock() {
    if (this.scalingMode === 1) {
      this.SelectBlock(
        '软件分辨率',
        [
          { value: '480p (640x480)' },
          { value: '720p (1280x720)' },
          { value: '1080p (1920x1080)' }
        ],
        this.softwareMaxPresetIndex,
        ['480p', '720p', '1080p'][this.softwareMaxPresetIndex],
        !this.switching,
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

          Toggle({ type: ToggleType.Switch, isOn: this.hwRenderAllowed })
            .enabled(!this.switching)
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

          Toggle({ type: ToggleType.Switch, isOn: this.hideVirtualController })
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
        if (!this.gameRunning) {
          Button('开始游戏')
            .fontSize(18)
            .height(50)
            .width('100%')
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor('#4CAF50')
            .enabled(!this.switching)
            .onClick(() => {
              this.onStartGame?.()
            })
        } else {
          Row({ space: 10 }) {
            if (this.gamePaused) {
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
              .enabled(!this.switching)
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
              .enabled(!this.switching)
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
              .enabled(!this.switching)
              .onClick(() => {
                this.onQuickLoad?.()
              })
          }
          .width('100%')
        }

        Text(this.runtimeSaveStatusText)
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
        Button(this.soakRunning ? `压力测试中 ${this.soakSecondsLeft}s` : '压力测试 (10min)')
          .fontSize(14)
          .height(40)
          .width('100%')
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.soakRunning ? '#607D8B' : '#455A64')
          .enabled(!this.switching)
          .onClick(() => {
            this.onSoakToggle?.()
          })

        if (this.soakSummaryText) {
          Text(this.soakSummaryText)
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
        this.SelectBlock('选择端口', this.portOptions, this.selectedPortIndex,
          this.currentPortLabel, !this.switching, (index: number) => {
            this.onPortSelect?.(index)
          })
        this.SelectBlock('输入来源', this.inputSourceOptions, this.selectedInputSourceIndex,
          this.currentInputSourceLabel, !this.switching, (index: number) => {
            this.onInputSourceSelect?.(index)
          })
        this.SelectBlock('选择核心', this.coreOptions, this.selectedCoreIndex,
          this.currentCoreLabel, !this.switching, (index: number) => {
            this.onCoreSelect?.(index)
          })
        this.SelectBlock('选择 ROM', this.romOptions, this.selectedRomIndex,
          this.currentRomLabel, this.hasRomOptions && !this.switching, (index: number) => {
            this.onRomSelect?.(index)
          })
        this.CoreCheckBlock()
        this.RenderModeBlock()
        this.SoftwareResolutionBlock()
        this.SwitchOptionsBlock()
        this.GameActionsBlock()
        this.SoakBlock()

        if (this.switchError) {
          ListItem() {
            Text(this.switchError)
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
