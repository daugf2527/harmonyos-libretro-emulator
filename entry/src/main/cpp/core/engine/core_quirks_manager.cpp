#include "core_quirks_manager.h"
#include <algorithm>
#include <cctype>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "CoreQuirks"
#include "../../common/log_prefix.h"

namespace libretro {

CoreQuirksManager &CoreQuirksManager::GetInstance() {
  static CoreQuirksManager instance;
  return instance;
}

void CoreQuirksManager::Reset() {
  quirks_ = {};
}

std::string CoreQuirksManager::NormalizeName(const std::string &name) {
  std::string normalized = name;
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return normalized;
}

bool CoreQuirksManager::NameMatchesToken(const std::string &name,
                                         const char *token) {
  if (!token || !*token) {
    return false;
  }
  return name.find(token) != std::string::npos;
}

const std::array<CoreQuirksManager::Rule, 1> &CoreQuirksManager::GetRules() {
  static const std::array<Rule, 1> rules = {{
      {"gambatte", {true, true}},
  }};
  return rules;
}

CoreQuirksManager::Quirks
CoreQuirksManager::GetQuirks(const std::string &library_name) {
  Quirks result;
  if (library_name.empty()) {
    return result;
  }

  const std::string normalized = NormalizeName(library_name);
  for (const auto &rule : GetRules()) {
    if (NameMatchesToken(normalized, rule.token)) {
      result.audio_sample_rate_bug =
          result.audio_sample_rate_bug || rule.quirks.audio_sample_rate_bug;
      result.audio_stereo_frame_bug =
          result.audio_stereo_frame_bug || rule.quirks.audio_stereo_frame_bug;
    }
  }
  return result;
}

void CoreQuirksManager::Detect(const retro_system_info &info) {
  Reset();
  if (!info.library_name) {
    return;
  }

  quirks_ = GetQuirks(info.library_name);
  if (quirks_.audio_stereo_frame_bug || quirks_.audio_sample_rate_bug) {
    LOGF(LOG_INFO, "Core quirks applied: %{public}s",
         info.library_name);
  }
}

} // namespace libretro
