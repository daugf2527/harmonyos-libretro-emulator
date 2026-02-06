/*
 * 音频接收器接口 - 符合Libretro规范
 *
 * 设计原则:
 * - 职责单一: 只负责接收和处理音频数据
 * - 可替换: 可用MockAudioSink测试，或实现不同音频后端
 */

#ifndef INTERFACES_I_AUDIO_SINK_H
#define INTERFACES_I_AUDIO_SINK_H

#include <cstddef>
#include <cstdint>

namespace interfaces {

/**
 * @brief 音频接收器接口
 *
 * 对应规范:
 * - Libretro: retro_audio_sample_batch_t
 * - HarmonyOS: OHAudio API
 */
class IAudioSink {
public:
  virtual ~IAudioSink() = default;

  /**
   * @brief 初始化音频系统
   * @param sample_rate 采样率 (通常为48000Hz)
   * @return true 成功，false 失败
   */
  virtual bool Initialize(double sample_rate) = 0;

  /**
   * @brief 启动音频播放
   */
  /**
   * @brief 启动音频播放
   * @return true 成功，false 失败
   */
  virtual bool Start() = 0;

  /**
   * @brief 停止音频播放
   * @return true 成功，false 失败
   */
  virtual bool Stop() = 0;

  /**
   * @brief 处理音频批量采样
   * @param data 音频数据（int16_t立体声交错格式）
   * @param frames 帧数（每帧包含左右声道）
   * @return 实际处理的帧数
   */
  virtual size_t ProcessAudio(const int16_t *data, size_t frames) = 0;

  /**
   * @brief 检查音频系统是否正在运行
   */
  virtual bool IsRunning() const = 0;

  // --- 音频配置接口 (对应 ArkTS refactoredSet... 接口) ---

  /**
   * @brief 设置最小音频延迟
   * @param latency_ms 延迟毫秒数
   */
  virtual bool SetMinimumAudioLatency(int latency_ms) = 0;

  /**
   * @brief 设置音频同步模式
   * @param mode 0=NonBlocking, 1=Blocking
   */
  virtual bool SetAudioSyncMode(int mode) = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_AUDIO_SINK_H
