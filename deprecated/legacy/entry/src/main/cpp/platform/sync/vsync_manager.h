/*
 * VSync Manager for High-Performance Rendering
 * Uses HarmonyOS NativeVSync API for hardware-synchronized rendering
 */
#ifndef VSYNC_MANAGER_H
#define VSYNC_MANAGER_H

#include <functional>
#include <mutex>
#include <native_vsync/native_vsync.h>

class VsyncManager {
public:
    VsyncManager();
    ~VsyncManager();
    
    // Initialize VSync instance
    bool Initialize(const char* name);
    
    // Start VSync loop (requests frame continuously)
    void Start();
    
    // Stop VSync loop
    void Stop();
    
    // Set frame callback (called on every VSync signal)
    void SetFrameCallback(std::function<void(long long)> callback);
    
    // Check if VSync is running
    bool IsRunning() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return isRunning_;
    }
    
private:
    mutable std::mutex mutex_;
    OH_NativeVSync* nativeVSync_ = nullptr;
    std::function<void(long long)> frameCallback_;
    bool isRunning_ = false;
    
    // Static callback wrapper for C API
    static void OnVSyncCallback(long long timestamp, void* data);
};

#endif // VSYNC_MANAGER_H
