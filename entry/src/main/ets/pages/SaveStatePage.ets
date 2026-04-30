import testNapi from 'libentry.so'
import { common } from '@kit.AbilityKit'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors } from '../common/EmuUiTokens'
import {
  deleteSaveStateItem,
  listSaveStateItems,
  readSaveStateData,
  SaveStateManifestItem,
  saveStateData
} from '../common/SaveStateRepository'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'

interface SaveStateNapi {
  refactoredSaveState(): ArrayBuffer | null
  refactoredLoadState(data: ArrayBuffer): boolean
}

interface SaveSlotItem {
  id: string
  fileName: string
  slotLabel: string
  detail: string
  durationLabel: string
  isActive: boolean
  coverColor: string
}

interface SaveStateRouteParams {
  romFile?: string
}

const nativeApi = testNapi as SaveStateNapi

@Entry
@Component
struct SaveStatePage {
  @State private saveItems: SaveSlotItem[] = []
  @State private selectedSaveFile: string = ''
  @State private showDeleteConfirm: boolean = false
  @State private toastMessage: string = ''
  @State private showToast: boolean = false
  @State private syncStatusText: string = 'LOCAL_ARCHIVE'
  @State private loading: boolean = false
  @State private currentRomFile: string = ''
  private toastTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: false },
    { key: 'system', iconName: 'tune', label: '系统', isActive: true }
  ]
  private readonly coverColors: string[] = ['#274530', '#27405E', '#4A3628', '#39364A']

  aboutToAppear(): void {
    this.pageActive = true
    this.currentRomFile = this.resolveCurrentRomFile()
    void this.refreshSaveItems()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
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

  private resolveCurrentRomFile(): string {
    const params = this.getUIContext().getRouter().getParams() as SaveStateRouteParams
    if (typeof params?.romFile === 'string' && params.romFile.length > 0) {
      return params.romFile
    }
    return ''
  }

  private async refreshSaveItems(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.saveItems = []
      this.syncStatusText = 'CONTEXT_MISSING'
      return
    }
    this.loading = true
    try {
      const entries = await listSaveStateItems(context)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const visibleEntries = this.filterSaveItemsForCurrentRom(entries)
      const nextItems: SaveSlotItem[] = []
      visibleEntries.forEach((item: SaveStateManifestItem, index: number) => {
        nextItems.push(this.buildSaveSlot(item, index))
      })
      this.saveItems = nextItems
      this.syncStatusText = this.buildSaveStatusText(nextItems.length)
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.warn('SaveStatePage', 'Save', `读取存档目录失败: ${message}`)
      this.saveItems = []
      this.syncStatusText = 'NO_SAVE_ARCHIVE'
    }
    if (!this.isCurrentPageTask(token)) {
      return
    }
    this.loading = false
  }

  private filterSaveItemsForCurrentRom(items: SaveStateManifestItem[]): SaveStateManifestItem[] {
    if (this.currentRomFile.length === 0) {
      return items
    }
    const filtered: SaveStateManifestItem[] = []
    items.forEach((item: SaveStateManifestItem) => {
      if (item.romFile === this.currentRomFile) {
        filtered.push(item)
      }
    })
    return filtered
  }

  private buildSaveStatusText(count: number): string {
    if (count > 0) {
      return this.currentRomFile.length > 0 ? 'LOCAL_ROM_INDEX_READY' : 'LOCAL_INDEX_READY'
    }
    return this.currentRomFile.length > 0 ? 'NO_SAVE_FOR_CURRENT_ROM' : 'NO_SAVE_ARCHIVE'
  }

  private buildSaveSlot(item: SaveStateManifestItem, index: number): SaveSlotItem {
    const slotNumber = (index + 1).toString().padStart(3, '0')
    const colorIndex = index % this.coverColors.length
    return {
      id: item.id,
      fileName: item.fileName,
      slotLabel: `SLOT_${slotNumber}`,
      detail: `${this.normalizeTitle(item.fileName)} | ${this.formatBytes(item.byteLength)}`,
      durationLabel: item.createdAt > 0 ? this.formatDateTime(item.createdAt) : 'LOCAL',
      isActive: index === 0,
      coverColor: this.coverColors[colorIndex]
    }
  }

  private normalizeTitle(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
    const cleaned = baseName.replace(/[_-]+/g, ' ')
    return cleaned.length > 0 ? cleaned : 'Unknown Save'
  }

  private formatBytes(byteLength: number): string {
    if (byteLength <= 0) {
      return '0 B'
    }
    if (byteLength < 1024) {
      return `${byteLength} B`
    }
    return `${Math.floor(byteLength / 1024)} KB`
  }

  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hour = `${date.getHours()}`.padStart(2, '0')
    const minute = `${date.getMinutes()}`.padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`
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

  private requestDelete(fileName: string): void {
    this.selectedSaveFile = fileName
    this.showDeleteConfirm = true
  }

  private async confirmDelete(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context || this.selectedSaveFile.length === 0) {
      this.showDeleteConfirm = false
      return
    }
    const targetFile = this.selectedSaveFile
    this.showDeleteConfirm = false
    try {
      await deleteSaveStateItem(context, targetFile)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.showToastMessage('Archive Deleted Successfully')
      await this.refreshSaveItems()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('SAVE_DELETE_FAILED')
    }
  }

  private async quickSave(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.showToastMessage('CONTEXT_MISSING')
      return
    }
    try {
      const stateData = nativeApi.refactoredSaveState()
      if (!stateData || stateData.byteLength <= 0) {
        this.showToastMessage('SAVE_STATE_UNAVAILABLE')
        return
      }
      await saveStateData(context, stateData, this.currentRomFile)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.showToastMessage('SAVE_STATE_WRITTEN')
      await this.refreshSaveItems()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `写入即时存档失败: ${message}`)
      this.showToastMessage('SAVE_STATE_FAILED')
    }
  }

  private async loadSave(fileName: string): Promise<void> {
    const context = this.getContext()
    if (!context) {
      this.showToastMessage('CONTEXT_MISSING')
      return
    }
    try {
      const stateData = readSaveStateData(context, fileName)
      const loaded = nativeApi.refactoredLoadState(stateData)
      this.showToastMessage(loaded ? 'SAVE_STATE_LOADED' : 'LOAD_STATE_REJECTED')
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `读取即时存档失败: ${message}`)
      this.showToastMessage('LOAD_STATE_FAILED')
    }
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[SaveStatePage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[SaveStatePage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  @Builder
  private TelemetryStrip() {
    Row() {
      Row({ space: 18 }) {
        this.StatusChip('Storage', 'APP_FILES')
        this.StatusChip('Slots', `${this.saveItems.length}/99`)
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(EmuColors.primary)

        Text(this.loading ? '正在读取本地存档...' : this.syncStatusText)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.primary)
          .letterSpacing(0.8)
      }
      .alignItems(VerticalAlign.Center)

      Button('QUICK SAVE')
        .height(30)
        .fontSize(10)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Bold)
        .fontColor('#004C0C')
        .backgroundColor(EmuColors.primary)
        .onClick(() => {
          void this.quickSave()
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 24, right: 24 })
    .backgroundColor('#0E0E0E')
    .border({ width: { bottom: 0.5 }, color: '#262626', style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private StatusChip(label: string, value: string) {
    Row({ space: 8 }) {
      Row()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(EmuColors.primary)

      Text(`${label}: ${value}`)
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1.2)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SaveSlotRow(item: SaveSlotItem) {
    Stack() {
      Row() {
        Row({ space: 8 }) {
          this.SwipeAction('读档', EmuColors.primary, item.fileName)
          this.SwipeAction('删除', EmuColors.error, item.fileName)
        }
        .align(Alignment.BottomEnd)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)

      Row({ space: 16 }) {
        Stack() {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor(item.coverColor)
            .opacity(0.72)

          Row()
            .width('100%')
            .height(2)
            .backgroundColor(EmuColors.primary)
            .align(Alignment.Center)
            .opacity(item.isActive ? 0.78 : 0.18)
        }
        .width(80)
        .height(56)
        .borderRadius(3)
        .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Solid })
        .clip(true)

        Column({ space: 4 }) {
          Text(this.normalizeTitle(item.fileName))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${item.slotLabel} | ${item.detail}`)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(EmuColors.onSurfaceVariant)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.DurationBadge(item)

          Text('≡')
            .fontSize(14)
            .fontColor(EmuColors.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .height(96)
      .padding({ left: item.isActive ? 18 : 24, right: 24 })
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: { bottom: 0.5 }, color: '#262626', style: BorderStyle.Solid })
      .translate({ x: item.isActive ? -112 : 0 })
      .onClick(() => {
        void this.loadSave(item.fileName)
      })
    }
    .width('100%')
    .height(96)
    .clip(true)
  }

  @Builder
  private DurationBadge(item: SaveSlotItem) {
    if (item.isActive) {
      Text(item.durationLabel)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(EmuColors.primary)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .border({ width: 0.5, color: EmuColors.primary, style: BorderStyle.Solid })
    } else {
      Text(item.durationLabel)
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor(EmuColors.onSurfaceVariant)
    }
  }

  @Builder
  private SwipeAction(label: string, color: string, fileName: string) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(label === '读档' ? '#004C0C' : '#450900')
        .letterSpacing(1)
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(color)
    .onClick(() => {
      if (label === '删除') {
        this.requestDelete(fileName)
      } else {
        void this.loadSave(fileName)
      }
    })
  }

  @Builder
  private ArchiveList() {
    if (this.saveItems.length > 0) {
      List() {
        ForEach(this.saveItems, (item: SaveSlotItem) => {
          ListItem() {
            this.SaveSlotRow(item)
          }
        }, (item: SaveSlotItem) => item.id)
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      Column({ space: 16 }) {
        Text('▣')
          .fontSize(42)
          .fontColor(EmuColors.onSurfaceVariant)
          .opacity(0.48)

        Text('End of Archive Stream')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2.4)
          .opacity(0.48)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Dashed })
      .margin({ left: 24, right: 24, top: 42, bottom: 42 })
    }
  }

  @Builder
  private DeleteModal() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .backdropBlur(10)
        .onClick(() => {
          this.showDeleteConfirm = false
        })

      Column({ space: 14 }) {
        Row() {
          EmuIcon({
            name: 'warning',
            iconSize: 28
          })
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor('#18ED7F64')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Text('确定要删除此存档吗？')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurface)

        Text('此操作不可恢复')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)

        Button('确定删除')
          .width('100%')
          .height(42)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#450900')
          .backgroundColor(EmuColors.error)
          .onClick(() => {
            void this.confirmDelete()
          })

        Button('取消')
          .width('100%')
          .height(40)
          .fontSize(12)
          .fontColor(EmuColors.onSurfaceVariant)
          .backgroundColor(EmuColors.surfaceContainerHigh)
          .onClick(() => {
            this.showDeleteConfirm = false
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 280 })
      .padding(24)
      .backgroundColor('#0C0C0C')
      .borderRadius(12)
      .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Solid })
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Toast() {
    Row({ space: 8 }) {
      EmuIcon({
        name: 'check_circle',
        iconSize: 14
      })
      Text(this.toastMessage)
        .fontSize(10)
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
          titleText: 'EMU_CORE_v1.0',
          rightLabel: '存档管理',
          titleIcon: 'memory',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18
        })

        this.TelemetryStrip()
        this.ArchiveList()

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
      .width('100%')
      .height('100%')

      if (this.showDeleteConfirm) {
        this.DeleteModal()
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
