/*
 * 像素格式转换器 - NEON 优化实现
 *
 * 完全遵循 Libretro 官方标准和华为鸿蒙官方规范
 *
 * 支持的格式转换:
 * 1. 0RGB1555 -> RGBA8888 (Libretro 默认格式,已废弃但需兼容)
 * 2. RGB565 -> RGBA8888 (Libretro 推荐 16位格式)
 * 3. XRGB8888 -> RGBA8888 (Libretro 推荐 32位格式)
 *
 * 性能优化:
 * - ARM NEON SIMD 指令加速 (2-3x)
 * - 批量处理 (每次 4-8 个像素)
 * - 预计算缩放映射表
 *
 * 参考文档:
 * - Libretro API:
 * https://github.com/libretro/RetroArch/blob/master/libretro-common/include/libretro.h
 * - 鸿蒙 NEON:
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/neon-guide
 * - ARM NEON:
 * https://developer.arm.com/architectures/instruction-sets/intrinsics/
 */

#include "hilog/log.h"
#include "pixel_converter.h"
#include <algorithm>
#include <vector>
#include <arm_neon.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "PixelConverter"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

// ========== 辅助函数 ==========

/**
 * 获取像素格式名称
 */
const char *PixelConverter::GetFormatName(PixelFormat format) {
  switch (format) {
  case PixelFormat::RGB0555:
    return "0RGB1555";
  case PixelFormat::RGB565:
    return "RGB565";
  case PixelFormat::XRGB8888:
    return "XRGB8888";
  case PixelFormat::RGBA8888:
    return "RGBA8888";
  case PixelFormat::BGRA8888:
    return "BGRA8888";
  case PixelFormat::UNKNOWN:
    return "UNKNOWN";
  default:
    return "INVALID";
  }
}

/**
 * 检测格式转换是否支持
 */
bool PixelConverter::IsConversionSupported(PixelFormat srcFormat,
                                           PixelFormat destFormat) {
  if (destFormat != PixelFormat::RGBA8888 && destFormat != PixelFormat::BGRA8888) {
    return false;
  }

  // 支持的源格式
  return srcFormat == PixelFormat::RGB0555 ||
         srcFormat == PixelFormat::RGB565 || srcFormat == PixelFormat::XRGB8888;
}

// ========== 格式转换实现 ==========

/**
 * XRGB8888 -> RGBA8888 转换 (NEON 优化)
 *
 * 一次处理 4 个像素 (16 字节)
 *
 * 源格式: [B0, G0, R0, X0, B1, G1, R1, X1, B2, G2, R2, X2, B3, G3, R3, X3]
 * 目标格式: [R0, G0, B0, A0, R1, G1, B1, A1, R2, G2, B2, A2, R3, G3, B3, A3]
 */
static void ConvertXRGB8888ToRGBA8888_NEON(const uint8_t *src, uint32_t *dest,
                                           size_t pixelCount) {
  size_t i = 0;

  // 每次处理 4 个像素 (16 字节)
  for (; i + 4 <= pixelCount; i += 4) {
    // 加载 4 个 XRGB8888 像素 (16 字节)
    uint8x16_t srcPixels = vld1q_u8(src + i * 4);

    // 提取各个通道
    // srcPixels: [B0, G0, R0, X0, B1, G1, R1, X1, ...]

    // 方法 1: 使用 vtbl (查表) 指令重排字节
    // 创建查表索引: [2, 1, 0, 255, 6, 5, 4, 255, 10, 9, 8, 255, 14, 13, 12,
    // 255] 这会将 [B, G, R, X] 重排为 [R, G, B, 0xFF]

    const uint8_t indices[16] = {
        2,  1,  0,  255, // 像素 0: R0, G0, B0, 0xFF
        6,  5,  4,  255, // 像素 1: R1, G1, B1, 0xFF
        10, 9,  8,  255, // 像素 2: R2, G2, B2, 0xFF
        14, 13, 12, 255  // 像素 3: R3, G3, B3, 0xFF
    };

    uint8x16_t indexVec = vld1q_u8(indices);

    // 使用 vqtbl1q_u8 进行字节重排
    // 注意: 索引 255 会被替换为 0,我们后面会设置为 0xFF
    uint8x16_t result = vqtbl1q_u8(srcPixels, indexVec);

    // 设置 Alpha 通道为 0xFF
    // 创建 Alpha 掩码: [0, 0, 0, 0xFF, 0, 0, 0, 0xFF, ...]
    const uint8_t alphaMask[16] = {0, 0, 0, 0xFF, 0, 0, 0, 0xFF,
                                   0, 0, 0, 0xFF, 0, 0, 0, 0xFF};
    uint8x16_t alphaMaskVec = vld1q_u8(alphaMask);

    // 使用 OR 操作设置 Alpha
    result = vorrq_u8(result, alphaMaskVec);

    // 存储 4 个 RGBA8888 像素
    vst1q_u8((uint8_t *)(dest + i), result);
  }

  // 处理剩余像素 (标量代码)
  for (; i < pixelCount; i++) {
    uint8_t b = src[i * 4 + 0];
    uint8_t g = src[i * 4 + 1];
    uint8_t r = src[i * 4 + 2];
    dest[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
  }
}

static void ConvertRGB565ToBGRA8888_NEON(const uint16_t *src, uint32_t *dest,
                                         size_t pixelCount) {
  size_t i = 0;

  for (; i + 8 <= pixelCount; i += 8) {
    uint16x8_t pixels = vld1q_u16(src + i);

    uint16x8_t r5 = vshrq_n_u16(pixels, 11);
    uint16x8_t g6 = vshrq_n_u16(vshlq_n_u16(pixels, 5), 10);
    uint16x8_t b5 = vandq_u16(pixels, vdupq_n_u16(0x1F));

    uint16x8_t r8 = vshlq_n_u16(r5, 3);
    r8 = vorrq_u16(r8, vshrq_n_u16(r5, 2));

    uint16x8_t g8 = vshlq_n_u16(g6, 2);
    g8 = vorrq_u16(g8, vshrq_n_u16(g6, 4));

    uint16x8_t b8 = vshlq_n_u16(b5, 3);
    b8 = vorrq_u16(b8, vshrq_n_u16(b5, 2));

    uint8x8_t r = vmovn_u16(r8);
    uint8x8_t g = vmovn_u16(g8);
    uint8x8_t b = vmovn_u16(b8);
    uint8x8_t a = vdup_n_u8(0xFF);

    uint8x8x4_t bgra;
    bgra.val[0] = b;
    bgra.val[1] = g;
    bgra.val[2] = r;
    bgra.val[3] = a;
    vst4_u8((uint8_t *)(dest + i), bgra);
  }

  for (; i < pixelCount; i++) {
    uint16_t pixel = src[i];
    uint32_t r = (pixel >> 11) & 0x1F;
    uint32_t g = (pixel >> 5) & 0x3F;
    uint32_t b = pixel & 0x1F;

    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);

    dest[i] = (0xFFu << 24) | (r << 16) | (g << 8) | b;
  }
}

static void Convert0RGB1555ToBGRA8888_NEON(const uint16_t *src, uint32_t *dest,
                                           size_t pixelCount) {
  size_t i = 0;

  for (; i + 8 <= pixelCount; i += 8) {
    uint16x8_t pixels = vld1q_u16(src + i);

    uint16x8_t r5 = vshrq_n_u16(pixels, 10);
    uint16x8_t g5 = vshrq_n_u16(vshlq_n_u16(pixels, 5), 11);
    uint16x8_t b5 = vandq_u16(pixels, vdupq_n_u16(0x1F));

    uint16x8_t r8 = vshlq_n_u16(r5, 3);
    uint16x8_t g8 = vshlq_n_u16(g5, 3);
    uint16x8_t b8 = vshlq_n_u16(b5, 3);

    r8 = vorrq_u16(r8, vshrq_n_u16(r5, 2));
    g8 = vorrq_u16(g8, vshrq_n_u16(g5, 2));
    b8 = vorrq_u16(b8, vshrq_n_u16(b5, 2));

    uint8x8_t r = vmovn_u16(r8);
    uint8x8_t g = vmovn_u16(g8);
    uint8x8_t b = vmovn_u16(b8);
    uint8x8_t a = vdup_n_u8(0xFF);

    uint8x8x4_t bgra;
    bgra.val[0] = b;
    bgra.val[1] = g;
    bgra.val[2] = r;
    bgra.val[3] = a;
    vst4_u8((uint8_t *)(dest + i), bgra);
  }

  for (; i < pixelCount; i++) {
    uint16_t pixel = src[i];
    uint32_t r = (pixel >> 10) & 0x1F;
    uint32_t g = (pixel >> 5) & 0x1F;
    uint32_t b = pixel & 0x1F;

    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);

    dest[i] = (0xFFu << 24) | (r << 16) | (g << 8) | b;
  }
}

static void ConvertXRGB8888ToBGRA8888_NEON(const uint8_t *src, uint32_t *dest,
                                           size_t pixelCount) {
  size_t i = 0;

  for (; i + 4 <= pixelCount; i += 4) {
    uint8x16_t srcPixels = vld1q_u8(src + i * 4);

    const uint8_t indices[16] = {
        0,  1,  2,  255,
        4,  5,  6,  255,
        8,  9,  10, 255,
        12, 13, 14, 255,
    };
    uint8x16_t indexVec = vld1q_u8(indices);
    uint8x16_t result = vqtbl1q_u8(srcPixels, indexVec);

    const uint8_t alphaMask[16] = {0, 0, 0, 0xFF, 0, 0, 0, 0xFF,
                                   0, 0, 0, 0xFF, 0, 0, 0, 0xFF};
    uint8x16_t alphaMaskVec = vld1q_u8(alphaMask);
    result = vorrq_u8(result, alphaMaskVec);
    vst1q_u8((uint8_t *)(dest + i), result);
  }

  for (; i < pixelCount; i++) {
    uint8_t b = src[i * 4 + 0];
    uint8_t g = src[i * 4 + 1];
    uint8_t r = src[i * 4 + 2];
    dest[i] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
              (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
  }
}

/**
 * 0RGB1555 -> RGBA8888 转换 (NEON 优化)
 *
 * Libretro 默认格式，已废弃但需兼容
 * 格式: [0RRRRRGGGGGBBBBB] (15位)
 * 一次处理 8 个像素
 */
static void Convert0RGB1555ToRGBA8888_NEON(const uint16_t *src, uint32_t *dest,
                                           size_t pixelCount) {
  size_t i = 0;

  // 每次处理 8 个像素
  for (; i + 8 <= pixelCount; i += 8) {
    // 加载 8 个 0RGB1555 像素 (16 字节)
    uint16x8_t pixels = vld1q_u16(src + i);

    // 提取 R, G, B 分量 (5-5-5)
    uint16x8_t r5 = vshrq_n_u16(pixels, 10); // 右移 10 位,得到 R (5位)
    uint16x8_t g5 = vshrq_n_u16(vshlq_n_u16(pixels, 5), 11); // 提取 G (5位)
    uint16x8_t b5 = vandq_u16(pixels, vdupq_n_u16(0x1F)); // 掩码提取 B (5位)

    // 扩展到 8 位
    uint16x8_t r8 = vshlq_n_u16(r5, 3); // 5位 -> 8位 (左移 3)
    uint16x8_t g8 = vshlq_n_u16(g5, 3); // 5位 -> 8位 (左移 3)
    uint16x8_t b8 = vshlq_n_u16(b5, 3); // 5位 -> 8位 (左移 3)

    // 复制高位到低位 (提高精度)
    r8 = vorrq_u16(r8, vshrq_n_u16(r5, 2));
    g8 = vorrq_u16(g8, vshrq_n_u16(g5, 2));
    b8 = vorrq_u16(b8, vshrq_n_u16(b5, 2));

    // 转换为 8 位
    uint8x8_t r = vmovn_u16(r8);
    uint8x8_t g = vmovn_u16(g8);
    uint8x8_t b = vmovn_u16(b8);
    uint8x8_t a = vdup_n_u8(0xFF);

    // 交错存储为 RGBA
    uint8x8x4_t rgba;
    rgba.val[0] = r;
    rgba.val[1] = g;
    rgba.val[2] = b;
    rgba.val[3] = a;

    vst4_u8((uint8_t *)(dest + i), rgba);
  }

  // 处理剩余像素
  for (; i < pixelCount; i++) {
    uint16_t pixel = src[i];
    uint32_t r = (pixel >> 10) & 0x1F;
    uint32_t g = (pixel >> 5) & 0x1F;
    uint32_t b = pixel & 0x1F;

    // 5-bit to 8-bit expansion
    r = (r << 3) | (r >> 2);
    g = (g << 3) | (g >> 2);
    b = (b << 3) | (b >> 2);

    dest[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
  }
}

/**
 * RGB565 -> RGBA8888 转换 (NEON 优化)
 *
 * 格式: [RRRRRGGGGGGBBBBB] (16位)
 * 一次处理 8 个像素
 */
static void ConvertRGB565ToRGBA8888_NEON(const uint16_t *src, uint32_t *dest,
                                         size_t pixelCount) {
  size_t i = 0;

  // 每次处理 8 个像素
  for (; i + 8 <= pixelCount; i += 8) {
    // 加载 8 个 RGB565 像素 (16 字节)
    uint16x8_t pixels = vld1q_u16(src + i);

    // 提取 R, G, B 分量
    uint16x8_t r5 = vshrq_n_u16(pixels, 11);                     // R (5位)
    uint16x8_t g6 = vshrq_n_u16(vshlq_n_u16(pixels, 5), 10);     // G (6位)
    uint16x8_t b5 = vandq_u16(pixels, vdupq_n_u16(0x1F));        // B (5位)

    // 扩展到 8 位
    // R (5->8): << 3 | >> 2
    uint16x8_t r8 = vshlq_n_u16(r5, 3);
    r8 = vorrq_u16(r8, vshrq_n_u16(r5, 2));

    // G (6->8): << 2 | >> 4
    uint16x8_t g8 = vshlq_n_u16(g6, 2);
    g8 = vorrq_u16(g8, vshrq_n_u16(g6, 4));

    // B (5->8): << 3 | >> 2
    uint16x8_t b8 = vshlq_n_u16(b5, 3);
    b8 = vorrq_u16(b8, vshrq_n_u16(b5, 2));

    // 转换为 8 位
    uint8x8_t r = vmovn_u16(r8);
    uint8x8_t g = vmovn_u16(g8);
    uint8x8_t b = vmovn_u16(b8);
    uint8x8_t a = vdup_n_u8(0xFF);

    // 交错存储为 RGBA
    uint8x8x4_t rgba;
    rgba.val[0] = r;
    rgba.val[1] = g;
    rgba.val[2] = b;
    rgba.val[3] = a;

    vst4_u8((uint8_t *)(dest + i), rgba);
  }

  // 处理剩余像素
  for (; i < pixelCount; i++) {
    uint16_t pixel = src[i];
    uint32_t r = (pixel >> 11) & 0x1F;
    uint32_t g = (pixel >> 5) & 0x3F;
    uint32_t b = pixel & 0x1F;

    // 5/6-bit to 8-bit expansion
    r = (r << 3) | (r >> 2);
    g = (g << 2) | (g >> 4);
    b = (b << 3) | (b >> 2);

    dest[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
  }
}

/**
 * 带缩放的像素转换 (NEON 优化)
 *
 * 优化策略:
 * 1. 预计算缩放映射表 (避免浮点除法)
 * 2. 使用 NEON 处理每一行
 */
static void ConvertAndScaleXRGB8888_NEON(const uint8_t *srcData,
                                         unsigned srcWidth, unsigned srcHeight,
                                         size_t srcPitch, uint32_t *destData,
                                         unsigned destWidth,
                                         unsigned destHeight,
                                         unsigned destStride,
                                         bool outputBgra) {
  // 计算缩放比例
  float scaleX = static_cast<float>(srcWidth) / destWidth;
  float scaleY = static_cast<float>(srcHeight) / destHeight;

  // 预计算 X 轴映射表 (避免浮点除法)
  // 优化: 使用 thread_local vector 避免每帧分配
  static thread_local std::vector<uint32_t> xMappingVec;
  if (xMappingVec.size() < destWidth) {
    xMappingVec.resize(destWidth);
  }
  uint32_t *xMapping = xMappingVec.data();

  for (unsigned x = 0; x < destWidth; x++) {
    xMapping[x] = static_cast<unsigned>(x * scaleX);
  }

  // 逐行处理
  for (unsigned dstY = 0; dstY < destHeight; dstY++) {
    unsigned srcY = static_cast<unsigned>(dstY * scaleY);
    if (srcY >= srcHeight)
      continue;

    const uint8_t *srcRow = srcData + srcY * srcPitch;
    uint32_t *destRow = destData + dstY * destStride;

    // 使用 NEON 处理每一行
    unsigned dstX = 0;

    // 每次处理 4 个像素
    for (; dstX + 4 <= destWidth; dstX += 4) {
      // 收集 4 个源像素
      uint8_t srcPixels[16]; // 4 个 XRGB8888 像素

      for (int i = 0; i < 4; i++) {
        unsigned srcX = xMapping[dstX + i];
        if (srcX < srcWidth) {
          const uint8_t *srcPixel = srcRow + srcX * 4;
          srcPixels[i * 4 + 0] = srcPixel[0]; // B
          srcPixels[i * 4 + 1] = srcPixel[1]; // G
          srcPixels[i * 4 + 2] = srcPixel[2]; // R
          srcPixels[i * 4 + 3] = srcPixel[3]; // X
        } else {
          // 边界外,填充黑色
          srcPixels[i * 4 + 0] = 0;
          srcPixels[i * 4 + 1] = 0;
          srcPixels[i * 4 + 2] = 0;
          srcPixels[i * 4 + 3] = 0;
        }
      }

      if (outputBgra) {
        ConvertXRGB8888ToBGRA8888_NEON(srcPixels, destRow + dstX, 4);
      } else {
        ConvertXRGB8888ToRGBA8888_NEON(srcPixels, destRow + dstX, 4);
      }
    }

    // 处理剩余像素
    for (; dstX < destWidth; dstX++) {
      unsigned srcX = xMapping[dstX];
      if (srcX < srcWidth) {
        const uint8_t *srcPixel = srcRow + srcX * 4;
        uint8_t b = srcPixel[0];
        uint8_t g = srcPixel[1];
        uint8_t r = srcPixel[2];
        if (outputBgra) {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(b);
        } else {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(r);
        }
      }
    }
  }

}

/**
 * 带缩放的 0RGB1555 转换
 */
static void ConvertAndScale0RGB1555_NEON(const uint8_t *srcData,
                                         unsigned srcWidth, unsigned srcHeight,
                                         size_t srcPitch, uint32_t *destData,
                                         unsigned destWidth,
                                         unsigned destHeight,
                                         unsigned destStride,
                                         bool outputBgra) {
  // 计算缩放比例
  float scaleX = static_cast<float>(srcWidth) / destWidth;
  float scaleY = static_cast<float>(srcHeight) / destHeight;

  // 预计算 X 轴映射表
  // 优化: 使用 thread_local vector 避免每帧分配
  static thread_local std::vector<uint32_t> xMappingVec;
  if (xMappingVec.size() < destWidth) {
    xMappingVec.resize(destWidth);
  }
  uint32_t *xMapping = xMappingVec.data();

  for (unsigned x = 0; x < destWidth; x++) {
    xMapping[x] = static_cast<unsigned>(x * scaleX);
  }

  // 逐行处理
  for (unsigned dstY = 0; dstY < destHeight; dstY++) {
    unsigned srcY = static_cast<unsigned>(dstY * scaleY);
    if (srcY >= srcHeight)
      continue;

    const uint16_t *srcRow =
        reinterpret_cast<const uint16_t *>(srcData + srcY * srcPitch);
    uint32_t *destRow = destData + dstY * destStride;

    // 每次处理 8 个像素
    unsigned dstX = 0;
    for (; dstX + 8 <= destWidth; dstX += 8) {
      uint16_t srcPixels[8];
      for (int i = 0; i < 8; i++) {
        unsigned srcX = xMapping[dstX + i];
        srcPixels[i] = (srcX < srcWidth) ? srcRow[srcX] : 0;
      }
      if (outputBgra) {
        Convert0RGB1555ToBGRA8888_NEON(srcPixels, destRow + dstX, 8);
      } else {
        Convert0RGB1555ToRGBA8888_NEON(srcPixels, destRow + dstX, 8);
      }
    }

    // 处理剩余像素
    for (; dstX < destWidth; dstX++) {
      unsigned srcX = xMapping[dstX];
      if (srcX < srcWidth) {
        uint16_t pixel = srcRow[srcX];
        uint8_t r = ((pixel >> 10) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x1F) << 3;
        uint8_t b = (pixel & 0x1F) << 3;
        r |= r >> 5;
        g |= g >> 5;
        b |= b >> 5;
        if (outputBgra) {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(b);
        } else {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(r);
        }
      }
    }
  }

}

/**
 * 带缩放的 RGB565 转换
 */
static void ConvertAndScaleRGB565_NEON(const uint8_t *srcData,
                                       unsigned srcWidth, unsigned srcHeight,
                                       size_t srcPitch, uint32_t *destData,
                                       unsigned destWidth, unsigned destHeight,
                                       unsigned destStride,
                                       bool outputBgra) {
  // 计算缩放比例
  float scaleX = static_cast<float>(srcWidth) / destWidth;
  float scaleY = static_cast<float>(srcHeight) / destHeight;

  // 预计算 X 轴映射表
  // 优化: 使用 thread_local vector 避免每帧分配
  static thread_local std::vector<uint32_t> xMappingVec;
  if (xMappingVec.size() < destWidth) {
    xMappingVec.resize(destWidth);
  }
  uint32_t *xMapping = xMappingVec.data();

  for (unsigned x = 0; x < destWidth; x++) {
    xMapping[x] = static_cast<unsigned>(x * scaleX);
  }

  // 逐行处理
  for (unsigned dstY = 0; dstY < destHeight; dstY++) {
    unsigned srcY = static_cast<unsigned>(dstY * scaleY);
    if (srcY >= srcHeight)
      continue;

    const uint16_t *srcRow =
        reinterpret_cast<const uint16_t *>(srcData + srcY * srcPitch);
    uint32_t *destRow = destData + dstY * destStride;

    // 每次处理 8 个像素
    unsigned dstX = 0;
    for (; dstX + 8 <= destWidth; dstX += 8) {
      uint16_t srcPixels[8];
      for (int i = 0; i < 8; i++) {
        unsigned srcX = xMapping[dstX + i];
        srcPixels[i] = (srcX < srcWidth) ? srcRow[srcX] : 0;
      }
      if (outputBgra) {
        ConvertRGB565ToBGRA8888_NEON(srcPixels, destRow + dstX, 8);
      } else {
        ConvertRGB565ToRGBA8888_NEON(srcPixels, destRow + dstX, 8);
      }
    }

    // 处理剩余像素
    for (; dstX < destWidth; dstX++) {
      unsigned srcX = xMapping[dstX];
      if (srcX < srcWidth) {
        uint16_t pixel = srcRow[srcX];
        uint8_t r = ((pixel >> 11) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x3F) << 2;
        uint8_t b = (pixel & 0x1F) << 3;
        r |= r >> 5;
        g |= g >> 6;
        b |= b >> 5;
        if (outputBgra) {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(b);
        } else {
          destRow[dstX] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                          (static_cast<uint32_t>(g) << 8) |
                          static_cast<uint32_t>(r);
        }
      }
    }
  }

}

// ========== 公共接口实现 ==========

void PixelConverter::ConvertAndScale(const void *srcData, PixelFormat srcFormat,
                                     unsigned srcWidth, unsigned srcHeight,
                                     size_t srcPitch, void *destData,
                                     PixelFormat destFormat, unsigned destWidth,
                                     unsigned destHeight, unsigned destStride) {
  static uint64_t convertLogCount = 0;
  convertLogCount++;
  struct ConvertLogKey {
    PixelFormat srcFormat;
    PixelFormat destFormat;
    unsigned srcWidth;
    unsigned srcHeight;
    size_t srcPitch;
    unsigned destWidth;
    unsigned destHeight;
    unsigned destStride;
  };

  static ConvertLogKey lastKey{
      PixelFormat::RGBA8888, PixelFormat::RGBA8888, 0, 0, 0, 0, 0, 0,
  };

  ConvertLogKey key{srcFormat, destFormat, srcWidth,   srcHeight,
                    srcPitch,  destWidth,  destHeight, destStride};

  const bool changed = (key.srcFormat != lastKey.srcFormat) ||
                       (key.destFormat != lastKey.destFormat) ||
                       (key.srcWidth != lastKey.srcWidth) ||
                       (key.srcHeight != lastKey.srcHeight) ||
                       (key.srcPitch != lastKey.srcPitch) ||
                       (key.destWidth != lastKey.destWidth) ||
                       (key.destHeight != lastKey.destHeight) ||
                       (key.destStride != lastKey.destStride);

  const bool shouldLog = (convertLogCount <= 3) || changed;

  if (changed) {
    lastKey = key;
  }

  if (shouldLog) {
    LOGF(LOG_INFO, "像素转换: %{public}s -> %{public}s (%{public}ux%{public}u -> %{public}ux%{public}u)",
                GetFormatName(srcFormat), GetFormatName(destFormat), srcWidth,
                srcHeight, destWidth, destHeight);
  }

  // 检查是否支持该转换
  if (!IsConversionSupported(srcFormat, destFormat)) {
    LOGF(LOG_ERROR, " 不支持的像素格式转换: %{public}s -> %{public}s",
                 GetFormatName(srcFormat), GetFormatName(destFormat));
    return;
  }

  const bool outputBgra = (destFormat == PixelFormat::BGRA8888);

  // 根据源格式选择转换函数
  switch (srcFormat) {
  case PixelFormat::RGB0555:
    if (shouldLog) {
      LOGF(LOG_INFO, " 使用 0RGB1555 转换 (Libretro 默认格式)");
    }
    ConvertAndScale0RGB1555_NEON(static_cast<const uint8_t *>(srcData), srcWidth,
                                 srcHeight, srcPitch,
                                 static_cast<uint32_t *>(destData), destWidth,
                                 destHeight, destStride, outputBgra);
    break;

  case PixelFormat::RGB565:
    if (shouldLog) {
      LOGF(LOG_INFO, " 使用 RGB565 转换 (Libretro 推荐 16位格式)");
    }
    ConvertAndScaleRGB565_NEON(static_cast<const uint8_t *>(srcData), srcWidth,
                               srcHeight, srcPitch,
                               static_cast<uint32_t *>(destData), destWidth,
                               destHeight, destStride, outputBgra);
    break;

  case PixelFormat::XRGB8888:
    if (shouldLog) {
      LOGF(LOG_INFO, " 使用 XRGB8888 转换 (Libretro 推荐 32位格式)");
    }
    ConvertAndScaleXRGB8888_NEON(static_cast<const uint8_t *>(srcData), srcWidth,
                                 srcHeight, srcPitch,
                                 static_cast<uint32_t *>(destData), destWidth,
                                 destHeight, destStride, outputBgra);
    break;

  default:
    LOGF(LOG_ERROR, " 未知的源格式");
    break;
  }
}

void PixelConverter::Convert(const void *srcData, PixelFormat srcFormat,
                             void *destData, PixelFormat destFormat,
                             size_t pixelCount) {
  // 检查是否支持该转换
  if (!IsConversionSupported(srcFormat, destFormat)) {
    LOGF(LOG_ERROR, " 不支持的像素格式转换: %{public}s -> %{public}s",
                 GetFormatName(srcFormat), GetFormatName(destFormat));
    return;
  }

  const bool outputBgra = (destFormat == PixelFormat::BGRA8888);

  switch (srcFormat) {
  case PixelFormat::RGB0555:
    if (outputBgra) {
      Convert0RGB1555ToBGRA8888_NEON(static_cast<const uint16_t *>(srcData),
                                     static_cast<uint32_t *>(destData),
                                     pixelCount);
    } else {
      Convert0RGB1555ToRGBA8888_NEON(static_cast<const uint16_t *>(srcData),
                                     static_cast<uint32_t *>(destData),
                                     pixelCount);
    }
    break;

  case PixelFormat::RGB565:
    if (outputBgra) {
      ConvertRGB565ToBGRA8888_NEON(static_cast<const uint16_t *>(srcData),
                                   static_cast<uint32_t *>(destData),
                                   pixelCount);
    } else {
      ConvertRGB565ToRGBA8888_NEON(static_cast<const uint16_t *>(srcData),
                                   static_cast<uint32_t *>(destData),
                                   pixelCount);
    }
    break;

  case PixelFormat::XRGB8888:
    if (outputBgra) {
      ConvertXRGB8888ToBGRA8888_NEON(static_cast<const uint8_t *>(srcData),
                                     static_cast<uint32_t *>(destData),
                                     pixelCount);
    } else {
      ConvertXRGB8888ToRGBA8888_NEON(static_cast<const uint8_t *>(srcData),
                                     static_cast<uint32_t *>(destData),
                                     pixelCount);
    }
    break;

  default:
    LOGF(LOG_ERROR, " 未知的源格式");
    break;
  }
}

bool PixelConverter::IsNeonSupported() {
  // arm64-v8a 默认支持 NEON
  return true;
}

const char *PixelConverter::GetImplementation() { return "NEON"; }

} // namespace libretro
