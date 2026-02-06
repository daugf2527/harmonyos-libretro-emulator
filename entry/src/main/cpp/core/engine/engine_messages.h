#ifndef LIBRETRO_ENGINE_ENGINE_MESSAGES_H
#define LIBRETRO_ENGINE_ENGINE_MESSAGES_H

#include <memory>
#include <native_window/external_window.h>
#include <string>
#include <vector>

namespace libretro {

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
  WindowResized,   // 窗口尺寸变化
  SetVideoFormat   // 设置视频格式
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
  // 固定 512 字节：鸿蒙沙箱路径通常 <100 字符，512 足够覆盖所有场景
  // 使用固定数组而非 std::string 是为了保持消息结构的简单性和可拷贝性
  char path[512];
  std::shared_ptr<std::vector<uint8_t>> data;
};

struct EngineMessageTouch {
  float x;
  float y;
  bool pressed;
};

struct EngineMessageWindow {
  OHNativeWindow *window;
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
  } payload;

  // 辅助构造函数：LoadCore/LoadRom (处理路径)
  static EngineMessage
  MakeLoadMessage(MessageType type, const std::string &path,
                  std::shared_ptr<std::vector<uint8_t>> data = nullptr) {
    EngineMessage msg;
    msg.type = type;
    size_t copyLen = (path.size() < 511) ? path.size() : 511;
    std::memcpy(msg.payload.loadPath.path, path.c_str(), copyLen);
    msg.payload.loadPath.path[copyLen] = '\0';
    msg.payload.loadPath.data = data;
    return msg;
  }

  // 辅助构造函数：Window 消息
  static EngineMessage MakeWindowMessage(MessageType type,
                                         OHNativeWindow *window) {
    EngineMessage msg;
    msg.type = type;
    msg.payload.window.window = window;
    return msg;
  }

  static EngineMessage MakeWindowResizeMessage(int width, int height) {
    EngineMessage msg;
    msg.type = MessageType::WindowResized;
    msg.payload.windowSize.width = width;
    msg.payload.windowSize.height = height;
    return msg;
  }

  // 其他辅助构造函数可以根据需要添加
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_ENGINE_MESSAGES_H
