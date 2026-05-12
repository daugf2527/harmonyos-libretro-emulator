#include "temp_file_manager.h"
#include "../../common/file_utils.h"
#include <hilog/log.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstring>
#include <iostream>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "TempFileManager"
#undef LOG_FLOW
#define LOG_FLOW "Resource"
#include "../../common/log_prefix.h"

namespace libretro {

TempFileManager::TempFileManager(const std::string& filesDir) : filesDir_(filesDir) {}

bool TempFileManager::Initialize() {
    if (filesDir_.empty()) {
        return false;
    }
    if (!common::EnsureDirExists(filesDir_)) {
        return false;
    }
    return common::EnsureDirExists(filesDir_ + "/temp_roms");
}

bool TempFileManager::WriteTempRom(const std::string& rawfilePath, const std::vector<uint8_t>& data, std::string& outTempPath) {
    if (filesDir_.empty()) {
        return false;
    }

    std::string baseName = common::GetBaseName(rawfilePath);
    std::string tempPath = filesDir_ + "/temp_roms/" + baseName;
    
    // Ensure temp_roms directory exists
    std::string tempDir = filesDir_ + "/temp_roms";
    if (!common::EnsureDirExists(tempDir)) {
        LOGF(LOG_ERROR, "Failed to create temp_roms directory: %{public}s", tempDir.c_str());
        return false;
    }

    if (common::WriteFileAll(tempPath, data.data(), data.size())) {
        LOGF(LOG_INFO, "Wrote temp ROM file: %{public}s", tempPath.c_str());
        outTempPath = tempPath;
        return true;
    }

    LOGF(LOG_ERROR, "Failed to write temp ROM file: %{public}s", tempPath.c_str());
    return false;
}

bool TempFileManager::WriteDependencyFile(const std::string& relativePath, const std::string& parentTempDir, const std::vector<uint8_t>& data) {
    if (parentTempDir.empty() || relativePath.empty()) {
        return false;
    }

    if (relativePath.find("..") != std::string::npos) {
        LOGF(LOG_ERROR, "Path traversal detected in dependency path: %{public}s", relativePath.c_str());
        return false;
    }

    std::string fullPath = parentTempDir + "/" + relativePath;
    
    // Ensure parent directory of the dependency exists (handling subdirectories in relativePath)
    size_t lastSlash = fullPath.find_last_of('/');
    if (lastSlash == std::string::npos) {
        LOGF(LOG_ERROR, "No directory separator in path: %{public}s", fullPath.c_str());
        return false;
    }
    std::string dirName = fullPath.substr(0, lastSlash);
    if (!common::EnsureDirExists(dirName)) {
        LOGF(LOG_ERROR, "Failed to create dependency directory: %{public}s", dirName.c_str());
        return false;
    }

    if (common::WriteFileAll(fullPath, data.data(), data.size())) {
        LOGF(LOG_INFO, "Wrote dependency file: %{public}s", fullPath.c_str());
        return true;
    }
    
    LOGF(LOG_ERROR, "Failed to write dependency file: %{public}s", fullPath.c_str());
    return false;
}

} // namespace libretro
