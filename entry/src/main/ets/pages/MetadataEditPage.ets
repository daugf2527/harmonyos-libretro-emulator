import { common } from '@kit.AbilityKit'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import {
  getLibraryRecordByRomFile,
  LibraryMetadataPatch,
  LibraryRecord,
  updateLibraryRecordMetadata
} from '../common/LibraryRepository'
import LogHelper from '../common/LogHelper'

interface MetadataEditRouteParams {
  romFile?: string
}

@Entry
@ComponentV2
struct MetadataEditPage {
  @Local private romFile: string = ''
  @Local private titleText: string = ''
  @Local private publisherText: string = ''
  @Local private overviewText: string = ''
  @Local private releaseYearText: string = ''
  @Local private platformText: string = ''
  @Local private coverKeyText: string = ''
  @Local private statusText: string = '资料编辑'
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
      this.statusText = '现在还不能读取本地资料，请稍后再试'
      return
    }
    const targetRomFile = this.resolveRomFile()
    this.romFile = targetRomFile
    if (targetRomFile.length === 0) {
      this.statusText = '未找到对应游戏条目'
      return
    }
    try {
      const record = await getLibraryRecordByRomFile(context, targetRomFile)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.applyInitialFields(record)
      this.statusText = record ? '本地资料已读到' : '当前条目暂无本地资料'
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('MetadataEditPage', 'Load', `读取本地 metadata 失败: ${message}`)
      this.applyInitialFields(undefined)
      this.statusText = '本地资料没有读出来，请稍后重试'
    }
  }

  private applyInitialFields(record: LibraryRecord | undefined): void {
    this.titleText = record?.title ?? ''
    this.publisherText = record?.publisher ?? ''
    this.overviewText = record?.overview ?? ''
    this.releaseYearText = record?.releaseYear && record.releaseYear > 0 ? `${record.releaseYear}` : ''
    this.platformText = record?.platform ?? ''
    this.coverKeyText = record?.coverKey ?? ''
  }

  private async saveMetadata(): Promise<void> {
    const token = this.beginPageTask()
    const context = this.getContext()
    if (!context) {
      this.statusText = '现在还不能保存资料，请稍后再试'
      return
    }
    if (this.romFile.length === 0) {
      this.statusText = '未找到对应游戏条目'
      return
    }
    try {
      const patchInput: LibraryMetadataPatch = this.buildMetadataPatchInput()
      await updateLibraryRecordMetadata(context, this.romFile, patchInput)
      if (!this.isCurrentPageTask(token)) {
        return
      }
      this.statusText = '资料已保存到本地'
    } catch (err) {
      if (!this.isCurrentPageTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('MetadataEditPage', 'Save', `保存本地 metadata 失败: ${message}`)
      this.statusText = '资料没有保存成功，请稍后重试'
    }
  }

  private parseReleaseYear(): number {
    const year = Number(this.releaseYearText.trim())
    if (!Number.isFinite(year) || year <= 0) {
      return 0
    }
    return Math.floor(year)
  }

  private buildMetadataPatchInput(): LibraryMetadataPatch {
    return {
      title: this.titleText.trim(),
      overview: this.overviewText.trim(),
      publisher: this.publisherText.trim(),
      releaseYear: this.parseReleaseYear(),
      platform: this.platformText.trim(),
      coverKey: this.coverKeyText.trim()
    }
  }

  private returnToDetail(): void {
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/LibraryDetailPage',
      params: {
        romFile: this.romFile
      } as MetadataEditRouteParams
    }).catch((err: Error) => {
      LogHelper.error('MetadataEditPage', 'Route', `返回详情页失败: ${err.message}`)
      this.statusText = '现在还回不到游戏详情，请稍后再试'
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

          Text(this.romFile.length > 0 ? this.romFile : '未找到 ROM 路径')
            .fontSize(EmuTypography.xs)
            .fontFamily('monospace')
            .fontColor(EmuColors.primary)
            .letterSpacing(1.2)
            .width('100%')

          this.Field('标题', this.titleText, '输入游戏标题', 'title')
          this.Field('发行方', this.publisherText, '输入发行方（可选）', 'publisher')
          this.Field('简介', this.overviewText, '输入本地简介（可选）', 'overview')
          this.Field('发行年份', this.releaseYearText, '例如 2004', 'releaseYear')
          this.Field('平台', this.platformText, '例如 GBA / PS / NDS', 'platform')
          this.Field('封面样式', this.coverKeyText, '留空使用默认封面样式', 'coverKey')

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
