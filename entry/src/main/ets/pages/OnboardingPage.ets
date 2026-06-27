import { common } from '@kit.AbilityKit'
import { fileIo as fs, picker } from '@kit.CoreFileKit'
import { display } from '@kit.ArkUI'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { GridBackground } from '../components/EmuAppShell'
import { PageLifecycleGuard } from '../common/PageLifecycleGuard'
import LogHelper from '../common/LogHelper'

type PermissionStatus = 'GRANTED' | 'PENDING' | 'DENIED'
type ProtocolStatus = 'VERIFIED' | 'DENIED' | 'PENDING'

interface PermissionItem {
  key: string
  label: string
  status: PermissionStatus
  detail: string
}

const Colors = EmuColors

@ComponentV2
struct ScanningLine {
  @Local scanOffset: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.scanOffset = 0
    // Reduced from 16ms (60fps) to 50ms (20fps) — the scanning line is
    // purely decorative and 20fps is smooth enough while cutting render
    // pressure by 67%.  Combined with shadow and blur effects on this
    // page, 60fps saturated the main-thread render pipeline, causing
    // VSync timeouts and APP_INPUT_BLOCK ANRs under native memory
    // pressure (~168 MB RSS).
    this.timer = setInterval(() => {
      const nextOffset = this.scanOffset + 1
      this.scanOffset = nextOffset > 191 ? 0 : nextOffset
    }, 50)
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  build() {
    Row()
      .width('100%')
      .height(1)
      .backgroundColor('#3300FF41')
      .shadow({ radius: 15, color: '#6600FF41', offsetX: 0, offsetY: 0 })
      .align(Alignment.Top)
      .translate({ y: this.scanOffset })
  }
}

@Entry
@ComponentV2
struct OnboardingPage {
  @Local private currentStep: number = 1
  @Local private stepOpacity: number = 1
  @Local private stepOffsetY: number = 0
  @Local private startButtonPressed: boolean = false
  @Local private authorizeButtonPressed: boolean = false
  @Local private permissions: PermissionItem[] = [
    { key: 'DOCUMENT_PICKER', label: '系统文件选择器', status: 'PENDING', detail: '正在检查是否可打开系统文件选择器' },
    { key: 'SANDBOX_IMPORT', label: '应用导入目录', status: 'PENDING', detail: '正在检查应用是否可写入导入目录' },
  ]
  @Local private protocolStatus: ProtocolStatus = 'PENDING'
  @Local private protocolDetailText: string = '正在检查导入前需要的文件访问能力'
  @Local private foldDisplayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  private lifecycle: PageLifecycleGuard = new PageLifecycleGuard()
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    if (!this.lifecycle.isActive()) {
      return
    }
    this.updateFoldDisplayMode()
  }

  aboutToAppear() {
    this.lifecycle.activate()
    this.updateFoldDisplayMode()
    try {
      display.on('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('OnboardingPage', 'FoldDetect', `foldStatusChange on failed: ${err}`)
    }
    void this.refreshImportReadiness()
  }

  aboutToDisappear() {
    try {
      display.off('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('OnboardingPage', 'FoldDetect', `foldStatusChange off failed: ${err}`)
    }
    this.lifecycle.deactivate()
  }

  private updateFoldDisplayMode(): void {
    try {
      this.foldDisplayMode = display.getFoldDisplayMode()
    } catch (err) {
      LogHelper.error('OnboardingPage', 'FoldDetect', `getFoldDisplayMode failed: ${(err as Error).message}`)
      this.foldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
    }
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
    this.lifecycle.trackTimeout(setTimeout(() => {
      if (!this.lifecycle.isCurrentTask(token)) {
        return
      }
      this.currentStep = 2
      this.stepOffsetY = 20
      this.stepOpacity = 0
      this.getUIContext().animateTo(paramIn, () => {
        this.stepOpacity = 1
        this.stepOffsetY = 0
      })
      this.lifecycle.trackTimeout(setTimeout(() => {
        if (!this.lifecycle.isCurrentTask(token)) {
          return
        }
        if (this.currentStep === 2 && this.stepOpacity < 1) {
          this.stepOpacity = 1
          this.stepOffsetY = 0
        }
      }, 380))
    }, 350))
  }

  private openImportEntry(): void {
    this.authorizeButtonPressed = false
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/ImportEntryPage' }).catch((err: Error) => {
      LogHelper.error('OnboardingPage', 'Route', `replaceUrl failed: ${err.message}`)
      this.protocolDetailText = '导入入口现在还打不开，请稍后再试'
    })
  }

  private openLibraryPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
      LogHelper.error('OnboardingPage', 'Route', `replaceUrl failed: ${err.message}`)
      this.protocolDetailText = '游戏库现在还打不开，请稍后再试'
    })
  }

  private async refreshImportReadiness(): Promise<void> {
    const token = this.lifecycle.beginTask()
    this.protocolStatus = 'PENDING'
    this.protocolDetailText = '正在检查系统文件选择器和本地导入目录'
    this.permissions = this.permissions.map((item: PermissionItem): PermissionItem => {
      return {
        key: item.key,
        label: item.label,
        status: 'PENDING',
        detail: item.key === 'DOCUMENT_PICKER' ? '正在检查是否可打开系统文件选择器' : '正在检查应用是否可写入导入目录'
      }
    })
    const nextPermissions = await this.checkImportReadiness()
    if (!this.lifecycle.isCurrentTask(token)) {
      return
    }
    this.permissions = nextPermissions
    const allGranted = nextPermissions.every((item: PermissionItem) => item.status === 'GRANTED')
    const anyDenied = nextPermissions.some((item: PermissionItem) => item.status === 'DENIED')
    if (allGranted) {
      this.protocolStatus = 'VERIFIED'
      this.protocolDetailText = '导入前置检查已通过，后续导入结果仍以实际打开和写入为准'
      return
    }
    if (anyDenied) {
      this.protocolStatus = 'DENIED'
      this.protocolDetailText = '至少还有一项导入所需的文件访问能力没有准备好'
      return
    }
    this.protocolStatus = 'PENDING'
    this.protocolDetailText = '还有文件访问能力正在检查中'
  }

  private async checkImportReadiness(): Promise<PermissionItem[]> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return [
        this.createPermissionItem('DOCUMENT_PICKER', 'DENIED', '现在还不能检查系统文件选择器，请稍后再试'),
        this.createPermissionItem('SANDBOX_IMPORT', 'DENIED', '现在还不能检查本地导入目录，请稍后再试')
      ]
    }
    const documentPickerStatus = this.checkDocumentPickerAvailability(context)
    const sandboxStatus = await this.checkSandboxImportAvailability(context)
    return [documentPickerStatus, sandboxStatus]
  }

  private createPermissionItem(key: string, status: PermissionStatus, detail: string): PermissionItem {
    return {
      key: key,
      label: key === 'DOCUMENT_PICKER' ? '系统文件选择器' : '应用导入目录',
      status: status,
      detail: detail
    }
  }

  private checkDocumentPickerAvailability(context: common.UIAbilityContext): PermissionItem {
    try {
      const documentPicker = new picker.DocumentViewPicker(context)
      if (documentPicker) {
        return this.createPermissionItem('DOCUMENT_PICKER', 'GRANTED', '已通过实例创建检查，后续仍以实际打开结果为准')
      }
    } catch (err) {
      void err
      return this.createPermissionItem('DOCUMENT_PICKER', 'DENIED', '当前设备现在还打不开系统文件选择器')
    }
    return this.createPermissionItem('DOCUMENT_PICKER', 'DENIED', '系统文件选择器现在还不能正常打开')
  }

  private async checkSandboxImportAvailability(context: common.UIAbilityContext): Promise<PermissionItem> {
    const romDir = `${context.filesDir}/roms`
    try {
      await fs.mkdir(romDir, true)
      await fs.mkdir(`${romDir}/builtin`, true)
      await fs.mkdir(`${romDir}/imported`, true)
      await fs.mkdir(`${romDir}/temp`, true)
      await fs.access(romDir)
      return this.createPermissionItem('SANDBOX_IMPORT', 'GRANTED', '已通过目录创建与访问检查，后续仍以实际写入结果为准')
    } catch (err) {
      void err
      return this.createPermissionItem('SANDBOX_IMPORT', 'DENIED', '应用现在还不能写入本地导入目录')
    }
  }

  private getPermissionStatusText(item: PermissionItem): string {
    if (item.status === 'GRANTED') {
      return `${item.label}: 当前检查通过`
    }
    if (item.status === 'DENIED') {
      return `${item.label}: 未准备好`
    }
    return `${item.label}: 检查中`
  }

  private getProtocolStatusLabel(): string {
    if (this.protocolStatus === 'VERIFIED') {
      return '当前检查通过'
    }
    if (this.protocolStatus === 'DENIED') {
      return '需要处理'
    }
    return '准备中'
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

  private getProtocolColor(): string {
    if (this.protocolStatus === 'VERIFIED') {
      return Colors.primary
    }
    if (this.protocolStatus === 'DENIED') {
      return '#FFBA573F'
    }
    return Colors.outlineVariant
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

  private getResponsiveIconSize(): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return 48
    }
    return 40
  }

  private getResponsiveSpacing(base: number): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return base
    }
    return Math.max(24, Math.floor(base * 0.72))
  }

  private getResponsiveTitleSize(): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return EmuTypography.display
    }
    return EmuTypography.xxl
  }

  private getResponsiveBodySize(): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return EmuTypography.lg
    }
    return EmuTypography.md
  }

  private getResponsiveLineHeight(): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return 26
    }
    return 22
  }

  private getResponsiveMaxWidth(): number {
    if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
      return 520
    }
    return 420
  }

  build() {
    Column() {
      this.Header()

      if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
        this.FullDisplayLayout()
      } else {
        this.CompactLayout()
      }

      this.Footer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private CompactLayout() {
    Stack() {
      GridBackground({ gridSize: 40, lineColor: '#1A484848', lineWidth: 0.5 })

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
  }

  @Builder
  private FullDisplayLayout() {
    Stack() {
      GridBackground({ gridSize: 40, lineColor: '#1A484848', lineWidth: 0.5 })

      Row() {
        Column() {
          if (this.currentStep === 1) {
            this.Step1Content()
          } else {
            this.Step2Content()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .opacity(this.stepOpacity)
        .translate({ y: this.stepOffsetY })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 64, right: 64 })
  }

  @Builder
  private Header() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: 'memory',
          iconSize: 14
        })
        Text('碳影 / Carbon Shade')
                    .fontSize(EmuTypography.md)
          .fontColor(Colors.primary)
          .letterSpacing(1.6)
      }

      Row({ space: 16 }) {
        Text(this.currentStep === 1 ? '初始设置 01' : '文件授权 02')
          .fontFamily('Inter')
          .fontSize(EmuTypography.sm)
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
          iconSize: this.getResponsiveIconSize()
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
      .margin({ bottom: this.getResponsiveSpacing(48) })

      // Title + subtitle
      Column({ space: 16 }) {
        Text('一键找回你的童年游戏')
          .fontSize(this.getResponsiveTitleSize())
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.onSurface)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('为本地 ROM / ISO 建立游戏库，保留 Core、Shader、存档等模拟器工作流。')
          .fontSize(this.getResponsiveBodySize())
          .fontColor('#CCABABAB')
          .lineHeight(this.getResponsiveLineHeight())
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: this.getResponsiveMaxWidth() })
      }
      .width('100%')
      .margin({ bottom: this.getResponsiveSpacing(64) })

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
              .fontSize(EmuTypography.md)
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
      .margin({ bottom: this.getResponsiveSpacing(96) })
      .onTouch((event: TouchEvent) => this.onStartButtonTouch(event))
      .onClick(() => this.switchToStep2())

      // Status bar
      Row() {
        Column({ space: 4 }) {
          Text('状态').fontSize(EmuTypography.xs).fontColor('#FF666666').letterSpacing(2)
          Text(this.protocolStatus === 'VERIFIED' ? '当前可尝试导入' : (this.protocolStatus === 'DENIED' ? '需要处理文件访问' : '正在准备'))
            .fontSize(EmuTypography.xs)
            .fontColor('#FF9D9E9E')
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('模式').fontSize(EmuTypography.xs).fontColor('#FF666666').letterSpacing(2)
          Text('本地文件导入').fontSize(EmuTypography.xs).fontColor('#FF9D9E9E')
        }
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('说明').fontSize(EmuTypography.xs).fontColor('#FF666666').letterSpacing(2)
          Text('不提供 ROM 下载').fontSize(EmuTypography.xs).fontColor(Colors.primary)
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
            .fontSize(EmuTypography.sm)
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

        Text('碳影使用系统文件选择器获取一次性文件 URI，并把 ROM 复制到应用沙箱。')
          .fontSize(EmuTypography.md)
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
          GridBackground({ gridSize: 20, lineColor: '#1A484848', lineWidth: 0.5 })

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

          ScanningLine()
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
            .fontSize(EmuTypography.xs)
                        .fontColor('#FF666666')
            .letterSpacing(1)

          Text(this.getProtocolStatusLabel())
            .fontSize(EmuTypography.xs)
                        .fontColor(this.getProtocolColor())
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
              .fontSize(EmuTypography.sm)
                            .fontColor(Colors.onSurfaceVariant)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 8 })

          Text(item.detail)
            .fontSize(EmuTypography.xs)
            .fontColor('#FF777777')
            .margin({ left: 18, bottom: 8 })
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }, (item: PermissionItem) => item.key)

        Text(this.protocolDetailText)
          .fontSize(EmuTypography.xs)
          .fontColor(Colors.onSurfaceVariant)
          .width('100%')
          .margin({ top: 4 })
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
              .fontSize(EmuTypography.md)
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
          .fontSize(EmuTypography.xs)
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
      Text('仅支持本地文件导入与本地游玩')
        .fontSize(9)
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
@ComponentV2
// Preview-only wrapper keeps DevEco preview isolated from the entry page.
// homecheck-disable-next-line @performance/avoid-overusing-custom-component-check
struct OnboardingPagePreview {
  build() {
    OnboardingPage()
  }
}
