/*
 * Phase 3.2 - Game2048 Native 渲染器实现
 * 
 * 核心流程:
 * 1. OH_NativeWindow_NativeWindowRequestBuffer - 申请 Buffer
 * 2. OH_NativeBuffer_Map - 映射内存
 * 3. 像素格式转换 + 缩放
 * 4. OH_NativeBuffer_Unmap - 解除映射
 * 5. OH_NativeWindow_NativeWindowFlushBuffer - 提交 Buffer
 */

#include "game2048_native_renderer.h"
#include "pixel_converter.h"  // NEON 优化的像素转换器
#include "hilog/log.h"
#include <cstring>
#include <algorithm>
#include <cerrno>
#include <poll.h>
#include <unistd.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "Game2048Renderer"

static void WaitAndCloseFenceFd(int fenceFd)
{
    if (fenceFd < 0) {
        return;
    }

    struct pollfd pfd;
    std::memset(&pfd, 0, sizeof(pfd));
    pfd.fd = fenceFd;
    pfd.events = POLLIN;

    int ret = -1;
    do {
        ret = poll(&pfd, 1, 3000);
    } while (ret == -1 && (errno == EINTR || errno == EAGAIN));

    if (ret < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "poll fenceFd failed: %{public}d", errno);
    } else if (ret == 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "poll fenceFd timeout");
    }

    close(fenceFd);
}

Game2048NativeRenderer::Game2048NativeRenderer(const std::string& id) 
    : id_(id) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048NativeRenderer created: %{public}s", id_.c_str());
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "🚀 Pixel Converter: %{public}s (NEON: %{public}s)", 
                libretro::PixelConverter::GetImplementation(),
                libretro::PixelConverter::IsNeonSupported() ? "YES" : "NO");
}

Game2048NativeRenderer::~Game2048NativeRenderer() {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Game2048NativeRenderer destroyed: %{public}s", id_.c_str());
    OnSurfaceDestroyed();
}

void Game2048NativeRenderer::OnSurfaceCreated(OHNativeWindow* window) {
    std::lock_guard<std::mutex> lock(renderMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreated: %{public}s", id_.c_str());
    if (nativeWindow_ != window) {
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectUnreference(nativeWindow_);
        }
        nativeWindow_ = window;
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectReference(nativeWindow_);
        }
    }
    
    if (!nativeWindow_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "nativeWindow is null!");
        return;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Surface created, using default buffer format");
}

void Game2048NativeRenderer::OnSurfaceChanged(OHNativeWindow* window, int32_t width, int32_t height) {
    std::lock_guard<std::mutex> lock(renderMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChanged: %{public}dx%{public}d", width, height);
    if (nativeWindow_ != window) {
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectUnreference(nativeWindow_);
        }
        nativeWindow_ = window;
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectReference(nativeWindow_);
        }
    }
    windowWidth_ = width;
    windowHeight_ = height;
    
    if (nativeWindow_) {
        // 设置 Buffer 几何尺寸 (宽高) - 适配折叠屏等尺寸变化
        int32_t ret = OH_NativeWindow_NativeWindowHandleOpt(nativeWindow_, 
            SET_BUFFER_GEOMETRY, width, height);
        if (ret == 0) {
            OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Buffer 尺寸已更新: %{public}dx%{public}d", width, height);
        } else {
            OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "⚠️ 设置 Buffer 尺寸返回: %{public}d (可能使用默认值)", ret);
        }
    }
}

void Game2048NativeRenderer::OnSurfaceDestroyed() {
    std::lock_guard<std::mutex> lock(renderMutex_);
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyed: %{public}s", id_.c_str());
    if (nativeWindow_) {
        OH_NativeWindow_NativeObjectUnreference(nativeWindow_);
        nativeWindow_ = nullptr;
    }
}

void Game2048NativeRenderer::RenderFrame(const void* data, unsigned width, unsigned height, size_t pitch) {
    std::lock_guard<std::mutex> lock(renderMutex_);
    
    if (!nativeWindow_ || !data) {
        return;
    }
    
    RenderFrameInternal(data, width, height, pitch);
}

void Game2048NativeRenderer::RenderFrameInternal(const void* data, unsigned width, unsigned height, size_t pitch) {
    // ========== 1. 申请 Buffer ==========
    OHNativeWindowBuffer* buffer = nullptr;
    int fenceFd = -1;
    int32_t ret = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &buffer, &fenceFd);
    if (ret != 0 || !buffer) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "RequestBuffer failed: %{public}d", ret);
        return;
    }

    WaitAndCloseFenceFd(fenceFd);
    fenceFd = -1;
    
    // ========== 2. 转换为 NativeBuffer 并映射内存 ==========
    OH_NativeBuffer* nativeBuffer = nullptr;
    ret = OH_NativeBuffer_FromNativeWindowBuffer(buffer, &nativeBuffer);
    if (ret != 0 || !nativeBuffer) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "FromNativeWindowBuffer failed: %{public}d", ret);
        OH_NativeWindow_NativeWindowAbortBuffer(nativeWindow_, buffer);
        return;
    }
    
    void* virAddr = nullptr;
    ret = OH_NativeBuffer_Map(nativeBuffer, &virAddr);
    if (ret != 0 || !virAddr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "NativeBuffer_Map failed: %{public}d", ret);
        OH_NativeWindow_NativeWindowAbortBuffer(nativeWindow_, buffer);
        return;
    }
    
    // ========== 3. 获取 Buffer 配置 ==========
    OH_NativeBuffer_Config config;
    OH_NativeBuffer_GetConfig(nativeBuffer, &config);
    
    uint32_t* dest = static_cast<uint32_t*>(virAddr);
    const uint8_t* src = static_cast<const uint8_t*>(data);
    
    // ========== 4. 计算缩放比例 (保持宽高比) ==========
    float scaleX = static_cast<float>(config.width) / width;
    float scaleY = static_cast<float>(config.height) / height;
    float scale = std::min(scaleX, scaleY);
    
    int scaledWidth = static_cast<int>(width * scale);
    int scaledHeight = static_cast<int>(height * scale);
    int offsetX = (config.width - scaledWidth) / 2;
    int offsetY = (config.height - scaledHeight) / 2;
    
    // ========== 5. 清空背景为黑色 ==========
    std::memset(dest, 0, config.height * config.stride);
    
    // ========== 6. 使用 NEON 优化的像素转换器渲染游戏画面 ==========
    // 计算渲染区域 (居中显示,保持宽高比)
    uint32_t* destRegion = dest + offsetY * (config.stride / 4) + offsetX;
    
    // 使用 PixelConverter 进行 NEON 优化的像素转换和缩放
    libretro::PixelConverter::ConvertAndScale(
        data,                                    // 源数据 (XRGB8888)
        libretro::PixelFormat::XRGB8888,        // 源格式
        width,                                   // 源宽度
        height,                                  // 源高度
        pitch,                                   // 源行字节数
        destRegion,                              // 目标数据 (RGBA8888)
        libretro::PixelFormat::RGBA8888,        // 目标格式
        scaledWidth,                             // 目标宽度
        scaledHeight,                            // 目标高度
        config.stride / 4                        // 目标行像素数
    );
    
    // ========== 7. 解除内存映射 ==========
    ret = OH_NativeBuffer_Unmap(nativeBuffer);
    if (ret != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "NativeBuffer_Unmap failed: %{public}d", ret);
        OH_NativeWindow_NativeWindowAbortBuffer(nativeWindow_, buffer);
        return;
    }
    
    // ========== 8. 提交 Buffer ==========
    Region region{nullptr, 0};  // 全屏刷新
    const int acquireFenceFd = -1;
    ret = OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, buffer, acquireFenceFd, region);
    if (ret != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "FlushBuffer failed: %{public}d", ret);
    }
    
    static int frameCount = 0;
    if (frameCount++ % 60 == 0) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Native 渲染帧 #%{public}d (缩放: %.2fx, 窗口: %{public}dx%{public}d)", 
                    frameCount, scale, config.width, config.height);
    }
}
