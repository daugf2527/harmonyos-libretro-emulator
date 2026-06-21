#ifndef COMMON_FILE_SECURITY_H_
#define COMMON_FILE_SECURITY_H_

#include <string>

namespace security {

/**
 * @brief 返回可公开打印的路径描述，不包含完整目录或文件名。
 *
 * 用于日志与用户可见错误消息，避免泄露沙箱绝对路径、导入文件名或用户目录。
 * 结果仅保留路径类别与安全扩展名，例如 absolute:ext=.gb 或 rawfile:ext=.gba。
 */
std::string DescribePathForLog(const std::string &path);

/**
 * @brief 返回可公开展示的错误信息，移除绝对路径/相对路径细节。
 *
 * 用于 dlopen/dlsym/文件系统错误向 ArkTS 或日志透出前的脱敏。
 */
std::string SanitizeErrorMessageForLog(const std::string &message);

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
 * - /data/storage/el1/bundle/entry/libs/ (Stage bundleCodeDir/libs)
 * - /data/storage/el2/base/haps/entry/libs/ (Stage 代码目录)
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
 * - /data/storage/el2/base/haps/entry/files/roms/ (用户 ROM 目录，含 builtin/imported/temp 子目录)
 * - /data/storage/el2/base/haps/entry/files/system/ (ROM 暂存目录)
 *
 * @param romPath ROM 文件路径
 * @return true 如果路径合法
 */
bool ValidateRomPath(const std::string &romPath);

/**
 * @brief 验证磁盘镜像文件路径
 *
 * 允许普通 ROM 目录与运行时导入的多盘镜像目录。
 *
 * @param diskImagePath 磁盘镜像文件路径
 * @return true 如果路径合法
 */
bool ValidateDiskImagePath(const std::string &diskImagePath);

/**
 * @brief 验证引擎文件根目录
 *
 * 只允许使用应用沙箱 files 根目录，避免核心 system/save 路径被指向沙箱外。
 *
 * @param filesDir ArkTS context.filesDir
 * @return true 如果路径合法
 */
bool ValidateFilesDir(const std::string &filesDir);

} // namespace security

#endif // COMMON_FILE_SECURITY_H_
