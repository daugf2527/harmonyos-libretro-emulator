#include "vulkan_loader.h"
#include <dlfcn.h>
#include <hilog/log.h>
#include <type_traits>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD00D
#undef LOG_TAG
#define LOG_TAG "VulkanLoader"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

namespace {

template <typename T>
bool LoadSymbol(void *handle, const char *name, T &out) {
  out = reinterpret_cast<T>(dlsym(handle, name));
  if (!out) {
    LOGF(LOG_WARN, "Failed to load %{public}s", name);
    return false;
  }
  return true;
}

} // namespace

bool VulkanLoader::Initialize() {
  if (ready_) {
    return true;
  }
  handle_ = dlopen("libvulkan.so", RTLD_LAZY | RTLD_LOCAL);
  if (!handle_) {
    LOGF(LOG_WARN, "dlopen libvulkan.so failed");
    return false;
  }

  bool ok = true;
  ok &= LoadSymbol(handle_, "vkGetInstanceProcAddr",
                   api_.get_instance_proc_addr);
  ok &= LoadSymbol(handle_, "vkGetDeviceProcAddr",
                   api_.get_device_proc_addr);
  ok &= LoadSymbol(handle_, "vkCreateInstance", api_.create_instance);
  ok &= LoadSymbol(handle_, "vkEnumerateInstanceExtensionProperties",
                   api_.enumerate_instance_extension_properties);
  LoadSymbol(handle_, "vkEnumerateInstanceLayerProperties",
             api_.enumerate_instance_layer_properties);

  if (!ok) {
    Shutdown();
    return false;
  }

  ready_ = true;
  LOGF(LOG_INFO, "Vulkan loader initialized");
  return true;
}

void VulkanLoader::Shutdown() {
  if (handle_) {
    dlclose(handle_);
    handle_ = nullptr;
  }
  ready_ = false;
  api_ = VulkanApi{};
}

bool VulkanLoader::LoadInstanceFunctions(VkInstance instance) {
  if (!ready_ || !api_.get_instance_proc_addr || instance == VK_NULL_HANDLE) {
    return false;
  }

  auto load = [&](auto &fn, const char *name) {
    using Fn = std::remove_reference_t<decltype(fn)>;
    fn = reinterpret_cast<Fn>(
        api_.get_instance_proc_addr(instance, name));
    if (!fn) {
      LOGF(LOG_WARN, "Missing instance function %{public}s", name);
      return false;
    }
    return true;
  };

  bool ok = true;
  ok &= load(api_.destroy_instance, "vkDestroyInstance");
  ok &= load(api_.enumerate_physical_devices, "vkEnumeratePhysicalDevices");
  ok &= load(api_.enumerate_device_extension_properties,
             "vkEnumerateDeviceExtensionProperties");
  ok &= load(api_.get_physical_device_queue_family_properties,
             "vkGetPhysicalDeviceQueueFamilyProperties");
  ok &= load(api_.get_physical_device_surface_support_khr,
             "vkGetPhysicalDeviceSurfaceSupportKHR");
  ok &= load(api_.get_physical_device_surface_capabilities_khr,
             "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
  ok &= load(api_.get_physical_device_surface_formats_khr,
             "vkGetPhysicalDeviceSurfaceFormatsKHR");
  ok &= load(api_.get_physical_device_surface_present_modes_khr,
             "vkGetPhysicalDeviceSurfacePresentModesKHR");
  ok &= load(api_.create_device, "vkCreateDevice");
  ok &= load(api_.destroy_surface_khr, "vkDestroySurfaceKHR");
  ok &= load(api_.create_surface_ohos, "vkCreateSurfaceOHOS");
  return ok;
}

bool VulkanLoader::LoadDeviceFunctions(VkDevice device) {
  if (!ready_ || !api_.get_device_proc_addr || device == VK_NULL_HANDLE) {
    return false;
  }

  auto load = [&](auto &fn, const char *name) {
    using Fn = std::remove_reference_t<decltype(fn)>;
    fn = reinterpret_cast<Fn>(
        api_.get_device_proc_addr(device, name));
    if (!fn) {
      LOGF(LOG_WARN, "Missing device function %{public}s", name);
      return false;
    }
    return true;
  };

  bool ok = true;
  ok &= load(api_.destroy_device, "vkDestroyDevice");
  ok &= load(api_.get_device_queue, "vkGetDeviceQueue");
  ok &= load(api_.device_wait_idle, "vkDeviceWaitIdle");
  ok &= load(api_.create_swapchain_khr, "vkCreateSwapchainKHR");
  ok &= load(api_.destroy_swapchain_khr, "vkDestroySwapchainKHR");
  ok &= load(api_.get_swapchain_images_khr, "vkGetSwapchainImagesKHR");
  ok &= load(api_.acquire_next_image_khr, "vkAcquireNextImageKHR");
  ok &= load(api_.queue_present_khr, "vkQueuePresentKHR");
  ok &= load(api_.queue_submit, "vkQueueSubmit");
  ok &= load(api_.create_semaphore, "vkCreateSemaphore");
  ok &= load(api_.destroy_semaphore, "vkDestroySemaphore");
  ok &= load(api_.create_fence, "vkCreateFence");
  ok &= load(api_.destroy_fence, "vkDestroyFence");
  ok &= load(api_.reset_fences, "vkResetFences");
  ok &= load(api_.wait_for_fences, "vkWaitForFences");
  ok &= load(api_.create_command_pool, "vkCreateCommandPool");
  ok &= load(api_.destroy_command_pool, "vkDestroyCommandPool");
  ok &= load(api_.allocate_command_buffers, "vkAllocateCommandBuffers");
  ok &= load(api_.free_command_buffers, "vkFreeCommandBuffers");
  ok &= load(api_.reset_command_buffer, "vkResetCommandBuffer");
  ok &= load(api_.begin_command_buffer, "vkBeginCommandBuffer");
  ok &= load(api_.end_command_buffer, "vkEndCommandBuffer");
  ok &= load(api_.cmd_pipeline_barrier, "vkCmdPipelineBarrier");
  ok &= load(api_.cmd_blit_image, "vkCmdBlitImage");
  ok &= load(api_.cmd_copy_image, "vkCmdCopyImage");
  return ok;
}

} // namespace libretro
