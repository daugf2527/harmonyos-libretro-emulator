#pragma once
#include "libretro.h"
#include <mutex>
#include <string>
#include <vector>

// Polyfill for missing definitions in libretro.h
#ifndef RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE
#define RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE 61

struct retro_disk_control_ext_callback
{
   bool (RETRO_CALLCONV *set_eject_state)(bool ejected);
   bool (RETRO_CALLCONV *get_eject_state)(void);
   unsigned (RETRO_CALLCONV *get_image_index)(void);
   bool (RETRO_CALLCONV *set_image_index)(unsigned index);
   unsigned (RETRO_CALLCONV *get_num_images)(void);
   bool (RETRO_CALLCONV *replace_image_index)(unsigned index, const struct retro_game_info *info);
   bool (RETRO_CALLCONV *add_image_index)(void);
   bool (RETRO_CALLCONV *set_initial_image)(unsigned index, const char *path);
   bool (RETRO_CALLCONV *get_image_path)(unsigned index, char *path, size_t len);
   bool (RETRO_CALLCONV *get_image_label)(unsigned index, char *label, size_t len);
};
#endif

namespace libretro {

class DiskController {
public:
  void SetCallbacks(const retro_disk_control_ext_callback* cbs);
  // 兼容旧版回调
  void SetCallbacks(const retro_disk_control_callback* cbs);
  // T8-A-F2: core unload 前必须调用,清零悬空函数指针(指向已 dlclose 的 .so 代码段)。
  void ClearCallbacks();
  
  bool Eject();
  bool Insert();
  bool SetImageIndex(unsigned index);
  unsigned GetImageIndex() const;
  unsigned GetNumImages() const;
  bool ReplaceImageIndex(unsigned index, const std::string& path);
  bool AddImageIndex();
  bool AddImagePath(const std::string& path);
  bool IsEjected() const;
  
private:
  retro_disk_control_ext_callback callbacks_{};
  bool is_ext_ = false;
  bool ejected_ = false;
  mutable std::mutex mutex_;
};

} // namespace libretro
