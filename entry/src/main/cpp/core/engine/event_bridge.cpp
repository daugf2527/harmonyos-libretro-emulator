#include "event_bridge.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD013
#undef LOG_TAG
#define LOG_TAG "EventBridge"
#undef LOG_FLOW
#define LOG_FLOW "Event"
#include "common/log_prefix.h"

namespace libretro {
namespace {
struct ThrottleRule {
  int64_t interval_ms = 0;
  bool coalesce = false;
};

// Map Enum to String
static const char* GetEventName(EventBridge::EventType event) {
    switch (event) {
        case EventBridge::EventType::FPS_UPDATE: return "fps_update";
        case EventBridge::EventType::AUDIO_STATUS: return "audio_status";
        case EventBridge::EventType::GEOMETRY_UPDATE: return "geometry_update";
        case EventBridge::EventType::OPTIONS_UPDATE: return "options_update";
        case EventBridge::EventType::PIXEL_FORMAT_UPDATE: return "pixel_format_update";
        case EventBridge::EventType::CORE_MESSAGE: return "core_message";
        case EventBridge::EventType::CORE_ERROR: return "core_error";
        case EventBridge::EventType::CORE_CRASH: return "core_crash";
        case EventBridge::EventType::ENGINE_STATE: return "engine_state";
        case EventBridge::EventType::DISK_CONTROL: return "disk_control";
        case EventBridge::EventType::RUMBLE: return "rumble";
        case EventBridge::EventType::SENSOR_STATE: return "sensor_state";
        default: return "unknown";
    }
}

// Map String to Enum (for legacy support)
static EventBridge::EventType GetEventType(const std::string& event) {
    if (event == "fps_update") return EventBridge::EventType::FPS_UPDATE;
    if (event == "audio_status") return EventBridge::EventType::AUDIO_STATUS;
    if (event == "geometry_update") return EventBridge::EventType::GEOMETRY_UPDATE;
    if (event == "options_update") return EventBridge::EventType::OPTIONS_UPDATE;
    if (event == "pixel_format_update") return EventBridge::EventType::PIXEL_FORMAT_UPDATE;
    if (event == "core_message") return EventBridge::EventType::CORE_MESSAGE;
    if (event == "core_error") return EventBridge::EventType::CORE_ERROR;
    if (event == "core_crash") return EventBridge::EventType::CORE_CRASH;
    if (event == "engine_state") return EventBridge::EventType::ENGINE_STATE;
    if (event == "disk_control") return EventBridge::EventType::DISK_CONTROL;
    if (event == "rumble") return EventBridge::EventType::RUMBLE;
    if (event == "sensor_state") return EventBridge::EventType::SENSOR_STATE;
    return EventBridge::EventType::UNKNOWN;
}

ThrottleRule GetThrottleRule(EventBridge::EventType event) {
  switch (event) {
  case EventBridge::EventType::FPS_UPDATE:
    return {500, true};
  case EventBridge::EventType::AUDIO_STATUS:
    return {200, true};
  case EventBridge::EventType::GEOMETRY_UPDATE:
    return {200, true};
  case EventBridge::EventType::OPTIONS_UPDATE:
    return {500, true};
  case EventBridge::EventType::PIXEL_FORMAT_UPDATE:
    return {500, true};
  default:
    return {};
  }
}
} // namespace

EventBridge::~EventBridge() { Release(); }

bool EventBridge::Initialize(napi_env env, napi_value callback) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (tsfn_) {
    LOGF(LOG_WARN, "EventBridge already initialized. Aborting old TSFN and re-creating.");
    napi_release_threadsafe_function(tsfn_, napi_tsfn_abort);  // Audit A-F4: abort mode drains pending EventData* before re-init
    tsfn_ = nullptr;
  }

  napi_value resource_name;
  napi_create_string_utf8(env, "LibretroEventBridge", NAPI_AUTO_LENGTH,
                          &resource_name);

  // 创建 TSFN
  // context: nullptr, max_queue_size: 256
  constexpr size_t MAX_QUEUE_SIZE = 256;
  napi_status status = napi_create_threadsafe_function(
      env, callback, nullptr, resource_name, MAX_QUEUE_SIZE, 1, nullptr, nullptr, nullptr,
      CallJsHandler, &tsfn_);

  if (status != napi_ok) {
    LOGF(LOG_ERROR, "Failed to create TSFN: %{public}d", status);
    return false;
  }

  pending_payload_.clear();
  last_event_time_.clear();
  backoff_until_ = std::chrono::steady_clock::time_point();
  queue_full_count_ = 0;
  LOGF(LOG_INFO, "EventBridge Initialized");
  return true;
}

void EventBridge::Emit(const std::string &event, const std::string &payload, bool force) {
    Emit(GetEventType(event), payload, force);
}

void EventBridge::Emit(EventType event, const std::string &payload,
                       bool force) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!tsfn_) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (!force && backoff_until_ != std::chrono::steady_clock::time_point() &&
      now < backoff_until_) {
    return;
  }

  std::string payload_to_send = payload;
  int eventKey = static_cast<int>(event);

  ThrottleRule rule{};
  if (!force) {
    rule = GetThrottleRule(event);
    if (rule.interval_ms > 0) {
      auto last_it = last_event_time_.find(eventKey);
      if (last_it != last_event_time_.end()) {
        const auto elapsed_ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                now - last_it->second)
                .count();
        if (elapsed_ms < rule.interval_ms) {
          if (rule.coalesce) {
            pending_payload_[eventKey] = payload;
          }
          return;
        }
      }

      auto pending_it = pending_payload_.find(eventKey);
      if (pending_it != pending_payload_.end()) {
        pending_payload_.erase(pending_it);
      }
    }
  }

  EventData *data = new EventData{GetEventName(event), payload_to_send};
  napi_status status = napi_call_threadsafe_function(
      tsfn_, data, napi_tsfn_nonblocking);

  if (status == napi_queue_full) {
    delete data;
    queue_full_count_++;
    if (!force && rule.coalesce) {
      pending_payload_[eventKey] = payload_to_send;
    }
    if (queue_full_count_ > 10) {
        // Backoff for 1s
        backoff_until_ = now + std::chrono::seconds(1);
        queue_full_count_ = 0;
        LOGF(LOG_WARN, "EventBridge queue full, backing off");
    }
  } else if (status != napi_ok) {
    delete data;
  } else {
      if (!force) {
        last_event_time_[eventKey] = now;
      }
      queue_full_count_ = 0;
  }
}

void EventBridge::Release() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (tsfn_) {
    LOGF(LOG_INFO, "Releasing TSFN...");
    napi_release_threadsafe_function(tsfn_, napi_tsfn_release);
    tsfn_ = nullptr;
  }
  pending_payload_.clear();
  last_event_time_.clear();
  backoff_until_ = std::chrono::steady_clock::time_point();
  queue_full_count_ = 0;
}

void EventBridge::CallJsHandler(napi_env env, napi_value js_cb, void *context,
                                void *data) {
  if (env == nullptr || js_cb == nullptr) {
    if (data)
      delete static_cast<EventData *>(data);
    return;
  }

  auto eventData = static_cast<EventData *>(data);
  if (!eventData)
    return;

  // 构造传回 JS 的对象 { event: string, payload: any/string }
  napi_value result;
  napi_create_object(env, &result);

  napi_value event_name, event_payload;
  napi_create_string_utf8(env, eventData->event.c_str(), NAPI_AUTO_LENGTH,
                          &event_name);
  napi_create_string_utf8(env, eventData->payload.c_str(), NAPI_AUTO_LENGTH,
                          &event_payload);

  napi_set_named_property(env, result, "event", event_name);
  napi_set_named_property(env, result, "payload", event_payload);

  // 调用 JS 回调
  napi_value undefined;
  napi_get_undefined(env, &undefined);
  napi_status call_status = napi_call_function(env, undefined, js_cb, 1, &result, nullptr);
  if (call_status == napi_pending_exception) {  // Audit A-F5: clear JS exception to prevent NAPI state corruption
    napi_value exception;
    napi_get_and_clear_last_exception(env, &exception);
    LOGF(LOG_WARN, "EventBridge JS callback threw; exception cleared");
  }

  delete eventData;
}

} // namespace libretro
