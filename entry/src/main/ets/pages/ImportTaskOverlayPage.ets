import { common } from '@kit.AbilityKit'
import { EmuHeaderBar, GridBackground } from '../components/EmuAppShell'
import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuIcon } from '../components/EmuIcon'
import { consumePendingImportTask } from '../common/ImportTaskBridge'
import { EmuColors, EmuStateColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuButton, EmuButtonKind, EmuButtonShape, EmuButtonSize } from '../components/EmuButton'
import LogHelper from '../common/LogHelper'
import {
  importRomUris,
  inspectRomImportConflicts,
  RomImportConflictSummary,
  RomImportItemResult,
  RomImportProgress,
  RomImportResult
} from '../common/RomImportService'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import { PageLifecycleGuard } from '../common/PageLifecycleGuard'

type FeedbackState = 'CONFLICT' | 'IMPORTING' | 'SUCCESS' | 'ERROR'

const Colors = EmuColors

@ComponentV2
struct ImportPulseDot {
  @Local private visible: boolean = true
  private pulseTimer: number = -1

  aboutToAppear(): void {
    this.pulseTimer = setInterval(() => {
      this.visible = !this.visible
    }, 420)
  }

  aboutToDisappear(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
  }

  build() {
    Row()
      .width(4)
      .height(4)
      .borderRadius(2)
      .backgroundColor(Colors.primary)
      .opacity(this.visible ? 1 : 0.3)
  }
}

@ComponentV2
struct ImportPulseStatusText {
  @Param text: string = ''
  @Local private visible: boolean = true
  private pulseTimer: number = -1

  aboutToAppear(): void {
    this.pulseTimer = setInterval(() => {
      this.visible = !this.visible
    }, 420)
  }

  aboutToDisappear(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
  }

  build() {
    Text(this.text)
      .fontSize(9)
      .fontColor('#FF666666')
      .opacity(this.visible ? 1 : 0.5)
  }
}

@Entry
@ComponentV2
struct ImportTaskOverlayPage {
  @Local private feedbackState: FeedbackState = 'IMPORTING'
  @Local private overlayOpacity: number = 1
  @Local private overlayScale: number = 1
  @Local private cancelPressed: boolean = false
  @Local private etaText: string = '剩余时间待估算'
  @Local private sourceText: string = '文件来源：尚未选择'
  @Local private transferRateText: string = '--'
  @Local private progressPercent: number = 0
  @Local private processStatusText: string = '等待开始导入'
  @Local private processIdText: string = '本地文件导入'
  @Local private conflictTitleText: string = '检测到同名文件'
  @Local private conflictMessageText: string = '请选择本次导入任务的冲突处理策略'
  @Local private conflictDetailText: string = ''
  @Local private conflictNamesPreviewText: string = ''
  @Local private conflictNames: string[] = []
  @Local private resultTitleText: string = '导入结果'
  @Local private resultMessageText: string = '文件写入结果会在这里显示'
  @Local private resultDetailText: string = ''
  @Local private currentProgressText: string = '等待开始导入'
  @Local private importedNamesPreviewText: string = ''
  @Local private resultItems: RomImportItemResult[] = []
  private hasActualImportResult: boolean = false
  private currentImportUris: string[] = []
  private latestImportResult: RomImportResult | undefined = undefined
  private cancelRequested: boolean = false
  private importStartedAtMs: number = 0
  private pageActive: boolean = false
  private importTaskToken: number = 0
  private lifecycle: PageLifecycleGuard = new PageLifecycleGuard()
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('library')

  aboutToAppear(): void {
    this.pageActive = true
    this.lifecycle.activate()
    this.cancelRequested = false
    this.importTaskToken += 1
    const token = this.importTaskToken
    const pendingTask = consumePendingImportTask()
    if (pendingTask.state === 'PENDING' && pendingTask.uris.length > 0) {
      void this.prepareActualImport(pendingTask.uris, token)
      return
    }
    if (pendingTask.state === 'CONSUMED' && pendingTask.selectedCount > 0) {
      this.showConsumedImportTask(pendingTask.selectedCount)
      return
    }
    this.showMissingImportTask()
  }

  aboutToDisappear(): void {
    this.pageActive = false
    this.lifecycle.deactivate()
    this.cancelRequested = true
    this.importTaskToken += 1
  }

  private isCurrentImportTask(token: number): boolean {
    return this.pageActive && token === this.importTaskToken
  }

  private showMissingImportTask(): void {
    this.hasActualImportResult = true
    this.latestImportResult = undefined
    this.currentImportUris = []
    this.resultItems = []
    this.progressPercent = 0
    this.feedbackState = 'ERROR'
    this.resultTitleText = '还没选择要导入的文件'
    this.resultMessageText = '请先从导入页选择本地文件'
    this.resultDetailText = '返回上一页选择本地文件后再继续导入'
    this.importedNamesPreviewText = ''
    this.processStatusText = '没有待导入文件'
    this.processIdText = '尚未选择文件'
    this.currentProgressText = '等待选择要导入的文件'
    this.sourceText = '文件来源：尚未选择文件'
    this.transferRateText = '--'
    this.etaText = '剩余约 --'
  }

  private showConsumedImportTask(selectedCount: number): void {
    this.hasActualImportResult = true
    this.latestImportResult = undefined
    this.currentImportUris = []
    this.resultItems = []
    this.progressPercent = 0
    this.feedbackState = 'ERROR'
    this.resultTitleText = '这批导入流程已中断'
    this.resultMessageText = selectedCount > 0 ?
      `刚才选择的 ${selectedCount} 个文件没有保留在当前导入页里` :
      '刚才选择的文件没有保留在当前导入页里'
    this.resultDetailText = '请返回导入页重新选择同一批文件后再试'
    this.importedNamesPreviewText = ''
    this.processStatusText = '需要重新开始这批导入'
    this.processIdText = selectedCount > 0 ? `上一批文件：${selectedCount} 个` : '上一批文件未保留'
    this.currentProgressText = '需要重新选择要导入的文件'
    this.sourceText = '文件来源：上一批选择未保留'
    this.transferRateText = '--'
    this.etaText = '请重新选择文件'
  }

  private switchState(nextState: FeedbackState): void {
    if (this.feedbackState === nextState) {
      return
    }
    const token = this.lifecycle.beginTask()
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.overlayOpacity = 0
      this.overlayScale = 0.96
    })
    this.lifecycle.trackTimeout(setTimeout(() => {
      if (!this.lifecycle.isCurrentTask(token)) {
        return
      }
      this.feedbackState = nextState
      this.overlayOpacity = 0
      this.overlayScale = 0.96
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.overlayOpacity = 1
        this.overlayScale = 1
      })
    }, 120))
  }

  private onCancelTouch(event: TouchEvent): void {
    const eventType = Number(event.type)
    if (eventType === TouchType.Down) {
      this.cancelPressed = true
      return
    }
    if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
      this.cancelPressed = false
    }
  }

  private applyImportResult(result: RomImportResult): void {
    this.hasActualImportResult = true
    this.latestImportResult = result
    this.resultItems = [...result.items]
    this.overlayOpacity = 1
    this.overlayScale = 1
    if (!result.canceled) {
      this.progressPercent = 100
    }
    if (result.canceled) {
      this.feedbackState = 'ERROR'
      this.resultTitleText = '导入已取消'
      this.resultMessageText = `已处理 ${result.importedCount + result.overwrittenCount + result.skippedCount + result.failedCount}/${result.selectedCount} 个文件`
      this.resultDetailText = this.buildResultDetailText(result)
      this.importedNamesPreviewText = this.buildNamesPreview(
        result.importedNames.length > 0 ?
          result.importedNames :
          (result.overwrittenNames.length > 0 ? result.overwrittenNames : result.skippedNames)
      )
      return
    }
    if (result.importedCount > 0 || result.overwrittenCount > 0) {
      this.feedbackState = 'SUCCESS'
      this.resultTitleText = '文件写入完成'
      this.resultMessageText = `已写入 ${result.importedCount + result.overwrittenCount} 个本地文件`
      this.resultDetailText = this.buildResultDetailText(result)
      this.importedNamesPreviewText = this.buildNamesPreview(
        result.importedNames.length > 0 ? result.importedNames : result.overwrittenNames
      )
      return
    }
    this.feedbackState = 'ERROR'
    this.resultTitleText = '这批文件还没写进本地目录'
    if (result.skippedCount > 0 && result.failedCount === 0) {
      this.resultMessageText = '没有可导入的新文件'
    } else {
      this.resultMessageText = '这次没有找到可成功写入本地目录的游戏文件'
    }
    this.resultDetailText = this.buildResultDetailText(result)
    this.importedNamesPreviewText = this.buildNamesPreview(result.failedNames.length > 0 ? result.failedNames : result.skippedNames)
  }

  private buildResultDetailText(result: RomImportResult): string {
    const details: string[] = []
    if (result.importedCount > 0) {
      details.push(`成功 ${result.importedCount}`)
    }
    if (result.overwrittenCount > 0) {
      details.push(`覆盖 ${result.overwrittenCount}`)
    }
    if (result.skippedCount > 0) {
      details.push(`跳过 ${result.skippedCount}`)
    }
    if (result.failedCount > 0) {
      details.push(`未成功 ${result.failedCount}`)
    }
    return details.join(' / ')
  }

  private buildNamesPreview(names: string[]): string {
    if (names.length === 0) {
      return ''
    }
    return names.slice(0, 3).join('\n')
  }

  private async prepareActualImport(uris: string[], token: number): Promise<void> {
    if (!this.isCurrentImportTask(token)) {
      return
    }
    this.currentImportUris = [...uris]
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      if (this.isCurrentImportTask(token)) {
        this.applyImportResult(this.buildFailedImportResult(uris.length, false))
        this.resultTitleText = '当前导入流程暂时不可继续'
        this.resultMessageText = '这批文件还没有开始导入'
        this.resultDetailText = '请退出当前页面后重新进入导入流程'
      }
      return
    }

    try {
      const conflictSummary = await inspectRomImportConflicts(context, uris)
      if (!this.isCurrentImportTask(token)) {
        return
      }
      if (conflictSummary.conflictCount > 0) {
        this.applyConflictSummary(conflictSummary)
        return
      }
      await this.startActualImport(uris, token)
    } catch (err) {
      if (!this.isCurrentImportTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ImportTaskOverlayPage', 'Import', `准备导入任务失败: ${message}`)
      this.applyImportResult(this.buildFailedImportResult(uris.length, false))
      this.resultTitleText = '暂时没法继续导入'
      this.resultMessageText = '这批文件还没有开始导入'
      this.resultDetailText = '请返回上一页重新选择文件后再试'
    }
  }

  private applyConflictSummary(summary: RomImportConflictSummary): void {
    this.feedbackState = 'CONFLICT'
    this.hasActualImportResult = false
    this.latestImportResult = undefined
    this.progressPercent = 0
    this.conflictTitleText = '检测到同名文件'
    this.conflictMessageText = `发现 ${summary.conflictCount} 个同名文件，请选择保留现有文件还是替换为新文件`
    this.conflictDetailText = '可选：保留现有文件 / 替换现有文件 / 取消本次导入'
    this.conflictNamesPreviewText = this.buildNamesPreview(summary.conflictNames)
    this.conflictNames = [...summary.conflictNames]
    this.processStatusText = '请决定如何处理同名文件'
    this.processIdText = `同名文件：${summary.conflictCount}`
    this.currentProgressText = '等待冲突处理策略'
    this.sourceText = '文件来源：当前保留的本地文件'
    this.transferRateText = `${summary.conflictCount} 个冲突`
    this.etaText = '等待你选择处理方式'
  }

  private async startActualImport(uris: string[], token: number): Promise<void> {
    if (!this.isCurrentImportTask(token)) {
      return
    }
    this.currentImportUris = [...uris]
    this.cancelRequested = false
    this.importStartedAtMs = Date.now()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      if (this.isCurrentImportTask(token)) {
        this.applyImportResult(this.buildFailedImportResult(uris.length, false))
        this.resultTitleText = '当前导入流程暂时不可继续'
        this.resultMessageText = '这批文件还没有开始导入'
        this.resultDetailText = '请退出当前页面后重新进入导入流程'
      }
      return
    }

    this.feedbackState = 'IMPORTING'
    this.hasActualImportResult = false
    this.latestImportResult = undefined
    this.resultItems = []
    this.progressPercent = 0
    this.importedNamesPreviewText = ''
    try {
      const result = await importRomUris(context, uris, (progress: RomImportProgress) => {
        if (this.isCurrentImportTask(token)) {
          this.applyActualImportProgress(progress)
        }
      }, {
        overwriteExisting: false,
        shouldCancel: () => this.cancelRequested || !this.isCurrentImportTask(token)
      })
      if (!this.isCurrentImportTask(token)) {
        return
      }
      this.applyImportResult(result)
    } catch (err) {
      if (!this.isCurrentImportTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ImportTaskOverlayPage', 'Import', `执行导入失败: ${message}`)
      this.applyImportResult(this.buildFailedImportResult(uris.length, this.cancelRequested))
      this.resultTitleText = this.cancelRequested ? '导入已取消' : '这批文件还没写进本地目录'
      this.resultMessageText = this.cancelRequested ? '这批导入任务已取消' : '这批文件没有成功写入本地目录'
      this.resultDetailText = this.resolveImportFailureDetail(message)
    }
  }

  private async restartActualImportWithOverwrite(): Promise<void> {
    const token = this.importTaskToken
    if (!this.isCurrentImportTask(token)) {
      return
    }
    if (this.currentImportUris.length === 0) {
      return
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!context) {
      return
    }
    this.cancelRequested = false
    this.importStartedAtMs = Date.now()
    this.feedbackState = 'IMPORTING'
    this.hasActualImportResult = false
    this.latestImportResult = undefined
    this.resultItems = []
    this.progressPercent = 0
    this.importedNamesPreviewText = ''
    try {
      const result = await importRomUris(context, this.currentImportUris, (progress: RomImportProgress) => {
        if (this.isCurrentImportTask(token)) {
          this.applyActualImportProgress(progress)
        }
      }, {
        overwriteExisting: true,
        shouldCancel: () => this.cancelRequested || !this.isCurrentImportTask(token)
      })
      if (!this.isCurrentImportTask(token)) {
        return
      }
      this.applyImportResult(result)
    } catch (err) {
      if (!this.isCurrentImportTask(token)) {
        return
      }
      const message = (err as Error).message || String(err)
      LogHelper.error('ImportTaskOverlayPage', 'Import', `覆盖导入失败: ${message}`)
      this.applyImportResult(this.buildFailedImportResult(this.currentImportUris.length, this.cancelRequested))
      this.resultTitleText = this.cancelRequested ? '导入已取消' : '覆盖旧文件没有完成'
      this.resultMessageText = this.cancelRequested ? '这批导入任务已取消' : '旧文件替换到一半时停下来了'
      this.resultDetailText = this.resolveImportFailureDetail(message)
    }
  }

  private resolveImportFailureDetail(message: string): string {
    if (message.startsWith('IMPORT_MULTIFILE_ENTRY_READ_FAILED:')) {
      const fileName = message.substring('IMPORT_MULTIFILE_ENTRY_READ_FAILED:'.length).trim()
      return fileName.length > 0 ?
        `多文件入口 ${fileName} 没有读出来，请确认文件仍可访问后再试` :
        '多文件入口没有读出来，请确认文件仍可访问后再试'
    }
    return '请检查文件格式、配套依赖、磁盘空间或文件权限后再试'
  }

  private buildFailedImportResult(selectedCount: number, canceled: boolean): RomImportResult {
    return {
      selectedCount,
      importedCount: 0,
      overwrittenCount: 0,
      skippedCount: 0,
      failedCount: canceled ? 0 : selectedCount,
      canceled,
      importedNames: [],
      overwrittenNames: [],
      skippedNames: [],
      failedNames: [],
      items: []
    }
  }

  private applyActualImportProgress(progress: RomImportProgress): void {
    const total = progress.totalCount > 0 ? progress.totalCount : 1
    const completed = progress.completedCount > total ? total : progress.completedCount
    const totalBytes = progress.totalBytes > 0 ? progress.totalBytes : total
    const completedBytes = progress.completedBytes > totalBytes ? totalBytes : progress.completedBytes
    const percent = Math.floor((completedBytes / totalBytes) * 100)
    this.progressPercent = percent
    if (progress.stage === 'CANCELED') {
      this.currentProgressText = `取消中 ${completed}/${total}`
      this.processStatusText = '正在取消...'
      this.transferRateText = this.buildTransferRateText(progress, completedBytes)
      this.processIdText = `进度：${completed}/${total}`
      this.etaText = this.buildEtaText(progress, completedBytes, totalBytes)
      return
    }
    const currentIndex = progress.currentFileIndex > 0 ? progress.currentFileIndex : Math.min(completed + 1, total)
    this.currentProgressText = `正在导入 ${Math.min(currentIndex, total)}/${total}`
    this.sourceText = progress.currentFileName.length > 0 ? `当前文件：${progress.currentFileName}` : '文件来源：本地文件选择器'
    this.transferRateText = this.buildTransferRateText(progress, completedBytes)
    this.processStatusText = this.getImportStageText(progress.stage)
    this.processIdText = `进度：${completed}/${total}`
    this.etaText = this.buildEtaText(progress, completedBytes, totalBytes)
    this.importedNamesPreviewText = progress.currentFileName
  }

  private buildTransferRateText(progress: RomImportProgress, completedBytes: number): string {
    if (!progress.hasAccurateByteProgress || completedBytes <= 0 || this.importStartedAtMs <= 0) {
      return `${this.progressPercent}%`
    }
    const elapsedSeconds = Math.max(1, (Date.now() - this.importStartedAtMs) / 1000)
    const bytesPerSecond = completedBytes / elapsedSeconds
    return `${this.formatBytes(bytesPerSecond)}/s`
  }

  private getImportStageText(stage: string): string {
    if (stage === 'COPYING') {
      return '正在复制游戏文件...'
    }
    if (stage === 'OVERWRITING') {
      return '正在覆盖同名文件...'
    }
    if (stage === 'OVERWRITTEN') {
      return '已覆盖同名文件'
    }
    if (stage === 'SKIPPED') {
      return '已保留现有文件'
    }
    if (stage === 'EXISTS') {
      return '发现同名文件'
    }
    if (stage === 'DONE') {
      return '文件写入完成'
    }
    if (stage === 'FAILED') {
      return '未导入成功'
    }
    if (stage === 'MISSING_DEPENDENCY') {
      return '缺少导入依赖'
    }
    if (stage === 'CANCELED') {
      return '已取消'
    }
    return '正在处理文件...'
  }

  private buildEtaText(progress: RomImportProgress, completedBytes: number, totalBytes: number): string {
    if (!progress.hasAccurateByteProgress || completedBytes <= 0 || completedBytes >= totalBytes || this.importStartedAtMs <= 0) {
      return `进度 ${this.progressPercent}%`
    }
    const elapsedSeconds = Math.max(1, (Date.now() - this.importStartedAtMs) / 1000)
    const bytesPerSecond = completedBytes / elapsedSeconds
    if (bytesPerSecond <= 0) {
      return `进度 ${this.progressPercent}%`
    }
    const etaSeconds = Math.max(0, Math.ceil((totalBytes - completedBytes) / bytesPerSecond))
    const minutes = Math.floor(etaSeconds / 60).toString().padStart(2, '0')
    const seconds = (etaSeconds % 60).toString().padStart(2, '0')
    return `剩余约 ${minutes}:${seconds}`
  }

  private formatBytes(bytes: number): string {
    const normalized = Math.max(0, bytes)
    if (normalized >= 1024 * 1024 * 1024) {
      return `${(normalized / (1024 * 1024 * 1024)).toFixed(2)} GB`
    }
    if (normalized >= 1024 * 1024) {
      return `${(normalized / (1024 * 1024)).toFixed(1)} MB`
    }
    if (normalized >= 1024) {
      return `${(normalized / 1024).toFixed(1)} KB`
    }
    return `${Math.floor(normalized)} B`
  }

  private getResultStatusText(item: RomImportItemResult): string {
    if (item.status === 'IMPORTED') {
      return '已写入'
    }
    if (item.status === 'OVERWRITTEN') {
      return '已覆盖'
    }
    if (item.status === 'SKIPPED') {
      return '已跳过'
    }
    if (item.status === 'FAILED') {
      return '未成功'
    }
    return '已取消'
  }

  private getResultStatusColor(item: RomImportItemResult): string {
    if (item.status === 'IMPORTED' || item.status === 'OVERWRITTEN') {
      return Colors.primary
    }
    if (item.status === 'SKIPPED') {
      return Colors.onSurfaceVariant
    }
    // FAILED 与 CANCELLED 当前统一为 danger 色；若需视觉区分两态，应在 EmuStateColors 加 cancelled token。
    return EmuStateColors.dangerDefault
  }

  private getResultDetailText(item: RomImportItemResult): string {
    const detail = `${item.detail}`.trim()
    if (detail.length === 0) {
      return item.status === 'FAILED' ? '这项文件还没有写进本地目录，请稍后重试' : '已处理当前文件'
    }
    if (detail === 'IMPORT_DIR_REJECTED') {
      return '游戏库导入目录现在还不能写入'
    }
    if (detail.startsWith('MISSING_DEPENDENCY: ')) {
      return `缺少配套文件：${detail.substring('MISSING_DEPENDENCY: '.length)}`
    }
    if (detail.startsWith('IMPORT_MULTIFILE_ENTRY_READ_FAILED:')) {
      const fileName = detail.substring('IMPORT_MULTIFILE_ENTRY_READ_FAILED:'.length).trim()
      return fileName.length > 0 ?
        `这个多文件入口没有读出来：${fileName}` :
        '这个多文件入口没有读出来，请确认文件仍可访问'
    }
    if (detail === '不支持的文件格式') {
      return '当前文件格式暂不支持导入'
    }
    if (detail === '目标文件已存在') {
      return '游戏库里已经有同名文件'
    }
    if (detail === '依赖文件已存在') {
      return '配套依赖文件已存在，已跳过重复导入'
    }
    if (detail === '已覆盖写入目标文件') {
      return '已用这次选择的文件替换旧文件'
    }
    if (detail === '已成功写入本地游戏目录') {
      return '已写入本地游戏目录'
    }
    if (detail === '已作为多文件依赖写入本地游戏目录') {
      return '已作为配套文件写入本地目录'
    }
    if (detail === '任务在复制开始前取消') {
      return '导入已取消，文件还没开始复制'
    }
    if (detail === '覆盖过程中取消，原文件已保留') {
      return '导入已取消，原有文件已经保留'
    }
    if (detail === '复制过程中取消，已清理未完成文件') {
      return '导入已取消，未完成的文件已经清理'
    }
    if (detail.startsWith('IMPORT_') || detail.endsWith('_REJECTED') || detail.endsWith('_ERROR')) {
      return item.status === 'FAILED' ? '当前文件还没有写进本地目录' : '当前文件已跳过'
    }
    return detail
  }

  @Builder
  private ResultItemsList(items: RomImportItemResult[]) {
    Scroll() {
      Column({ space: 8 }) {
        ForEach(items, (item: RomImportItemResult, index: number) => {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(item.fileName)
                .width('100%')
                .fontSize(EmuTypography.sm)
                .fontWeight(FontWeight.Medium)
                .fontColor(Colors.onSurface)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.getResultDetailText(item))
                .width('100%')
                .fontSize(EmuTypography.xs)
                                .fontColor(Colors.onSurfaceVariant)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(this.getResultStatusText(item))
              .fontSize(9)
                            .fontColor(this.getResultStatusColor(item))
              .letterSpacing(0.8)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor('#141414')
          .borderRadius(8)
          .border({ width: 0.5, color: '#22333333', style: BorderStyle.Solid })
        }, (item: RomImportItemResult, index: number) => `${item.status}-${item.fileName}-${index}`)
      }
      .width('100%')
    }
    .width('100%')
    .height(Math.min(220, Math.max(80, items.length * 64)))
    .scrollBar(BarState.Off)
  }

  @Builder
  private ConflictNamesList(names: string[]) {
    Scroll() {
      Column({ space: 8 }) {
        ForEach(names, (name: string, index: number) => {
          Row() {
            Text(name)
              .width('100%')
              .fontSize(11)
                            .fontColor(Colors.onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor('#141414')
          .borderRadius(8)
          .border({ width: 0.5, color: '#22333333', style: BorderStyle.Solid })
        }, (name: string, index: number) => `${name}-${index}`)
      }
      .width('100%')
    }
    .width('100%')
    .height(Math.min(200, Math.max(72, names.length * 46)))
    .scrollBar(BarState.Off)
  }

  private handleRetryAction(): void {
    if (this.currentImportUris.length > 0) {
      void this.startActualImport(this.currentImportUris, this.importTaskToken)
      return
    }
    this.replaceUrl('pages/ImportEntryPage')
  }

  private handleDismissAction(): void {
    this.replaceUrl('pages/ImportEntryPage')
  }

  private handleCancelAction(): void {
    if (!this.hasActualImportResult && this.currentImportUris.length > 0) {
      this.cancelRequested = true
      this.processStatusText = '正在取消这批导入'
      return
    }
    this.handleDismissAction()
  }

  private canOverwriteExisting(): boolean {
    return !!this.latestImportResult &&
      this.latestImportResult.skippedCount > 0 &&
      this.currentImportUris.length > 0
  }

  private replaceUrl(url: string): void {
    this.getUIContext().getRouter().replaceUrl({ url: url }).catch((err: Error) => {
      LogHelper.error('ImportTaskOverlayPage', 'Route', `replaceUrl failed: ${err.message}`)
      this.resultMessageText = '现在还跳不回目标页面，请稍后再试'
    })
  }

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'library')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        LogHelper.error('ImportTaskOverlayPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
        this.resultMessageText = '现在还回不到游戏库，请稍后再试'
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('ImportTaskOverlayPage', 'Route', `pushUrl ${route} failed: ${err.message}`)
      this.resultMessageText = '这个页面现在还打不开，请稍后再试'
    })
  }

  build() {
    Stack() {
      Column() {
        EmuHeaderBar({
          titleText: '碳影 / Carbon Shade',
          titleIcon: 'terminal',
          rightLabel: '导入进度',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          mutedTextColor: '#7A7A7A',
          iconSize: 18,
          rightIconSize: 18
        })
        this.BackgroundWorkspace()
        EmuBottomNav({
          items: this.navItems,
          activeFontColor: '#FFE5E5E5',
          inactiveFontColor: '#FF666666',
          indicatorStyle: 'line',
          overallOpacity: 1,
          panelBackgroundColor: '#F2000000',
          onItemClick: (key: string) => {
            this.onBottomNavClick(key)
          }
        })
      }
      .width('100%')
      .height('100%')

      this.ImportOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private BackgroundWorkspace() {
    Stack() {
      GridBackground({ gridSize: 40, lineColor: '#1A484848', lineWidth: 0.5 })

      Column({ space: 20 }) {
        Column({ space: 16 }) {
          Row() {
            Text('本地导入状态')
              .fontSize(EmuTypography.xs)
                            .fontColor(Colors.onSurfaceVariant)
              .letterSpacing(1.5)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          Row({ space: 3 }) {
            Column().width(4).height(16).backgroundColor(Colors.primary)
            Column().width(4).height(12).backgroundColor('#6600FF41')
            Column().width(4).height(24).backgroundColor(Colors.primary)
            Column().width(4).height(10).backgroundColor('#3300FF41')
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Colors.surfaceContainer)
        .border({ width: { left: 2 }, color: Colors.primary, style: BorderStyle.Solid })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: 240 })

        Row({ space: 16 }) {
          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('#33262626')
            .border({ width: 0.5, color: '#26FFFFFF', style: BorderStyle.Solid })
          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('#33262626')
            .border({ width: 0.5, color: '#26FFFFFF', style: BorderStyle.Solid })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 32, right: 32, top: 28, bottom: 28 })
    }
    .width('100%')
    .layoutWeight(1)
    .blur(28)
    .opacity(0.06)
  }

  @Builder
  private ImportOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#C9000000')
        .backdropBlur(28)

      Column() {
        Row()
          .width('100%')
          .height(1)
          .linearGradient({
            angle: 90,
            colors: [[0x00000000, 0.0], [0x4D00FF41, 0.5], [0x00000000, 1.0]]
          })

        if (this.feedbackState === 'CONFLICT') {
          this.ConflictState()
        } else if (this.feedbackState === 'IMPORTING') {
          this.ImportingState()
        } else if (this.feedbackState === 'SUCCESS') {
          this.SuccessState()
        } else {
          this.ErrorState()
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 760, minHeight: 300 })
      .backgroundColor('#FF0A0A0A')
      .border({ width: 0.5, color: '#1AFFFFFF', style: BorderStyle.Solid })
      .shadow({ radius: 36, color: '#99000000', offsetX: 0, offsetY: 10 })
      .clip(true)
      .opacity(this.overlayOpacity)
      .scale({ x: this.overlayScale, y: this.overlayScale })
      .margin({ left: 0, right: 0 })
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ImportingState() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 2 }) {
          Text('正在导入')
            .fontSize(EmuTypography.xs)
                        .fontColor(Colors.primary)
            .letterSpacing(1.4)

          Text(this.currentProgressText)
            .fontSize(EmuTypography.xxl)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)

        Text(this.etaText)
          .fontSize(EmuTypography.xs)
                    .fontColor(Colors.onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 26 })

      Stack() {
        Row()
          .width('100%')
          .height(3)
          .backgroundColor(Colors.surfaceContainerHighest)

        Row()
          .width(`${this.progressPercent}%`)
          .height(3)
          .backgroundColor(Colors.primary)
          .shadow({ radius: 8, color: '#6600FF41', offsetX: 0, offsetY: 0 })
          .align(Alignment.Start)
      }
      .width('100%')
      .margin({ bottom: 18 })

      Row() {
        Row({ space: 8 }) {
          ImportPulseDot()

          Text(this.sourceText)
            .layoutWeight(1)
            .fontSize(11)
                        .fontColor(Colors.onSurfaceVariant)
            .letterSpacing(0.3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)

        Text(this.transferRateText)
          .fontSize(11)
                    .fontColor(Colors.onSurfaceVariant)
          .maxLines(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 30 })

      if (this.importedNamesPreviewText.length > 0) {
        Text(this.importedNamesPreviewText)
          .width('100%')
          .fontSize(11)
                    .fontColor(Colors.onSurfaceVariant)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 18 })
      }

      Row() {
        Button('取消导入')
          .fontSize(EmuTypography.xs)
          .fontWeight(FontWeight.Bold)
                    .fontColor(Colors.onSurfaceVariant)
          .height(48)
          .padding({ left: 28, right: 28 })
          .border({ width: 0.5, color: '#4D757575', style: BorderStyle.Solid })
          .backgroundColor(this.cancelPressed ? Colors.surfaceContainerHighest : Color.Transparent)
          .scale({ x: this.cancelPressed ? 0.95 : 1, y: this.cancelPressed ? 0.95 : 1 })
          .onTouch((event: TouchEvent) => this.onCancelTouch(event))
          .onClick(() => {
            this.handleCancelAction()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: 22 })

      Row() {
        Text(this.processIdText)
          .fontSize(9)
                    .fontColor('#FF666666')

        ImportPulseStatusText({ text: this.processStatusText })
      }
      .width('100%')
      .height(30)
      .padding({ left: 32, right: 32, top: 8, bottom: 8 })
      .backgroundColor(Colors.surfaceContainerLow)
      .border({ width: { top: 0.5 }, color: '#1AFFFFFF', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 60, right: 60, top: 58 })
  }

  @Builder
  private ConflictState() {
    Column({ space: 0 }) {
      Row() {
        EmuIcon({
          name: 'warning',
          iconSize: 30
        })
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#0DED7F64')
      .border({ width: 0.5, color: '#33ED7F64', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Text(this.conflictTitleText)
        .fontSize(EmuTypography.xl)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.onSurface)
        .margin({ bottom: 4 })

      Text(this.conflictMessageText)
        .fontSize(EmuTypography.md)
        .fontColor(Colors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      if (this.conflictDetailText.length > 0) {
        Text(this.conflictDetailText)
          .fontSize(11)
                    .fontColor('#9A6D5954')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })
      }

      if (this.conflictNames.length > 0) {
        Column() {
          this.ConflictNamesList(this.conflictNames)
        }
        .width('100%')
        .margin({ bottom: 20 })
      }

      EmuButton({
        label: '全部跳过并继续',
        kind: EmuButtonKind.SECONDARY,
        buttonSize: EmuButtonSize.COMPACT,
        shape: EmuButtonShape.PILL,
        tinted: true,
        onTap: () => { void this.startActualImport(this.currentImportUris, this.importTaskToken) }
      })
        .width('100%')
        .margin({ bottom: 12 })

      EmuButton({
        label: '全部覆盖并继续',
        kind: EmuButtonKind.SECONDARY,
        buttonSize: EmuButtonSize.COMPACT,
        shape: EmuButtonShape.PILL,
        tinted: true,
        onTap: () => { void this.restartActualImportWithOverwrite() }
      })
        .width('100%')
        .margin({ bottom: 12 })

      EmuButton({
        label: '取消本次任务',
        kind: EmuButtonKind.GHOST,
        buttonSize: EmuButtonSize.COMPACT,
        shape: EmuButtonShape.PILL,
        onTap: () => { this.replaceUrl('pages/ImportEntryPage') }
      })
        .width('100%')
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SuccessState() {
    Column({ space: 0 }) {
      Row() {
        EmuIcon({
          name: 'check_circle',
          iconSize: 30
        })
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#0D00FF41')
      .border({ width: 0.5, color: '#3300FF41', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Text(this.resultTitleText)
        .fontSize(EmuTypography.xl)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.onSurface)
        .margin({ bottom: 4 })

      Text(this.resultMessageText)
        .fontSize(EmuTypography.md)
        .fontColor(Colors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 28 })

      if (this.resultDetailText.length > 0) {
        Text(this.resultDetailText)
          .fontSize(11)
                    .fontColor('#8AABABAB')
          .margin({ bottom: 16 })
      }

      if (this.resultItems.length > 0) {
        Column() {
          this.ResultItemsList(this.resultItems)
        }
        .width('100%')
        .margin({ bottom: 16 })
      } else if (this.importedNamesPreviewText.length > 0) {
        Text(this.importedNamesPreviewText)
          .width('100%')
          .fontSize(11)
                    .fontColor('#8AABABAB')
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 16 })
      }

      if (this.canOverwriteExisting()) {
        EmuButton({
          label: '覆盖已存在',
          kind: EmuButtonKind.SECONDARY,
          buttonSize: EmuButtonSize.COMPACT,
          shape: EmuButtonShape.PILL,
          tinted: true,
          onTap: () => { void this.restartActualImportWithOverwrite() }
        })
          .width('100%')
          .margin({ bottom: 16 })
      }

      EmuButton({
        label: '返回游戏库',
        kind: EmuButtonKind.PRIMARY,
        buttonSize: EmuButtonSize.COMPACT,
        shape: EmuButtonShape.PILL,
        tinted: true,
        onTap: () => { this.replaceUrl('pages/LibraryPage') }
      })
        .width('100%')
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column({ space: 0 }) {
      Row() {
        EmuIcon({
          name: 'warning',
          iconSize: 30
        })
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#0DED7F64')
      .border({ width: 0.5, color: '#33ED7F64', style: BorderStyle.Solid })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Text(this.resultTitleText)
        .fontSize(EmuTypography.xl)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.onSurface)
        .margin({ bottom: 4 })

      Text(this.resultMessageText)
        .fontSize(EmuTypography.md)
        .fontColor(Colors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      if (this.resultDetailText.length > 0) {
        Text(this.resultDetailText)
          .fontSize(11)
                    .fontColor('#9A6D5954')
          .margin({ bottom: 16 })
      }

      if (this.resultItems.length > 0) {
        Column() {
          this.ResultItemsList(this.resultItems)
        }
        .width('100%')
        .margin({ bottom: 16 })
      } else if (this.importedNamesPreviewText.length > 0) {
        Text(this.importedNamesPreviewText)
          .width('100%')
          .fontSize(11)
                    .fontColor('#9A6D5954')
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 16 })
      }

      Row({ space: 8 }) {
        EmuButton({
          label: '取消',
          kind: EmuButtonKind.GHOST,
          buttonSize: EmuButtonSize.COMPACT,
          shape: EmuButtonShape.PILL,
          onTap: () => { this.handleDismissAction() }
        })
          .layoutWeight(1)

        EmuButton({
          label: '再试一次',
          kind: EmuButtonKind.DANGER,
          buttonSize: EmuButtonSize.COMPACT,
          shape: EmuButtonShape.PILL,
          tinted: true,
          onTap: () => { this.handleRetryAction() }
        })
          .layoutWeight(1)
      }
      .width('100%')

      if (this.canOverwriteExisting()) {
        EmuButton({
          label: '覆盖已存在并重试',
          kind: EmuButtonKind.SECONDARY,
          buttonSize: EmuButtonSize.COMPACT,
          shape: EmuButtonShape.PILL,
          tinted: true,
          onTap: () => { void this.restartActualImportWithOverwrite() }
        })
          .width('100%')
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(32)
    .alignItems(HorizontalAlign.Center)
  }

}

@Preview
@ComponentV2
// Preview-only wrapper keeps DevEco preview isolated from the entry page.
// homecheck-disable-next-line @performance/avoid-overusing-custom-component-check
struct ImportTaskOverlayPagePreview {
  build() {
    ImportTaskOverlayPage()
  }
}
