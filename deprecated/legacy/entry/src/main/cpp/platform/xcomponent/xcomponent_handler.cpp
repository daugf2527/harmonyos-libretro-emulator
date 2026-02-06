/*
 * HarmonyOS XComponent 回调处理
 * Platform层：管理XComponent的Surface生命周期和NativeWindow
 */

#include "platform/graphics/libretro_native_renderer.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <js_native_api.h>
#include <js_native_api_types.h>
#include <mutex>
#include <native_window/external_window.h>
#include <string>
#include <unordered_map>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "XComponentHandler"

// XComponent 回调处理
extern "C" {

// 全局渲染器实例映射（用于 Surface 创建时保存 NativeWindow）
static std::unordered_map<std::string, OHNativeWindow *> g_pendingWindows;
static std::mutex g_windowsMutex;

// Surface 创建回调
void OnSurfaceCreated(OH_NativeXComponent *component, void *window) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "========== XComponent: Surface Created ==========");

  // 获取 XComponent ID
  char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
  uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
  OH_NativeXComponent_GetXComponentId(component, idStr, &idSize);

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "XComponent ID: %{public}s", idStr);

  // 将 window 转换为 OHNativeWindow
  OHNativeWindow *nativeWindow = static_cast<OHNativeWindow *>(window);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "NativeWindow 指针: %{public}p", nativeWindow);

  // 固定使用 "libretro_renderer" 作为渲染器 ID
  std::string rendererId = "libretro_renderer";

  // 尝试获取已存在的渲染器实例（使用libretro命名空间）
  libretro::LibretroNativeRenderer *renderer =
      libretro::LibretroNativeRenderer::GetInstance(rendererId);
  if (renderer) {
    // 渲染器已创建，直接设置 NativeWindow
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "找到已存在的渲染器实例，设置 NativeWindow");
    renderer->Initialize(nativeWindow);
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ NativeWindow 已保存到渲染器: %{public}s",
                rendererId.c_str());
  } else {
    // 渲染器还未创建，保存 NativeWindow 等待后续使用
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "渲染器实例尚未创建，保存 NativeWindow 待用");
    std::lock_guard<std::mutex> lock(g_windowsMutex);
    auto itOld = g_pendingWindows.find(rendererId);
    if (itOld != g_pendingWindows.end()) {
      if (itOld->second) {
        OH_NativeWindow_NativeObjectUnreference(itOld->second);
      }
      g_pendingWindows.erase(itOld);
    }

    if (nativeWindow) {
      OH_NativeWindow_NativeObjectReference(nativeWindow);
    }
    g_pendingWindows[rendererId] = nativeWindow;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ NativeWindow 已保存到待用队列: %{public}s",
                rendererId.c_str());
  }

  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "========== Surface Created 完成 ==========");
}

// Surface 改变回调
void OnSurfaceChanged(OH_NativeXComponent *component, void *window) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "XComponent: Surface Changed");

  // 获取窗口大小
  uint64_t width = 0, height = 0;
  OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Window size: %{public}lux%{public}lu", width, height);
}

// Surface 销毁回调
void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window) {
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "XComponent: Surface Destroyed");

  std::string rendererId = "libretro_renderer";
  std::lock_guard<std::mutex> lock(g_windowsMutex);
  auto it = g_pendingWindows.find(rendererId);
  if (it != g_pendingWindows.end()) {
    if (it->second) {
      OH_NativeWindow_NativeObjectUnreference(it->second);
    }
    g_pendingWindows.erase(it);
  }
}

// 分发触摸事件回调
void DispatchTouchEvent(OH_NativeXComponent *component, void *window) {
  // 触摸事件处理（如果需要）
}

// 获取待用的 NativeWindow（供 NAPI 层调用）
OHNativeWindow *GetPendingNativeWindow(const std::string &rendererId) {
  std::lock_guard<std::mutex> lock(g_windowsMutex);
  auto it = g_pendingWindows.find(rendererId);
  if (it != g_pendingWindows.end()) {
    OHNativeWindow *window = it->second;
    g_pendingWindows.erase(it); // 使用后移除
    if (window) {
      OH_NativeWindow_NativeObjectUnreference(window);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ 从待用队列获取 NativeWindow: %{public}s",
                rendererId.c_str());
    return window;
  }
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "⚠️ 待用队列中没有 NativeWindow: %{public}s",
              rendererId.c_str());
  return nullptr;
}

} // extern "C"

// 注册 XComponent 回调
extern "C" void RegisterXComponentCallbacks(OH_NativeXComponent *component) {
  OH_NativeXComponent_Callback callback;
  callback.OnSurfaceCreated = OnSurfaceCreated;
  callback.OnSurfaceChanged = OnSurfaceChanged;
  callback.OnSurfaceDestroyed = OnSurfaceDestroyed;
  callback.DispatchTouchEvent = DispatchTouchEvent;

  OH_NativeXComponent_RegisterCallback(component, &callback);
  OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "✅ XComponent callbacks registered");
}
