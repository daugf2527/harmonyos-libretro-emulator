import testNapi from 'libentry.so'

interface RuntimeAudioSettingsNapi {
  refactoredSetMinimumAudioLatency(ms: number): boolean
  refactoredSetAudioSyncMode(mode: number): boolean
}

const nativeApi = testNapi as RuntimeAudioSettingsNapi

export class RuntimeAudioSettingsController {
  // 设置音频最小延迟（ms）：决定 RingBuffer 缓冲目标水位深度。
  // 越大越抗 callback 抖动（模拟器/低端机），代价是按键到出声延迟。见 D019。
  setMinimumAudioLatency(ms: number): boolean {
    return nativeApi.refactoredSetMinimumAudioLatency(ms)
  }

  // 音频同步模式 0=NonBlocking / 1=Blocking。当前生产路径保留默认 Blocking，
  // 此入口预留给未来需要切非阻塞抗抖动时使用。
  setAudioSyncMode(mode: number): boolean {
    return nativeApi.refactoredSetAudioSyncMode(mode)
  }
}

export const runtimeAudioSettingsController: RuntimeAudioSettingsController =
  new RuntimeAudioSettingsController()
