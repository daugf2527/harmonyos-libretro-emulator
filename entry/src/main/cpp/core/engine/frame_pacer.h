#pragma once
#include <atomic>
#include <chrono>
#include <thread>
#include <cstdint>

namespace libretro {

class FramePacer {
public:
  void BeginFrame() {
    const auto now = std::chrono::steady_clock::now();
    frame_start_ = now;
    frame_started_ = true;
    const int64_t period_us = target_frame_time_us_.load();
    if (!deadline_initialized_) {
      next_deadline_ = now;
      deadline_initialized_ = true;
    } else if (now > next_deadline_) {
      const auto delta_us =
          std::chrono::duration_cast<std::chrono::microseconds>(now -
                                                                next_deadline_)
              .count();
      const int64_t behind = (delta_us / period_us) + 1;
      next_deadline_ += std::chrono::microseconds(behind * period_us);
    }
    next_deadline_ += std::chrono::microseconds(period_us);
  }

  // 在丢帧或正常帧结束时调用，确保帧时间稳定
  void EndFrame() {
    if (!frame_started_) {
      return;
    }
    const int64_t period_us = target_frame_time_us_.load();
    auto target_end = next_deadline_;
    auto now = std::chrono::steady_clock::now();
    
    if (now >= target_end) {
      return;
    }
    
    auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        target_end - now).count();
    
    const int64_t spin_reserve_us = period_us / 10;
    if (remaining > spin_reserve_us) {
      std::this_thread::sleep_for(
          std::chrono::microseconds(remaining - spin_reserve_us));
    }
    
    while (std::chrono::steady_clock::now() < target_end) {
    }
  }

  void SetTargetFps(double fps) {
    if (fps > 0.0) {
      target_frame_time_us_ = static_cast<int64_t>(1000000.0 / fps);
      deadline_initialized_ = false;
      frame_started_ = false;
    }
  }

  int64_t GetTargetFrameTimeUs() const {
    return target_frame_time_us_;
  }

private:
  std::chrono::steady_clock::time_point frame_start_;
  std::chrono::steady_clock::time_point next_deadline_;
  bool deadline_initialized_ = false;
  bool frame_started_ = false;
  std::atomic<int64_t> target_frame_time_us_{16667};
};

} // namespace libretro
