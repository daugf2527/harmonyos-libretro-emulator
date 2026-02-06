/*
 * Configuration interface - abstract key-value config I/O
 */

#ifndef INTERFACES_CONFIG_I_CONFIGURATION_H
#define INTERFACES_CONFIG_I_CONFIGURATION_H

#include <map>
#include <string>

namespace interfaces {

class IConfiguration {
public:
  virtual ~IConfiguration() = default;
  virtual bool LoadKeyValues(const std::string &path,
                             std::map<std::string, std::string> &out) = 0;
  virtual bool SaveKeyValues(
      const std::string &path,
      const std::map<std::string, std::string> &kv) = 0;
};

} // namespace interfaces

#endif // INTERFACES_CONFIG_I_CONFIGURATION_H
