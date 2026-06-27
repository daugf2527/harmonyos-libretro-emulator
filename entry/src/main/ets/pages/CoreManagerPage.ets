import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { display } from '@kit.ArkUI'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import LogHelper from '../common/LogHelper'
import {
  buildCoreFirmwareDependencyState,
  CoreFirmwareDependencyState,
  CORE_FIRMWARE_DEPENDENCY_RULES,
  loadSystemFirmwareEntries
} from '../common/CoreFirmwareRepository'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { CoreConfig, LIBRETRO_CORE_CATALOG } from '../common/LibretroCoreCatalog'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

interface ManagedCoreItem {
  id: string
  name: string
  platform: string
  soFile: string
  status: string
  installed: boolean
  firmwareStatus: string
  firmwareDetail: string
  firmwareFoundText: string
  firmwareMissingText: string
  hasFirmwareDependencies: boolean
}

interface CoreFileErrorWithCode {
  code?: string | number
}

@Entry
@ComponentV2
struct CoreManagerPage {
  @Local private coreItems: ManagedCoreItem[] = []
  @Local private statusText: string = '正在检查本地核心文件'
  @Local private selectedCoreId: string = ''
  @Local private firmwareSummaryText: string = '正在检查本地固件文件情况'
  @Local private firmwareFilesText: string = '正在检查本地固件目录'
  @Local private remoteUpdateText: string = '当前版本仅管理随应用提供的本地核心与固件'
  @Local private foldDisplayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  private pageActive: boolean = false
  private coreRefreshToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    if (!this.pageActive) {
      return
    }
    this.updateFoldDisplayMode()
  }

  aboutToAppear(): void {
    this.pageActive = true
    this.updateFoldDisplayMode()
    try {
      display.on('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('CoreManagerPage', 'Fold', `foldStatusChange on failed: ${err}`)
    }
    void this.refreshCoreStatus()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.coreRefreshToken += 1
    try {
      display.off('foldStatusChange', this.foldStatusListener)
    } catch (err) {
      LogHelper.error('CoreManagerPage', 'Fold', `foldStatusChange off failed: ${err}`)
    }
  }

  private updateFoldDisplayMode(): void {
    try {
      this.foldDisplayMode = display.getFoldDisplayMode()
    } catch (err) {
      LogHelper.error('CoreManagerPage', 'Fold', `getFoldDisplayMode failed: ${err}`)
      this.foldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
    }
  }

  private beginCoreRefresh(): number {
    this.coreRefreshToken += 1
    return this.coreRefreshToken
  }

  private isCurrentCoreRefresh(token: number): boolean {
    return this.pageActive && token === this.coreRefreshToken
  }

  private async refreshCoreStatus(): Promise<void> {
    const token = this.beginCoreRefresh()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.statusText = '现在还读不到本地核心列表，请稍后再试'
      this.firmwareSummaryText = '本地固件文件情况暂时没有读出来'
      this.firmwareFilesText = '本地固件目录暂时没有读出来'
      this.coreItems = this.buildUnavailableCatalogItems()
      return
    }
    const nextItems: ManagedCoreItem[] = []
    const catalogItems = this.buildCatalogItems()
    try {
      let systemEntries: string[] = []
      let firmwareEntriesReady: boolean = true
      try {
        systemEntries = await loadSystemFirmwareEntries(context)
      } catch (err) {
        firmwareEntriesReady = false
        const message = (err as Error).message || String(err)
        LogHelper.error('CoreManagerPage', 'Firmware', `扫描本地固件目录失败: ${message}`)
      }
      if (!this.isCurrentCoreRefresh(token)) {
        return
      }
      this.firmwareFilesText = firmwareEntriesReady ?
        this.buildFirmwareFilesSummary(systemEntries) :
        '本地固件目录没有扫描出来，请稍后重试'
      for (let index = 0; index < catalogItems.length; index += 1) {
        const item = catalogItems[index]
        const installed = await this.hasCoreFile(context, item.soFile)
        if (!this.isCurrentCoreRefresh(token)) {
          return
        }
        const firmwareState: CoreFirmwareDependencyState = firmwareEntriesReady ?
          buildCoreFirmwareDependencyState(item.id, systemEntries) :
          this.buildUnavailableFirmwareState(item.id, item.name)
        nextItems.push({
          id: item.id,
          name: item.name,
          platform: item.platform,
          soFile: item.soFile,
          status: installed ? '已检测到' : '当前包内未检测到',
          installed: installed,
          firmwareStatus: firmwareState.statusText,
          firmwareDetail: firmwareState.detailText,
          firmwareFoundText: firmwareState.foundFilesText,
          firmwareMissingText: firmwareState.missingFilesText,
          hasFirmwareDependencies: firmwareState.hasDependencies
        })
      }
      this.coreItems = nextItems
      this.statusText = this.buildStatusText(nextItems)
      this.firmwareSummaryText = firmwareEntriesReady ?
        this.buildFirmwareSummaryText(nextItems, systemEntries) :
        '本地固件文件情况没有读出来'
    } catch (err) {
      if (!this.isCurrentCoreRefresh(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('CoreManagerPage', 'Core', `扫描本地核心失败: ${message}`)
      this.coreItems = this.buildUnavailableCatalogItems()
      this.statusText = '本地核心列表没有读出来，请稍后重试'
      this.firmwareSummaryText = '本地固件文件情况没有读出来'
      this.firmwareFilesText = '本地固件目录没有扫描出来，请稍后重试'
    }
  }

  private buildUnavailableFirmwareState(coreId: string, coreName: string): CoreFirmwareDependencyState {
    const hasDependencies = CORE_FIRMWARE_DEPENDENCY_RULES.some((item) => item.coreId === coreId)
    if (!hasDependencies) {
      return {
        coreId: coreId,
        coreName: coreName,
        statusText: '无需额外固件',
        detailText: '当前核心不依赖额外 BIOS 或固件',
        foundFilesText: '不需要额外固件文件',
        missingFilesText: '无',
        hasDependencies: false
      }
    }
    return {
      coreId: coreId,
      coreName: coreName,
      statusText: '待重试',
      detailText: '这次没有读到这项核心的固件文件情况',
      foundFilesText: '请稍后重试',
      missingFilesText: '请稍后重试',
      hasDependencies: true
    }
  }

  private async hasCoreFile(context: common.UIAbilityContext, soFile: string): Promise<boolean> {
    const abiCandidates: string[] = ['arm64-v8a', 'arm64', 'x86_64']
    for (let index = 0; index < abiCandidates.length; index += 1) {
      const path = `${context.bundleCodeDir}/libs/${abiCandidates[index]}/${soFile}`
      try {
        await fs.access(path)
        return true
      } catch (err) {
        if (!this.isMissingFileError(err)) {
          throw err as Error
        }
        continue
      }
    }
    return false
  }

  private isMissingFileError(err: unknown): boolean {
    const errorCode = (err as CoreFileErrorWithCode).code
    if (errorCode === '13900002' || errorCode === 13900002 || errorCode === 2) {
      return true
    }
    const message = (err as Error).message || String(err)
    const normalized = message.toLowerCase()
    return normalized.indexOf('no such file') >= 0 || normalized.indexOf('ret: -2') >= 0
  }

  private buildStatusText(items: ManagedCoreItem[]): string {
    let installedCount = 0
    items.forEach((item: ManagedCoreItem) => {
      if (item.installed) {
        installedCount += 1
      }
    })
    return `当前版本内置了 ${items.length} 个核心，其中 ${installedCount} 个已检测到本地文件`
  }

  private buildFirmwareSummaryText(items: ManagedCoreItem[], systemEntries: string[]): string {
    const dependencyItems = items.filter((item: ManagedCoreItem) => item.hasFirmwareDependencies)
    if (dependencyItems.length === 0) {
      return `已检查本地固件目录，共发现 ${systemEntries.length} 个文件`
    }
    let readyCount = 0
    dependencyItems.forEach((item: ManagedCoreItem) => {
      if (item.firmwareMissingText === '无缺失项') {
        readyCount += 1
      }
    })
    return `依赖额外固件的核心中，${readyCount}/${dependencyItems.length} 个所需文件名已配齐`
  }

  private buildFirmwareFilesSummary(systemEntries: string[]): string {
    if (systemEntries.length === 0) {
      return '当前还没有检测到本地固件文件'
    }
    if (systemEntries.length <= 3) {
      return `已检测到 ${systemEntries.length} 个固件文件：${systemEntries.join('、')}`
    }
    return `已检测到 ${systemEntries.length} 个固件文件：${systemEntries.slice(0, 3).join('、')} 等`
  }

  private buildCatalogItems(): ManagedCoreItem[] {
    const items: ManagedCoreItem[] = []
    for (let index = 0; index < LIBRETRO_CORE_CATALOG.length; index += 1) {
      const config: CoreConfig = LIBRETRO_CORE_CATALOG[index]
      items.push({
        id: config.id,
        name: config.name,
        platform: config.description,
        soFile: config.soFile,
        status: '正在检查',
        installed: false,
        firmwareStatus: '正在检查',
        firmwareDetail: '正在读取本地固件目录',
        firmwareFoundText: '正在读取',
        firmwareMissingText: '正在读取',
        hasFirmwareDependencies: false
      })
    }
    return items
  }

  private buildUnavailableCatalogItems(): ManagedCoreItem[] {
    const items: ManagedCoreItem[] = []
    for (let index = 0; index < LIBRETRO_CORE_CATALOG.length; index += 1) {
      const config: CoreConfig = LIBRETRO_CORE_CATALOG[index]
      items.push({
        id: config.id,
        name: config.name,
        platform: config.description,
        soFile: config.soFile,
        status: '待重试',
        installed: false,
        firmwareStatus: '待重试',
        firmwareDetail: '当前没有读到这项核心和固件状态',
        firmwareFoundText: '请稍后重试',
        firmwareMissingText: '请稍后重试',
        hasFirmwareDependencies: false
      })
    }
    return items
  }

  private isUnavailableCoreItem(item: ManagedCoreItem): boolean {
    return item.status === '待重试'
  }

  private isUnavailableFirmwareState(item: ManagedCoreItem): boolean {
    return item.firmwareStatus === '待重试'
  }

  private getCoreIconName(item: ManagedCoreItem): string {
    if (this.isUnavailableCoreItem(item)) {
      return 'help'
    }
    return item.installed ? 'memory' : 'developer_board'
  }

  private getCoreIconTone(item: ManagedCoreItem): ResourceColor {
    if (this.isUnavailableCoreItem(item)) {
      return EmuColors.onSurfaceVariant
    }
    return item.installed ? EmuColors.primary : EmuColors.onSurfaceVariant
  }

  private getCoreStatusColor(item: ManagedCoreItem): ResourceColor {
    if (this.isUnavailableCoreItem(item)) {
      return EmuColors.onSurfaceVariant
    }
    return item.installed ? EmuColors.primary : EmuColors.error
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('CoreManagerPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.statusText = '这个页面现在还打不开，请稍后再试'
    })
  }

  @Builder
  private MemoryFootprint() {
    Row({ space: 1 }) {
      this.FootprintCell('核心条目', `${this.coreItems.length} 项`, 72)
      this.FootprintCell('固件文件情况', this.firmwareSummaryText, 44)
      this.FootprintCell(
        '核心来源',
        this.coreItems.some((item: ManagedCoreItem) => this.isUnavailableCoreItem(item)) ? '状态待重试' : '随应用提供',
        18
      )
    }
    .width('100%')
    .backgroundColor('#33484848')
  }

  @Builder
  private FootprintCell(label: string, value: string, level: number) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(9)
                .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1.4)
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Row()
          .width(`${level}%`)
          .height(2)
          .backgroundColor(EmuColors.primary)
      }
      .width('100%')
      .height(2)
      .backgroundColor(EmuColors.surfaceContainerHigh)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(EmuColors.surfaceContainerLowest)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CoreRow(item: ManagedCoreItem) {
    Row({ space: 14 }) {
      Row() {
        EmuIcon({
          name: this.getCoreIconName(item),
          iconSize: 20,
          tone: this.getCoreIconTone(item)
        })
      }
      .width(44)
      .height(44)
      .backgroundColor(EmuColors.surfaceContainerHigh)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 6 }) {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
        Text(item.platform)
          .fontSize(9)
                    .fontColor(EmuColors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.firmwareDetail)
          .fontSize(9)
          .fontColor(EmuColors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text(item.status)
          .fontSize(EmuTypography.xs)
                    .fontWeight(FontWeight.Bold)
          .fontColor(this.getCoreStatusColor(item))
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .border({ width: 0.5, color: this.getCoreStatusColor(item), style: BorderStyle.Solid })

      Text(item.firmwareStatus)
          .fontSize(9)
          .fontColor(this.isUnavailableCoreItem(item) || !item.hasFirmwareDependencies ?
            EmuColors.onSurfaceVariant :
            EmuColors.primary)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .border({ width: 0.5, color: EmuColors.outlineVariant, style: BorderStyle.Solid })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.selectedCoreId === item.id ? '#1800FF41' : EmuColors.surfaceContainerLowest)
    .border({ width: { bottom: 0.5 }, color: '#33484848', style: BorderStyle.Solid })
    .onClick(() => {
      this.selectedCoreId = item.id
    })
  }

  @Builder
  private KernelLog() {
    Column({ space: 6 }) {
      Text('页面说明')
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(2)
      Text('这里只显示当前版本随应用提供的本地核心。')
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
      Text(this.firmwareFilesText)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
      Text(this.firmwareSummaryText)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
      Text('需要额外固件的核心，会在列表和详情里显示本地文件情况。')
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
      Text(this.remoteUpdateText)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.primary)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(EmuColors.surfaceContainerLowest)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: '碳影',
        titleIcon: 'terminal',
        rightLabel: '本地核心与固件',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 18
      })

      if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
        this.DualModeLayout()
      } else if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
        this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_SUB) {
        this.TripleModeLayout()
      } else {
        this.SingleModeLayout()
      }

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
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private buildSelectedCoreFirmwareText(): string {
    const currentItem = this.coreItems.find((item: ManagedCoreItem) => item.id === this.selectedCoreId)
    if (!currentItem) {
      return ''
    }
    if (this.isUnavailableCoreItem(currentItem) || this.isUnavailableFirmwareState(currentItem)) {
      return `${currentItem.name} 的本地核心和固件状态这次没有读出来，请稍后重试`
    }
    if (!currentItem.installed) {
      return currentItem.hasFirmwareDependencies ?
        `${currentItem.name} 当前包内没有检测到核心文件；下面这组固件文件情况仅供后续补齐核心后参考。` :
        `${currentItem.name} 当前包内没有检测到核心文件。`
    }
    if (!currentItem.hasFirmwareDependencies) {
      return `${currentItem.name} 当前不需要额外固件`
    }
    return `${currentItem.name}：${currentItem.firmwareDetail}。已找到：${currentItem.firmwareFoundText}；仍缺少：${currentItem.firmwareMissingText}`
  }

  @Builder
  private SingleModeLayout() {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Text('本地核心摘要')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
          Text(this.statusText)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.primary)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        this.MemoryFootprint()

        Text('核心目录')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2)
          .width('100%')

        Text('本页显示当前版本随应用提供的核心，以及本地固件目录里的依赖文件情况。')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .width('100%')

        Column({ space: 1 }) {
          ForEach(this.coreItems, (item: ManagedCoreItem) => {
            this.CoreRow(item)
          }, (item: ManagedCoreItem) => item.id)
        }
        .width('100%')
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

        if (this.selectedCoreId.length > 0) {
          Text(this.buildSelectedCoreFirmwareText())
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')
        }

        this.KernelLog()
      }
      .width('100%')
      .constraintSize({ maxWidth: 920 })
      .padding({ left: 20, right: 20, top: 28, bottom: 32 })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private DualModeLayout() {
    Row() {
      Scroll() {
        Column({ space: 12 }) {
          Text('核心目录')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
            .width('100%')

          Column({ space: 1 }) {
            ForEach(this.coreItems, (item: ManagedCoreItem) => {
              this.CoreRowCompact(item)
            }, (item: ManagedCoreItem) => item.id)
          }
          .width('100%')
          .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 20 })
      }
      .width('40%')
      .height('100%')
      .backgroundColor(EmuColors.surfaceContainerLowest)

      Scroll() {
        Column({ space: 20 }) {
          Row() {
            Text('本地核心摘要')
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.onSurfaceVariant)
              .letterSpacing(2)
            Text(this.statusText)
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          this.MemoryFootprint()

          if (this.selectedCoreId.length > 0) {
            this.CoreDetailPanel()
          } else {
            Column({ space: 12 }) {
              Text('请从左侧选择核心查看详情')
                .fontSize(EmuTypography.sm)
                .fontColor(EmuColors.onSurfaceVariant)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(40)
            }
          }

          this.KernelLog()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      }
      .layoutWeight(1)
      .height('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private TripleModeLayout() {
    Row() {
      Scroll() {
        Column({ space: 12 }) {
          Text('核心目录')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
            .width('100%')

          Column({ space: 1 }) {
            ForEach(this.coreItems, (item: ManagedCoreItem) => {
              this.CoreRowCompact(item)
            }, (item: ManagedCoreItem) => item.id)
          }
          .width('100%')
          .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 20 })
      }
      .width('30%')
      .height('100%')
      .backgroundColor(EmuColors.surfaceContainerLowest)

      Scroll() {
        Column({ space: 20 }) {
          Row() {
            Text('本地核心摘要')
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.onSurfaceVariant)
              .letterSpacing(2)
            Text(this.statusText)
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          this.MemoryFootprint()

          if (this.selectedCoreId.length > 0) {
            this.CoreDetailPanel()
          } else {
            Column({ space: 12 }) {
              Text('请从左侧选择核心查看详情')
                .fontSize(EmuTypography.sm)
                .fontColor(EmuColors.onSurfaceVariant)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(40)
            }
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      }
      .width('40%')
      .height('100%')

      Scroll() {
        Column({ space: 20 }) {
          Text('固件文件情况')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
            .width('100%')

          if (this.selectedCoreId.length > 0) {
            this.FirmwareStatusPanel()
          } else {
            Column({ space: 12 }) {
              Text('选择核心后显示固件文件情况')
                .fontSize(EmuTypography.sm)
                .fontColor(EmuColors.onSurfaceVariant)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(40)
            }
          }

          this.KernelLog()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      }
      .width('30%')
      .height('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private CoreRowCompact(item: ManagedCoreItem) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        EmuIcon({
          name: this.getCoreIconName(item),
          iconSize: 18,
          tone: this.getCoreIconTone(item)
        })

        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .layoutWeight(1)

        Text(item.status)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getCoreStatusColor(item))
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .border({ width: 0.5, color: this.getCoreStatusColor(item), style: BorderStyle.Solid })
      }
      .width('100%')

      Text(item.platform)
        .fontSize(9)
        .fontColor(EmuColors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedCoreId === item.id ? '#1800FF41' : EmuColors.surfaceContainerLowest)
    .border({ width: { bottom: 0.5 }, color: '#33484848', style: BorderStyle.Solid })
    .onClick(() => {
      this.selectedCoreId = item.id
    })
  }

  @Builder
  private CoreDetailPanel() {
    ForEach(this.getSelectedCoreItems(), (currentItem: ManagedCoreItem) => {
      this.CoreDetailContent(currentItem)
    }, (currentItem: ManagedCoreItem) => currentItem.id)
  }

  @Builder
  private CoreDetailContent(currentItem: ManagedCoreItem) {
    Column({ space: 16 }) {
      Text('核心详情')
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(2)
        .width('100%')

      Column({ space: 12 }) {
        Row({ space: 12 }) {
          EmuIcon({
            name: this.getCoreIconName(currentItem),
            iconSize: 32,
            tone: this.getCoreIconTone(currentItem)
          })

          Column({ space: 6 }) {
            Text(currentItem.name)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(EmuColors.onSurface)

            Text(currentItem.platform)
              .fontSize(12)
              .fontColor(EmuColors.onSurfaceVariant)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('检测结果：')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.status)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getCoreStatusColor(currentItem))
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('适用平台：')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.platform)
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurface)
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('固件状态：')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.firmwareStatus)
            .fontSize(EmuTypography.sm)
            .fontColor(this.isUnavailableCoreItem(currentItem) || !currentItem.hasFirmwareDependencies ?
              EmuColors.onSurfaceVariant :
              EmuColors.primary)
        }
        .width('100%')

        if (currentItem.hasFirmwareDependencies) {
          Column({ space: 8 }) {
            Text(currentItem.firmwareDetail)
              .fontSize(EmuTypography.xs)
              .fontColor(EmuColors.onSurfaceVariant)
              .width('100%')
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(EmuColors.surfaceContainerLowest)
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    }
  }

  @Builder
  private FirmwareStatusPanel() {
    ForEach(this.getSelectedCoreItems(), (currentItem: ManagedCoreItem) => {
      this.FirmwareStatusContent(currentItem)
    }, (currentItem: ManagedCoreItem) => currentItem.id)
  }

  @Builder
  private FirmwareStatusContent(currentItem: ManagedCoreItem) {
    Column({ space: 16 }) {
      if (this.isUnavailableCoreItem(currentItem)) {
        Column({ space: 12 }) {
          Text('这项核心的固件文件情况这次没有读出来，请稍后重试')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(20)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(EmuColors.surfaceContainerLowest)
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      } else if (currentItem.hasFirmwareDependencies) {
        Column({ space: 12 }) {
          Text('已检测到的固件')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.primary)
            .letterSpacing(2)
            .width('100%')

          Text(currentItem.firmwareFoundText)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')

          Text('仍需补充的固件')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.error)
            .letterSpacing(2)
            .width('100%')
            .margin({ top: 12 })

          Text(currentItem.firmwareMissingText)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(EmuColors.surfaceContainerLowest)
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      } else {
        Column({ space: 12 }) {
          Text('当前核心不需要额外固件')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(20)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(EmuColors.surfaceContainerLowest)
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      }
    }
  }

  private getSelectedCoreItems(): ManagedCoreItem[] {
    const items: ManagedCoreItem[] = []
    for (let index = 0; index < this.coreItems.length; index += 1) {
      const item = this.coreItems[index]
      if (item.id === this.selectedCoreId) {
        items.push(item)
      }
    }
    return items
  }
}
