#include "rom_loader.h"
#include "platform_resource_manager.h"
#include <filemanagement/file_uri/oh_file_uri.h>
#include <hilog/log.h>
#include <cstring>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD001
#define LOG_TAG "ROMLoader"
#undef LOG_FLOW
#define LOG_FLOW "ROM"
#include "common/log_prefix.h"

namespace libretro {

// ========== 公共接口 ==========

ROMLoadResult ROMLoader::LoadFromUri(const std::string& uri) {
    ROMLoadResult result;
    result.success = false;
    
    LOGF(LOG_INFO, "Loading ROM from URI: %{public}s", uri.c_str());
    
    // 1. URI 转路径
    std::string path = UriToPath(uri);
    if (path.empty()) {
        result.error_message = "Failed to convert URI to path";
        LOGF(LOG_ERROR, "%{public}s", result.error_message.c_str());
        return result;
    }
    
    // 2. 从路径加载
    return LoadFromPath(path);
}

ROMLoadResult ROMLoader::LoadFromPath(const std::string& path) {
    LOGF(LOG_INFO, "Loading ROM from path: %{public}s", path.c_str());
    auto *vfs = PlatformResourceManager::GetInstance();
    return LoadFromVfs(path, *vfs);
}

ROMLoadResult ROMLoader::LoadFromRawFile(
    const std::string& rawfile_path,
    NativeResourceManager* resource_manager
) {
    LOGF(LOG_INFO, "Loading ROM from rawfile: %{public}s", rawfile_path.c_str());

    if (!resource_manager) {
        ROMLoadResult result;
        result.success = false;
        result.path = rawfile_path;
        result.error_message = "Resource manager is null";
        LOGF(LOG_ERROR, "%{public}s", result.error_message.c_str());
        return result;
    }

    auto *mgr = PlatformResourceManager::GetInstance();
    mgr->Initialize(resource_manager);
    return LoadFromVfs(rawfile_path, *mgr);
}

retro_game_info ROMLoader::CreateGameInfo(
    const ROMLoadResult& result,
    bool need_fullpath
) {
    retro_game_info game_info;
    memset(&game_info, 0, sizeof(game_info));
    
    if (need_fullpath) {
        // 模式 1: 只传路径
        game_info.path = result.path.c_str();
        game_info.data = nullptr;
        game_info.size = 0;
    } else {
        // 模式 2: 传数据
        game_info.path = result.path.empty() ? nullptr : result.path.c_str();
        game_info.data = result.data.data();
        game_info.size = result.size;
    }
    
    game_info.meta = "";
    
    return game_info;
}

bool ROMLoader::ValidateROM(const uint8_t* data, size_t size) {
    // 基本验证
    if (!data || size == 0) {
        return false;
    }
    
    // 最小大小检查（至少 1KB）
    if (size < 1024) {
        LOGF(LOG_WARN, "ROM size is very small: %{public}zu bytes", size);
    }
    
    // 最大大小检查（不超过 512MB）
    if (size > 512 * 1024 * 1024) {
        LOGF(LOG_ERROR, "ROM size is too large: %{public}zu bytes", size);
        return false;
    }
    
    // 简单的内容检查：防止全零文件 (常见于下载失败或空文件占位)
    size_t check_len = (size < 1024) ? size : 1024;
    bool all_zeros = true;
    for (size_t i = 0; i < check_len; ++i) {
        if (data[i] != 0) {
            all_zeros = false;
            break;
        }
    }
    
    if (all_zeros) {
        LOGF(LOG_ERROR, "ROM content invalid: File is all zeros");
        return false;
    }
    
    // 可按需扩展校验逻辑：
    // - 检查文件头魔数
    // - 验证 CRC/校验和
    // - 检查文件格式
    
    return true;
}

// ========== 私有方法 ==========

ROMLoadResult ROMLoader::LoadFromVfs(const std::string &path,
                                     interfaces::IVirtualFileSystem &vfs) {
    ROMLoadResult result;
    result.success = false;
    result.path = path;

    if (path.empty()) {
        result.error_message = "ROM path is empty";
        LOGF(LOG_ERROR, "%{public}s", result.error_message.c_str());
        return result;
    }

    if (!vfs.ReadFile(path, result.data)) {
        result.error_message = "Failed to read ROM file";
        LOGF(LOG_ERROR, "%{public}s: %{public}s", result.error_message.c_str(), path.c_str());
        return result;
    }

    result.size = result.data.size();

    if (!ValidateROM(result.data.data(), result.size)) {
        result.error_message = "Invalid ROM file";
        LOGF(LOG_ERROR, "%{public}s", result.error_message.c_str());
        return result;
    }

    result.success = true;
    LOGF(LOG_INFO, " ROM loaded successfully: %{public}zu bytes", result.size);

    return result;
}

std::string ROMLoader::UriToPath(const std::string& uri) {
    if (uri.empty()) {
        return "";
    }
    
    // 验证 URI 格式
    unsigned int length = uri.length();
    if (!OH_FileUri_IsValidUri(uri.c_str(), length)) {
        LOGF(LOG_ERROR, "Invalid URI format: %{public}s", uri.c_str());
        return "";
    }
    
    // URI 转路径
    char* pathResult = nullptr;
    FileManagement_ErrCode ret = OH_FileUri_GetPathFromUri(uri.c_str(), length, &pathResult);
    
    if (ret != 0 || !pathResult) {
        LOGF(LOG_ERROR, "Failed to convert URI to path: %{public}d", ret);
        return "";
    }
    
    std::string path(pathResult);
    free(pathResult);  // 释放内存
    
    LOGF(LOG_INFO, "URI converted to path: %{public}s", path.c_str());
    
    return path;
}

} // namespace libretro
