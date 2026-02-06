/*
 * Logger interface - decouple logging backend from core components
 */

#ifndef INTERFACES_DIAGNOSTICS_I_LOGGER_H
#define INTERFACES_DIAGNOSTICS_I_LOGGER_H

#include <string>

namespace interfaces {

enum class LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
};

class ILogger {
public:
  virtual ~ILogger() = default;
  virtual void Log(LogLevel level, const char *tag,
                   const std::string &message) = 0;
};

} // namespace interfaces

#endif // INTERFACES_DIAGNOSTICS_I_LOGGER_H
