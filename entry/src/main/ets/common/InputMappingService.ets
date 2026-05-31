import { common } from '@kit.AbilityKit'
import {
  InputMappingProfile,
  createDefaultInputMappingProfile,
  loadInputMappingProfile,
  saveInputMappingProfile
} from './InputMappingRepository'
import LogHelper from './LogHelper'
import libentry from 'libentry.so'

class InputMappingService {
  private currentProfile: InputMappingProfile = createDefaultInputMappingProfile()
  private context: common.UIAbilityContext | undefined = undefined

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context
    this.currentProfile = await loadInputMappingProfile(context)
    LogHelper.info('InputMappingService', 'Init', `已加载配置: ${this.currentProfile.mappings.length} 个映射`)
    await this.applyToNative()
  }

  getCurrentProfile(): InputMappingProfile {
    return this.currentProfile
  }

  async updateProfile(profile: InputMappingProfile): Promise<void> {
    if (!this.context) {
      throw new Error('InputMappingService not initialized')
    }
    this.currentProfile = profile
    await saveInputMappingProfile(this.context, profile)
    await this.applyToNative()
    LogHelper.info('InputMappingService', 'Update', `配置已更新并同步到 C++`)
  }

  async resetToDefault(): Promise<void> {
    const defaultProfile = createDefaultInputMappingProfile()
    await this.updateProfile(defaultProfile)
  }

  private async applyToNative(): Promise<void> {
    try {
      const mappingMap: Record<string, number> = {}
      this.currentProfile.mappings.forEach((mapping) => {
        mappingMap[mapping.keyCode] = mapping.joypadId
      })
      libentry.setInputKeyMapping(mappingMap)
      LogHelper.info('InputMappingService', 'Apply', `已同步 ${this.currentProfile.mappings.length} 个映射到 C++`)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.error('InputMappingService', 'Apply', `同步到 C++ 失败: ${message}`)
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
