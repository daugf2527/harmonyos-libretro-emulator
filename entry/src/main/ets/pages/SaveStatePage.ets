import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { ErrorCodeUtils, EngineErrorCodes, FileErrorCodes } from '../common/ErrorCodes'
import {
  buildSaveStateThumbnailUri,
  deleteSaveStateItem,
  listSaveStateItems,
  readSaveStateData,
  SaveStateManifestItemThumbnail,
  SaveStateManifestItem,
  saveStateData
} from '../common/SaveStateRepository'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'
import {
  runtimeSessionController,
  RuntimeSaveStateBundle
} from '../common/RuntimeSessionController'

interface SaveSlotItem {
  id: string
  fileName: string
  slotLabel: string
  detail: string
  durationLabel: string
  isActive: boolean
  coverColor: string
  byteLength: number
  thumbnailUrl: string
}

interface SaveStateRouteParams {
  romFile?: string
}

@Entry
@ComponentV2
struct SaveStatePage {
  @Local private saveItems: SaveSlotItem[] = []
  @Local private selectedSaveFile: string = ''
  @Local private showDeleteConfirm: boolean = false
  @Local private toastMessage: string = ''
  @Local private showToast: boolean = false
  @Local private syncStatusText: string = '本地存档'
  @Local private loading: boolean = false
  @Local private currentRomFile: string = ''
  @Local private currentFoldMode: 'single' | 'dual' | 'triple' = 'single'
  @Local private selectedSaveItem: SaveSlotItem | null = null
  private toastTimer: number = -1
  private pageActive: boolean = false
  private pageTaskToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')
  private readonly coverColors: string[] = ['#274530', '#27405E', '#4A3628', '#39364A']
  private readonly formatDate: Date = new Date(0)
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    this.detectFoldMode()
  }

  aboutToAppear(): void {
    this.pageActive = true
    this.currentRomFile = this.resolveCurrentRomFile()
    try {
      display.on('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('SaveStatePage', 'Fold', `foldStatusChange on failed: ${err}`)
    }
    this.detectFoldMode()
    void this.refreshSaveItems()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
    try {
      display.off('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('SaveStatePage', 'Fold', `foldStatusChange off failed: ${err}`)
    }
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

  private async refreshSaveItems(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.saveItems = []
      this.syncStatusText = '无法访问上下文'
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
      const selectedSaveId = this.selectedSaveItem?.id ?? ''
      visibleEntries.forEach((item: SaveStateManifestItem, index: number) => {
        nextItems.push(this.buildSaveSlot(context, item, index))
      })
      this.saveItems = nextItems
      this.selectedSaveItem = selectedSaveId.length > 0
        ? nextItems.find((item: SaveSlotItem) => item.id === selectedSaveId) ?? null
        : null
      this.syncStatusText = this.buildSaveStatusText(nextItems.length)
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.warn('SaveStatePage', 'Save', `读取存档目录失败: ${message}`)
      // 使用错误码提供用户友好的错误消息
      const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_LIST_ERROR.numericCode)
      LogHelper.info('SaveStatePage', 'Save', `错误提示: ${userMsg}`)
      this.saveItems = []
      this.syncStatusText = '暂无存档'
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
      return this.currentRomFile.length > 0 ? '当前游戏存档已就绪' : '本地存档索引已就绪'
    }
    return this.currentRomFile.length > 0 ? '当前游戏暂无存档' : '暂无存档'
  }

  private buildSaveSlot(
    context: common.UIAbilityContext,
    item: SaveStateManifestItem,
    index: number
  ): SaveSlotItem {
    const slotNumber = (index + 1).toString().padStart(3, '0')
    const colorIndex = index % this.coverColors.length
    return {
      id: item.id,
      fileName: item.fileName,
      slotLabel: `存档位_${slotNumber}`,
      detail: `${this.normalizeTitle(item.fileName)} | ${this.formatBytes(item.byteLength)}`,
      durationLabel: item.createdAt > 0 ? this.formatDateTime(item.createdAt) : '本地',
      isActive: index === 0,
      coverColor: this.coverColors[colorIndex],
      byteLength: item.byteLength,
      thumbnailUrl: buildSaveStateThumbnailUri(context.filesDir, item.thumbnailFileName)
    }
  }

  private normalizeTitle(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
    const cleaned = baseName.replace(/[_-]+/g, ' ')
    return cleaned.length > 0 ? cleaned : '未知存档'
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
    this.formatDate.setTime(timestamp)
    const date = this.formatDate
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
      this.showToastMessage('存档删除成功')
      await this.refreshSaveItems()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `删除存档失败: ${message}`)
      // 使用错误码提供具体错误信息
      const userMsg = ErrorCodeUtils.getUserMessage(FileErrorCodes.FILE_WRITE_ERROR.numericCode)
      this.showToastMessage(userMsg)
    }
  }

  private async quickSave(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.showToastMessage(ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_SAVE_FAILED.numericCode))
      return
    }
    try {
      const bundle = await runtimeSessionController.saveStateBundleAsync()
      if (!this.isCurrentPageTask(token)) {
        return
      }
      if (!bundle.stateData || bundle.stateData.byteLength <= 0) {
        this.showToastMessage(ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_SAVE_FAILED.numericCode))
        return
      }
      await saveStateData(context, bundle.stateData, this.currentRomFile, {
        thumbnail: buildSaveSlotThumbnail(bundle)
      })
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.showToastMessage('即时存档已保存')
      await this.refreshSaveItems()
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `写入即时存档失败: ${message}`)
      // 使用错误码提供具体错误信息
      const userMsg = ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_SAVE_FAILED.numericCode)
      this.showToastMessage(userMsg)
    }
  }

  private async loadSave(fileName: string): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.showToastMessage(ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_LOAD_FAILED.numericCode))
      return
    }
    try {
      const stateData = readSaveStateData(context, fileName)
      // 与 quickSave() 保持一致，避免同步 NAPI 调用阻塞 UI 线程。
      const loaded = await runtimeSessionController.loadStateAsync(stateData)
      // D018: await 后页面可能已销毁,写 @State(toast)前检查 pageActive,与同页
      // confirmDelete/quickSave 的 isCurrentPageTask 守卫一致(此处用 pageActive)。
      if (!this.pageActive) {
        return
      }
      this.showToastMessage(
        loaded
          ? '即时存档已读取'
          : ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_LOAD_FAILED.numericCode)
      )
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('SaveStatePage', 'Save', `读取即时存档失败: ${message}`)
      // 使用错误码提供具体错误信息
      const userMsg = ErrorCodeUtils.getUserMessage(EngineErrorCodes.SAVE_STATE_LOAD_FAILED.numericCode)
      this.showToastMessage(userMsg)
    }
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        LogHelper.error('SaveStatePage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('SaveStatePage', 'Route', `pushUrl ${route} failed: ${err.message}`)
    })
  }

  private onSaveItemClick(item: SaveSlotItem): void {
    if (this.currentFoldMode === 'single') {
      // 单折态：直接加载存档
      void this.loadSave(item.fileName)
    } else {
      // 双折态/三折态：选中存档，显示详情
      this.selectedSaveItem = item
    }
  }

  @Builder
  private SaveHeader() {
    Row() {
      Row({ space: 10 }) {
        EmuIcon({
          name: 'memory',
          iconSize: 21
        })

        Text('碳影 / Carbon Shade')
          .fontSize(EmuTypography.lg)
                    .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(1.6)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Text('存档管理')
        .fontSize(EmuTypography.md)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)
        .letterSpacing(0.8)

      Row({ space: 16 }) {
        Row() {
          Text('+')
            .fontSize(EmuTypography.display)
            .fontWeight(FontWeight.Bold)
            .fontColor('#004C0C')
        }
        .width(34)
        .height(34)
        .borderRadius(3)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(EmuColors.primary)
        .onClick(() => {
          void this.quickSave()
        })

        Row() {
          EmuIcon({
            name: 'settings_input_component',
            iconSize: 28
          })
        }
        .onClick(() => {
          void this.refreshSaveItems()
        })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(64)
    .padding({ left: 24, right: 24 })
    .backgroundColor('#E6000000')
    .border({ width: { bottom: 0.5 }, color: '#262626', style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backdropBlur(24)
  }

  @Builder
  private TelemetryStrip() {
    Row() {
      this.StatusColumn('存储', this.currentRomFile.length > 0 ? '当前游戏' : '本地文件')
      this.StatusColumn('存档位', `${this.saveItems.length}/99`)
      this.StatusColumn('归档', this.loading ? '正在读取本地...' : this.syncStatusText)
    }
    .width('100%')
    .height(100)
    .padding({ left: 30, right: 30 })
    .backgroundColor('#0E0E0E')
    .border({ width: { bottom: 0.5 }, color: '#262626', style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private StatusColumn(label: string, value: string) {
    Row({ space: 12 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(EmuColors.primary)

      Column({ space: 6 }) {
        Text(label.toUpperCase())
          .fontSize(EmuTypography.xs)
                    .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2.4)

        Text(value)
          .fontSize(EmuTypography.md)
                    .fontColor(label === '归档' ? EmuColors.primary : EmuColors.onSurfaceVariant)
          .letterSpacing(1.6)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  private SaveThumbnailContent(item: SaveSlotItem, showFallbackText: boolean = false) {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(item.coverColor)
        .opacity(item.thumbnailUrl.length > 0 ? 0.18 : 0.72)

      if (item.thumbnailUrl.length > 0) {
        Image(item.thumbnailUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (showFallbackText) {
        Column({ space: 8 }) {
          Text('预览')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)

          Text('无截图')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
            .opacity(0.6)
        }
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private SaveSlotRow(item: SaveSlotItem) {
    Stack() {
      Row() {
        Row({ space: 0 }) {
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
          this.SaveThumbnailContent(item)

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
            .fontSize(EmuTypography.md)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${item.slotLabel} | ${item.detail}`)
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.onSurfaceVariant)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.DurationBadge(item)

          Text('≡')
            .fontSize(EmuTypography.md)
            .fontColor(EmuColors.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .height(96)
      .padding({ left: item.isActive ? 18 : 24, right: 24 })
      .backgroundColor(this.selectedSaveItem?.id === item.id ? '#1A1A1A' : EmuColors.surfaceContainerLowest)
      .border({ width: { bottom: 0.5 }, color: '#262626', style: BorderStyle.Solid })
      .translate({ x: item.isActive ? -184 : 0 })
      .onClick(() => {
        this.onSaveItemClick(item)
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
                .fontColor(EmuColors.primary)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .border({ width: 0.5, color: EmuColors.primary, style: BorderStyle.Solid })
    } else {
      Text(item.durationLabel)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
    }
  }

  @Builder
  private SwipeAction(label: string, color: string, fileName: string) {
    Row() {
      Text(label)
        .fontSize(EmuTypography.xs)
        .fontWeight(FontWeight.Bold)
        .fontColor(label === '读档' ? '#004C0C' : '#450900')
        .letterSpacing(1)
    }
    .width(92)
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
          .fontSize(46)
          .fontColor(EmuColors.onSurfaceVariant)
          .opacity(0.48)

        Text('已到存档列表末尾')
          .fontSize(EmuTypography.sm)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(4)
          .opacity(0.48)
      }
      .width('100%')
      .height(252)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Dashed })
      .borderRadius(8)
      .margin({ left: 44, right: 44, top: 88, bottom: 88 })
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
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.2)

        Button('确定删除')
          .width('100%')
          .height(42)
          .fontSize(EmuTypography.sm)
          .fontWeight(FontWeight.Bold)
          .fontColor('#450900')
          .backgroundColor(EmuColors.error)
          .onClick(() => {
            void this.confirmDelete()
          })

        Button('取消')
          .width('100%')
          .height(40)
          .fontSize(EmuTypography.sm)
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
        .fontSize(EmuTypography.xs)
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

  @Builder
  private SaveDetailPanel() {
    if (!this.selectedSaveItem) {
      this.EmptySaveDetailPanel()
    } else {
      ForEach(this.getSelectedSaveItems(), (item: SaveSlotItem) => {
        this.SelectedSaveDetailPanel(item)
      }, (item: SaveSlotItem) => item.id)
    }
  }

  @Builder
  private EmptySaveDetailPanel() {
    Column({ space: 16 }) {
      Text('▣')
        .fontSize(46)
        .fontColor(EmuColors.onSurfaceVariant)
        .opacity(0.48)

      Text('请选择存档位')
        .fontSize(EmuTypography.sm)
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(4)
        .opacity(0.48)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SelectedSaveDetailPanel(item: SaveSlotItem) {
    Column({ space: 24 }) {
      Stack() {
        this.SaveThumbnailContent(item, true)
      }
      .width('100%')
      .aspectRatio(1.5)
      .borderRadius(8)
      .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Solid })

      // 存档详情
      Column({ space: 16 }) {
        this.DetailRow('文件名', this.normalizeTitle(item.fileName))
        this.DetailRow('存档位', item.slotLabel)
        this.DetailRow('大小', this.getSaveItemSizeText(item))
        this.DetailRow('创建时间', item.durationLabel)
        this.DetailRow('游戏', this.currentRomFile.length > 0 ? this.currentRomFile : '未知')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#0E0E0E')
      .borderRadius(8)
      .border({ width: 0.5, color: '#262626', style: BorderStyle.Solid })

      // 操作按钮
      Column({ space: 12 }) {
        Button('读取存档')
          .width('100%')
          .height(48)
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor('#004C0C')
          .backgroundColor(EmuColors.primary)
          .onClick(() => {
            void this.loadSave(item.fileName)
          })

        Button('删除存档')
          .width('100%')
          .height(48)
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor('#450900')
          .backgroundColor(EmuColors.error)
          .onClick(() => {
            this.requestDelete(item.fileName)
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(24)
  }

  private getSelectedSaveItems(): SaveSlotItem[] {
    const items: SaveSlotItem[] = []
    if (!this.selectedSaveItem) {
      return items
    }
    items.push(this.selectedSaveItem)
    return items
  }

  private getSaveItemSizeText(item: SaveSlotItem): string {
    return this.formatBytes(item.byteLength)
  }

  @Builder
  private DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .width(80)

      Text(value)
        .fontSize(EmuTypography.sm)
        .fontColor(EmuColors.onSurface)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private SaveOperationsPanel() {
    Column({ space: 24 }) {
      // 快速操作
      Column({ space: 12 }) {
        Text('快捷操作')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2)

        Button('新建存档')
          .width('100%')
          .height(48)
          .fontSize(EmuTypography.md)
          .fontWeight(FontWeight.Bold)
          .fontColor('#004C0C')
          .backgroundColor(EmuColors.primary)
          .onClick(() => {
            void this.quickSave()
          })

        Button('刷新列表')
          .width('100%')
          .height(48)
          .fontSize(EmuTypography.sm)
          .fontColor(EmuColors.onSurfaceVariant)
          .backgroundColor(EmuColors.surfaceContainerHigh)
          .onClick(() => {
            void this.refreshSaveItems()
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#0E0E0E')
      .borderRadius(8)
      .border({ width: 0.5, color: '#262626', style: BorderStyle.Solid })

      // 存档预览（如果有选中）
      ForEach(this.getSelectedSaveItems(), (item: SaveSlotItem) => {
        this.SavePreviewPanel(item)
      }, (item: SaveSlotItem) => item.id)
    }
    .width('100%')
    .height('100%')
    .padding(24)
  }

  @Builder
  private SavePreviewPanel(item: SaveSlotItem) {
    Stack() {
      this.SaveThumbnailContent(item, true)
    }
    .width('100%')
    .aspectRatio(1.2)
    .borderRadius(8)
    .border({ width: 0.5, color: '#4D484848', style: BorderStyle.Solid })
  }

  build() {
    Stack() {
      if (this.currentFoldMode === 'single') {
        // 单折态：保持原有布局
        this.SingleFoldLayout()
      } else if (this.currentFoldMode === 'dual') {
        // 双折态：左侧列表 40%，右侧详情 60%
        this.DualFoldLayout()
      } else {
        // 三折态：左侧列表 30%，中间详情 40%，右侧操作 30%
        this.TripleFoldLayout()
      }

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

  @Builder
  private SingleFoldLayout() {
    Column() {
      this.SaveHeader()
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
  }

  @Builder
  private DualFoldLayout() {
    Column() {
      this.SaveHeader()
      this.TelemetryStrip()

      Row() {
        // 左侧：存档列表（40%）
        Column() {
          this.ArchiveList()
        }
        .width('40%')
        .height('100%')
        .border({ width: { right: 0.5 }, color: '#262626', style: BorderStyle.Solid })

        // 右侧：存档详情（60%）
        Column() {
          this.SaveDetailPanel()
        }
        .width('60%')
        .height('100%')
        .backgroundColor('#0C0C0C')
      }
      .layoutWeight(1)
      .width('100%')

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
  }

  @Builder
  private TripleFoldLayout() {
    Column() {
      this.SaveHeader()
      this.TelemetryStrip()

      Row() {
        // 左侧：存档列表（30%）
        Column() {
          this.ArchiveList()
        }
        .width('30%')
        .height('100%')
        .border({ width: { right: 0.5 }, color: '#262626', style: BorderStyle.Solid })

        // 中间：存档详情（40%）
        Column() {
          this.SaveDetailPanel()
        }
        .width('40%')
        .height('100%')
        .backgroundColor('#0C0C0C')
        .border({ width: { right: 0.5 }, color: '#262626', style: BorderStyle.Solid })

        // 右侧：操作按钮（30%）
        Column() {
          this.SaveOperationsPanel()
        }
        .width('30%')
        .height('100%')
        .backgroundColor('#0E0E0E')
      }
      .layoutWeight(1)
      .width('100%')

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
  }
}

function buildSaveSlotThumbnail(
  bundle: RuntimeSaveStateBundle
): SaveStateManifestItemThumbnail | undefined {
  if (!bundle.thumbnailRgba || bundle.thumbnailWidth <= 0 || bundle.thumbnailHeight <= 0) {
    return undefined
  }
  return {
    rgba: bundle.thumbnailRgba,
    width: bundle.thumbnailWidth,
    height: bundle.thumbnailHeight
  }
}
