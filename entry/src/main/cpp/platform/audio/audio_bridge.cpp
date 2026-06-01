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

#include "audio_bridge.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <hilog/log.h>
#include <vector>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD020
#undef LOG_TAG
#define LOG_TAG "AudioBridge"
#undef LOG_FLOW
#define LOG_FLOW "Audio"
#include "common/log_prefix.h"

namespace libretro {

namespace {
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";
constexpr const char *kAudioDiagPrefix = "[AUDIO_DIAG]";
constexpr int kAudioProducerMaxBlockMs = 8;
}

const char *AudioBridge::AudioRunStateToString(AudioRunState state) {
  switch (state) {
  case AudioRunState::INIT:
    return "init";
  case AudioRunState::BUFFERING:
    return "buffering";
  case AudioRunState::RUNNING:
    return "running";
  case AudioRunState::PAUSED:
    return "paused";
  case AudioRunState::RECOVERING:
    return "recovering";
  default:
    return "unknown";
  }
}

void AudioBridge::SetRunState(AudioRunState state, const char *reason) {
  const int next = static_cast<int>(state);
  const int prev = run_state_.exchange(next, std::memory_order_acq_rel);
  if (prev == next) {
    return;
  }
  run_state_log_count_++;
  if (run_state_log_count_ <= 5 || (run_state_log_count_ % 120) == 0) {
    LOGF(LOG_INFO,
         "%{public}s AudioRunState: %{public}s -> %{public}s (%{public}s)",
         kAudioChainPrefix, AudioRunStateToString(static_cast<AudioRunState>(prev)),
         AudioRunStateToString(state), reason ? reason : "no_reason");
  }
}

AudioBridge::AudioBridge() {
  run_state_.store(static_cast<int>(AudioRunState::INIT),
                   std::memory_order_release);
  LOGF(LOG_INFO, "%{public}s AudioBridge created", kAudioChainPrefix);
}

void AudioBridge::SetMinimumLatencyMs(unsigned latency_ms) {
  if (!initialized_ || sample_rate_ <= 0) {
    return;
  }

  minimum_latency_ms_.store(latency_ms);

  const size_t current_frames = min_buffer_frames_.load();

  size_t target_frames = 0;
  if (latency_ms == 0) {
    target_frames = default_min_buffer_frames_.load();
  } else {
    target_frames = (static_cast<size_t>(sample_rate_) * latency_ms) / 1000;
    const size_t default_frames = default_min_buffer_frames_.load();
    if (target_frames < default_frames) {
      target_frames = default_frames;
    }
  }

  if (latency_ms == 0) {
    min_buffer_frames_.store(target_frames);
  } else {
    if (target_frames > current_frames) {
      min_buffer_frames_.store(target_frames);
    }
  }

  LOGF(LOG_INFO,
       "%{public}s SetMinimumLatencyMs: req=%{public}u ms, "
       "min_frames=%{public}zu (rate=%{public}d)",
       kAudioChainPrefix, latency_ms, min_buffer_frames_.load(), sample_rate_);
}

AudioBridge::~AudioBridge() {
  // 停止播放
  if (audio_player_) {
    // 通知停止以唤醒所有阻塞等待
    running_.store(false);
    if (ring_buffer_) {
      ring_buffer_->Clear();
    }
    audio_player_->Stop();
  }
  SetRunState(AudioRunState::PAUSED, "destructor");

  LOGF(LOG_INFO, "%{public}s AudioBridge destroyed", kAudioChainPrefix);
}

AudioBridge *AudioBridge::GetInstance() {
  static AudioBridge instance;
  return &instance;
}

void AudioBridge::DestroyInstance() {
  // Meyers singleton: 生命周期由运行时管理；保留接口以兼容历史调用点。
}

// IAudioSink 接口实现
bool AudioBridge::Initialize(double sample_rate) {
  return Initialize(static_cast<int32_t>(sample_rate));
}

bool AudioBridge::SetMinimumAudioLatency(int latency_ms) {
  if (latency_ms < 0) return false;
  SetMinimumLatencyMs(static_cast<unsigned>(latency_ms));
  return true;
}

bool AudioBridge::SetAudioSyncMode(int mode) {
  // 0=NonBlocking, 1=Blocking
  if (mode == 0) {
    SetSyncMode(SyncMode::NON_BLOCKING);
    return true;
  } else if (mode == 1) {
    SetSyncMode(SyncMode::AUDIO_BLOCKING);
    return true;
  }
  return false;
}

bool AudioBridge::Start() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_.load()) {
    LOGF(LOG_ERROR, "%{public}s AudioBridge not initialized",
         kAudioChainPrefix);
    return false;
  }

  if (!audio_player_) {
    LOGF(LOG_ERROR, "%{public}s Audio player not created", kAudioChainPrefix);
    return false;
  }

  // 如果已经启动(逻辑上),仍需确保 running_ 为 true（修复暂停后恢复无声音问题）
  if (is_started_) {
    running_.store(true,
                   std::memory_order_release); // 确保 WriteWait 可以写入数据
    if (audio_player_ && audio_player_->IsPlaying()) {
      SetRunState(AudioRunState::RUNNING, "start_already_playing");
    } else {
      SetRunState(AudioRunState::BUFFERING, "start_already_started");
    }
    LOGF(LOG_INFO,
         "%{public}s AudioBridge already started, running_ reset to true",
         kAudioChainPrefix);
    return true;
  }

  is_started_ = true;
  running_.store(true, std::memory_order_release); // 确保首次启动时也设置

  // 清空缓冲区统计
  if (ring_buffer_) {
    ring_buffer_->ResetStats();
    last_rebuffer_underruns_.store(0, std::memory_order_relaxed);

    // 检查缓冲区当前水位 (Samples -> Frames)
    // RingBuffer::AvailableRead 返回的是 samples
    size_t available_samples = ring_buffer_->AvailableRead();
    size_t available_frames = available_samples / 2;

    const size_t min_frames = min_buffer_frames_.load();

    if (available_frames >= min_frames) {
      // 数据足够，直接启动
      LOGF(LOG_INFO,
           "%{public}s AudioBridge starting (buffer ready: %{public}zu frames)",
           kAudioChainPrefix, available_frames);
      if (audio_player_->Start()) {
        buffering_ = false;
        recover_streak_ = 0;
        SetRunState(AudioRunState::RUNNING, "start_buffer_ready");
        return true;
      }
    } else {
      // 数据不足，进入缓冲状态
      buffering_ = true;
      SetRunState(AudioRunState::BUFFERING, "start_buffering");
      LOGF(LOG_INFO,
           "%{public}s AudioBridge starting (buffering... need %{public}zu, has "
           "%{public}zu frames)",
           kAudioChainPrefix, min_frames, available_frames);
      return true; // Return true as "Started logically"
    }
  }

  SetRunState(AudioRunState::RECOVERING, "start_failed");
  return false;
}

bool AudioBridge::IsRunning() const { return is_started_; } // use logical state

size_t AudioBridge::ProcessAudio(const int16_t *data, size_t frames) {
  // 1. 快速检查 (Atomic Acquire)
  if (!initialized_.load(std::memory_order_acquire)) {
    if (++process_audio_drop_log_count_ <= 3 ||
        (process_audio_drop_log_count_ % 300) == 0) {
      LOGF(LOG_WARN,
           "%{public}s ProcessAudio drop: not initialized", kAudioChainPrefix);
    }
    return 0;
  }

  auto now = std::chrono::steady_clock::now();
  int32_t dt_ms = 0;
  if (process_audio_last_time_.time_since_epoch().count() != 0) {
    dt_ms = static_cast<int32_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            now - process_audio_last_time_)
            .count());
  }
  process_audio_last_time_ = now;

  // 2. 加锁保护 Resampler 和 buffer 指针
  // 必须使用 unique_lock 以便手动解锁
  std::unique_lock<std::mutex> lock(mutex_);

  if (!ring_buffer_) {
    if (++process_audio_drop_log_count_ <= 3 ||
        (process_audio_drop_log_count_ % 300) == 0) {
      LOGF(LOG_WARN, "%{public}s ProcessAudio drop: no ring buffer",
           kAudioChainPrefix);
    }
    return 0;
  }
  if (!data || frames == 0) {
    if (++process_audio_drop_log_count_ <= 3 ||
        (process_audio_drop_log_count_ % 300) == 0) {
      LOGF(LOG_WARN,
           "%{public}s ProcessAudio drop: invalid data/frames "
           "(data=%{public}p, frames=%{public}zu)",
           kAudioChainPrefix, data, frames);
    }
    return 0;
  }

  if (audio_player_) {
    audio_player_->ProcessPendingInterruptActions();
    if (audio_player_->IsPlaying()) {
      SetRunState(AudioRunState::RUNNING, "interrupt_processed_playing");
    }
  }

  // 1.5 Bypass 重采样 (如果采样率相同)
  // 注意:不能仅用 resampler_.GetRatio() == 1.0 判断,因为 DRC 在 1.0 附近微调时
  // ratio 与 1.0 浮点相等的概率不稳定,bypass 与否会跳变。
  // 改用整数比较 core/output 采样率 + DRC skew 严格等于 1.0(初始未触发) 双重判定。
  const bool bypass = (core_sample_rate_ == output_sample_rate_) &&
                      (drc_skew_.load() == 1.0);
  const double ratio_snapshot = resampler_.GetCurrentRatio();
  size_t out_frames = 0;

  if (bypass) {
    const size_t samples_bytes = frames * 2 * sizeof(int16_t);
    if (resample_out_buf_.size() < frames * 2) {
      resample_out_buf_.resize(frames * 2);
    }
    memcpy(resample_out_buf_.data(), data, samples_bytes);
    out_frames = frames;
  } else {
    // 重采样到输出采样率（固定 48k）
    // 注意：Resample 必须在锁内进行，因为它修改 resampler_ 状态，且 Reset() 可能会重置它
    const double ratio = resampler_.GetCurrentRatio();
    size_t max_out_frames = static_cast<size_t>(std::ceil(frames * ratio)) + 16; // Audit T3-F7: +16 margin (was +8)
    const size_t required_samples = max_out_frames * 2;
    if (resample_out_buf_.size() < required_samples) {
      resample_out_buf_.resize(required_samples);
    }
    out_frames = resampler_.Resample(data, frames, resample_out_buf_.data());
    if (out_frames == 0) {
      return 0;
    }
  }

  // 关键修复：使用 shared_ptr 延长生命周期，防止 Reset/Stop 在其他线程销毁它
  std::shared_ptr<RingBuffer> buffer_ref = ring_buffer_;
  const bool buffering_snapshot = buffering_;
  const bool started_snapshot = is_started_;
  const int32_t expected_ms =
      (core_sample_rate_ > 0)
          ? static_cast<int32_t>((frames * 1000) / core_sample_rate_)
          : 0;
  if (dt_ms >= 40) {
    int log_count = ++process_audio_gap_log_count_;
    if (log_count <= 3 || (log_count % 120) == 0) {
      LOGF(LOG_WARN,
           "%{public}s %{public}s producer gap: dt=%{public}d ms, "
           "frames=%{public}d (exp=%{public}d ms), buffering=%{public}d, "
           "started=%{public}d, sync=%{public}d",
           kAudioChainPrefix, kAudioDiagPrefix, dt_ms,
           static_cast<int32_t>(frames), expected_ms,
           buffering_snapshot ? 1 : 0, started_snapshot ? 1 : 0,
           static_cast<int>(sync_mode_.load()));
    }
  }
  float usage_before = buffer_ref ? buffer_ref->GetUsage() : 0.0f;

  // Audit T3-F3: capture buffer pointer and sample count before releasing lock
  const int16_t* const out_buf_data = resample_out_buf_.data();
  const size_t samples_to_write = out_frames * 2;

  // 在调用可能阻塞的 WriteWait 之前解锁
  lock.unlock();

  // 写入环形缓冲区：
  // 根据 SyncMode 决定是否阻塞
  // - AUDIO_BLOCKING: 阻塞等待空间 (正常游戏速度同步)
  // - NON_BLOCKING: 丢弃溢出数据 (Fast Forward)
  bool success = false;

  // 如果正在缓冲(buffering_)，始终非阻塞以快速填满
  bool should_block =
      (sync_mode_.load() == SyncMode::AUDIO_BLOCKING && !buffering_snapshot);

  if (buffer_ref) {
    auto write_start = std::chrono::steady_clock::now();
    if (should_block) {
      success = buffer_ref->WriteWaitFor(out_buf_data, samples_to_write,
                                         running_, kAudioProducerMaxBlockMs);
    } else {
      success = buffer_ref->Write(out_buf_data, samples_to_write);
    }
    auto write_end = std::chrono::steady_clock::now();
    int32_t write_us = static_cast<int32_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(write_end -
                                                              write_start)
            .count());
    if (write_us > 2000) {
      int log_count = ++process_audio_slow_log_count_;
      if (log_count <= 3 || (log_count % 120) == 0) {
        LOGF(LOG_WARN,
             "%{public}s %{public}s producer write slow: cost=%{public}d us, "
             "blocking=%{public}d, success=%{public}d, frames=%{public}d",
             kAudioChainPrefix, kAudioDiagPrefix, write_us,
             should_block ? 1 : 0, success ? 1 : 0,
             static_cast<int32_t>(out_frames));
      }
    }
  }
  float usage_after = buffer_ref ? buffer_ref->GetUsage() : 0.0f;
  {
    auto diag_now = std::chrono::steady_clock::now();
    if (diag_window_start_.time_since_epoch().count() == 0) {
      diag_window_start_ = diag_now;
    }
    diag_calls_++;
    diag_in_frames_ += frames;
    diag_out_frames_ += out_frames;
    if (should_block) {
      diag_blocking_calls_++;
    }
    if (!success) {
      diag_write_failures_++;
    }
    if (dt_ms > diag_max_dt_ms_) {
      diag_max_dt_ms_ = dt_ms;
    }
    const auto diag_elapsed_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            diag_now - diag_window_start_)
            .count();
    if (diag_elapsed_ms >= 1000) {
      const int32_t usage_before_percent =
          static_cast<int32_t>(usage_before * 100.0f + 0.5f);
      const int32_t usage_after_percent =
          static_cast<int32_t>(usage_after * 100.0f + 0.5f);
      uint64_t callback_count = 0;
      uint64_t callback_frames_read = 0;
      int64_t last_callback_ms = 0;
      if (audio_player_) {
        audio_player_->GetCallbackDiag(callback_count, callback_frames_read,
                                       last_callback_ms);
      }
      int64_t callback_age_ms = -1;
      if (last_callback_ms > 0) {
        const int64_t now_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                diag_now.time_since_epoch())
                .count();
        callback_age_ms = now_ms - last_callback_ms;
      }
      LOGF(LOG_INFO,
           "%{public}s %{public}s producer_window: ms=%{public}lld, "
           "calls=%{public}llu, in_frames=%{public}llu, "
           "out_frames=%{public}llu, write_fail=%{public}llu, "
           "blocking_calls=%{public}llu, max_gap_ms=%{public}d, "
           "usage=%{public}d%%->%{public}d%%, run_state=%{public}s, "
           "cb_count=%{public}llu, cb_read_frames=%{public}llu, "
           "cb_age_ms=%{public}lld",
           kAudioChainPrefix, kAudioDiagPrefix,
           static_cast<long long>(diag_elapsed_ms),
           static_cast<unsigned long long>(diag_calls_),
           static_cast<unsigned long long>(diag_in_frames_),
           static_cast<unsigned long long>(diag_out_frames_),
           static_cast<unsigned long long>(diag_write_failures_),
           static_cast<unsigned long long>(diag_blocking_calls_),
           diag_max_dt_ms_, usage_before_percent, usage_after_percent,
           AudioRunStateToString(GetRunState()),
           static_cast<unsigned long long>(callback_count),
           static_cast<unsigned long long>(callback_frames_read),
           static_cast<long long>(callback_age_ms));
      diag_window_start_ = diag_now;
      diag_calls_ = 0;
      diag_in_frames_ = 0;
      diag_out_frames_ = 0;
      diag_write_failures_ = 0;
      diag_blocking_calls_ = 0;
      diag_max_dt_ms_ = 0;
    }
  }
  if (!success) {
    recover_streak_ = std::min<uint32_t>(recover_streak_ + 1, 100);
    SetRunState(AudioRunState::RECOVERING, "producer_write_failed");
    LOGF(LOG_WARN,
         "%{public}s %{public}s producer drop: write failed (blocking=%{public}d)",
         kAudioChainPrefix, kAudioDiagPrefix, should_block ? 1 : 0);
  } else {
    if (recover_streak_ > 0) {
      recover_streak_--;
    }
    if (buffering_snapshot) {
      SetRunState(AudioRunState::BUFFERING, "producer_buffering");
    } else {
      SetRunState(AudioRunState::RUNNING, "producer_success");
    }
  }

  if (success && started_snapshot && !buffering_snapshot && buffer_ref) {
    const size_t min_frames = min_buffer_frames_.load();
    const size_t available_frames = buffer_ref->AvailableRead() / 2;
    size_t underruns = 0;
    size_t overruns = 0;
    buffer_ref->GetStats(underruns, overruns);
    const size_t last_rebuffer_underruns =
        last_rebuffer_underruns_.load(std::memory_order_relaxed);
    if (underruns > last_rebuffer_underruns && available_frames < min_frames) {
      std::lock_guard<std::mutex> guard(mutex_);
      if (audio_player_ && !buffering_ && audio_player_->IsPlaying()) {
        const bool paused = audio_player_->Pause();
        last_rebuffer_underruns_.store(underruns, std::memory_order_relaxed);
        if (paused) {
          buffering_ = true;
          SetRunState(AudioRunState::BUFFERING, "runtime_underrun_rebuffer");
        }
        LOGF(LOG_WARN,
             "%{public}s Runtime rebuffer after underrun: paused=%{public}d, "
             "available=%{public}zu frames, min=%{public}zu frames, "
             "underruns=%{public}zu, overruns=%{public}zu",
             kAudioChainPrefix, paused ? 1 : 0, available_frames, min_frames,
             underruns, overruns);
      }
    }
  }

  // [DEBUG] 采样生产日志 (每300次调用打印一次，避免刷屏)
  if (++process_audio_log_count_ % 300 == 0 || process_audio_log_count_ < 5) {
    // Check signal
    bool has_signal = false;
    for (size_t i = 0; i < samples_to_write; ++i) {
        if (resample_out_buf_[i] != 0) {
            has_signal = true;
            break;
        }
    }

    size_t avail_samples = buffer_ref ? buffer_ref->AvailableRead() : 0;
    float usage = buffer_ref ? buffer_ref->GetUsage() : 0.0f;
    LOGF(LOG_INFO,
         "%{public}s Producer: in=%{public}zu, out=%{public}zu, "
         "buffer=%{public}zu samples (usage=%{public}.1f%%), "
         "buffering=%{public}d, started=%{public}d, blocking=%{public}d, "
         "success=%{public}d, signal=%{public}d",
         kAudioChainPrefix, frames, out_frames, avail_samples, usage * 100.0f,
         buffering_snapshot, started_snapshot, should_block ? 1 : 0,
         success ? 1 : 0, has_signal);
  }
  process_audio_diag_log_count_++;
  if (process_audio_diag_log_count_ <= 5 ||
      (process_audio_diag_log_count_ % 300) == 0) {
    int32_t usage_before_percent =
        static_cast<int32_t>(usage_before * 100.0f + 0.5f);
    int32_t usage_after_percent =
        static_cast<int32_t>(usage_after * 100.0f + 0.5f);
    int32_t ratio_ppm = static_cast<int32_t>(ratio_snapshot * 1000000.0);
    int32_t skew_ppm =
        static_cast<int32_t>(drc_skew_.load() * 1000000.0);
    LOGF(LOG_INFO,
         "%{public}s %{public}s producer: in=%{public}d, out=%{public}d, "
         "dt=%{public}d ms, in_ms=%{public}d, buf=%{public}d%%->%{public}d%%, "
         "blocking=%{public}d, success=%{public}d, ratio_ppm=%{public}d, "
         "skew_ppm=%{public}d, buffering=%{public}d, started=%{public}d",
         kAudioChainPrefix, kAudioDiagPrefix, static_cast<int32_t>(frames),
         static_cast<int32_t>(out_frames), dt_ms, expected_ms,
         usage_before_percent, usage_after_percent, should_block ? 1 : 0,
         success ? 1 : 0, ratio_ppm, skew_ppm, buffering_snapshot ? 1 : 0,
         started_snapshot ? 1 : 0);
  }

  // DRC 动态比率微调（目标水位 50% ±10%，节流 ≥50ms）
  {
    auto now = std::chrono::steady_clock::now();
    // 简单的原子检查，无需加锁
    // 注意：GetUsage 内部是原子的，这里不需要加 AudioBridge 的大锁
    if (drc_last_update_.time_since_epoch().count() == 0 ||
        std::chrono::duration_cast<std::chrono::milliseconds>(now -
                                                              drc_last_update_)
                .count() >= kDrcUpdateIntervalMs) {
      float usage = buffer_ref ? buffer_ref->GetUsage() : 0.0f;
      double skew = drc_skew_.load();
      if (usage < kDrcLowThreshold) {
        skew = std::min(skew + kDrcStep, static_cast<double>(kDrcMaxSkew));
      } else if (usage > kDrcHighThreshold) {
        skew = std::max(skew - kDrcStep, static_cast<double>(kDrcMinSkew));
      }

      // 更新 Ratio 需要加锁,因为 Reset() 可能在另一线程重置 Resampler。
      // 原实现注释承认"风险可控"但实际是数据竞争 UB,这里恢复加锁。
      if (skew != drc_skew_.load()) {
        std::lock_guard<std::mutex> drc_guard(mutex_);
        drc_skew_.store(skew);
        resampler_.UpdateRatio(skew);
        int32_t skew_ppm = static_cast<int32_t>(skew * 1000000.0);
        int32_t usage_percent = static_cast<int32_t>(usage * 100.0f + 0.5f);
        LOGF(LOG_INFO,
             "%{public}s %{public}s DRC update: usage=%{public}d%%, "
             "skew_ppm=%{public}d",
             kAudioChainPrefix, kAudioDiagPrefix, usage_percent, skew_ppm);
      }
      drc_last_update_ = now;
    }
  }

  // Check buffering
  if (success && started_snapshot && buffering_snapshot) {
    // RingBuffer::AvailableRead() returns SAMPLES
    size_t available_samples = buffer_ref ? buffer_ref->AvailableRead() : 0;
    size_t available_frames = available_samples / 2;

    const size_t min_frames = min_buffer_frames_.load();

    if (available_frames >= min_frames) {
      LOGF(LOG_INFO,
           "%{public}s Buffering complete: %{public}zu >= %{public}zu frames. "
           "Starting player.",
           kAudioChainPrefix, available_frames, min_frames);
      {
        std::lock_guard<std::mutex> guard(mutex_);
        if (audio_player_ && buffering_) {
          if (audio_player_->Start()) {
            buffering_ = false;
            recover_streak_ = 0;
            SetRunState(AudioRunState::RUNNING, "buffering_complete");
          }
        }
      }
    }
  }

  // 返回实际处理的输入帧数（Libretro 语义），写入为 out_frames
  return success ? frames : 0;
}

// 现有的 Initialize (int32)
bool AudioBridge::Initialize(int32_t sample_rate) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (initialized_.load()) {
    // 已初始化：重置运行标志以支持重入
    running_.store(true, std::memory_order_release);
    buffering_ = false;
    is_started_ = false;
    recover_streak_ = 0;
    SetRunState(AudioRunState::INIT, "initialize_reuse");
    if (ring_buffer_) {
      ring_buffer_->Clear();
    }
    // Audit T3-F10: update core_sample_rate_ and reinit resampler if sample rate changed
    const int32_t new_rate = (sample_rate > 0 ? sample_rate : 48000);
    if (new_rate != core_sample_rate_) {
      LOGF(LOG_INFO, "%{public}s AudioBridge reuse: sample rate changed %{public}d->%{public}d, reinit resampler",
           kAudioChainPrefix, core_sample_rate_, new_rate);
      core_sample_rate_ = new_rate;
      resampler_.Init(core_sample_rate_, output_sample_rate_);
      drc_skew_.store(1.0);
    }
    LOGF(LOG_INFO,
         "%{public}s AudioBridge reuse: running reset, "
         "core_rate=%{public}d, out_rate=%{public}d",
         kAudioChainPrefix, core_sample_rate_, output_sample_rate_);
    return true;
  }
  // Libretro 核心采样率（输入）
  core_sample_rate_ = (sample_rate > 0 ? sample_rate : 48000);
  // 输出采样率固定 48k（OHAudio 建议）
  output_sample_rate_ = 48000;
  sample_rate_ = output_sample_rate_; // 兼容旧字段命名

  // 1. 创建环形缓冲区
  // 缓冲 1 秒音频数据 (立体声: 采样率 * 2)
  size_t buffer_capacity_samples = output_sample_rate_ * 2;
  // 使用新的 RingBuffer (传入 Samples)
  ring_buffer_ = std::make_unique<RingBuffer>(buffer_capacity_samples);

  // 设定最小缓冲帧数 (200ms)。OHAudio NORMAL 模式下单次回调约 20ms，
  // 100ms 水位在系统调度抖动时容易读穿，导致持续 underrun。
  default_min_buffer_frames_.store(output_sample_rate_ / 5);
  min_buffer_frames_.store(default_min_buffer_frames_.load());
  minimum_latency_ms_.store(0);

  // 2. 创建音频播放器
  audio_player_ = std::make_unique<AudioPlayer>();
  if (!audio_player_->Initialize(output_sample_rate_, 2, ring_buffer_.get(),
                                 &running_)) {
    LOGF(LOG_ERROR, "%{public}s Failed to initialize audio player",
         kAudioChainPrefix);
    audio_player_.reset();
    ring_buffer_.reset();
    return false;
  }

  // 3. 初始化重采样器（Core -> 48k）
  resampler_.Init(core_sample_rate_, output_sample_rate_);
  drc_skew_.store(1.0);

  initialized_.store(true, std::memory_order_release);
  is_started_ = false;
  buffering_ = false;
  running_.store(true, std::memory_order_release);
  last_rebuffer_underruns_.store(0, std::memory_order_relaxed);
  recover_streak_ = 0;
  SetRunState(AudioRunState::INIT, "initialize_success");

  LOGF(LOG_INFO,
       "%{public}s AudioBridge initialized: core_rate=%{public}d Hz, "
       "out_rate=%{public}d Hz, buffer_capacity=%{public}zu samples, "
       "min_buffer=%{public}zu frames (%{public}d ms), sync_mode=%{public}d",
       kAudioChainPrefix, core_sample_rate_, output_sample_rate_,
       buffer_capacity_samples, min_buffer_frames_.load(),
       (int)(min_buffer_frames_.load() * 1000 / output_sample_rate_),
       static_cast<int>(sync_mode_.load()));

  return true;
}

bool AudioBridge::Reset(int32_t sample_rate) {
  {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_.load() && core_sample_rate_ == sample_rate) {
      // 采样率未变化：复用现有实例，但需要在 stop 之后重新武装运行标志
      // 确保新的游戏会向 RingBuffer 写入数据，而不是因为 running_=false 导致
      // WriteWait 早退
      running_.store(true, std::memory_order_release);
      buffering_ = false;
      is_started_ = false;
      recover_streak_ = 0;
      if (ring_buffer_) {
        ring_buffer_->ResetStats();
        last_rebuffer_underruns_.store(0, std::memory_order_relaxed);
        // 清空旧数据，重新缓冲
        ring_buffer_->Clear();
      }
      // 重新初始化重采样器与 DRC 状态，以避免沿用上一次的动态比率
      resampler_.Init(core_sample_rate_, output_sample_rate_);
      drc_skew_.store(1.0);
      // Audit T3-F2: clear DRC throttle timestamp so the first post-Reset update is not delayed by stale timing
      drc_last_update_ = std::chrono::steady_clock::time_point{};
      SetRunState(AudioRunState::INIT, "reset_same_rate");

      LOGF(LOG_INFO,
           "%{public}s AudioBridge already configured with same core rate: "
           "%{public}d (re-armed)",
           kAudioChainPrefix, sample_rate);
      return true;
    }

    if (initialized_.load()) {
      if (audio_player_) {
        running_.store(false, std::memory_order_release);
        if (ring_buffer_)
          ring_buffer_->Clear();
        audio_player_->Stop();
        audio_player_.reset();
      }
      ring_buffer_.reset();
      initialized_.store(false);
      recover_streak_ = 0;
      // Audit T3-F2: clear DRC throttle timestamp on full reinit path too
      drc_last_update_ = std::chrono::steady_clock::time_point{};
      SetRunState(AudioRunState::INIT, "reset_reinit");
    }
  }

  return Initialize(sample_rate);
}

// Libretro 单帧音频回调
void AudioBridge::AudioSampleCallback(int16_t left, int16_t right) {
  auto *instance = GetInstance();
  if (!instance || !instance->initialized_.load(std::memory_order_acquire)) {
    return;
  }

  // 写入环形缓冲区 (1帧 = 2采样点)
  int16_t samples[2] = {left, right};
  instance->ProcessAudio(samples, 1);
}

// 修正：AudioBridge::AudioSampleBatchCallback 实现
size_t AudioBridge::AudioSampleBatchCallback(const int16_t *data,
                                             size_t frames) {
  auto *instance = GetInstance();
  if (!instance || !instance->initialized_.load(std::memory_order_acquire)) {
    return frames;
  }
  return instance->ProcessAudio(data, frames);
}

bool AudioBridge::Pause() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_.load() || !audio_player_) {
    return false;
  }

  is_started_ = false; // Stop logical
  buffering_ = false;
  running_.store(false, std::memory_order_release);
  recover_streak_ = 0;
  if (ring_buffer_) {
    ring_buffer_->Clear();
  }

  bool success = audio_player_->Pause();
  if (success) {
    SetRunState(AudioRunState::PAUSED, "pause_success");
    LOGF(LOG_INFO, "%{public}s AudioBridge paused", kAudioChainPrefix);
  } else {
    SetRunState(AudioRunState::RECOVERING, "pause_failed");
  }

  return success;
}

bool AudioBridge::Stop() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_.load() || !audio_player_) {
    return false;
  }

  is_started_ = false; // Stop logical
  buffering_ = false;
  // 通知停止，以唤醒等待的读写方
  running_.store(false, std::memory_order_release);
  recover_streak_ = 0;
  if (ring_buffer_) {
    ring_buffer_->Clear();
  }

  bool success = audio_player_->Stop();
  if (success) {
    SetRunState(AudioRunState::PAUSED, "stop_success");
    LOGF(LOG_INFO, "%{public}s AudioBridge stopped", kAudioChainPrefix);

    // 打印缓冲区统计信息
    if (ring_buffer_) {
      size_t underruns = 0;
      size_t overruns = 0;
      ring_buffer_->GetStats(underruns, overruns);
      LOGF(LOG_INFO,
           "%{public}s Buffer stats: usage=%{public}.1f%%, "
           "underruns=%{public}d, overruns=%{public}d",
           kAudioChainPrefix, ring_buffer_->GetUsage() * 100.0f,
           static_cast<int32_t>(underruns),
           static_cast<int32_t>(overruns));
    }
  }
  if (!success) {
    SetRunState(AudioRunState::RECOVERING, "stop_failed");
  }
  return success;
}

bool AudioBridge::IsPlaying() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_ || !audio_player_) {
    return false;
  }

  return audio_player_->IsPlaying();
}

float AudioBridge::GetBufferUsage() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_ || !ring_buffer_) {
    return 0.0f;
  }

  return ring_buffer_->GetUsage();
}

size_t AudioBridge::GetBufferedFrames() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_ || !ring_buffer_) {
    return 0;
  }
  return ring_buffer_->AvailableRead() / 2;
}

void AudioBridge::GetBufferStats(size_t &underruns, size_t &overruns) const {
  std::lock_guard<std::mutex> lock(mutex_);
  underruns = 0;
  overruns = 0;

  if (!initialized_ || !ring_buffer_) {
    return;
  }

  ring_buffer_->GetStats(underruns, overruns);
}

void AudioBridge::GetCallbackDiag(uint64_t &callbackCount, uint64_t &framesRead,
                                  int64_t &lastCallbackMs) const {
  std::lock_guard<std::mutex> lock(mutex_);
  callbackCount = 0;
  framesRead = 0;
  lastCallbackMs = 0;

  if (!initialized_ || !audio_player_) {
    return;
  }

  audio_player_->GetCallbackDiag(callbackCount, framesRead, lastCallbackMs);
}

void AudioBridge::ResetBufferStats() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!initialized_ || !ring_buffer_) {
    return;
  }

  ring_buffer_->ResetStats();
}

} // namespace libretro
