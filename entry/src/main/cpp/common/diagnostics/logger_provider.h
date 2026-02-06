/*
 * Logger provider - global access point for ILogger
 */

#ifndef COMMON_DIAGNOSTICS_LOGGER_PROVIDER_H
#define COMMON_DIAGNOSTICS_LOGGER_PROVIDER_H

#include "interfaces/diagnostics/i_logger.h"

namespace diagnostics {

interfaces::ILogger *GetLogger();
void SetLogger(interfaces::ILogger *logger);

} // namespace diagnostics

#endif // COMMON_DIAGNOSTICS_LOGGER_PROVIDER_H
