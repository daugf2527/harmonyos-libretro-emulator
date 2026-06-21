/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef AUDIO_BRIDGE_H
#define AUDIO_BRIDGE_H

#include "audio_player.h"
#include "audio_resampler.h"
#include "interfaces/audio/i_audio_sink.h" // 1. 引入接口
#include "ring_buffer.h"
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace libretro {

/**
 * @brief 音频桥接层 implementation
 */
class AudioBridge : public interfaces::IAudioSink { // 2. 继承接口
public:
  enum class AudioRunState : uint8_t {
    INIT = 0,
    BUFFERING = 1,
    RUNNING = 2,
    PAUSED = 3,
    RECOVERING = 4,
  };

  static AudioBridge *GetInstance();
  static void DestroyInstance();

  // IAudioSink 接口实现
  bool Initialize(double sample_rate) override;
  bool Start() override;
  bool Stop() override;
  size_t ProcessAudio(const int16_t *data, size_t frames) override;
  bool IsRunning() const override;
  bool SetMinimumAudioLatency(int latency_ms) override;
  bool SetAudioSyncMode(int mode) override;
  bool SetVolumePercent(int percent);
  int GetVolumePercent() const { return volume_percent_.load(); }

  // 保留旧的 Initialize (为了兼容现有代码)
  bool Initialize(int32_t sample_rate = 48000);

  // 重置音频桥接器 (支持更改采样率)
  bool Reset(int32_t sample_rate);

  // Libretro 回调 (静态)
  static void AudioSampleCallback(int16_t left, int16_t right);
  static size_t AudioSampleBatchCallback(const int16_t *data, size_t frames);

  bool Pause();
  bool IsPlaying() const;
  AudioRunState GetRunState() const {
    return static_cast<AudioRunState>(run_state_.load(std::memory_order_acquire));
  }
  static const char *AudioRunStateToString(AudioRunState state);

  float GetBufferUsage() const;
  size_t GetBufferedFrames() const;
  size_t GetMinBufferFrames() const { return min_buffer_frames_.load(); }
  void GetBufferStats(size_t &underruns, size_t &overruns) const;
  void GetCallbackDiag(uint64_t &callbackCount, uint64_t &framesRead,
                       int64_t &lastCallbackMs) const;
  void ResetBufferStats();

  void SetMinimumLatencyMs(unsigned latency_ms);

  enum class SyncMode {
    NON_BLOCKING,  // Fast Forward behavior: drop data on overflow
    AUDIO_BLOCKING // Normal behavior: block until space available
  };

  void SetSyncMode(SyncMode mode) { sync_mode_.store(mode); }
  SyncMode GetSyncMode() const { return sync_mode_.load(); }

  // 平台实时调度能力(由引擎 GameLoop 入口 OH_QoS_SetThreadQoS 成败注入):
  // true=真机(有 RT,回调规整)→ 浅缓冲低延迟;false=模拟器(无 RT,回调抖)→ 深缓冲抗抖动。
  // 须在 AudioBridge::Initialize 之前调用方生效(引擎设 QoS 后即调,早于游戏加载)。
  void SetRtSchedulingAvailable(bool available);

private:
  // --- 平台双 profile:缓冲深度 + DRC 带 ---
  // 按 RT 调度能力(SetRtSchedulingAvailable,源自引擎 OH_QoS_SetThreadQoS 成败)二选一,
  // 在 Initialize 落地。详见 memory project-audio-underrun-api22-emulator-not-code。
  //  - 真机(有 RT):回调规整 ~20ms,浅缓冲 + DRC 维持 ~116ms,低延迟。
  //  - 模拟器(无 RT,workgroup/QoS 被系统拒):回调抖 ~150ms,需深缓冲扛,DRC 带抬高
  //    (留足深缓冲不被 DRC 抽干);延迟高些但不卡,开发环境可接受。
  // DRC 带语义: 水位 < low 加速生产补水、> high 减速,把水位维持在带内。
  static constexpr int kMinBufferMsDevice = 100;
  static constexpr int kMinBufferMsEmulator = 250;
  static constexpr int kAdaptiveBoostMsStep = 50;
  static constexpr int kAdaptiveBoostMsMax = 150;
  static constexpr float kDrcLowThresholdDevice = 0.06f;    // ~82ms
  static constexpr float kDrcHighThresholdDevice = 0.11f;   // ~150ms
  static constexpr float kDrcLowThresholdEmulator = 0.12f;  // ~164ms
  static constexpr float kDrcHighThresholdEmulator = 0.28f; // ~382ms
  static constexpr double kDrcStep = 0.001;
  static constexpr double kDrcMaxSkew = 1.015;
  static constexpr double kDrcMinSkew = 0.995;
  static constexpr int kDrcUpdateIntervalMs = 50;
  // 运行时生效的 DRC 带(Initialize 按 profile 赋值;默认真机档)。同线程(引擎)读写,无需原子。
  float drc_low_threshold_ = kDrcLowThresholdDevice;
  float drc_high_threshold_ = kDrcHighThresholdDevice;

  AudioBridge();
  ~AudioBridge() override;

  std::shared_ptr<RingBuffer> ring_buffer_;
  std::unique_ptr<AudioPlayer> audio_player_;
  // 输出采样率（固定 48k），与 OHAudio 配置一致
  int32_t sample_rate_ = 48000; // 保持命名以兼容现有日志/计算
  int32_t output_sample_rate_ = 48000;
  // 核心（Libretro）实际采样率，用于重采样输入
  int32_t core_sample_rate_ = 48000;
  // 轻量重采样器与 DRC 状态
  AudioResampler resampler_;
  std::atomic<double> drc_skew_{1.0};
  // 全局运行状态：用于阻塞读写的退出条件
  std::atomic<bool> running_{false};

  // Buffering logic
  bool buffering_ = false;

  std::atomic<SyncMode> sync_mode_{SyncMode::AUDIO_BLOCKING};
  // 平台 RT 调度能力。默认 false=保守走模拟器深缓冲档;引擎 GameLoop 入口早期注入纠正。
  std::atomic<bool> rt_scheduling_available_{false};
  bool is_started_ = false; // Intended state
  std::atomic<size_t> min_buffer_frames_{0};
  std::atomic<size_t> default_min_buffer_frames_{0};
  std::atomic<unsigned> minimum_latency_ms_{0};
  std::atomic<unsigned> adaptive_buffer_boost_ms_{0};
  std::atomic<int> volume_percent_{100};

  // DRC 更新节流（从 static 移为成员变量，避免多线程数据竞争）
  std::chrono::steady_clock::time_point drc_last_update_{};
  std::chrono::steady_clock::time_point process_audio_last_time_{};

  // 日志节流计数器（从 static 移为成员变量）
  int process_audio_log_count_{0};
  int process_audio_drop_log_count_{0};
  int process_audio_diag_log_count_{0};
  int process_audio_gap_log_count_{0};
  int process_audio_slow_log_count_{0};
  std::chrono::steady_clock::time_point diag_window_start_{};
  uint64_t diag_calls_{0};
  uint64_t diag_in_frames_{0};
  uint64_t diag_out_frames_{0};
  uint64_t diag_write_failures_{0};
  uint64_t diag_blocking_calls_{0};
  int32_t diag_max_dt_ms_{0};
  std::atomic<size_t> last_rebuffer_underruns_{0};

  std::vector<int16_t> resample_out_buf_;

  mutable std::mutex mutex_;
  std::atomic<bool> initialized_{false};
  std::atomic<int> run_state_{static_cast<int>(AudioRunState::INIT)};
  uint32_t run_state_log_count_{0};
  uint32_t recover_streak_{0};

  void SetRunState(AudioRunState state, const char *reason = nullptr);
  void ApplyAudioProfileLocked();
  void IncreaseAdaptiveBufferBoostLocked();
  void ResetAdaptiveBufferBoostLocked();

  AudioBridge(const AudioBridge &) = delete;
  AudioBridge &operator=(const AudioBridge &) = delete;
};

} // namespace libretro

#endif // AUDIO_BRIDGE_H
