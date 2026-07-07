@ComponentV2
export struct EmuCoverArt {
  @Param coverKey: string = ''
  @Param variant: string = 'recent'
  @Param coverUrl: string = ''

  private isCoolCover(): boolean {
    return this.coverKey === 'aurora_grid'
  }

  private isWarmCover(): boolean {
    return this.coverKey === 'ember_glow'
  }

  private getScaleValue(): number {
    if (this.variant === 'list') {
      return this.isCoolCover() ? 1.2 : (this.isWarmCover() ? 1.12 : 1.16)
    }
    return this.isCoolCover() ? 1.02 : (this.isWarmCover() ? 1.08 : 1.04)
  }

  private getOffsetX(): number {
    if (this.variant === 'list') {
      return this.isCoolCover() ? -8 : (this.isWarmCover() ? 6 : 2)
    }
    return this.isWarmCover() ? 3 : 0
  }

  private getOffsetY(): number {
    if (this.variant === 'list') {
      return this.isCoolCover() ? -4 : (this.isWarmCover() ? -10 : -6)
    }
    return this.isWarmCover() ? -3 : -1
  }

  private getPlaceholderStartColor(): string {
    if (this.coverKey === 'moss_signal') {
      return '#244732'
    }
    if (this.isCoolCover()) {
      return '#223E5A'
    }
    if (this.isWarmCover()) {
      return '#5A3B2A'
    }
    return '#3E3E3E'
  }

  private getPlaceholderEndColor(): string {
    if (this.coverKey === 'moss_signal') {
      return '#7BC87A'
    }
    if (this.isCoolCover()) {
      return '#62C3D7'
    }
    if (this.isWarmCover()) {
      return '#D89A57'
    }
    return '#7A7A7A'
  }

  build() {
    Stack() {
      if (this.coverUrl && this.coverUrl.length > 0) {
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.coverKey === 'metroid_fusion' || this.coverKey === 'aria_of_sorrow') {
        Image($r('app.media.cover_metroid_fusion'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.coverKey === 'zelda_triforce') {
        Image($r('app.media.cover_zelda_triforce'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.coverKey === 'chrono_trigger') {
        Image($r('app.media.cover_chrono_trigger'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Row()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [[this.getPlaceholderStartColor(), 0], [this.getPlaceholderEndColor(), 1]]
            })

          Row()
            .width(this.variant === 'list' ? 68 : 84)
            .height(this.variant === 'list' ? 68 : 84)
            .borderRadius(this.variant === 'list' ? 34 : 42)
            .backgroundColor('#22FFFFFF')
            .scale({ x: this.getScaleValue(), y: this.getScaleValue() })
            .translate({ x: this.getOffsetX(), y: this.getOffsetY() })

          Text((this.coverKey || 'rom').substring(0, 3).toUpperCase())
            .fontSize(this.variant === 'list' ? 14 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F5F5F5')
            .letterSpacing(1.2)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
