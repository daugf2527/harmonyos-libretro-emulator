#ifndef LIBRETRO_ENGINE_ENGINE_MESSAGES_H
#define LIBRETRO_ENGINE_ENGINE_MESSAGES_H

#include <cstring>
#include <cstdint>
#include <memory>
#include <native_window/external_window.h>
#include <string>
#include <utility>
#include <vector>

namespace libretro {

class EngineSyncTask;

/**
 * @brief 消息类型定义
 */
enum class MessageType {
  Input,      // 输入状态变化（通常用于设备连接/映射变更）
  LoadCore,   // 加载核心
  LoadRom,    // 加载 ROM
  SetFilesDir, // 设置 filesDir（仅允许在 Core 未加载时）
  TouchEvent, // 触摸事件
  Pause,      // 暂停请求
  Resume,     // 恢复请求
  Stop,       // 停止请求
  WindowCreated,   // 窗口已创建
  WindowDestroyed, // 窗口已销毁
  WindowRebind,    // 兼容旧链路的遗留消息（新链路请使用 WindowCreated+generation）
  WindowResized,   // 窗口尺寸变化
  SetVideoFormat,  // 设置视频格式
  SyncTask         // 同步任务（在 Engine 线程执行）
};

/**
 * @brief 消息负载定义
 */
struct EngineMessageInput {
  int port;
  int id;
  bool pressed;
};

struct EngineMessageLoadPath {
  // 与 NAPI 路径缓冲保持一致，避免跨线程消息层静默截断。
  // 使用固定数组而非 std::string 是为了保持消息结构的简单性和可拷贝性
  static constexpr size_t kPathCapacity = 1024;
  char path[kPathCapacity];
  std::shared_ptr<std::vector<uint8_t>> data;
};

struct EngineMessageTouch {
  float x;
  float y;
  bool pressed;
};

struct EngineMessageWindow {
  OHNativeWindow *window;
  bool force_rebind; // legacy 字段：新链路不再依赖隐式重绑
  uint64_t generation;
};

struct EngineMessageWindowSize {
  int width;
  int height;
};

struct EngineMessageVideoFormat {
  int format;
  int width;
  int height;
  int pitch;
};

struct EngineMessageSyncTask {
  std::shared_ptr<EngineSyncTask> task;
};

/**
 * @brief 统一消息包装体 (Tagged Struct)
 * 采用 C++14 安全的 pod 组合，避免 union 在非 POD 类型（如
 * std::string）下的陷阱。 约定：根据 type 字段决定读取 payload 中的哪个成员。
 */
struct EngineMessage {
  MessageType type;

  struct {
    EngineMessageInput input;
    EngineMessageLoadPath loadPath;
    EngineMessageTouch touch;
    EngineMessageWindow window;
    EngineMessageWindowSize windowSize;
    EngineMessageVideoFormat videoFormat;
    EngineMessageSyncTask syncTask;
  } payload;

  // 辅助构造函数：LoadCore/LoadRom (处理路径)
  static EngineMessage
  MakeLoadMessage(MessageType type, const std::string &path,
                  std::shared_ptr<std::vector<uint8_t>> data = nullptr) {
    EngineMessage msg{};
    msg.type = type;
    const size_t maxLen = EngineMessageLoadPath::kPathCapacity - 1;
    size_t copyLen = (path.size() < maxLen) ? path.size() : maxLen;
    std::memcpy(msg.payload.loadPath.path, path.c_str(), copyLen);
    msg.payload.loadPath.path[copyLen] = '\0';
    msg.payload.loadPath.data = data;
    return msg;
  }

  // 辅助构造函数：Window 消息
  static EngineMessage MakeWindowMessage(MessageType type, OHNativeWindow *window,
                                         bool force_rebind = false,
                                         uint64_t generation = 0) {
    EngineMessage msg{};
    msg.type = type;
    msg.payload.window.window = window;
    msg.payload.window.force_rebind = force_rebind;
    msg.payload.window.generation = generation;
    return msg;
  }

  static EngineMessage MakeWindowRebindMessage(OHNativeWindow *window,
                                               uint64_t generation = 0) {
    // 保留仅用于兼容旧消息源；新代码请使用 MakeWindowMessage(WindowCreated,...)
    return MakeWindowMessage(MessageType::WindowRebind, window, true,
                             generation);
  }

  static EngineMessage MakeWindowResizeMessage(int width, int height) {
    EngineMessage msg{};
    msg.type = MessageType::WindowResized;
    msg.payload.windowSize.width = width;
    msg.payload.windowSize.height = height;
    return msg;
  }

  static EngineMessage MakeSyncTaskMessage(std::shared_ptr<EngineSyncTask> task) {
    EngineMessage msg{};
    msg.type = MessageType::SyncTask;
    msg.payload.syncTask.task = std::move(task);
    return msg;
  }

  // 其他辅助构造函数可以根据需要添加
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_ENGINE_MESSAGES_H
