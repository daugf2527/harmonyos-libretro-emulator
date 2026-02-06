#pragma once

#ifndef LOG_FLOW
#define LOG_FLOW "General"
#endif

#ifndef LOG_PREFIX_FMT
#define LOG_PREFIX_FMT "【%{public}s】【%{public}s】 "
#endif

#ifndef LOGF
#define LOGF(level, fmt, ...)                                                \
  OH_LOG_Print(LOG_APP, level, LOG_DOMAIN, LOG_TAG, LOG_PREFIX_FMT fmt,      \
               LOG_TAG, LOG_FLOW, ##__VA_ARGS__)
#endif
