#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace libretro {

class TempFileManager {
public:
    explicit TempFileManager(const std::string& filesDir);
    bool Initialize();
    bool WriteTempRom(const std::string& rawfilePath, const std::vector<uint8_t>& data, std::string& outTempPath);
    bool WriteDependencyFile(const std::string& relativePath, const std::string& parentTempDir, const std::vector<uint8_t>& data);

private:
    std::string filesDir_;
};

} // namespace libretro
