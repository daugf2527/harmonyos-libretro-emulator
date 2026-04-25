import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuCoverArt } from '../components/EmuCoverArt'
import { EmuIcon } from '../components/EmuIcon'
import {
  createIndexRange,
  EmuColors,
  EmuMetrics
} from '../common/EmuUiTokens'
import { consumePendingLibraryDetailRequest } from '../common/LibraryDetailBridge'
import { setPendingLibraryLaunchRequest } from '../common/LibraryLaunchBridge'
import {
  getLibraryRecordByRomFile,
  LibraryRecord,
  updateLibraryRecordCover
} from '../common/LibraryRepository'
import LogHelper from '../common/LogHelper'

interface LibraryDetailRouteParams {
  romFile?: string
}

interface LibraryLaunchRouteParams {
  coreId?: string
  romFile?: string
  autoStart?: boolean
}

interface TelemetryPoint {
  x: number
  y: number
}

interface DetailTelemetrySnapshot {
  fpsText: string
  audioText: string
  dropText: string
  profile: number[]
}

@Entry
@Component
struct LibraryDetailPage {
  @State private navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: 'LIBRARY', isActive: true },
    { key: 'engine', iconName: 'terminal', label: 'ENGINE', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: 'INPUT', isActive: false },
    { key: 'system', iconName: 'tune', label: 'SYSTEM', isActive: false }
  ]
  @State private libraryRecord: LibraryRecord | undefined = undefined
  @State private showExtendedDetails: boolean = false
  @State private showActionMenu: boolean = false
  @State private showToast: boolean = false
  @State private toastMessage: string = ''
  @State private isLaunching: boolean = false
  @State private launchProgress: number = 0
  @State private launchStatusText: string = 'READY_TO_HANDOFF'
  @State private launchCpuText: string = 'FPS: --'
  @State private telemetryFpsText: string = '--.-'
  @State private telemetryCpuText: string = '--'
  @State private telemetryGpuText: string = '--'
  @State private heroScale: number = 1.04
  @State private telemetryScanOffset: number = -180
  @State private telemetryGlowOpacity: number = 0.2
  private readonly coverCycleKeys: string[] = ['', 'metroid_fusion', 'zelda_triforce']
  private readonly coverPalette: string[] = ['#274530', '#27405E', '#4E2A41', '#5A4331']
  private toastTimer: number = -1
  private visualTimer: number = -1

  aboutToAppear(): void {
    void this.loadRecord()
    this.startVisualLoop()
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
      this.toastTimer = -1
    }
    this.stopVisualLoop()
  }

  private async loadRecord(): Promise<void> {
    const romFile = this.resolveRequestedRomFile()
    if (romFile.length === 0) {
      this.showToastMessage('未找到详情上下文 DETAIL_MISSING')
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('上下文不可用 CONTEXT_MISSING')
      return
    }
    const record = await getLibraryRecordByRomFile(context, romFile)
    if (!record) {
      this.showToastMessage('条目不存在 RECORD_NOT_FOUND')
      return
    }
    this.libraryRecord = record
    this.applyTelemetrySnapshot(record)
  }

  private resolveRequestedRomFile(): string {
    const params = this.getUIContext().getRouter().getParams() as LibraryDetailRouteParams
    if (typeof params?.romFile === 'string' && params.romFile.length > 0) {
      return params.romFile
    }
    const request = consumePendingLibraryDetailRequest()
    if (request?.romFile && request.romFile.length > 0) {
      return request.romFile
    }
    return this.libraryRecord?.romFile ?? ''
  }

  private showToastMessage(message: string): void {
    this.toastMessage = message
    this.showToast = true
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer)
    }
    this.toastTimer = setTimeout(() => {
      this.showToast = false
      this.toastTimer = -1
    }, 2600)
  }

  private applyTelemetrySnapshot(record: LibraryRecord): void {
    const snapshot = this.buildTelemetrySnapshot(record)
    this.telemetryFpsText = snapshot.fpsText
    this.telemetryCpuText = snapshot.audioText
    this.telemetryGpuText = snapshot.dropText
    this.launchCpuText = `FPS: ${snapshot.fpsText}`
  }

  private getLocalizedTitle(record: LibraryRecord): string {
    return this.cleanFileName(record.fileName)
  }

  private getDisplayTitle(record: LibraryRecord): string {
    return record.title.toUpperCase()
  }

  private getSourceLabel(record: LibraryRecord): string {
    return record.sourceType === 'IMPORTED' ? 'USER IMPORT' : 'BUNDLED'
  }

  private getConsoleLabel(record: LibraryRecord): string {
    if (record.platform === 'SNES') {
      return 'SFC'
    }
    if (record.platform === 'FC') {
      return 'NES'
    }
    return record.platform
  }

  private getYearLabel(record: LibraryRecord): string {
    const tag = this.extractTaggedTokens(record.fileName).find((item: string) => /^[12][0-9]{3}$/.test(item))
    if (tag) {
      return tag
    }
    if (record.importedAt > 0) {
      return String(new Date(record.importedAt).getFullYear())
    }
    return '--'
  }

  private getLastPlayedText(record: LibraryRecord): string {
    if (record.lastPlayedAt <= 0) {
      return 'NEVER'
    }
    return this.formatDate(record.lastPlayedAt)
  }

  private getOverviewText(record: LibraryRecord): string {
    const segments: string[] = [
      `该条目来自${this.getSourceLabel(record)} ROM 库，当前库状态为 ${this.getStatusLabel(record)}。`,
      `系统识别平台为 ${record.platform}，默认核心为 ${record.preferredCoreId.toUpperCase()}。`,
      `ROM 文件名为 ${record.fileName}。`
    ]
    const region = this.getRegionLabel(record)
    if (region !== 'AUTO / UNKNOWN') {
      segments.push(`文件标签中识别到区域信息 ${region}。`)
    }
    if (record.importedAt > 0) {
      segments.push(`导入时间 ${this.formatDate(record.importedAt)}。`)
    }
    if (record.lastPlayedAt > 0) {
      segments.push(`最近一次启动时间 ${this.formatDate(record.lastPlayedAt)}，累计启动 ${record.playCount} 次。`)
      if (record.totalPlayTimeMs > 0) {
        segments.push(`真实累计运行时长 ${this.formatDuration(record.totalPlayTimeMs)}。`)
      }
    } else {
      segments.push('该条目尚未产生启动记录。')
    }
    return segments.join('')
  }

  private getRegionLabel(record: LibraryRecord): string {
    const tokens = this.extractTaggedTokens(record.fileName).map((item: string) => item.toUpperCase())
    const joined = tokens.join(' ')
    if (joined.indexOf('NTSC-J') >= 0 || joined.indexOf('JAPAN') >= 0 || joined.indexOf('JP') >= 0) {
      return 'JP / NTSC'
    }
    if (joined.indexOf('NTSC-U') >= 0 || joined.indexOf('USA') >= 0 || joined.indexOf('US') >= 0) {
      return 'US / NTSC'
    }
    if (joined.indexOf('PAL') >= 0 || joined.indexOf('EU') >= 0 || joined.indexOf('EUR') >= 0 ||
      joined.indexOf('EUROPE') >= 0) {
      return 'EU / PAL'
    }
    if (joined.indexOf('WORLD') >= 0) {
      return 'WORLD'
    }
    return 'AUTO / UNKNOWN'
  }

  private getEngineLabel(record: LibraryRecord): string {
    return `EMU_CORE_${record.preferredCoreId.toUpperCase()}`
  }

  private getPublisherLabel(record: LibraryRecord): string {
    return 'Unknown Publisher'
  }

  private getPlaytimeLabel(record: LibraryRecord): string {
    if (record.totalPlayTimeMs <= 0) {
      return '0h 00m'
    }
    return this.formatDuration(record.totalPlayTimeMs)
  }

  private formatDuration(durationMs: number): string {
    const totalMinutes = Math.floor(Math.max(0, durationMs) / 60000)
    const hours = Math.floor(totalMinutes / 60)
    const minutes = totalMinutes % 60
    return `${hours}h ${minutes.toString().padStart(2, '0')}m`
  }

  private getLaunchCountLabel(record: LibraryRecord): string {
    return `${record.playCount}`
  }

  private getRomVersionLabel(record: LibraryRecord): string {
    const platform = this.getConsoleLabel(record)
    const fileBase = this.cleanFileName(record.fileName).replace(/\s+/g, '_').toUpperCase()
    return `${platform}_v1.0_${fileBase.substring(0, Math.min(16, fileBase.length))}`
  }

  private getMemoryModeLabel(record: LibraryRecord): string {
    return record.sourceType === 'IMPORTED' ? 'DIRECT_MAPPING_L2' : 'BUNDLE_MOUNT_RO'
  }

  private getStatusLabel(record: LibraryRecord): string {
    return record.lastPlayedAt > 0 ? 'PLAYED' : 'READY'
  }

  private getImportedTimeText(record: LibraryRecord): string {
    const timestamp = record.importedAt > 0 ? record.importedAt : record.createdAt
    if (timestamp <= 0) {
      return '--'
    }
    return this.formatDate(timestamp)
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    return `${date.getFullYear()}-${month}-${day}`
  }

  private cleanFileName(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.')
    const withoutExt = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
    return withoutExt.replace(/[_-]+/g, ' ')
  }

  private extractTaggedTokens(fileName: string): string[] {
    const matches = fileName.match(/[\(\[]([^\)\]]+)[\)\]]/g) ?? []
    return matches.map((item: string) => {
      return item.substring(1, item.length - 1).trim()
    })
  }

  private buildTelemetrySnapshot(record: LibraryRecord): DetailTelemetrySnapshot {
    if (!this.hasRuntimeSnapshot(record)) {
      return {
        fpsText: '--.-',
        audioText: '--',
        dropText: '--',
        profile: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      }
    }
    const profile = this.buildRuntimeProfile(record)
    return {
      fpsText: record.lastRuntimeFps > 0 ? record.lastRuntimeFps.toFixed(1) : '--.-',
      audioText: this.formatPercent(record.lastRuntimeAudioBufferUsage),
      dropText: `${record.lastRuntimeVideoDrops}`,
      profile: profile
    }
  }

  private hasRuntimeSnapshot(record: LibraryRecord): boolean {
    return record.lastRuntimeUpdatedAt > 0 || record.lastSessionDurationMs > 0
  }

  private formatPercent(value: number): string {
    if (value <= 0) {
      return '--'
    }
    const percent = value <= 1 ? value * 100 : value
    return `${percent.toFixed(0)}%`
  }

  private buildRuntimeProfile(record: LibraryRecord): number[] {
    const fpsLevel = Math.min(52, Math.max(0, record.lastRuntimeFps / 60 * 52))
    const audioLevel = Math.min(52, Math.max(0, (record.lastRuntimeAudioBufferUsage <= 1 ?
      record.lastRuntimeAudioBufferUsage * 100 : record.lastRuntimeAudioBufferUsage) / 100 * 52))
    const dropLevel = Math.min(52, record.lastRuntimeVideoDrops * 4)
    const dupeLevel = Math.min(52, record.lastRuntimeVideoDupes * 3)
    const nullLevel = Math.min(52, record.lastRuntimeVideoNulls * 3)
    const underrunLevel = Math.min(52, record.lastRuntimeAudioUnderruns * 4)
    const overrunLevel = Math.min(52, record.lastRuntimeAudioOverruns * 4)
    return [
      fpsLevel,
      audioLevel,
      52 - dropLevel,
      52 - dupeLevel,
      52 - nullLevel,
      52 - underrunLevel,
      52 - overrunLevel,
      audioLevel,
      fpsLevel,
      52 - dropLevel,
      52 - dupeLevel,
      audioLevel,
      fpsLevel
    ]
  }

  private buildTelemetryBars(record: LibraryRecord): number[] {
    const snapshot = this.buildTelemetrySnapshot(record)
    const bars: number[] = []
    snapshot.profile.forEach((value: number) => bars.push(value))
    return bars
  }

  private buildTelemetryPoints(record: LibraryRecord): TelemetryPoint[] {
    const bars = this.buildTelemetryBars(record)
    const points: TelemetryPoint[] = []
    const spacing = 36
    const chartBottom = 76
    bars.forEach((height: number, index: number) => {
      points.push({
        x: index * spacing,
        y: chartBottom - Math.min(52, height)
      })
    })
    return points
  }

  private buildTelemetryStrokePath(record: LibraryRecord): string {
    const points = this.buildTelemetryPoints(record)
    if (points.length === 0) {
      return ''
    }
    let path = `M${points[0].x} ${points[0].y}`
    for (let index = 1; index < points.length; index += 1) {
      path += ` L${points[index].x} ${points[index].y}`
    }
    return path
  }

  private buildTelemetryFillPath(record: LibraryRecord): string {
    const points = this.buildTelemetryPoints(record)
    if (points.length === 0) {
      return ''
    }
    let path = this.buildTelemetryStrokePath(record)
    const lastPoint = points[points.length - 1]
    path += ` L${lastPoint.x} 96 L0 96 Z`
    return path
  }

  private getLaunchFileLabel(record: LibraryRecord): string {
    return record.fileName.replace(/\s+/g, '_').toUpperCase()
  }

  private startVisualLoop(): void {
    if (this.visualTimer !== -1) {
      return
    }
    let frame = 0
    this.visualTimer = setInterval(() => {
      frame += 1
      this.heroScale = 1.08 + Math.sin(frame / 18) * 0.035
      this.telemetryScanOffset = -180 + (frame % 100) * 5
      this.telemetryGlowOpacity = 0.14 + (Math.sin(frame / 6) + 1) * 0.1
    }, 90)
  }

  private stopVisualLoop(): void {
    if (this.visualTimer !== -1) {
      clearInterval(this.visualTimer)
      this.visualTimer = -1
    }
  }

  private async beginLaunchSequence(record: LibraryRecord): Promise<void> {
    if (this.isLaunching) {
      return
    }
    this.showActionMenu = false
    this.isLaunching = true
    this.applyTelemetrySnapshot(record)
    this.launchProgress = 100
    this.launchStatusText = 'HANDOFF_TO_ENGINE_PAGE'
    await Promise.resolve()
    this.commitLaunchNavigation(record)
  }

  private commitLaunchNavigation(record: LibraryRecord): void {
    const routeParams: LibraryLaunchRouteParams = {
      coreId: record.preferredCoreId,
      romFile: record.romFile,
      autoStart: true
    }
    setPendingLibraryLaunchRequest({
      coreId: record.preferredCoreId,
      romFile: record.romFile,
      autoStart: true
    })
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LibretroGamePage',
      params: routeParams
    }).catch((err: Error) => {
      this.isLaunching = false
      LogHelper.error('LibraryDetailPage', 'Route', `跳转游戏页失败: ${err.message}`)
      this.showToastMessage('启动失败 ROUTE_PUSH_FAIL')
    })
  }

  private getNextCoverKey(record: LibraryRecord): string {
    const currentIndex = this.coverCycleKeys.findIndex((item: string) => item === record.coverKey)
    if (currentIndex < 0) {
      return this.coverCycleKeys[1]
    }
    return this.coverCycleKeys[(currentIndex + 1) % this.coverCycleKeys.length]
  }

  private resolveCoverColorByKey(key: string): string {
    if (key === 'metroid_fusion') {
      return '#274530'
    }
    if (key === 'zelda_triforce') {
      return '#27405E'
    }
    return this.coverPalette[0]
  }

  private launchGame(): void {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    this.beginLaunchSequence(target)
  }

  private async cycleCoverPreset(): Promise<void> {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('封面更新失败 CONTEXT_MISSING')
      return
    }
    const nextCoverKey = this.getNextCoverKey(target)
    const nextCoverColor = this.resolveCoverColorByKey(nextCoverKey)
    const updated = await updateLibraryRecordCover(context, target.romFile, nextCoverKey, nextCoverColor)
    if (!updated) {
      this.showToastMessage('封面更新失败 COVER_WRITE_FAIL')
      return
    }
    this.libraryRecord = updated
    this.applyTelemetrySnapshot(updated)
    this.showActionMenu = false
    this.showToastMessage('已切换内置封面 COVER_UPDATED')
  }

  private async deleteSaveFiles(): Promise<void> {
    const target = this.libraryRecord
    if (!target) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      this.showToastMessage('存档删除失败 CONTEXT_MISSING')
      return
    }
    const saveDir = `${context.filesDir}/saves`
    const baseName = this.normalizeContentKey(this.cleanFileName(target.fileName))
    try {
      const entries = await fs.listFile(saveDir)
      const candidates = entries.filter((item: string) => this.isSaveCandidate(item, baseName))
      if (candidates.length === 0) {
        this.showToastMessage('未找到对应存档 SAVE_EMPTY')
        this.showActionMenu = false
        return
      }
      for (let index = 0; index < candidates.length; index += 1) {
        await fs.unlink(`${saveDir}/${candidates[index]}`)
      }
      this.showActionMenu = false
      this.showToastMessage(`已删除 ${candidates.length} 个存档 SAVE_PURGED`)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('LibraryDetailPage', 'Save', `删除存档失败: ${message}`)
      this.showToastMessage('存档删除失败 SAVE_PURGE_FAIL')
    }
  }

  private isSaveCandidate(fileName: string, baseName: string): boolean {
    const normalized = this.normalizeContentKey(fileName)
    return normalized.indexOf(baseName) === 0
  }

  private normalizeContentKey(value: string): string {
    return value.toLowerCase().replace(/[^a-z0-9]+/g, '')
  }

  private openLibraryPage(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/LibraryPage' }).catch((err: Error) => {
      LogHelper.error('LibraryDetailPage', 'Route', `返回库页失败: ${err.message}`)
    })
  }

  private onBottomNavClick(key: string): void {
    this.navItems = this.navItems.map((item: EmuBottomNavItem): EmuBottomNavItem => {
      return { key: item.key, iconName: item.iconName, label: item.label, isActive: item.key === key }
    })
    if (key === 'library') {
      this.openLibraryPage()
      return
    }
    if (key === 'engine' || key === 'input') {
      this.launchGame()
      return
    }
    if (key === 'system') {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/OnboardingPage' }).catch((err: Error) => {
        LogHelper.error('LibraryDetailPage', 'Route', `跳转系统页失败: ${err.message}`)
      })
    }
  }

  private handleActionMenuClick(actionKey: string): void {
    if (actionKey === 'launch') {
      this.launchGame()
      return
    }
    if (actionKey === 'details') {
      const record = this.libraryRecord
      this.showActionMenu = false
      this.showToastMessage(record ? `当前已在 ${record.title} 详情页` : '当前已在详情页')
      return
    }
    if (actionKey === 'cover') {
      void this.cycleCoverPreset()
      return
    }
    if (actionKey === 'purge_save') {
      void this.deleteSaveFiles()
    }
  }

  @Builder
  private TopBar() {
    Row() {
      Row({ space: 6 }) {
        EmuIcon({
          name: 'terminal',
          iconSize: 15
        })

        Text('EMU_OS // 0.1')
          .fontFamily('monospace')
          .fontSize(13)
          .fontColor(EmuColors.primary)
          .letterSpacing(2.2)
      }

      Blank()
        .layoutWeight(1)

      Row() {
        EmuIcon({
          name: 'settings_input_component',
          iconSize: 20
        })
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.showActionMenu = true
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: 390 })
    .height(EmuMetrics.headerHeight)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#E6000000')
    .backdropBlur(22)
    .border({
      width: { bottom: 0.5 },
      color: '#26262626',
      style: BorderStyle.Solid
    })
  }

  @Builder
  private HeroSection(record: LibraryRecord) {
    Column({ space: 18 }) {
      Stack() {
        Column()
          .width('100%')
          .aspectRatio(3 / 4)
          .backgroundColor(EmuColors.surfaceContainerLow)
          .borderRadius(8)
          .border({ width: 1, color: '#33484848', style: BorderStyle.Solid })
          .clip(true)

        EmuCoverArt({
          coverKey: record.coverKey,
          variant: 'recent'
        })
          .width('100%')
          .aspectRatio(3 / 4)
          .scale({ x: this.heroScale, y: this.heroScale })
          .borderRadius(8)
          .clip(true)

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              ['#11000000', 0],
              ['#05050505', 0.45],
              ['#99000000', 1]
            ]
          })
      }
      .width('100%')
      .shadow({ radius: 28, color: '#4400FF41', offsetX: 0, offsetY: 0 })

      Column({ space: 4 }) {
        Text(this.getDisplayTitle(record))
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor(EmuColors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getLocalizedTitle(record))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#CCABABAB')
          .letterSpacing(1.4)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  private PrimaryActions(record: LibraryRecord) {
    Column({ space: 12 }) {
      Column({ space: 2 }) {
        Text('启动游戏')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
          .letterSpacing(0.8)

        Text('LAUNCH GAME')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CC00FF41')
          .fontFamily('monospace')
          .letterSpacing(2.4)
      }
      .width('100%')
      .height(98)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#1900FF41')
      .border({ width: 1.5, color: '#6600FF41', style: BorderStyle.Solid })
      .shadow({ radius: 18, color: '#5500FF41', offsetX: 0, offsetY: 0 })
      .onClick(() => {
        this.beginLaunchSequence(record)
      })

      Row({ space: 12 }) {
        this.QuickActionButton('按键布局', 'videogame_asset', '游戏页控制面板即将收口到这里')
        this.QuickActionButton('画面风格', 'palette', `当前核心: ${record.preferredCoreId.toUpperCase()}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private QuickActionButton(label: string, iconName: string, toastMessage: string) {
    Row({ space: 8 }) {
      EmuIcon({
        name: iconName,
        tone: 'on_surface',
        iconSize: 18,
        opacityValue: 0.86
      })

      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(EmuColors.surfaceContainerHigh)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
    .borderRadius(4)
    .onClick(() => {
      this.showToastMessage(toastMessage)
    })
  }

  @Builder
  private SummaryCell(title: string, value: string, isLarge: boolean = false) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(isLarge ? 10 : 9)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8AABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.6)

      Text(value)
        .fontSize(isLarge ? 14 : 12)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(isLarge ? 78 : 72)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(EmuColors.surfaceContainerLow)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private DetailToggleRow() {
    Row({ space: 4 }) {
      Text('详情 (DETAILS)')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#B3B3B3')
        .fontFamily('monospace')
        .letterSpacing(1.6)

      Text(this.showExtendedDetails ? '˄' : '˅')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .onClick(() => {
      this.showExtendedDetails = !this.showExtendedDetails
    })
  }

  @Builder
  private SummarySection(record: LibraryRecord) {
      Column({ space: 8 }) {
        Row({ space: 1 }) {
          this.SummaryCell('CN NAME', this.getLocalizedTitle(record))
          this.SummaryCell('YEAR', this.getYearLabel(record))
          this.SummaryCell('CONSOLE', this.getConsoleLabel(record))
        }
        .width('100%')

      this.DetailToggleRow()

      if (this.showExtendedDetails) {
        Column({ space: 1 }) {
          Row({ space: 1 }) {
            this.SummaryCell('PUBLISHER', this.getPublisherLabel(record), true)
            this.SummaryCell('PLAYTIME', this.getPlaytimeLabel(record), true)
          }
          .width('100%')

          Row({ space: 1 }) {
            this.SummaryCell('ENGINE', this.getEngineLabel(record), true)
            this.SummaryCell('REGION', this.getRegionLabel(record), true)
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private TelemetryMeta(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(8)
        .fontColor('#889D9E9E')
        .fontFamily('monospace')

      Text(value)
        .fontSize(10)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TelemetrySection(record: LibraryRecord) {
    const strokePath = this.buildTelemetryStrokePath(record)
    const fillPath = this.buildTelemetryFillPath(record)
    const sessionStateText = this.hasRuntimeSnapshot(record) ? 'LAST SESSION' : 'NO SESSION DATA'
    Column({ space: 12 }) {
      Row() {
        Text('SYSTEM TELEMETRY')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCABABAB')
          .fontFamily('monospace')
          .letterSpacing(1.8)

        Row({ space: 6 }) {
          Row()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(EmuColors.primary)

          Text(`${this.telemetryFpsText} FPS // ${sessionStateText}`)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(EmuColors.primary)
            .fontFamily('monospace')
            .letterSpacing(1.2)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Stack() {
        Column({ space: 16 }) {
          ForEach(createIndexRange(4), (_: number) => {
            Row()
              .width('100%')
              .height(1)
              .backgroundColor('#142C2C2C')
          }, (index: number) => index.toString())
        }
        .width('100%')
        .height('100%')
        .padding({ top: 16, bottom: 16 })
        .justifyContent(FlexAlign.SpaceBetween)

        Path({
          width: 440,
          height: 96,
          commands: fillPath
        })
          .fill('#00FF41')
          .fillOpacity(0.06)
          .strokeWidth(0)
          .opacity(this.telemetryGlowOpacity + 0.12)

        Path({
          width: 440,
          height: 96,
          commands: strokePath
        })
          .fillOpacity(0)
          .stroke('#00FF41')
          .strokeWidth(1.6)
          .strokeOpacity(0.92)

        Column()
          .width(52)
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              ['#0000FF41', 0],
              ['#1800FF41', 0.5],
              ['#0000FF41', 1]
            ]
          })
          .align(Alignment.Start)
          .opacity(0.45)

        Column()
          .width('100%')
          .height(18)
          .linearGradient({
            angle: 180,
            colors: [
              ['#0000FF41', 0],
              ['#2200FF41', 0.52],
              ['#0000FF41', 1]
            ]
          })
          .translate({ y: this.telemetryScanOffset })
          .opacity(0.72)

        Row({ space: 26 }) {
          this.TelemetryMeta('AUDIO', this.telemetryCpuText)
          this.TelemetryMeta('DROPS', this.telemetryGpuText)
        }
        .align(Alignment.TopStart)
        .margin({ left: 12, top: 10 })
      }
      .width('100%')
      .height(96)
      .backgroundColor('#060606')
      .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
      .clip(true)
    }
    .width('100%')
  }

  @Builder
  private OverviewSection(record: LibraryRecord) {
    Column({ space: 12 }) {
      Text('OVERVIEW')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#CCABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.8)

      Stack() {
        Column() {
          Text(this.getOverviewText(record))
            .fontSize(14)
            .lineHeight(26)
            .fontColor('#E6E5E5E5')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18, bottom: 18 })
        .backgroundColor(EmuColors.surfaceContainer)
        .border({
          width: { left: 1.5 },
          color: '#6600FF41',
          style: BorderStyle.Solid
        })

        Text('◢')
          .fontSize(18)
          .fontColor('#22FFFFFF')
          .align(Alignment.TopEnd)
          .margin({ top: 8, right: 8 })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private CoreSpecRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#CCABABAB')

      Text(value)
        .fontSize(13)
        .fontColor(EmuColors.onSurface)
        .fontFamily('monospace')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .justifyContent(FlexAlign.SpaceBetween)
    .border({
      width: { bottom: 0.5 },
      color: '#1AABABAB',
      style: BorderStyle.Solid
    })
  }

  @Builder
  private CoreSpecsSection(record: LibraryRecord) {
    Column({ space: 10 }) {
      Text('CORE SPECIFICATIONS')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#CCABABAB')
        .fontFamily('monospace')
        .letterSpacing(1.8)

      Column() {
        this.CoreSpecRow('ROM Version', this.getRomVersionLabel(record))
        this.CoreSpecRow('Processor Cluster', this.getEngineLabel(record))
        this.CoreSpecRow('Memory Mode', this.getMemoryModeLabel(record))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private MenuTextAction(title: string, iconName: string, isDanger: boolean, actionKey: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(isDanger ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(isDanger ? EmuColors.error : EmuColors.onSurface)

      EmuIcon({
        name: iconName,
        tone: isDanger ? 'outline' : 'on_surface',
        iconSize: 20,
        opacityValue: 1
      })
    }
    .width('100%')
    .height(54)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.handleActionMenuClick(actionKey)
    })
  }

  @Builder
  private MenuCoverAction() {
    Row() {
      Text('修改封面')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)

      Row({ space: 10 }) {
        EmuIcon({
          name: 'image_edit_auto',
          tone: 'on_surface',
          iconSize: 24,
          opacityValue: 0.88
        })

        Text('AUTO')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#B8B8B8')
          .fontFamily('monospace')
          .letterSpacing(1.2)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(72)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.handleActionMenuClick('cover')
    })
  }

  @Builder
  private ActionMenuDivider() {
    Row()
      .width('100%')
      .height(1)
      .backgroundColor('#14FFFFFF')
      .margin({ left: 12, right: 12 })
  }

  @Builder
  private ActionMenuOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#B8000000')
        .backdropBlur(14)
        .onClick(() => {
          this.showActionMenu = false
        })

      Column({ space: 18 }) {
        Column({ space: 0 }) {
          this.MenuTextAction('启动游戏', 'play_arrow', false, 'launch')
          this.ActionMenuDivider()
          this.MenuTextAction('查看详情', 'info', false, 'details')
          this.MenuCoverAction()
          this.ActionMenuDivider()
          this.MenuTextAction('删除存档', 'delete_forever', true, 'purge_save')
        }
        .width('100%')
        .backgroundColor('#F0141414')
        .backdropBlur(24)
        .borderRadius(16)
        .border({ width: 0.8, color: '#33FFFFFF', style: BorderStyle.Solid })
        .shadow({ radius: 30, color: '#99000000', offsetX: 0, offsetY: 10 })

        Row() {
          Text('取消 CANCEL')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .fontFamily('monospace')
            .letterSpacing(1.2)
        }
        .width('100%')
        .height(54)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC1A1A1A')
        .borderRadius(14)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
        .onClick(() => {
          this.showActionMenu = false
        })
      }
      .width(240)
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  private SuccessToast() {
    Row({ space: 8 }) {
      Row()
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(EmuColors.primary)

      Text(this.toastMessage)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontFamily('monospace')
        .fontColor('#FF0E0E0E')
        .letterSpacing(0.8)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#E600FF41')
    .borderRadius(999)
    .shadow({ radius: 18, color: '#5500FF41', offsetX: 0, offsetY: 0 })
    .align(Alignment.Top)
    .margin({ top: 68 })
  }

  @Builder
  private LoadingScreenCorner(alignment: Alignment, size: number) {
    Stack() {
      Row()
        .width(size)
        .height(2)
        .backgroundColor(EmuColors.primary)
      Row()
        .width(2)
        .height(size)
        .backgroundColor(EmuColors.primary)
    }
    .align(alignment)
  }

  @Builder
  private LaunchOverlay(record: LibraryRecord) {
    Stack() {
      Column({ space: 2 }) {
        ForEach(createIndexRange(90), (_: number) => {
          Row()
            .width('100%')
            .height(1)
            .backgroundColor('#1400FF41')
        }, (index: number) => index.toString())
      }
      .width('100%')
      .height('100%')
      .opacity(0.12)

      Column() {
        Row() {
          Row({ space: 8 }) {
            EmuIcon({
              name: 'terminal',
              tone: 'primary',
              iconSize: 14,
              opacityValue: 1
            })

            Text('EMU_OS // KERNEL.LOAD')
              .fontSize(11)
              .fontColor(EmuColors.primary)
              .fontFamily('monospace')
              .letterSpacing(1.8)
          }

          Row({ space: 10 }) {
            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(EmuColors.primary)

              Text(this.launchCpuText)
                .fontSize(9)
                .fontColor(EmuColors.primary)
                .fontFamily('monospace')
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor('#161616')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(EmuColors.primary)

              Text(this.hasRuntimeSnapshot(record) ? 'RECORDED' : 'NO DATA')
                .fontSize(9)
                .fontColor(EmuColors.primary)
                .fontFamily('monospace')
            }
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor('#161616')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 16 })
        .justifyContent(FlexAlign.SpaceBetween)
        .border({
          width: { bottom: 0.5 },
          color: '#26262626',
          style: BorderStyle.Solid
        })

        Column({ space: 24 }) {
          Stack() {
            Column()
              .width(256)
              .height(320)
              .backgroundColor(EmuColors.surfaceContainerLow)
              .borderRadius(8)
              .border({ width: 1, color: '#33FFFFFF', style: BorderStyle.Solid })
              .clip(true)

            EmuCoverArt({
              coverKey: record.coverKey,
              variant: 'recent'
            })
              .width(256)
              .height(320)
              .scale({ x: 1.08, y: 1.08 })
              .borderRadius(8)
              .clip(true)

            Column()
              .width(256)
              .height(320)
              .backgroundColor('#8C000000')

            this.LoadingScreenCorner(Alignment.TopStart, 28)
              .margin({ top: -16, left: -16 })
            this.LoadingScreenCorner(Alignment.BottomEnd, 28)
              .margin({ bottom: -16, right: -16 })

            Stack() {
              Row()
                .width(80)
                .height(80)
                .borderRadius(40)
                .border({ width: 2, color: '#2200FF41', style: BorderStyle.Solid })

              Row()
                .width(80)
                .height(80)
                .borderRadius(40)
                .border({
                  width: { top: 2, right: 2 },
                  color: EmuColors.primary,
                  style: BorderStyle.Solid
                })
                .rotate({ angle: this.launchProgress * 3.6 })

              Row()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(EmuColors.primary)
                .shadow({ radius: 8, color: '#8800FF41', offsetX: 0, offsetY: 0 })
            }
            .align(Alignment.Center)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Text('System Status')
                .fontSize(9)
                .fontColor('#ABABAB')
                .fontFamily('monospace')
                .letterSpacing(2.2)

              Row()
                .width(1)
                .height(12)
                .backgroundColor('#3300FF41')

              Text(this.launchStatusText)
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(EmuColors.primary)
                .fontFamily('monospace')
                .letterSpacing(1.4)
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor('#171717')
            .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })

            Text('正在加载你的童年')
              .fontSize(26)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)

            Column({ space: 8 }) {
              Stack() {
                Row()
                  .width('100%')
                  .height(2)
                  .backgroundColor('#222222')

                Row()
                  .width(`${this.launchProgress}%`)
                  .height(2)
                  .backgroundColor(EmuColors.primary)
                  .shadow({ radius: 10, color: '#5500FF41', offsetX: 0, offsetY: 0 })
                  .align(Alignment.Start)
              }
              .width('100%')

              Row() {
                Text(this.getLaunchFileLabel(record))
                  .fontSize(9)
                  .fontColor('#666666')
                  .fontFamily('monospace')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Text(`${this.launchProgress}%`)
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(EmuColors.primary)
                  .fontFamily('monospace')
              }
              .width('100%')
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 28, right: 28, top: 24, bottom: 48 })
        .justifyContent(FlexAlign.Center)

        Text('Kinetic Obsidian // Virtual_Core_v0.1')
          .fontSize(10)
          .fontColor('#666666')
          .fontFamily('monospace')
          .letterSpacing(3.6)
          .margin({ bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F2000000')
      .backdropBlur(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private EmptyState() {
    Column({ space: 18 }) {
      Text('未找到详情页数据')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.onSurface)

      Text('请从游戏库条目的“查看详情”进入。')
        .fontSize(14)
        .fontColor('#CCABABAB')

      Row() {
        Text('返回游戏库')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(EmuColors.primary)
      }
      .padding({ left: 18, right: 18, top: 14, bottom: 14 })
      .backgroundColor(EmuColors.surfaceContainer)
      .border({ width: 1, color: '#6600FF41', style: BorderStyle.Solid })
      .borderRadius(6)
      .onClick(() => {
        this.openLibraryPage()
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        Row() {
          if (this.libraryRecord) {
            Scroll() {
              Column({ space: 30 }) {
                this.HeroSection(this.libraryRecord as LibraryRecord)
                this.PrimaryActions(this.libraryRecord as LibraryRecord)
                this.SummarySection(this.libraryRecord as LibraryRecord)
                this.TelemetrySection(this.libraryRecord as LibraryRecord)
                this.OverviewSection(this.libraryRecord as LibraryRecord)
                this.CoreSpecsSection(this.libraryRecord as LibraryRecord)
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 24, bottom: 40 })
            }
            .width('100%')
            .constraintSize({ maxWidth: 390 })
            .scrollBar(BarState.Off)
          } else {
            Column() {
              this.EmptyState()
            }
            .width('100%')
            .constraintSize({ maxWidth: 390 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)

        EmuBottomNav({
          items: this.navItems,
          activeFontColor: EmuColors.primary,
          inactiveFontColor: '#665E5E67',
          indicatorStyle: 'dot',
          overallOpacity: 1,
          panelBackgroundColor: '#F2000000',
          onItemClick: (key: string) => {
            this.onBottomNavClick(key)
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(EmuColors.background)

      if (this.showToast) {
        this.SuccessToast()
      }

      if (this.showActionMenu && this.libraryRecord) {
        this.ActionMenuOverlay()
      }

      if (this.isLaunching && this.libraryRecord) {
        this.LaunchOverlay(this.libraryRecord as LibraryRecord)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
