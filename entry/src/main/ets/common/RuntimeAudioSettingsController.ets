import testNapi from 'libentry.so'
import LogHelper from './LogHelper'

interface RuntimeAudioSettingsNapi {
  refactoredSetMinimumAudioLatency(ms: number): boolean
  refactoredSetAudioSyncMode(mode: number): boolean
  refactoredSetAudioVolume(percent: number): boolean
}

const nativeApi = testNapi as RuntimeAudioSettingsNapi

export class RuntimeAudioSettingsController {
  // 设置音频最小延迟（ms）：决定 RingBuffer 缓冲目标水位深度。
  // 越大越抗 callback 抖动（模拟器/低端机），代价是按键到出声延迟。见 D019。
  setMinimumAudioLatency(ms: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeAudioSettings', 'Audio', '设置最小音频延迟跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetMinimumAudioLatency(ms)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeAudioSettings', 'Audio', `设置最小音频延迟失败: ${message}`)
      return false
    }
  }

  // 音频同步模式 0=NonBlocking / 1=Blocking。当前生产路径保留默认 Blocking，
  // 此入口预留给未来需要切非阻塞抗抖动时使用。
  setAudioSyncMode(mode: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeAudioSettings', 'Audio', '设置音频同步模式跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetAudioSyncMode(mode)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeAudioSettings', 'Audio', `设置音频同步模式失败: ${message}`)
      return false
    }
  }

  // 主音量百分比 0-100。通过 AudioRenderer_SetVolume 直接作用到当前输出流。
  setVolumePercent(percent: number): boolean {
    try {
      if (!testNapi) {
        LogHelper.warn('RuntimeAudioSettings', 'Audio', '设置主音量跳过: engine not ready')
        return false
      }
      return nativeApi.refactoredSetAudioVolume(percent)
    } catch (err) {
      const message = (err as Error).message || String(err)
      LogHelper.warn('RuntimeAudioSettings', 'Audio', `设置主音量失败: ${message}`)
      return false
    }
  }
}

export const runtimeAudioSettingsController: RuntimeAudioSettingsController =
  new RuntimeAudioSettingsController()
