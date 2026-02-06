#include "disk_controller.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD001
#undef LOG_TAG
#define LOG_TAG "DiskController"
#include "common/log_prefix.h"

namespace libretro {

void DiskController::SetCallbacks(const retro_disk_control_ext_callback* cbs) {
  if (cbs) {
    callbacks_ = *cbs;
    is_ext_ = true;
    LOGF(LOG_INFO, "Disk control interface (EXT) registered");
  }
}

void DiskController::SetCallbacks(const retro_disk_control_callback* cbs) {
  if (cbs) {
    callbacks_.set_eject_state = cbs->set_eject_state;
    callbacks_.get_eject_state = cbs->get_eject_state;
    callbacks_.get_image_index = cbs->get_image_index;
    callbacks_.set_image_index = cbs->set_image_index;
    callbacks_.get_num_images = cbs->get_num_images;
    callbacks_.replace_image_index = cbs->replace_image_index;
    callbacks_.add_image_index = cbs->add_image_index;
    is_ext_ = false;
    LOGF(LOG_INFO, "Disk control interface (Legacy) registered");
  }
}

bool DiskController::Eject() {
  if (!callbacks_.set_eject_state) return false;
  bool success = callbacks_.set_eject_state(true);
  if (success) ejected_ = true;
  return success;
}

bool DiskController::Insert() {
  if (!callbacks_.set_eject_state) return false;
  bool success = callbacks_.set_eject_state(false);
  if (success) ejected_ = false;
  return success;
}

bool DiskController::SetImageIndex(unsigned index) {
  if (!callbacks_.set_image_index) return false;
  return callbacks_.set_image_index(index);
}

unsigned DiskController::GetImageIndex() const {
  if (!callbacks_.get_image_index) return 0;
  return callbacks_.get_image_index();
}

unsigned DiskController::GetNumImages() const {
  if (!callbacks_.get_num_images) return 0;
  return callbacks_.get_num_images();
}

bool DiskController::ReplaceImageIndex(unsigned index, const std::string& path) {
  if (!callbacks_.replace_image_index) return false;
  struct retro_game_info info = {0};
  info.path = path.empty() ? nullptr : path.c_str();
  return callbacks_.replace_image_index(index, &info);
}

bool DiskController::AddImageIndex() {
  if (!callbacks_.add_image_index) return false;
  return callbacks_.add_image_index();
}

bool DiskController::AddImagePath(const std::string& path) {
  if (!callbacks_.add_image_index) return false;

  // 添加一个新槽位
  if (!callbacks_.add_image_index()) {
    return false;
  }

  // 如果提供了路径，则替换该槽位的内容
  if (!path.empty() && callbacks_.replace_image_index) {
    if (!callbacks_.get_num_images) {
      LOGF(LOG_WARN, "DiskController: get_num_images callback missing");
      return false;
    }
    unsigned numImages = callbacks_.get_num_images();
    if (numImages == 0) {
      LOGF(LOG_WARN, "DiskController: get_num_images returned 0 after add");
      return false;
    }
    unsigned newIndex = numImages - 1;
    struct retro_game_info info = {0};
    info.path = path.c_str();
    return callbacks_.replace_image_index(newIndex, &info);
  }

  return true;
}

} // namespace libretro
