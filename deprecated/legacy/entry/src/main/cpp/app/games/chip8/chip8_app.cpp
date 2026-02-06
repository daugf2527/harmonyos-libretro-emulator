/*
 * [LEGACY] This file is part of the old Standalone Chip8 implementation (Phase 2).
 * It is replaced by the Libretro Bridge architecture (Phase 3).
 *
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "chip8_app.h"
#include <cerrno>
#include <cstring>
#include <hilog/log.h>
#include <memory>
#include <native_buffer/native_buffer.h>
#include <poll.h>
#include <unistd.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD001
#undef LOG_TAG
#define LOG_TAG "Chip8App"

// Static callback functions for XComponent
static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreatedCB");
    if ((component == nullptr) || (window == nullptr)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreatedCB: component or window is null");
        return;
    }
    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(component, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreatedCB: Unable to get XComponent id");
        return;
    }
    std::string id(idStr);
    auto app = Chip8App::GetInstance(id);
    OHNativeWindow *nativeWindow = static_cast<OHNativeWindow *>(window);
    app->SetNativeWindow(nativeWindow);

    uint64_t width;
    uint64_t height;
    int32_t xSize = OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    if ((xSize == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) && (app != nullptr)) {
        app->SetHeight(height);
        app->SetWidth(width);
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "xComponent width = %{public}lu, height = %{public}lu", width, height);
    }
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyedCB");
    if ((component == nullptr) || (window == nullptr)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyedCB: component or window is null");
        return;
    }
    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(component, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyedCB: Unable to get XComponent id");
        return;
    }
    std::string id(idStr);
    Chip8App::Release(id);
}

// Global instance map - 使用智能指针管理生命周期
static std::unordered_map<std::string, std::shared_ptr<Chip8App>> g_instance;

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

Chip8App *Chip8App::GetInstance(std::string &id) {
    if (g_instance.find(id) == g_instance.end()) {
        // 使用 make_shared 创建实例,自动管理内存
        g_instance[id] = std::make_shared<Chip8App>(id);
    }
    return g_instance[id].get();
}

void Chip8App::Release(std::string &id) {
    // 直接擦除,shared_ptr 会自动析构对象
    g_instance.erase(id);
}

Chip8App::Chip8App(std::string id) : id_(id) {
    core_ = new Chip8Core();
    lastFpsTime_ = std::chrono::steady_clock::now();
    
    // Initialize VSync manager
    vsyncManager_ = new VsyncManager();
    if (vsyncManager_->Initialize("Chip8_VSync")) {
        // Set VSync callback
        vsyncManager_->SetFrameCallback([this](long long timestamp) {
            this->OnVSyncFrame(timestamp);
        });
    }
    
    InitChip8();
}

Chip8App::~Chip8App() {
    // Stop VSync before cleanup
    if (vsyncManager_) {
        vsyncManager_->Stop();
        delete vsyncManager_;
        vsyncManager_ = nullptr;
    }
    
    if (core_) {
        delete core_;
        core_ = nullptr;
    }
    buffer_ = nullptr;
    if (nativeWindow_) {
        OH_NativeWindow_NativeObjectUnreference(nativeWindow_);
        nativeWindow_ = nullptr;
    }
}

void Chip8App::InitChip8() {
    if (!core_) return;
    core_->Initialize();

    // Hardcoded IBM Logo ROM (Standard Chip8 Test ROM)
    // Source: https://github.com/loktar00/chip8/blob/master/roms/IBM%20Logo.ch8
    const uint8_t ibm_logo[] = {
        // Program code (42 bytes)
        0x00, 0xE0, 0xA2, 0x2A, 0x60, 0x0C, 0x61, 0x08, 0xD0, 0x1F, 0x70, 0x09, 0xA2, 0x39, 0xD0, 0x1F,
        0xA2, 0x48, 0x70, 0x08, 0xD0, 0x1F, 0x70, 0x04, 0xA2, 0x57, 0xD0, 0x1F, 0x70, 0x08, 0xA2, 0x66,
        0xD0, 0x1F, 0x70, 0x08, 0xA2, 0x75, 0xD0, 0x1F, 0x12, 0x28,
        
        // Sprite data for "IBM" logo (90 bytes total, 6 sprites × 15 bytes each)
        // Sprite 1 - Letter "I" (starts at 0x22A = index 42)
        0x3C, 0x3C, 0x00, 0x3C, 0x00, 0x3C, 0x00, 0x3C, 0x00, 0x3C, 0x00, 0x3C, 0x3C, 0x3C, 0x00,
        
        // Sprite 2 - Letter "B" part 1 (starts at 0x239 = index 57)
        0xFC, 0xCC, 0xCC, 0xFC, 0xCC, 0xCC, 0xCC, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        
        // Sprite 3 - Letter "B" part 2 (starts at 0x248 = index 72)
        0x3C, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        
        // Sprite 4 - Letter "M" part 1 (starts at 0x257 = index 87)
        0xC3, 0xE7, 0xFF, 0xDB, 0xC3, 0xC3, 0xC3, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        
        // Sprite 5 - Letter "M" part 2 (starts at 0x266 = index 102)
        0xC3, 0xE7, 0xFF, 0xDB, 0xC3, 0xC3, 0xC3, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        
        // Sprite 6 - Additional sprite (starts at 0x275 = index 117)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    
    core_->LoadRomFromBuffer(ibm_logo, sizeof(ibm_logo));
}

void Chip8App::SetWidth(uint64_t width) { width_ = width; }

void Chip8App::SetHeight(uint64_t height) { height_ = height; }

void Chip8App::SetNativeWindow(OHNativeWindow *nativeWindow) { 
    if (nativeWindow_ != nativeWindow) {
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectUnreference(nativeWindow_);
        }
        nativeWindow_ = nativeWindow;
        if (nativeWindow_) {
            OH_NativeWindow_NativeObjectReference(nativeWindow_);
        }
    }
    
    // Start VSync rendering loop when window is ready
    // FIX: Disable automatic VSync start to avoid contention with LibretroEngine
    /*
    if (nativeWindow_ && vsyncManager_ && !vsyncManager_->IsRunning()) {
        vsyncManager_->Start();
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "VSync rendering started");
    }
    */
}

void Chip8App::RenderTestFrame() {
    if (nativeWindow_ == nullptr || core_ == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "nativeWindow_ or core_ is nullptr");
        return;
    }

    // Emulate multiple cycles per frame to speed up execution
    // Target: ~600Hz (60fps * 10 cycles)
    for (int i = 0; i < 10; ++i) {
        core_->Cycle();
    }
    core_->TickTimers();

    // Performance monitoring: Calculate FPS every second
    frameCount_++;
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastFpsTime_).count();
    if (elapsed >= 1000) {
        currentFps_ = (frameCount_ * 1000.0f) / elapsed;
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "FPS: %{public}.1f (Rendered: %{public}d frames)", currentFps_, frameCount_);
        frameCount_ = 0;
        lastFpsTime_ = now;
    }
    
    // Only render if the draw flag is set (performance optimization)
    if (!core_->IsDrawFlag()) {
        return;
    }

    // 1. Request Buffer
    int ret = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &buffer_, &fenceFd_);
    if (ret != 0 || buffer_ == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "RequestBuffer failed: %{public}d", ret);
        return;
    }

    auto abortBuffer = [this]() {
        if (nativeWindow_ && buffer_) {
            OH_NativeWindow_NativeWindowAbortBuffer(nativeWindow_, buffer_);
        }
        buffer_ = nullptr;
    };

    WaitAndCloseFenceFd(fenceFd_);
    fenceFd_ = -1;

    // 2. Convert to NativeBuffer (官方推荐方式)
    OH_NativeBuffer* nativeBuffer = nullptr;
    int32_t convertRet = OH_NativeBuffer_FromNativeWindowBuffer(buffer_, &nativeBuffer);
    if (convertRet != 0 || !nativeBuffer) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OH_NativeBuffer_FromNativeWindowBuffer failed: %{public}d", convertRet);
        abortBuffer();
        return;
    }

    // 3. Map Memory using NativeBuffer API
    void* virAddr = nullptr;
    int32_t mapRet = OH_NativeBuffer_Map(nativeBuffer, &virAddr);
    if (mapRet != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OH_NativeBuffer_Map failed: %{public}d", mapRet);
        abortBuffer();
        return;
    }

    // 4. Get Buffer Configuration
    OH_NativeBuffer_Config config;
    OH_NativeBuffer_GetConfig(nativeBuffer, &config);
    
    // 5. Copy Graphics Buffer (Upscaling 64x32 -> Screen Size)
    // Optimized: Use Forward Mapping with Integer Arithmetic to draw Rectangles
    // This avoids 7+ million floating point divisions per frame on high-res screens.
    uint32_t *dest = static_cast<uint32_t *>(virAddr);
    int32_t destStride = config.stride / 4; // Assume 32-bit format (4 bytes/pixel)
    int32_t destWidth = config.width;
    int32_t destHeight = config.height;
    
    const uint32_t *src = core_->GetGraphicsBuffer();
    const int srcW = Chip8Core::VIDEO_WIDTH;  // 64
    const int srcH = Chip8Core::VIDEO_HEIGHT; // 32

    // Pre-calculate row/col start indices to ensure gap-less coverage
    // We allocate on stack for speed (size is small)
    int colStart[65]; // 64 + 1
    int rowStart[33]; // 32 + 1
    
    for(int i = 0; i <= srcW; ++i) colStart[i] = (i * destWidth) / srcW;
    for(int i = 0; i <= srcH; ++i) rowStart[i] = (i * destHeight) / srcH;

    for (int y = 0; y < srcH; ++y) {
        int y0 = rowStart[y];
        int y1 = rowStart[y + 1];
        
        for (int x = 0; x < srcW; ++x) {
            uint32_t color = src[y * srcW + x];
            int x0 = colStart[x];
            int x1 = colStart[x + 1];

            // Fill the rectangle for this "virtual pixel"
            for (int dy = y0; dy < y1; ++dy) {
                uint32_t* rowPtr = dest + (dy * destStride);
                // Use memset-like optimization loop or just simple assignment
                // Simple loop is fast enough for memory-aligned writes
                for (int dx = x0; dx < x1; ++dx) {
                    rowPtr[dx] = color;
                }
            }
        }
    }

    // Clear flag
    core_->ClearDrawFlag();

    // 6. Unmap Memory
    mapRet = OH_NativeBuffer_Unmap(nativeBuffer);
    if (mapRet != 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "OH_NativeBuffer_Unmap failed: %{public}d", mapRet);
        abortBuffer();
        return;
    }

    // 7. Flush Buffer
    Region region{nullptr, 0};
    const int acquireFenceFd = -1;
    OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, buffer_, acquireFenceFd, region);
    buffer_ = nullptr;
}

void Chip8App::ChangeColor() {
    // 使用互斥锁保护,防止与 VSync 线程的数据竞争
    std::lock_guard<std::mutex> lock(renderMutex_);
    
    // Cycle colors: Red -> Green -> Blue
    if (drawColor_ == 0xFFFF0000) drawColor_ = 0xFF00FF00;
    else if (drawColor_ == 0xFF00FF00) drawColor_ = 0xFF0000FF;
    else drawColor_ = 0xFFFF0000;
}

napi_value Chip8App::NapiChangeColor(napi_env env, napi_callback_info info) {
    napi_value thisArg;
    if (napi_get_cb_info(env, info, nullptr, nullptr, &thisArg, nullptr) != napi_ok) return nullptr;

    napi_value exportInstance;
    if (napi_get_named_property(env, thisArg, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) return nullptr;

    OH_NativeXComponent *nativeXComponent = nullptr;
    if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&nativeXComponent)) != napi_ok) return nullptr;

    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) return nullptr;
    
    std::string id(idStr);
    Chip8App *app = Chip8App::GetInstance(id);
    if (app != nullptr) {
        app->ChangeColor();
    }
    return nullptr;
}

napi_value Chip8App::NapiDrawPattern(napi_env env, napi_callback_info info) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "NapiDrawPattern called");
    if ((env == nullptr) || (info == nullptr)) {
        return nullptr;
    }

    napi_value thisArg;
    if (napi_get_cb_info(env, info, nullptr, nullptr, &thisArg, nullptr) != napi_ok) {
        return nullptr;
    }

    napi_value exportInstance;
    if (napi_get_named_property(env, thisArg, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) {
        return nullptr;
    }

    OH_NativeXComponent *nativeXComponent = nullptr;
    if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&nativeXComponent)) != napi_ok) {
        return nullptr;
    }

    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(nativeXComponent, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return nullptr;
    }
    
    std::string id(idStr);
    Chip8App *app = Chip8App::GetInstance(id);
    if (app != nullptr) {
        app->RenderTestFrame();
    }
    return nullptr;
}

void Chip8App::Export(napi_env env, napi_value exports) {
    if ((env == nullptr) || (exports == nullptr)) {
        return;
    }
    // We map 'drawPattern' to our new RenderTestFrame logic for compatibility with existing ArkTS code
    napi_property_descriptor desc[] = {
        {"drawPattern", nullptr, Chip8App::NapiDrawPattern, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"changeColor", nullptr, Chip8App::NapiChangeColor, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}

void Chip8App::RegisterCallback(OH_NativeXComponent *nativeXComponent) {
    renderCallback_.OnSurfaceCreated = OnSurfaceCreatedCB;
    renderCallback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
    renderCallback_.DispatchTouchEvent = nullptr; // Reserved for Phase 3
    renderCallback_.OnSurfaceChanged = nullptr;
    OH_NativeXComponent_RegisterCallback(nativeXComponent, &renderCallback_);
}
