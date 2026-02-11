#ifndef LIBRETRO_ENV_DISPATCHER_H
#define LIBRETRO_ENV_DISPATCHER_H

#include "core/libretro/libretro.h"
#include "core/libretro/libretro_vulkan.h"
#include "core/libretro/core_options_registry.h"
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include <atomic>
#include <functional>

namespace libretro {

class EnvState {
public:
  bool SetBaseDir(const std::string &filesDir);
  void ResetCoreState();
  const char *GetBaseDir() const { return base_directory_.c_str(); }
  void SetLibretroPath(const std::string &corePath) { libretro_path_ = corePath; }
  const char *GetLibretroPath() const { return libretro_path_.c_str(); }

  const char *GetSystemDirectory() const { return system_directory_.c_str(); }
  const char *GetSaveDirectory() const { return save_directory_.c_str(); }
  const char *GetContentDirectory() const { return content_directory_.c_str(); }
  const char *GetCoreAssetsDirectory() const { return core_assets_directory_.c_str(); }
  const char *GetCacheDirectory() const { return cache_directory_.c_str(); }

  void SetSystemDirectory(const std::string &dir) { system_directory_ = dir; }
  void SetSaveDirectory(const std::string &dir) { save_directory_ = dir; }
  void SetContentDirectory(const std::string &dir) { content_directory_ = dir; }
  void SetCoreAssetsDirectory(const std::string &dir) { core_assets_directory_ = dir; }
  void SetCacheDirectory(const std::string &dir) { cache_directory_ = dir; }

  void SetFrameTimeCallback(::retro_frame_time_callback_t cb, ::retro_usec_t reference) {
    frame_time_callback_ = cb;
    frame_time_reference_ = reference;
  }
  ::retro_frame_time_callback_t GetFrameTimeCallback() const { return frame_time_callback_; }
  ::retro_usec_t GetFrameTimeReference() const { return frame_time_reference_; }

  void SetAudioBufferStatusCallback(::retro_audio_buffer_status_callback_t cb) {
    audio_buffer_status_callback_ = cb;
  }
  ::retro_audio_buffer_status_callback_t GetAudioBufferStatusCallback() const {
    return audio_buffer_status_callback_;
  }

  void EnterRetroRun() { in_retro_run_ = true; }
  void ExitRetroRun() { in_retro_run_ = false; }
  bool IsInRetroRun() const { return in_retro_run_; }

  void SetPendingMinimumAudioLatencyMs(unsigned latency_ms) {
    std::lock_guard<std::mutex> lock(min_audio_latency_mutex_);
    pending_min_audio_latency_ms_ = latency_ms;
    has_pending_min_audio_latency_ = true;
  }
  bool ConsumePendingMinimumAudioLatencyMs(unsigned &out_latency_ms) {
    std::lock_guard<std::mutex> lock(min_audio_latency_mutex_);
    if (!has_pending_min_audio_latency_) {
      return false;
    }
    out_latency_ms = pending_min_audio_latency_ms_;
    has_pending_min_audio_latency_ = false;
    return true;
  }

  bool SetVariable(const char *key, const char *value);
  const char *GetVariable(const char *key) const;

  bool ConsumeVariableUpdated();

  void SetCanDupe(bool can) { can_dupe_ = can; }
  bool CanDupe() const { return can_dupe_; }

  void SetOverscan(bool overscan) { overscan_ = overscan; }
  bool GetOverscan() const { return overscan_; }

  void SetPixelFormat(::retro_pixel_format format) { pixel_format_ = format; }
  ::retro_pixel_format GetPixelFormat() const { return pixel_format_; }

  // Geometry 支持 (SET_GEOMETRY)
  void SetGeometry(unsigned base_w, unsigned base_h, float aspect) {
    geometry_base_width_ = base_w;
    geometry_base_height_ = base_h;
    geometry_aspect_ratio_ = aspect;
    geometry_updated_ = true;
  }
  unsigned GetGeometryBaseWidth() const { return geometry_base_width_; }
  unsigned GetGeometryBaseHeight() const { return geometry_base_height_; }
  float GetGeometryAspectRatio() const { return geometry_aspect_ratio_; }
  bool ConsumeGeometryUpdated() {
    bool updated = geometry_updated_;
    geometry_updated_ = false;
    return updated;
  }

  void SetSupportsNoGame(bool supports) { supports_no_game_ = supports; }
  bool SupportsNoGame() const { return supports_no_game_; }

  void SetPerformanceLevel(unsigned level) { performance_level_ = level; }
  unsigned GetPerformanceLevel() const { return performance_level_; }

  void SetInputDeviceCapabilities(uint64_t caps) { input_capabilities_ = caps; }
  uint64_t GetInputDeviceCapabilities() const { return input_capabilities_; }

  void SetInputMaxUsers(unsigned users) { input_max_users_ = users; }
  unsigned GetInputMaxUsers() const { return input_max_users_; }

  void SetSupportsInputBitmasks(bool supported) {
    supports_input_bitmasks_ = supported;
  }
  bool SupportsInputBitmasks() const { return supports_input_bitmasks_; }

  void SetUsername(const std::string &name) { username_ = name; }
  const char *GetUsername() const { return username_.c_str(); }

  void SetLanguage(::retro_language lang) { language_ = lang; }
  ::retro_language GetLanguage() const { return language_; }

  const std::string &GetCoreOptionsConfigPath() const {
    return core_options_config_path_;
  }

  void ClearCoreOptions();
  void SetCoreOptions(std::vector<core_options::CoreOptionCategory> categories,
                      std::vector<core_options::CoreOptionDefinition> definitions);
  std::vector<core_options::CoreOptionCategory> GetCoreOptionCategories() const {
    std::lock_guard<std::mutex> lock(core_options_mutex_);
    return core_option_categories_;
  }
  std::vector<core_options::CoreOptionDefinition> GetCoreOptionDefinitions() const {
    std::lock_guard<std::mutex> lock(core_options_mutex_);
    return core_option_definitions_;
  }

  bool SetCoreOptionValue(const char *key, const char *value);

  void SetKeyboardCallback(const ::retro_keyboard_callback &cb) {
    keyboard_callback_ = cb;
    has_keyboard_callback_ = true;
  }
  bool HasKeyboardCallback() const { return has_keyboard_callback_; }
  const ::retro_keyboard_callback *GetKeyboardCallback() const {
    return has_keyboard_callback_ ? &keyboard_callback_ : nullptr;
  }

  void SetHwRenderCallback(const ::retro_hw_render_callback &cb) {
    hw_render_cb_ = cb;
    hw_context_type_ = cb.context_type;
    hw_render_enabled_.store(hw_context_type_ != ::RETRO_HW_CONTEXT_NONE);
  }
  bool IsHwRenderEnabled() const { return hw_render_enabled_.load(); }
  void SetHwRenderAllowed(bool allowed) { hw_render_allowed_.store(allowed); }
  bool IsHwRenderAllowed() const { return hw_render_allowed_.load(); }
  const ::retro_hw_render_callback &GetHwRenderCallback() const {
    return hw_render_cb_;
  }
  ::retro_hw_context_type GetHwContextType() const {
    return hw_context_type_;
  }

  void SetVulkanInterface(const retro_hw_render_interface_vulkan *iface) {
    vulkan_interface_ = iface;
  }
  const retro_hw_render_interface_vulkan *GetVulkanInterface() const {
    return vulkan_interface_;
  }

  void SetVulkanNegotiationInterface(
      const retro_hw_render_context_negotiation_interface_vulkan &iface) {
    vulkan_negotiation_ = iface;
    has_vulkan_negotiation_ = true;
  }
  bool HasVulkanNegotiationInterface() const { return has_vulkan_negotiation_; }
  const retro_hw_render_context_negotiation_interface_vulkan *
  GetVulkanNegotiationInterface() const {
    return has_vulkan_negotiation_ ? &vulkan_negotiation_ : nullptr;
  }

  void ClearDiskControlCallbacks() {
    has_disk_control_cb_ = false;
    has_disk_control_ext_cb_ = false;
  }
  void SetDiskControlCallback(const ::retro_disk_control_callback &cb) {
    disk_control_cb_ = cb;
    has_disk_control_cb_ = true;
  }
  void SetDiskControlExtCallback(const ::retro_disk_control_ext_callback &cb) {
    disk_control_ext_cb_ = cb;
    has_disk_control_ext_cb_ = true;
  }
  bool HasDiskControlCallback() const { return has_disk_control_cb_; }
  bool HasDiskControlExtCallback() const { return has_disk_control_ext_cb_; }
  const ::retro_disk_control_callback *GetDiskControlCallback() const {
    return has_disk_control_cb_ ? &disk_control_cb_ : nullptr;
  }
  const ::retro_disk_control_ext_callback *GetDiskControlExtCallback() const {
    return has_disk_control_ext_cb_ ? &disk_control_ext_cb_ : nullptr;
  }

private:
  std::string system_directory_;
  std::string save_directory_;
  std::string content_directory_;
  std::string core_assets_directory_;
  std::string cache_directory_;
  std::string config_directory_;
  std::string base_directory_;
  std::string core_options_config_path_;
  std::string libretro_path_;

  ::retro_frame_time_callback_t frame_time_callback_ = nullptr;
  ::retro_usec_t frame_time_reference_ = 0;

  ::retro_audio_buffer_status_callback_t audio_buffer_status_callback_ = nullptr;

  unsigned pending_min_audio_latency_ms_ = 0;
  bool has_pending_min_audio_latency_ = false;
  mutable std::mutex min_audio_latency_mutex_;
  bool in_retro_run_ = false;

  std::map<std::string, std::string> variables_;
  bool variable_updated_ = false;
  mutable std::mutex variables_mutex_;

  bool can_dupe_ = true;
  bool overscan_ = false;
  bool supports_no_game_ = false;
  ::retro_pixel_format pixel_format_ = ::RETRO_PIXEL_FORMAT_0RGB1555;
  unsigned geometry_base_width_ = 0;
  unsigned geometry_base_height_ = 0;
  float geometry_aspect_ratio_ = 0.0f;
  bool geometry_updated_ = false;
  unsigned performance_level_ = 0;

  uint64_t input_capabilities_ =
      (1ULL << RETRO_DEVICE_JOYPAD) | (1ULL << RETRO_DEVICE_ANALOG);
  unsigned input_max_users_ = 4;
  bool supports_input_bitmasks_ = true;

  std::string username_ = "Player";
  ::retro_language language_ = ::RETRO_LANGUAGE_CHINESE_SIMPLIFIED;

  mutable std::mutex core_options_mutex_;
  std::vector<core_options::CoreOptionCategory> core_option_categories_;
  std::vector<core_options::CoreOptionDefinition> core_option_definitions_;

  ::retro_keyboard_callback keyboard_callback_{};
  bool has_keyboard_callback_ = false;
  ::retro_disk_control_callback disk_control_cb_{};
  bool has_disk_control_cb_ = false;
  ::retro_disk_control_ext_callback disk_control_ext_cb_{};
  bool has_disk_control_ext_cb_ = false;

  std::atomic<bool> hw_render_enabled_{false};
  std::atomic<bool> hw_render_allowed_{true};
  ::retro_hw_render_callback hw_render_cb_{};
  const retro_hw_render_interface_vulkan *vulkan_interface_ = nullptr;
  retro_hw_render_context_negotiation_interface_vulkan vulkan_negotiation_{};
  bool has_vulkan_negotiation_ = false;
  ::retro_hw_context_type hw_context_type_ = ::RETRO_HW_CONTEXT_NONE;
};

bool HandleEnvironmentCommand(EnvState &state, unsigned cmd, void *data);

// --- Global Callbacks for Static Interfaces ---
// These are needed because Libretro interfaces (Rumble, Sensor) use static C callbacks
// that don't provide a user context pointer.

using RumbleCallback = std::function<bool(unsigned port, enum retro_rumble_effect effect, uint16_t strength)>;
void SetGlobalRumbleCallback(RumbleCallback cb);

using SensorSetStateCallback = std::function<bool(unsigned port, enum retro_sensor_action action, unsigned rate)>;
using SensorGetInputCallback = std::function<float(unsigned port, unsigned id)>;
void SetGlobalSensorCallbacks(SensorSetStateCallback set_cb, SensorGetInputCallback get_cb);

using HwRenderFramebufferCallback = std::function<uintptr_t(void)>;
void SetGlobalHwRenderFramebufferCallback(HwRenderFramebufferCallback cb);

} // namespace libretro

#endif // LIBRETRO_ENV_DISPATCHER_H
