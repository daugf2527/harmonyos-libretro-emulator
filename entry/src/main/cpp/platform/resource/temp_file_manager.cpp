#include "temp_file_manager.h"
#include "../../common/file_utils.h"
#include <hilog/log.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstring>
#include <iostream>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD032
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
    // Create roms/builtin for persistent built-in ROM storage
    if (!common::EnsureDirExists(filesDir_ + "/roms")) {
        return false;
    }
    if (!common::EnsureDirExists(filesDir_ + "/roms/builtin")) {
        return false;
    }
    // Keep temp_roms for backward compatibility during migration
    return common::EnsureDirExists(filesDir_ + "/temp_roms");
}

bool TempFileManager::WriteTempRom(const std::string& rawfilePath, const std::vector<uint8_t>& data, std::string& outTempPath) {
    if (filesDir_.empty()) {
        return false;
    }

    std::string baseName = common::GetBaseName(rawfilePath);
    // Use roms/builtin for persistent storage (M1.2)
    std::string builtinPath = filesDir_ + "/roms/builtin/" + baseName;

    // Check if already extracted (use access() to check file existence)
    if (access(builtinPath.c_str(), F_OK) == 0) {
        LOGF(LOG_INFO, "Built-in ROM already exists: %{public}s", builtinPath.c_str());
        outTempPath = builtinPath;
        return true;
    }

    // Ensure builtin directory exists
    std::string builtinDir = filesDir_ + "/roms/builtin";
    if (!common::EnsureDirExists(builtinDir)) {
        LOGF(LOG_ERROR, "Failed to create builtin directory: %{public}s", builtinDir.c_str());
        return false;
    }

    if (common::WriteFileAll(builtinPath, data.data(), data.size())) {
        LOGF(LOG_INFO, "Wrote built-in ROM file: %{public}s", builtinPath.c_str());
        outTempPath = builtinPath;
        return true;
    }

    LOGF(LOG_ERROR, "Failed to write built-in ROM file: %{public}s", builtinPath.c_str());
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
