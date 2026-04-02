import { webview } from '@kit.ArkWeb'

const STITCH_IMPORT_TASK_URL: string = 'resource://rawfile/stitch/import_task_feedback.html'

interface WebProgressEvent {
  newProgress: number
}

@Entry
@Component
struct StitchImportTaskPage {
  @State private isLoading: boolean = true
  @State private hasLoadError: boolean = false
  @State private progressValue: number = 0
  @State private pageUrl: string = STITCH_IMPORT_TASK_URL
  private controller: webview.WebviewController = new webview.WebviewController()

  build() {
    Stack() {
      Web({
        src: this.pageUrl,
        controller: this.controller
      })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageBegin(() => {
          this.isLoading = true
          this.hasLoadError = false
          this.progressValue = 0
        })
        .onProgressChange((event?: WebProgressEvent) => {
          if (!event) {
            return
          }
          this.progressValue = event.newProgress
        })
        .onPageEnd(() => {
          this.progressValue = 100
          this.isLoading = false
          this.hasLoadError = false
        })
        .onErrorReceive(() => {
          this.hasLoadError = true
          this.isLoading = false
        })
        .width('100%')
        .height('100%')

      if (this.isLoading) {
        Column({ space: 12 }) {
          Text('正在加载页面')
            .fontSize(18)
            .fontColor('#E5E5E5')
            .fontWeight(FontWeight.Medium)

          Text(`${this.progressValue}%`)
            .fontSize(14)
            .fontColor('#00FF41')
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor('#000000E6')
      }

      if (this.hasLoadError) {
        Column({ space: 14 }) {
          Text('页面加载失败')
            .fontSize(18)
            .fontColor('#ED7F64')
            .fontWeight(FontWeight.Medium)

          Button('重试')
            .fontSize(14)
            .height(40)
            .padding({ left: 18, right: 18 })
            .backgroundColor('#1F1F1F')
            .fontColor('#00FF41')
            .onClick(() => {
              this.hasLoadError = false
              this.isLoading = true
              this.progressValue = 0
              this.pageUrl = `${STITCH_IMPORT_TASK_URL}#retry-${Date.now()}`
            })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width('100%')
        .height('100%')
        .backgroundColor('#000000E6')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
