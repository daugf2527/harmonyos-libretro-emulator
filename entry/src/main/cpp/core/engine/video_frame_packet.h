#ifndef LIBRETRO_ENGINE_VIDEO_FRAME_PACKET_H
#define LIBRETRO_ENGINE_VIDEO_FRAME_PACKET_H

#include "core/libretro/libretro.h"
#include <cstdint>
#include <memory>
#include <vector>

namespace libretro {

enum class VideoFrameKind : uint8_t {
  SOFTWARE = 0,
  NULL_FRAME = 1,
  HW_SWAP = 2,
  HW_NULL = 3,
};

struct VideoFramePacket {
  VideoFrameKind kind = VideoFrameKind::NULL_FRAME;
  uint64_t frameId = 0;
  uint64_t surfaceGeneration = 0;
  int64_t timestampUs = 0;
  unsigned width = 0;
  unsigned height = 0;
  size_t pitch = 0;
  retro_pixel_format pixelFormat = RETRO_PIXEL_FORMAT_UNKNOWN;
  bool isDupe = false;
  std::shared_ptr<std::vector<uint8_t>> storage;
};

} // namespace libretro

#endif // LIBRETRO_ENGINE_VIDEO_FRAME_PACKET_H
