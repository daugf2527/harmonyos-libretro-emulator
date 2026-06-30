/*
 * VSync Manager Implementation
 */
#include "vsync_manager.h"
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "VsyncManager"

VsyncManager::VsyncManager() {}

VsyncManager::~VsyncManager() {
    Stop();
    std::lock_guard<std::mutex> lock(mutex_);
    if (nativeVSync_) {
        OH_NativeVSync_Destroy(nativeVSync_);
        nativeVSync_ = nullptr;
    }
}

bool VsyncManager::Initialize(const char* name) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (nativeVSync_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "VSync already initialized");
        return false;
    }
    
    nativeVSync_ = OH_NativeVSync_Create(name, strlen(name));
    if (!nativeVSync_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create NativeVSync instance");
        return false;
    }
    
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "VSync initialized: %{public}s", name);
    return true;
}

void VsyncManager::Start() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!nativeVSync_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "VSync not initialized");
        return;
    }
    
    if (isRunning_) {
        return;
    }
    
    isRunning_ = true;
    
    // Request first frame
    OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "VSync started");
}

void VsyncManager::Stop() {
    std::lock_guard<std::mutex> lock(mutex_);
    isRunning_ = false;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "VSync stopped");
}

void VsyncManager::SetFrameCallback(std::function<void(long long)> callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    frameCallback_ = callback;
}

void VsyncManager::OnVSyncCallback(long long timestamp, void* data) {
    VsyncManager* manager = static_cast<VsyncManager*>(data);
    if (!manager) {
        return;
    }

    std::function<void(long long)> callback;
    OH_NativeVSync* nativeVSync = nullptr;
    {
        std::lock_guard<std::mutex> lock(manager->mutex_);
        if (!manager->isRunning_) {
            return;
        }
        callback = manager->frameCallback_;
        nativeVSync = manager->nativeVSync_;
    }

    if (callback) {
        callback(timestamp);
    }

    {
        std::lock_guard<std::mutex> lock(manager->mutex_);
        if (manager->isRunning_ && nativeVSync) {
            OH_NativeVSync_RequestFrame(nativeVSync, OnVSyncCallback, manager);
        }
    }
}
