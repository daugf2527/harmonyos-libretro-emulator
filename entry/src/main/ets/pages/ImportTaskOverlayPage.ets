import { router } from '@kit.ArkUI'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, createIndexRange } from '../common/EmuUiTokens'

type FeedbackState = 'IMPORTING' | 'SUCCESS' | 'ERROR'

const Colors = EmuColors

@Entry
@Component
struct ImportTaskOverlayPage {
  @State private feedbackState: FeedbackState = 'IMPORTING'
  @State private overlayOpacity: number = 1
  @State private overlayScale: number = 1
  @State private cancelPressed: boolean = false
  @State private confirmPressed: boolean = false
  @State private retryPressed: boolean = false
  @State private pulseDotVisible: boolean = true
  @State private etaText: string = 'EST: 02:45'
  @State private sourceText: string = 'Source: EXT_DISK_A'
  @State private transferRateText: string = '24.4 MB/s'
  @State private processStatusText: string = 'VERIFYING_CHECKSUM...'
  @State private processIdText: string = 'PROCESS_ID: 0x882A_IMPORT'
  private pulseTimer: number = -1
  private importTimer: number = -1
  private readonly horizontalGridIndexes: number[] = createIndexRange(120)
  private readonly verticalGridIndexes: number[] = createIndexRange(120)
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: 'LIBRARY', isActive: false },
    { key: 'explore', iconName: 'explore', label: 'EXPLORE', isActive: false },
    { key: 'system', iconName: 'tune', label: 'SYSTEM', isActive: true }
  ]

  aboutToAppear(): void {
    this.startPulseTimer()
    this.startImportSimulation()
  }

  aboutToDisappear(): void {
    this.stopPulseTimer()
    this.stopImportSimulation()
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

  private applyImportProgress(nextProgress: number): void {
    this.transferRateText = `${(18 + Math.random() * 14).toFixed(1)} MB/s`
    this.processStatusText = 'VERIFYING_CHECKSUM...'
    this.sourceText = 'Source: EXT_DISK_A'

    const etaSeconds = Math.max(0, Math.ceil((100 - nextProgress) / 8))
    const minutes = Math.floor(etaSeconds / 60).toString().padStart(2, '0')
    const seconds = (etaSeconds % 60).toString().padStart(2, '0')
    this.etaText = `EST: ${minutes}:${seconds}`
  }

  private startImportSimulation(reset: boolean = true): void {
    this.stopImportSimulation()
    if (reset) {
      this.etaText = 'EST: 02:45'
      this.sourceText = 'Source: EXT_DISK_A'
      this.transferRateText = '24.4 MB/s'
      this.processStatusText = 'VERIFYING_CHECKSUM...'
      this.processIdText = 'PROCESS_ID: 0x882A_IMPORT'
      this.feedbackState = 'IMPORTING'
    }
    this.importTimer = setInterval(() => {
      const nextProgress = Math.min(33, Number(Math.random() * 6) + 28)
      this.applyImportProgress(nextProgress)

      if (nextProgress >= 33) {
        this.stopImportSimulation()
        setTimeout(() => {
          this.switchState('SUCCESS')
        }, 900)
      }
    }, 220)
  }

  private stopImportSimulation(): void {
    if (this.importTimer !== -1) {
      clearInterval(this.importTimer)
      this.importTimer = -1
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

  build() {
    Stack() {
      Column() {
        EmuHeaderBar({
          titleText: 'EMU_OS // 0.1',
          titleIcon: 'terminal',
          rightLabel: 'SYS_MONITOR',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          mutedTextColor: '#7A7A7A',
          iconSize: 18,
          rightIconSize: 18
        })
        this.BackgroundWorkspace()
        EmuBottomNav({
          items: this.navItems,
          activeFontColor: '#FFE5E5E5',
          inactiveFontColor: '#FF666666',
          indicatorStyle: 'line',
          overallOpacity: 1,
          panelBackgroundColor: '#F2000000'
        })
      }
      .width('100%')
      .height('100%')

      this.ImportOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
    .blur(28)
    .opacity(0.06)
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
          .linearGradient({
            angle: 90,
            colors: [[0x00000000, 0.0], [0x4D00FF41, 0.5], [0x00000000, 1.0]]
          })

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
      .backgroundColor('#FF080808')
      .border({ width: 0.5, color: '#1AFFFFFF', style: BorderStyle.Solid })
      .shadow({ radius: 28, color: '#52000000', offsetX: 0, offsetY: 6 })
      .clip(true)
      .opacity(this.overlayOpacity)
      .scale({ x: this.overlayScale, y: this.overlayScale })
      .margin({ left: 20, right: 20 })
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

        Text(this.etaText)
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

          Text(this.sourceText)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(Colors.onSurfaceVariant)
            .letterSpacing(0.3)
        }
        .alignItems(VerticalAlign.Center)

        Text(this.transferRateText)
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
            this.stopImportSimulation()
            this.switchState('ERROR')
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: 22 })

      Row() {
        Text(this.processIdText)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#FF666666')

        Text(this.processStatusText)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor('#FF666666')
          .opacity(this.pulseDotVisible ? 1 : 0.5)
      }
      .width('100%')
      .height(30)
      .padding({ left: 32, right: 32, top: 8, bottom: 8 })
      .backgroundColor(Colors.surfaceContainerLow)
      .border({ width: { top: 0.5 }, color: '#1AFFFFFF', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 32 })
  }

  @Builder
  private SuccessState() {
    Column({ space: 0 }) {
      Row() {
        EmuIcon({
          name: 'check_circle',
          size: 30
        })
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
        .onClick(() => {
          router.replaceUrl({ url: 'pages/LibraryPage' })
        })
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column({ space: 0 }) {
      Row() {
        EmuIcon({
          name: 'warning',
          size: 30
        })
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
          .onClick(() => this.startImportSimulation())

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
          .onClick(() => this.startImportSimulation())
      }
      .width('100%')
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

}

@Preview
@Component
struct ImportTaskOverlayPagePreview {
  build() {
    ImportTaskOverlayPage()
  }
}
