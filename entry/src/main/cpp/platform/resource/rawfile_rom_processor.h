#ifndef RAWFILE_ROM_PROCESSOR_H
#define RAWFILE_ROM_PROCESSOR_H

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

struct NativeResourceManager;

namespace libretro {

class RawfileRomProcessor {
public:
  struct Result {
    bool success = false;
    std::string error_message;
    std::string output_path;
    std::shared_ptr<std::vector<uint8_t>> data;
    size_t dependency_count = 0;
  };

  static Result Process(const std::string &input_path,
                        NativeResourceManager *resource_manager,
                        const std::string &files_dir);
};

} // namespace libretro

#endif // RAWFILE_ROM_PROCESSOR_H
