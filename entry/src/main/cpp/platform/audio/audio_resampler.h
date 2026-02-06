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

#ifndef AUDIO_RESAMPLER_H
#define AUDIO_RESAMPLER_H

#include <cstddef>
#include <cstdint>

namespace libretro {

/**
 * AudioResampler: 轻量级 4 点 Hermite（Catmull-Rom）插值重采样，
 * 面向实时音频，支持流式状态与动态比率（DRC skew）。
 * 输入/输出均为立体声交错格式的 int16 PCM。
 */
class AudioResampler {
public:
  AudioResampler();

  /**
   * 初始化重采样器
   * @param in_rate  输入采样率（Libretro core）
   * @param out_rate 输出采样率（OHAudio，固定 48000）
   */
  void Init(int32_t in_rate, int32_t out_rate);

  /**
   * 更新 DRC 偏移（skew），范围建议 0.995 - 1.005
   * current_ratio = base_ratio * skew
   */
  void UpdateRatio(double skew);

  /** 获取当前输出/输入的比率 */
  double GetCurrentRatio() const { return current_ratio_; }
  double GetRatio() const { return current_ratio_; }

  /**
   * 进行一次批量重采样
   * @param in 输入数据（frames 帧，立体声交错，长度=frames*2）
   * @param in_frames 输入帧数
   * @param out 输出缓冲区指针（长度至少为 预估帧数*2）
   * @return 实际输出帧数
   */
  size_t Resample(const int16_t *in, size_t in_frames, int16_t *out);

  /** 重置内部状态（保留采样率配置） */
  void Reset();

private:
  // Safety limits for skew (ratio adjustment)
  static constexpr double kMinSkewLimit = 0.99;
  static constexpr double kMaxSkewLimit = 1.01;

  // 采样率与比率
  int32_t in_rate_ = 48000;
  int32_t out_rate_ = 48000;
  double base_ratio_ = 1.0;    // out_rate / in_rate
  double current_ratio_ = 1.0; // base_ratio * skew

  // 流式位置：以输入帧为单位的连续位置
  double phase_ = 0.0; // 下次调用起始位置（相对当前批输入起点）

  // 边界处理：保存上一批尾部的 4 个样本（左右声道各 4）
  int16_t hist_l_[4] = {0, 0, 0, 0};
  int16_t hist_r_[4] = {0, 0, 0, 0};
  bool history_init_ = false;

  // 工具函数
  static inline int16_t Clamp16(int x) {
    if (x > 32767)
      return 32767;
    if (x < -32768)
      return -32768;
    return static_cast<int16_t>(x);
  }
};

} // namespace libretro

#endif // AUDIO_RESAMPLER_H
