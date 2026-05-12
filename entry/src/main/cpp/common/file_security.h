#ifndef COMMON_FILE_SECURITY_H_
#define COMMON_FILE_SECURITY_H_

#include <string>

namespace security {

/**
 * @brief 验证路径是否在允许的根目录下（防止路径遍历攻击）
 * @param inputPath 用户提供的路径
 * @param allowedRoot 允许的根目录
 * @return true 如果路径安全，false 如果检测到路径遍历
 */
bool ValidatePath(const std::string &inputPath, const std::string &allowedRoot);

/**
 * @brief 验证 Libretro Core 文件路径
 *
 * 只允许从以下目录加载：
 * - /data/storage/el1/bundle/libs/ (应用内置库)
 * - /data/storage/el2/base/haps/entry/files/cores/ (用户下载的核心)
 *
 * @param corePath Core 文件路径
 * @return true 如果路径合法
 */
bool ValidateCorePath(const std::string &corePath);

/**
 * @brief 验证 ROM 文件路径
 *
 * 只允许从以下路径加载：
 * - roms/ (rawfile 资源，不需要完整路径)
 * - /data/storage/el2/base/haps/entry/files/roms/ (用户 ROM)
 * - /data/storage/el2/base/haps/entry/files/system/ (ROM 暂存目录)
 * - /data/storage/el2/base/haps/entry/files/temp_roms/ (rawfile 解包临时目录)
 *
 * @param romPath ROM 文件路径
 * @return true 如果路径合法
 */
bool ValidateRomPath(const std::string &romPath);

} // namespace security

#endif // COMMON_FILE_SECURITY_H_
