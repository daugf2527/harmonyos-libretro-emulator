import { EmuColors, EmuMetrics } from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

export interface EmuBottomNavItem {
  key: string
  iconName: string
  label: string
  isActive: boolean
}

@Component
export struct EmuBottomNav {
  @Prop items: EmuBottomNavItem[] = []
  @Prop activeFontColor: string = '#FFFFFFFF'
  @Prop inactiveFontColor: string = '#FF666666'
  @Prop indicatorStyle: string = 'line'
  @Prop overallOpacity: number = 1
  @Prop panelBackgroundColor: string = '#F2000000'
  onItemClick?: (key: string) => void

  private isDotIndicator(): boolean {
    return this.indicatorStyle === 'dot'
  }

  build() {
    Row() {
      ForEach(this.items, (item: EmuBottomNavItem) => {
        Stack() {
          Column({ space: 3 }) {
            EmuIcon({
              name: item.iconName,
              tone: item.isActive ? 'primary' : 'muted',
              size: 24,
              opacityValue: item.isActive ? 1 : 0.42
            })

            Text(item.label)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(item.isActive ? this.activeFontColor : this.inactiveFontColor)
              .letterSpacing(1.2)
          }
          .height(EmuMetrics.bottomNavHeight)
          .padding({ top: 12, bottom: 18 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          if (item.isActive && this.isDotIndicator()) {
            Row()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(EmuColors.primary)
              .align(Alignment.Top)
              .margin({ top: 8 })
          }
        }
        .layoutWeight(1)
        .height(EmuMetrics.bottomNavHeight)
        .border({
          width: { top: item.isActive && !this.isDotIndicator() ? 2 : 0 },
          color: item.isActive ? EmuColors.primary : Color.Transparent,
          style: BorderStyle.Solid
        })
        .onClick(() => {
          this.onItemClick?.(item.key)
        })
      }, (item: EmuBottomNavItem) => item.key)
    }
    .width('100%')
    .height(EmuMetrics.bottomNavHeight)
    .padding({ left: 24, right: 24 })
    .backgroundColor(this.panelBackgroundColor)
    .backdropBlur(20)
    .border({
      width: { top: 0.5 },
      color: '#33262626',
      style: BorderStyle.Solid
    })
    .opacity(this.overallOpacity)
  }
}
