#ifndef LIBRETRO_ENGINE_INPUT_PORT_ROUTER_H
#define LIBRETRO_ENGINE_INPUT_PORT_ROUTER_H

#include "input_manager.h"
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace libretro {

enum class InputSourceType : uint8_t {
  None = 0,
  Virtual = 1,
  Keyboard = 2,
  Mouse = 3,
  Gamepad = 4,
  BluetoothGamepad = 5,
  Unknown = 6
};

struct InputDeviceInfo {
  std::string deviceId;
  InputSourceType sourceType = InputSourceType::Unknown;
  std::string name;
};

struct PortSource {
  InputSourceType sourceType = InputSourceType::None;
  std::string deviceId;
};

class InputPortRouter {
public:
  explicit InputPortRouter(InputManager *inputManager);

  bool AssignPort(int port, InputSourceType sourceType,
                  const std::string &deviceId);
  bool UnassignPort(int port);

  bool CanSendVirtual(int port) const;
  bool ResolvePortForDevice(const std::string &deviceId,
                            InputSourceType sourceType, int &outPort);

  void RecordDeviceSeen(const std::string &deviceId,
                        InputSourceType sourceType,
                        const std::string &name);
  std::vector<InputDeviceInfo> ListDevices() const;
  PortSource GetPortSource(int port) const;

private:
  bool IsValidPort(int port) const;
  void ClearPortStateLocked(int port);
  bool UnassignPortLocked(int port);
  bool MatchSourceType(InputSourceType portType,
                       InputSourceType incomingType) const;

  InputManager *inputManager_ = nullptr;
  mutable std::mutex mutex_;
  PortSource portSources_[InputSnapshot::kMaxPorts];
  std::unordered_map<std::string, int> deviceToPort_;
  std::unordered_map<std::string, InputDeviceInfo> devices_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_INPUT_PORT_ROUTER_H
