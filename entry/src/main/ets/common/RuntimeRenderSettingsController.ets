import testNapi from 'libentry.so'

interface RuntimeRenderSettingsNapi {
  refactoredResetStats(): boolean
  refactoredSetScalingMode(mode: number): boolean
  refactoredSetSoftwareMaxResolution(width: number, height: number): boolean
  refactoredSetHwRenderAllowed(allowed: boolean): boolean
}

const nativeApi = testNapi as RuntimeRenderSettingsNapi

export class RuntimeRenderSettingsController {
  resetStats(): boolean {
    return nativeApi.refactoredResetStats()
  }

  setScalingMode(mode: number): boolean {
    return nativeApi.refactoredSetScalingMode(mode)
  }

  setSoftwareMaxResolution(width: number, height: number): boolean {
    return nativeApi.refactoredSetSoftwareMaxResolution(width, height)
  }

  setHwRenderAllowed(allowed: boolean): boolean {
    return nativeApi.refactoredSetHwRenderAllowed(allowed)
  }
}

export const runtimeRenderSettingsController: RuntimeRenderSettingsController =
  new RuntimeRenderSettingsController()
