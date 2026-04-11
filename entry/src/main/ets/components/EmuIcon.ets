@Component
export struct EmuIcon {
  @Prop name: string = ''
  @Prop tone: string = 'primary'
  @Prop size: number = 24
  @Prop opacityValue: number = 1

  private isTone(value: string): boolean {
    return this.tone === value
  }

  build() {
    if (this.name === 'memory') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_memory_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_memory_outline')
        : this.isTone('muted') ? $r('app.media.icon_memory_muted')
        : $r('app.media.icon_memory_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'terminal') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_terminal_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_terminal_outline')
        : this.isTone('muted') ? $r('app.media.icon_terminal_muted')
        : $r('app.media.icon_terminal_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'settings_input_component') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_settings_input_component_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_settings_input_component_outline')
        : this.isTone('muted') ? $r('app.media.icon_settings_input_component_muted')
        : $r('app.media.icon_settings_input_component_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'sports_esports') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_sports_esports_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_sports_esports_outline')
        : this.isTone('muted') ? $r('app.media.icon_sports_esports_muted')
        : $r('app.media.icon_sports_esports_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'folder_open') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_folder_open_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_folder_open_outline')
        : this.isTone('muted') ? $r('app.media.icon_folder_open_muted')
        : $r('app.media.icon_folder_open_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'chevron_right') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_chevron_right_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_chevron_right_outline')
        : this.isTone('muted') ? $r('app.media.icon_chevron_right_muted')
        : $r('app.media.icon_chevron_right_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'check_circle') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_check_circle_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_check_circle_outline')
        : this.isTone('muted') ? $r('app.media.icon_check_circle_muted')
        : $r('app.media.icon_check_circle_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'warning') {
      Image($r('app.media.icon_warning_error'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'search') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_search_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_search_outline')
        : this.isTone('muted') ? $r('app.media.icon_search_muted')
        : $r('app.media.icon_search_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'grid_view') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_grid_view_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_grid_view_outline')
        : this.isTone('muted') ? $r('app.media.icon_grid_view_muted')
        : $r('app.media.icon_grid_view_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'explore') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_explore_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_explore_outline')
        : this.isTone('muted') ? $r('app.media.icon_explore_muted')
        : $r('app.media.icon_explore_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'tune') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_tune_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_tune_outline')
        : this.isTone('muted') ? $r('app.media.icon_tune_muted')
        : $r('app.media.icon_tune_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'add_circle') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_add_circle_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_add_circle_outline')
        : this.isTone('muted') ? $r('app.media.icon_add_circle_muted')
        : $r('app.media.icon_add_circle_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else if (this.name === 'eject') {
      Image(this.isTone('on_surface') ? $r('app.media.icon_eject_on_surface')
        : this.isTone('outline') ? $r('app.media.icon_eject_outline')
        : this.isTone('muted') ? $r('app.media.icon_eject_muted')
        : $r('app.media.icon_eject_primary'))
        .width(this.size)
        .height(this.size)
        .opacity(this.opacityValue)
    } else {
      Blank()
        .width(this.size)
        .height(this.size)
    }
  }
}
