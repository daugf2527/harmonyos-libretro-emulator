import { EmuColors, EmuTypography } from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

@Component
export struct LibraryContextMenuOverlay {
  onClose?: () => void
  onLaunch?: () => void
  onDetails?: () => void
  onCoverChange?: () => void
  onDeleteSaves?: () => void

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#D9000000')
        .backdropBlur(26)
        .onClick(() => {
          this.onClose?.()
        })

      Column({ space: 26 }) {
        Column({ space: 0 }) {
          this.ActionMenuItem('启动游戏', 'play_arrow', 'primary', true, () => {
            this.onLaunch?.()
          })

          this.ActionMenuDivider()

          this.ActionMenuItem('查看详情', 'info', 'on_surface', false, () => {
            this.onDetails?.()
          })

          this.ActionMenuDivider()

          this.ActionMenuItem('修改封面', 'image_edit_auto', 'on_surface', false, () => {
            this.onCoverChange?.()
          })

          this.ActionMenuDivider()

          this.ActionMenuItem('删除存档', 'delete_forever', 'outline', true, () => {
            this.onDeleteSaves?.()
          }, true)
        }
        .width('100%')
        .backgroundColor('#F0141414')
        .backdropBlur(24)
        .borderRadius(12)
        .border({ width: 0.8, color: '#33FFFFFF', style: BorderStyle.Solid })
        .shadow({ radius: 34, color: '#AA000000', offsetX: 0, offsetY: 12 })

        Row() {
          Text('取消 CANCEL')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#CCABABAB')
            .fontFamily('monospace')
            .letterSpacing(1.2)
        }
        .width('100%')
        .height(76)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC1A1A1A')
        .borderRadius(12)
        .border({ width: 0.5, color: '#33FFFFFF', style: BorderStyle.Solid })
        .onClick(() => {
          this.onClose?.()
        })
      }
      .width('78%')
      .constraintSize({ minWidth: 300, maxWidth: 430 })
      .align(Alignment.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ActionMenuItem(
    label: string,
    iconName: string,
    iconTone: string,
    bold: boolean,
    action: () => void,
    danger: boolean = false
  ) {
    Row() {
      Text(label)
        .fontSize(EmuTypography.xl)
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(danger ? EmuColors.error : EmuColors.onSurface)
        .fontFamily('monospace')
        .letterSpacing(danger ? 0.8 : 1)

      EmuIcon({
        name: iconName,
        tone: iconTone,
        iconSize: danger ? 22 : 24
      })
    }
    .width('100%')
    .height(76)
    .padding({ left: 42, right: 42 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action()
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
}
