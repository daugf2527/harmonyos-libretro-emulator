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

#include "audio_resampler.h"
#include <cmath>

namespace libretro {

static inline float catmull_rom(float y0, float y1, float y2, float y3,
                                float t) {
  // 经典 4 点 Catmull-Rom（三次 Hermite）插值公式
  float a0 = -0.5f * y0 + 1.5f * y1 - 1.5f * y2 + 0.5f * y3;
  float a1 = y0 - 2.5f * y1 + 2.0f * y2 - 0.5f * y3;
  float a2 = -0.5f * y0 + 0.5f * y2;
  float a3 = y1;
  return ((a0 * t + a1) * t + a2) * t + a3;
}

AudioResampler::AudioResampler() {}

void AudioResampler::Init(int32_t in_rate, int32_t out_rate) {
  in_rate_ = in_rate > 0 ? in_rate : 48000;
  out_rate_ = out_rate > 0 ? out_rate : 48000;
  base_ratio_ = static_cast<double>(out_rate_) / static_cast<double>(in_rate_);
  current_ratio_ = base_ratio_;
  phase_ = 0.0;
  history_init_ = false;
}

void AudioResampler::UpdateRatio(double skew) {
  // 限幅以防骤变（上层仍应控制范围）
  if (skew < kMinSkewLimit)
    skew = kMinSkewLimit;
  if (skew > kMaxSkewLimit)
    skew = kMaxSkewLimit;
  current_ratio_ = base_ratio_ * skew;
}

void AudioResampler::Reset() {
  phase_ = 0.0;
  history_init_ = false;
}

static inline int16_t fetch_channel(const int16_t *in, size_t in_frames,
                                    const int16_t hist[4], int idx,
                                    bool left) {
  if (idx < 0) {
    // 使用历史样本：idx=-1 -> hist[3], -2->hist[2], -3->hist[1], -4->hist[0]
    int hpos = 4 + idx; // idx=-1 => 3, idx=-4 => 0
    if (hpos < 0)
      hpos = 0;
    if (hpos > 3)
      hpos = 3;
    return hist[hpos];
  }
  if (static_cast<size_t>(idx) >= in_frames) {
    // 边界：重复最后一个样本
    if (in_frames == 0)
      return 0;
    size_t last = (in_frames - 1) * 2;
    return in[left ? last : (last + 1)];
  }
  size_t base = static_cast<size_t>(idx) * 2;
  return in[left ? base : (base + 1)];
}

size_t AudioResampler::Resample(const int16_t *in, size_t in_frames,
                                int16_t *out) {
  if (!in || !out || in_frames == 0 || current_ratio_ <= 0.0)
    return 0;

  if (!history_init_ && in_frames >= 1) {
    int16_t l0 = in[0];
    int16_t r0 = in[1];
    hist_l_[0] = hist_l_[1] = hist_l_[2] = hist_l_[3] = l0;
    hist_r_[0] = hist_r_[1] = hist_r_[2] = hist_r_[3] = r0;
    history_init_ = true;
  }

  const double step = 1.0 / current_ratio_;
  double pos = phase_;
  size_t out_frames = 0;

  // 生成直到耗尽当前输入（允许使用边界样本）
  while (pos < static_cast<double>(in_frames)) {
    int i = static_cast<int>(std::floor(pos));
    float t = static_cast<float>(pos - static_cast<double>(i));

    // 左右声道各做 4 点插值
    float l0 = static_cast<float>(fetch_channel(in, in_frames, hist_l_, i - 1, true));
    float l1 = static_cast<float>(fetch_channel(in, in_frames, hist_l_, i, true));
    float l2 = static_cast<float>(fetch_channel(in, in_frames, hist_l_, i + 1, true));
    float l3 = static_cast<float>(fetch_channel(in, in_frames, hist_l_, i + 2, true));

    float r0 = static_cast<float>(fetch_channel(in, in_frames, hist_r_, i - 1, false));
    float r1 = static_cast<float>(fetch_channel(in, in_frames, hist_r_, i, false));
    float r2 = static_cast<float>(fetch_channel(in, in_frames, hist_r_, i + 1, false));
    float r3 = static_cast<float>(fetch_channel(in, in_frames, hist_r_, i + 2, false));

    float lf = catmull_rom(l0, l1, l2, l3, t);
    float rf = catmull_rom(r0, r1, r2, r3, t);

    // 写回并限幅
    out[out_frames * 2] = Clamp16(static_cast<int>(std::lround(lf)));
    out[out_frames * 2 + 1] = Clamp16(static_cast<int>(std::lround(rf)));
    out_frames++;
    pos += step;
  }

  // 更新 phase：下批次从新输入的起点处继续
  phase_ = pos - static_cast<double>(in_frames);
  if (phase_ < 0.0)
    phase_ = 0.0; // 数值稳定性保护

  // 更新历史样本为本批次尾部 4 个样本
  for (int k = 0; k < 4; ++k) {
    int idx = static_cast<int>(in_frames) - 4 + k;
    if (idx < 0)
      idx = 0;
    size_t base = static_cast<size_t>(idx) * 2;
    hist_l_[k] = in[base];
    hist_r_[k] = in[base + 1];
  }

  return out_frames;
}

} // namespace libretro
