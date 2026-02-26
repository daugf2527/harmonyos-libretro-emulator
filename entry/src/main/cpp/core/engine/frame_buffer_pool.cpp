#include "frame_buffer_pool.h"

namespace libretro {

FrameBufferPool::FrameBufferPool(size_t maxSlots)
    : state_(std::make_shared<State>(maxSlots)) {}

std::shared_ptr<std::vector<uint8_t>> FrameBufferPool::Acquire(size_t bytes) {
  auto state = state_;
  if (!state) {
    return std::make_shared<std::vector<uint8_t>>(bytes);
  }

  std::unique_ptr<std::vector<uint8_t>> buffer;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->cache.empty()) {
      buffer = std::move(state->cache.front());
      state->cache.pop_front();
    }
  }

  if (!buffer) {
    buffer = std::make_unique<std::vector<uint8_t>>();
  }

  if (buffer->size() != bytes) {
    buffer->resize(bytes);
  }

  std::weak_ptr<State> weakState(state);
  return std::shared_ptr<std::vector<uint8_t>>(
      buffer.release(), [weakState](std::vector<uint8_t> *raw) {
        std::unique_ptr<std::vector<uint8_t>> holder(raw);
        if (!holder) {
          return;
        }
        auto sharedState = weakState.lock();
        if (!sharedState) {
          return;
        }
        std::lock_guard<std::mutex> lock(sharedState->mutex);
        if (sharedState->cache.size() >= sharedState->maxSlots) {
          return;
        }
        sharedState->cache.emplace_back(std::move(holder));
      });
}

void FrameBufferPool::Clear() {
  auto state = state_;
  if (!state) {
    return;
  }
  std::lock_guard<std::mutex> lock(state->mutex);
  state->cache.clear();
}

size_t FrameBufferPool::CachedCount() const {
  auto state = state_;
  if (!state) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(state->mutex);
  return state->cache.size();
}

} // namespace libretro
