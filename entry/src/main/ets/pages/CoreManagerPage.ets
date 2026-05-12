import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors } from '../common/EmuUiTokens'
import { CoreConfig, LIBRETRO_CORE_CATALOG } from '../common/LibretroCoreCatalog'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

interface ManagedCoreItem {
  id: string
  name: string
  platform: string
  soFile: string
  status: string
  installed: boolean
}

@Entry
@Component
struct CoreManagerPage {
  @State private coreItems: ManagedCoreItem[] = []
  @State private statusText: string = 'SCANNING_LOCAL_CORES'
  @State private selectedCoreId: string = ''
  private pageActive: boolean = false
  private coreRefreshToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: false },
    { key: 'system', iconName: 'tune', label: '系统', isActive: true }
  ]

  aboutToAppear(): void {
    this.pageActive = true
    void this.refreshCoreStatus()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.coreRefreshToken += 1
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
      this.statusText = 'CONTEXT_MISSING'
      this.coreItems = this.buildCatalogItems()
      return
    }
    const nextItems: ManagedCoreItem[] = []
    const catalogItems = this.buildCatalogItems()
    for (let index = 0; index < catalogItems.length; index += 1) {
      const item = catalogItems[index]
      const installed = await this.hasCoreFile(context, item.soFile)
      if (!this.isCurrentCoreRefresh(token)) {
        return
      }
      nextItems.push({
        id: item.id,
        name: item.name,
        platform: item.platform,
        soFile: item.soFile,
        status: installed ? 'INSTALLED' : 'NOT_FOUND',
        installed: installed
      })
    }
    this.coreItems = nextItems
    this.statusText = this.buildStatusText(nextItems)
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
    return `${installedCount}/${items.length}_LOCAL_CORES_READY`
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
        status: 'LOCAL',
        installed: false
      })
    }
    return items
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[CoreManagerPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[CoreManagerPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  @Builder
  private MemoryFootprint() {
    Row({ space: 1 }) {
      this.FootprintCell('CORE CATALOG', `${this.coreItems.length}`, 72)
      this.FootprintCell('FIRMWARE SOURCE', '本地', 44)
      this.FootprintCell('NETWORK UPDATE', '已关闭', 18)
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
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text(item.status)
          .fontSize(10)
                    .fontWeight(FontWeight.Bold)
          .fontColor(item.installed ? EmuColors.primary : EmuColors.error)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .border({ width: 0.5, color: item.installed ? EmuColors.primary : EmuColors.error, style: BorderStyle.Solid })

        Text('REMOTE_DISABLED')
          .fontSize(9)
                    .fontColor(EmuColors.onSurfaceVariant)
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
      Text('KERNEL_LOG')
        .fontSize(10)
                .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(2)
      Text('[SYS] Local core scan reads packaged libs only.')
        .fontSize(10)
                .fontColor(EmuColors.onSurfaceVariant)
      Text('[FW] Firmware database is not connected. Missing firmware remains UNKNOWN.')
        .fontSize(10)
                .fontColor(EmuColors.onSurfaceVariant)
      Text('[NET] Remote updater intentionally disabled in this phase.')
        .fontSize(10)
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
        titleText: 'OS_EMU_v2.4.1',
        titleIcon: 'terminal',
        rightLabel: '内核与固件管理',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 18
      })

      Scroll() {
        Column({ space: 24 }) {
          Row() {
            Text('MEMORY_FOOTPRINT')
              .fontSize(10)
                            .fontColor(EmuColors.onSurfaceVariant)
              .letterSpacing(2)
            Text(this.statusText)
              .fontSize(10)
                            .fontColor(EmuColors.primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          this.MemoryFootprint()

          Text('ACTIVE_CORES')
            .fontSize(10)
                        .fontColor(EmuColors.onSurfaceVariant)
            .letterSpacing(2)
            .width('100%')

          Column({ space: 1 }) {
            ForEach(this.coreItems, (item: ManagedCoreItem) => {
              this.CoreRow(item)
            }, (item: ManagedCoreItem) => item.id)
          }
          .width('100%')
          .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

          this.KernelLog()
        }
        .width('100%')
        .constraintSize({ maxWidth: 920 })
        .padding({ left: 20, right: 20, top: 28, bottom: 32 })
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
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
