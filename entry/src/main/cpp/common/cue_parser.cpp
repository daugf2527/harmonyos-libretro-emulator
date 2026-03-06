#include "cue_parser.h"
#include "string_utils.h"
#include <algorithm>
#include <cctype>
#include <sstream>

namespace common {

std::vector<std::string> ParseCueReferencedFiles(const std::vector<uint8_t>& cueData) {
    std::vector<std::string> files;
    if (cueData.empty()) {
        return files;
    }

    // Convert data to string stream for line-by-line processing
    std::string content(reinterpret_cast<const char*>(cueData.data()), cueData.size());
    std::istringstream stream(content);
    std::string line;

    while (std::getline(stream, line)) {
        // Trim whitespace
        std::string trimmed = TrimCopy(line);
        if (trimmed.empty()) {
            continue;
        }

        // Check if line starts with "FILE" (case-insensitive)
        std::string upper = trimmed;
        std::transform(upper.begin(), upper.end(), upper.begin(),
                       [](unsigned char c) {
                         return static_cast<char>(std::toupper(c));
                       });
        if (upper.rfind("FILE", 0) == 0 &&
            (upper.size() == 4 || std::isspace(static_cast<unsigned char>(upper[4])))) {
            // Format: FILE "filename.bin" BINARY
            // or: FILE filename.bin BINARY
            
            // Skip "FILE" and following whitespace
            size_t pos = 4;
            while (pos < trimmed.size() &&
                   std::isspace(static_cast<unsigned char>(trimmed[pos]))) {
                pos++;
            }
            
            if (pos >= trimmed.size()) {
                continue;
            }

            std::string filename;
            if (trimmed[pos] == '"') {
                // Quoted filename
                size_t endQuote = trimmed.find('"', pos + 1);
                if (endQuote != std::string::npos) {
                    filename = trimmed.substr(pos + 1, endQuote - pos - 1);
                }
            } else {
                // Unquoted filename, read until next space
                size_t endSpace = trimmed.find(' ', pos);
                if (endSpace != std::string::npos) {
                    filename = trimmed.substr(pos, endSpace - pos);
                } else {
                    filename = trimmed.substr(pos);
                }
            }

            if (!filename.empty()) {
                files.push_back(filename);
            }
        }
    }

    return files;
}

} // namespace common
