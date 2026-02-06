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

#ifndef AUDIO_PLAYER_H
#define AUDIO_PLAYER_H

#include "ring_buffer.h"
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>
#include <ohaudio/native_audio_resource_manager.h>  // Phase 3.3+ - 音频工作组
#include <chrono>
#include <cstdint>
#include <atomic>

namespace libretro {

/**
 * @brief OHAudio 音频播放器
 * 
 * 封装鸿蒙 OHAudio API,提供简单的音频播放接口
 * 
 * 特性:
 * - 低时延模式 (AUDIOSTREAM_LATENCY_MODE_FAST)
 * - 游戏音效优化 (AUDIOSTREAM_USAGE_GAME)
 * - 自动从环形缓冲区读取数据
 * - 支持播放控制 (启动/暂停/停止)
 * 
 * 基于官方文档:
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-ohaudio-for-playback
 */
class AudioPlayer {
public:
    /**
     * @brief 构造函数
     */
    AudioPlayer();
    
    /**
     * @brief 析构函数
     */
    ~AudioPlayer();
    
    /**
     * @brief 初始化音频播放器
     * @param sample_rate 采样率 (Hz), 推荐 48000
     * @param channel_count 声道数, 2 = 立体声
     * @param ring_buffer 环形缓冲区指针 (必须在播放器生命周期内有效)
     * @return true 初始化成功, false 失败
     */
    bool Initialize(
        int32_t sample_rate,
        int32_t channel_count,
        RingBuffer* ring_buffer,
        const std::atomic<bool>* running
    );
    
    /**
     * @brief 启动音频播放
     * @return true 启动成功, false 失败
     */
    bool Start();
    
    /**
     * @brief 暂停音频播放
     * @return true 暂停成功, false 失败
     */
    bool Pause();
    
    /**
     * @brief 停止音频播放
     * @return true 停止成功, false 失败
     */
    bool Stop();
    
    /**
     * @brief 检查是否正在播放
     * @return true 正在播放
     */
    bool IsPlaying() const;
    
    /**
     * @brief 获取采样率
     * @return 采样率 (Hz)
     */
    int32_t GetSampleRate() const { return sample_rate_; }
    
    /**
     * @brief 获取声道数
     * @return 声道数
     */
    int32_t GetChannelCount() const { return channel_count_; }

private:
  /**
   * @brief OHAudio 写入数据回调
     * 
     * 由 OHAudio 在音频线程中调用,从环形缓冲区读取数据
     * 
     * @param renderer 音频渲染器
     * @param userData 用户数据 (AudioPlayer 指针)
     * @param buffer 输出缓冲区
     * @param length 缓冲区长度 (字节)
     * @return 实际写入的字节数
     */
  static OH_AudioData_Callback_Result OnWriteDataCallback(
      OH_AudioRenderer* renderer,
      void* userData,
      void* audioData,
      int32_t audioDataSize
  );

  /**
   * @brief OHAudio 写入数据回调 (API 11 兼容，返回字节数)
   *
   * 由旧版 OHAudio 通过 callbacks.OH_AudioRenderer_OnWriteData 调用。
   * 当数据不足时，使用静音补齐，保证返回 audioDataSize。
   */
  static int32_t OnWriteDataLegacy(
      OH_AudioRenderer* renderer,
      void* userData,
      void* audioData,
      int32_t audioDataSize
  );
    
    /**
     * @brief OHAudio 音频中断事件回调
     * 
     * 处理音频焦点变化等事件
     * 
     * @param renderer 音频渲染器
     * @param userData 用户数据 (AudioPlayer 指针)
     * @param type 中断类型
     * @param hint 中断提示
     * @return 0 成功
     */
    static int32_t OnInterruptEvent(
        OH_AudioRenderer* renderer,
        void* userData,
        OH_AudioInterrupt_ForceType type,
        OH_AudioInterrupt_Hint hint
    );
    
    /**
     * @brief 清理资源
     */
    void Cleanup();
    
    OH_AudioStreamBuilder* builder_ = nullptr;  // 音频流构造器
    OH_AudioRenderer* renderer_ = nullptr;      // 音频渲染器
    RingBuffer* ring_buffer_ = nullptr; // 环形缓冲区 (不拥有)
    const std::atomic<bool>* running_ = nullptr; // 运行状态 (不拥有)
    
    // Phase 3.3+ - 音频工作组 (官方推荐优化)
    OH_AudioResourceManager* resource_manager_ = nullptr;  // 资源管理器
    OH_AudioWorkgroup* workgroup_ = nullptr;               // 音频工作组
    int32_t workgroup_token_ = 0;                          // 工作组令牌
    std::atomic<bool> workgroup_disabled_{false};          // 工作组禁用开关
    
    int32_t sample_rate_ = 48000;               // 采样率
    int32_t channel_count_ = 2;                 // 声道数
    bool is_playing_ = false;                   // 播放状态
    bool resume_on_interrupt_ = false;          // 中断恢复标志
    
    // 日志节流计数器（从 static 移为成员变量，避免多线程数据竞争）
    mutable std::chrono::steady_clock::time_point callback_last_time_{};
    mutable int callback_log_count_ = 0;
    mutable int callback_jitter_log_count_ = 0;
    mutable int callback_diag_log_count_ = 0;
    mutable int callback_underrun_log_count_ = 0;
    mutable int callback_cost_log_count_ = 0;
    mutable int callback_invalid_log_count_ = 0;
    mutable int legacy_log_count_ = 0;
    mutable int legacy_cb11_log_count_ = 0;
    mutable int legacy_diag_log_count_ = 0;
    
    // 禁止拷贝和赋值
    AudioPlayer(const AudioPlayer&) = delete;
    AudioPlayer& operator=(const AudioPlayer&) = delete;
};

} // namespace libretro

#endif // AUDIO_PLAYER_H
