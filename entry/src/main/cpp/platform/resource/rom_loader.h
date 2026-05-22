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
   * 创建 retro_game_info 结构体。
   *
   * **重要 - 生命周期契约**:
   * 返回的 retro_game_info 内 `.path` / `.data` 是指向 `result` 内部缓冲区的
   * **裸指针**,本函数不持有所有权。调用方 **必须保证 `result` 在 retro_load_game
   * 返回前持续存活**,否则核心将访问悬空内存。
   *
   * 典型正确用法:
   *   ROMLoadResult result = ... ;        // 调用方栈/堆变量
   *   auto info = ROMLoader::CreateGameInfo(result, need_fullpath);
   *   bool ok = core.retro_load_game(&info);   // result 仍在作用域内
   *
   * @param result ROM 加载结果(必须比返回值存活更久)
   * @param need_fullpath 核心是否需要完整路径
   * @return retro_game_info 结构体(含指向 result 内部数据的裸指针)
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
