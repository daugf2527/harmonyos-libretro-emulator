#ifndef LIBRETRO_ENGINE_INPUT_MANAGER_H
#define LIBRETRO_ENGINE_INPUT_MANAGER_H

#include "../libretro/libretro.h"
#include "event_bridge.h"
#include "input_snapshot.h"
#include "interfaces/input/i_input_manager.h"
#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>

namespace libretro {

class InputPortRouter;
enum class InputSourceType : uint8_t;

/**
 * @brief InputManager
 * Manages input state, sensor data, and rumble effects.
 * Decoupled from LibretroEngine to reduce complexity.
 */
class InputManager : public interfaces::IInputManager {
public:
  InputManager(EventBridge *eventBridge);
  ~InputManager();

  // Explicitly handle lifecycle if needed (e.g. strict singleton management)
  static InputManager *GetInstance();

  // --- Input Updates (called from UI/NAPI) ---
  bool SendInput(int port, int id, bool pressed) override;
  bool SendAnalog(int port, int index, int id, int value) override;
  bool SendPointer(int port, int x, int y, bool pressed) override;
  bool SendSensor(int port, int id, float value) override;

  bool AssignPortSource(int port, int sourceType,
                        const std::string &deviceId = "") override;
  bool UnassignPort(int port) override;
  std::vector<interfaces::InputDeviceInfo> ListInputDevices() const override;
  bool SetControllerPortDevice(int port, int device) override;
  interfaces::InputDebugStats GetDebugStats() const override;

  void SetPortRouter(InputPortRouter *router);
  void SetControllerPortDeviceCallback(
      std::function<void(unsigned, unsigned)> callback);

  bool CanSendVirtual(int port) const;
  bool ResolvePortForDevice(const std::string &deviceId,
                            InputSourceType sourceType, int &outPort);
  void RecordInputDevice(const std::string &deviceId,
                         InputSourceType sourceType,
                         const std::string &name);

  // --- State Management ---
  void Clear();
  void ClearPort(int port);
  InputSnapshot *GetSnapshot() { return &inputSnapshot_; }

  // --- Libretro Callbacks (Static) ---
  static void OnInputPoll();
  static int16_t OnInputState(unsigned port, unsigned device, unsigned index,
                              unsigned id);
  static bool OnRumble(unsigned port, retro_rumble_effect effect,
                       uint16_t strength);
  static bool OnSensorSetState(unsigned port, retro_sensor_action action,
                               unsigned rate);
  static float OnSensorGetInput(unsigned port, unsigned id);

private:
  InputSnapshot inputSnapshot_;
  EventBridge *eventBridge_; // Weak reference to EventBridge for emitting
                             // events (Rumble/Sensor)
  InputPortRouter *portRouter_ = nullptr;
  std::function<void(unsigned, unsigned)> controller_port_device_callback_;

  // Static instance for Libretro C-style callbacks
  static std::atomic<InputManager *> g_instance;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_INPUT_MANAGER_H
