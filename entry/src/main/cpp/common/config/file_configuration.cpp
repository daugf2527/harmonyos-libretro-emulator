#include "file_configuration.h"
#include "common/diagnostics/logger_provider.h"

#include <cctype>
#include <cstdio>
#include <fstream>
#include <unistd.h>

namespace common {
namespace {

std::string TrimCopy(const std::string &s) {
  size_t start = 0;
  while (start < s.size() &&
         std::isspace(static_cast<unsigned char>(s[start]))) {
    start++;
  }
  size_t end = s.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(s[end - 1]))) {
    end--;
  }
  return s.substr(start, end - start);
}

std::string StripQuotes(std::string s) {
  s = TrimCopy(s);
  if (s.size() >= 2) {
    const char a = s.front();
    const char b = s.back();
    if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
      return s.substr(1, s.size() - 2);
    }
  }
  return s;
}

std::string EscapeDoubleQuotes(const std::string &s) {
  std::string out;
  out.reserve(s.size());
  for (char c : s) {
    if (c == '"') {
      out.push_back('\\');
    }
    out.push_back(c);
  }
  return out;
}

void LogConfigFailure(const std::string &message) {
  auto *logger = diagnostics::GetLogger();
  if (!logger) {
    return;
  }
  logger->Log(interfaces::LogLevel::DEBUG, "Config", message);
}

} // namespace

bool FileConfiguration::LoadKeyValues(
    const std::string &path, std::map<std::string, std::string> &out) {
  std::ifstream in(path);
  if (!in.is_open()) {
    LogConfigFailure("Config open failed: " + path);
    return false;
  }

  std::string line;
  while (std::getline(in, line)) {
    std::string s = TrimCopy(line);
    if (s.empty()) {
      continue;
    }
    if (s[0] == '#') {
      continue;
    }
    size_t eq = s.find('=');
    if (eq == std::string::npos) {
      continue;
    }
    std::string key = TrimCopy(s.substr(0, eq));
    std::string val = StripQuotes(s.substr(eq + 1));
    if (key.empty()) {
      continue;
    }
    out[key] = val;
  }
  return true;
}

bool FileConfiguration::SaveKeyValues(
    const std::string &path,
    const std::map<std::string, std::string> &kv) {
  // 原子写入:先写临时文件,fsync 落盘,再 rename 原子替换。避免崩溃/断电
  // 时直接 fopen("wb") 把目标文件截断为空导致配置丢失。
  const std::string tmpPath = path + ".tmp";
  FILE *fp = fopen(tmpPath.c_str(), "wb");
  if (!fp) {
    LogConfigFailure("Config save failed (open tmp): " + tmpPath);
    return false;
  }

  for (const auto &it : kv) {
    const std::string escaped = EscapeDoubleQuotes(it.second);
    fprintf(fp, "%s = \"%s\"\n", it.first.c_str(), escaped.c_str());
  }

  fflush(fp);
  fsync(fileno(fp));
  fclose(fp);

  if (rename(tmpPath.c_str(), path.c_str()) != 0) {
    LogConfigFailure("Config save failed (rename): " + path);
    unlink(tmpPath.c_str());
    return false;
  }
  return true;
}

} // namespace common
