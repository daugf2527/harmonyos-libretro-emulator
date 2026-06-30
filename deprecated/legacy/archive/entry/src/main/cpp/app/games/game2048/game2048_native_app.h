/*
 * Phase 3.2 - Game2048 Native 应用
 * Phase 3.5 - 完整的 Environment 回调支持
 * 完整的 Libretro + NativeWindow 渲染方案
 *
 * 架构:
 * - XComponent → OnSurfaceCreated → 获取 NativeWindow
 * - Libretro video_refresh → 直接渲染到 NativeWindow
 * - 零拷贝,高性能
 */

#ifndef GAME2048_NATIVE_APP_H
#define GAME2048_NATIVE_APP_H

#include "core/libretro/env_dispatcher.h"
#include "platform/graphics/game2048_native_renderer.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <memory>
#include <mutex>
#include <native_vsync/native_vsync.h>
#include <native_window/external_window.h>
#include <string>

// 前向声明静态回调函数
static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window);
static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window);
static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window);

class Game2048NativeApp {
public:
  explicit Game2048NativeApp(const std::string &id);
  ~Game2048NativeApp();

  // XComponent 回调注册
  void RegisterCallback(OH_NativeXComponent *nativeXComponent);

  // 友元声明 (允许静态回调函数访问 private 成员)
  friend void ::OnSurfaceCreatedCB(OH_NativeXComponent *component,
                                   void *window);
  friend void ::OnSurfaceChangedCB(OH_NativeXComponent *component,
                                   void *window);
  friend void ::OnSurfaceDestroyedCB(OH_NativeXComponent *component,
                                     void *window);

  // XComponent 回调
  void OnSurfaceCreated(OHNativeWindow *window);
  void OnSurfaceChanged(OHNativeWindow *window, int32_t width, int32_t height);
  void OnSurfaceDestroyed();

  // 游戏控制
  bool InitGame(const std::string &soPath,
                const std::string &filesDir = std::string());
  void StartVSync(); // 启动 VSync 驱动
  void StopVSync();  // 停止 VSync
  void ResetGame();
  void DeinitGame();
  void SetInput(int keyId, bool pressed);

  // 获取实例 ID
  std::string GetId() const { return id_; }

  // VSync 回调
  void OnVSyncFrame(long long timestamp);

private:
  std::string id_;
  std::shared_ptr<Game2048NativeRenderer> renderer_;

  // Libretro 核心
  void *libretroHandle_ = nullptr;
  bool gameRunning_ = false;
  std::mutex stateMutex_;

  // Env 状态（方案B：通用 EnvDispatcher）
  libretro::EnvState envState_;

  // VSync 管理
  OH_NativeVSync *nativeVSync_ = nullptr;
  bool vsyncRunning_ = false;

  // Libretro 函数指针
  void (*retro_init_)(void) = nullptr;
  void (*retro_deinit_)(void) = nullptr;
  void (*retro_reset_)(void) = nullptr;
  void (*retro_run_)(void) = nullptr;
  bool (*retro_load_game_)(void *) = nullptr;
  void (*retro_unload_game_)(void) = nullptr;

  // 输入状态
  bool inputState_[16] = {false};

  // 静态回调函数
  static void VideoRefreshCallback(const void *data, unsigned width,
                                   unsigned height, size_t pitch);
  static bool EnvironmentCallback(unsigned cmd, void *data);
  static void InputPollCallback(void);
  static int16_t InputStateCallback(unsigned port, unsigned device,
                                    unsigned index, unsigned id);
  static void AudioSampleCallback(int16_t left, int16_t right);
  static size_t AudioSampleBatchCallback(const int16_t *data, size_t frames);

  // 全局实例指针 (用于静态回调)
  static Game2048NativeApp *s_instance;

  // XComponent 回调结构 (成员变量,避免局部变量生命周期问题)
  OH_NativeXComponent_Callback renderCallback_;
};

#endif // GAME2048_NATIVE_APP_H
