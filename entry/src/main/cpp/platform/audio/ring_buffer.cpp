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

#include "ring_buffer.h"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "RingBuffer"
#undef LOG_FLOW
#define LOG_FLOW "Audio"
#include "common/log_prefix.h"

namespace libretro {

namespace {
constexpr const char *kAudioChainPrefix = "[AUD][CHAIN]";
}

size_t RingBuffer::NextPowerOf2(size_t v) {
  if (v == 0)
    return 1;
  // 检查是否溢出或过大
  if (v > (1ULL << (sizeof(size_t) * 8 - 1))) {
      // 溢出或超过最大允许值，回退到最大可能值，或者直接抛出异常/返回安全值
      // 考虑到 RingBuffer 必须是 2 的幂次，如果溢出，则取系统能支持的最大 2 的幂次
      return 1ULL << (sizeof(size_t) * 8 - 1);
  }

  v--;
  v |= v >> 1;
  v |= v >> 2;
  v |= v >> 4;
  v |= v >> 8;
  v |= v >> 16;
  if (sizeof(size_t) > 4) {
    v |= v >> 32;
  }
  return v + 1;
}

RingBuffer::RingBuffer(size_t capacity_samples)
    : capacity_(NextPowerOf2(std::max<size_t>(capacity_samples, 2))),
      mask_(capacity_ - 1), buffer_(new int16_t[capacity_]) {
  head_.v.store(0);
  tail_.v.store(0);
  underrun_count_.store(0);
  overrun_count_.store(0);
  reader_waiting_.store(false);
  writer_waiting_.store(false);
  LOGF(LOG_INFO,
       "%{public}s RingBuffer created: capacity=%{public}zu samples "
       "(requested %{public}zu)",
       kAudioChainPrefix, capacity_, capacity_samples);
}

RingBuffer::~RingBuffer() {
  Clear(); // 确保唤醒所有等待者
  LOGF(LOG_INFO,
       "%{public}s RingBuffer destroyed: underruns=%{public}zu, "
       "overruns=%{public}zu",
       kAudioChainPrefix, underrun_count_.load(), overrun_count_.load());
}

void RingBuffer::WriteDataInternal(const int16_t *data, size_t count,
                                   size_t head) {
  const size_t mask = mask_;
  size_t offset = head & mask;
  size_t to_end = capacity_ - offset;
  size_t chunk1 = std::min(count, to_end);

  memcpy(&buffer_[offset], data, chunk1 * sizeof(int16_t));
  if (chunk1 < count) {
    memcpy(&buffer_[0], data + chunk1, (count - chunk1) * sizeof(int16_t));
  }
}

void RingBuffer::ReadDataInternal(int16_t *data, size_t count, size_t tail) {
  const size_t mask = mask_;
  size_t offset = tail & mask;
  size_t to_end = capacity_ - offset;
  size_t chunk1 = std::min(count, to_end);

  memcpy(data, &buffer_[offset], chunk1 * sizeof(int16_t));
  if (chunk1 < count) {
    memcpy(data + chunk1, &buffer_[0], (count - chunk1) * sizeof(int16_t));
  }
}

bool RingBuffer::Write(const int16_t *data, size_t samples) {
  if (!data || samples == 0)
    return false;

  const size_t head = head_.v.load(std::memory_order_relaxed);
  const size_t tail = tail_.v.load(std::memory_order_acquire);

  const size_t size = head - tail;
  const size_t available = capacity_ - size;

  if (samples > available) {
    const size_t overrun =
        overrun_count_.fetch_add(1, std::memory_order_relaxed) + 1;
    if (overrun <= 3 || (overrun % 250) == 0) {
      LOGF(LOG_WARN,
           "%{public}s RingBuffer overrun: need=%{public}zu, free=%{public}zu, "
           "size=%{public}zu, cap=%{public}zu",
           kAudioChainPrefix, samples, available, size, capacity_);
    }
    return false;
  }

  WriteDataInternal(data, samples, head);

  head_.v.store(head + samples, std::memory_order_release);
  // C++11 memory fence not strictly needed with release store above, but good for clarity
  // std::atomic_thread_fence(std::memory_order_seq_cst);

  if (reader_waiting_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(mutex_);
    cv_not_empty_.notify_one();
  }

  return true;
}

bool RingBuffer::WriteWait(const int16_t *data, size_t samples,
                           const std::atomic<bool> &running) {
  if (!data || samples == 0)
    return false;

  const size_t head = head_.v.load(std::memory_order_relaxed);
  const size_t tail = tail_.v.load(std::memory_order_acquire);

  if (samples <= capacity_ - (head - tail)) {
    // 快速路径：空间足够，直接写入
    WriteDataInternal(data, samples, head);
    head_.v.store(head + samples, std::memory_order_release);

    if (reader_waiting_.load(std::memory_order_relaxed)) {
      std::lock_guard<std::mutex> lock(mutex_);
      cv_not_empty_.notify_one();
    }
    return true;
  }

  // 慢速路径：空间不足，阻塞等待
  std::unique_lock<std::mutex> lock(mutex_);
  writer_waiting_.store(true, std::memory_order_relaxed);

  // 日志记录阻塞
  if (write_wait_block_logs_ < 3 || (write_wait_block_logs_ % 250) == 0) {
      size_t free = capacity_ - (head - tail);
      LOGF(LOG_INFO,
           "%{public}s [WriteWait] blocking: need=%{public}zu, free=%{public}zu",
           kAudioChainPrefix, samples, free);
  }
  write_wait_block_logs_++;

  auto wait_start = std::chrono::steady_clock::now();
  
  // 等待条件：有足够空间 OR 停止运行
  // 注意：我们在 wait 中必须重新加载 atomic 变量
  cv_not_full_.wait(lock, [&]() {
    if (!running.load(std::memory_order_relaxed)) return true;
    const size_t curr_head = head_.v.load(std::memory_order_relaxed);
    const size_t curr_tail = tail_.v.load(std::memory_order_acquire);
    return samples <= capacity_ - (curr_head - curr_tail);
  });

  auto waited_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::steady_clock::now() - wait_start)
                       .count();

  if (!running.load(std::memory_order_relaxed)) {
    writer_waiting_.store(false, std::memory_order_relaxed);
    if (waited_ms > 0) {
        LOGF(LOG_INFO,
             "%{public}s [WriteWait] aborted by stop after %{public}lld ms",
             kAudioChainPrefix, (long long)waited_ms);
    }
    return false;
  }

  // 醒来后再次检查并写入
  const size_t curr_head = head_.v.load(std::memory_order_relaxed);
  // const size_t curr_tail = tail_.v.load(std::memory_order_acquire); // 已经在 wait predicate 中检查过

  WriteDataInternal(data, samples, curr_head);
  head_.v.store(curr_head + samples, std::memory_order_release);
  writer_waiting_.store(false, std::memory_order_relaxed);
  
  lock.unlock(); // 尽早释放锁

  if (reader_waiting_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> notify_lock(mutex_);
    cv_not_empty_.notify_one();
  }

  if (waited_ms > 0) {
    if (write_wait_resume_logs_ < 3 || (write_wait_resume_logs_ % 250) == 0) {
      LOGF(LOG_INFO,
           "%{public}s [WriteWait] resumed after %{public}lld ms",
           kAudioChainPrefix, (long long)waited_ms);
    }
    write_wait_resume_logs_++;
  }

  return true;
}

size_t RingBuffer::Read(int16_t *data, size_t samples) {
  if (!data || samples == 0)
    return 0;

  const size_t tail = tail_.v.load(std::memory_order_relaxed);
  const size_t head = head_.v.load(std::memory_order_acquire);

  const size_t size = head - tail;
  const size_t to_read = std::min(samples, size);

  if (to_read == 0)
    return 0;

  ReadDataInternal(data, to_read, tail);

  tail_.v.store(tail + to_read, std::memory_order_release);

  if (writer_waiting_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> lock(mutex_);
    cv_not_full_.notify_one();
  }

  if (to_read < samples) {
    const size_t underrun =
        underrun_count_.fetch_add(1, std::memory_order_relaxed) + 1;
    if (underrun <= 3 || (underrun % 250) == 0) {
      LOGF(LOG_WARN,
           "%{public}s RingBuffer underrun: need=%{public}zu, got=%{public}zu, "
           "size=%{public}zu, cap=%{public}zu",
           kAudioChainPrefix, samples, to_read, size, capacity_);
    }
  }

  return to_read;
}

size_t RingBuffer::ReadWait(int16_t *data, size_t samples,
                            const std::atomic<bool> &running) {
  if (!data || samples == 0)
    return 0;

  const size_t tail = tail_.v.load(std::memory_order_relaxed);
  const size_t head = head_.v.load(std::memory_order_acquire);

  if (head - tail >= samples) {
    // 快速路径
    ReadDataInternal(data, samples, tail);
    tail_.v.store(tail + samples, std::memory_order_release);

    if (writer_waiting_.load(std::memory_order_relaxed)) {
      std::lock_guard<std::mutex> lock(mutex_);
      cv_not_full_.notify_one();
    }
    return samples;
  }

  // 慢速路径
  std::unique_lock<std::mutex> lock(mutex_);
  reader_waiting_.store(true, std::memory_order_relaxed);

  // 日志
  if (read_wait_block_logs_ < 3 || (read_wait_block_logs_ % 250) == 0) {
      size_t avail = head - tail;
      LOGF(LOG_INFO,
           "%{public}s [ReadWait] blocking: need=%{public}zu, avail=%{public}zu",
           kAudioChainPrefix, samples, avail);
  }
  read_wait_block_logs_++;

  auto wait_start = std::chrono::steady_clock::now();

  cv_not_empty_.wait(lock, [&]() {
    if (!running.load(std::memory_order_relaxed)) return true;
    const size_t curr_tail = tail_.v.load(std::memory_order_relaxed);
    const size_t curr_head = head_.v.load(std::memory_order_acquire);
    return curr_head - curr_tail >= samples;
  });

  auto waited_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::steady_clock::now() - wait_start)
                       .count();

  if (!running.load(std::memory_order_relaxed)) {
    reader_waiting_.store(false, std::memory_order_relaxed);
    if (waited_ms > 0) {
        LOGF(LOG_INFO,
             "%{public}s [ReadWait] aborted by stop after %{public}lld ms",
             kAudioChainPrefix, (long long)waited_ms);
    }
    return 0;
  }

  const size_t curr_tail = tail_.v.load(std::memory_order_relaxed);
  // const size_t curr_head = head_.v.load(std::memory_order_acquire);

  ReadDataInternal(data, samples, curr_tail);
  tail_.v.store(curr_tail + samples, std::memory_order_release);
  reader_waiting_.store(false, std::memory_order_relaxed);

  lock.unlock();

  if (writer_waiting_.load(std::memory_order_relaxed)) {
    std::lock_guard<std::mutex> notify_lock(mutex_);
    cv_not_full_.notify_one();
  }

  if (waited_ms > 0) {
    if (read_wait_resume_logs_ < 3 || (read_wait_resume_logs_ % 250) == 0) {
      LOGF(LOG_INFO,
           "%{public}s [ReadWait] resumed after %{public}lld ms",
           kAudioChainPrefix, (long long)waited_ms);
    }
    read_wait_resume_logs_++;
  }

  return samples;
}

size_t RingBuffer::AvailableRead() const {
  const size_t tail = tail_.v.load(std::memory_order_relaxed);
  const size_t head = head_.v.load(std::memory_order_acquire);
  return head - tail;
}

size_t RingBuffer::AvailableWrite() const {
  const size_t tail = tail_.v.load(std::memory_order_acquire);
  const size_t head = head_.v.load(std::memory_order_relaxed);
  return capacity_ - (head - tail);
}

void RingBuffer::Clear() {
  // 1. 重置指针
  head_.v.store(0, std::memory_order_relaxed);
  tail_.v.store(0, std::memory_order_relaxed);
  
  // 2. 唤醒所有等待者 (重要!)
  // 因为 Clear 通常意味着重置或停止，等待中的线程应该被唤醒并重新检查条件
  {
      std::lock_guard<std::mutex> lock(mutex_);
      // 注意：这里的 notify 不一定能让 wait 返回 true (因为 head/tail 重置了可能还是不满/不空)
      // 但配合 running=false 的外部状态，可以确保线程退出
      cv_not_empty_.notify_all();
      cv_not_full_.notify_all();
  }
  
  LOGF(LOG_INFO, "%{public}s RingBuffer cleared and waiters notified",
       kAudioChainPrefix);
}

float RingBuffer::GetUsage() const {
  if (capacity_ == 0) return 0.0f;
  return static_cast<float>(AvailableRead()) / static_cast<float>(capacity_);
}

void RingBuffer::ResetStats() {
  underrun_count_.store(0, std::memory_order_relaxed);
  overrun_count_.store(0, std::memory_order_relaxed);
  LOGF(LOG_INFO, "%{public}s RingBuffer stats reset", kAudioChainPrefix);
}

void RingBuffer::GetStats(size_t &underruns, size_t &overruns) const {
  underruns = underrun_count_.load(std::memory_order_relaxed);
  overruns = overrun_count_.load(std::memory_order_relaxed);
}

} // namespace libretro
