@Component
export struct EmuCoverArt {
  @Prop coverKey: string = ''
  @Prop variant: string = 'recent'

  private isCyberCover(): boolean {
    return this.coverKey === 'metroid_fusion' || this.coverKey === 'aria_of_sorrow'
  }

  private isChronoCover(): boolean {
    return this.coverKey === 'chrono_trigger'
  }

  private getScaleValue(): number {
    if (this.isChronoCover()) {
      return this.variant === 'list' ? 1.08 : 1.02
    }
    if (this.variant === 'list') {
      return this.isCyberCover() ? 1.22 : 1.16
    }
    return this.isCyberCover() ? 1.02 : 1.06
  }

  private getOffsetX(): number {
    if (this.isChronoCover()) {
      return this.variant === 'list' ? 0 : 0
    }
    if (this.variant === 'list') {
      return this.isCyberCover() ? -10 : 4
    }
    return this.isCyberCover() ? 0 : 2
  }

  private getOffsetY(): number {
    if (this.isChronoCover()) {
      return this.variant === 'list' ? -2 : 0
    }
    if (this.variant === 'list') {
      return this.isCyberCover() ? -2 : -8
    }
    return this.isCyberCover() ? 0 : -2
  }

  build() {
    Stack() {
      if (this.coverKey === 'metroid_fusion' || this.coverKey === 'aria_of_sorrow') {
        Image($r('app.media.cover_metroid_fusion'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: this.getScaleValue(), y: this.getScaleValue() })
          .translate({ x: this.getOffsetX(), y: this.getOffsetY() })
      } else if (this.coverKey === 'chrono_trigger') {
        Image($r('app.media.cover_chrono_trigger'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: this.getScaleValue(), y: this.getScaleValue() })
          .translate({ x: this.getOffsetX(), y: this.getOffsetY() })
      } else if (this.coverKey === 'zelda_triforce') {
        Image($r('app.media.cover_zelda_triforce'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: this.getScaleValue(), y: this.getScaleValue() })
          .translate({ x: this.getOffsetX(), y: this.getOffsetY() })
      } else {
        Blank()
          .width('100%')
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
