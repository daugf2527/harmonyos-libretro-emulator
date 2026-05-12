#ifndef PLATFORM_GRAPHICS_VULKAN_PRESENTER_H
#define PLATFORM_GRAPHICS_VULKAN_PRESENTER_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

#include "core/libretro/libretro_vulkan.h"
#include "vulkan_loader.h"

namespace libretro {

class VulkanContext;

class VulkanPresenter {
public:
  VulkanPresenter();
  ~VulkanPresenter();

  bool Initialize(const VulkanContext &context);
  void Destroy();

  bool IsReady() const { return ready_; }
  const retro_hw_render_interface_vulkan &GetInterface() const {
    return interface_;
  }

  void SetSwapchain(VkSwapchainKHR swapchain);
  void SetSyncIndex(uint32_t index);
  void SetSyncIndexMask(uint32_t mask);
  bool Present();
  void SetContentSize(uint32_t width, uint32_t height);
  void SetSwapchainExtent(VkExtent2D extent);
  void SetSwapchainUsage(VkImageUsageFlags usage);
  bool ShouldRecreateSwapchain() const { return swapchain_out_of_date_; }
  void ClearSwapchainOutOfDate() { swapchain_out_of_date_ = false; }

  struct FrameImageState {
    bool valid = false;
    retro_vulkan_image image{};
    std::vector<VkSemaphore> wait_semaphores;
    uint32_t src_queue_family = VK_QUEUE_FAMILY_IGNORED;
  };

  struct FrameCommandState {
    bool valid = false;
    std::vector<VkCommandBuffer> buffers;
  };

  struct FrameState {
    FrameImageState image;
    FrameCommandState commands;
    VkSemaphore signal_semaphore = VK_NULL_HANDLE;
    VkSemaphore acquire_semaphore = VK_NULL_HANDLE;
    VkSemaphore present_wait_semaphore = VK_NULL_HANDLE;
    VkFence submit_fence = VK_NULL_HANDLE;
    VkCommandBuffer presenter_cmd = VK_NULL_HANDLE;
    uint64_t submit_serial = 0;
    bool core_cmd_submitted = false;
    bool presenter_cmd_submitted = false;
    bool presenter_cmd_ready = false;
  };

  const FrameState *GetFrameState(uint32_t index) const;
  FrameState *GetFrameState(uint32_t index);
  VkSemaphore GetAcquireSemaphore(uint32_t index) const;
  void SwapAcquireSemaphores(uint32_t a, uint32_t b);
  void ClearFrameState(uint32_t index);
  void SetSwapchainImages(const std::vector<VkImage> &images);

private:
  static void SetImageCallback(void *handle,
                               const retro_vulkan_image *image,
                               uint32_t num_semaphores,
                               const VkSemaphore *semaphores,
                               uint32_t src_queue_family);
  static uint32_t GetSyncIndexCallback(void *handle);
  static uint32_t GetSyncIndexMaskCallback(void *handle);
  static void SetCommandBuffersCallback(void *handle,
                                        uint32_t num_cmd,
                                        const VkCommandBuffer *cmd);
  static void WaitSyncIndexCallback(void *handle);
  static void LockQueueCallback(void *handle);
  static void UnlockQueueCallback(void *handle);
  static void SetSignalSemaphoreCallback(void *handle, VkSemaphore semaphore);

  void SetImage(const retro_vulkan_image *image, uint32_t num_semaphores,
                const VkSemaphore *semaphores, uint32_t src_queue_family);
  void SetCommandBuffers(uint32_t num_cmd, const VkCommandBuffer *cmd);
  void WaitSyncIndex();
  void LockQueue();
  void UnlockQueue();
  void SetSignalSemaphore(VkSemaphore semaphore);
  bool SubmitFrame(FrameState &state, uint32_t image_index);
  bool RecordPresenterCommands(FrameState &state, uint32_t image_index,
                               VkImage swapchain_image);

  void EnsureFrameSlots(uint32_t mask);
  FrameState *GetFrameStateLocked(uint32_t index);
  bool CreateCommandPool();
  void DestroyCommandPool();
  bool AllocateFrameResources(FrameState &state);
  void DestroyFrameResources(FrameState &state);

  retro_hw_render_interface_vulkan interface_{};
  std::atomic<uint32_t> sync_index_{0};
  std::atomic<uint32_t> sync_index_mask_{1};
  mutable std::mutex state_mutex_;
  std::mutex queue_mutex_;
  std::vector<FrameState> frames_;
  VulkanApi api_{};
  VkDevice device_ = VK_NULL_HANDLE;
  VkQueue queue_ = VK_NULL_HANDLE;
  VkQueue present_queue_ = VK_NULL_HANDLE;
  uint32_t queue_family_index_ = 0;
  uint32_t present_queue_family_index_ = 0;
  VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
  std::vector<VkImage> swapchain_images_;
  std::vector<VkImageLayout> swapchain_image_layouts_;
  uint32_t content_width_ = 0;
  uint32_t content_height_ = 0;
  VkExtent2D swapchain_extent_{};
  std::atomic<bool> swapchain_out_of_date_{false};
  VkImageUsageFlags swapchain_usage_ = 0;
  size_t submit_fail_count_ = 0;
  size_t present_fail_count_ = 0;
  size_t present_out_of_date_count_ = 0;
  size_t swapchain_usage_fail_count_ = 0;
  size_t blit_copy_fail_count_ = 0;
  size_t record_fail_count_ = 0;
  VkCommandPool command_pool_ = VK_NULL_HANDLE;
  bool ready_ = false;
};

} // namespace libretro

#endif // PLATFORM_GRAPHICS_VULKAN_PRESENTER_H
