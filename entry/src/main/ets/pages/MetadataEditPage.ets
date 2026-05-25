import { common } from '@kit.AbilityKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import {
  GameMetadataRecord,
  getGameMetadataByRomFile,
  upsertGameMetadata
} from '../common/GameMetadataRepository'
import {
  getLibraryRecordByRomFile,
  LibraryRecord
} from '../common/LibraryRepository'
import LogHelper from '../common/LogHelper'

interface MetadataEditRouteParams {
  romFile?: string
}

@Entry
@Component
struct MetadataEditPage {
  @State private romFile: string = ''
  @State private titleText: string = ''
  @State private publisherText: string = ''
  @State private overviewText: string = ''
  @State private releaseYearText: string = ''
  @State private platformText: string = ''
  @State private coverKeyText: string = ''
  @State private statusText: string = 'LOCAL_METADATA_EDITOR'
  private pageActive: boolean = false
  private pageTaskToken: number = 0

  aboutToAppear(): void {
    this.pageActive = true
    void this.loadMetadata()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.pageTaskToken += 1
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

  private resolveRomFile(): string {
    const params = this.getUIContext().getRouter().getParams() as MetadataEditRouteParams
    if (typeof params?.romFile === 'string' && params.romFile.length > 0) {
      return params.romFile
    }
    return this.romFile
  }

  private async loadMetadata(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.statusText = 'CONTEXT_MISSING'
      return
    }
    const targetRomFile = this.resolveRomFile()
    this.romFile = targetRomFile
    if (targetRomFile.length === 0) {
      this.statusText = 'ROM_CONTEXT_MISSING'
      return
    }
    const record = await getLibraryRecordByRomFile(context, targetRomFile)
    const metadata = await getGameMetadataByRomFile(context, targetRomFile)
    if (!this.isCurrentPageTask(token)) {
      return
    }
    this.applyInitialFields(record, metadata)
    this.statusText = metadata ? 'LOCAL_METADATA_LOADED' : 'LOCAL_METADATA_EMPTY'
  }

  private applyInitialFields(record: LibraryRecord | undefined, metadata: GameMetadataRecord | undefined): void {
    this.titleText = metadata?.title ?? record?.title ?? ''
    this.publisherText = metadata?.publisher ?? ''
    this.overviewText = metadata?.overview ?? ''
    this.releaseYearText = metadata && metadata.releaseYear > 0 ? `${metadata.releaseYear}` : ''
    this.platformText = metadata?.platform ?? record?.platform ?? ''
    this.coverKeyText = metadata?.coverKey ?? record?.coverKey ?? ''
  }

  private async saveMetadata(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.statusText = 'CONTEXT_MISSING'
      return
    }
    if (this.romFile.length === 0) {
      this.statusText = 'ROM_CONTEXT_MISSING'
      return
    }
    try {
      const record: GameMetadataRecord = {
        romFile: this.romFile,
        title: this.titleText.trim(),
        publisher: this.publisherText.trim(),
        overview: this.overviewText.trim(),
        releaseYear: this.parseReleaseYear(),
        platform: this.platformText.trim(),
        coverKey: this.coverKeyText.trim()
      }
      await upsertGameMetadata(context, record)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.statusText = 'LOCAL_METADATA_SAVED'
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('MetadataEditPage', 'Save', `保存本地 metadata 失败: ${message}`)
      this.statusText = 'LOCAL_METADATA_SAVE_FAILED'
    }
  }

  private parseReleaseYear(): number {
    const year = Number(this.releaseYearText.trim())
    if (!Number.isFinite(year) || year <= 0) {
      return 0
    }
    return Math.floor(year)
  }

  private returnToDetail(): void {
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/LibraryDetailPage',
      params: {
        romFile: this.romFile
      } as MetadataEditRouteParams
    }).catch((err: Error) => {
      LogHelper.error('MetadataEditPage', 'Route', `返回详情页失败: ${err.message}`)
    })
  }

  @Builder
  private Field(label: string, value: string, placeholder: string, fieldKey: string) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(EmuTypography.xs)
        .fontFamily('monospace')
        .fontColor(EmuColors.onSurfaceVariant)
        .letterSpacing(1.4)
      TextInput({
        text: value,
        placeholder: placeholder
      })
        .width('100%')
        .height(fieldKey === 'overview' ? 72 : 44)
        .fontSize(13)
        .fontColor(EmuColors.onSurface)
        .placeholderColor('#66757575')
        .backgroundColor(EmuColors.surfaceContainerLowest)
        .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
        .borderRadius(4)
        .onChange((nextValue: string) => {
          this.updateField(fieldKey, nextValue)
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private updateField(fieldKey: string, value: string): void {
    if (fieldKey === 'title') {
      this.titleText = value
      return
    }
    if (fieldKey === 'publisher') {
      this.publisherText = value
      return
    }
    if (fieldKey === 'overview') {
      this.overviewText = value
      return
    }
    if (fieldKey === 'releaseYear') {
      this.releaseYearText = value
      return
    }
    if (fieldKey === 'platform') {
      this.platformText = value
      return
    }
    if (fieldKey === 'coverKey') {
      this.coverKeyText = value
    }
  }

  build() {
    Column() {
      EmuHeaderBar({
        titleText: '碳影 / Carbon Shade',
        titleIcon: 'memory',
        rightLabel: this.statusText,
        rightIcon: 'settings_input_component',
        activeTextColor: EmuColors.primary,
        iconSize: 16,
        rightIconSize: 18
      })

      Scroll() {
        Column({ space: 18 }) {
          Text('本地游戏资料')
            .fontSize(EmuTypography.display)
            .fontWeight(FontWeight.Medium)
            .fontColor(EmuColors.onSurface)
            .width('100%')

          Text(this.romFile.length > 0 ? this.romFile : 'UNKNOWN_ROM')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .letterSpacing(1.2)
            .width('100%')

          this.Field('TITLE', this.titleText, 'Unknown', 'title')
          this.Field('PUBLISHER', this.publisherText, 'Unknown', 'publisher')
          this.Field('OVERVIEW', this.overviewText, 'Unknown', 'overview')
          this.Field('RELEASE YEAR', this.releaseYearText, 'Unknown', 'releaseYear')
          this.Field('PLATFORM', this.platformText, 'Unknown', 'platform')
          this.Field('COVER KEY', this.coverKeyText, 'Optional local cover key', 'coverKey')

          Row({ space: 12 }) {
            Button('保存')
              .layoutWeight(1)
              .height(44)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#004C0C')
              .backgroundColor(EmuColors.primary)
              .onClick(() => {
                void this.saveMetadata()
              })

            Button('返回')
              .layoutWeight(1)
              .height(44)
              .fontSize(13)
              .fontColor(EmuColors.onSurfaceVariant)
              .backgroundColor(EmuColors.surfaceContainerHigh)
              .onClick(() => {
                this.returnToDetail()
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .constraintSize({ maxWidth: 620 })
        .padding({ left: 24, right: 24, top: 30, bottom: 40 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
