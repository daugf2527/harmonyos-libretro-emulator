#pragma once
#include <algorithm>
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
    const int64_t period_us = EffectivePeriodUs();
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

  // 平台门控:是否允许末尾忙等自旋(busy-spin)收窄抖动。
  // 真机(有 RT 调度、多大核)允许 → 末尾极短自旋换低 jitter;
  // 模拟器(无 RT、少 vCPU、软件 GPU 已占满核)禁止 → 纯 sleep 到 deadline,
  // 不用 PAUSE 烧满一个虚拟核去抢 GameLoop / 软件 GL 的核。
  // 外网实证:PAUSE 忙等填毫秒级帧节拍在 VM/模拟器是反模式(vCPU 100%、帧不均、
  // 加剧 vCPU stacking);毫秒级等待应 sleep/yield 让 guest 正确让出 pCPU。
  // 由 RenderThread 据 OH_QoS_SetThreadQoS 成败注入(见 render_thread.cpp)。
  void SetBusyWaitAllowed(bool allowed) {
    busy_wait_allowed_.store(allowed, std::memory_order_relaxed);
  }

  // 在丢帧或正常帧结束时调用，确保帧时间稳定
  void EndFrame() {
    if (!frame_started_) {
      return;
    }
    const int64_t period_us = EffectivePeriodUs();
    auto target_end = next_deadline_;
    auto now = std::chrono::steady_clock::now();

    if (now >= target_end) {
      return;
    }

    auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        target_end - now).count();

    if (!busy_wait_allowed_.load(std::memory_order_relaxed)) {
      // 模拟器路径:纯 sleep 到 deadline,绝不忙等烧核(让核给 GameLoop/软件 GL)。
      // sleep 精度差导致的轻微帧偏晚,远优于忙等抢核引发的 GameLoop 换出卡顿。
      std::this_thread::sleep_for(std::chrono::microseconds(remaining));
      return;
    }

    // 真机路径:sleep 大部分 + 末尾极短自旋(hybrid)收窄抖动。
    const int64_t spin_reserve_us =
        std::max<int64_t>(50, std::min<int64_t>(300, period_us / 20));
    if (remaining > spin_reserve_us) {
      std::this_thread::sleep_for(
          std::chrono::microseconds(remaining - spin_reserve_us));
    }

    while (std::chrono::steady_clock::now() < target_end) {
#if defined(__aarch64__) || defined(__arm__)
      asm volatile("yield");
#elif defined(__x86_64__) || defined(__i386__)
      __builtin_ia32_pause();
#endif
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
  // [2026-06-07] 撤销模拟器渲染降频 30fps(原 commit 14b4759)。
  // 经用户实测权衡后决定恢复 60fps 显示:降频虽缓解模拟器音频 underrun,但牺牲了
  // 输入→画面跟手度;且音频 underrun 本质是当前模拟器缺实时调度(workgroup/QoS)
  // 的平台问题,真机/5.0.5 不存在(真机本就 60fps)。故渲染节拍统一按 target fps,
  // 不再因模拟器(busy_wait_allowed_==false)封顶 30fps。如需回退降频见 git 14b4759。
  // 注:busy_wait_allowed_ 仍保留——它独立门控 EndFrame 的"纯 sleep vs 末尾自旋",
  // 模拟器不忙等烧核的策略不变,仅恢复 60fps 节拍。
  int64_t EffectivePeriodUs() const {
    return target_frame_time_us_.load();
  }

  std::chrono::steady_clock::time_point frame_start_;
  std::chrono::steady_clock::time_point next_deadline_;
  // [2026-06-08 D029] 改 atomic:SetTargetFps(Engine 线程)写这两 bool,
  // BeginFrame/EndFrame(RenderThread)读写 → 原 plain bool 跨线程 = data race(UB)。
  // 与 target_frame_time_us_ 已原子化对齐(此前漏了同函数顺带写的这两个)。
  std::atomic<bool> deadline_initialized_{false};
  std::atomic<bool> frame_started_{false};
  std::atomic<int64_t> target_frame_time_us_{16667};
  // 默认 true:保守保持真机 hybrid 自旋行为;模拟器(无 RT)由 RenderThread 显式置 false。
  std::atomic<bool> busy_wait_allowed_{true};
};

} // namespace libretro
