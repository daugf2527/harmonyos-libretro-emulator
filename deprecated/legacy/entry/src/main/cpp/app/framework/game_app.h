/*
 * Libretro 游戏应用 - 完全参考 Game2048NativeApp 架构
 */

#ifndef LIBRETRO_GAME_APP_H
#define LIBRETRO_GAME_APP_H

#include "platform/graphics/libretro_native_renderer.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <native_vsync/native_vsync.h>
#include <native_window/external_window.h>
#include <string>

class LibretroGameApp {
public:
  explicit LibretroGameApp(const std::string &id);
  ~LibretroGameApp();

  // XComponent 回调注册（对应 Game2048NativeApp::RegisterCallback）
  void RegisterCallback(OH_NativeXComponent *nativeXComponent);

  // XComponent 回调（对应 Game2048NativeApp 的回调）
  void OnSurfaceCreated(OHNativeWindow *window);
  void OnSurfaceChanged(OHNativeWindow *window, int32_t width, int32_t height);
  void OnSurfaceDestroyed();

  // 游戏控制（对应 Game2048NativeApp 的游戏控制）
  bool LoadCore(const std::string &corePath,
                const std::string &filesDir = std::string(),
                const std::string &cacheDir = std::string());
  bool LoadRom(const std::string &romPath,
               NativeResourceManager *nativeResourceManager,
               const std::string &filesDir = std::string(),
               const std::string &cacheDir = std::string());
  void StartGame();
  void PauseGame();
  void StopGame();
  void RunFrame();
  bool RequestCloseContent();

  // 输入控制
  void SetButtonState(unsigned port, unsigned buttonId, bool pressed);

  // 获取渲染器
  libretro::LibretroNativeRenderer *GetRenderer() { return renderer_.get(); }

  // VSync 回调（需要 public 以便静态回调函数访问）
  void OnVSyncFrame(long long timestamp);

private:
  void StartVSync();
  void StopVSync();

  std::string id_;
  std::shared_ptr<libretro::LibretroNativeRenderer> renderer_;

  // VSync 相关
  OH_NativeVSync *nativeVSync_ = nullptr;
  bool vsyncRunning_ = false;
  std::mutex stateMutex_;

  // XComponent 回调结构
  OH_NativeXComponent_Callback renderCallback_;

  // 游戏状态
  bool gameRunning_ = false;
  bool gamePaused_ = false;

  std::atomic<bool> closeContentRequested_{false};
};

#endif // LIBRETRO_GAME_APP_H
