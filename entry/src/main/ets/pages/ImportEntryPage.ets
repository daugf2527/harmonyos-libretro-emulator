import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuBottomNav } from '../components/EmuBottomNav'
import { ImportEmptyStateHero } from '../components/ImportEmptyStateHero'
import { clearPendingImportUris, setPendingImportUris } from '../common/ImportTaskBridge'
import { EmuColors } from '../common/EmuUiTokens'
import { LIBRETRO_CORE_CATALOG } from '../common/LibretroCoreCatalog'
import {
  LibraryRecord,
  loadAllLibraryRecords
} from '../common/LibraryRepository'
import { pickRomUris } from '../common/RomImportService'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'

interface ImportParticle {
  x: number
  y: number
  size: number
  opacity: number
}

@ComponentV2
struct ParticleLayer {
  @Param boosted: boolean = false
  @Local particlePhase: number = 0
  private timer: number = -1
  private readonly particles: ImportParticle[] = [
    { x: 24, y: 88, size: 2, opacity: 0.12 },
    { x: 46, y: 148, size: 2, opacity: 0.16 },
    { x: 88, y: 104, size: 2, opacity: 0.1 },
    { x: 140, y: 180, size: 2, opacity: 0.15 },
    { x: 186, y: 128, size: 2, opacity: 0.12 },
    { x: 250, y: 76, size: 2, opacity: 0.1 },
    { x: 292, y: 166, size: 2, opacity: 0.14 },
    { x: 328, y: 122, size: 2, opacity: 0.12 },
    { x: 32, y: 438, size: 2, opacity: 0.11 },
    { x: 74, y: 502, size: 2, opacity: 0.13 },
    { x: 132, y: 546, size: 2, opacity: 0.1 },
    { x: 208, y: 484, size: 2, opacity: 0.14 },
    { x: 286, y: 526, size: 2, opacity: 0.12 }
  ]

  aboutToAppear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
    this.timer = setInterval(() => {
      this.particlePhase += 0.08
      if (this.particlePhase > 1000) {
        this.particlePhase = 0
      }
    }, 32)
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private getParticleOffsetX(index: number): number {
    return Math.sin(this.particlePhase + index) * 2
  }

  private getParticleOffsetY(index: number): number {
    return Math.cos(this.particlePhase + index * 0.7) * 3
  }

  build() {
    ForEach(this.particles, (particle: ImportParticle, index: number) => {
      Row()
        .width(particle.size)
        .height(particle.size)
        .backgroundColor(EmuColors.primary)
        .opacity(this.boosted ? Math.min(1, particle.opacity + 0.25) : particle.opacity)
        .position({
          x: particle.x + this.getParticleOffsetX(index),
          y: particle.y + this.getParticleOffsetY(index)
        })
    }, (_p: ImportParticle, index: number) => `particle-${index}`)
  }
}

@Entry
@ComponentV2
struct ImportEntryPage {
  @Local private hasGames: boolean = false
  @Local private isScanning: boolean = false
  @Local private scanProgress: number = 0
  @Local private scanStatusText: string = '正在扫描本地文件...'
  @Local private importButtonPressed: boolean = false
  @Local private particleBoosted: boolean = false
  @Local private foldDisplayMode: display.FoldDisplayMode = display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN
  @Local private importedGameCount: number = 0
  @Local private detectedPlatformCount: number = 0
  @Local private availableCoreCount: number = 0
  @Local private previewStatsReady: boolean = false
  @Local private previewStatusText: string = '以上仅反映当前库记录和已打包核心数量，不代表所有文件都能顺利运行。'
  private scanTimer: number = -1
  private pageActive: boolean = false
  private importTaskToken: number = 0
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('library')
  private foldDisplayModeListener: (mode: display.FoldDisplayMode) => void = (mode: display.FoldDisplayMode) => {
    if (!this.pageActive) {
      return
    }
    this.foldDisplayMode = mode
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('ImportEntryPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.resetImportState('这个页面现在还打不开，请稍后再试')
    })
  }

  aboutToAppear(): void {
    this.pageActive = true
    clearPendingImportUris()
    try {
      this.foldDisplayMode = display.getFoldDisplayMode()
    } catch (err) {
      LogHelper.error('ImportEntryPage', 'FoldDetect', `getFoldDisplayMode failed: ${err}`)
    }
    try {
      display.on('foldDisplayModeChange', this.foldDisplayModeListener)
    } catch (err) {
      LogHelper.error('ImportEntryPage', 'FoldDetect', `foldDisplayModeChange on failed: ${err}`)
    }
    void this.refreshPreviewStats()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.importTaskToken += 1
    this.stopScan()
    try {
      display.off('foldDisplayModeChange', this.foldDisplayModeListener)
    } catch (err) {
      LogHelper.error('ImportEntryPage', 'FoldDetect', `foldDisplayModeChange off failed: ${err}`)
    }
  }

  private stopScan(): void {
    if (this.scanTimer !== -1) {
      clearInterval(this.scanTimer)
      this.scanTimer = -1
    }
  }

  private beginImportTask(): number {
    this.importTaskToken += 1
    return this.importTaskToken
  }

  private isCurrentImportTask(token: number): boolean {
    return this.pageActive && token === this.importTaskToken
  }

  private async refreshPreviewStats(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.hasGames = false
      this.importedGameCount = 0
      this.detectedPlatformCount = 0
      this.availableCoreCount = 0
      this.previewStatsReady = false
      this.previewStatusText = '本地库概况现在还没读到，请稍后重试。'
      return
    }
    try {
      const records = await loadAllLibraryRecords(context)
      if (!this.pageActive) {
        return
      }
      const readyRecords = records.filter((item: LibraryRecord) => item.status === 'READY')
      const platforms: Set<string> = new Set()
      readyRecords.forEach((item: LibraryRecord) => {
        if (item.platform.length > 0) {
          platforms.add(item.platform)
        }
      })
      const installedCoreCount = await this.countInstalledCores(context)
      if (!this.pageActive) {
        return
      }
      this.hasGames = readyRecords.length > 0
      this.importedGameCount = readyRecords.length
      this.detectedPlatformCount = platforms.size
      this.availableCoreCount = installedCoreCount
      this.previewStatsReady = true
      this.previewStatusText = '以上仅反映当前库记录和已打包核心数量，不代表所有文件都能顺利运行。'
    } catch (err) {
      LogHelper.error('ImportEntryPage', 'Preview', `读取导入预览统计失败: ${(err as Error).message || String(err)}`)
      if (!this.pageActive) {
        return
      }
      this.hasGames = false
      this.importedGameCount = 0
      this.detectedPlatformCount = 0
      this.availableCoreCount = 0
      this.previewStatsReady = false
      this.previewStatusText = '本地库概况暂时没有读出来，请稍后重试。'
    }
  }

  private formatPreviewCount(value: number): string {
    return this.previewStatsReady ? `${value}` : '未读取'
  }

  private async countInstalledCores(context: common.UIAbilityContext): Promise<number> {
    let installedCount = 0
    for (let index = 0; index < LIBRETRO_CORE_CATALOG.length; index += 1) {
      const item = LIBRETRO_CORE_CATALOG[index]
      if (await this.hasCoreFile(context, item.soFile)) {
        installedCount += 1
      }
    }
    return installedCount
  }

  private async hasCoreFile(context: common.UIAbilityContext, soFile: string): Promise<boolean> {
    const abiCandidates: string[] = ['arm64-v8a', 'arm64', 'x86_64']
    for (let index = 0; index < abiCandidates.length; index += 1) {
      const path = `${context.bundleCodeDir}/libs/${abiCandidates[index]}/${soFile}`
      try {
        await fs.access(path)
        return true
      } catch (_err) {
        continue
      }
    }
    return false
  }

  private startImport(): void {
    if (this.isScanning) {
      return
    }
    clearPendingImportUris()
    this.isScanning = true
    this.scanProgress = 100
    this.scanStatusText = '正在打开文件选择器...'
    this.particleBoosted = true
    this.stopScan()
    const token = this.beginImportTask()
    void this.finishImportFlow(token)
  }

  private async finishImportFlow(token: number): Promise<void> {
    if (!this.isCurrentImportTask(token)) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.resetImportState('现在还打不开文件选择器，请稍后再试')
      return
    }

    try {
      const selection = await pickRomUris(context)
      if (!this.isCurrentImportTask(token)) {
        return
      }
      this.isScanning = false
      this.particleBoosted = false
      if (selection.failed) {
        clearPendingImportUris()
        this.resetImportState(selection.message.length > 0 ? selection.message : '系统文件选择器这次没有成功返回文件，请稍后再试')
        return
      }
      if (!selection.uris || selection.uris.length === 0) {
        clearPendingImportUris()
        this.scanProgress = 0
        this.scanStatusText = selection.message.length > 0 ? selection.message : '这次没有选中文件'
        return
      }

      setPendingImportUris(selection.uris)
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTaskOverlayPage' }).catch((err: Error) => {
        LogHelper.error('ImportEntryPage', 'Route', `pushUrl failed: ${err.message}`)
        clearPendingImportUris()
        this.resetImportState('导入结果页现在还打不开，请稍后再试')
      })
    } catch (err) {
      if (!this.isCurrentImportTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ImportEntryPage', 'Import', `选择导入文件失败: ${message}`)
      this.resetImportState('这次没有成功选中文件，请稍后重试')
    }
  }

  private resetImportState(statusText: string): void {
    this.isScanning = false
    this.particleBoosted = false
    this.scanProgress = 0
    this.scanStatusText = statusText
  }

  @Builder
  private MainContent() {
    Column() {
      Blank()
      ImportEmptyStateHero({
        isScanning: this.isScanning,
        scanProgress: this.scanProgress,
        scanStatusText: this.scanStatusText,
        buttonPressed: this.importButtonPressed,
        particleBoosted: this.particleBoosted,
        titleText: !this.previewStatsReady ? '导入本地游戏' : (this.hasGames ? '继续导入本地游戏' : '一键导入游戏，重温经典'),
        descriptionText: !this.previewStatsReady ?
          '本地库概况暂时没有读出来，你仍然可以直接选择 ROM、ISO 或部分常见压缩包开始导入。' :
          (this.hasGames ?
            '当前游戏库已有本地条目。你可以继续导入新的 ROM 或 ISO 文件。' :
            '请选择本地 ROM、ISO 或部分常见压缩包开始导入。'),
        footnoteText: '仅支持你合法拥有的游戏内容',
        onPrimaryTouch: (pressed: boolean) => {
          this.importButtonPressed = pressed
        },
        onPrimaryAction: () => {
          this.startImport()
        }
      })
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private InstructionPanel() {
    Column({ space: 24 }) {
      Text('导入说明')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Column({ space: 16 }) {
        this.InstructionItem('1', '支持格式', '可尝试导入部分常见 ROM、ISO 与压缩包，是否可用以后续导入结果为准')
        this.InstructionItem('2', '文件来源', '请确保导入的游戏文件来源合法')
        this.InstructionItem('3', '存储位置', '文件将被复制到应用沙箱目录')
        this.InstructionItem('4', '核心匹配', '系统会先尝试自动匹配核心；如果没匹配好，之后仍可在详情页调整')
      }
    }
    .width('100%')
    .padding(24)
    .backgroundColor('#0A0A0A')
    .borderRadius(8)
    .border({ width: 1, color: '#2A2A2A' })
  }

  @Builder
  private InstructionItem(number: string, title: string, description: string) {
    Row({ space: 16 }) {
      Text(number)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(16)
        .backgroundColor('#1A1A1A')
        .border({ width: 1, color: EmuColors.primary })

      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)

        Text(description)
          .fontSize(13)
          .fontColor('#ABABAB')
          .lineHeight(20)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private PreviewPanel() {
    Column({ space: 16 }) {
      Text('本地库概况')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Column({ space: 12 }) {
        this.PreviewItem('库内平台数', this.formatPreviewCount(this.detectedPlatformCount))
        this.PreviewItem('库内游戏条目', this.formatPreviewCount(this.importedGameCount))
        this.PreviewItem('已检测到的核心', this.formatPreviewCount(this.availableCoreCount))
      }

      Text(this.previewStatusText)
        .fontSize(12)
        .fontColor('#ABABAB')
        .lineHeight(18)
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#0A0A0A')
    .borderRadius(8)
    .border({ width: 1, color: '#2A2A2A' })
  }

  @Builder
  private PreviewItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#ABABAB')
        .layoutWeight(1)

      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .borderRadius(4)
    .backgroundColor('#0F0F0F')
  }

  @Builder
  private FoldedLayout() {
    Column() {
      this.MainContent()
    }
    .width('100%')
    .constraintSize({ maxWidth: 448 })
  }

  @Builder
  private HalfFoldedLayout() {
    Row({ space: 24 }) {
      Column() {
        this.MainContent()
      }
      .width('40%')

      Column() {
        Blank()
        this.InstructionPanel()
        Blank()
      }
      .width('60%')
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private FullyUnfoldedLayout() {
    Row({ space: 20 }) {
      Column() {
        this.MainContent()
      }
      .width('30%')

      Column() {
        Blank()
        this.InstructionPanel()
        Blank()
      }
      .width('40%')
      .layoutWeight(1)

      Column() {
        Blank()
        this.PreviewPanel()
        Blank()
      }
      .width('30%')
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: '碳影 / Carbon Shade',
        rightLabel: '本地导入',
        titleIcon: 'memory',
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        mutedTextColor: '#646464',
        iconSize: 16,
        rightIconSize: 18
      })

      Stack() {
        EmuPrecisionGridBackdrop()
        ParticleLayer({ boosted: this.particleBoosted })

        Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#04000000')

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [[0x00000000, 0.0], [0x33000000, 0.4], [0x77000000, 1.0]]
          })

        Column() {
          if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_FULL) {
            this.FullyUnfoldedLayout()
          } else if (this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_MAIN ||
                     this.foldDisplayMode === display.FoldDisplayMode.FOLD_DISPLAY_MODE_SUB) {
            this.HalfFoldedLayout()
          } else {
            this.FoldedLayout()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24 })

      EmuBottomNav({
        items: this.navItems,
        activeFontColor: EmuColors.primary,
        inactiveFontColor: '#FF666666',
        indicatorStyle: 'dot',
        overallOpacity: 0.86,
        panelBackgroundColor: '#E8000000',
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
