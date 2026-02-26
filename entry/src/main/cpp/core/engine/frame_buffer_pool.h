#ifndef LIBRETRO_ENGINE_FRAME_BUFFER_POOL_H
#define LIBRETRO_ENGINE_FRAME_BUFFER_POOL_H

#include <cstddef>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <vector>

namespace libretro {

class FrameBufferPool {
public:
  explicit FrameBufferPool(size_t maxSlots = 3);

  std::shared_ptr<std::vector<uint8_t>> Acquire(size_t bytes);
  void Clear();
  size_t CachedCount() const;

private:
  struct State {
    explicit State(size_t max) : maxSlots(max > 0 ? max : 1) {}

    mutable std::mutex mutex;
    size_t maxSlots;
    std::deque<std::unique_ptr<std::vector<uint8_t>>> cache;
  };

  std::shared_ptr<State> state_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_FRAME_BUFFER_POOL_H
