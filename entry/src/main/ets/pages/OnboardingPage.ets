import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, createIndexRange } from '../common/EmuUiTokens'
import { PageLifecycleGuard } from '../common/PageLifecycleGuard'

type PermissionStatus = 'GRANTED' | 'PENDING' | 'DENIED'

interface PermissionItem {
  key: string
  label: string
  status: PermissionStatus
}

const Colors = EmuColors

@Entry
@Component
struct OnboardingPage {
  @State private currentStep: number = 1
  @State private stepOpacity: number = 1
  @State private stepOffsetY: number = 0
  @State private scanLineOffsetY: number = 0
  @State private startButtonPressed: boolean = false
  @State private authorizeButtonPressed: boolean = false
  @State private permissions: PermissionItem[] = [
    { key: 'DOCUMENT_PICKER', label: 'DOCUMENT_PICKER', status: 'GRANTED' },
    { key: 'SANDBOX_IMPORT', label: 'SANDBOX_IMPORT', status: 'GRANTED' },
  ]
  @State private protocolStatus: string = 'VERIFIED'
  private readonly horizontalGridIndexes: number[] = createIndexRange(120)
  private readonly verticalGridIndexes: number[] = createIndexRange(120)
  private scanLineTimer: number = -1
  private lifecycle: PageLifecycleGuard = new PageLifecycleGuard()

  aboutToAppear() {
    this.lifecycle.activate()
    this.applyPermissionState('GRANTED')
    this.startScanLineAnimation()
  }

  aboutToDisappear() {
    this.lifecycle.deactivate()
    this.stopScanLineAnimation()
  }

  private switchToStep2(): void {
    if (this.currentStep === 2) {
      return
    }
    this.startButtonPressed = false
    const token = this.lifecycle.beginTask()
    const paramOut: AnimateParam = { duration: 350, curve: Curve.EaseInOut }
    const paramIn: AnimateParam = { duration: 350, curve: Curve.EaseInOut }
    this.getUIContext().animateTo(paramOut, () => {
      this.stepOpacity = 0
      this.stepOffsetY = 20
    })
    setTimeout(() => {
      if (!this.lifecycle.isCurrentTask(token)) {
        return
      }
      this.currentStep = 2
      this.stepOffsetY = 20
      this.scanLineOffsetY = 0
      this.stepOpacity = 0
      this.getUIContext().animateTo(paramIn, () => {
        this.stepOpacity = 1
        this.stepOffsetY = 0
      })
      setTimeout(() => {
        if (!this.lifecycle.isCurrentTask(token)) {
          return
        }
        if (this.currentStep === 2 && this.stepOpacity < 1) {
          this.stepOpacity = 1
          this.stepOffsetY = 0
        }
      }, 380)
    }, 350)
  }

  private openImportEntry(): void {
    this.authorizeButtonPressed = false
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/ImportEntryPage' }).catch((err: Error) => {
      console.error(`replaceUrl failed: ${err.message}`)
    })
  }

  private openLibraryPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
      console.error(`replaceUrl failed: ${err.message}`)
    })
  }

  private applyPermissionState(status: PermissionStatus): void {
    this.permissions = this.permissions.map((item: PermissionItem): PermissionItem => {
      return { key: item.key, label: item.label, status: status }
    })
    if (status === 'GRANTED') {
      this.protocolStatus = 'VERIFIED'
      return
    }
    if (status === 'DENIED') {
      this.protocolStatus = 'DENIED'
      return
    }
    this.protocolStatus = 'PENDING'
  }

  private getPermissionStatusText(item: PermissionItem): string {
    if (item.status === 'GRANTED') {
      return `${item.label}: GRANTED`
    }
    if (item.status === 'DENIED') {
      return `${item.label}: DENIED`
    }
    return `${item.label}: PENDING...`
  }

  private getPermissionDotColor(item: PermissionItem): string {
    if (item.status === 'GRANTED') {
      return Colors.primary
    }
    if (item.status === 'DENIED') {
      return '#BA573F'
    }
    return Colors.outlineVariant
  }

  private startScanLineAnimation(): void {
    if (this.scanLineTimer !== -1) {
      clearInterval(this.scanLineTimer)
      this.scanLineTimer = -1
    }
    this.scanLineOffsetY = 0
    this.scanLineTimer = this.lifecycle.trackInterval(setInterval(() => {
      if (!this.lifecycle.isActive()) {
        return
      }
      if (this.currentStep !== 2) {
        this.scanLineOffsetY = 0
        return
      }
      const nextOffset = this.scanLineOffsetY + 1
      this.scanLineOffsetY = nextOffset > 191 ? 0 : nextOffset
    }, 16))
  }

  private stopScanLineAnimation(): void {
    if (this.scanLineTimer !== -1) {
      this.lifecycle.clearIntervalId(this.scanLineTimer)
      this.scanLineTimer = -1
    }
  }

  private onStartButtonTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.startButtonPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.startButtonPressed = false
    }
  }

  private onAuthorizeButtonTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.authorizeButtonPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.authorizeButtonPressed = false
    }
  }

  build() {
    Column() {
      this.Header()

      Stack() {
        this.PrecisionGrid(40, '#1A484848', 0.5)

        Column() {
          if (this.currentStep === 1) {
            this.Step1Content()
          } else {
            this.Step2Content()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 560 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .opacity(this.stepOpacity)
        .translate({ y: this.stepOffsetY })
        .align(Alignment.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 32, right: 32 })

      this.Footer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
  private Header() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: 'memory',
          iconSize: 14
        })
        Text('EMU_CORE_v1.0')
          .fontFamily('monospace')
          .fontSize(14)
          .fontColor(Colors.primary)
          .letterSpacing(3)
      }

      Row({ space: 16 }) {
        Text(this.currentStep === 1 ? '初始设置 01' : '文件授权 02')
          .fontFamily('Inter')
          .fontSize(12)
          .fontColor(Colors.secondary)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(0)

        EmuIcon({
          name: 'settings_input_component',
          iconSize: 12
        })
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
  private Step1Content() {
    Column({ space: 0 }) {
      // Icon
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Colors.surfaceContainer)
          .borderRadius(8)
          .border({ width: 0.5, color: '#66484848', style: BorderStyle.Solid })

        EmuIcon({
          name: 'sports_esports',
          iconSize: 52
        })

        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(Colors.primary)
          .align(Alignment.TopEnd)

        Row()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#66484848')
          .align(Alignment.TopEnd)
          .margin({ top: 10, right: 1 })
      }
      .width('26%')
      .constraintSize({ minWidth: 88, maxWidth: 112 })
      .aspectRatio(1)
      .margin({ bottom: 48 })

      // Title + subtitle
      Column({ space: 16 }) {
        Text('一键找回你的童年游戏')
          .fontSize(34)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.onSurface)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('为本地 ROM / ISO 建立游戏库，保留 Core、Shader、存档等模拟器工作流。')
          .fontSize(16)
          .fontColor('#CCABABAB')
          .lineHeight(28)
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 420 })
      }
      .width('100%')
      .margin({ bottom: 64 })

      // CTA button
      Button({ type: ButtonType.Normal }) {
        Stack() {
          Row({ space: 12 }) {
            Row()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(Colors.primary)

            Text('立即开启')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.primary)
              .letterSpacing(4)
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .align(Alignment.Center)

          Row()
            .width(4)
            .height(4)
            .border({ width: { top: 1, left: 1 }, color: Colors.primary, style: BorderStyle.Solid })
            .align(Alignment.TopStart)

          Row()
            .width(4)
            .height(4)
            .border({ width: { right: 1, bottom: 1 }, color: Colors.primary, style: BorderStyle.Solid })
            .align(Alignment.BottomEnd)
        }
        .width('100%')
        .height('100%')
      }
      .width('56%')
      .constraintSize({ minWidth: 292, maxWidth: 340 })
      .height(58)
      .backgroundColor(this.startButtonPressed ? Colors.surfaceContainerHighest : Color.Transparent)
      .border({ width: 1, color: Colors.outline, style: BorderStyle.Solid })
      .borderRadius(6)
      .margin({ bottom: 96 })
      .onTouch((event: TouchEvent) => this.onStartButtonTouch(event))
      .onClick(() => this.switchToStep2())

      // Status bar
      Row() {
        Column({ space: 4 }) {
          Text('状态').fontSize(10).fontColor('#FF666666').letterSpacing(2)
          Text('本地就绪').fontSize(10).fontColor('#FF9D9E9E')
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('核心').fontSize(10).fontColor('#FF666666').letterSpacing(2)
          Text('Core 已启用').fontSize(10).fontColor('#FF9D9E9E')
        }
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('延迟').fontSize(10).fontColor('#FF666666').letterSpacing(2)
          Text('0.02ms').fontSize(10).fontFamily('monospace').fontColor(Colors.primary)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
      .padding({ left: 8, right: 8 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private Step2Content() {
    Column({ space: 0 }) {
      // Section header
      Column({ space: 16 }) {
        Row({ space: 8 }) {
          Row()
            .width(3)
            .height(16)
            .backgroundColor(Colors.primary)

          Text('需要文件访问权限')
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(Colors.primary)
            .letterSpacing(3)
        }
        .alignItems(VerticalAlign.Center)

        Text('允许访问文件，才能导入你手机里的游戏')
          .fontSize(25)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('EMU_CORE 使用系统文件选择器获取一次性文件 URI，并把 ROM 复制到应用沙箱。')
          .fontSize(14)
          .fontColor(Colors.onSurfaceVariant)
          .lineHeight(22)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: 460 })
      .padding({ left: 32, right: 32 })
      .margin({ bottom: 48 })

      // Folder icon panel
      Stack() {
        Column()
          .width('90%')
          .aspectRatio(1)
          .borderRadius(108)
          .backgroundColor('#0D00FF41')
          .blur(24)
          .align(Alignment.Center)

        Stack() {
          this.PrecisionGrid(20, '#1A484848', 0.5)

          Column({ space: 16 }) {
            EmuIcon({
              name: 'folder_open',
              iconSize: 72
            })

            Row({ space: 4 }) {
              Row().width(4).height(4).backgroundColor(Colors.primary)
              Row().width(4).height(4).backgroundColor(Colors.outlineVariant)
              Row().width(4).height(4).backgroundColor(Colors.outlineVariant)
            }
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .align(Alignment.Center)

          Row()
            .width('100%')
            .height(1)
            .backgroundColor('#3300FF41')
            .shadow({ radius: 15, color: '#6600FF41', offsetX: 0, offsetY: 0 })
            .align(Alignment.Top)
            .translate({ y: this.scanLineOffsetY })
        }
        .width('80%')
        .aspectRatio(1)
          .backgroundColor(Colors.surfaceContainerLow)
          .borderRadius(8)
          .border({ width: 0.5, color: '#66484848', style: BorderStyle.Solid })
          .align(Alignment.Center)

        Row()
          .width(16)
          .height(16)
          .border({ width: { top: 1, left: 1 }, color: '#4D00D635', style: BorderStyle.Solid })
          .align(Alignment.TopStart)
          .margin({ top: 16, left: 16 })

        Row()
          .width(16)
          .height(16)
          .border({ width: { right: 1, bottom: 1 }, color: '#4D00D635', style: BorderStyle.Solid })
          .align(Alignment.BottomEnd)
          .margin({ right: 16, bottom: 16 })
      }
      .width('58%')
      .constraintSize({ minWidth: 200, maxWidth: 240 })
      .aspectRatio(1)
      .margin({ bottom: 48 })

      // Permission list
      Column({ space: 0 }) {
        Row() {
          Text('文件访问状态')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor('#FF666666')
            .letterSpacing(1)

          Text(this.protocolStatus)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(this.protocolStatus === 'VERIFIED' ? Colors.primary : (this.protocolStatus === 'DENIED' ? '#FFBA573F' : Colors.outlineVariant))
            .letterSpacing(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 12 })

        ForEach(this.permissions, (item: PermissionItem) => {
          Row({ space: 12 }) {
            Row()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.getPermissionDotColor(item))

            Text(this.getPermissionStatusText(item))
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(Colors.onSurfaceVariant)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 8 })
        }, (item: PermissionItem) => item.key)
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
      .padding(16)
      .backgroundColor(Colors.surfaceContainerLow)
      .borderRadius(4)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .margin({ left: 32, right: 32, bottom: 48 })

      // Buttons
      Column({ space: 24 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Text('打开导入器')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.onSurface)
              .letterSpacing(4)

            EmuIcon({
              name: 'chevron_right',
              iconSize: 20
            })
              .translate({ x: this.authorizeButtonPressed ? 2 : 0 })
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.authorizeButtonPressed ? Colors.surfaceContainerHighest : Color.Transparent)
        .border({ width: 1, color: Colors.outline, style: BorderStyle.Solid })
        .borderRadius(0)
        .onTouch((event: TouchEvent) => this.onAuthorizeButtonTouch(event))
        .onClick(() => this.openImportEntry())

        Text('稍后导入，先进入游戏库')
          .fontSize(10)
          .fontColor('#FF666666')
          .letterSpacing(2)
          .onClick(() => this.openLibraryPage())
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
      .padding({ left: 32, right: 32 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private Footer() {
    Row() {
      Text('Kinetic Obsidian Protocol • Build 2405.01')
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor('#66666666')
        .letterSpacing(3)
    }
    .width('100%')
    .height(48)
    .padding({ left: 32, right: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: 1 }, color: '#1A484848', style: BorderStyle.Solid })
  }
}

@Preview
@Component
struct OnboardingPagePreview {
  build() {
    OnboardingPage()
  }
}
