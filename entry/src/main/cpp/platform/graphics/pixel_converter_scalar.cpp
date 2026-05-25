/*
 * 像素格式转换器 - 标量实现 (备份)
 * 
 * 使用标准 C++ 代码实现像素转换
 * 作为 NEON 优化版本的备份和性能对比基准
 */

#include "pixel_converter.h"
#include "hilog/log.h"
#include <algorithm>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD00F
#define LOG_TAG "PixelConverter"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

static void ConvertAndScaleXRGB8888_Scalar(
    const uint8_t* srcData,
    unsigned srcWidth,
    unsigned srcHeight,
    size_t srcPitch,
    uint32_t* destData,
    unsigned destWidth,
    unsigned destHeight,
    unsigned destStride
);

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

static void ConvertAndScaleScalar(
    const void* srcData,
    PixelFormat srcFormat,
    unsigned srcWidth,
    unsigned srcHeight,
    size_t srcPitch,
    uint32_t* destData,
    PixelFormat destFormat,
    unsigned destWidth,
    unsigned destHeight,
    unsigned destStride
) {
    // 默认 Stride = Width
    if (destStride == 0) {
        destStride = destWidth;
    }

    const bool outputBgra = (destFormat == PixelFormat::BGRA8888);
    if (srcFormat == PixelFormat::XRGB8888 && !outputBgra) {
        ConvertAndScaleXRGB8888_Scalar(static_cast<const uint8_t*>(srcData), srcWidth,
                                       srcHeight, srcPitch, destData, destWidth,
                                       destHeight, destStride);
        return;
    }
    const uint32_t xStep = static_cast<uint32_t>(
        (static_cast<uint64_t>(srcWidth) << 16) / static_cast<uint64_t>(destWidth));
    const uint32_t yStep = static_cast<uint32_t>(
        (static_cast<uint64_t>(srcHeight) << 16) / static_cast<uint64_t>(destHeight));

    uint32_t yAcc = 0;
    switch (srcFormat) {
    case PixelFormat::RGB565: {
        for (unsigned dy = 0; dy < destHeight; dy++) {
            const unsigned sy = yAcc >> 16;
            yAcc += yStep;
            const uint16_t* srcRow = reinterpret_cast<const uint16_t*>(
                static_cast<const uint8_t*>(srcData) + static_cast<size_t>(sy) * srcPitch);
            uint32_t* dstRow = destData + static_cast<size_t>(dy) * destStride;
            uint32_t xAcc = 0;

            for (unsigned dx = 0; dx < destWidth; dx++) {
                const unsigned sx = xAcc >> 16;
                xAcc += xStep;
                uint16_t p = srcRow[sx];
                uint8_t r = ((p >> 11) & 0x1F) << 3;
                uint8_t g = ((p >> 5) & 0x3F) << 2;
                uint8_t b = (p & 0x1F) << 3;
                r |= r >> 5;
                g |= g >> 6;
                b |= b >> 5;
                if (outputBgra) {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
                } else {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(r);
                }
            }
        }
        break;
    }
    case PixelFormat::RGB0555: {
        for (unsigned dy = 0; dy < destHeight; dy++) {
            const unsigned sy = yAcc >> 16;
            yAcc += yStep;
            const uint16_t* srcRow = reinterpret_cast<const uint16_t*>(
                static_cast<const uint8_t*>(srcData) + static_cast<size_t>(sy) * srcPitch);
            uint32_t* dstRow = destData + static_cast<size_t>(dy) * destStride;
            uint32_t xAcc = 0;

            for (unsigned dx = 0; dx < destWidth; dx++) {
                const unsigned sx = xAcc >> 16;
                xAcc += xStep;
                uint16_t p = srcRow[sx];
                uint8_t r = ((p >> 10) & 0x1F) << 3;
                uint8_t g = ((p >> 5) & 0x1F) << 3;
                uint8_t b = (p & 0x1F) << 3;
                r |= r >> 5;
                g |= g >> 5;
                b |= b >> 5;
                if (outputBgra) {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
                } else {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(r);
                }
            }
        }
        break;
    }
    case PixelFormat::XRGB8888:
    default: {
        for (unsigned dy = 0; dy < destHeight; dy++) {
            const unsigned sy = yAcc >> 16;
            yAcc += yStep;
            const uint8_t* srcRow =
                static_cast<const uint8_t*>(srcData) + static_cast<size_t>(sy) * srcPitch;
            uint32_t* dstRow = destData + static_cast<size_t>(dy) * destStride;
            uint32_t xAcc = 0;

            for (unsigned dx = 0; dx < destWidth; dx++) {
                const unsigned sx = xAcc >> 16;
                xAcc += xStep;
                const uint8_t* srcPx = srcRow + static_cast<size_t>(sx) * 4u;
                uint8_t b = srcPx[0];
                uint8_t g = srcPx[1];
                uint8_t r = srcPx[2];
                if (outputBgra) {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
                } else {
                    dstRow[dx] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                                 (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(r);
                }
            }
        }
        break;
    }
    }
}

bool PixelConverter::IsConversionSupported(PixelFormat srcFormat, PixelFormat destFormat) {
    if (destFormat != PixelFormat::RGBA8888 && destFormat != PixelFormat::BGRA8888) {
        return false;
    }
    return srcFormat == PixelFormat::RGB0555 || srcFormat == PixelFormat::RGB565 ||
           srcFormat == PixelFormat::XRGB8888;
}

/**
 * XRGB8888 -> RGBA8888 转换 (标量实现)
 * 
 * 源格式: [B, G, R, X] (X 未使用)
 * 目标格式: [R, G, B, A]
 */
static void ConvertXRGB8888ToRGBA8888_Scalar(
    const uint8_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        // 读取源像素 (XRGB8888)
        uint8_t b = src[i * 4 + 0];
        uint8_t g = src[i * 4 + 1];
        uint8_t r = src[i * 4 + 2];
        // X 通道忽略
        
        // 写入目标像素 (RGBA8888)
        dest[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
    }
}

static void ConvertXRGB8888ToBGRA8888_Scalar(
    const uint8_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        uint8_t b = src[i * 4 + 0];
        uint8_t g = src[i * 4 + 1];
        uint8_t r = src[i * 4 + 2];
        dest[i] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                  (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
    }
}

/**
 * RGB565 -> RGBA8888 转换 (标量实现)
 * 
 * 源格式: 16位,5-6-5
 * 目标格式: [R, G, B, A]
 */
static void ConvertRGB565ToRGBA8888_Scalar(
    const uint16_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        uint16_t pixel = src[i];
        
        // 提取 RGB 分量 (5-6-5)
        uint8_t r = ((pixel >> 11) & 0x1F) << 3;  // 5位 -> 8位
        uint8_t g = ((pixel >> 5) & 0x3F) << 2;   // 6位 -> 8位
        uint8_t b = (pixel & 0x1F) << 3;          // 5位 -> 8位
        
        // 扩展到完整 8 位 (复制高位到低位)
        r |= r >> 5;
        g |= g >> 6;
        b |= b >> 5;
        
        // 写入目标像素 (RGBA8888)
        dest[i] = (0xFF << 24) | (b << 16) | (g << 8) | r;
    }
}

static void ConvertRGB565ToBGRA8888_Scalar(
    const uint16_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        uint16_t pixel = src[i];
        uint8_t r = ((pixel >> 11) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x3F) << 2;
        uint8_t b = (pixel & 0x1F) << 3;
        r |= r >> 5;
        g |= g >> 6;
        b |= b >> 5;
        dest[i] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                  (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
    }
}

static void Convert0RGB1555ToRGBA8888_Scalar(
    const uint16_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        uint16_t pixel = src[i];
        uint8_t r = ((pixel >> 10) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x1F) << 3;
        uint8_t b = (pixel & 0x1F) << 3;
        r |= r >> 5;
        g |= g >> 5;
        b |= b >> 5;
        dest[i] = (0xFFu << 24) | (static_cast<uint32_t>(b) << 16) |
                  (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(r);
    }
}

static void Convert0RGB1555ToBGRA8888_Scalar(
    const uint16_t* src,
    uint32_t* dest,
    size_t pixelCount
) {
    for (size_t i = 0; i < pixelCount; i++) {
        uint16_t pixel = src[i];
        uint8_t r = ((pixel >> 10) & 0x1F) << 3;
        uint8_t g = ((pixel >> 5) & 0x1F) << 3;
        uint8_t b = (pixel & 0x1F) << 3;
        r |= r >> 5;
        g |= g >> 5;
        b |= b >> 5;
        dest[i] = (0xFFu << 24) | (static_cast<uint32_t>(r) << 16) |
                  (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
    }
}

/**
 * 带缩放的像素转换 (标量实现)
 * 
 * 使用最近邻插值算法
 */
static void ConvertAndScaleXRGB8888_Scalar(
    const uint8_t* srcData,
    unsigned srcWidth,
    unsigned srcHeight,
    size_t srcPitch,
    uint32_t* destData,
    unsigned destWidth,
    unsigned destHeight,
    unsigned destStride
) {
    // 计算缩放比例
    float scaleX = static_cast<float>(srcWidth) / destWidth;
    float scaleY = static_cast<float>(srcHeight) / destHeight;
    
    for (unsigned dstY = 0; dstY < destHeight; dstY++) {
        for (unsigned dstX = 0; dstX < destWidth; dstX++) {
            // 计算源像素位置 (最近邻)
            unsigned srcX = static_cast<unsigned>(dstX * scaleX);
            unsigned srcY = static_cast<unsigned>(dstY * scaleY);
            
            // 边界检查
            if (srcX >= srcWidth || srcY >= srcHeight) {
                continue;
            }
            
            // 读取源像素 (XRGB8888)
            const uint8_t* srcPixel = srcData + srcY * srcPitch + srcX * 4;
            uint8_t b = srcPixel[0];
            uint8_t g = srcPixel[1];
            uint8_t r = srcPixel[2];
            
            // 写入目标像素 (RGBA8888)
            uint32_t color = (0xFF << 24) | (b << 16) | (g << 8) | r;
            destData[dstY * destStride + dstX] = color;
        }
    }
}

// ========== 公共接口实现 ==========

void PixelConverter::ConvertAndScale(
    const void* srcData,
    PixelFormat srcFormat,
    unsigned srcWidth,
    unsigned srcHeight,
    size_t srcPitch,
    void* destData,
    PixelFormat destFormat,
    unsigned destWidth,
    unsigned destHeight,
    unsigned destStride
) {
    if (!srcData || !destData || srcWidth == 0 || srcHeight == 0 ||
        destWidth == 0 || destHeight == 0) {
        return;
    }

    if (!IsConversionSupported(srcFormat, destFormat)) {
        LOGF(LOG_ERROR, "Unsupported pixel format conversion");
        return;
    }

    ConvertAndScaleScalar(srcData, srcFormat, srcWidth, srcHeight, srcPitch,
                          static_cast<uint32_t*>(destData), destFormat, destWidth,
                          destHeight, destStride);
}

void PixelConverter::Convert(
    const void* srcData,
    PixelFormat srcFormat,
    void* destData,
    PixelFormat destFormat,
    size_t pixelCount
) {
    if (!IsConversionSupported(srcFormat, destFormat)) {
        LOGF(LOG_ERROR, "Unsupported pixel format conversion");
        return;
    }

    const bool outputBgra = (destFormat == PixelFormat::BGRA8888);
    if (srcFormat == PixelFormat::XRGB8888) {
        if (outputBgra) {
            ConvertXRGB8888ToBGRA8888_Scalar(static_cast<const uint8_t*>(srcData),
                                             static_cast<uint32_t*>(destData),
                                             pixelCount);
        } else {
            ConvertXRGB8888ToRGBA8888_Scalar(static_cast<const uint8_t*>(srcData),
                                             static_cast<uint32_t*>(destData),
                                             pixelCount);
        }
    } else if (srcFormat == PixelFormat::RGB565) {
        if (outputBgra) {
            ConvertRGB565ToBGRA8888_Scalar(static_cast<const uint16_t*>(srcData),
                                           static_cast<uint32_t*>(destData),
                                           pixelCount);
        } else {
            ConvertRGB565ToRGBA8888_Scalar(static_cast<const uint16_t*>(srcData),
                                           static_cast<uint32_t*>(destData),
                                           pixelCount);
        }
    } else if (srcFormat == PixelFormat::RGB0555) {
        if (outputBgra) {
            Convert0RGB1555ToBGRA8888_Scalar(static_cast<const uint16_t*>(srcData),
                                             static_cast<uint32_t*>(destData),
                                             pixelCount);
        } else {
            Convert0RGB1555ToRGBA8888_Scalar(static_cast<const uint16_t*>(srcData),
                                             static_cast<uint32_t*>(destData),
                                             pixelCount);
        }
    }
}

bool PixelConverter::IsNeonSupported() {
    // 标量版本不使用 NEON
    return false;
}

const char* PixelConverter::GetImplementation() {
    return "Scalar";
}

} // namespace libretro
