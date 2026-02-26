#ifndef LIBRETRO_ENGINE_BOUNDED_LATEST_FRAME_QUEUE_H
#define LIBRETRO_ENGINE_BOUNDED_LATEST_FRAME_QUEUE_H

#include "video_frame_packet.h"
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>

namespace libretro {

class BoundedLatestFrameQueue {
public:
  struct Stats {
    uint64_t pushed = 0;
    uint64_t popped = 0;
    uint64_t droppedOldest = 0;
    uint64_t droppedStaleOnPop = 0;
    size_t depthMax = 0;
  };

  explicit BoundedLatestFrameQueue(size_t capacity = 2)
      : capacity_(capacity > 0 ? capacity : 1) {}

  void SetCapacity(size_t capacity) {
    std::lock_guard<std::mutex> lock(mutex_);
    capacity_ = capacity > 0 ? capacity : 1;
    while (queue_.size() > capacity_) {
      queue_.pop_front();
      stats_.droppedOldest++;
    }
  }

  bool Push(VideoFramePacket &&packet) {
    std::lock_guard<std::mutex> lock(mutex_);
    stats_.pushed++;
    if (queue_.size() >= capacity_) {
      queue_.pop_front();
      stats_.droppedOldest++;
    }
    queue_.emplace_back(std::move(packet));
    if (queue_.size() > stats_.depthMax) {
      stats_.depthMax = queue_.size();
    }
    cond_.notify_one();
    return true;
  }

  bool PopLatest(VideoFramePacket &packet) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (queue_.empty()) {
      return false;
    }

    if (queue_.size() > 1) {
      stats_.droppedStaleOnPop += static_cast<uint64_t>(queue_.size() - 1);
    }

    packet = std::move(queue_.back());
    queue_.clear();
    stats_.popped++;
    return true;
  }

  void Clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    queue_.clear();
  }

  size_t Size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.size();
  }

  Stats GetStats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return stats_;
  }

  void ResetStats() {
    std::lock_guard<std::mutex> lock(mutex_);
    stats_ = Stats{};
  }

private:
  mutable std::mutex mutex_;
  std::condition_variable cond_;
  std::deque<VideoFramePacket> queue_;
  size_t capacity_ = 2;
  Stats stats_{};
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_BOUNDED_LATEST_FRAME_QUEUE_H
