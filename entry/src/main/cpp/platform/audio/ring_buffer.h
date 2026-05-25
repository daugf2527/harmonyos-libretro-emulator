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

#ifndef RING_BUFFER_H
#define RING_BUFFER_H

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

namespace libretro {

/**
 * @brief 高性能无锁环形缓冲区 (SPSC)
 *
 * 针对音频场景优化：
 * - 单生产者 (Libretro Core -> ProcessAudio)
 * - 单消费者 (OHAudio Callback)
 * - 使用 C++11 std::atomic 实现无锁队列
 * - 支持阻塞等待 (Wait) 与 状态通知 (Running/Clear)
 *
 * 注意：单位统一为 Samples (采样点数)，不再隐式处理帧(Frames)与声道关系。
 * 例如：立体声 48kHz，1帧=2samples。
 */
class RingBuffer {
public:
  /**
   * @brief 构造函数
   * @param capacity_samples 缓冲区容量 (采样点数)
   *                         内部会自动向上取整到 2 的幂次
   */
  explicit RingBuffer(size_t capacity_samples);

  ~RingBuffer();

  /**
   * @brief 非阻塞写入
   * @param data 数据指针
   * @param samples 采样点数
   * @return true 写入成功 (全部写入), false 空间不足 (全部不写入)
   */
  bool Write(const int16_t *data, size_t samples);

  /**
   * @brief 阻塞写入
   * @param running 运行状态，为 false 时立即返回
   * @return true 写入成功, false 被中断或停止
   */
  bool WriteWait(const int16_t *data, size_t samples,
                 const std::atomic<bool> &running);

  /**
   * @brief 非阻塞读取
   * @param data 输出缓冲区
   * @param samples 期望读取的采样点数
   * @return 实际读取的采样点数
   */
  size_t Read(int16_t *data, size_t samples);

  /**
   * @brief 阻塞读取 (读取指定数量)
   * @return 实际读取的采样点数 (等于 samples，除非被中断)
   */
  size_t ReadWait(int16_t *data, size_t samples,
                  const std::atomic<bool> &running);

  size_t AvailableRead() const;
  size_t AvailableWrite() const;

  /**
   * @brief 清空缓冲区并唤醒所有等待线程
   */
  void Clear();

  // --- 统计与监控 ---
  float GetUsage() const;
  void ResetStats();
  void GetStats(size_t &underruns, size_t &overruns) const;

private:
  // 内部辅助
  static size_t NextPowerOf2(size_t v);
  void WriteDataInternal(const int16_t *data, size_t count, size_t head);
  void ReadDataInternal(int16_t *data, size_t count, size_t tail);

  // 核心数据
  const size_t capacity_;
  const size_t mask_;
  std::unique_ptr<int16_t[]> buffer_;

  // 缓存行对齐的原子变量，避免伪共享 (False Sharing)
  struct alignas(64) AlignedAtomic {
    std::atomic<size_t> v;
  };
  AlignedAtomic head_; // 写入位置
  AlignedAtomic tail_; // 读取位置

  // 等待状态优化
  std::atomic<bool> reader_waiting_{false};
  std::atomic<bool> writer_waiting_{false};

  // 统计
  std::atomic<size_t> underrun_count_{0};
  std::atomic<size_t> overrun_count_{0};

  // 用于阻塞等待的锁与条件变量
  // 注意：这把锁仅用于 wait/notify，不保护数据读写
  mutable std::mutex mutex_;
  std::condition_variable cv_not_empty_;
  std::condition_variable cv_not_full_;

  // 日志节流 — Audit T3-F6: atomic to avoid UB from concurrent producer/consumer access
  mutable std::atomic<size_t> write_wait_block_logs_{0};
  mutable std::atomic<size_t> write_wait_resume_logs_{0};
  mutable std::atomic<size_t> read_wait_block_logs_{0};
  mutable std::atomic<size_t> read_wait_resume_logs_{0};

  RingBuffer(const RingBuffer &) = delete;
  RingBuffer &operator=(const RingBuffer &) = delete;
};

} // namespace libretro

#endif // RING_BUFFER_H
