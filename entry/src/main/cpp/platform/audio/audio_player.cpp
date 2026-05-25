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

#include "audio_player.h"
#include <chrono> // Phase 3.3+ - 音频工作组时间戳
#include <cstring>
#include <time.h>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "AudioPlayer"
#undef LOG_FLOW
#define LOG_FLOW "Audio"
#include "common/log_prefix.h"

namespace libretro {

namespace {
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";
constexpr const char *kAudioDiagPrefix = "[AUDIO_DIAG]";

class CallbackGuard {
public:
  explicit CallbackGuard(AudioPlayer *player) : player_(player) {
    active_ = player_ && player_->EnterCallback();
  }

  ~CallbackGuard() {
    if (active_) {
      player_->ExitCallback();
    }
  }

  bool IsActive() const { return active_; }

private:
  AudioPlayer *player_ = nullptr;
  bool active_ = false;
};
}

AudioPlayer::AudioPlayer() {
  LOGF(LOG_INFO, "%{public}s AudioPlayer created", kAudioChainPrefix);
}

AudioPlayer::~AudioPlayer() {
  Cleanup();
  LOGF(LOG_INFO, "%{public}s AudioPlayer destroyed", kAudioChainPrefix);
}

bool AudioPlayer::EnterCallback() {
  std::lock_guard<std::mutex> lock(callback_mutex_);
  if (shutting_down_) {
    return false;
  }
  ++active_callbacks_;
  return true;
}

void AudioPlayer::ExitCallback() {
  std::lock_guard<std::mutex> lock(callback_mutex_);
  if (active_callbacks_ > 0) {
    --active_callbacks_;
  }
  if (active_callbacks_ == 0) {
    callback_cond_.notify_all();
  }
}

bool AudioPlayer::IsShuttingDown() const {
  std::lock_guard<std::mutex> lock(callback_mutex_);
  return shutting_down_;
}

bool AudioPlayer::Initialize(int32_t sample_rate, int32_t channel_count,
                             RingBuffer *ring_buffer,
                             const std::atomic<bool>* running) {
  if (!ring_buffer) {
    LOGF(LOG_ERROR,"RingBuffer is null");
    return false;
  }

  sample_rate_ = sample_rate;
  channel_count_ = channel_count;
  ring_buffer_ = ring_buffer;
  running_ = running;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = false;
    resume_on_interrupt_ = false;
    workgroup_token_ = 0;
  }
  pending_interrupt_pause_.store(false, std::memory_order_release);
  pending_interrupt_resume_.store(false, std::memory_order_release);
  pending_interrupt_stop_.store(false, std::memory_order_release);
  {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    shutting_down_ = false;
    active_callbacks_ = 0;
  }

  // 1. 创建音频流构造器
  OH_AudioStream_Result result =
      OH_AudioStreamBuilder_Create(&builder_, AUDIOSTREAM_TYPE_RENDERER);

  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR, "%{public}s Failed to create audio stream builder: %{public}d",
         kAudioChainPrefix, result);
    return false;
  }

  // 2. 配置音频流参数 (基于官方文档推荐配置)

  // 采样率
  OH_AudioStreamBuilder_SetSamplingRate(builder_, sample_rate_);

  // 声道数
  OH_AudioStreamBuilder_SetChannelCount(builder_, channel_count_);

  // 采样格式: 16-bit PCM (Libretro 标准格式)
  OH_AudioStreamBuilder_SetSampleFormat(builder_, AUDIOSTREAM_SAMPLE_S16LE);

  // 编码类型: 原始 PCM
  OH_AudioStreamBuilder_SetEncodingType(builder_,
                                        AUDIOSTREAM_ENCODING_TYPE_RAW);

  // 注意：OHAudio Native API (API 11/12) 的 Builder 中似乎没有 SetVolume 接口
  // 音量通常在 Renderer 创建后通过 OH_AudioRenderer_SetVolume 设置
  // 或者在 ArkTS 层管理音量
  
  // 低时延模式 (游戏音频推荐) -> 改为 NORMAL 以增强抗卡顿能力
  // 用户反馈长时间运行后卡顿，FAST 模式下 100ms 的调度延迟会导致音频断续
  OH_AudioStreamBuilder_SetLatencyMode(builder_, AUDIOSTREAM_LATENCY_MODE_NORMAL);

  // 音频流类型: 游戏音效
  OH_AudioStreamBuilder_SetRendererInfo(builder_, AUDIOSTREAM_USAGE_GAME);

  // 设置回调帧大小: 20ms (增加缓冲粒度，减少回调频率)
  // 32768Hz -> ~655 frames, 44100Hz -> ~882 frames
  int32_t frame_size = sample_rate_ / 50;
  result = OH_AudioStreamBuilder_SetFrameSizeInCallback(builder_, frame_size);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to set frame size in callback: %{public}d",
         kAudioChainPrefix, result);
    Cleanup(); // Audit T3-F4: SetFrameSizeInCallback failure is fatal; cleanup before returning
    return false;
  }
  LOGF(LOG_INFO,
       "%{public}s Set frame size in callback: %{public}d frames (20ms)",
       kAudioChainPrefix, frame_size);
  const int32_t bytes_per_frame =
      static_cast<int32_t>(sizeof(int16_t)) * channel_count_;
  LOGF(LOG_INFO,
       "%{public}s %{public}s init: rate=%{public}d, ch=%{public}d, "
       "frame_size=%{public}d, bytes_per_frame=%{public}d",
       kAudioChainPrefix, kAudioDiagPrefix, sample_rate_, channel_count_,
       frame_size, bytes_per_frame);

  // 3. 设置回调函数
  OH_AudioRenderer_Callbacks callbacks;
  memset(&callbacks, 0, sizeof(OH_AudioRenderer_Callbacks));
  // API 11 回调：在旧版本上由 builder callbacks 使用
  callbacks.OH_AudioRenderer_OnWriteData = OnWriteDataLegacy;
  callbacks.OH_AudioRenderer_OnInterruptEvent = OnInterruptEvent;

  result = OH_AudioStreamBuilder_SetRendererCallback(builder_, callbacks, this);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to set renderer callback: %{public}d",
         kAudioChainPrefix, result);
    Cleanup();
    return false;
  }

  // API 12+ 推荐: 使用 SetRendererWriteDataCallback 设置写入回调
  OH_AudioRenderer_OnWriteDataCallback writeDataCb = OnWriteDataCallback;
  result = OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder_, writeDataCb, this);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to set renderer write data callback: %{public}d",
         kAudioChainPrefix, result);
    Cleanup();
    return false;
  }

  // 4. 生成音频渲染器
  result = OH_AudioStreamBuilder_GenerateRenderer(builder_, &renderer_);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to generate audio renderer: %{public}d",
         kAudioChainPrefix, result);
    Cleanup();
    return false;
  }
  
  // 设置音量为 1.0
  OH_AudioRenderer_SetVolume(renderer_, 1.0f);

  // 5. Phase 3.3+ - 创建音频工作组 (官方推荐优化)
  OH_AudioCommon_Result workgroup_result =
      OH_AudioManager_GetAudioResourceManager(&resource_manager_);
  if (workgroup_result == AUDIOCOMMON_RESULT_SUCCESS && resource_manager_) {
    workgroup_result =
        OH_AudioResourceManager_CreateWorkgroup(resource_manager_,
                                                "libretro_audio", // 工作组名称
                                                &workgroup_);

    if (workgroup_result == AUDIOCOMMON_RESULT_SUCCESS && workgroup_) {
      LOGF(LOG_INFO, "%{public}s Audio workgroup created", kAudioChainPrefix);
    } else {
      LOGF(LOG_WARN, "%{public}s Failed to create audio workgroup: %{public}d",
           kAudioChainPrefix, workgroup_result);
      // 非致命错误，继续运行
    }
  } else {
    LOGF(LOG_WARN,
         "%{public}s Failed to get audio resource manager: %{public}d",
         kAudioChainPrefix, workgroup_result);
    // 非致命错误，继续运行
  }

  LOGF(LOG_INFO,
       "%{public}s AudioPlayer initialized: %{public}d Hz, %{public}d channels, "
       "latency mode: NORMAL",
       kAudioChainPrefix, sample_rate_, channel_count_);

  return true;
}

bool AudioPlayer::Start() {
  if (IsShuttingDown()) {
    LOGF(LOG_WARN, "%{public}s Start ignored: cleanup in progress",
         kAudioChainPrefix);
    return false;
  }

  OH_AudioRenderer *renderer = nullptr;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    renderer = renderer_;
    if (!renderer) {
      LOGF(LOG_ERROR, "%{public}s Audio renderer not initialized",
           kAudioChainPrefix);
      return false;
    }
    if (is_playing_) {
      LOGF(LOG_WARN, "%{public}s Audio player already playing",
           kAudioChainPrefix);
      return true;
    }
  }

  OH_AudioStream_Result result = OH_AudioRenderer_Start(renderer);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to start audio renderer: %{public}d",
         kAudioChainPrefix, result);
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = true;
    resume_on_interrupt_ = false;
  }
  pending_interrupt_pause_.store(false, std::memory_order_release);
  pending_interrupt_resume_.store(false, std::memory_order_release);
  pending_interrupt_stop_.store(false, std::memory_order_release);
  LOGF(LOG_INFO, "%{public}s AudioPlayer started", kAudioChainPrefix);

  return true;
}

bool AudioPlayer::Pause() {
  OH_AudioRenderer *renderer = nullptr;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    renderer = renderer_;
    if (!renderer) {
      LOGF(LOG_ERROR, "%{public}s Audio renderer not initialized",
           kAudioChainPrefix);
      return false;
    }
    if (!is_playing_) {
      LOGF(LOG_WARN, "%{public}s Audio player not playing", kAudioChainPrefix);
      return true;
    }
  }

  OH_AudioStream_Result result = OH_AudioRenderer_Pause(renderer);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to pause audio renderer: %{public}d",
         kAudioChainPrefix, result);
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = false;
    resume_on_interrupt_ = false;
  }
  pending_interrupt_pause_.store(false, std::memory_order_release);
  pending_interrupt_resume_.store(false, std::memory_order_release);
  pending_interrupt_stop_.store(false, std::memory_order_release);
  LOGF(LOG_INFO, "%{public}s AudioPlayer paused", kAudioChainPrefix);

  return true;
}

bool AudioPlayer::Stop() {
  OH_AudioRenderer *renderer = nullptr;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    renderer = renderer_;
    if (!renderer) {
      LOGF(LOG_ERROR, "%{public}s Audio renderer not initialized",
           kAudioChainPrefix);
      return false;
    }
    if (!is_playing_) {
      return true;
    }
  }

  OH_AudioStream_Result result = OH_AudioRenderer_Stop(renderer);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_ERROR,
         "%{public}s Failed to stop audio renderer: %{public}d",
         kAudioChainPrefix, result);
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = false;
    resume_on_interrupt_ = false;
  }
  pending_interrupt_pause_.store(false, std::memory_order_release);
  pending_interrupt_resume_.store(false, std::memory_order_release);
  pending_interrupt_stop_.store(false, std::memory_order_release);

  // 清空缓冲区
  if (ring_buffer_) {
    ring_buffer_->Clear();
  }

  LOGF(LOG_INFO, "%{public}s AudioPlayer stopped", kAudioChainPrefix);

  return true;
}

bool AudioPlayer::IsPlaying() const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  return is_playing_;
}

bool AudioPlayer::PauseFromInterrupt() {
  OH_AudioRenderer *renderer = nullptr;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    renderer = renderer_;
    if (!renderer) {
      return false;
    }
    if (!is_playing_) {
      return true;
    }
  }

  OH_AudioStream_Result result = OH_AudioRenderer_Pause(renderer);
  if (result != AUDIOSTREAM_SUCCESS) {
    LOGF(LOG_WARN, "%{public}s Deferred interrupt pause failed: %{public}d",
         kAudioChainPrefix, result);
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = false;
  }
  return true;
}

void AudioPlayer::ProcessPendingInterruptActions() {
  if (pending_interrupt_stop_.exchange(false, std::memory_order_acq_rel)) {
    (void)Stop();
    return;
  }

  if (pending_interrupt_pause_.exchange(false, std::memory_order_acq_rel)) {
    (void)PauseFromInterrupt();
  }

  if (pending_interrupt_resume_.exchange(false, std::memory_order_acq_rel)) {
    (void)Start();
  }
}

// OHAudio 回调: 写入数据 (API 12+ 推荐)
OH_AudioData_Callback_Result AudioPlayer::OnWriteDataCallback(
    OH_AudioRenderer *renderer, void *userData, void *audioData,
    int32_t audioDataSize) {
  auto *player = static_cast<AudioPlayer *>(userData);
  auto cb_start = std::chrono::steady_clock::now();
  if (!player || !player->ring_buffer_ || !audioData || audioDataSize <= 0) {
    return AUDIO_DATA_CALLBACK_RESULT_INVALID;
  }
  CallbackGuard callbackGuard(player);
  if (!callbackGuard.IsActive()) {
    return AUDIO_DATA_CALLBACK_RESULT_INVALID;
  }

  // 若收到停止信号，则快速返回 INVALID，避免阻塞音频线程
  if (player->running_ && !player->running_->load()) {
    int log_count = ++player->callback_invalid_log_count_;
    if (log_count <= 3 || (log_count % 120) == 0) {
      LOGF(LOG_INFO, "%{public}s %{public}s [API12] running=false -> INVALID",
           kAudioChainPrefix, kAudioDiagPrefix);
    }
    return AUDIO_DATA_CALLBACK_RESULT_INVALID;
  }

  if (!player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_ && player->workgroup_token_ == 0) {
      OH_AudioCommon_Result add_result =
          OH_AudioWorkgroup_AddCurrentThread(player->workgroup_,
                                             &player->workgroup_token_);
      if (add_result == AUDIOCOMMON_RESULT_SUCCESS &&
          player->workgroup_token_ > 0) {
        LOGF(LOG_INFO,
             "%{public}s Audio workgroup thread added (token: %{public}d)",
             kAudioChainPrefix, player->workgroup_token_);
      } else {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: AddCurrentThread failed (%{public}d)",
               kAudioChainPrefix, add_result);
        }
        player->workgroup_token_ = -1;
      }
    }
  }

  // 计算需要的帧数
  int32_t bytes_per_sample = sizeof(int16_t);
  int32_t bytes_per_frame = bytes_per_sample * player->channel_count_;
  if (bytes_per_frame <= 0) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
  }
  int32_t frames_needed = audioDataSize / bytes_per_frame;
  if (frames_needed <= 0) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
  }
  const int32_t bytes_filled = frames_needed * bytes_per_frame;
  const int32_t tail_bytes = audioDataSize - bytes_filled;

  bool workgroup_started = false;

  // Phase 3.3+ - 通知音频工作组开始处理（可选优化，失败则自动禁用）
  if (!player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_ && player->workgroup_token_ > 0) {
      timespec ts{};
      clock_gettime(CLOCK_MONOTONIC, &ts);
      uint64_t start_ns = static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
                          static_cast<uint64_t>(ts.tv_nsec);

      uint64_t work_ns =
          (static_cast<uint64_t>(frames_needed) * 1000000000ULL +
           static_cast<uint64_t>(player->sample_rate_) - 1ULL) /
          static_cast<uint64_t>(player->sample_rate_);
      if (work_ns < 1) {
        work_ns = 1;
      }

      OH_AudioCommon_Result start_result =
          OH_AudioWorkgroup_Start(player->workgroup_, start_ns,
                                  start_ns + work_ns);
      workgroup_started = (start_result == AUDIOCOMMON_RESULT_SUCCESS);
      if (!workgroup_started) {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: Start failed (%{public}d)",
               kAudioChainPrefix, start_result);
        }
      }
    }
  }

  // [DEBUG] 记录回调时间间隔（使用成员变量避免多线程数据竞争）
  auto current_time = std::chrono::steady_clock::now();
  long long delta_ms = 0;
  if (player->callback_log_count_ > 0) {
    delta_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                   current_time - player->callback_last_time_)
                   .count();
  }
  player->callback_last_time_ = current_time;

  // 非阻塞拉取：数据不足时由 RingBuffer 填充静音，保证回调及时返回
  // [Fix] API12 建议：如果数据不足，返回 INVALID 让系统处理（通常是重试或静音），而不是手动填静音
  // 但为了保持平滑，我们尝试 ReadWait（带极短超时或无超时），如果还是不足，才 VALID + 静音
  // 考虑到 RingBuffer::Read 已经是非阻塞的，我们在这里做个策略选择：
  // 1. 尝试读取
  size_t samples_needed = static_cast<size_t>(frames_needed) * player->channel_count_;
  size_t samples_read = player->ring_buffer_->Read(
      static_cast<int16_t *>(audioData), samples_needed);
  
  size_t frames_read = samples_read / player->channel_count_;

  size_t underruns = 0;
  size_t overruns = 0;
  if (player->ring_buffer_) {
    player->ring_buffer_->GetStats(underruns, overruns);
  }
  const size_t frames_needed_sz = static_cast<size_t>(frames_needed);
  const size_t missing_frames =
      (frames_read < frames_needed_sz) ? (frames_needed_sz - frames_read) : 0;

  if (frames_read < frames_needed) {
      // 欠载处理
      size_t bytes_read = frames_read * bytes_per_frame;
      size_t bytes_missing = (frames_needed - frames_read) * bytes_per_frame;
      std::memset(static_cast<uint8_t *>(audioData) + bytes_read, 0, bytes_missing);
      
      // [Fix] 记录欠载，但在 API12 中如果严重欠载（例如读取为 0），可以考虑返回 INVALID
      // 不过为了稳健性，目前仍返回 VALID，只是打个警告日志（限流）
      // 线上难以定位问题是因为缺乏 INVALID 信号？
      // 我们可以引入一个阈值，比如连续欠载 N 次后返回 INVALID
  }

  if (missing_frames > 0) {
    int log_count = ++player->callback_underrun_log_count_;
    if (log_count <= 5 || (log_count % 120) == 0) {
      float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
      int32_t usage_percent = static_cast<int32_t>(usage * 100.0f + 0.5f);
      LOGF(LOG_WARN,
           "%{public}s %{public}s [API12] underrun: need=%{public}d "
           "read=%{public}d miss=%{public}d size=%{public}d bytes "
           "usage=%{public}d%% underruns=%{public}d overruns=%{public}d "
           "running=%{public}d wg=%{public}d",
           kAudioChainPrefix, kAudioDiagPrefix, frames_needed,
           static_cast<int32_t>(frames_read),
           static_cast<int32_t>(missing_frames), audioDataSize, usage_percent,
           static_cast<int32_t>(underruns), static_cast<int32_t>(overruns),
           (player->running_ && player->running_->load()) ? 1 : 0,
           workgroup_started ? 1 : 0);
    }
  }

  if (delta_ms >= 40) {
    int jitter_count = ++player->callback_jitter_log_count_;
    if (jitter_count <= 3 || (jitter_count % 120) == 0) {
      float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
      LOGF(LOG_WARN,
           "%{public}s [API12] callback jitter: dt=%{public}lld ms, "
           "frames=%{public}d read=%{public}zu (usage=%{public}.1f%%)",
           kAudioChainPrefix, (long long)delta_ms, frames_needed, frames_read,
           usage * 100.0f);
    }
  }

  if (tail_bytes > 0) {
    std::memset(static_cast<uint8_t *>(audioData) + bytes_filled, 0,
                static_cast<size_t>(tail_bytes));
  }

  if (workgroup_started && !player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_) {
      OH_AudioCommon_Result stop_result =
          OH_AudioWorkgroup_Stop(player->workgroup_);
      if (stop_result != AUDIOCOMMON_RESULT_SUCCESS) {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: Stop failed (%{public}d)",
               kAudioChainPrefix, stop_result);
        }
      }
    }
  }

  auto cb_end = std::chrono::steady_clock::now();
  int32_t cost_us = static_cast<int32_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(cb_end - cb_start)
          .count());
  if (cost_us > 2000) {
    int log_count = ++player->callback_cost_log_count_;
    if (log_count <= 3 || (log_count % 120) == 0) {
      LOGF(LOG_WARN,
           "%{public}s %{public}s [API12] callback slow: cost=%{public}d us, "
           "dt=%{public}lld ms, frames=%{public}d, read=%{public}d",
           kAudioChainPrefix, kAudioDiagPrefix, cost_us, (long long)delta_ms,
           frames_needed, static_cast<int32_t>(frames_read));
    }
  }

  // 检测是否有非零数据 (Debug)
  bool has_sound = false;
  const int16_t* pcm = static_cast<const int16_t*>(audioData);
  // 只检查前 100 个采样点以提高性能，或者检查全部
  // 考虑到这是回调，尽量快。检查全部也不会太慢（10ms 数据量很小）。
  for (size_t i = 0; i < samples_read; ++i) {
      if (pcm[i] != 0) {
          has_sound = true;
          break;
      }
  }

  // 回调统计与日志（限流打印，使用成员变量避免多线程数据竞争）
  player->callback_log_count_++;
  if (player->callback_log_count_ <= 5 || (player->callback_log_count_ % 250) == 0) {
    float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
    LOGF(LOG_INFO,
        "%{public}s [API12] dt=%{public}lld ms, frames=%{public}d "
        "read=%{public}zu (signal=%{public}d, usage=%{public}.1f%%) -> VALID",
        kAudioChainPrefix, (long long)delta_ms, frames_needed, frames_read,
        has_sound, usage * 100.0f);
  }
  player->callback_diag_log_count_++;
  if (player->callback_diag_log_count_ <= 5 ||
      (player->callback_diag_log_count_ % 250) == 0) {
    float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
    int32_t usage_percent = static_cast<int32_t>(usage * 100.0f + 0.5f);
    LOGF(LOG_INFO,
         "%{public}s %{public}s [API12] size=%{public}d bytes, "
         "bytes_per_frame=%{public}d, need=%{public}d, read=%{public}d, "
         "miss=%{public}d, usage=%{public}d%%, underruns=%{public}d, "
         "overruns=%{public}d, cost=%{public}d us, running=%{public}d",
         kAudioChainPrefix, kAudioDiagPrefix, audioDataSize, bytes_per_frame,
         frames_needed, static_cast<int32_t>(frames_read),
         static_cast<int32_t>(missing_frames), usage_percent,
         static_cast<int32_t>(underruns), static_cast<int32_t>(overruns),
         cost_us, (player->running_ && player->running_->load()) ? 1 : 0);
  }

  return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

// OHAudio 回调: 写入数据 (API 11 兼容)
int32_t AudioPlayer::OnWriteDataLegacy(OH_AudioRenderer *renderer,
                                       void *userData,
                                       void *audioData,
                                       int32_t audioDataSize) {
  auto *player = static_cast<AudioPlayer *>(userData);
  auto cb_start = std::chrono::steady_clock::now();
  if (!player || !player->ring_buffer_ || !audioData || audioDataSize <= 0) {
    return 0;
  }
  CallbackGuard callbackGuard(player);
  if (!callbackGuard.IsActive()) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return audioDataSize;
  }

  if (player->running_ && !player->running_->load()) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return audioDataSize;
  }

  int32_t bytes_per_sample = sizeof(int16_t);
  int32_t bytes_per_frame = bytes_per_sample * player->channel_count_;
  if (bytes_per_frame <= 0) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return audioDataSize;
  }

  int32_t frames_needed = audioDataSize / bytes_per_frame;
  if (frames_needed <= 0) {
    std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
    return audioDataSize;
  }
  const int32_t bytes_filled = frames_needed * bytes_per_frame;
  const int32_t tail_bytes = audioDataSize - bytes_filled;

  bool workgroup_started = false;
  if (!player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_ && player->workgroup_token_ == 0) {
      OH_AudioCommon_Result add_result = OH_AudioWorkgroup_AddCurrentThread(
          player->workgroup_, &player->workgroup_token_);
      if (add_result == AUDIOCOMMON_RESULT_SUCCESS &&
          player->workgroup_token_ > 0) {
        LOGF(LOG_INFO,
             "%{public}s Audio workgroup thread added (token: %{public}d)",
             kAudioChainPrefix, player->workgroup_token_);
      } else {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: AddCurrentThread failed (%{public}d)",
               kAudioChainPrefix, add_result);
        }
        player->workgroup_token_ = -1;
      }
    }
  }

  if (!player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_ && player->workgroup_token_ > 0) {
      timespec ts{};
      clock_gettime(CLOCK_MONOTONIC, &ts);
      uint64_t start_ns = static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
                          static_cast<uint64_t>(ts.tv_nsec);
      uint64_t work_ns =
          (static_cast<uint64_t>(frames_needed) * 1000000000ULL +
           static_cast<uint64_t>(player->sample_rate_) - 1ULL) /
          static_cast<uint64_t>(player->sample_rate_);
      if (work_ns < 1) {
        work_ns = 1;
      }
      OH_AudioCommon_Result start_result =
          OH_AudioWorkgroup_Start(player->workgroup_, start_ns,
                                  start_ns + work_ns);
      workgroup_started = (start_result == AUDIOCOMMON_RESULT_SUCCESS);
      if (!workgroup_started) {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: Start failed (%{public}d)",
               kAudioChainPrefix, start_result);
        }
      }
    }
  }

  // 非阻塞读取：数据不足时由 RingBuffer 填充静音
  size_t samples_needed = static_cast<size_t>(frames_needed) * player->channel_count_;
  size_t samples_read = player->ring_buffer_->Read(
      static_cast<int16_t *>(audioData), samples_needed);

  size_t frames_read = samples_read / player->channel_count_;
  
  // LockFreeRingBuffer::Read 不自动填充静音，需手动处理
  if (frames_read < frames_needed) {
      size_t bytes_read = frames_read * bytes_per_frame;
      size_t bytes_missing = (frames_needed - frames_read) * bytes_per_frame;
      std::memset(static_cast<uint8_t *>(audioData) + bytes_read, 0, bytes_missing);
  }

  if (tail_bytes > 0) {
    std::memset(static_cast<uint8_t *>(audioData) + bytes_filled, 0,
                static_cast<size_t>(tail_bytes));
  }

  if (workgroup_started &&
      !player->workgroup_disabled_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(player->state_mutex_);
    if (player->workgroup_) {
      OH_AudioCommon_Result stop_result =
          OH_AudioWorkgroup_Stop(player->workgroup_);
      if (stop_result != AUDIOCOMMON_RESULT_SUCCESS) {
        bool expected = false;
        if (player->workgroup_disabled_.compare_exchange_strong(
                expected, true, std::memory_order_relaxed)) {
          LOGF(LOG_WARN,
               "%{public}s Audio workgroup disabled: Stop failed (%{public}d)",
               kAudioChainPrefix, stop_result);
        }
      }
    }
  }
  // 正常路径限流日志（使用成员变量避免多线程数据竞争）
  player->legacy_cb11_log_count_++;
  if (frames_read > 0 &&
      (player->legacy_cb11_log_count_ <= 5 ||
       (player->legacy_cb11_log_count_ % 250) == 0)) {
    float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
    LOGF(LOG_INFO,
         "%{public}s [API11] frames=%{public}d read=%{public}zu "
         "(usage=%{public}.1f%%) -> return=%{public}d bytes",
         kAudioChainPrefix, frames_needed, frames_read, usage * 100.0f,
         audioDataSize);
  }
  player->legacy_diag_log_count_++;
  if (player->legacy_diag_log_count_ <= 5 ||
      (player->legacy_diag_log_count_ % 250) == 0) {
    size_t underruns = 0;
    size_t overruns = 0;
    if (player->ring_buffer_) {
      player->ring_buffer_->GetStats(underruns, overruns);
    }
    float usage = player->ring_buffer_ ? player->ring_buffer_->GetUsage() : 0.0f;
    int32_t usage_percent = static_cast<int32_t>(usage * 100.0f + 0.5f);
    auto cb_end = std::chrono::steady_clock::now();
    int32_t cost_us = static_cast<int32_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(cb_end - cb_start)
            .count());
    const size_t frames_needed_sz = static_cast<size_t>(frames_needed);
    const size_t missing_frames =
        (frames_read < frames_needed_sz) ? (frames_needed_sz - frames_read) : 0;
    LOGF(LOG_INFO,
         "%{public}s %{public}s [API11] size=%{public}d bytes, "
         "bytes_per_frame=%{public}d, need=%{public}d, read=%{public}d, "
         "miss=%{public}d, usage=%{public}d%%, underruns=%{public}d, "
         "overruns=%{public}d, cost=%{public}d us",
         kAudioChainPrefix, kAudioDiagPrefix, audioDataSize, bytes_per_frame,
         frames_needed, static_cast<int32_t>(frames_read),
         static_cast<int32_t>(missing_frames), usage_percent,
         static_cast<int32_t>(underruns), static_cast<int32_t>(overruns),
         cost_us);
  }
  return audioDataSize;
}

// OHAudio 回调: 音频中断事件
int32_t AudioPlayer::OnInterruptEvent(OH_AudioRenderer *renderer,
                                      void *userData,
                                      OH_AudioInterrupt_ForceType type,
                                      OH_AudioInterrupt_Hint hint) {
  (void)renderer;
  auto *player = static_cast<AudioPlayer *>(userData);
  if (!player) {
    return 0;
  }
  CallbackGuard callbackGuard(player);
  if (!callbackGuard.IsActive()) {
    return 0;
  }

  // 记录中断事件
  LOGF(LOG_INFO, "%{public}s Audio interrupt: type=%{public}d, hint=%{public}d",
       kAudioChainPrefix, type, hint);

  // 根据中断类型处理
  switch (hint) {
  case AUDIOSTREAM_INTERRUPT_HINT_PAUSE:
    // 音频焦点丢失：回调线程只打标记，Pause 在安全线程执行
    {
      std::lock_guard<std::mutex> lock(player->state_mutex_);
      if (player->is_playing_) {
        player->resume_on_interrupt_ = true;
      }
    }
    player->pending_interrupt_resume_.store(false, std::memory_order_release);
    player->pending_interrupt_pause_.store(true, std::memory_order_release);
    {
      std::lock_guard<std::mutex> lock(player->state_mutex_);
      LOGF(LOG_INFO,
           "%{public}s Audio paused due to interrupt (resume_later=%{public}d)",
           kAudioChainPrefix, player->resume_on_interrupt_ ? 1 : 0);
    }
    break;

  case AUDIOSTREAM_INTERRUPT_HINT_RESUME: {
    // 音频焦点恢复：仅标记恢复请求，在安全线程执行 Start
    bool resume = false;
    {
      std::lock_guard<std::mutex> lock(player->state_mutex_);
      resume = player->resume_on_interrupt_;
      if (resume) {
        player->resume_on_interrupt_ = false;
      }
      LOGF(LOG_INFO,
           "%{public}s Audio resume hint received (resume_flag=%{public}d)",
           kAudioChainPrefix, resume ? 1 : 0);
    }
    if (resume) {
      player->pending_interrupt_pause_.store(false, std::memory_order_release);
      player->pending_interrupt_resume_.store(true, std::memory_order_release);
    }
    break;
  }

  case AUDIOSTREAM_INTERRUPT_HINT_STOP:
    // 音频焦点永久丢失：仅打标记，在安全线程执行 Stop
    {
      std::lock_guard<std::mutex> lock(player->state_mutex_);
      player->resume_on_interrupt_ = false;
    }
    player->pending_interrupt_pause_.store(false, std::memory_order_release);
    player->pending_interrupt_resume_.store(false, std::memory_order_release);
    player->pending_interrupt_stop_.store(true, std::memory_order_release);
    LOGF(LOG_INFO, "%{public}s Audio stopped due to interrupt",
         kAudioChainPrefix);
    break;

  default:
    break;
  }

  return 0;
}

void AudioPlayer::Cleanup() {
  {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    shutting_down_ = true;
  }

  OH_AudioRenderer *renderer = nullptr;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    renderer = renderer_;
  }

  bool stopSucceeded = false;
  if (renderer) {
    OH_AudioStream_Result stopResult = OH_AudioRenderer_Stop(renderer);
    stopSucceeded = (stopResult == AUDIOSTREAM_SUCCESS);
    if (!stopSucceeded) {
      LOGF(LOG_WARN, "%{public}s AudioRenderer Stop failed: %{public}d, attempting Release anyway",
           kAudioChainPrefix, static_cast<int>(stopResult));
    }
  }

  {
    std::unique_lock<std::mutex> lock(callback_mutex_);
    callback_cond_.wait_for(lock, std::chrono::seconds(2),
                             [this]() { return active_callbacks_ == 0; }); // Audit T3-F5: bounded wait, avoid indefinite hang
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    is_playing_ = false;
    resume_on_interrupt_ = false;

    // Phase 3.3+ - 清理音频工作组
    if (workgroup_) {
      if (workgroup_token_ > 0) {
        OH_AudioWorkgroup_RemoveThread(workgroup_, workgroup_token_);
        workgroup_token_ = 0;
        LOGF(LOG_INFO, "%{public}s Audio workgroup thread removed",
             kAudioChainPrefix);
      }

      if (resource_manager_) {
        OH_AudioResourceManager_ReleaseWorkgroup(resource_manager_, workgroup_);
        LOGF(LOG_INFO, "%{public}s Audio workgroup released",
             kAudioChainPrefix);
      }

      workgroup_ = nullptr;
    }

    resource_manager_ = nullptr;

    // 释放渲染器
    if (renderer_) {
      OH_AudioRenderer_Release(renderer_);
      renderer_ = nullptr;
    }

    // 销毁构造器
    if (builder_) {
      OH_AudioStreamBuilder_Destroy(builder_);
      builder_ = nullptr;
    }
  }
  pending_interrupt_pause_.store(false, std::memory_order_release);
  pending_interrupt_resume_.store(false, std::memory_order_release);
  pending_interrupt_stop_.store(false, std::memory_order_release);

  ring_buffer_ = nullptr;
  running_ = nullptr;

  // 注意:不再把 shutting_down_ 重置为 false。Cleanup 是单次最终态,
  // 残留 OHAudio 回调必须通过 shutting_down_ == true 检查拦截,
  // 避免回调访问已置 nullptr 的 ring_buffer_。
}

} // namespace libretro
