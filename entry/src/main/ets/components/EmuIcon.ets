@Component
export struct EmuIcon {
  @Prop name: string = ''
  @Prop tone: string = 'primary'
  @Prop iconSize: number = 24
  @Prop opacityValue: number = 1

  private isTone(value: string): boolean {
    return this.tone === value
  }

  private resolveIconResource(): Resource {
    const multiToneIcons: Record<string, [Resource, Resource, Resource, Resource]> = {
      'memory': [$r('app.media.icon_memory_primary'), $r('app.media.icon_memory_on_surface'), $r('app.media.icon_memory_outline'), $r('app.media.icon_memory_muted')],
      'terminal': [$r('app.media.icon_terminal_primary'), $r('app.media.icon_terminal_on_surface'), $r('app.media.icon_terminal_outline'), $r('app.media.icon_terminal_muted')],
      'settings_input_component': [$r('app.media.icon_settings_input_component_primary'), $r('app.media.icon_settings_input_component_on_surface'), $r('app.media.icon_settings_input_component_outline'), $r('app.media.icon_settings_input_component_muted')],
      'sports_esports': [$r('app.media.icon_sports_esports_primary'), $r('app.media.icon_sports_esports_on_surface'), $r('app.media.icon_sports_esports_outline'), $r('app.media.icon_sports_esports_muted')],
      'folder_open': [$r('app.media.icon_folder_open_primary'), $r('app.media.icon_folder_open_on_surface'), $r('app.media.icon_folder_open_outline'), $r('app.media.icon_folder_open_muted')],
      'chevron_right': [$r('app.media.icon_chevron_right_primary'), $r('app.media.icon_chevron_right_on_surface'), $r('app.media.icon_chevron_right_outline'), $r('app.media.icon_chevron_right_muted')],
      'check_circle': [$r('app.media.icon_check_circle_primary'), $r('app.media.icon_check_circle_on_surface'), $r('app.media.icon_check_circle_outline'), $r('app.media.icon_check_circle_muted')],
      'search': [$r('app.media.icon_search_primary'), $r('app.media.icon_search_on_surface'), $r('app.media.icon_search_outline'), $r('app.media.icon_search_muted')],
      'grid_view': [$r('app.media.icon_grid_view_primary'), $r('app.media.icon_grid_view_on_surface'), $r('app.media.icon_grid_view_outline'), $r('app.media.icon_grid_view_muted')],
      'explore': [$r('app.media.icon_explore_primary'), $r('app.media.icon_explore_on_surface'), $r('app.media.icon_explore_outline'), $r('app.media.icon_explore_muted')],
      'tune': [$r('app.media.icon_tune_primary'), $r('app.media.icon_tune_on_surface'), $r('app.media.icon_tune_outline'), $r('app.media.icon_tune_muted')],
      'add_circle': [$r('app.media.icon_add_circle_primary'), $r('app.media.icon_add_circle_on_surface'), $r('app.media.icon_add_circle_outline'), $r('app.media.icon_add_circle_muted')],
      'eject': [$r('app.media.icon_eject_primary'), $r('app.media.icon_eject_on_surface'), $r('app.media.icon_eject_outline'), $r('app.media.icon_eject_muted')],
    }

    const singleToneIcons: Record<string, Resource> = {
      'warning': $r('app.media.icon_warning_error'),
      'equalizer': $r('app.media.icon_equalizer_primary'),
      'play_arrow': $r('app.media.icon_play_arrow_on_surface'),
      'info': $r('app.media.icon_info_on_surface'),
      'image_edit_auto': $r('app.media.icon_image_edit_auto_on_surface'),
      'delete_forever': $r('app.media.icon_delete_forever_error'),
      'cloud_done': $r('app.media.icon_cloud_done_black'),
      'videogame_asset': $r('app.media.icon_videogame_asset_on_surface'),
      'palette': $r('app.media.icon_palette_on_surface'),
      'image': $r('app.media.icon_image_on_surface'),
      'edit': $r('app.media.icon_edit_on_surface'),
    }

    const multiTone = multiToneIcons[this.name]
    if (multiTone !== undefined) {
      return this.isTone('on_surface') ? multiTone[1]
        : this.isTone('outline') ? multiTone[2]
        : this.isTone('muted') ? multiTone[3]
        : multiTone[0]
    }

    const singleTone = singleToneIcons[this.name]
    if (singleTone !== undefined) {
      return singleTone
    }

    return $r('app.media.icon_videogame_asset_on_surface')
  }

  build() {
    Image(this.resolveIconResource())
      .width(this.iconSize)
      .height(this.iconSize)
      .opacity(this.opacityValue)
  }
}
