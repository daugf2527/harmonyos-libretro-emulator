import { common } from '@kit.AbilityKit'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuMetrics } from '../common/EmuUiTokens'
import {
  createDefaultInputLayoutProfile,
  InputLayoutButton,
  InputLayoutProfile,
  loadInputLayoutProfile,
  resetInputLayoutProfile,
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
}

interface NetplayRoomItem {
  id: string
  name: string
  game: string
  latency: string
  players: string
  color: string
}

@Entry
@Component
struct InputLayoutPage {
  @State private activeMode: string = 'center'
  @State private savedToastVisible: boolean = false
  @State private layoutButtons: InputLayoutButton[] = createDefaultInputLayoutProfile().buttons
  @State private selectedButtonId: string = 'a'
  @State private layoutStatusText: string = 'LOCAL_LAYOUT_READY'
  @State private layoutUpdatedAtText: string = 'NOT_SAVED'
  private savedToastTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0
  private readonly editorLayoutWidth: number = 440
  private readonly editorLayoutHeight: number = 340
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: true },
    { key: 'system', iconName: 'tune', label: '系统', isActive: false }
  ]
  private readonly controllerCards: ControllerCardItem[] = [
    {
      id: 'p1',
      label: '玩家 1',
      name: '虚拟手柄 P1',
      status: '就绪',
      power: '本地',
      metrics: [
        { label: '轮询', value: 'FRAME_SYNC', highlight: false },
        { label: '延迟', value: 'INPUT_QUEUE', highlight: true },
        { label: '协议', value: 'RETRO_PAD', highlight: false }
      ]
    },
    {
      id: 'p2',
      label: '外接手柄',
      name: '等待连接手柄',
      status: '未绑定',
      power: '无设备',
      metrics: [
        { label: '轮询', value: '--', highlight: false },
        { label: '延迟', value: '--', highlight: false },
        { label: '协议', value: 'HID_WAIT', highlight: false }
      ]
    }
  ]
  private readonly rooms: NetplayRoomItem[] = [
    { id: 'local', name: '本地游玩', game: '当前运行输入桥', latency: '0ms', players: '1 / 1', color: EmuColors.primary },
    { id: 'netplay', name: 'Netplay 联机', game: '外部服务未配置', latency: '--', players: '离线', color: EmuColors.error }
  ]

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadSavedLayout()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
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

  private async loadSavedLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = 'CONTEXT_MISSING'
      return
    }
    const profile = await loadInputLayoutProfile(context)
    if (!this.isCurrentPageTask(token)) {
      return
    }
    this.applyLayoutProfile(profile, 'LOCAL_LAYOUT_READY')
  }

  private applyLayoutProfile(profile: InputLayoutProfile, statusText: string): void {
    const nextButtons: InputLayoutButton[] = []
    profile.buttons.forEach((button: InputLayoutButton) => {
      nextButtons.push({
        id: button.id,
        label: button.label,
        caption: button.caption,
        x: button.x,
        y: button.y,
        size: button.size,
        shape: button.shape
      })
    })
    this.layoutButtons = nextButtons
    this.layoutStatusText = statusText
    this.layoutUpdatedAtText = profile.updatedAt > 0 ? this.formatDateTime(profile.updatedAt) : 'NOT_SAVED'
  }

  private async saveCurrentLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = 'CONTEXT_MISSING'
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
      this.applyLayoutProfile(savedProfile, 'LOCAL_LAYOUT_SAVED')
      this.showSavedToast()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('InputLayoutPage', 'Layout', `保存输入布局失败: ${message}`)
      this.layoutStatusText = 'LOCAL_LAYOUT_SAVE_FAILED'
    }
  }

  private async resetCurrentLayout(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.layoutStatusText = 'CONTEXT_MISSING'
      return
    }
    try {
      const profile = await resetInputLayoutProfile(context)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.applyLayoutProfile(profile, '已重置本地布局')
      this.showSavedToast()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('InputLayoutPage', 'Layout', `重置输入布局失败: ${message}`)
      this.layoutStatusText = '本地布局重置失败'
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
      shape: b.shape
    }
    this.layoutButtons = nextButtons
    this.layoutStatusText = 'LOCAL_LAYOUT_DIRTY'
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
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/MultiplayerInputPage' }).catch((err: Error) => {
        console.error(`[InputLayoutPage] replaceUrl MultiplayerInputPage failed: ${err.message}`)
      })
      return
    }
    const route = getEmuBottomNavTargetRoute(key, 'input')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      console.error(`[InputLayoutPage] replaceUrl ${route} failed: ${err.message}`)
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
            .backgroundColor(item.status === 'READY' ? EmuColors.primary : EmuColors.outline)

          Text(item.label)
            .fontSize(10)
                        .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(1.6)
        }
        .alignItems(VerticalAlign.Center)

        Text(item.status)
          .fontSize(10)
                    .fontColor(item.status === 'READY' ? EmuColors.primary : EmuColors.onSurfaceVariant)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(item.status === 'READY' ? '#1800FF41' : EmuColors.surfaceContainerHigh)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Column({ space: 4 }) {
          Text(item.name)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
          Text(`ID: ${item.id.toUpperCase()}_INPUT_BUS`)
            .fontSize(10)
                        .fontColor('#666666')
        }
        .alignItems(HorizontalAlign.Start)

        Text(item.power)
          .fontSize(10)
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
        .fontSize(12)
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
            .fontSize(16)
            .fontColor(EmuColors.onSurfaceVariant)
          Text('Netplay 联机')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .letterSpacing(2)
        }
        .alignItems(VerticalAlign.Center)

        Text('中继：未配置')
          .fontSize(10)
                    .fontColor('#666666')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 1 }) {
        ForEach(this.rooms, (room: NetplayRoomItem) => {
          this.RoomRow(room)
        }, (room: NetplayRoomItem) => room.id)
      }
      .width('100%')
      .border({ width: 0.5, color: '#26333333', style: BorderStyle.Solid })
    }
    .width('100%')
  }

  @Builder
  private RoomRow(room: NetplayRoomItem) {
    Row({ space: 16 }) {
      Row()
        .width(48)
        .height(48)
        .backgroundColor(room.color)
        .opacity(0.32)
        .border({ width: 0.5, color: '#6600FF41', style: BorderStyle.Solid })

      Column({ space: 4 }) {
        Text(room.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
        Text(`Game: ${room.game}`)
          .fontSize(10)
                    .fontColor('#666666')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('Latency')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.latency)
          .fontSize(12)
                    .fontColor(room.color)
      }
      .alignItems(HorizontalAlign.End)

      Column({ space: 4 }) {
        Text('Players')
          .fontSize(9)
          .fontColor('#666666')
        Text(room.players)
          .fontSize(12)
                    .fontColor(EmuColors.onSurface)
      }
      .alignItems(HorizontalAlign.End)

      Text('›')
        .fontSize(24)
        .fontColor(EmuColors.onSurfaceVariant)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainerLowest)
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

  @Builder
  private EditorTelemetry() {
    Column({ space: 8 }) {
      this.EditorMetric('Resolution', `${this.editorLayoutWidth} X ${this.editorLayoutHeight}`)
      this.EditorMetric('Latency', 'INPUT_QUEUE')
      this.EditorMetric('Input Poll', this.layoutStatusText)
      this.EditorMetric('Selected', this.selectedButtonId.toUpperCase())
    }
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .backgroundColor('#82000000')
    .backdropBlur(12)
    .border({ width: { left: 2 }, color: EmuColors.primary, style: BorderStyle.Solid })
    .align(Alignment.TopStart)
    .margin({ left: 24, top: 44 })
    .constraintSize({ maxWidth: 330 })
  }

  @Builder
  private EditorMetric(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(10)
                .fontColor(EmuColors.onSurfaceVariant)
      Text(value)
        .fontSize(10)
                .fontColor(value === 'INPUT_QUEUE' || value === this.selectedButtonId.toUpperCase() ? EmuColors.primary : EmuColors.onSurface)
    }
    .width('100%')
    .constraintSize({ maxWidth: 220 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  private getEditorCaption(button: InputLayoutButton): string {
    if (button.id === 'up' || button.id === 'down' || button.id === 'left' || button.id === 'right') {
      return 'DIRECTIONAL'
    }
    if (button.id === 'l') {
      return 'LEFT_SHOULDER'
    }
    if (button.id === 'r') {
      return 'RIGHT_SHOULDER'
    }
    if (button.id === 'a') {
      return 'PRIMARY'
    }
    if (button.id === 'b') {
      return 'SECONDARY'
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
        .fontSize(10)
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
          Text('EDITOR\nACTIVE')
            .fontSize(10)
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
          .fontSize(18)
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
                    .fontSize(18)
          .fontColor(EmuColors.primary)
          .letterSpacing(4)
      }
      .alignItems(VerticalAlign.Center)

      Column({ space: 3 }) {
        Text('正在编辑布局...')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('CALIBRATION MODE')
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
        Text('INPUT_LAYOUT_SAVED')
          .fontSize(10)
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
          rightLabel: '输入映射与联机中心',
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

      if (this.isEditorMode()) {
        this.EditorContent()
      } else {
        this.InputCenterContent()
      }

      if (!this.isEditorMode()) {
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
