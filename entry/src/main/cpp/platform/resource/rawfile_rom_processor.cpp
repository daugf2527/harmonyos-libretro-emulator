#include "rawfile_rom_processor.h"
#include "rom_loader.h"
#include "temp_file_manager.h"
#include "../../common/cue_parser.h"
#include "../../common/string_utils.h"
#include <hilog/log.h>
#include <unordered_set>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "RawfileRom"
#undef LOG_FLOW
#define LOG_FLOW "Resource"
#include "../../common/log_prefix.h"

namespace libretro {
namespace {

bool EndsWithIgnoreCase(const std::string &value, const std::string &suffix) {
  if (suffix.size() > value.size()) {
    return false;
  }
  const size_t offset = value.size() - suffix.size();
  for (size_t i = 0; i < suffix.size(); ++i) {
    char a = value[offset + i];
    char b = suffix[i];
    if (a >= 'A' && a <= 'Z') {
      a = static_cast<char>(a - 'A' + 'a');
    }
    if (b >= 'A' && b <= 'Z') {
      b = static_cast<char>(b - 'A' + 'a');
    }
    if (a != b) {
      return false;
    }
  }
  return true;
}

std::string GetDirName(const std::string &path) {
  if (path.empty()) {
    return std::string();
  }
  size_t pos = path.rfind('/');
  if (pos == std::string::npos) {
    return std::string();
  }
  if (pos == 0) {
    return std::string("/");
  }
  return path.substr(0, pos);
}

bool SanitizeCuePath(const std::string &raw, std::string &out) {
  std::string name = common::TrimCopy(raw);
  for (char &c : name) {
    if (c == '\\') {
      c = '/';
    }
  }
  if (name.empty() || name[0] == '/' ||
      name.find("..") != std::string::npos) {
    return false;
  }
  out = name;
  return true;
}

} // namespace

RawfileRomProcessor::Result RawfileRomProcessor::Process(
    const std::string &input_path,
    NativeResourceManager *resource_manager,
    const std::string &files_dir) {
  Result result;
  result.output_path = input_path;

  if (input_path.empty()) {
    result.success = true;
    return result;
  }
  if (!resource_manager) {
    result.error_message = "resource_manager_missing";
    return result;
  }

  auto load_result = ROMLoader::LoadFromRawFile(input_path, resource_manager);
  if (!load_result.success) {
    result.error_message = load_result.error_message;
    return result;
  }

  result.data =
      std::make_shared<std::vector<uint8_t>>(std::move(load_result.data));
  result.success = true;

  TempFileManager temp_mgr(files_dir);
  if (!temp_mgr.Initialize()) {
    LOGF(LOG_WARN,
         "TempFileManager failed to initialize, skip temp ROM write");
    return result;  // 内存数据已加载,直接返回,不再尝试写盘
  }

  std::string temp_path;
  if (temp_mgr.WriteTempRom(input_path, *result.data, temp_path)) {
    result.output_path = temp_path;
  }

  if (!EndsWithIgnoreCase(input_path, ".cue")) {
    return result;
  }

  if (temp_path.empty() || files_dir.empty()) {
    LOGF(LOG_WARN, "Temp ROM not available, skip CUE dependencies");
    return result;
  }

  const std::vector<std::string> referenced_files =
      common::ParseCueReferencedFiles(*result.data);
  if (referenced_files.empty()) {
    LOGF(LOG_WARN, "CUE referenced files empty: %{public}s",
         input_path.c_str());
    return result;
  }

  std::string rawfile_dir = GetDirName(input_path);
  std::string temp_dir = GetDirName(temp_path);
  if (temp_dir.empty()) {
    LOGF(LOG_WARN, "Temp ROM directory invalid, skip CUE dependencies");
    return result;
  }
  std::unordered_set<std::string> seen;

  for (const auto &raw_name : referenced_files) {
    std::string name;
    if (!SanitizeCuePath(raw_name, name)) {
      LOGF(LOG_WARN, "CUE referenced path rejected: %{public}s",
           raw_name.c_str());
      continue;
    }
    if (!seen.insert(name).second) {
      continue;
    }

    std::string ref_rawfile_path;
    if (name.rfind("roms/", 0) == 0) {
      ref_rawfile_path = name;
    } else if (!rawfile_dir.empty()) {
      ref_rawfile_path = rawfile_dir + "/" + name;
    } else {
      ref_rawfile_path = name;
    }

    auto ref_result =
        ROMLoader::LoadFromRawFile(ref_rawfile_path, resource_manager);
    if (!ref_result.success || ref_result.data.empty()) {
      LOGF(LOG_WARN, "CUE referenced file load failed: %{public}s",
           ref_rawfile_path.c_str());
      continue;
    }

    if (temp_mgr.WriteDependencyFile(name, temp_dir, ref_result.data)) {
      result.dependency_count++;
    }
  }

  if (result.dependency_count > 0) {
    LOGF(LOG_INFO, "CUE dependencies written: %{public}zu",
         result.dependency_count);
  }

  return result;
}

} // namespace libretro
