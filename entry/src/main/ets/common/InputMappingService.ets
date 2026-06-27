import { common } from '@kit.AbilityKit'
import {
  InputMappingProfile,
  createDefaultInputMappingProfile,
  loadInputMappingProfile,
  saveInputMappingProfile
} from './InputMappingRepository'
import LogHelper from './LogHelper'

export interface InputMappingStatusSnapshot {
  summaryText: string
  detailText: string
  healthy: boolean
}

export interface InputMappingNativeApi {
  setInputKeyMapping(mappingMap: Record<string, number>): boolean | void
}

class InputMappingService {
  private currentProfile: InputMappingProfile = createDefaultInputMappingProfile()
  private context: common.UIAbilityContext | undefined = undefined
  private initialized: boolean = false
  private profileLoadFailed: boolean = false
  private nativeSyncReady: boolean = false
  private nativeApi: InputMappingNativeApi | undefined = undefined
  private lastLoadError: string = ''
  private lastNativeSyncError: string = ''

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context
    this.initialized = true
    this.profileLoadFailed = false
    this.lastLoadError = ''
    try {
      this.currentProfile = await loadInputMappingProfile(context)
      LogHelper.info('InputMappingService', 'Init', `已加载配置: ${this.currentProfile.mappings.length} 个映射`)
    } catch (err) {
      const message = (err as Error).message || String(err)
      this.currentProfile = createDefaultInputMappingProfile()
      this.profileLoadFailed = true
      this.lastLoadError = message
      LogHelper.warn('InputMappingService', 'Init', `本地键盘映射配置没有读出来，当前不会直接覆盖成默认映射: ${message}`)
    }
    this.nativeSyncReady = false
  }

  getCurrentProfile(): InputMappingProfile {
    if (!this.initialized) {
      throw new Error('InputMappingService not initialized')
    }
    if (this.profileLoadFailed) {
      throw new Error('input_mapping_profile_unavailable')
    }
    return this.currentProfile
  }

  getStatusSnapshot(): InputMappingStatusSnapshot {
    if (!this.initialized) {
      return {
        summaryText: '键盘映射待读取',
        detailText: '应用启动后会读取本地键盘映射配置',
        healthy: false
      }
    }
    if (this.profileLoadFailed) {
      const syncText = this.nativeSyncReady ?
        '当前不会直接改写成默认映射。' :
        (this.nativeApi ? '当前不会直接改写成默认映射，运行内同步也还没成功。' : '进入游戏后会继续尝试读取并同步这份映射配置。')
      return {
        summaryText: '键盘映射待重试',
        detailText: `本地键盘映射配置没有读出来，请稍后重试。当前不会直接拿兜底默认映射覆盖你原来的本地配置。${syncText}`,
        healthy: false
      }
    }
    if (!this.nativeApi) {
      return {
        summaryText: '键盘映射待应用',
        detailText: `本地键盘映射已读到，进入游戏后会自动同步 ${this.currentProfile.mappings.length} 组映射。`,
        healthy: false
      }
    }
    if (!this.nativeSyncReady) {
      return {
        summaryText: '键盘映射待同步',
        detailText: '本地键盘映射配置已经读到，但当前运行里还没同步成功；进入游戏后会继续尝试同步这份配置。',
        healthy: false
      }
    }
    return {
      summaryText: '键盘映射已同步',
      detailText: `本地键盘映射已同步到当前运行，当前共 ${this.currentProfile.mappings.length} 组映射。`,
      healthy: true
    }
  }

  async attachNativeApi(nativeApi: InputMappingNativeApi): Promise<void> {
    this.nativeApi = nativeApi
    this.nativeSyncReady = await this.applyToNative()
  }

  async updateProfile(profile: InputMappingProfile): Promise<void> {
    if (!this.context || !this.initialized) {
      throw new Error('InputMappingService not initialized')
    }
    if (this.profileLoadFailed) {
      throw new Error('input_mapping_profile_unavailable')
    }
    this.profileLoadFailed = false
    this.lastLoadError = ''
    this.currentProfile = profile
    await saveInputMappingProfile(this.context, profile)
    this.nativeSyncReady = this.nativeApi ? await this.applyToNative() : false
    LogHelper.info('InputMappingService', 'Update', `配置已更新，nativeSyncReady=${this.nativeSyncReady}`)
  }

  async resetToDefault(): Promise<void> {
    const defaultProfile = createDefaultInputMappingProfile()
    await this.updateProfile(defaultProfile)
  }

  private async applyToNative(): Promise<boolean> {
    if (!this.nativeApi) {
      return false
    }
    try {
      const mappingMap: Record<string, number> = {}
      this.currentProfile.mappings.forEach((mapping) => {
        mappingMap[mapping.keyCode] = mapping.joypadId
      })
      const applyResult = this.nativeApi.setInputKeyMapping(mappingMap)
      if (applyResult === false) {
        this.lastNativeSyncError = 'native_apply_rejected'
        LogHelper.warn('InputMappingService', 'Apply', 'C++ 侧拒绝应用当前键盘映射')
        return false
      }
      this.lastNativeSyncError = ''
      LogHelper.info('InputMappingService', 'Apply', `已同步 ${this.currentProfile.mappings.length} 个映射到 C++`)
      return true
    } catch (err) {
      const message = (err as Error).message || String(err)
      this.lastNativeSyncError = message
      LogHelper.error('InputMappingService', 'Apply', `同步到 C++ 失败: ${message}`)
      return false
    }
  }
}

let serviceInstance: InputMappingService | undefined = undefined

export function getInputMappingService(): InputMappingService {
  if (!serviceInstance) {
    serviceInstance = new InputMappingService()
  }
  return serviceInstance
}
