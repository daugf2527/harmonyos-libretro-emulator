import { common } from '@kit.AbilityKit'
import { display } from '@kit.ArkUI'
import { EmuHeaderBar, EmuPrecisionGridBackdrop } from '../components/EmuAppShell'
import { EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuBottomNav } from '../components/EmuBottomNav'
import { ImportEmptyStateHero } from '../components/ImportEmptyStateHero'
import { setPendingImportUris } from '../common/ImportTaskBridge'
import { EmuColors } from '../common/EmuUiTokens'
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
  private scanTimer: number = -1
  private pageActive: boolean = false
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('library')
  private foldDisplayModeListener: (mode: display.FoldDisplayMode) => void = (mode: display.FoldDisplayMode) => {
    this.foldDisplayMode = mode
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('ImportEntryPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
    })
  }

  aboutToAppear(): void {
    this.pageActive = true
    try {
      this.foldDisplayMode = display.getFoldDisplayMode()
    } catch (err) {
      LogHelper.error('ImportEntryPage', 'FoldDetect', `getFoldDisplayMode failed: ${err}`)
    }
    display.on('foldDisplayModeChange', this.foldDisplayModeListener)
    if (this.hasGames) {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
        LogHelper.error('ImportEntryPage', 'Route', `replaceUrl failed: ${err.message}`)
      })
    }
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.stopScan()
    display.off('foldDisplayModeChange', this.foldDisplayModeListener)
  }

  private stopScan(): void {
    if (this.scanTimer !== -1) {
      clearInterval(this.scanTimer)
      this.scanTimer = -1
    }
  }

  private startImport(): void {
    if (this.isScanning) {
      return
    }
    this.isScanning = true
    this.scanProgress = 100
    this.scanStatusText = '等待选择文件...'
    this.particleBoosted = true
    this.stopScan()
    void this.finishImportFlow()
  }

  private async finishImportFlow(): Promise<void> {
    if (!this.pageActive) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.resetImportState('获取导入上下文失败')
      return
    }

    const uris = await pickRomUris(context)
    if (!this.pageActive) {
      return
    }
    this.isScanning = false
    this.particleBoosted = false
    if (!uris || uris.length === 0) {
      this.scanProgress = 0
      this.scanStatusText = '未选择文件'
      return
    }

    setPendingImportUris(uris)
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTaskOverlayPage' }).catch((err: Error) => {
      LogHelper.error('ImportEntryPage', 'Route', `pushUrl failed: ${err.message}`)
    })
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
        this.InstructionItem('1', '支持格式', 'ROM、ISO、ZIP 等常见游戏镜像格式')
        this.InstructionItem('2', '文件来源', '请确保导入的游戏文件来源合法')
        this.InstructionItem('3', '存储位置', '文件将被复制到应用沙箱目录')
        this.InstructionItem('4', '核心匹配', '系统将自动匹配合适的模拟器核心')
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
      Text('导入预览')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Column({ space: 12 }) {
        this.PreviewItem('支持的平台', '30+')
        this.PreviewItem('已导入游戏', '0')
        this.PreviewItem('可用核心', '12')
      }
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
