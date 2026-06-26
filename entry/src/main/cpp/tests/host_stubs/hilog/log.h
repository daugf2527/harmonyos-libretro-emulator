#pragma once

#define LOG_DEBUG 3
#define LOG_INFO 4
#define LOG_WARN 5
#define LOG_ERROR 6
#define LOG_FATAL 7
#define LOG_APP 0

static inline int OH_LOG_Print(int, int, unsigned int, const char *, const char *,
                               ...) {
  return 0;
}
