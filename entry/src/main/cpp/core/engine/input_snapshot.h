#ifndef LIBRETRO_ENGINE_INPUT_SNAPSHOT_H
#define LIBRETRO_ENGINE_INPUT_SNAPSHOT_H

#include <atomic>
#include <cstdint>

namespace libretro {

/**
 * @brief 原子输入快照，用于游戏后台线程高性能轮询输入状态。
 * 使用原子比特掩码和原子数组，避免消息队列对高频操作（如快速连按）的延迟影响。
 */
class InputSnapshot {
public:
  static constexpr int kMaxPorts = 4;
  static constexpr int kMaxButtons = 32;
  static constexpr int kMaxAnalogAxes = 32;
  static constexpr int kMaxSensors = 16;

  InputSnapshot() {
    for (int port = 0; port < kMaxPorts; ++port) {
      buttons_mask_[port].store(0);
      pointer_state_[port].store(0);
      for (int i = 0; i < kMaxAnalogAxes; ++i) {
        analog_axes_[port][i].store(0);
      }
      for (int i = 0; i < kMaxSensors; ++i) {
        sensor_values_[port][i].store(0.0f);
      }
    }
  }

  /**
   * @brief 设置按键状态（由 UI 线程/NAPI 调用）
   */
  void SetButton(int port, int id, bool pressed) {
    if (!IsValidPort(port) || id < 0 || id >= kMaxButtons) {
      return;
    }
    if (pressed) {
      buttons_mask_[port].fetch_or(1u << id);
    } else {
      buttons_mask_[port].fetch_and(~(1u << id));
    }
  }

  /**
   * @brief 获取按键掩码 (用于 RETRO_DEVICE_ID_JOYPAD_MASK)
   */
  uint32_t GetButtonsMask(int port) const {
    if (!IsValidPort(port)) {
      return 0;
    }
    return buttons_mask_[port].load();
  }

  /**
   * @brief 获取单个按键状态
   */
  bool GetButton(int port, int id) const {
    if (IsValidPort(port) && id >= 0 && id < kMaxButtons) {
      return (buttons_mask_[port].load(std::memory_order_relaxed) &
              (1u << id)) != 0;
    }
    return false;
  }

  /**
   * @brief 设置模拟量状态
   */
  void SetAnalog(int port, int index, int id, int16_t value) {
    if (!IsValidPort(port) || index < 0 || id < 0) {
      return;
    }
    int axis_idx = (index * 2) + id;
    if (axis_idx < kMaxAnalogAxes) {
      analog_axes_[port][axis_idx].store(value, std::memory_order_relaxed);
    }
  }

  /**
   * @brief 获取模拟量状态
   */
  int16_t GetAnalog(int port, int index, int id) const {
    if (!IsValidPort(port) || index < 0 || id < 0 ||
        index >= kMaxAnalogAxes / 2 || id >= 2) {  // Audit A-F2: pre-check prevents (index*2)+id overflow
      return 0;
    }
    int axis_idx = (index * 2) + id;
    if (axis_idx < kMaxAnalogAxes) {
      return analog_axes_[port][axis_idx].load(std::memory_order_relaxed);
    }
    return 0;
  }

  /**
   * @brief 清空所有输入状态
   */
  void Clear() {
    for (int port = 0; port < kMaxPorts; ++port) {
      buttons_mask_[port].store(0);
      for (int i = 0; i < kMaxAnalogAxes; ++i) {
        analog_axes_[port][i].store(0, std::memory_order_relaxed);
      }
      pointer_state_[port].store(0, std::memory_order_relaxed);
      for (int i = 0; i < kMaxSensors; ++i) {
        sensor_values_[port][i].store(0.0f, std::memory_order_relaxed);
      }
    }
  }

  /**
   * @brief 清空指定端口输入状态
   */
  void ClearPort(int port) {
    if (!IsValidPort(port)) {
      return;
    }
    buttons_mask_[port].store(0);
    for (int i = 0; i < kMaxAnalogAxes; ++i) {
      analog_axes_[port][i].store(0, std::memory_order_relaxed);
    }
    pointer_state_[port].store(0, std::memory_order_relaxed);
    for (int i = 0; i < kMaxSensors; ++i) {
      sensor_values_[port][i].store(0.0f, std::memory_order_relaxed);
    }
  }

  /**
   * @brief 设置指针状态 (Touch/Mouse)
   * 坐标应归一化到 [-0x8000, 0x7fff]
   *
   * 单原子 64-bit 打包 (xy + pressed),保证 GetPointer 不会读到"新坐标 + 旧
   * pressed"撕裂状态(原 xy 与 pressed 分两个 atomic,可能跨 1 帧不一致)。
   */
  void SetPointer(int port, int16_t x, int16_t y, bool pressed) {
    if (!IsValidPort(port)) {
      return;
    }
    // 位布局: bit 63 = pressed, bits 31..16 = y, bits 15..0 = x
    uint64_t packed =
        (static_cast<uint64_t>(static_cast<uint16_t>(y)) << 16) |
        static_cast<uint64_t>(static_cast<uint16_t>(x));
    if (pressed) {
      packed |= (1ULL << 63);
    }
    pointer_state_[port].store(packed, std::memory_order_relaxed);
  }

  /**
   * @brief 获取指针状态
   */
  void GetPointer(int port, int16_t &x, int16_t &y, bool &pressed) const {
    if (!IsValidPort(port)) {
      x = 0;
      y = 0;
      pressed = false;
      return;
    }
    uint64_t packed = pointer_state_[port].load(std::memory_order_relaxed);
    x = static_cast<int16_t>(packed & 0xFFFF);
    y = static_cast<int16_t>((packed >> 16) & 0xFFFF);
    pressed = ((packed >> 63) & 1ULL) != 0;
  }

  /**
   * @brief 设置传感器数据 (Accelerometer/Gyroscope/etc.)
   * @param port 端口 (通常为 0)
   * @param id 传感器 ID (如 RETRO_SENSOR_ACCELEROMETER_X)
   * @param value 传感器值
   */
  void SetSensor(int port, int id, float value) {
    if (IsValidPort(port) && id >= 0 && id < kMaxSensors) {
      sensor_values_[port][id].store(value, std::memory_order_relaxed);
    }
  }

  /**
   * @brief 获取传感器数据
   */
  float GetSensor(int port, int id) const {
    if (IsValidPort(port) && id >= 0 && id < kMaxSensors) {
      return sensor_values_[port][id].load(std::memory_order_relaxed);
    }
    return 0.0f;
  }

private:
  static bool IsValidPort(int port) {
    return port >= 0 && port < kMaxPorts;
  }

  // Audit A-F8: 60fps read path assumes lock-free atomics; assert at compile time.
  // HarmonyOS libc++ lacks is_always_lock_free member; use C11 ATOMIC_*_LOCK_FREE macros (== 2 means always lock-free).
  static_assert(ATOMIC_INT_LOCK_FREE == 2,   "atomic<uint32_t> must be lock-free on this platform");
  static_assert(ATOMIC_SHORT_LOCK_FREE == 2, "atomic<int16_t> must be lock-free on this platform");
  // float is same size as int (4 bytes on AArch64); lock-free iff ATOMIC_INT_LOCK_FREE==2
  static_assert(ATOMIC_INT_LOCK_FREE == 2,   "atomic<float> must be lock-free on this platform");
  static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "atomic<uint64_t> must be lock-free on this platform");

  // 使用原子 32 位整数位图存储按键状态（支持 32 个按键）
  std::atomic<uint32_t> buttons_mask_[kMaxPorts];

  // 使用原子数组存储模拟量（支持 32 个轴）
  std::atomic<int16_t> analog_axes_[kMaxPorts][kMaxAnalogAxes];

  // 指针状态 (xy + pressed 打包到单个 64-bit atomic,避免跨原子撕裂)
  // 位布局: bit 63 = pressed, bits 31..16 = y, bits 15..0 = x
  std::atomic<uint64_t> pointer_state_[kMaxPorts];

  // 传感器数据 (支持 16 个通道，足以覆盖 Accel(3) + Gyro(3) + Light(1) + others)
  std::atomic<float> sensor_values_[kMaxPorts][kMaxSensors];
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_INPUT_SNAPSHOT_H
