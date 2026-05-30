export type EmuNavKey = 'library' | 'input' | 'system'

export function getEmuBottomNavRoute(key: string): string {
  if (key === 'library') {
    return 'pages/LibraryPage'
  }
  if (key === 'input') {
    return 'pages/MultiplayerInputPage'
  }
  if (key === 'system') {
    return 'pages/SettingsPage'
  }
  return ''
}

export function getEmuBottomNavTargetRoute(
  key: string,
  currentKey: EmuNavKey
): string {
  if (key === currentKey) {
    return ''
  }
  return getEmuBottomNavRoute(key)
}
