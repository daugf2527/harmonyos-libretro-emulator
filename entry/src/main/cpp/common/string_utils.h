#ifndef COMMON_STRING_UTILS_H
#define COMMON_STRING_UTILS_H

#include <string>

namespace common {

std::string TrimCopy(const std::string &s);
void JsonEscape(const std::string &in, std::string &out);

} // namespace common

#endif // COMMON_STRING_UTILS_H
