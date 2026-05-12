#ifndef PLATFORM_GRAPHICS_VULKAN_CONTEXT_H
#define PLATFORM_GRAPHICS_VULKAN_CONTEXT_H

#include "vulkan_loader.h"
#include <atomic>
#include <native_window/external_window.h>
#include <vector>

#include "core/libretro/libretro_vulkan.h"

namespace libretro {

class EnvState;

class VulkanContext {
public:
  VulkanContext() = default;
  ~VulkanContext();

  bool Initialize(OHNativeWindow *window, const EnvState &env);
  bool RecreateSwapchain(OHNativeWindow *window, int width, int height);
  void Destroy();

  bool IsReady() const { return ready_; }

  const VulkanApi &GetApi() const { return loader_.GetApi(); }
  VkInstance GetInstance() const { return instance_; }
  VkPhysicalDevice GetGpu() const { return gpu_; }
  VkDevice GetDevice() const { return device_; }
  VkQueue GetQueue() const { return queue_; }
  VkQueue GetPresentQueue() const { return present_queue_; }
  uint32_t GetQueueFamilyIndex() const { return queue_family_index_; }
  uint32_t GetPresentQueueFamilyIndex() const { return present_queue_family_index_; }
  VkSurfaceKHR GetSurface() const { return surface_; }
  VkSwapchainKHR GetSwapchain() const { return swapchain_; }
  VkFormat GetSwapchainFormat() const { return swapchain_format_; }
  VkImageUsageFlags GetSwapchainImageUsage() const { return swapchain_usage_; }
  VkExtent2D GetSwapchainExtent() const { return swapchain_extent_; }
  const std::vector<VkImage> &GetSwapchainImages() const { return swapchain_images_; }
  bool ShouldRecreateSwapchain() const { return swapchain_out_of_date_; }
  void ClearSwapchainOutOfDate() { swapchain_out_of_date_ = false; }
  void MarkSwapchainOutOfDate() { swapchain_out_of_date_ = true; }

private:
  bool CreateInstance(const EnvState &env);
  bool CreateSurface(OHNativeWindow *window);
  bool CreateDevice(const EnvState &env);
  bool CreateSwapchain(int width, int height);
  void DestroySwapchain();

  VkInstance CreateInstanceWithWrapper(const VkInstanceCreateInfo &create_info);
  VkDevice CreateDeviceWithWrapper(VkPhysicalDevice gpu, const VkDeviceCreateInfo &create_info);

  bool PickPhysicalDevice();
  bool PickQueueFamily(VkPhysicalDevice gpu, uint32_t &graphics_index,
                       uint32_t &present_index);
  bool CheckDeviceExtensions(VkPhysicalDevice gpu,
                             const std::vector<const char *> &required);

  static VkInstance CreateInstanceWrapper(void *opaque,
                                          const VkInstanceCreateInfo *create_info);
  static VkDevice CreateDeviceWrapper(VkPhysicalDevice gpu, void *opaque,
                                      const VkDeviceCreateInfo *create_info);

private:
  VulkanLoader loader_;
  bool ready_ = false;

  VkInstance instance_ = VK_NULL_HANDLE;
  VkPhysicalDevice gpu_ = VK_NULL_HANDLE;
  VkDevice device_ = VK_NULL_HANDLE;
  VkQueue queue_ = VK_NULL_HANDLE;
  VkQueue present_queue_ = VK_NULL_HANDLE;
  uint32_t queue_family_index_ = 0;
  uint32_t present_queue_family_index_ = 0;
  VkSurfaceKHR surface_ = VK_NULL_HANDLE;
  VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
  VkFormat swapchain_format_ = VK_FORMAT_UNDEFINED;
  VkImageUsageFlags swapchain_usage_ = 0;
  VkExtent2D swapchain_extent_{};
  std::vector<VkImage> swapchain_images_;
  OHNativeWindow *window_ = nullptr;

  std::vector<const char *> instance_extensions_;
  std::vector<const char *> device_extensions_;

  retro_hw_render_context_negotiation_interface_vulkan negotiation_{};
  bool has_negotiation_ = false;
  std::atomic<bool> swapchain_out_of_date_{false};

  retro_vulkan_context core_context_{};
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_VULKAN_CONTEXT_H
