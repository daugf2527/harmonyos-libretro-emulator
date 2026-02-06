/*
 * File-backed configuration implementation
 */

#ifndef COMMON_CONFIG_FILE_CONFIGURATION_H
#define COMMON_CONFIG_FILE_CONFIGURATION_H

#include "interfaces/config/i_configuration.h"

namespace common {

class FileConfiguration : public interfaces::IConfiguration {
public:
  bool LoadKeyValues(const std::string &path,
                     std::map<std::string, std::string> &out) override;
  bool SaveKeyValues(const std::string &path,
                     const std::map<std::string, std::string> &kv) override;
};

} // namespace common

#endif // COMMON_CONFIG_FILE_CONFIGURATION_H
