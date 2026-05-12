#ifndef ROM_LOADER_H
#define ROM_LOADER_H

#include "core/libretro/retro_common.h"
#include "interfaces/vfs/i_virtual_file_system.h"
#include <cstdint>
#include <string>
#include <vector>

// 前向声明
struct NativeResourceManager;

namespace libretro {

/**
 * ROM 加载结果
 */
struct ROMLoadResult {
  bool success = false;      // 是否成功
  std::string error_message; // 错误信息
  std::vector<uint8_t> data; // ROM 数据
  std::string path;          // ROM 路径
  size_t size = 0;           // ROM 大小
};

/**
 * ROM 加载器
 */
class ROMLoader {
public:
  /**
   * 从 FileUri 加载 ROM
   * @param uri 文件 URI（来自文件选择器）
   * @return 加载结果
   */
  static ROMLoadResult LoadFromUri(const std::string &uri);

  /**
   * 从沙箱路径加载 ROM
   * @param path 沙箱路径
   * @return 加载结果
   */
  static ROMLoadResult LoadFromPath(const std::string &path);

  /**
   * 从 RawFile 加载内置 ROM
   * @param rawfile_path rawfile 路径（如 "roms/2048.rom"）
   * @param resource_manager 资源管理器
   * @return 加载结果
   */
  static ROMLoadResult LoadFromRawFile(const std::string &rawfile_path,
                                       NativeResourceManager *resource_manager);

  /**
   * 创建 retro_game_info 结构体
   * @param result ROM 加载结果
   * @param need_fullpath 核心是否需要完整路径
   * @return retro_game_info 结构体
   */
  static retro_game_info CreateGameInfo(const ROMLoadResult &result,
                                        bool need_fullpath);

  /**
   * 验证 ROM 文件
   * @param data ROM 数据
   * @param size ROM 大小
   * @return 是否有效
   */
  static bool ValidateROM(const uint8_t *data, size_t size);

private:
  /**
   * 通过虚拟文件系统读取 ROM
   * @param path 文件路径
   * @param vfs 文件系统接口
   * @return ROM 加载结果
   */
  static ROMLoadResult LoadFromVfs(const std::string &path,
                                   interfaces::IVirtualFileSystem &vfs);

  /**
   * URI 转路径
   * @param uri 文件 URI
   * @return 沙箱路径
   */
  static std::string UriToPath(const std::string &uri);
};

} // namespace libretro

#endif // ROM_LOADER_H
