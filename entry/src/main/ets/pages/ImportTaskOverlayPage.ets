type FeedbackState = 'IMPORTING' | 'SUCCESS' | 'ERROR'

interface ImportOverlayColors {
  background: string
  surfaceContainerLowest: string
  surfaceContainerLow: string
  surfaceContainer: string
  surfaceContainerHigh: string
  surfaceContainerHighest: string
  primary: string
  error: string
  onSurface: string
  onSurfaceVariant: string
  outline: string
  outlineVariant: string
  secondary: string
}

interface BottomNavItem {
  key: string
  iconCode: string
  label: string
  isActive: boolean
}

function createRange(size: number): number[] {
  const values: number[] = []
  let index: number = 0
  while (index < size) {
    values.push(index)
    index += 1
  }
  return values
}

const Colors: ImportOverlayColors = {
  background: '#000000',
  surfaceContainerLowest: '#000000',
  surfaceContainerLow: '#131313',
  surfaceContainer: '#191919',
  surfaceContainerHigh: '#1F1F1F',
  surfaceContainerHighest: '#262626',
  primary: '#00FF41',
  error: '#ED7F64',
  onSurface: '#E5E5E5',
  onSurfaceVariant: '#ABABAB',
  outline: '#757575',
  outlineVariant: '#484848',
  secondary: '#9D9E9E'
}

@Entry
@Component
struct ImportTaskOverlayPage {
  @State private feedbackState: FeedbackState = 'IMPORTING'
  @State private showCancelResultDialog: boolean = false
  @State private overlayOpacity: number = 1
  @State private overlayScale: number = 1
  @State private cancelPressed: boolean = false
  @State private confirmPressed: boolean = false
  @State private retryPressed: boolean = false
  @State private cancelDialogDismissPressed: boolean = false
  @State private cancelDialogRetryPressed: boolean = false
  @State private pulseDotVisible: boolean = true
  private pulseTimer: number = -1
  private readonly horizontalGridIndexes: number[] = createRange(120)
  private readonly verticalGridIndexes: number[] = createRange(120)
  private readonly navItems: BottomNavItem[] = [
    { key: 'library', iconCode: '\uE2C8', label: 'LIBRARY', isActive: false },
    { key: 'explore', iconCode: '\uE8D6', label: 'EXPLORE', isActive: false },
    { key: 'system', iconCode: '\uE429', label: 'SYSTEM', isActive: true }
  ]

  aboutToAppear(): void {
    this.startPulseTimer()
  }

  aboutToDisappear(): void {
    this.stopPulseTimer()
  }

  private startPulseTimer(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
    this.pulseDotVisible = true
    this.pulseTimer = setInterval(() => {
      this.pulseDotVisible = !this.pulseDotVisible
    }, 420)
  }

  private stopPulseTimer(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
  }

  private switchState(nextState: FeedbackState): void {
    if (this.feedbackState === nextState) {
      return
    }
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.overlayOpacity = 0
      this.overlayScale = 0.96
    })
    setTimeout(() => {
      this.feedbackState = nextState
      this.overlayOpacity = 0
      this.overlayScale = 0.96
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.overlayOpacity = 1
        this.overlayScale = 1
      })
    }, 120)
  }

  private onCancelTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.cancelPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.cancelPressed = false
    }
  }

  private onConfirmTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.confirmPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.confirmPressed = false
    }
  }

  private onRetryTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.retryPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.retryPressed = false
    }
  }

  private onCancelDialogDismissTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.cancelDialogDismissPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.cancelDialogDismissPressed = false
    }
  }

  private onCancelDialogRetryTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.cancelDialogRetryPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.cancelDialogRetryPressed = false
    }
  }

  build() {
    Stack() {
      Column() {
        this.TopHeader()
        this.BackgroundWorkspace()
        this.BottomNavigation()
      }
      .width('100%')
      .height('100%')

      this.ImportOverlay()

      if (this.showCancelResultDialog) {
        this.CancelTaskResultDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private TopHeader() {
    Row() {
      Row({ space: 10 }) {
        Text('\uE322')
          .fontFamily('MaterialSymbolsOutlined')
          .fontColor(Colors.primary)
          .fontSize(20)

        Text('EMU_OS // 0.1')
          .fontFamily('monospace')
          .fontSize(14)
          .fontColor(Colors.primary)
          .letterSpacing(2.4)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 16 }) {
        Text('SYS_MONITOR')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#888888')
          .letterSpacing(1.2)

        Text('\uE8B8')
          .fontFamily('MaterialSymbolsOutlined')
          .fontColor(Colors.primary)
          .fontSize(20)
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backdropBlur(24)
    .backgroundColor('#D9000000')
    .border({ width: { bottom: 1 }, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private BackgroundWorkspace() {
    Stack() {
      this.PrecisionGrid(40, '#1A484848', 0.5)

      Column({ space: 20 }) {
        Column({ space: 16 }) {
          Row() {
            Text('System Load')
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(Colors.onSurfaceVariant)
              .letterSpacing(1.5)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          Row({ space: 3 }) {
            Column().width(4).height(16).backgroundColor(Colors.primary)
            Column().width(4).height(12).backgroundColor('#6600FF41')
            Column().width(4).height(24).backgroundColor(Colors.primary)
            Column().width(4).height(10).backgroundColor('#3300FF41')
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Colors.surfaceContainer)
        .border({ width: { left: 2 }, color: Colors.primary, style: BorderStyle.Solid })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: 240 })

        Row({ space: 16 }) {
          Column()
            .layoutWeight(1)
            .height(220)
            .backgroundColor('#33262626')
            .border({ width: 0.5, color: '#26FFFFFF', style: BorderStyle.Solid })
          Column()
            .layoutWeight(1)
            .height(220)
            .backgroundColor('#33262626')
            .border({ width: 0.5, color: '#26FFFFFF', style: BorderStyle.Solid })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 32, right: 32, top: 28, bottom: 28 })
    }
    .width('100%')
    .layoutWeight(1)
    .blur(22)
    .opacity(0.2)
  }

  @Builder
  private PrecisionGrid(gridSize: number, lineColor: string, lineWidth: number = 1) {
    Stack() {
      Column({ space: Math.max(0, gridSize - lineWidth) }) {
        ForEach(this.horizontalGridIndexes, (item: number) => {
          Row()
            .width('100%')
            .height(lineWidth)
            .backgroundColor(lineColor)
        }, (item: number) => `h-${item}`)
      }
      .width('100%')
      .height('100%')

      Row({ space: Math.max(0, gridSize - lineWidth) }) {
        ForEach(this.verticalGridIndexes, (item: number) => {
          Column()
            .width(lineWidth)
            .height('100%')
            .backgroundColor(lineColor)
        }, (item: number) => `v-${item}`)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ImportOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .backdropBlur(20)

      Column() {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#4D00FF41')

        if (this.feedbackState === 'IMPORTING') {
          this.ImportingState()
        } else if (this.feedbackState === 'SUCCESS') {
          this.SuccessState()
        } else {
          this.ErrorState()
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 400, minHeight: 220 })
      .backgroundColor('#FF0A0A0A')
      .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
      .shadow({ radius: 32, color: '#66000000', offsetX: 0, offsetY: 8 })
      .clip(true)
      .opacity(this.overlayOpacity)
      .scale({ x: this.overlayScale, y: this.overlayScale })
      .margin({ left: 24, right: 24 })
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ImportingState() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 2 }) {
          Text('Executing Task')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(Colors.primary)
            .letterSpacing(1.4)

          Text('正在导入 1/3')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.onSurface)
        }
        .alignItems(HorizontalAlign.Start)

        Text('EST: 02:45')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(Colors.onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 26 })

      Stack() {
        Row()
          .width('100%')
          .height(3)
          .backgroundColor(Colors.surfaceContainerHighest)

        Row()
          .width('33%')
          .height(3)
          .backgroundColor(Colors.primary)
          .shadow({ radius: 8, color: '#6600FF41', offsetX: 0, offsetY: 0 })
          .align(Alignment.Start)
      }
      .width('100%')
      .margin({ bottom: 18 })

      Row() {
        Row({ space: 8 }) {
          Row()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(Colors.primary)
            .opacity(this.pulseDotVisible ? 1 : 0.3)

          Text('Source: EXT_DISK_A')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(Colors.onSurfaceVariant)
            .letterSpacing(0.3)
        }
        .alignItems(VerticalAlign.Center)

        Text('24.4 MB/s')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(Colors.onSurfaceVariant)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 30 })

      Row() {
        Button('Cancel Task')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(Colors.onSurfaceVariant)
          .width(136)
          .height(40)
          .border({ width: 0.5, color: '#4D757575', style: BorderStyle.Solid })
          .backgroundColor(this.cancelPressed ? Colors.surfaceContainerHighest : Color.Transparent)
          .scale({ x: this.cancelPressed ? 0.95 : 1, y: this.cancelPressed ? 0.95 : 1 })
          .onTouch((event: TouchEvent) => this.onCancelTouch(event))
          .onClick(() => {
            this.showCancelResultDialog = true
          })

        Button(' ')
          .opacity(0.01)
          .width(10)
          .height(10)
          .onClick(() => this.switchState('SUCCESS'))
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: 22 })

      Row() {
        Text('PROCESS_ID: 0x882A_IMPORT')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#FF666666')

        Text('VERIFYING_CHECKSUM...')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#FF666666')
          .opacity(this.pulseDotVisible ? 1 : 0.5)
      }
      .width('100%')
      .height(30)
      .padding({ left: 16, right: 16 })
      .backgroundColor(Colors.surfaceContainerLow)
      .border({ width: { top: 0.5 }, color: '#1AFFFFFF', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 26 })
  }

  @Builder
  private SuccessState() {
    Column({ space: 0 }) {
      Row() {
        Text('\uE86C')
          .fontFamily('MaterialSymbolsOutlined')
          .fontSize(30)
          .fontColor(Colors.primary)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#0D00FF41')
      .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Text('导入成功')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.onSurface)
        .margin({ bottom: 4 })

      Text('3个项目已成功添加至游戏库')
        .fontSize(14)
        .fontColor(Colors.onSurfaceVariant)
        .margin({ bottom: 28 })

      Button('返回控制台')
        .width('100%')
        .height(36)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor(Colors.primary)
        .backgroundColor('#1A00FF41')
        .border({ width: 0.5, color: '#4D00FF41', style: BorderStyle.Solid })
        .scale({ x: this.confirmPressed ? 0.95 : 1, y: this.confirmPressed ? 0.95 : 1 })
        .onTouch((event: TouchEvent) => this.onConfirmTouch(event))
        .onClick(() => this.switchState('IMPORTING'))
    }
    .width('100%')
    .padding(28)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column({ space: 0 }) {
      Row() {
        Text('\uE002')
          .fontFamily('MaterialSymbolsOutlined')
          .fontSize(30)
          .fontColor(Colors.error)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#0DED7F64')
      .border({ width: 0.5, color: '#33ED7F64', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Text('导入失败')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.onSurface)
        .margin({ bottom: 4 })

      Text('文件格式不支持或数据包已损坏')
        .fontSize(14)
        .fontColor(Colors.onSurfaceVariant)
        .margin({ bottom: 24 })

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(36)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(Colors.onSurfaceVariant)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: '#4D757575', style: BorderStyle.Solid })
          .onClick(() => this.switchState('IMPORTING'))

        Button('再试一次')
          .layoutWeight(1)
          .height(36)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
          .fontColor(Colors.error)
          .backgroundColor(this.retryPressed ? '#3DED7F64' : '#1AED7F64')
          .border({ width: 0.5, color: '#4DED7F64', style: BorderStyle.Solid })
          .scale({ x: this.retryPressed ? 0.95 : 1, y: this.retryPressed ? 0.95 : 1 })
          .onTouch((event: TouchEvent) => this.onRetryTouch(event))
          .onClick(() => this.switchState('IMPORTING'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(28)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private CancelTaskResultDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#B3000000')
        .backdropBlur(16)

      Column({ space: 0 }) {
        Row() {
          Text('\uE002')
            .fontFamily('MaterialSymbolsOutlined')
            .fontSize(34)
            .fontColor('#FF9A81')
        }
        .width(60)
        .height(60)
        .borderRadius(16)
        .backgroundColor('#1A170F10')
        .border({ width: 0.5, color: '#4D763329', style: BorderStyle.Solid })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 28 })

        Text('导入失败')
          .fontSize(48)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.onSurface)
          .lineHeight(56)
          .margin({ bottom: 10 })

        Text('文件格式不支持或数据包已损坏')
          .fontSize(14)
          .lineHeight(22)
          .fontColor('#FFA0A4AB')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 42 })

        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Text('取消')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor('#FFE6E8EB')
          }
            .width(202)
            .height(40)
            .backgroundColor(this.cancelDialogDismissPressed ? Colors.surfaceContainerHighest : Color.Transparent)
            .border({ width: 0.5, color: '#4D3D444D', style: BorderStyle.Solid })
            .scale({
              x: this.cancelDialogDismissPressed ? 0.95 : 1,
              y: this.cancelDialogDismissPressed ? 0.95 : 1
            })
            .onTouch((event: TouchEvent) => this.onCancelDialogDismissTouch(event))
            .onClick(() => {
              this.showCancelResultDialog = false
              this.cancelDialogDismissPressed = false
            })

          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Text('\uE5D5')
                .fontFamily('MaterialSymbolsOutlined')
                .fontSize(16)
                .fontColor('#FFFF8F74')
              Text('再试一次')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontFamily('monospace')
                .fontColor('#FFFF8F74')
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
            .width(202)
            .height(40)
            .backgroundColor(this.cancelDialogRetryPressed ? '#3D4A1F19' : '#2B3A1612')
            .border({ width: 0.5, color: '#4D8D3C30', style: BorderStyle.Solid })
            .scale({
              x: this.cancelDialogRetryPressed ? 0.95 : 1,
              y: this.cancelDialogRetryPressed ? 0.95 : 1
            })
            .onTouch((event: TouchEvent) => this.onCancelDialogRetryTouch(event))
            .onClick(() => {
              this.showCancelResultDialog = false
              this.cancelDialogRetryPressed = false
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .constraintSize({ maxWidth: 540, minHeight: 388 })
      .padding({ left: 40, right: 40, top: 52, bottom: 40 })
      .backgroundColor('#FF05080D')
      .border({ width: 0.5, color: '#3A49505A', style: BorderStyle.Solid })
      .margin({ left: 24, right: 24 })
      .alignItems(HorizontalAlign.Center)
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private BottomNavigation() {
    Row() {
      ForEach(this.navItems, (item: BottomNavItem) => {
        Column({ space: 3 }) {
          Text(item.iconCode)
            .fontFamily('MaterialSymbolsOutlined')
            .fontSize(20)
            .fontColor(item.isActive ? '#FFFFFFFF' : '#FF666666')

          Text(item.label)
            .fontSize(10)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Bold)
            .fontColor(item.isActive ? '#FFFFFFFF' : '#FF666666')
            .letterSpacing(1.2)
        }
        .layoutWeight(1)
        .height(56)
        .padding({ top: 9, bottom: 10 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .border({
          width: { top: item.isActive ? 2 : 0 },
          color: item.isActive ? Colors.primary : Color.Transparent,
          style: BorderStyle.Solid
        })
      }, (item: BottomNavItem) => item.key)
    }
    .width('100%')
    .height(56)
    .padding({ left: 24, right: 24 })
    .backgroundColor('#F2000000')
    .backdropBlur(20)
    .border({ width: { top: 0.5 }, color: '#33262626', style: BorderStyle.Solid })
  }
}

@Preview
@Component
struct ImportTaskOverlayPagePreview {
  build() {
    ImportTaskOverlayPage()
  }
}
