import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuMetrics, EmuTypography } from '../common/EmuUiTokens'
import {
  createDefaultInputLayoutProfile,
  getDefaultRetroButtonId,
  getRetroButtonOptionLabel,
  InputLayoutButton,
  InputLayoutProfile,
  loadInputLayoutProfile,
  resetInputLayoutProfile,
  RETRO_BUTTON_OPTIONS,
  RetroButtonOption,
  saveInputLayoutProfile
} from '../common/InputLayoutRepository'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'

interface InputMetricItem {
  label: string
  value: string
  highlight: boolean
}

interface ControllerCardItem {
  id: string
  label: string
  name: string
  status: string
  power: string
  metrics: InputMetricItem[]
  active: boolean
}

@Entry
@ComponentV2
struct InputLayoutPage {
  @Local private activeMode: string = 'center'
  @Local private savedToastVisible: boolean = false
  @Local private layoutButtons: InputLayoutButton[] = createDefaultInputLayoutProfile().buttons
  @Local private selectedButtonId: string = 'a'
  @Local private layoutStatusText: string = '本地触控布局已读到'
  @Local private layoutUpdatedAtText: string = '未保存'
  @Local private currentFoldMode: 'single' | 'dual' | 'triple' = 'single'
  private savedToastTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0
  private dragStartX: number = 0
  private dragStartY: number = 0
  private readonly editorLayoutWidth: number = 440
  private readonly editorLayoutHeight: number = 340
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('input')
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    if (!this.pageActive) {
      return
    }
    this.detectFoldMode()
  }
  private readonly controllerCards: ControllerCardItem[] = [
    {
      id: 'layout',
      label: '触控布局',
      name: '屏上按键与热区编辑',
      status: '可编辑',
      power: '本地',
      metrics: [
        { label: '作用范围', value: '运行页触控层', highlight: true },
        { label: '保存方式', value: '需手动保存', highlight: false },
        { label: '对应键位', value: '虚拟手柄键位', highlight: false }
      ],
      active: true
    },
    {
      id: 'device',
      label: '外接手柄',
      name: '实时接入状态请前往输入设备页查看',
      status: '查看入口',
      power: '跳转查看',
      metrics: [
        { label: '当前页', value: '不检测外设', highlight: false },
        { label: '设备状态', value: '输入设备页查看', highlight: false },
        { label: '更多设备', value: '输入设备页查看', highlight: false }
      ],
      active: false
    }
  ]

  aboutToAppear(): void {
    this.pageActive = true
    try {
      display.on('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('InputLayoutPage', 'Fold', `foldStatusChange on failed: ${err}`)
    }
    this.detectFoldMode()
    void this.loadSavedLayout()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
    try {
      display.off('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('InputLayoutPage', 'Fold', `foldStatusChange off failed: ${err}`)
    }
    if (this.savedToastTimer !== -1) {
      clearTimeout(this.savedToastTimer)
      this.savedToastTimer = -1
    }
  }

  private beginPageTask(): number {
    this.pageTaskToken += 1
    return this.pageTaskToken
  }

  private isCurrentPageTask(token: number): boolean {
    return this.pageActive && token === this.pageTaskToken
  }

  private getContext(): common.UIAbilityContext | undefined {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return undefined
    }
    return context
  }

  private detectFoldMode(): void {
    try {
      const foldStatus = display.getFoldStatus()
      const displayClass = display.getFoldDisplayMode()

      // 根据折叠状态和显示模式判断折叠态
      if (foldStatus === display.FoldStatus.FOLD_STATUS_FOLDED) {
        this.currentFoldMode = 'single'
      } else if (foldStatus === display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
        this.currentFoldMode = 'dual'
      } else if (displayClass === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
        this.currentFoldMode = 'triple'
      } else {
        this.currentFoldMode = 'dual'
      }
    } catch (err) {
      // 非折叠屏设备，默认单折态
      this.currentFoldMode = 'single'
    }
  }

  private async loadSavedLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = '现在还不能读取布局，请稍后再试'
      return
    }
    try {
      const profile = await loadInputLayoutProfile(context)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.applyLayoutProfile(profile, '本地触控布局已读到')
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('InputLayoutPage', 'Layout', `读取输入布局失败: ${message}`)
      this.layoutButtons = createDefaultInputLayoutProfile().buttons
      this.layoutStatusText = '本地触控布局没有读出来，请稍后重试'
      this.layoutUpdatedAtText = '未保存'
    }
  }

  private applyLayoutProfile(profile: InputLayoutProfile, statusText: string): void {
    const nextButtons: InputLayoutButton[] = []
    profile.buttons.forEach((button: InputLayoutButton) => {
      const fallback = getDefaultRetroButtonId(button.id)
      const safeRetro = Number.isFinite(button.retroButtonId) ?
        button.retroButtonId : fallback
      nextButtons.push({
        id: button.id,
        label: button.label,
        caption: button.caption,
        x: button.x,
        y: button.y,
        size: button.size,
        shape: button.shape,
        retroButtonId: safeRetro
      })
    })
    this.layoutButtons = nextButtons
    this.layoutStatusText = statusText
    this.layoutUpdatedAtText = profile.updatedAt > 0 ? this.formatDateTime(profile.updatedAt) : '未保存'
  }

  private async saveCurrentLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = '现在还不能保存布局，请稍后再试'
      return
    }
    try {
      const profile: InputLayoutProfile = {
        version: 1,
        mode: 'RETRO_PAD_TOUCH',
        updatedAt: Date.now(),
        buttons: this.layoutButtons
      }
      const savedProfile = await saveInputLayoutProfile(context, profile)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.applyLayoutProfile(savedProfile, '触控布局已保存到本地')
      this.showSavedToast()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('InputLayoutPage', 'Layout', `保存输入布局失败: ${message}`)
      this.layoutStatusText = '布局没有保存成功，请稍后重试'
    }
  }

  private async resetCurrentLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = '现在还不能重置布局，请稍后再试'
      return
    }
    try {
      const profile = await resetInputLayoutProfile(context)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.applyLayoutProfile(profile, '已重置本地触控布局')
      this.showSavedToast()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('InputLayoutPage', 'Layout', `重置输入布局失败: ${message}`)
      this.layoutStatusText = '本地触控布局没有重置成功，请稍后重试'
    }
  }

  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hour = `${date.getHours()}`.padStart(2, '0')
    const minute = `${date.getMinutes()}`.padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`
  }

  private nudgeSelectedButton(deltaX: number, deltaY: number): void {
    const idx = this.layoutButtons.findIndex((b: InputLayoutButton) => b.id === this.selectedButtonId)
    if (idx === -1) {
      return
    }
    const b = this.layoutButtons[idx]
    const horizontalLimit = Math.max(0, this.editorLayoutWidth - this.getButtonVisualWidth(b))
    const verticalLimit = Math.max(0, this.editorLayoutHeight - this.getButtonVisualHeight(b))
    const nextButtons = [...this.layoutButtons]
    nextButtons[idx] = {
      id: b.id,
      label: b.label,
      caption: b.caption,
      x: Math.max(0, Math.min(horizontalLimit, b.x + deltaX)),
      y: Math.max(0, Math.min(verticalLimit, b.y + deltaY)),
      size: b.size,
      shape: b.shape,
      retroButtonId: b.retroButtonId
    }
    this.layoutButtons = nextButtons
    this.layoutStatusText = '布局有未保存更改'
  }

  private setSelectedButtonRetroId(retroButtonId: number): void {
    const idx = this.layoutButtons.findIndex((b: InputLayoutButton) => b.id === this.selectedButtonId)
    if (idx === -1) {
      return
    }
    const b = this.layoutButtons[idx]
    if (b.retroButtonId === retroButtonId) {
      return
    }
    const nextButtons = [...this.layoutButtons]
    nextButtons[idx] = {
      id: b.id,
      label: b.label,
      caption: b.caption,
      x: b.x,
      y: b.y,
      size: b.size,
      shape: b.shape,
      retroButtonId: retroButtonId
    }
    this.layoutButtons = nextButtons
    this.layoutStatusText = '布局有未保存更改'
  }

  private captureDragStart(button: InputLayoutButton): void {
    this.dragStartX = button.x
    this.dragStartY = button.y
  }

  private applyDragUpdate(buttonId: string, offsetX: number, offsetY: number): void {
    const idx = this.layoutButtons.findIndex((b: InputLayoutButton) => b.id === buttonId)
    if (idx === -1) {
      return
    }
    const b = this.layoutButtons[idx]
    const horizontalLimit = Math.max(0, this.editorLayoutWidth - this.getButtonVisualWidth(b))
    const verticalLimit = Math.max(0, this.editorLayoutHeight - this.getButtonVisualHeight(b))
    const nextX = Math.max(0, Math.min(horizontalLimit, this.dragStartX + offsetX))
    const nextY = Math.max(0, Math.min(verticalLimit, this.dragStartY + offsetY))
    if (nextX === b.x && nextY === b.y) {
      return
    }
    const nextButtons = [...this.layoutButtons]
    nextButtons[idx] = {
      id: b.id,
      label: b.label,
      caption: b.caption,
      x: nextX,
      y: nextY,
      size: b.size,
      shape: b.shape,
      retroButtonId: b.retroButtonId
    }
    this.layoutButtons = nextButtons
  }

  private getSelectedButton(): InputLayoutButton | undefined {
    return this.layoutButtons.find((b: InputLayoutButton) => b.id === this.selectedButtonId)
  }

  private getSelectedRetroButtonId(): number {
    const button = this.getSelectedButton()
    if (button && Number.isFinite(button.retroButtonId)) {
      return button.retroButtonId
    }
    return getDefaultRetroButtonId(this.selectedButtonId)
  }

  private getRetroOptionIndex(): number {
    const current = this.getSelectedRetroButtonId()
    const idx = RETRO_BUTTON_OPTIONS.findIndex((opt: RetroButtonOption) => opt.retroButtonId === current)
    return idx >= 0 ? idx : 0
  }

  private getRetroSelectOptions(): SelectOption[] {
    return RETRO_BUTTON_OPTIONS.map((opt: RetroButtonOption): SelectOption => {
      return { value: `${opt.retroButtonId} · ${opt.caption}` }
    })
  }

  private getCurrentRetroLabel(): string {
    return getRetroButtonOptionLabel(this.getSelectedRetroButtonId())
  }

  private getButtonVisualWidth(button: InputLayoutButton): number {
    return button.shape === 'shoulder' ? 96 : button.size + 20
  }

  private getButtonVisualHeight(button: InputLayoutButton): number {
    return button.shape === 'shoulder' ? 58 : button.size + 20
  }

  private isEditorMode(): boolean {
    return this.activeMode === 'editor'
  }

  private toggleEditorMode(): void {
    this.activeMode = this.isEditorMode() ? 'center' : 'editor'
  }

  private showSavedToast(): void {
    this.savedToastVisible = true
    if (this.savedToastTimer !== -1) {
      clearTimeout(this.savedToastTimer)
    }
    this.savedToastTimer = setTimeout(() => {
      if (!this.pageActive) {
        return
      }
      this.savedToastVisible = false
      this.savedToastTimer = -1
    }, 1800)
  }

  private onBottomNavClick(key: string): void {
    if (key === 'input') {
      this.openInputDevicesPage()
      return
    }
    const route = getEmuBottomNavTargetRoute(key, 'input')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('InputLayoutPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.layoutStatusText = '这个页面现在还打不开，请稍后再试'
    })
  }

  private openInputDevicesPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/MultiplayerInputPage' }).catch((err: Error) => {
      LogHelper.error('InputLayoutPage', 'Route', `replaceUrl MultiplayerInputPage failed: ${err.message}`)
      this.layoutStatusText = '输入设备页现在还打不开，请稍后再试'
    })
  }

  @Builder
  private ControllerCard(item: ControllerCardItem) {
    Column({ space: 16 }) {
      Row() {
        Row({ space: 8 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(item.active ? EmuColors.primary : EmuColors.outline)

          Text(item.label)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(1.6)
        }
        .alignItems(VerticalAlign.Center)

        Text(item.status)
          .fontSize(EmuTypography.xs)
                    .fontColor(item.active ? EmuColors.primary : EmuColors.onSurfaceVariant)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(item.active ? '#1800FF41' : EmuColors.surfaceContainerHigh)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Column({ space: 4 }) {
          Text(item.name)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
          Text(`端口 ${item.id.toUpperCase()}`)
            .fontSize(EmuTypography.xs)
                        .fontColor('#666666')
        }
        .alignItems(HorizontalAlign.Start)

        Text(item.power)
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 8 }) {
        ForEach(item.metrics, (metric: InputMetricItem) => {
          this.MetricBox(metric)
        }, (metric: InputMetricItem) => `${item.id}-${metric.label}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private MetricBox(metric: InputMetricItem) {
    Column({ space: 4 }) {
      Text(metric.label)
        .fontSize(8)
        .fontColor('#777777')
        .letterSpacing(0.5)
      Text(metric.value)
        .fontSize(EmuTypography.sm)
                .fontColor(metric.highlight ? EmuColors.primary : EmuColors.onSurface)
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
  private NetplaySection() {
    Column({ space: 14 }) {
      Row() {
        Row({ space: 8 }) {
          Text('◎')
            .fontSize(EmuTypography.lg)
            .fontColor(EmuColors.onSurfaceVariant)
          Text('功能说明')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)
        }
        .alignItems(VerticalAlign.Center)

        Text('当前页只处理本地触控布局')
          .fontSize(EmuTypography.xs)
                    .fontColor('#666666')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 12 }) {
        Text('当前页只负责调整屏上触控按键的位置，以及每个触控按键对应的虚拟手柄键位。')
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurface)
          .width('100%')

        Text('如果你要查看外接手柄接入状态或输入源列表，请前往“输入设备”页面。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')

        Button('打开输入设备页')
          .height(36)
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
          .fontColor('#004C0C')
          .backgroundColor(EmuColors.primary)
          .borderRadius(0)
          .onClick(() => {
            this.openInputDevicesPage()
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    }
    .width('100%')
  }

  @Builder
  private InputCenterContent() {
    Scroll() {
      Column({ space: 22 }) {
        Column({ space: 14 }) {
          ForEach(this.controllerCards, (item: ControllerCardItem) => {
            this.ControllerCard(item)
          }, (item: ControllerCardItem) => item.id)
        }
        .width('100%')

        this.NetplaySection()
      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .padding({ left: 24, right: 24, top: 24, bottom: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // 单折态布局 (F态) - 保持现有垂直布局
  @Builder
  private SingleFoldLayout() {
    if (this.isEditorMode()) {
      this.EditorContent()
    } else {
      this.InputCenterContent()
    }
  }

  // 双折态布局 (M态) - 左侧按钮列表 30%，右侧预览+编辑 70%
  @Builder
  private DualFoldLayout() {
    Row() {
      // 左侧：按钮列表 (30%)
      Column({ space: 14 }) {
        Text('输入设备')
          .fontSize(EmuTypography.lg)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .padding({ left: 16, top: 16 })

        Scroll() {
          Column({ space: 14 }) {
            ForEach(this.controllerCards, (item: ControllerCardItem) => {
              this.ControllerCard(item)
            }, (item: ControllerCardItem) => item.id)

            this.NetplaySection()
          }
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('30%')
      .height('100%')
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: { right: 1 }, color: EmuMetrics.panelBorderColor, style: BorderStyle.Solid })

      // 右侧：预览区 + 编辑面板 (70%)
      Column() {
        if (this.isEditorMode()) {
          this.EditorContent()
        } else {
          // 非编辑模式显示提示
          Column({ space: 16 }) {
            EmuIcon({ name: 'settings_input_component', iconSize: 64, tone: 'muted' })
            Text('点击右上角图标进入编辑模式')
              .fontSize(EmuTypography.lg)
              .fontColor(EmuColors.onSurfaceVariant)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('70%')
      .height('100%')
    }
    .width('100%')
    .layoutWeight(1)
  }

  // 三折态布局 (G态) - 左侧按钮列表 20%，中间预览区 50%，右侧属性编辑 30%
  @Builder
  private TripleFoldLayout() {
    Row() {
      // 左侧：按钮列表 (20%)
      Column({ space: 14 }) {
        Text('输入设备')
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .padding({ left: 12, top: 12 })

        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.controllerCards, (item: ControllerCardItem) => {
              this.CompactControllerCard(item)
            }, (item: ControllerCardItem) => item.id)
          }
          .padding({ left: 12, right: 12, bottom: 12 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('20%')
      .height('100%')
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: { right: 1 }, color: EmuMetrics.panelBorderColor, style: BorderStyle.Solid })

      // 中间：预览区 (50%)
      Column() {
        if (this.isEditorMode()) {
          Stack() {
            EmuPrecisionGridBackdrop()
              .opacity(0.08)

            Column()
              .width('100%')
              .height('100%')
              .linearGradient({
                angle: 135,
                colors: [[0x332D6C5A, 0.0], [0x11131313, 0.48], [0xDD000000, 1.0]]
              })

            Column() {
              this.EditableButtonLayer()
            }
            .width('100%')
            .height('100%')
            .padding(24)
            .justifyContent(FlexAlign.Center)

            this.CalibrationMarkers()

            if (this.savedToastVisible) {
              Text('布局已保存到本地')
                .fontSize(EmuTypography.xs)
                .fontWeight(FontWeight.Bold)
                .fontColor('#004C0C')
                .letterSpacing(1.4)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .backgroundColor(EmuColors.primary)
                .borderRadius(999)
                .align(Alignment.Top)
                .margin({ top: 26 })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Black)
        } else {
          Column({ space: 16 }) {
            EmuIcon({ name: 'settings_input_component', iconSize: 64, tone: 'muted' })
            Text('点击右上角图标进入编辑模式')
              .fontSize(EmuTypography.lg)
              .fontColor(EmuColors.onSurfaceVariant)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('50%')
      .height('100%')
      .border({ width: { right: 1 }, color: EmuMetrics.panelBorderColor, style: BorderStyle.Solid })

      // 右侧：属性编辑面板 (30%)
      Column({ space: 16 }) {
        Text('按钮属性')
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .padding({ left: 16, top: 16 })

        if (this.isEditorMode()) {
          Scroll() {
            Column({ space: 16 }) {
              this.PropertyPanel()
              this.EditorActionButtons()
            }
            .padding({ left: 16, right: 16, bottom: 16 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        } else {
          Column({ space: 12 }) {
            Text('进入编辑模式后可调整按钮属性')
              .fontSize(EmuTypography.sm)
              .fontColor(EmuColors.onSurfaceVariant)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding(16)
        }
      }
      .width('30%')
      .height('100%')
      .backgroundColor(EmuColors.surfaceContainerLowest)
    }
    .width('100%')
    .layoutWeight(1)
  }

  // 紧凑型控制器卡片 (用于三折态左侧栏)
  @Builder
  private CompactControllerCard(item: ControllerCardItem) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Row()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(item.active ? EmuColors.primary : EmuColors.outline)

        Text(item.label)
          .fontSize(10)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)
      }
      .alignItems(VerticalAlign.Center)

      Text(item.name)
        .fontSize(EmuTypography.sm)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.status)
        .fontSize(10)
        .fontColor(item.active ? EmuColors.primary : EmuColors.onSurfaceVariant)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(EmuColors.surfaceContainer)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
  }

  // 属性编辑面板 (用于三折态右侧栏)
  @Builder
  private PropertyPanel() {
    Column({ space: 12 }) {
      this.PropertyRow('画布尺寸', `${this.editorLayoutWidth} X ${this.editorLayoutHeight}`)
      this.PropertyRow('作用范围', '运行页触控层')
      this.PropertyRow('当前状态', this.layoutStatusText)
      this.PropertyRow('当前按键', this.getSelectedButtonDisplayLabel())

      Column({ space: 8 }) {
        Text('对应键位')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')

        Select(this.getRetroSelectOptions())
          .selected(this.getRetroOptionIndex())
          .value(this.getCurrentRetroLabel())
          .font({ size: 11 })
          .selectedOptionFont({ size: 11 })
          .optionFont({ size: 11 })
          .optionWidth(200)
          .fontColor(EmuColors.onSurface)
          .backgroundColor('#22484848')
          .borderRadius(4)
          .height(32)
          .width('100%')
          .onSelect((index: number) => {
            const opt = RETRO_BUTTON_OPTIONS[index]
            if (opt) {
              this.setSelectedButtonRetroId(opt.retroButtonId)
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#22000000')
    .border({ width: 0.5, color: '#55484848', style: BorderStyle.Solid })
  }

  @Builder
  private PropertyRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
      Text(value)
        .fontSize(EmuTypography.xs)
        .fontColor(value === '运行页触控层' || value === this.getSelectedButtonDisplayLabel() ? EmuColors.primary : EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  // 编辑操作按钮 (用于三折态右侧栏)
  @Builder
  private EditorActionButtons() {
    Column({ space: 12 }) {
      Button('保存布局')
        .width('100%')
        .height(44)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor('#004C0C')
        .backgroundColor(EmuColors.primary)
        .onClick(() => {
          void this.saveCurrentLayout()
        })

      Button('重置布局')
        .width('100%')
        .height(44)
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurfaceVariant)
        .backgroundColor(EmuColors.surfaceContainerHigh)
        .onClick(() => {
          void this.resetCurrentLayout()
        })
    }
    .width('100%')
  }

  @Builder
  private EditorTelemetry() {
    Column({ space: 8 }) {
      this.EditorMetric('画布尺寸', `${this.editorLayoutWidth} X ${this.editorLayoutHeight}`)
      this.EditorMetric('作用范围', '运行页触控层')
      this.EditorMetric('当前状态', this.layoutStatusText)
      this.EditorMetric('当前按键', this.getSelectedButtonDisplayLabel())

      Row({ space: 6 }) {
        Text('对应键位')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .layoutWeight(1)

        Select(this.getRetroSelectOptions())
          .selected(this.getRetroOptionIndex())
          .value(this.getCurrentRetroLabel())
          .font({ size: 10 })
          .selectedOptionFont({ size: 10 })
          .optionFont({ size: 10 })
          .optionWidth(180)
          .fontColor(EmuColors.onSurface)
          .backgroundColor('#22484848')
          .borderRadius(4)
          .height(28)
          .onSelect((index: number) => {
            const opt = RETRO_BUTTON_OPTIONS[index]
            if (opt) {
              this.setSelectedButtonRetroId(opt.retroButtonId)
            }
          })
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
      .alignItems(VerticalAlign.Center)
    }
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .backgroundColor('#82000000')
    .backdropBlur(12)
    .border({ width: { left: 2 }, color: EmuColors.primary, style: BorderStyle.Solid })
    .align(Alignment.TopStart)
    .margin({ left: 24, top: 44 })
    .constraintSize({ maxWidth: 280 })
  }

  @Builder
  private EditorMetric(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
      Text(value)
        .fontSize(EmuTypography.xs)
        .fontColor(value === '运行页触控层' || value === this.getSelectedButtonDisplayLabel() ? EmuColors.primary : EmuColors.onSurface)
    }
    .width('100%')
    .constraintSize({ maxWidth: 220 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  private getSelectedButtonDisplayLabel(): string {
    const selected = this.getSelectedButton()
    if (!selected) {
      return '未选择'
    }
    return this.getEditorCaption(selected)
  }

  private getEditorCaption(button: InputLayoutButton): string {
    if (button.id === 'up' || button.id === 'down' || button.id === 'left' || button.id === 'right') {
      return '方向键'
    }
    if (button.id === 'l') {
      return '左肩键'
    }
    if (button.id === 'r') {
      return '右肩键'
    }
    if (button.id === 'a') {
      return '主按键'
    }
    if (button.id === 'b') {
      return '副按键'
    }
    return button.label
  }

  @Builder
  private EditFrame(label: string, frameWidth: number = 96) {
    Column({ space: 6 }) {
      Row()
        .width('100%')
        .height(1)
        .backgroundColor(EmuColors.primary)
      Text(label)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.primary)
        .backgroundColor(EmuColors.background)
        .padding({ left: 4, right: 4 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(frameWidth)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EditableButtonLayer() {
    Stack() {
      ForEach(this.layoutButtons, (button: InputLayoutButton) => {
        this.EditableButton(button, this.selectedButtonId === button.id)
      }, (button: InputLayoutButton) => `${button.id}:${this.selectedButtonId === button.id ? '1' : '0'}`)
    }
    .width('100%')
    .constraintSize({ maxWidth: this.editorLayoutWidth, maxHeight: this.editorLayoutHeight })
    .aspectRatio(this.editorLayoutWidth / this.editorLayoutHeight)
    .align(Alignment.Bottom)
  }

  // EditableButton 用 .position(getEditorPercentX/Y) 业务坐标(布局 profile 百分比换算),
  // 外层 EditableButtonLayer 已用 aspectRatio 承载逻辑画布。不是截图补丁式 fixed 坐标。
  // 剩余真机验证项:触控热区精度、保存后 runtime 使用一致性、横竖屏缩放命中。
  @Builder
  private EditableButton(button: InputLayoutButton, isSelected: boolean) {
    Stack() {
      Row() {
        Text(button.label)
          .fontSize(button.shape === 'shoulder' ? 12 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(button.shape === 'shoulder' ? 86 : button.size)
      .height(button.shape === 'shoulder' ? 34 : button.size)
      .borderRadius(button.shape === 'circle' ? button.size / 2 : 3)
      .backgroundColor(isSelected ? '#6600FF41' : '#33FFFFFF')
      .border({
        width: 1,
        color: isSelected ? EmuColors.primary : '#55FFFFFF',
        style: BorderStyle.Dashed
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Stack() {
        this.EditFrame(this.getEditorCaption(button), button.shape === 'shoulder' ? 118 : 92)
      }
      .align(Alignment.TopStart)
      .margin({ top: -24 })
    }
    .width(this.getButtonVisualWidth(button))
    .height(this.getButtonVisualHeight(button))
    .padding(10)
    .align(Alignment.TopStart)
    .position({ x: this.getEditorPercentX(button.x), y: this.getEditorPercentY(button.y) })
    .onClick(() => {
      this.selectedButtonId = button.id
    })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
        .onActionStart(() => {
          this.selectedButtonId = button.id
          this.captureDragStart(button)
        })
        .onActionUpdate((event: GestureEvent) => {
          this.applyDragUpdate(button.id, event.offsetX, event.offsetY)
        })
        .onActionEnd(() => {
          this.layoutStatusText = '布局有未保存更改'
        })
    )
  }

  @Builder
  private EditorBottomBar() {
    Column() {
      Row({ space: 14 }) {
        Row({ space: 8 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(EmuColors.primary)
          Text('布局编辑\n进行中')
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(1.8)
            .lineHeight(18)
        }
        .layoutWeight(1)
        .padding({ right: 12 })
        .border({ width: { right: 0.5 }, color: '#55484848', style: BorderStyle.Solid })
        .alignItems(VerticalAlign.Center)

        Button('重置')
          .height(48)
          .padding({ left: 14, right: 14 })
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurfaceVariant)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: Color.Transparent, style: BorderStyle.Solid })
          .onClick(() => {
            void this.resetCurrentLayout()
          })

        Button('保存')
          .height(48)
          .padding({ left: 22, right: 22 })
          .fontSize(EmuTypography.xl)
          .fontWeight(FontWeight.Bold)
          .fontColor('#004C0C')
          .backgroundColor(EmuColors.primary)
          .borderRadius(0)
          .onClick(() => {
            void this.saveCurrentLayout()
          })

        Row({ space: 14 }) {
          EmuIcon({ name: 'grid_view', tone: 'muted', iconSize: 22 })
          EmuIcon({ name: 'tune', tone: 'muted', iconSize: 22 })
        }
        .padding({ left: 12 })
        .border({ width: { left: 0.5 }, color: '#55484848', style: BorderStyle.Solid })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .constraintSize({ maxWidth: 520 })
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .backgroundColor('#F0191919')
      .backdropBlur(24)
      .borderRadius(6)
      .border({ width: 0.5, color: '#55484848', style: BorderStyle.Solid })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 0, right: 0, bottom: 24 })
    .align(Alignment.Bottom)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private EditorHeaderBar() {
    Row() {
      Row({ space: 12 }) {
        EmuIcon({
          name: 'memory',
          iconSize: 28
        })

        Text('碳影 / Carbon Shade')
                    .fontSize(EmuTypography.xl)
          .fontColor(EmuColors.primary)
          .letterSpacing(4)
      }
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Text('正在编辑布局...')
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('布局校准')
          .fontSize(9)
                    .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(2.4)
      }
      .alignItems(HorizontalAlign.Center)

      Row({ space: 4 }) {
        EmuIcon({
          name: 'settings_input_component',
          tone: 'muted',
          iconSize: 30
        })
      }
      .width(56)
      .justifyContent(FlexAlign.End)
      .onClick(() => {
        this.toggleEditorMode()
      })
    }
    .width('100%')
    .height(72)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backdropBlur(24)
    .backgroundColor('#F0000000')
    .border({
      width: { bottom: 1 },
      color: EmuMetrics.panelBorderColor,
      style: BorderStyle.Solid
    })
  }

  @Builder
  private CalibrationMarkers() {
    Column({ space: 6 }) {
      Column()
        .width(4)
        .height(34)
        .backgroundColor('#33484848')
      Row()
        .width(22)
        .height(1)
        .backgroundColor(EmuColors.primary)
      Column()
        .width(4)
        .height(18)
        .backgroundColor('#33484848')
      Column()
        .width(4)
        .height(18)
        .backgroundColor('#33484848')
      Row()
        .width(22)
        .height(1)
        .backgroundColor(EmuColors.primary)
      Column()
        .width(4)
        .height(34)
        .backgroundColor('#33484848')
    }
    .alignItems(HorizontalAlign.End)
    .opacity(0.55)
    .align(Alignment.End)
    .margin({ right: 14 })
  }

  @Builder
  private EditorContent() {
    Stack() {
      EmuPrecisionGridBackdrop()
        .opacity(0.08)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [[0x332D6C5A, 0.0], [0x11131313, 0.48], [0xDD000000, 1.0]]
        })

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[0x2200FF41, 0.0], [0x00131313, 0.36], [0xD9000000, 1.0]]
        })

      Column() {
        Stack() {
          this.EditorTelemetry()
          this.EditableButtonLayer()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 24, right: 24, top: 24, bottom: 16 })

        this.EditorBottomBar()
      }
      .width('100%')
      .height('100%')

      this.CalibrationMarkers()

      if (this.savedToastVisible) {
        Text('布局已保存到本地')
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
                    .fontColor('#004C0C')
          .letterSpacing(1.4)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(EmuColors.primary)
          .borderRadius(999)
          .align(Alignment.Top)
          .margin({ top: 26 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(Color.Black)
  }

  private getEditorPercentX(value: number): string {
    return `${this.clampPercent((value / this.editorLayoutWidth) * 100)}%`
  }

  private getEditorPercentY(value: number): string {
    return `${this.clampPercent((value / this.editorLayoutHeight) * 100)}%`
  }

  private clampPercent(value: number): number {
    if (value < 0) {
      return 0
    }
    if (value > 100) {
      return 100
    }
    return value
  }

  build() {
    Column() {
      if (this.isEditorMode()) {
        this.EditorHeaderBar()
      } else {
        EmuHeaderBar({
          titleText: '碳影 / Carbon Shade',
          rightLabel: '触控布局编辑',
          titleIcon: 'terminal',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18,
          onRightClick: () => {
            this.toggleEditorMode()
          }
        })
      }

      // 根据折叠态渲染不同布局
      if (this.currentFoldMode === 'single') {
        this.SingleFoldLayout()
      } else if (this.currentFoldMode === 'dual') {
        this.DualFoldLayout()
      } else {
        this.TripleFoldLayout()
      }

      if (!this.isEditorMode() && this.currentFoldMode === 'single') {
        EmuBottomNav({
          items: this.navItems,
          activeFontColor: EmuColors.primary,
          inactiveFontColor: '#FF666666',
          indicatorStyle: 'dot',
          panelBackgroundColor: '#FF000000',
          onItemClick: (key: string) => {
            this.onBottomNavClick(key)
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
