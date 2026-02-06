#include "core_options_registry.h"

#include "env_dispatcher.h"
#include "common/config/file_configuration.h"

#include <cctype>
#include <map>
#include <string>
#include <utility>

namespace libretro {
namespace core_options {

static common::FileConfiguration &GetConfig() {
  static common::FileConfiguration config;
  return config;
}

static bool LoadCoreOptionsConfig(const std::string &path,
                                  std::map<std::string, std::string> &out) {
  return GetConfig().LoadKeyValues(path, out);
}

static bool SaveCoreOptionsConfig(const std::string &path,
                                  const std::map<std::string, std::string> &kv) {
  return GetConfig().SaveKeyValues(path, kv);
}

static bool HasValue(const std::vector<CoreOptionValue> &values, const std::string &v) {
  for (const auto &item : values) {
    if (item.value == v) {
      return true;
    }
  }
  return false;
}

static std::vector<CoreOptionValue>
CopyCoreOptionValues(const ::retro_core_option_value *values) {
  std::vector<CoreOptionValue> out;
  if (!values) {
    return out;
  }
  for (unsigned i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX; i++) {
    const char *v = values[i].value;
    const char *l = values[i].label;
    if (!v) {
      break;
    }
    CoreOptionValue item;
    item.value = v;
    item.label = l ? l : "";
    out.push_back(std::move(item));
  }
  return out;
}

static std::vector<CoreOptionCategory>
CopyCoreOptionCategories(const ::retro_core_option_v2_category *cats) {
  std::vector<CoreOptionCategory> out;
  if (!cats) {
    return out;
  }
  for (unsigned i = 0;; i++) {
    const char *key = cats[i].key;
    if (!key) {
      break;
    }
    CoreOptionCategory cat;
    cat.key = key;
    cat.desc = cats[i].desc ? cats[i].desc : "";
    cat.info = cats[i].info ? cats[i].info : "";
    out.push_back(std::move(cat));
  }
  return out;
}

static std::vector<CoreOptionDefinition>
CopyCoreOptionDefinitionsV2(const ::retro_core_option_v2_definition *defs) {
  std::vector<CoreOptionDefinition> out;
  if (!defs) {
    return out;
  }
  for (unsigned i = 0;; i++) {
    const char *key = defs[i].key;
    if (!key) {
      break;
    }
    CoreOptionDefinition d;
    d.key = key;
    d.desc = defs[i].desc ? defs[i].desc : "";
    d.desc_categorized = defs[i].desc_categorized ? defs[i].desc_categorized : "";
    d.info = defs[i].info ? defs[i].info : "";
    d.info_categorized = defs[i].info_categorized ? defs[i].info_categorized : "";
    d.category_key = defs[i].category_key ? defs[i].category_key : "";
    d.values = CopyCoreOptionValues(defs[i].values);
    d.default_value = defs[i].default_value ? defs[i].default_value : "";
    out.push_back(std::move(d));
  }
  return out;
}

static std::vector<CoreOptionDefinition>
CopyCoreOptionDefinitionsV1(const ::retro_core_option_definition *defs) {
  std::vector<CoreOptionDefinition> out;
  if (!defs) {
    return out;
  }
  for (unsigned i = 0;; i++) {
    const char *key = defs[i].key;
    if (!key) {
      break;
    }
    CoreOptionDefinition d;
    d.key = key;
    d.desc = defs[i].desc ? defs[i].desc : "";
    d.info = defs[i].info ? defs[i].info : "";
    d.values = CopyCoreOptionValues(defs[i].values);
    d.default_value = defs[i].default_value ? defs[i].default_value : "";
    out.push_back(std::move(d));
  }
  return out;
}

static void ApplyCoreOptionValues(EnvState &state,
                                  const std::vector<CoreOptionDefinition> &defs) {
  std::map<std::string, std::string> cfg;
  (void)LoadCoreOptionsConfig(state.GetCoreOptionsConfigPath(), cfg);

  bool touched = false;
  for (const auto &d : defs) {
    if (d.key.empty() || d.values.empty()) {
      continue;
    }

    std::string effective;
    auto it = cfg.find(d.key);
    if (it != cfg.end() && HasValue(d.values, it->second)) {
      effective = it->second;
    } else if (!d.default_value.empty() && HasValue(d.values, d.default_value)) {
      effective = d.default_value;
    } else {
      effective = d.values.front().value;
    }

    if (!effective.empty()) {
      state.SetVariable(d.key.c_str(), effective.c_str());
      cfg[d.key] = effective;
      touched = true;
    }
  }

  (void)state.ConsumeVariableUpdated();

  if (touched && !state.GetCoreOptionsConfigPath().empty()) {
    (void)SaveCoreOptionsConfig(state.GetCoreOptionsConfigPath(), cfg);
  }
}

static const CoreOptionDefinition *FindDefinitionByKey(
    const std::vector<CoreOptionDefinition> &defs, const char *key) {
  if (!key) {
    return nullptr;
  }
  for (const auto &d : defs) {
    if (d.key == key) {
      return &d;
    }
  }
  return nullptr;
}

bool SetCoreOptionsV2(EnvState &state, const ::retro_core_options_v2 *opts) {
  if (!opts) {
    state.ClearCoreOptions();
    return true;
  }
  state.SetCoreOptions(CopyCoreOptionCategories(opts->categories),
                       CopyCoreOptionDefinitionsV2(opts->definitions));
  ApplyCoreOptionValues(state, state.GetCoreOptionDefinitions());
  return true;
}

bool SetCoreOptionsV1(EnvState &state, const ::retro_core_option_definition *defs) {
  if (!defs) {
    state.ClearCoreOptions();
    return true;
  }
  state.SetCoreOptions({}, CopyCoreOptionDefinitionsV1(defs));
  ApplyCoreOptionValues(state, state.GetCoreOptionDefinitions());
  return true;
}

bool SetCoreOptionValue(EnvState &state, const char *key, const char *value) {
  if (!key || !value) {
    return false;
  }

  const CoreOptionDefinition *def =
      FindDefinitionByKey(state.GetCoreOptionDefinitions(), key);
  if (!def) {
    return false;
  }
  if (!HasValue(def->values, value)) {
    return false;
  }

  if (!state.SetVariable(key, value)) {
    return false;
  }

  const std::string &path = state.GetCoreOptionsConfigPath();
  if (!path.empty()) {
    std::map<std::string, std::string> cfg;
    (void)LoadCoreOptionsConfig(path, cfg);
    cfg[key] = value;
    (void)SaveCoreOptionsConfig(path, cfg);
  }

  return true;
}

}
}
