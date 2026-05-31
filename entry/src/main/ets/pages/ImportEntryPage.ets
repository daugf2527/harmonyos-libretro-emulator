import { common } from '@kit.AbilityKit'
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

@Component
struct ParticleLayer {
  @Prop boosted: boolean = false
  @State particlePhase: number = 0
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
@Component
struct ImportEntryPage {
  @State private hasGames: boolean = false
  @State private isScanning: boolean = false
  @State private scanProgress: number = 0
  @State private scanStatusText: string = '正在扫描本地文件...'
  @State private importButtonPressed: boolean = false
  @State private particleBoosted: boolean = false
  private scanTimer: number = -1
  private pageActive: boolean = false
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('library')

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
    if (this.hasGames) {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
        LogHelper.error('ImportEntryPage', 'Route', `replaceUrl failed: ${err.message}`)
      })
    }
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.stopScan()
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
          this.MainContent()
        }
        .width('100%')
        .constraintSize({ maxWidth: 448 })
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
