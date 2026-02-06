#ifndef LIBRETRO_ENGINE_CORE_QUIRKS_MANAGER_H
#define LIBRETRO_ENGINE_CORE_QUIRKS_MANAGER_H

#include "../libretro/libretro.h"
#include <array>
#include <string>

namespace libretro {

/**
 * @brief 管理核心特定的兼容性问题（Quirks）
 * 避免在 LibretroEngine 中硬编码特定核心的逻辑
 */
class CoreQuirksManager {
public:
  struct Quirks {
    bool audio_stereo_frame_bug = false; // Gambatte: Stereo samples reported as frames
    bool audio_sample_rate_bug = false; // Gambatte: System clock reported as sample rate
  };

  struct Rule {
    const char *token;
    Quirks quirks;
  };

  static CoreQuirksManager &GetInstance();

  void Detect(const retro_system_info &info);
  static Quirks GetQuirks(const std::string &library_name);
  const Quirks &Get() const { return quirks_; }
  void Reset();

private:
  CoreQuirksManager() = default;
  static std::string NormalizeName(const std::string &name);
  static bool NameMatchesToken(const std::string &name,
                               const char *token);
  static const std::array<Rule, 1> &GetRules();
  Quirks quirks_;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_CORE_QUIRKS_MANAGER_H
