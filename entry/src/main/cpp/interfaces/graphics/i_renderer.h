/*
 * 渲染器接口 - 符合Libretro和HarmonyOS规范
 *
 * 设计原则:
 * - 依赖倒置原则(DIP): App层依赖此接口，而非具体实现
 * - 单一职责原则(SRP): 只负责渲染相关操作
 * - 可测试性: 可注入MockRenderer进行测试
 */

#ifndef INTERFACES_I_RENDERER_H
#define INTERFACES_I_RENDERER_H

#include <cstddef>
#include <cstdint>
#include <native_window/external_window.h>

namespace interfaces {

/**
 * @brief 渲染器接口
 *
 * 对应规范:
 * - Libretro: retro_set_video_refresh 回调模式
 * - HarmonyOS: XComponent + NativeWindow 生命周期
 */
class IRenderer {
public:
  virtual ~IRenderer() = default;

  /**
   * @brief 初始化渲染器
   * @param window HarmonyOS NativeWindow句柄
   * @return true 初始化成功，false 失败
   */
  virtual bool Initialize(OHNativeWindow *window) = 0;

  /**
   * @brief 释放渲染器资源
   */
  virtual void Release() = 0;

  /**
   * @brief 渲染一帧数据
   * @param data 像素数据（符合Libretro retro_video_refresh_t）
   * @param width 画面宽度
   * @param height 画面高度
   * @param pitch 每行字节数
   */
  virtual void Render(const void *data, int width, int height,
                      size_t pitch) = 0;

  /**
   * @brief 处理Surface尺寸变化
   * @param width 新宽度
   * @param height 新高度
   */
  virtual void OnSurfaceChanged(int width, int height) = 0;

  /**
   * @brief 获取当前渲染器宽度
   */
  virtual int GetWidth() const = 0;

  /**
   * @brief 获取当前渲染器高度
   */
  virtual int GetHeight() const = 0;

  // --- 视频配置接口 (对应 ArkTS refactoredSet... 接口) ---

  /**
   * @brief 设置缩放模式
   * @param mode 0=Hardware, 1=Software, 2=GLES
   */
  virtual bool SetScalingMode(int mode) = 0;

  /**
   * @brief 设置软件渲染最大分辨率
   */
  virtual bool SetSoftwareMaxResolution(int maxWidth, int maxHeight) = 0;

  /**
   * @brief 启用/禁用 AI 超分
   */
  virtual bool SetAIUpscale(bool enabled) = 0;

  /**
   * @brief 允许/禁止硬件渲染
   */
  virtual bool SetHwRenderAllowed(bool enabled) = 0;
};

} // namespace interfaces

#endif // INTERFACES_I_RENDERER_H
