#include "file_security.h"
#include <climits>
#include <cstdlib>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "FileSecurity"
#undef LOG_FLOW
#define LOG_FLOW "VFS"
#include "common/log_prefix.h"

namespace security {

bool ValidatePath(const std::string &inputPath,
                  const std::string &allowedRoot) {
  if (inputPath.empty() || allowedRoot.empty()) {
    LOGF(LOG_ERROR,
                 "Empty path or root provided");
    return false;
  }

  // 解析允许的根目录
  char resolvedRoot[PATH_MAX];
  char *resolvedRootPtr = realpath(allowedRoot.c_str(), resolvedRoot);

  if (!resolvedRootPtr) {
    LOGF(LOG_ERROR,
                 "realpath failed for allowed root: %s", allowedRoot.c_str());
    return false;
  }

  std::string rootStr(resolvedRoot);

  // 确保根目录以 / 结尾，避免 /data/app 匹配 /data/app2
  if (!rootStr.empty() && rootStr.back() != '/') {
    rootStr += '/';
  }

  auto IsUnderRoot = [&](const std::string &path) {
    return (path.find(rootStr) == 0) ||
           (path == rootStr.substr(0, rootStr.length() - 1));
  };

  // 解析输入路径的绝对路径（解析符号链接和 .. 等）
  char resolvedInput[PATH_MAX];
  char *resolvedInputPtr = realpath(inputPath.c_str(), resolvedInput);
  if (resolvedInputPtr) {
    return IsUnderRoot(resolvedInput);
  }

  // realpath 失败，可能是文件不存在，尝试校验父目录
  LOGF(LOG_WARN,
               "realpath failed for input: %s (may not exist yet)",
               inputPath.c_str());
  if (inputPath.find("..") != std::string::npos) {
    return false;
  }

  std::string parent = inputPath;
  while (parent.size() > 1 && parent.back() == '/') {
    parent.pop_back();
  }
  size_t lastSlash = parent.find_last_of('/');
  if (lastSlash == std::string::npos) {
    return false;
  }
  parent = (lastSlash == 0) ? "/" : parent.substr(0, lastSlash);

  char resolvedParent[PATH_MAX];
  char *resolvedParentPtr = realpath(parent.c_str(), resolvedParent);
  if (!resolvedParentPtr) {
    LOGF(LOG_ERROR,
                 "realpath failed for input parent: %s", parent.c_str());
    // 允许父目录尚不存在的路径，但必须是绝对路径且在允许根目录下
    if (inputPath[0] == '/' && inputPath.find("..") == std::string::npos &&
        IsUnderRoot(inputPath)) {
      LOGF(LOG_WARN,
           "Allowing path under root even though parent is missing: %s",
           inputPath.c_str());
      return true;
    }
    return false;
  }

  bool isValid = IsUnderRoot(resolvedParent);

  if (!isValid) {
    LOGF(LOG_ERROR,
                 "Path Traversal Detected! Input: %s, Allowed Root: %s",
                 inputPath.c_str(), resolvedRoot);
  }

  return isValid;
}

bool ValidateCorePath(const std::string &corePath) {
  if (corePath.empty()) {
    return false;
  }

  // 允许的 Core 目录列表
  const char *allowedCoreDirs[] = {
      "/data/storage/el1/bundle/libs",                 // 应用内置库
      "/data/storage/el2/base/haps/entry/files/cores", // 用户下载的核心
  };

  // 检查是否在任一允许的目录下
  for (const char *allowedDir : allowedCoreDirs) {
    if (ValidatePath(corePath, allowedDir)) {
      LOGF(LOG_INFO,
                   "Core path validated: %s", corePath.c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR,
               "Core path rejected (not in allowed directories): %s",
               corePath.c_str());
  return false;
}

bool ValidateRomPath(const std::string &romPath) {
  if (romPath.empty()) {
    return false;
  }

  // rawfile 资源路径（相对路径，以 "roms/" 开头）
  if (romPath.find("roms/") == 0 || romPath.find("./roms/") == 0) {
    // rawfile 路径不是文件系统路径，不需要 realpath 检查
    // 只需确保没有路径遍历字符
    if (romPath.find("..") != std::string::npos) {
      LOGF(LOG_ERROR,
                   "ROM rawfile path contains ..: %s", romPath.c_str());
      return false;
    }
    LOGF(LOG_INFO,
                 "ROM rawfile path validated: %s", romPath.c_str());
    return true;
  }

  // 允许的 ROM 目录
  const char *allowedRomDirs[] = {
      "/data/storage/el2/base/haps/entry/files/roms",   // 用户 ROM 目录
      "/data/storage/el2/base/haps/entry/files/system", // 系统目录（ROM 暂存）
  };

  for (const char *allowedDir : allowedRomDirs) {
    if (ValidatePath(romPath, allowedDir)) {
      LOGF(LOG_INFO,
                   "ROM file path validated: %s", romPath.c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR,
               "ROM path rejected (not in allowed directories): %s",
               romPath.c_str());
  return false;
}

} // namespace security
