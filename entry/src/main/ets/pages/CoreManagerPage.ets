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
  formatCoreFirmwarePathList,
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

@Entry
@ComponentV2
struct CoreManagerPage {
  @Local private coreItems: ManagedCoreItem[] = []
  @Local private statusText: string = '正在扫描本地核心'
  @Local private selectedCoreId: string = ''
  @Local private firmwareSummaryText: string = '正在读取本地 system 目录'
  @Local private firmwareFilesText: string = 'system/ 尚未扫描'
  @Local private firmwareDirectoryText: string = 'filesDir/system'
  @Local private remoteUpdateText: string = '当前构建未配置远端 core / firmware 仓库'
  @Local private foldDisplayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  private pageActive: boolean = false
  private coreRefreshToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')
  private foldStatusListener: (data: display.FoldStatus) => void = (data: display.FoldStatus) => {
    this.updateFoldDisplayMode()
  }

  aboutToAppear(): void {
    this.pageActive = true
    this.updateFoldDisplayMode()
    display.on('foldStatusChange', this.foldStatusListener)
    void this.refreshCoreStatus()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.coreRefreshToken += 1
    display.off('foldStatusChange', this.foldStatusListener)
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
      this.statusText = '上下文不可用'
      this.coreItems = this.buildCatalogItems()
      return
    }
    const nextItems: ManagedCoreItem[] = []
    const catalogItems = this.buildCatalogItems()
    this.firmwareDirectoryText = `${context.filesDir}/system`
    const systemEntries = await loadSystemFirmwareEntries(context)
    if (!this.isCurrentCoreRefresh(token)) {
      return
    }
    this.firmwareFilesText = formatCoreFirmwarePathList(systemEntries)
    for (let index = 0; index < catalogItems.length; index += 1) {
      const item = catalogItems[index]
      const installed = await this.hasCoreFile(context, item.soFile)
      if (!this.isCurrentCoreRefresh(token)) {
        return
      }
      const firmwareState: CoreFirmwareDependencyState = buildCoreFirmwareDependencyState(item.id, systemEntries)
      nextItems.push({
        id: item.id,
        name: item.name,
        platform: item.platform,
        soFile: item.soFile,
        status: installed ? '已安装' : '未找到',
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
    this.firmwareSummaryText = this.buildFirmwareSummaryText(nextItems, systemEntries)
  }

  private async hasCoreFile(context: common.UIAbilityContext, soFile: string): Promise<boolean> {
    const abiCandidates: string[] = ['arm64-v8a', 'arm64', 'x86_64']
    for (let index = 0; index < abiCandidates.length; index += 1) {
      const path = `${context.bundleCodeDir}/libs/${abiCandidates[index]}/${soFile}`
      try {
        await fs.access(path)
        return true
      } catch (err) {
        continue
      }
    }
    return false
  }

  private buildStatusText(items: ManagedCoreItem[]): string {
    let installedCount = 0
    items.forEach((item: ManagedCoreItem) => {
      if (item.installed) {
        installedCount += 1
      }
    })
    return `已安装 ${installedCount}/${items.length} 个本地核心`
  }

  private buildFirmwareSummaryText(items: ManagedCoreItem[], systemEntries: string[]): string {
    const dependencyItems = items.filter((item: ManagedCoreItem) => item.hasFirmwareDependencies)
    if (dependencyItems.length === 0) {
      return `system/ 已扫描 · ${systemEntries.length} 个文件`
    }
    let readyCount = 0
    dependencyItems.forEach((item: ManagedCoreItem) => {
      if (item.firmwareMissingText === '无缺失项') {
        readyCount += 1
      }
    })
    return `${readyCount}/${dependencyItems.length} 个需固件核心已就绪`
  }

  private buildCatalogItems(): ManagedCoreItem[] {
    const items: ManagedCoreItem[] = []
    const maxVisibleItems = Math.min(6, LIBRETRO_CORE_CATALOG.length)
    for (let index = 0; index < maxVisibleItems; index += 1) {
      const config: CoreConfig = LIBRETRO_CORE_CATALOG[index]
      items.push({
        id: config.id,
        name: config.name,
        platform: config.description,
        soFile: config.soFile,
        status: '待扫描',
        installed: false,
        firmwareStatus: '尚未扫描',
        firmwareDetail: '等待读取 system/ 目录',
        firmwareFoundText: '尚未扫描',
        firmwareMissingText: '尚未扫描',
        hasFirmwareDependencies: false
      })
    }
    return items
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('CoreManagerPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
    })
  }

  @Builder
  private MemoryFootprint() {
    Row({ space: 1 }) {
      this.FootprintCell('LOCAL CORE', `${this.coreItems.length} 项`, 72)
      this.FootprintCell('FIRMWARE', this.firmwareSummaryText, 44)
      this.FootprintCell('REMOTE UPDATE', '未配置', 18)
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
          name: item.installed ? 'memory' : 'developer_board',
          iconSize: 20,
          tone: item.installed ? 'primary' : 'muted'
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
        Text(`${item.platform} | ${item.soFile}`)
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
          .fontColor(item.installed ? EmuColors.primary : EmuColors.error)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .border({ width: 0.5, color: item.installed ? EmuColors.primary : EmuColors.error, style: BorderStyle.Solid })

        Text(item.firmwareStatus)
          .fontSize(9)
          .fontColor(item.hasFirmwareDependencies ? EmuColors.primary : EmuColors.onSurfaceVariant)
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
      Text('运行日志')
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(2)
      Text('[SCAN] 仅扫描 bundleCodeDir/libs 下已打包的 core 文件')
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
      Text(`[FW] 本地固件目录: ${this.firmwareDirectoryText}`)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
      Text(`[FW] ${this.firmwareSummaryText}`)
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.onSurfaceVariant)
      Text(`[FW] ${this.firmwareFilesText}`)
        .fontSize(EmuTypography.xs)
        .fontColor(EmuColors.onSurfaceVariant)
      Text(`[NET] ${this.remoteUpdateText}，在线更新与固件库下载入口当前不可用`)
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
        rightLabel: '内核与固件管理',
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
    if (!currentItem.hasFirmwareDependencies) {
      return `${currentItem.name}: 当前未配置额外固件依赖`
    }
    return `${currentItem.name}: ${currentItem.firmwareDetail} / ${currentItem.firmwareFoundText} / ${currentItem.firmwareMissingText}`
  }

  @Builder
  private SingleModeLayout() {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Text('内存占用')
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

        Text('已识别核心')
          .fontSize(EmuTypography.xs)
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2)
          .width('100%')

        Text('本页只展示本地已打包 core 与 filesDir/system 下的固件依赖状态；远端更新、在线固件库当前未接入。')
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
          Text('已识别核心')
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
            Text('内存占用')
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
          Text('已识别核心')
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
            Text('内存占用')
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
          Text('固件依赖状态')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
            .width('100%')

          if (this.selectedCoreId.length > 0) {
            this.FirmwareStatusPanel()
          } else {
            Column({ space: 12 }) {
              Text('选择核心后显示固件依赖')
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
          name: item.installed ? 'memory' : 'developer_board',
          iconSize: 18,
          tone: item.installed ? 'primary' : 'muted'
        })

        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .layoutWeight(1)

        Text(item.status)
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(item.installed ? EmuColors.primary : EmuColors.error)
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .border({ width: 0.5, color: item.installed ? EmuColors.primary : EmuColors.error, style: BorderStyle.Solid })
      }
      .width('100%')

      Text(`${item.platform} | ${item.soFile}`)
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
            name: currentItem.installed ? 'memory' : 'developer_board',
            iconSize: 32,
            tone: currentItem.installed ? 'primary' : 'muted'
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
          Text('状态:')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.status)
            .fontSize(EmuTypography.sm)
            .fontWeight(FontWeight.Bold)
            .fontColor(currentItem.installed ? EmuColors.primary : EmuColors.error)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('文件:')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.soFile)
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurface)
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 8 }) {
          Text('固件:')
            .fontSize(EmuTypography.sm)
            .fontColor(EmuColors.onSurfaceVariant)
          Text(currentItem.firmwareStatus)
            .fontSize(EmuTypography.sm)
            .fontColor(currentItem.hasFirmwareDependencies ? EmuColors.primary : EmuColors.onSurfaceVariant)
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
      if (currentItem.hasFirmwareDependencies) {
        Column({ space: 12 }) {
          Text('已找到文件')
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.primary)
            .letterSpacing(2)
            .width('100%')

          Text(currentItem.firmwareFoundText)
            .fontSize(EmuTypography.xs)
            .fontColor(EmuColors.onSurfaceVariant)
            .width('100%')

          Text('缺失文件')
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
          Text('当前核心无固件依赖')
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
