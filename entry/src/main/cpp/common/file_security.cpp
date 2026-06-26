#include "file_security.h"
#include <cerrno>
#include <cctype>
#include <climits>
#include <cstdlib>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD051
#undef LOG_TAG
#define LOG_TAG "FileSecurity"
#undef LOG_FLOW
#define LOG_FLOW "VFS"
#include "common/log_prefix.h"

namespace security {
namespace {

bool LooksLikePathToken(const std::string &token) {
  if (token.empty()) {
    return false;
  }
  if (token[0] == '/' || token.find("/data/") != std::string::npos ||
      token.find("/storage/") != std::string::npos ||
      token.find("roms/") != std::string::npos ||
      token.find('\\') != std::string::npos) {
    return true;
  }
  return token.find('/') != std::string::npos && token.find('.') != std::string::npos;
}

std::string TrimPathToken(const std::string &token, std::string &suffix) {
  size_t begin = 0;
  size_t end = token.size();
  while (begin < end && std::ispunct(static_cast<unsigned char>(token[begin])) != 0 &&
         token[begin] != '/' && token[begin] != '\\' && token[begin] != '.') {
    ++begin;
  }
  while (end > begin &&
         std::ispunct(static_cast<unsigned char>(token[end - 1])) != 0 &&
         token[end - 1] != '/' && token[end - 1] != '\\') {
    suffix.insert(suffix.begin(), token[end - 1]);
    --end;
  }
  return token.substr(begin, end - begin);
}

} // namespace

std::string DescribePathForLog(const std::string &path) {
  if (path.empty()) {
    return "<empty>";
  }

  size_t pos = path.find_last_of("/\\");
  const std::string name =
      (pos == std::string::npos) ? path : path.substr(pos + 1);
  std::string ext = "no_ext";
  const size_t dot = name.find_last_of('.');
  if (dot != std::string::npos && dot + 1 < name.size() && dot > 0 &&
      name.size() - dot <= 16) {
    bool safe = true;
    for (size_t i = dot + 1; i < name.size(); ++i) {
      const unsigned char c = static_cast<unsigned char>(name[i]);
      if (std::isalnum(c) == 0 && c != '_' && c != '-') {
        safe = false;
        break;
      }
    }
    if (safe) {
      ext = std::string("ext=") + name.substr(dot);
    }
  }

  if (path.find("roms/") == 0 || path.find("./roms/") == 0) {
    return std::string("rawfile:") + ext;
  }
  if (!path.empty() && path[0] == '/') {
    return std::string("absolute:") + ext;
  }
  return std::string("relative:") + ext;
}

std::string SanitizeErrorMessageForLog(const std::string &message) {
  if (message.empty()) {
    return "unknown";
  }
  std::string result;
  std::string token;
  auto FlushToken = [&]() {
    if (token.empty()) {
      return;
    }
    std::string suffix;
    const std::string core = TrimPathToken(token, suffix);
    if (LooksLikePathToken(core)) {
      result += DescribePathForLog(core);
      result += suffix;
    } else {
      result += token;
    }
    token.clear();
  };

  for (char ch : message) {
    if (std::isspace(static_cast<unsigned char>(ch)) != 0) {
      FlushToken();
      result += ch;
    } else {
      token += ch;
    }
  }
  FlushToken();
  return result.empty() ? "unknown" : result;
}

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
                 "realpath failed for allowed root: %{public}s",
                 DescribePathForLog(allowedRoot).c_str());
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

  const int realpathErrno = errno;
  const bool targetMayNotExist =
      realpathErrno == ENOENT || realpathErrno == ENOTDIR;

  // realpath 失败，可能是文件不存在，尝试校验父目录
  if (inputPath.find("..") != std::string::npos) {
    LOGF(LOG_ERROR,
         "Path rejected due to traversal marker in unresolved input: %{public}s",
         DescribePathForLog(inputPath).c_str());
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
    if (!targetMayNotExist) {
      LOGF(LOG_WARN,
           "realpath failed for input and parent: input=%{public}s parent=%{public}s errno=%{public}d",
           DescribePathForLog(inputPath).c_str(),
           DescribePathForLog(parent).c_str(), realpathErrno);
    }
    // 允许父目录尚不存在的路径，但必须是绝对路径且在允许根目录下
    if (inputPath[0] == '/' && inputPath.find("..") == std::string::npos &&
        IsUnderRoot(inputPath)) {
      LOGF(LOG_INFO,
           "Allowing unresolved path under root: %{public}s",
           DescribePathForLog(inputPath).c_str());
      return true;
    }
    return false;
  }

  bool isValid = IsUnderRoot(resolvedParent);

  if (!isValid) {
    LOGF(LOG_ERROR,
                 "Path Traversal Detected! Input: %{public}s, Allowed Root: %{public}s",
                 DescribePathForLog(inputPath).c_str(),
                 DescribePathForLog(resolvedRoot).c_str());
  } else if (!targetMayNotExist) {
    LOGF(LOG_WARN,
         "realpath failed for input but parent is valid: %{public}s errno=%{public}d",
         DescribePathForLog(inputPath).c_str(), realpathErrno);
  }

  return isValid;
}

bool ValidateCorePath(const std::string &corePath) {
  if (corePath.empty()) {
    return false;
  }

  // 只允许应用打包目录中的 native core。用户可写 core 目录必须等签名/哈希校验
  // 与隔离策略落地后再开放，否则等价于加载未受信任 native 代码。
  const char *allowedCoreDirs[] = {
      "/data/storage/el1/bundle/libs",                 // 应用内置库
      "/data/storage/el1/bundle/entry/libs",           // Stage 模式 bundleCodeDir/libs
      "/data/storage/el2/base/haps/entry/libs",        // Stage 模式代码目录（新系统机型）
  };

  // 检查是否在任一允许的目录下
  for (const char *allowedDir : allowedCoreDirs) {
    if (ValidatePath(corePath, allowedDir)) {
      LOGF(LOG_INFO,
                   "Core path validated: %{public}s",
                   DescribePathForLog(corePath).c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR,
               "Core path rejected (not in allowed directories): %{public}s",
               DescribePathForLog(corePath).c_str());
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
                   "ROM rawfile path contains ..: %{public}s",
                   DescribePathForLog(romPath).c_str());
      return false;
    }
    LOGF(LOG_INFO,
                 "ROM rawfile path validated: %{public}s",
                 DescribePathForLog(romPath).c_str());
    return true;
  }

  // 允许的 ROM 目录
  const char *allowedRomDirs[] = {
      "/data/storage/el2/base/haps/entry/files/roms",   // 用户 ROM 目录（含 builtin/imported/temp 子目录）
      "/data/storage/el2/base/haps/entry/files/system", // 系统目录（ROM 暂存）
  };

  for (const char *allowedDir : allowedRomDirs) {
    if (ValidatePath(romPath, allowedDir)) {
      LOGF(LOG_INFO,
                   "ROM file path validated: %{public}s",
                   DescribePathForLog(romPath).c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR,
               "ROM path rejected (not in allowed directories): %{public}s",
               DescribePathForLog(romPath).c_str());
  return false;
}

bool ValidateDiskImagePath(const std::string &diskImagePath) {
  if (diskImagePath.empty()) {
    return false;
  }

  if (ValidateRomPath(diskImagePath)) {
    return true;
  }

  const char *allowedDiskImageDirs[] = {
      "/data/storage/el2/base/haps/entry/files/runtime/disks",
  };

  for (const char *allowedDir : allowedDiskImageDirs) {
    if (ValidatePath(diskImagePath, allowedDir)) {
      LOGF(LOG_INFO,
           "Disk image path validated: %{public}s",
           DescribePathForLog(diskImagePath).c_str());
      return true;
    }
  }

  LOGF(LOG_ERROR,
       "Disk image path rejected (not in allowed directories): %{public}s",
       DescribePathForLog(diskImagePath).c_str());
  return false;
}

bool ValidateFilesDir(const std::string &filesDir) {
  if (filesDir.empty()) {
    return false;
  }

  const char *allowedFilesRoot = "/data/storage/el2/base/haps/entry/files";
  if (ValidatePath(filesDir, allowedFilesRoot)) {
    LOGF(LOG_INFO,
         "Files dir validated: %{public}s", DescribePathForLog(filesDir).c_str());
    return true;
  }

  LOGF(LOG_ERROR,
       "Files dir rejected (not in allowed directory): %{public}s",
       DescribePathForLog(filesDir).c_str());
  return false;
}

} // namespace security
