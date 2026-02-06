/*
 * Libretro Core Loader for HarmonyOS
 * Dynamically loads and manages Libretro cores (.so files)
 * Phase 3 implementation placeholder
 */
#ifndef CORE_LOADER_H
#define CORE_LOADER_H

#include "../../interfaces/core/i_core_loader.h" // 1. 引入接口
#include "retro_common.h"                        // 同一目录下的文件
#include <string>

class CoreLoader : public interfaces::ICoreLoader { // 2. 继承接口
public:
  CoreLoader() = default;
  ~CoreLoader() override;

  // ICoreLoader 接口实现
  bool LoadCore(const std::string &corePath) override;
  void UnloadCore() override;
  bool IsLoaded() const override { return coreHandle_ != nullptr; }

  // Get core function pointers (按官方 libretro.h 顺序)
  retro_init_t GetInit() const override { return retro_init_; }
  retro_deinit_t GetDeinit() const override { return retro_deinit_; }
  // retro_api_version_t 是接口未定义的额外方法，不标 override
  retro_api_version_t GetApiVersion() const { return retro_api_version_; }

  retro_get_system_info_t GetSystemInfo() const override {
    return retro_get_system_info_;
  }
  retro_get_system_av_info_t GetSystemAvInfo() const override {
    return retro_get_system_av_info_;
  }
  retro_set_environment_t GetSetEnvironment() const override {
    return retro_set_environment_;
  }
  retro_set_video_refresh_t GetSetVideoRefresh() const override {
    return retro_set_video_refresh_;
  }
  // GetSetAudioSample 是额外方法
  retro_set_audio_sample_t GetSetAudioSample() const {
    return retro_set_audio_sample_;
  }
  retro_set_audio_sample_batch_t GetSetAudioSampleBatch() const override {
    return retro_set_audio_sample_batch_;
  }
  retro_set_input_poll_t GetSetInputPoll() const override {
    return retro_set_input_poll_;
  }
  retro_set_input_state_t GetSetInputState() const override {
    return retro_set_input_state_;
  }
  retro_set_controller_port_device_t GetSetControllerPortDevice() const {
    return retro_set_controller_port_device_;
  }
  retro_reset_t GetReset() const override { return retro_reset_; }
  retro_run_t GetRun() const override { return retro_run_; }
  retro_serialize_size_t GetSerializeSize() const {
    return retro_serialize_size_;
  }
  retro_serialize_t GetSerialize() const { return retro_serialize_; }
  retro_unserialize_t GetUnserialize() const { return retro_unserialize_; }
  retro_cheat_reset_t GetCheatReset() const { return retro_cheat_reset_; }
  retro_cheat_set_t GetCheatSet() const { return retro_cheat_set_; }
  retro_load_game_t GetLoadGame() const override { return retro_load_game_; }
  retro_load_game_special_t GetLoadGameSpecial() const {
    return retro_load_game_special_;
  }
  retro_unload_game_t GetUnloadGame() const override {
    return retro_unload_game_;
  }
  retro_get_region_t GetGetRegion() const { return retro_get_region_; }
  retro_get_memory_data_t GetGetMemoryData() const {
    return retro_get_memory_data_;
  }
  retro_get_memory_size_t GetGetMemorySize() const {
    return retro_get_memory_size_;
  }

  const std::string &GetLastErrorStep() const { return lastErrorStep_; }
  const std::string &GetLastErrorMessage() const { return lastErrorMessage_; }

private:
  void *coreHandle_ = nullptr;

  bool recordError_ = true;
  std::string lastErrorStep_;
  std::string lastErrorMessage_;

  void SetLastError(const std::string &step, const std::string &message) {
    lastErrorStep_ = step;
    lastErrorMessage_ = message;
  }

  // Core function pointers (按官方 libretro.h 顺序定义)
  // 生命周期函数 (必需)
  retro_init_t retro_init_ = nullptr;
  retro_deinit_t retro_deinit_ = nullptr;
  retro_api_version_t retro_api_version_ = nullptr;
  retro_get_system_info_t retro_get_system_info_ = nullptr;
  retro_get_system_av_info_t retro_get_system_av_info_ = nullptr;

  // 回调设置函数 (必需)
  retro_set_environment_t retro_set_environment_ = nullptr;
  retro_set_video_refresh_t retro_set_video_refresh_ = nullptr;
  retro_set_audio_sample_t retro_set_audio_sample_ = nullptr;
  retro_set_audio_sample_batch_t retro_set_audio_sample_batch_ = nullptr;
  retro_set_input_poll_t retro_set_input_poll_ = nullptr;
  retro_set_input_state_t retro_set_input_state_ = nullptr;
  retro_set_controller_port_device_t retro_set_controller_port_device_ =
      nullptr;

  // 游戏控制函数 (必需)
  retro_reset_t retro_reset_ = nullptr;
  retro_run_t retro_run_ = nullptr;

  // Save State 函数 (可选)
  retro_serialize_size_t retro_serialize_size_ = nullptr;
  retro_serialize_t retro_serialize_ = nullptr;
  retro_unserialize_t retro_unserialize_ = nullptr;

  // Cheat 函数 (可选)
  retro_cheat_reset_t retro_cheat_reset_ = nullptr;
  retro_cheat_set_t retro_cheat_set_ = nullptr;

  // 游戏加载函数 (必需)
  retro_load_game_t retro_load_game_ = nullptr;
  retro_load_game_special_t retro_load_game_special_ = nullptr;
  retro_unload_game_t retro_unload_game_ = nullptr;

  // 其他函数 (可选)
  retro_get_region_t retro_get_region_ = nullptr;
  retro_get_memory_data_t retro_get_memory_data_ = nullptr;
  retro_get_memory_size_t retro_get_memory_size_ = nullptr;

  // Helper: Load a function symbol from the core
  template <typename T> bool LoadSymbol(T &func, const char *name);
};

#endif // CORE_LOADER_H
