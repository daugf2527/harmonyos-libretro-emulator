import { EmuColors } from '../common/EmuUiTokens'
import { EmuIcon } from './EmuIcon'

export type LibraryDetailActionKey =
  'launch' |
  'details' |
  'metadata' |
  'cover' |
  'save_manager' |
  'purge_save'

@Component
export struct LibraryDetailActionMenu {
  onClose?: () => void
  onAction?: (actionKey: LibraryDetailActionKey) => void

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
          this.MenuTextAction('启动游戏', 'play_arrow', false, 'launch')
          this.ActionMenuDivider()
          this.MenuTextAction('查看详情', 'info', false, 'details')
          this.MenuTextAction('编辑资料', 'info', false, 'metadata')
          this.MenuCoverAction()
          this.ActionMenuDivider()
          this.MenuTextAction('存档管理', 'folder_open', false, 'save_manager')
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
  private MenuTextAction(
    title: string,
    iconName: string,
    isDanger: boolean,
    actionKey: LibraryDetailActionKey
  ) {
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
      this.onAction?.(actionKey)
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
      this.onAction?.('cover')
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
