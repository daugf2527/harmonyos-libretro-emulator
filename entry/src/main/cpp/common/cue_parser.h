#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace common {

std::vector<std::string> ParseCueReferencedFiles(const std::vector<uint8_t>& cueData);

} // namespace common
