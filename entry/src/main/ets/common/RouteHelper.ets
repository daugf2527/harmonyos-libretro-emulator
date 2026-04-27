export type EmuNavKey = 'library' | 'engine' | 'input' | 'system'

interface EmuRouteTarget {
  url: string
}

export interface EmuRouterHandle {
  pushUrl(target: EmuRouteTarget): Promise<void>
  replaceUrl(target: EmuRouteTarget): Promise<void>
}

export function getEmuBottomNavRoute(key: string): string {
  if (key === 'library') {
    return 'pages/LibraryPage'
  }
  if (key === 'engine') {
    return 'pages/LibretroGamePage'
  }
  if (key === 'input') {
    return 'pages/InputLayoutPage'
  }
  if (key === 'system') {
    return 'pages/SettingsPage'
  }
  return ''
}

export function navigateEmuBottomNav(
  router: EmuRouterHandle,
  key: string,
  currentKey: EmuNavKey,
  logTag: string
): void {
  if (key === currentKey) {
    return
  }
  const route = getEmuBottomNavRoute(key)
  if (route.length === 0) {
    return
  }
  if (key === 'library') {
    router.replaceUrl({ url: route }).catch((err: Error) => {
      console.error(`[${logTag}] replaceUrl ${route} failed: ${err.message}`)
    })
    return
  }
  router.pushUrl({ url: route }).catch((err: Error) => {
    console.error(`[${logTag}] pushUrl ${route} failed: ${err.message}`)
  })
}
