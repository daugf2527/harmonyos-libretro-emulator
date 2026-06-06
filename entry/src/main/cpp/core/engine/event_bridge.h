#ifndef LIBRETRO_ENGINE_EVENT_BRIDGE_H
#define LIBRETRO_ENGINE_EVENT_BRIDGE_H

#include <chrono>
#include <mutex>
#include <napi/native_api.h>
#include <string>
#include <unordered_map>

namespace libretro {

/**
 * @brief EventBridge 用于在非 JS 线程安全地调用 ArkTS 回调。
 * 封装了 napi_threadsafe_function (TSFN) 的生命周期与限流逻辑。
 */
class EventBridge {
public:
  EventBridge() = default;
  ~EventBridge();

  /**
   * @brief 初始化 TSFN（在 JS 线程调用）
   */
  bool Initialize(napi_env env, napi_value callback);

  /**
   * @brief 发送事件（游戏线程调用）
   * @param event 事件枚举
   * @param payload JSON 字符串负载
   * @param force 设为 true 则绕过限流（如核心崩溃、重要状态变更）
   */
  enum class EventType {
    FPS_UPDATE,
    AUDIO_STATUS,
    GEOMETRY_UPDATE,
    OPTIONS_UPDATE,
    PIXEL_FORMAT_UPDATE,
    CORE_MESSAGE,
    CORE_CRASH,
    ENGINE_STATE,
    DISK_CONTROL,
    RUMBLE,
    SENSOR_STATE,
    UNKNOWN
  };

  void Emit(EventType event, const std::string &payload, bool force = false);
  
  // Deprecated: String based emit
  void Emit(const std::string &event, const std::string &payload, bool force = false);

  /**
   * @brief 关闭并释放 TSFN
   */
  void Release();

private:
  static void CallJsHandler(napi_env env, napi_value js_cb, void *context,
                            void *data);

  struct EventData {
    std::string event;
    std::string payload;
  };

  napi_threadsafe_function tsfn_ = nullptr;
  std::mutex mutex_;

  // 限流/合并：按事件类型记录最后发送时间
  // Use Enum as key for faster lookup
  std::unordered_map<int, std::chrono::steady_clock::time_point> last_event_time_;
  std::unordered_map<int, std::string> pending_payload_;
  std::chrono::steady_clock::time_point backoff_until_{};
  size_t queue_full_count_{0};
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_EVENT_BRIDGE_H
