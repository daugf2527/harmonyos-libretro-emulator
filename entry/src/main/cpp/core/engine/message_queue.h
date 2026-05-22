#ifndef LIBRETRO_ENGINE_MESSAGE_QUEUE_H
#define LIBRETRO_ENGINE_MESSAGE_QUEUE_H

#include <condition_variable>
#include <mutex>
#include <queue>

namespace libretro {

/**
 * @brief 线程安全队列，用于跨线程传递指令。
 * 增加了 Close 语义，便于安全地关闭消费者线程。
 */
template <typename T> class ThreadSafeQueue {
public:
  ThreadSafeQueue() : closed_(false) {}

  /**
   * @brief 推送一个值到队列中。如果队列已关闭，则直接丢弃。
   */
  bool Push(T value) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) {
      return false;
    }
    queue_.push(std::move(value));
    cond_.notify_one();
    return true;
  }

  /**
   * @brief 推送并尝试合并。如果队尾元素满足条件，则用新值替换队尾元素。
   * 适用于高频事件（如 Resize），只保留最新值。
   *
   * **限制**:仅检查队尾元素。若同类消息已被其他类型消息"夹"在队列中部,
   * 此函数不会向前扫描合并,而是把新消息追加到队尾。对于持续高频推送
   * (如连续多个 Resize),实际效果良好;但若交替推送(Resize→Other→Resize)
   * 会保留中部旧 Resize。如需严格"仅留最新一条"语义,需改为全队列扫描替换。
   *
   * @param value 新消息
   * @param shouldReplace 判定函数：bool(const T& back, const T& incoming)
   */
  template <typename Predicate>
  bool PushCoalesce(T value, Predicate shouldReplace) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) {
      return false;
    }
    if (!queue_.empty() && shouldReplace(queue_.back(), value)) {
      queue_.back() = std::move(value);
      return true;
    }
    queue_.push(std::move(value));
    cond_.notify_one();
    return true;
  }

  /**
   * @brief 非阻塞弹出。如果队列为空，返回 false。
   */
  bool Pop(T &value) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (queue_.empty()) {
      return false;
    }
    value = std::move(queue_.front());
    queue_.pop();
    return true;
  }

  /**
   * @brief 阻塞弹出。直到队列中有值或被关闭。
   * @return 如果成功弹出值返回 true，如果队列关闭且为空返回 false。
   */
  bool WaitAndPop(T &value) {
    std::unique_lock<std::mutex> lock(mutex_);
    cond_.wait(lock, [this] { return closed_ || !queue_.empty(); });

    if (closed_ && queue_.empty()) {
      return false;
    }

    value = std::move(queue_.front());
    queue_.pop();
    return true;
  }

  /**
   * @brief 关闭队列。通知所有等待者，并拒绝后续的 Push。
   */
  void Close() {
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = true;
    cond_.notify_all();
  }

  /**
   * @brief 重新开放队列。用于在 Stop 后再次启动消费者线程。
   * 会清空残留消息以避免处理旧的 Stop 消息。
   */
  void Reopen() {
    std::lock_guard<std::mutex> lock(mutex_);
    // 清空残留消息（避免处理旧的 Stop 消息导致立即退出）
    while (!queue_.empty()) {
      queue_.pop();
    }
    closed_ = false;
    cond_.notify_all();
  }

  /**
   * @brief 检查队列是否为空。
   */
  bool Empty() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.empty();
  }

  /**
   * @brief 检查队列是否已关闭。
   */
  bool IsClosed() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return closed_;
  }

private:
  std::queue<T> queue_;
  mutable std::mutex mutex_;
  std::condition_variable cond_;
  bool closed_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_MESSAGE_QUEUE_H
