import { EmuBottomNav, EmuBottomNavItem, createEmuBottomNavItems } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'
import LogHelper from '../common/LogHelper'

interface HelpItem {
  id: string
  title: string
  detail: string
  value: string
}

@Entry
@ComponentV2
struct AboutHelpPage {
  @Local private selectedHelpId: string = 'import'
  @Local private showToast: boolean = false
  @Local private toastMessage: string = ''
  private readonly navItems: EmuBottomNavItem[] = createEmuBottomNavItems('system')
  private toastTimer: number = -1
  private readonly helpItems: HelpItem[] = [
    { id: 'import', title: '怎么导入游戏？', detail: '本地文件选择 / 导入目录 / 库页刷新', value: '从导入入口选择你有合法使用权的本地 ROM 或镜像文件。文件写入完成后，回到库页会在刷新扫描后出现。' },
    { id: 'input', title: '按键没反应怎么办？', detail: '输入设备检查 / 端口分配 / 布局调整', value: '先到输入设备页查看当前能否列出本机输入设备，再检查端口分配和触控布局。当前页展示的是本机枚举结果与触控入口，不代表联网或实时输入诊断。' },
    { id: 'legal', title: '合规声明', detail: '内容来源 / 使用责任 / 本地导入', value: '应用不提供 ROM 下载，也不提供在线内容。请自行确认 ROM、BIOS 和核心文件的来源、授权与使用权。' },
    { id: 'version', title: '当前提供什么？', detail: '本地模拟体验 / 当前功能范围', value: '当前版本提供本地导入、游戏库、输入、存档和画面设置等能力，不包含在线服务。' }
  ]

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
      LogHelper.error('AboutHelpPage', 'Route', `replaceUrl ${route} failed: ${err.message}`)
      this.showToastMessage('这个页面现在还打不开，请稍后再试')
    })
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
    }, 2400)
  }

  @Builder
  private StatusHeader() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Row()
          .width(5)
          .height(5)
          .backgroundColor(EmuColors.primary)
        Text('帮助说明')
          .fontSize(EmuTypography.xs)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2)
      }
      .alignItems(VerticalAlign.Center)

      Text('关于 & 帮助')
        .fontSize(34)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .letterSpacing(0)

      Text('碳影是基于 libretro 的本地模拟应用。这里集中说明导入、输入、版权和当前版本提供的能力。')
        .fontSize(13)
        .fontColor(EmuColors.onSurfaceVariant)
        .lineHeight(20)
        .maxLines(4)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VersionPanel() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 4 }) {
          Text('当前提供')
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.secondary)
            .letterSpacing(1.4)
          Row({ space: 8 }) {
            Text('本地模拟体验')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)
            Text('当前版本')
              .fontSize(EmuTypography.xs)
                            .fontColor(EmuColors.primary)
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('内容范围')
            .fontSize(EmuTypography.xs)
                        .fontColor(EmuColors.secondary)
            .letterSpacing(1.4)
          Text('仅本地导入与本地游玩')
            .fontSize(13)
                        .fontColor(EmuColors.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row({ space: 2 }) {
        Row().layoutWeight(3).height(2).backgroundColor(EmuColors.primary)
        Row().layoutWeight(2).height(2).backgroundColor('#8800FF41')
        Row().layoutWeight(7).height(2).backgroundColor(EmuColors.outlineVariant)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(EmuColors.surfaceContainerLow)
    .border({ width: 0.5, color: '#33484848', style: BorderStyle.Solid })
  }

  @Builder
  private HelpRow(item: HelpItem) {
    Row() {
      Column({ space: 5 }) {
        Text(item.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedHelpId === item.id ? EmuColors.primary : EmuColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.detail)
          .fontSize(9)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1)

        if (this.selectedHelpId === item.id) {
          Text(item.value)
            .fontSize(EmuTypography.sm)
            .lineHeight(18)
            .fontColor(EmuColors.onSurfaceVariant)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(EmuTypography.xxl)
        .fontColor(EmuColors.outline)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.selectedHelpId === item.id ? '#1200FF41' : EmuColors.surfaceContainerLowest)
    .border({ width: { bottom: 0.5 }, color: '#26333333', style: BorderStyle.Solid })
    .onClick(() => {
      this.selectedHelpId = item.id
    })
  }

  @Builder
  private HelpList() {
    Column({ space: 0 }) {
      Text('使用说明')
        .fontSize(EmuTypography.xs)
                .fontColor(EmuColors.secondary)
        .letterSpacing(2)
        .padding({ left: 2, bottom: 12 })
        .width('100%')

      ForEach(this.helpItems, (item: HelpItem) => {
        this.HelpRow(item)
      }, (item: HelpItem) => item.id)
    }
    .width('100%')
  }

  @Builder
  private FooterBrand() {
    Row() {
      Column({ space: 14 }) {
        Row()
          .width(64)
          .height(2)
          .backgroundColor(EmuColors.primary)

        Text('面向本地模拟体验\n构建于 HarmonyOS ArkUI\n基于 libretro 运行')
          .fontSize(13)
                    .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1.6)
          .lineHeight(22)
      }
      .alignItems(HorizontalAlign.Start)

      Stack() {
        Row()
          .width(40)
          .height(40)
          .backgroundColor('#2200FF41')
        EmuIcon({
          name: 'memory',
          tone: 'muted',
          iconSize: 22
        })
      }
      .width(64)
      .height(64)
      .backgroundColor(EmuColors.surfaceContainerLow)
      .border({ width: 0.5, color: '#22484848', style: BorderStyle.Solid })
    }
    .width('100%')
    .padding({ top: 38, bottom: 18 })
    .border({ width: { top: 0.5 }, color: '#22333333', style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private Toast() {
    Row({ space: 8 }) {
      Row()
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(EmuColors.primary)

      Text(this.toastMessage)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(EmuColors.primary)
        .fontFamily('monospace')
        .letterSpacing(0.8)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#2200FF41')
    .border({ width: 0.5, color: '#6600FF41', style: BorderStyle.Solid })
    .borderRadius(999)
    .align(Alignment.Bottom)
    .margin({ bottom: 96 })
  }

  build() {
    Stack() {
      Column() {
        EmuHeaderBar({
          titleText: '碳影 / Carbon Shade',
          titleIcon: 'memory',
          rightLabel: '系统',
          rightIcon: 'settings_input_component',
          activeTextColor: EmuColors.primary,
          iconSize: 16,
          rightIconSize: 18
        })

        Scroll() {
          Column({ space: 28 }) {
            this.StatusHeader()
            this.VersionPanel()
            this.HelpList()
            this.FooterBrand()
          }
          .width('100%')
          .constraintSize({ maxWidth: 680 })
          .padding({ left: 24, right: 24, top: 34, bottom: 40 })
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

      if (this.showToast) {
        this.Toast()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
