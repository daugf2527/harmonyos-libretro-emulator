#include "file_utils.h"
#include "string_utils.h"
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cctype>

namespace common {

// --- File Utils ---

bool EnsureDirExists(const std::string &path) {
  if (path.empty()) {
    return false;
  }

  std::string normalized = path;
  while (normalized.size() > 1 && normalized.back() == '/') {
    normalized.pop_back();
  }
  if (normalized == "/") {
    return true;
  }

  struct stat st;
  size_t pos = (normalized[0] == '/') ? 1 : 0;
  while (true) {
    size_t next = normalized.find('/', pos);
    std::string sub = normalized.substr(0, next);
    if (!sub.empty()) {
      if (stat(sub.c_str(), &st) == 0) {
        if (!S_ISDIR(st.st_mode)) {
          return false;
        }
      } else {
        if (mkdir(sub.c_str(), 0700) != 0) {
          if (errno != EEXIST) {
            return false;
          }
          if (stat(sub.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
            return false;
          }
        }
      }
    }
    if (next == std::string::npos) {
      break;
    }
    pos = next + 1;
  }

  return true;
}

bool WriteFileAll(const std::string &path, const uint8_t *data, size_t size) {
  if (!data || size == 0) {
    return false;
  }

  FILE *fp = fopen(path.c_str(), "wb");
  if (!fp) {
    return false;
  }

  size_t written = fwrite(data, 1, size, fp);
  fclose(fp);
  return written == size;
}

std::string GetBaseName(const std::string &path) {
  size_t pos = path.find_last_of("/\\");
  if (pos == std::string::npos) {
    return path;
  }
  return path.substr(pos + 1);
}

// --- String Utils ---

std::string TrimCopy(const std::string &s) {
  size_t start = 0;
  while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
    start++;
  }
  size_t end = s.size();
  while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
    end--;
  }
  return s.substr(start, end - start);
}

void JsonEscape(const std::string &in, std::string &out) {
  out.clear();
  out.reserve(in.size());
  for (unsigned char uc : in) {
    switch (uc) {
    case '"':
      out += "\\\"";
      break;
    case '\\':
      out += "\\\\";
      break;
    case '\b':
      out += "\\b";
      break;
    case '\f':
      out += "\\f";
      break;
    case '\n':
      out += "\\n";
      break;
    case '\r':
      out += "\\r";
      break;
    case '\t':
      out += "\\t";
      break;
    default:
      if (uc < 0x20) {
        char buf[7];
        std::snprintf(buf, sizeof(buf), "\\u%04X", static_cast<unsigned>(uc));
        out += buf;
      } else {
        out.push_back(static_cast<char>(uc));
      }
      break;
    }
  }
}

} // namespace common
