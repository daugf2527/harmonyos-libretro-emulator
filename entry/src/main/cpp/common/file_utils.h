#ifndef COMMON_FILE_UTILS_H
#define COMMON_FILE_UTILS_H

#include <string>
#include <cstdint>

namespace common {

bool EnsureDirExists(const std::string &path);
bool WriteFileAll(const std::string &path, const uint8_t *data, size_t size);
std::string GetBaseName(const std::string &path);

} // namespace common

#endif // COMMON_FILE_UTILS_H
