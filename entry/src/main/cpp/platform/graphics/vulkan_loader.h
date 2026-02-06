#ifndef PLATFORM_GRAPHICS_VULKAN_LOADER_H
#define PLATFORM_GRAPHICS_VULKAN_LOADER_H

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_ohos.h>

namespace libretro {

struct VulkanApi {
  PFN_vkGetInstanceProcAddr get_instance_proc_addr = nullptr;
  PFN_vkGetDeviceProcAddr get_device_proc_addr = nullptr;
  PFN_vkCreateInstance create_instance = nullptr;
  PFN_vkEnumerateInstanceExtensionProperties enumerate_instance_extension_properties = nullptr;
  PFN_vkEnumerateInstanceLayerProperties enumerate_instance_layer_properties = nullptr;

  PFN_vkDestroyInstance destroy_instance = nullptr;
  PFN_vkEnumeratePhysicalDevices enumerate_physical_devices = nullptr;
  PFN_vkEnumerateDeviceExtensionProperties enumerate_device_extension_properties = nullptr;
  PFN_vkGetPhysicalDeviceQueueFamilyProperties get_physical_device_queue_family_properties = nullptr;
  PFN_vkGetPhysicalDeviceSurfaceSupportKHR get_physical_device_surface_support_khr = nullptr;
  PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR get_physical_device_surface_capabilities_khr = nullptr;
  PFN_vkGetPhysicalDeviceSurfaceFormatsKHR get_physical_device_surface_formats_khr = nullptr;
  PFN_vkGetPhysicalDeviceSurfacePresentModesKHR get_physical_device_surface_present_modes_khr = nullptr;
  PFN_vkCreateDevice create_device = nullptr;
  PFN_vkDestroySurfaceKHR destroy_surface_khr = nullptr;
  PFN_vkCreateSurfaceOHOS create_surface_ohos = nullptr;

  PFN_vkDestroyDevice destroy_device = nullptr;
  PFN_vkGetDeviceQueue get_device_queue = nullptr;
  PFN_vkDeviceWaitIdle device_wait_idle = nullptr;
  PFN_vkCreateSwapchainKHR create_swapchain_khr = nullptr;
  PFN_vkDestroySwapchainKHR destroy_swapchain_khr = nullptr;
  PFN_vkGetSwapchainImagesKHR get_swapchain_images_khr = nullptr;
  PFN_vkAcquireNextImageKHR acquire_next_image_khr = nullptr;
  PFN_vkQueuePresentKHR queue_present_khr = nullptr;
  PFN_vkQueueSubmit queue_submit = nullptr;
  PFN_vkCreateSemaphore create_semaphore = nullptr;
  PFN_vkDestroySemaphore destroy_semaphore = nullptr;
  PFN_vkCreateFence create_fence = nullptr;
  PFN_vkDestroyFence destroy_fence = nullptr;
  PFN_vkResetFences reset_fences = nullptr;
  PFN_vkWaitForFences wait_for_fences = nullptr;
  PFN_vkCreateCommandPool create_command_pool = nullptr;
  PFN_vkDestroyCommandPool destroy_command_pool = nullptr;
  PFN_vkAllocateCommandBuffers allocate_command_buffers = nullptr;
  PFN_vkFreeCommandBuffers free_command_buffers = nullptr;
  PFN_vkResetCommandBuffer reset_command_buffer = nullptr;
  PFN_vkBeginCommandBuffer begin_command_buffer = nullptr;
  PFN_vkEndCommandBuffer end_command_buffer = nullptr;
  PFN_vkCmdPipelineBarrier cmd_pipeline_barrier = nullptr;
  PFN_vkCmdBlitImage cmd_blit_image = nullptr;
  PFN_vkCmdCopyImage cmd_copy_image = nullptr;
};

class VulkanLoader {
public:
  bool Initialize();
  void Shutdown();
  bool IsReady() const { return ready_; }

  bool LoadInstanceFunctions(VkInstance instance);
  bool LoadDeviceFunctions(VkDevice device);

  const VulkanApi &GetApi() const { return api_; }

private:
  void *handle_ = nullptr;
  bool ready_ = false;
  VulkanApi api_{};
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_VULKAN_LOADER_H
