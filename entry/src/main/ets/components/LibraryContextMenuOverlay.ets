import { EmuColors } from '../common/EmuUiTokens'
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
        .backgroundColor('#B8000000')
        .backdropBlur(14)
        .onClick(() => {
          this.onClose?.()
        })

      Column({ space: 18 }) {
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
          this.onClose?.()
        })
      }
      .width('86%')
      .constraintSize({ maxWidth: 320 })
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
        .fontSize(14)
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(danger ? EmuColors.error : EmuColors.onSurface)
        .fontFamily('monospace')
        .letterSpacing(danger ? 0.8 : 1)

      EmuIcon({
        name: iconName,
        tone: iconTone,
        iconSize: 20
      })
    }
    .width('100%')
    .height(54)
    .padding({ left: 18, right: 18 })
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
