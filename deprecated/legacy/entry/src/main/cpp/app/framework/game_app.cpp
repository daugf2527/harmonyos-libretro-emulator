/*
 * Libretro 游戏应用实现 - 完全参考 Game2048NativeApp 架构
 */

#include "app/framework/plugin_manager.h"
#include "game_app.h"
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD003
#define LOG_TAG "LibretroGameApp"

LibretroGameApp::LibretroGameApp(const std::string &id)
    : id_(id),
      renderer_(std::make_shared<libretro::LibretroNativeRenderer>(id)) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LibretroGameApp created: %{public}s", id_.c_str());
}

LibretroGameApp::~LibretroGameApp() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LibretroGameApp destroyed: %{public}s", id_.c_str());
  StopVSync();
  StopGame();

  if (nativeVSync_) {
    OH_NativeVSync_Destroy(nativeVSync_);
    nativeVSync_ = nullptr;
  }
}

// ========== XComponent 回调注册（完全参考 Game2048NativeApp）==========

// 静态回调函数（转发到实例方法）
static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
      "========== LibretroGameApp OnSurfaceCreatedCB: %{public}s ==========",
      idStr);

  std::string xComponentId(idStr);
  auto *app = PluginManager::GetInstance()->FindLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                "LibretroGameApp not found for OnSurfaceCreatedCB: %{public}s",
                xComponentId.c_str());
    return;
  }
  app->OnSurfaceCreated(static_cast<OHNativeWindow *>(window));
}

static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  uint64_t width, height;
  OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
      "LibretroGameApp OnSurfaceChangedCB: %{public}s %{public}lux%{public}lu",
      idStr, width, height);

  std::string xComponentId(idStr);
  auto *app = PluginManager::GetInstance()->FindLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                "LibretroGameApp not found for OnSurfaceChangedCB: %{public}s",
                xComponentId.c_str());
    return;
  }
  app->OnSurfaceChanged(static_cast<OHNativeWindow *>(window), width, height);
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window) {
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {'\0'};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LibretroGameApp OnSurfaceDestroyedCB: %{public}s",
              idStr);

  std::string xComponentId(idStr);
  auto *app = PluginManager::GetInstance()->FindLibretroGame(xComponentId);
  if (!app) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                "LibretroGameApp not found for OnSurfaceDestroyedCB: %{public}s",
                xComponentId.c_str());
    return;
  }
  app->OnSurfaceDestroyed();
}

void LibretroGameApp::RegisterCallback(OH_NativeXComponent *nativeXComponent) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "RegisterCallback: %{public}s", id_.c_str());

  // 设置回调函数（成员变量，生命周期与对象一致）
  renderCallback_.OnSurfaceCreated = OnSurfaceCreatedCB;
  renderCallback_.OnSurfaceChanged = OnSurfaceChangedCB;
  renderCallback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
  renderCallback_.DispatchTouchEvent = nullptr; // 后续实现

  // 注册回调
  OH_NativeXComponent_RegisterCallback(nativeXComponent, &renderCallback_);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ LibretroGameApp callbacks registered successfully");
}

// ========== XComponent 回调实现 ==========

void LibretroGameApp::OnSurfaceCreated(OHNativeWindow *window) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceCreated: %{public}s, window=%{public}p",
              id_.c_str(), window);
  if (renderer_) {
    renderer_->Initialize(window);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ Renderer initialized with NativeWindow");
  }
}

void LibretroGameApp::OnSurfaceChanged(OHNativeWindow *window, int32_t width,
                                       int32_t height) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceChanged: %{public}dx%{public}d", width,
              height);
  if (renderer_) {
    renderer_->OnSurfaceChanged(width, height);
  }
}

void LibretroGameApp::OnSurfaceDestroyed() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "OnSurfaceDestroyed: %{public}s", id_.c_str());
  StopVSync();
  if (renderer_) {
    renderer_->Release();
  }
}

// ========== 游戏控制 ==========

bool LibretroGameApp::LoadCore(const std::string &corePath,
                               const std::string &filesDir,
                               const std::string &cacheDir) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LoadCore: %{public}s", corePath.c_str());
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_) {
    return renderer_->LoadCore(corePath, filesDir, cacheDir);
  }
  return false;
}

bool LibretroGameApp::LoadRom(const std::string &romPath,
                              NativeResourceManager *nativeResourceManager,
                              const std::string &filesDir,
                              const std::string &cacheDir) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "LoadRom: %{public}s", romPath.c_str());
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_) {
    return renderer_->LoadRom(romPath, nativeResourceManager, filesDir, cacheDir);
  }
  return false;
}

void LibretroGameApp::StartGame() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StartGame: %{public}s", id_.c_str());
  if (renderer_) {
    renderer_->Start();
    {
      std::lock_guard<std::mutex> lock(stateMutex_);
      gameRunning_ = true;
      gamePaused_ = false;
    }
    StartVSync();
  }
}

void LibretroGameApp::PauseGame() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "PauseGame: %{public}s", id_.c_str());
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_) {
    renderer_->Pause();
    gamePaused_ = true;
  }
}

void LibretroGameApp::StopGame() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StopGame: %{public}s", id_.c_str());
  StopVSync();
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_) {
    renderer_->ClearButtonStates();
    renderer_->Stop();
  }
  gameRunning_ = false;
  gamePaused_ = false;
}

void LibretroGameApp::RunFrame() {
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_ && gameRunning_ && !gamePaused_) {
    renderer_->RunFrame();
  }
}

static void OnVSyncCallback(long long timestamp, void *data);

bool LibretroGameApp::RequestCloseContent() {
  bool expected = false;
  if (!closeContentRequested_.compare_exchange_strong(expected, true)) {
    return true;
  }

  {
    std::lock_guard<std::mutex> lock(stateMutex_);
    if (!nativeVSync_) {
      std::string vsyncName = "libretro_vsync_" + id_;
      nativeVSync_ = OH_NativeVSync_Create(vsyncName.c_str(), vsyncName.length());
      if (!nativeVSync_) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "RequestCloseContent: Failed to create NativeVSync");
        closeContentRequested_.store(false);
        return false;
      }
    }

    OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
  }
  return true;
}

void LibretroGameApp::SetButtonState(unsigned port, unsigned buttonId,
                                     bool pressed) {
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (renderer_) {
    renderer_->SetButtonState(port, 1, 0, buttonId, pressed);
  }
}

// ========== VSync 管理（完全参考 Game2048NativeApp）==========

// VSync 回调函数
static void OnVSyncCallback(long long timestamp, void *data) {
  LibretroGameApp *app = static_cast<LibretroGameApp *>(data);
  if (app) {
    app->OnVSyncFrame(timestamp);
  }
}

void LibretroGameApp::StartVSync() {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StartVSync: %{public}s", id_.c_str());

  std::lock_guard<std::mutex> lock(stateMutex_);
  if (vsyncRunning_) {
    OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "VSync already running");
    return;
  }

  // 创建 VSync 实例
  if (!nativeVSync_) {
    std::string vsyncName = "libretro_vsync_" + id_;
    nativeVSync_ = OH_NativeVSync_Create(vsyncName.c_str(), vsyncName.length());
    if (!nativeVSync_) {
      OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create NativeVSync");
      return;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ NativeVSync created: %{public}s",
                vsyncName.c_str());
  }

  vsyncRunning_ = true;

  // 请求第一帧
  OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ VSync started (跟随系统帧率)");
}

void LibretroGameApp::StopVSync() {
  std::lock_guard<std::mutex> lock(stateMutex_);
  if (vsyncRunning_) {
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "StopVSync: %{public}s", id_.c_str());
    vsyncRunning_ = false;
  }
}

void LibretroGameApp::OnVSyncFrame(long long timestamp) {
  if (closeContentRequested_.exchange(false)) {
    std::lock_guard<std::mutex> lock(stateMutex_);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "CloseContent pending: %{public}s", id_.c_str());
    vsyncRunning_ = false;
    if (renderer_) {
      renderer_->ClearButtonStates();
      renderer_->Stop();
      renderer_->UnloadRom();
      renderer_->UnloadCore();
    }
    gameRunning_ = false;
    gamePaused_ = false;
    return;
  }

  std::lock_guard<std::mutex> lock(stateMutex_);
  if (!vsyncRunning_ || !gameRunning_ || gamePaused_) {
    return;
  }

  if (renderer_) {
    renderer_->RunFrame();
  }

  if (vsyncRunning_ && nativeVSync_) {
    OH_NativeVSync_RequestFrame(nativeVSync_, OnVSyncCallback, this);
  }
}
