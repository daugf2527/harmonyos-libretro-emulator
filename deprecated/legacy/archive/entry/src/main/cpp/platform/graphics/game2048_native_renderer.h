/*
 * Phase 3.2 - Game2048 Native 渲染器
 * 使用 NativeWindow 直接渲染,避免 ArkTS Canvas 的性能开销
 * 
 * 参考:
 * - https://www.cnblogs.com/HarmonyOSDev/p/17896991.html
 * - /Users/asd/drawing-to-xcomponent/entry/src/main/cpp/samples/chip8_app.cpp
 */

#ifndef GAME2048_NATIVE_RENDERER_H
#define GAME2048_NATIVE_RENDERER_H

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <string>
#include <mutex>

class Game2048NativeRenderer {
public:
    explicit Game2048NativeRenderer(const std::string& id);
    ~Game2048NativeRenderer();
    
    // XComponent 回调
    void OnSurfaceCreated(OHNativeWindow* window);
    void OnSurfaceChanged(OHNativeWindow* window, int32_t width, int32_t height);
    void OnSurfaceDestroyed();
    
    // 渲染 Libretro 帧
    void RenderFrame(const void* data, unsigned width, unsigned height, size_t pitch);
    
    // 获取实例 ID
    std::string GetId() const { return id_; }
    
private:
    std::string id_;
    OHNativeWindow* nativeWindow_ = nullptr;
    int32_t windowWidth_ = 0;
    int32_t windowHeight_ = 0;
    std::mutex renderMutex_;
    
    // 渲染辅助函数
    void RenderFrameInternal(const void* data, unsigned width, unsigned height, size_t pitch);
};

#endif // GAME2048_NATIVE_RENDERER_H
