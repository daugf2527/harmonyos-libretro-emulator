@Component
export struct EmuCoverArt {
  @Prop coverKey: string = ''

  build() {
    if (this.coverKey === 'metroid_fusion' || this.coverKey === 'aria_of_sorrow') {
      Image($r('app.media.cover_metroid_fusion'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.coverKey === 'zelda_triforce' || this.coverKey === 'chrono_trigger') {
      Image($r('app.media.cover_zelda_triforce'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      Blank()
        .width('100%')
        .height('100%')
    }
  }
}
