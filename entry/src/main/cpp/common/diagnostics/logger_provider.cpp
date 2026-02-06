#include "logger_provider.h"

#include <atomic>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD004

namespace diagnostics {
namespace {

class HilogLogger : public interfaces::ILogger {
public:
  void Log(interfaces::LogLevel level, const char *tag,
           const std::string &message) override {
    const char *safe_tag = (tag && tag[0] != '\0') ? tag : "Logger";
    const LogLevel pri = ToHilogLevel(level);
    OH_LOG_Print(LOG_APP, pri, LOG_DOMAIN, safe_tag, "%{public}s",
                 message.c_str());
  }

private:
  static LogLevel ToHilogLevel(interfaces::LogLevel level) {
    switch (level) {
    case interfaces::LogLevel::DEBUG:
      return LOG_DEBUG;
    case interfaces::LogLevel::INFO:
      return LOG_INFO;
    case interfaces::LogLevel::WARN:
      return LOG_WARN;
    case interfaces::LogLevel::ERROR:
      return LOG_ERROR;
    default:
      return LOG_INFO;
    }
  }
};

HilogLogger g_default_logger;
std::atomic<interfaces::ILogger *> g_logger{&g_default_logger};

} // namespace

interfaces::ILogger *GetLogger() { return g_logger.load(); }

void SetLogger(interfaces::ILogger *logger) {
  if (logger) {
    g_logger.store(logger);
  }
}

} // namespace diagnostics
