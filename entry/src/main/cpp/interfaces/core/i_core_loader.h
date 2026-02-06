/*
 * Libretro Core加载器接口
 *
 * 设计原则:
 * - 符合Libretro规范的动态加载流程
 * - 可测试: 可注入MockCoreLoader用于测试
 */

#ifndef INTERFACES_I_CORE_LOADER_H
#define INTERFACES_I_CORE_LOADER_H

#include "core/libretro/retro_common.h"
#include <string>

namespace interfaces {

/**
 * @brief Libretro Core加载器接口
 */
class ICoreLoader {
public:
  virtual ~ICoreLoader() = default;

  /**
   * @brief 加载Libretro Core
   * @param core_path .so文件路径
   * @return true 加载成功，false 失败
   */
  virtual bool LoadCore(const std::string &core_path) = 0;

  /**
   * @brief 卸载当前Core
   */
  virtual void UnloadCore() = 0;

  /**
   * @brief 检查Core是否已加载
   */
  virtual bool IsLoaded() const = 0;

  // Libretro API函数指针获取（按官方顺序）
  virtual retro_init_t GetInit() const = 0;
  virtual retro_deinit_t GetDeinit() const = 0;
  virtual retro_run_t GetRun() const = 0;
  virtual retro_reset_t GetReset() const = 0;
  virtual retro_load_game_t GetLoadGame() const = 0;
  virtual retro_unload_game_t GetUnloadGame() const = 0;
  virtual retro_get_system_info_t GetSystemInfo() const = 0;
  virtual retro_get_system_av_info_t GetSystemAvInfo() const = 0;
  virtual retro_set_environment_t GetSetEnvironment() const = 0;
  virtual retro_set_video_refresh_t GetSetVideoRefresh() const = 0;
  virtual retro_set_audio_sample_batch_t GetSetAudioSampleBatch() const = 0;
  virtual retro_set_input_poll_t GetSetInputPoll() const = 0;
  virtual retro_set_input_state_t GetSetInputState() const = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_CORE_LOADER_H
