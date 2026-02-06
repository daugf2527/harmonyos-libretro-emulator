#ifndef LIBRETRO_CORE_OPTIONS_REGISTRY_H
#define LIBRETRO_CORE_OPTIONS_REGISTRY_H

#include "core/libretro/libretro.h"

#include <string>
#include <vector>

namespace libretro {

class EnvState;

namespace core_options {

struct CoreOptionValue {
  std::string value;
  std::string label;
};

struct CoreOptionCategory {
  std::string key;
  std::string desc;
  std::string info;
};

struct CoreOptionDefinition {
  std::string key;
  std::string desc;
  std::string desc_categorized;
  std::string info;
  std::string info_categorized;
  std::string category_key;
  std::vector<CoreOptionValue> values;
  std::string default_value;
};

bool SetCoreOptionsV2(EnvState &state, const ::retro_core_options_v2 *opts);
bool SetCoreOptionsV1(EnvState &state, const ::retro_core_option_definition *defs);

bool SetCoreOptionValue(EnvState &state, const char *key, const char *value);

}

}

#endif
