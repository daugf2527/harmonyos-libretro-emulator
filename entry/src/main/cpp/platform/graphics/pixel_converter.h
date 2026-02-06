/*
 * 像素格式转换器 - 接口定义
 * 
 * 完全遵循 Libretro 官方标准和华为鸿蒙官方规范
 * 
 * 支持的格式转换:
 * - 0RGB1555 -> RGBA8888 (Libretro 默认格式,已废弃但需兼容)
 * - RGB565 -> RGBA8888 (Libretro 推荐 16位格式)
 * - XRGB8888 -> RGBA8888 (Libretro 推荐 32位格式)
 * 
 * 性能优化:
 * - ARM NEON SIMD 指令加速 (2-3x)
 * - 预计算缩放映射表 (避免浮点除法)
 * - 批量处理 (每次 4-8 个像素)
 * 
 * 参考文档:
 * - Libretro API: https://github.com/libretro/RetroArch/blob/master/libretro-common/include/libretro.h
 * - 鸿蒙 NEON: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/neon-guide
 */

#ifndef PIXEL_CONVERTER_H
#define PIXEL_CONVERTER_H

#include <cstdint>
#include <cstddef>

namespace libretro {

/**
 * 像素格式枚举
 * 
 * 完全对应 Libretro 官方定义的 retro_pixel_format
 * 参考: libretro.h 第 5620-5647 行
 */
enum class PixelFormat {
    // Libretro 源格式 (核心输出)
    RGB0555,    // 0RGB1555 - 15位, [0RRRRRGGGGGBBBBB], Libretro 默认格式 (已废弃)
    RGB565,     // RGB565 - 16位, [RRRRRGGGGGGBBBBB], Libretro 推荐 16位格式
    XRGB8888,   // XRGB8888 - 32位, [XXXXXXXX RRRRRRRR GGGGGGGG BBBBBBBB], Libretro 推荐 32位格式
    
    // 鸿蒙目标格式 (NativeWindow 输入)
    RGBA8888,   // RGBA8888 - 32位, [RRRRRRRR GGGGGGGG BBBBBBBB AAAAAAAA], 鸿蒙标准格式
    BGRA8888,
    
    // 未知格式
    UNKNOWN     // 不支持的格式
};

/**
 * 像素转换器类
 * 
 * 提供高性能的像素格式转换功能
 * 自动选择 NEON 或标量实现
 */
class PixelConverter {
public:
    /**
     * @brief 执行格式转换并缩放
     *
     * @param srcData 源数据指针
     * @param srcFormat 源像素格式
     * @param srcWidth 源图像宽度
     * @param srcHeight 源图像高度
     * @param srcPitch 源数据行距 (Bytes)
     * @param destData 目标数据指针
     * @param destFormat 目标像素格式 (通常为 RGBA8888)
     * @param destWidth 目标图像宽度
     * @param destHeight 目标图像高度
     * @param destStride 目标数据行跨度 (像素数，非字节数)
     */
    static void ConvertAndScale(const void *srcData, PixelFormat srcFormat,
                                unsigned srcWidth, unsigned srcHeight,
                                size_t srcPitch, void *destData,
                                PixelFormat destFormat, unsigned destWidth,
                                unsigned destHeight, unsigned destStride = 0);
    
    /**
     * 转换像素格式 (无缩放,1:1)
     * 
     * @param srcData 源数据指针
     * @param srcFormat 源像素格式
     * @param destData 目标数据指针
     * @param destFormat 目标像素格式
     * @param pixelCount 像素数量
     */
    static void Convert(
        const void* srcData,
        PixelFormat srcFormat,
        void* destData,
        PixelFormat destFormat,
        size_t pixelCount
    );
    
    /**
     * 检测是否支持 NEON 优化
     * 
     * @return true 如果支持 NEON
     */
    static bool IsNeonSupported();
    
    /**
     * 获取转换器信息 (用于调试)
     * 
     * @return 转换器实现类型 ("NEON" 或 "Scalar")
     */
    static const char* GetImplementation();
    
    /**
     * 获取像素格式名称 (用于调试)
     * 
     * @param format 像素格式
     * @return 格式名称字符串
     */
    static const char* GetFormatName(PixelFormat format);
    
    /**
     * 检测格式转换是否支持
     * 
     * @param srcFormat 源格式
     * @param destFormat 目标格式
     * @return true 如果支持该转换
     */
    static bool IsConversionSupported(PixelFormat srcFormat, PixelFormat destFormat);

private:
    // 禁止实例化
    PixelConverter() = delete;
    ~PixelConverter() = delete;
    PixelConverter(const PixelConverter&) = delete;
    PixelConverter& operator=(const PixelConverter&) = delete;
};

} // namespace libretro

#endif // PIXEL_CONVERTER_H
