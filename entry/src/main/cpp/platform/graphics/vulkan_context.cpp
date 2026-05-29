#include "vulkan_context.h"
#include "core/libretro/env_dispatcher.h"
#include <algorithm>
#include <cstring>
#include <hilog/log.h>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD00C
#undef LOG_TAG
#define LOG_TAG "VulkanContext"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

namespace {

std::vector<const char *> MergeExtensions(const char *const *names,
                                          uint32_t count,
                                          const std::vector<const char *> &extra) {
  std::vector<const char *> merged;
  merged.reserve(count + extra.size());
  for (uint32_t i = 0; i < count; ++i) {
    merged.push_back(names[i]);
  }
  for (auto *name : extra) {
    bool exists = false;
    for (auto *existing : merged) {
      if (std::strcmp(existing, name) == 0) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      merged.push_back(name);
    }
  }
  return merged;
}

VkApplicationInfo DefaultApplicationInfo() {
  VkApplicationInfo app{};
  app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  app.pApplicationName = "libretro_harmonyos";
  app.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
  app.pEngineName = "libretro_frontend";
  app.engineVersion = VK_MAKE_VERSION(1, 0, 0);
  app.apiVersion = VK_API_VERSION_1_1;
  return app;
}

} // namespace

VulkanContext::~VulkanContext() { Destroy(); }

bool VulkanContext::Initialize(OHNativeWindow *window, const EnvState &env) {
  if (!window) {
    return false;
  }
  if (!loader_.Initialize()) {
    return false;
  }

  instance_extensions_ = {VK_KHR_SURFACE_EXTENSION_NAME,
                          VK_OHOS_SURFACE_EXTENSION_NAME};
  device_extensions_ = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};

  if (env.HasVulkanNegotiationInterface()) {
    negotiation_ = *env.GetVulkanNegotiationInterface();
    has_negotiation_ = true;
  } else {
    has_negotiation_ = false;
  }

  if (!CreateInstance(env)) {
    Destroy();
    return false;
  }
  if (!loader_.LoadInstanceFunctions(instance_)) {
    LOGF(LOG_ERROR, "LoadInstanceFunctions failed");
    Destroy();
    return false;
  }
  if (!CreateSurface(window)) {
    Destroy();
    return false;
  }
  if (!CreateDevice(env)) {
    Destroy();
    return false;
  }
  if (!loader_.LoadDeviceFunctions(device_)) {
    LOGF(LOG_ERROR, "LoadDeviceFunctions failed");
    Destroy();
    return false;
  }
  if (!CreateSwapchain(0, 0)) {
    Destroy();
    return false;
  }

  ready_ = true;
  return true;
}

bool VulkanContext::RecreateSwapchain(OHNativeWindow *window, int width,
                                      int height) {
  if (!device_ || !loader_.GetApi().device_wait_idle) {
    return false;
  }
  loader_.GetApi().device_wait_idle(device_);
  swapchain_out_of_date_ = false;

  if (window && window != window_) {
    DestroySwapchain();
    if (surface_ != VK_NULL_HANDLE && loader_.GetApi().destroy_surface_khr) {
      loader_.GetApi().destroy_surface_khr(instance_, surface_, nullptr);
      surface_ = VK_NULL_HANDLE;
    }
    if (!CreateSurface(window)) {
      return false;
    }
  } else {
    DestroySwapchain();
  }

  return CreateSwapchain(width, height);
}

void VulkanContext::Destroy() {
  ready_ = false;

  if (device_ && loader_.GetApi().device_wait_idle) {
    loader_.GetApi().device_wait_idle(device_);
  }
  DestroySwapchain();

  if (has_negotiation_ && negotiation_.destroy_device) {
    negotiation_.destroy_device();
    device_ = VK_NULL_HANDLE;
  }
  if (device_ && loader_.GetApi().destroy_device) {
    loader_.GetApi().destroy_device(device_, nullptr);
  }
  device_ = VK_NULL_HANDLE;
  queue_ = VK_NULL_HANDLE;
  present_queue_ = VK_NULL_HANDLE;
  queue_family_index_ = 0;
  present_queue_family_index_ = 0;

  if (surface_ != VK_NULL_HANDLE && loader_.GetApi().destroy_surface_khr) {
    loader_.GetApi().destroy_surface_khr(instance_, surface_, nullptr);
  }
  surface_ = VK_NULL_HANDLE;
  window_ = nullptr;

  if (instance_ != VK_NULL_HANDLE && loader_.GetApi().destroy_instance) {
    loader_.GetApi().destroy_instance(instance_, nullptr);
  }
  instance_ = VK_NULL_HANDLE;
  gpu_ = VK_NULL_HANDLE;
  loader_.Shutdown();
}

bool VulkanContext::CreateInstance(const EnvState &env) {
  const auto &api = loader_.GetApi();
  if (!api.create_instance) {
    return false;
  }

  VkApplicationInfo app = DefaultApplicationInfo();
  const VkApplicationInfo *app_ptr = &app;
  if (has_negotiation_ && negotiation_.get_application_info) {
    const VkApplicationInfo *core_app = negotiation_.get_application_info();
    if (core_app) {
      app_ptr = core_app;
    }
  }

  if (has_negotiation_ && negotiation_.interface_version >=
                              RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN_VERSION &&
      negotiation_.create_instance) {
    instance_ = negotiation_.create_instance(
        api.get_instance_proc_addr, app_ptr, CreateInstanceWrapper, this);
    if (instance_ != VK_NULL_HANDLE) {
      return true;
    }
    LOGF(LOG_WARN, "Core create_instance failed, fallback");
  }

  VkInstanceCreateInfo info{};
  info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  info.pApplicationInfo = app_ptr;
  info.enabledExtensionCount = static_cast<uint32_t>(instance_extensions_.size());
  info.ppEnabledExtensionNames = instance_extensions_.data();

  instance_ = CreateInstanceWithWrapper(info);
  return instance_ != VK_NULL_HANDLE;
}

VkInstance VulkanContext::CreateInstanceWithWrapper(
    const VkInstanceCreateInfo &create_info) {
  const auto &api = loader_.GetApi();
  VkInstance instance = VK_NULL_HANDLE;
  auto merged = MergeExtensions(create_info.ppEnabledExtensionNames,
                                create_info.enabledExtensionCount,
                                instance_extensions_);
  VkInstanceCreateInfo info = create_info;
  info.enabledExtensionCount = static_cast<uint32_t>(merged.size());
  info.ppEnabledExtensionNames = merged.data();
  if (api.create_instance(&info, nullptr, &instance) != VK_SUCCESS) {
    return VK_NULL_HANDLE;
  }
  return instance;
}

VkInstance VulkanContext::CreateInstanceWrapper(void *opaque,
                                                const VkInstanceCreateInfo *info) {
  auto *self = reinterpret_cast<VulkanContext *>(opaque);
  if (!self || !info) {
    return VK_NULL_HANDLE;
  }
  return self->CreateInstanceWithWrapper(*info);
}

bool VulkanContext::CreateSurface(OHNativeWindow *window) {
  if (!window || !loader_.GetApi().create_surface_ohos) {
    return false;
  }
  VkSurfaceCreateInfoOHOS info{};
  info.sType = VK_STRUCTURE_TYPE_SURFACE_CREATE_INFO_OHOS;
  info.window = window;
  if (loader_.GetApi().create_surface_ohos(instance_, &info, nullptr,
                                           &surface_) != VK_SUCCESS) {
    LOGF(LOG_ERROR, "vkCreateSurfaceOHOS failed");
    return false;
  }
  window_ = window;
  return true;
}

bool VulkanContext::CreateDevice(const EnvState &env) {
  const auto &api = loader_.GetApi();
  if (has_negotiation_) {
    std::memset(&core_context_, 0, sizeof(core_context_));
    bool ok = false;
    if (negotiation_.interface_version >=
            RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN_VERSION &&
        negotiation_.create_device2) {
      ok = negotiation_.create_device2(
          &core_context_, instance_, VK_NULL_HANDLE, surface_,
          api.get_instance_proc_addr, CreateDeviceWrapper, this);
      if (!ok) {
        LOGF(LOG_WARN, "Core create_device2 failed");
      }
    }
    if (!ok && negotiation_.create_device) {
      ok = negotiation_.create_device(
          &core_context_, instance_, VK_NULL_HANDLE, surface_,
          api.get_instance_proc_addr, device_extensions_.data(),
          static_cast<unsigned>(device_extensions_.size()), nullptr, 0, nullptr);
      if (!ok) {
        LOGF(LOG_WARN, "Core create_device failed");
      }
    }
    if (ok) {
      gpu_ = core_context_.gpu;
      device_ = core_context_.device;
      queue_ = core_context_.queue;
      queue_family_index_ = core_context_.queue_family_index;
      present_queue_ = core_context_.presentation_queue
                           ? core_context_.presentation_queue
                           : core_context_.queue;
      present_queue_family_index_ =
          core_context_.presentation_queue_family_index
              ? core_context_.presentation_queue_family_index
              : core_context_.queue_family_index;
      return device_ != VK_NULL_HANDLE;
    }
  }

  if (!PickPhysicalDevice()) {
    return false;
  }

  std::vector<uint32_t> families;
  families.push_back(queue_family_index_);
  if (present_queue_family_index_ != queue_family_index_) {
    families.push_back(present_queue_family_index_);
  }

  float priority = 1.0f;
  std::vector<VkDeviceQueueCreateInfo> queues;
  for (uint32_t family : families) {
    VkDeviceQueueCreateInfo q{};
    q.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    q.queueFamilyIndex = family;
    q.queueCount = 1;
    q.pQueuePriorities = &priority;
    queues.push_back(q);
  }

  VkDeviceCreateInfo info{};
  info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  info.queueCreateInfoCount = static_cast<uint32_t>(queues.size());
  info.pQueueCreateInfos = queues.data();
  info.enabledExtensionCount = static_cast<uint32_t>(device_extensions_.size());
  info.ppEnabledExtensionNames = device_extensions_.data();

  device_ = CreateDeviceWithWrapper(gpu_, info);
  if (device_ == VK_NULL_HANDLE) {
    return false;
  }
  api.get_device_queue(device_, queue_family_index_, 0, &queue_);
  if (present_queue_family_index_ != queue_family_index_) {
    api.get_device_queue(device_, present_queue_family_index_, 0,
                         &present_queue_);
  } else {
    present_queue_ = queue_;
  }
  return true;
}

VkDevice VulkanContext::CreateDeviceWithWrapper(
    VkPhysicalDevice gpu, const VkDeviceCreateInfo &create_info) {
  const auto &api = loader_.GetApi();
  VkDevice device = VK_NULL_HANDLE;
  auto merged = MergeExtensions(create_info.ppEnabledExtensionNames,
                                create_info.enabledExtensionCount,
                                device_extensions_);
  VkDeviceCreateInfo info = create_info;
  info.enabledExtensionCount = static_cast<uint32_t>(merged.size());
  info.ppEnabledExtensionNames = merged.data();
  if (api.create_device(gpu, &info, nullptr, &device) != VK_SUCCESS) {
    return VK_NULL_HANDLE;
  }
  return device;
}

VkDevice VulkanContext::CreateDeviceWrapper(VkPhysicalDevice gpu, void *opaque,
                                            const VkDeviceCreateInfo *info) {
  auto *self = reinterpret_cast<VulkanContext *>(opaque);
  if (!self || !info) {
    return VK_NULL_HANDLE;
  }
  return self->CreateDeviceWithWrapper(gpu, *info);
}

bool VulkanContext::PickPhysicalDevice() {
  const auto &api = loader_.GetApi();
  uint32_t count = 0;
  if (api.enumerate_physical_devices(instance_, &count, nullptr) != VK_SUCCESS ||
      count == 0) {
    return false;
  }
  std::vector<VkPhysicalDevice> devices(count);
  if (api.enumerate_physical_devices(instance_, &count, devices.data()) !=
      VK_SUCCESS) {
    return false;
  }
  for (auto dev : devices) {
    if (!CheckDeviceExtensions(dev, device_extensions_)) {
      continue;
    }
    uint32_t graphics = 0;
    uint32_t present = 0;
    if (PickQueueFamily(dev, graphics, present)) {
      gpu_ = dev;
      queue_family_index_ = graphics;
      present_queue_family_index_ = present;
      return true;
    }
  }
  return false;
}

bool VulkanContext::PickQueueFamily(VkPhysicalDevice gpu, uint32_t &graphics,
                                    uint32_t &present) {
  const auto &api = loader_.GetApi();
  uint32_t count = 0;
  api.get_physical_device_queue_family_properties(gpu, &count, nullptr);
  if (count == 0) {
    return false;
  }
  std::vector<VkQueueFamilyProperties> props(count);
  api.get_physical_device_queue_family_properties(gpu, &count, props.data());

  // First pass: prefer a single queue family that supports both graphics and
  // present — avoids the overhead of concurrent swapchain sharing mode.
  for (uint32_t i = 0; i < count; ++i) {
    if (!(props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
      continue;
    }
    VkBool32 supports_present = VK_FALSE;
    api.get_physical_device_surface_support_khr(gpu, i, surface_,
                                                &supports_present);
    if (supports_present) {
      graphics = i;
      present = i;
      return true;
    }
  }

  // Second pass: find separate graphics and present queue families.
  // Some devices expose a graphics queue that does not support present on the
  // given surface; in that case we must use a dedicated presentation queue.
  uint32_t graphics_family = UINT32_MAX;
  uint32_t present_family = UINT32_MAX;
  for (uint32_t i = 0; i < count; ++i) {
    if ((props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) &&
        graphics_family == UINT32_MAX) {
      graphics_family = i;
    }
    VkBool32 supports_present = VK_FALSE;
    api.get_physical_device_surface_support_khr(gpu, i, surface_,
                                                &supports_present);
    if (supports_present && present_family == UINT32_MAX) {
      present_family = i;
    }
    if (graphics_family != UINT32_MAX && present_family != UINT32_MAX) {
      break;
    }
  }
  if (graphics_family != UINT32_MAX && present_family != UINT32_MAX) {
    LOGF(LOG_WARN,
         "PickQueueFamily: using separate graphics(%{public}u) and "
         "present(%{public}u) queue families",
         graphics_family, present_family);
    graphics = graphics_family;
    present = present_family;
    return true;
  }
  return false;
}

bool VulkanContext::CheckDeviceExtensions(
    VkPhysicalDevice gpu, const std::vector<const char *> &required) {
  const auto &api = loader_.GetApi();
  uint32_t count = 0;
  if (api.enumerate_device_extension_properties(gpu, nullptr, &count, nullptr) !=
      VK_SUCCESS) {
    return false;
  }
  std::vector<VkExtensionProperties> props(count);
  if (api.enumerate_device_extension_properties(gpu, nullptr, &count,
                                                props.data()) != VK_SUCCESS) {
    return false;
  }
  for (auto *req : required) {
    bool found = false;
    for (const auto &p : props) {
      if (std::strcmp(p.extensionName, req) == 0) {
        found = true;
        break;
      }
    }
    if (!found) {
      return false;
    }
  }
  return true;
}

bool VulkanContext::CreateSwapchain(int width, int height) {
  const auto &api = loader_.GetApi();
  VkSurfaceCapabilitiesKHR caps{};
  if (api.get_physical_device_surface_capabilities_khr(
          gpu_, surface_, &caps) != VK_SUCCESS) {
    return false;
  }

  uint32_t format_count = 0;
  api.get_physical_device_surface_formats_khr(gpu_, surface_, &format_count,
                                              nullptr);
  if (format_count == 0) {
    return false;
  }
  std::vector<VkSurfaceFormatKHR> formats(format_count);
  api.get_physical_device_surface_formats_khr(gpu_, surface_, &format_count,
                                              formats.data());
  VkSurfaceFormatKHR chosen = formats[0];
  if (formats.size() == 1 && formats[0].format == VK_FORMAT_UNDEFINED) {
    chosen.format = VK_FORMAT_B8G8R8A8_UNORM;
    chosen.colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  }
  swapchain_format_ = chosen.format;

  uint32_t present_mode_count = 0;
  api.get_physical_device_surface_present_modes_khr(
      gpu_, surface_, &present_mode_count, nullptr);
  VkPresentModeKHR present_mode = VK_PRESENT_MODE_FIFO_KHR;
  if (present_mode_count > 0) {
    std::vector<VkPresentModeKHR> modes(present_mode_count);
    api.get_physical_device_surface_present_modes_khr(
        gpu_, surface_, &present_mode_count, modes.data());
    for (auto mode : modes) {
      if (mode == VK_PRESENT_MODE_FIFO_KHR) {
        present_mode = mode;
        break;
      }
    }
  }

  VkExtent2D extent = caps.currentExtent;
  if (extent.width == UINT32_MAX) {
    extent.width = width > 0 ? static_cast<uint32_t>(width) : caps.minImageExtent.width;
    extent.height = height > 0 ? static_cast<uint32_t>(height) : caps.minImageExtent.height;
    extent.width = std::max(caps.minImageExtent.width,
                            std::min(caps.maxImageExtent.width, extent.width));
    extent.height = std::max(caps.minImageExtent.height,
                             std::min(caps.maxImageExtent.height, extent.height));
  }
  swapchain_extent_ = extent;

  uint32_t image_count = caps.minImageCount + 1;
  if (caps.maxImageCount > 0 && image_count > caps.maxImageCount) {
    image_count = caps.maxImageCount;
  }

  VkSwapchainCreateInfoKHR info{};
  info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  info.surface = surface_;
  info.minImageCount = image_count;
  info.imageFormat = chosen.format;
  info.imageColorSpace = chosen.colorSpace;
  info.imageExtent = extent;
  info.imageArrayLayers = 1;
  info.imageUsage =
      VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  swapchain_usage_ = info.imageUsage;
  uint32_t indices[] = {queue_family_index_, present_queue_family_index_};
  if (queue_family_index_ != present_queue_family_index_) {
    info.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
    info.queueFamilyIndexCount = 2;
    info.pQueueFamilyIndices = indices;
  } else {
    info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  }
  info.preTransform = caps.currentTransform;
  info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  info.presentMode = present_mode;
  info.clipped = VK_TRUE;
  info.oldSwapchain = swapchain_;

  VkSwapchainKHR new_swapchain = VK_NULL_HANDLE;
  if (api.create_swapchain_khr(device_, &info, nullptr, &new_swapchain) !=
      VK_SUCCESS) {
    return false;
  }

  if (swapchain_ != VK_NULL_HANDLE) {
    api.destroy_swapchain_khr(device_, swapchain_, nullptr);
  }
  swapchain_ = new_swapchain;

  uint32_t swapchain_image_count = 0;
  api.get_swapchain_images_khr(device_, swapchain_, &swapchain_image_count,
                               nullptr);
  swapchain_images_.resize(swapchain_image_count);
  api.get_swapchain_images_khr(device_, swapchain_, &swapchain_image_count,
                               swapchain_images_.data());
  swapchain_out_of_date_ = false;

  LOGF(LOG_INFO,
               "Vulkan swapchain created: %{public}ux%{public}u images=%{public}u",
               extent.width, extent.height, swapchain_image_count);
  return true;
}

void VulkanContext::DestroySwapchain() {
  const auto &api = loader_.GetApi();
  if (device_ && swapchain_ != VK_NULL_HANDLE && api.destroy_swapchain_khr) {
    api.destroy_swapchain_khr(device_, swapchain_, nullptr);
  }
  swapchain_ = VK_NULL_HANDLE;
  swapchain_images_.clear();
  swapchain_usage_ = 0;
  swapchain_out_of_date_ = false;
}

} // namespace libretro
