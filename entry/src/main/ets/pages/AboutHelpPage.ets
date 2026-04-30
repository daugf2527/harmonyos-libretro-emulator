import { EmuBottomNav, EmuBottomNavItem } from '../components/EmuBottomNav'
import { EmuHeaderBar } from '../components/EmuAppShell'
import { EmuIcon } from '../components/EmuIcon'
import { EmuColors } from '../common/EmuUiTokens'
import { getEmuBottomNavTargetRoute } from '../common/RouteHelper'

interface HelpItem {
  id: string
  title: string
  detail: string
  value: string
}

@Entry
@Component
struct AboutHelpPage {
  @State private selectedHelpId: string = 'import'
  private readonly navItems: EmuBottomNavItem[] = [
    { key: 'library', iconName: 'grid_view', label: '游戏库', isActive: false },
    { key: 'engine', iconName: 'terminal', label: '引擎', isActive: false },
    { key: 'input', iconName: 'sports_esports', label: '输入', isActive: false },
    { key: 'system', iconName: 'tune', label: '系统', isActive: true }
  ]
  private readonly helpItems: HelpItem[] = [
    { id: 'import', title: '怎么导入游戏？', detail: 'Procedure / Storage / Pathing', value: '使用导入入口选择本地 ROM，导入完成后进入库页同步。' },
    { id: 'input', title: '按键没反应怎么办？', detail: 'Input / Mapping / Calibration', value: '进入 INPUT 页面检查端口映射；布局编辑只保存本地 UI 配置。' },
    { id: 'legal', title: '合规声明', detail: 'Compliance / Licensing / EULA', value: '应用不提供商业 ROM；用户需自行确认 ROM 与 BIOS 使用权。' },
    { id: 'version', title: '当前版本', detail: 'System Architecture / Build Info', value: 'EMU_CORE_v1.0 / HarmonyOS ArkUI native shell。' }
  ]

  private onBottomNavClick(key: string): void {
    const route = getEmuBottomNavTargetRoute(key, 'system')
    if (route.length === 0) {
      return
    }
    if (key === 'library') {
      this.getUIContext().getRouter().replaceUrl({ url: route }).catch((err: Error) => {
        console.error(`[AboutHelpPage] replaceUrl ${route} failed: ${err.message}`)
      })
      return
    }
    this.getUIContext().getRouter().pushUrl({ url: route }).catch((err: Error) => {
      console.error(`[AboutHelpPage] pushUrl ${route} failed: ${err.message}`)
    })
  }

  @Builder
  private StatusHeader() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Row()
          .width(5)
          .height(5)
          .backgroundColor(EmuColors.primary)
        Text('Status: LOCAL_ABOUT_READY')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(2)
      }
      .alignItems(VerticalAlign.Center)

      Text('关于 & 帮助')
        .fontSize(34)
        .fontWeight(FontWeight.Medium)
        .fontColor(EmuColors.onSurface)
        .letterSpacing(0)

      Text('EMU_CORE 是基于 libretro 的本地模拟运行壳。页面只描述当前已接入的本地能力；未接入联网资料与远端服务时会显示 UNKNOWN 或 NOT CONFIGURED。')
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
          Text('Core Version')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(EmuColors.secondary)
            .letterSpacing(1.4)
          Row({ space: 8 }) {
            Text('v1.0.2')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(EmuColors.onSurface)
            Text('STABLE')
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(EmuColors.primary)
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)

        Column({ space: 4 }) {
          Text('Data Source')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(EmuColors.secondary)
            .letterSpacing(1.4)
          Text('LOCAL_ONLY')
            .fontSize(13)
            .fontFamily('monospace')
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
          .fontFamily('monospace')
          .fontColor(EmuColors.onSurfaceVariant)
          .letterSpacing(1)

        if (this.selectedHelpId === item.id) {
          Text(item.value)
            .fontSize(12)
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
        .fontSize(22)
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
      Text('DOCUMENTATION & LEGAL')
        .fontSize(10)
        .fontFamily('monospace')
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

        Text('DESIGNED FOR LOCAL\nLIBRETRO SHELL.\nHARMONYOS // ARKUI //\nLIBRETRO')
          .fontSize(13)
          .fontFamily('monospace')
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

  build() {
    Column() {
      EmuHeaderBar({
        titleText: 'EMU_CORE_v1.0',
        titleIcon: 'memory',
        rightLabel: 'SYSTEM',
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
    .width('100%')
    .height('100%')
    .backgroundColor(EmuColors.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
