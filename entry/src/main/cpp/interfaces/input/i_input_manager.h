/*
 * 输入管理器接口 - 处理手柄、触摸、键盘等输入
 */

#ifndef INTERFACES_I_INPUT_MANAGER_H
#define INTERFACES_I_INPUT_MANAGER_H

#include <cstdint>
#include <string>
#include <vector>

namespace interfaces {

struct InputDeviceInfo {
  std::string deviceId;
  int sourceType;
  std::string name;
};

struct InputDebugStats {
  int touchCount;
  int mouseCount;
  int keyCount;
  bool hasFocus;
  bool mouseDown;
  int lastTouchType;
  int lastMouseAction;
  int lastKeyAction;
};

/**
 * @brief 输入管理器接口
 * 对应 ArkTS refactoredSendInput 等接口
 */
class IInputManager {
public:
  virtual ~IInputManager() = default;

  // 输入事件发送
  virtual bool SendInput(int port, int id, bool pressed) = 0;
  virtual bool SendAnalog(int port, int index, int id, int value) = 0;
  virtual bool SendPointer(int port, int x, int y, bool pressed) = 0;
  virtual bool SendSensor(int port, int id, float value) = 0;

  // 设备管理
  virtual bool AssignPortSource(int port, int sourceType,
                                const std::string &deviceId = "") = 0;
  virtual bool UnassignPort(int port) = 0;
  virtual std::vector<InputDeviceInfo> ListInputDevices() const = 0;
  virtual bool SetControllerPortDevice(int port, int device) = 0;

  // 调试信息
  virtual InputDebugStats GetDebugStats() const = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_INPUT_MANAGER_H
