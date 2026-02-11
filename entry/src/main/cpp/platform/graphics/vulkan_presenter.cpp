#include "vulkan_presenter.h"
#include "vulkan_context.h"

#include <hilog/log.h>
#include <utility>

#undef LOG_DOMAIN
#define LOG_DOMAIN 0xD003
#undef LOG_TAG
#define LOG_TAG "VulkanPresenter"
#undef LOG_FLOW
#define LOG_FLOW "Video"
#include "common/log_prefix.h"

namespace libretro {

namespace {

uint32_t MaskToCount(uint32_t mask) {
  if (mask == 0) {
    return 1;
  }
  uint32_t count = 0;
  while (mask) {
    ++count;
    mask >>= 1;
  }
  return count;
}

bool ShouldLog(size_t &counter, size_t burst, size_t interval) {
  counter++;
  if (counter <= burst) {
    return true;
  }
  if (interval == 0) {
    return false;
  }
  return (counter % interval) == 0;
}

} // namespace

VulkanPresenter::VulkanPresenter() = default;

VulkanPresenter::~VulkanPresenter() { Destroy(); }

bool VulkanPresenter::Initialize(const VulkanContext &context) {
  if (context.GetDevice() == VK_NULL_HANDLE || !context.GetApi().create_fence) {
    return false;
  }
  api_ = context.GetApi();
  device_ = context.GetDevice();
  queue_ = context.GetQueue();
  queue_family_index_ = context.GetQueueFamilyIndex();
  swapchain_ = context.GetSwapchain();

  if (!CreateCommandPool()) {
    return false;
  }

  interface_ = retro_hw_render_interface_vulkan{};
  interface_.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
  interface_.interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
  interface_.handle = this;
  interface_.instance = context.GetInstance();
  interface_.gpu = context.GetGpu();
  interface_.device = context.GetDevice();
  interface_.get_device_proc_addr = context.GetApi().get_device_proc_addr;
  interface_.get_instance_proc_addr = context.GetApi().get_instance_proc_addr;
  interface_.queue = context.GetQueue();
  interface_.queue_index = context.GetQueueFamilyIndex();
  interface_.set_image = SetImageCallback;
  interface_.get_sync_index = GetSyncIndexCallback;
  interface_.get_sync_index_mask = GetSyncIndexMaskCallback;
  interface_.set_command_buffers = SetCommandBuffersCallback;
  interface_.wait_sync_index = WaitSyncIndexCallback;
  interface_.lock_queue = LockQueueCallback;
  interface_.unlock_queue = UnlockQueueCallback;
  interface_.set_signal_semaphore = SetSignalSemaphoreCallback;

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    frames_.clear();
    EnsureFrameSlots(sync_index_mask_.load());
  }

  ready_ = true;
  LOGF(LOG_INFO, "Vulkan presenter initialized");
  return true;
}

void VulkanPresenter::SetSwapchain(VkSwapchainKHR swapchain) {
  swapchain_ = swapchain;
}

void VulkanPresenter::SetSwapchainImages(const std::vector<VkImage> &images) {
  swapchain_images_ = images;
  swapchain_image_layouts_.assign(images.size(), VK_IMAGE_LAYOUT_UNDEFINED);
  swapchain_out_of_date_ = false;
  std::lock_guard<std::mutex> lock(state_mutex_);
  for (auto &frame : frames_) {
    frame.presenter_cmd_ready = false;
  }
}

void VulkanPresenter::SetSwapchainUsage(VkImageUsageFlags usage) {
  swapchain_usage_ = usage;
}

void VulkanPresenter::SetContentSize(uint32_t width, uint32_t height) {
  content_width_ = width;
  content_height_ = height;
}

void VulkanPresenter::SetSwapchainExtent(VkExtent2D extent) {
  swapchain_extent_ = extent;
}

void VulkanPresenter::Destroy() {
  if (!ready_) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    for (auto &frame : frames_) {
      DestroyFrameResources(frame);
    }
    frames_.clear();
  }
  DestroyCommandPool();
  interface_ = retro_hw_render_interface_vulkan{};
  device_ = VK_NULL_HANDLE;
  queue_ = VK_NULL_HANDLE;
  queue_family_index_ = 0;
  swapchain_ = VK_NULL_HANDLE;
  ready_ = false;
}

bool VulkanPresenter::Present() {
  if (!ready_ || device_ == VK_NULL_HANDLE || !api_.queue_submit ||
      !api_.queue_present_khr || swapchain_ == VK_NULL_HANDLE) {
    return false;
  }
  const uint32_t index = sync_index_.load();
  std::lock_guard<std::mutex> lock(state_mutex_);
  FrameState *state = GetFrameStateLocked(index);
  if (!state) {
    return false;
  }
  if (!state->presenter_cmd_ready) {
    if (index >= swapchain_images_.size()) {
      return false;
    }
    if (!RecordPresenterCommands(*state, index, swapchain_images_[index])) {
      return false;
    }
  }
  if (!SubmitFrame(*state, index)) {
    return false;
  }
  if (swapchain_out_of_date_) {
    return false;
  }
  return true;
}

void VulkanPresenter::SetSyncIndex(uint32_t index) { sync_index_ = index; }

void VulkanPresenter::SetSyncIndexMask(uint32_t mask) {
  sync_index_mask_ = (mask == 0) ? 1 : mask;
  std::lock_guard<std::mutex> lock(state_mutex_);
  EnsureFrameSlots(sync_index_mask_.load());
}

const VulkanPresenter::FrameState *
VulkanPresenter::GetFrameState(uint32_t index) const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (index >= frames_.size()) {
    return nullptr;
  }
  return &frames_[index];
}

VulkanPresenter::FrameState *
VulkanPresenter::GetFrameState(uint32_t index) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (index >= frames_.size()) {
    return nullptr;
  }
  return &frames_[index];
}

VkSemaphore VulkanPresenter::GetAcquireSemaphore(uint32_t index) const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (index >= frames_.size()) {
    return VK_NULL_HANDLE;
  }
  return frames_[index].acquire_semaphore;
}

void VulkanPresenter::SwapAcquireSemaphores(uint32_t a, uint32_t b) {
  if (a == b) {
    return;
  }
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (a >= frames_.size() || b >= frames_.size()) {
    return;
  }
  std::swap(frames_[a].acquire_semaphore, frames_[b].acquire_semaphore);
}

void VulkanPresenter::ClearFrameState(uint32_t index) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  FrameState *state = GetFrameStateLocked(index);
  if (!state) {
    return;
  }
  state->image = FrameImageState{};
  state->commands = FrameCommandState{};
  state->signal_semaphore = VK_NULL_HANDLE;
  state->submit_serial = 0;
  state->core_cmd_submitted = false;
  state->presenter_cmd_submitted = false;
  state->presenter_cmd_ready = false;
}

void VulkanPresenter::SetImageCallback(void *handle,
                                       const retro_vulkan_image *image,
                                       uint32_t num_semaphores,
                                       const VkSemaphore *semaphores,
                                       uint32_t src_queue_family) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->SetImage(image, num_semaphores, semaphores, src_queue_family);
}

uint32_t VulkanPresenter::GetSyncIndexCallback(void *handle) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return 0;
  }
  return self->sync_index_.load();
}

uint32_t VulkanPresenter::GetSyncIndexMaskCallback(void *handle) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return 1;
  }
  return self->sync_index_mask_.load();
}

void VulkanPresenter::SetCommandBuffersCallback(void *handle, uint32_t num_cmd,
                                                const VkCommandBuffer *cmd) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->SetCommandBuffers(num_cmd, cmd);
}

void VulkanPresenter::WaitSyncIndexCallback(void *handle) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->WaitSyncIndex();
}

void VulkanPresenter::LockQueueCallback(void *handle) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->LockQueue();
}

void VulkanPresenter::UnlockQueueCallback(void *handle) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->UnlockQueue();
}

void VulkanPresenter::SetSignalSemaphoreCallback(void *handle,
                                                 VkSemaphore semaphore) {
  auto *self = reinterpret_cast<VulkanPresenter *>(handle);
  if (!self) {
    return;
  }
  self->SetSignalSemaphore(semaphore);
}

void VulkanPresenter::SetImage(const retro_vulkan_image *image,
                               uint32_t num_semaphores,
                               const VkSemaphore *semaphores,
                               uint32_t src_queue_family) {
  const uint32_t index = sync_index_.load();
  std::lock_guard<std::mutex> lock(state_mutex_);
  EnsureFrameSlots(sync_index_mask_.load());
  FrameState *state = GetFrameStateLocked(index);
  if (!state) {
    return;
  }
  state->image = FrameImageState{};
  if (image) {
    state->image.valid = true;
    state->image.image = *image;
    if (num_semaphores > 0 && semaphores) {
      state->image.wait_semaphores.assign(semaphores,
                                          semaphores + num_semaphores);
    }
    state->image.src_queue_family = src_queue_family;
  }
  state->presenter_cmd_ready = false;
}

void VulkanPresenter::SetCommandBuffers(uint32_t num_cmd,
                                        const VkCommandBuffer *cmd) {
  const uint32_t index = sync_index_.load();
  std::lock_guard<std::mutex> lock(state_mutex_);
  EnsureFrameSlots(sync_index_mask_.load());
  FrameState *state = GetFrameStateLocked(index);
  if (!state) {
    return;
  }
  state->commands = FrameCommandState{};
  if (num_cmd > 0 && cmd) {
    state->commands.valid = true;
    state->commands.buffers.assign(cmd, cmd + num_cmd);
  }
  state->presenter_cmd_ready = false;
}

void VulkanPresenter::WaitSyncIndex() {
  const uint32_t index = sync_index_.load();
  std::lock_guard<std::mutex> lock(state_mutex_);
  FrameState *state = GetFrameStateLocked(index);
  if (!state || state->submit_fence == VK_NULL_HANDLE) {
    return;
  }
  
  // Wait for the fence to ensure the GPU has finished with this frame's resources
  // before the core starts reusing them.
  if (api_.wait_for_fences) {
    VkResult res = api_.wait_for_fences(device_, 1, &state->submit_fence, VK_TRUE,
                                        1000000000); // 1s timeout
    if (res == VK_TIMEOUT) {
        LOGF(LOG_ERROR, "WaitSyncIndex: vkWaitForFences timed out (1s) - GPU hang?");
    } else if (res != VK_SUCCESS) {
        LOGF(LOG_WARN, "WaitSyncIndex: vkWaitForFences failed: %d", res);
    }
  }
}

void VulkanPresenter::LockQueue() { queue_mutex_.lock(); }

void VulkanPresenter::UnlockQueue() { queue_mutex_.unlock(); }

void VulkanPresenter::SetSignalSemaphore(VkSemaphore semaphore) {
  const uint32_t index = sync_index_.load();
  std::lock_guard<std::mutex> lock(state_mutex_);
  EnsureFrameSlots(sync_index_mask_.load());
  FrameState *state = GetFrameStateLocked(index);
  if (!state) {
    return;
  }
  state->signal_semaphore = semaphore;
}

void VulkanPresenter::EnsureFrameSlots(uint32_t mask) {
  const uint32_t count = MaskToCount(mask);
  if (frames_.size() == count) {
    return;
  }
  if (count < frames_.size()) {
    for (size_t i = count; i < frames_.size(); ++i) {
      DestroyFrameResources(frames_[i]);
    }
    frames_.resize(count);
    return;
  }

  const size_t old_count = frames_.size();
  frames_.resize(count);
  for (size_t i = old_count; i < frames_.size(); ++i) {
    if (!AllocateFrameResources(frames_[i])) {
      LOGF(LOG_WARN, "Vulkan frame resource allocate failed");
      break;
    }
  }
}

VulkanPresenter::FrameState *
VulkanPresenter::GetFrameStateLocked(uint32_t index) {
  if (index >= frames_.size()) {
    return nullptr;
  }
  return &frames_[index];
}

bool VulkanPresenter::SubmitFrame(FrameState &state, uint32_t image_index) {
  if (state.submit_fence == VK_NULL_HANDLE ||
      state.acquire_semaphore == VK_NULL_HANDLE) {
    return false;
  }

  if (api_.wait_for_fences &&
      api_.wait_for_fences(device_, 1, &state.submit_fence, VK_TRUE,
                           UINT64_MAX) != VK_SUCCESS) {
    return false;
  }
  if (api_.reset_fences) {
    api_.reset_fences(device_, 1, &state.submit_fence);
  }

  if (!state.presenter_cmd_ready) {
    return false;
  }

  std::vector<VkCommandBuffer> to_submit;
  if (state.commands.valid && !state.commands.buffers.empty()) {
    to_submit.insert(to_submit.end(), state.commands.buffers.begin(),
                     state.commands.buffers.end());
    state.core_cmd_submitted = true;
  }
  if (state.presenter_cmd != VK_NULL_HANDLE) {
    to_submit.push_back(state.presenter_cmd);
    state.presenter_cmd_submitted = true;
  }
  if (to_submit.empty()) {
    return false;
  }

  std::vector<VkSemaphore> wait_semaphores;
  std::vector<VkPipelineStageFlags> wait_stages;
  wait_semaphores.push_back(state.acquire_semaphore);
  wait_stages.push_back(VK_PIPELINE_STAGE_TRANSFER_BIT);
  if (!state.commands.valid) {
    for (auto sem : state.image.wait_semaphores) {
      wait_semaphores.push_back(sem);
      wait_stages.push_back(VK_PIPELINE_STAGE_TRANSFER_BIT);
    }
  }

  std::vector<VkSemaphore> signal_semaphores;
  signal_semaphores.push_back(state.present_wait_semaphore);
  if (state.signal_semaphore != VK_NULL_HANDLE) {
    signal_semaphores.push_back(state.signal_semaphore);
  }

  VkSubmitInfo submit{};
  submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submit.waitSemaphoreCount =
      static_cast<uint32_t>(wait_semaphores.size());
  submit.pWaitSemaphores = wait_semaphores.data();
  submit.pWaitDstStageMask = wait_stages.data();
  submit.commandBufferCount = static_cast<uint32_t>(to_submit.size());
  submit.pCommandBuffers = to_submit.data();
  submit.signalSemaphoreCount =
      static_cast<uint32_t>(signal_semaphores.size());
  submit.pSignalSemaphores = signal_semaphores.data();

  LockQueue();
  const VkResult submit_res =
      api_.queue_submit(queue_, 1, &submit, state.submit_fence);
  UnlockQueue();
  if (submit_res != VK_SUCCESS) {
    if (ShouldLog(submit_fail_count_, 3, 60)) {
      LOGF(LOG_ERROR, "vkQueueSubmit failed: %{public}d", submit_res);
    }
    return false;
  }

  VkPresentInfoKHR present{};
  present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  present.waitSemaphoreCount = 1;
  present.pWaitSemaphores = &state.present_wait_semaphore;
  present.swapchainCount = 1;
  present.pSwapchains = &swapchain_;
  present.pImageIndices = &image_index;

  const VkResult present_res = api_.queue_present_khr(queue_, &present);
  if (present_res == VK_ERROR_OUT_OF_DATE_KHR ||
      present_res == VK_SUBOPTIMAL_KHR) {
    if (ShouldLog(present_out_of_date_count_, 3, 60)) {
      LOGF(LOG_WARN, "vkQueuePresentKHR out of date: %{public}d",
           present_res);
    }
    swapchain_out_of_date_ = true;
    return false;
  }
  if (present_res != VK_SUCCESS) {
    if (ShouldLog(present_fail_count_, 3, 60)) {
      LOGF(LOG_ERROR, "vkQueuePresentKHR failed: %{public}d", present_res);
    }
    return false;
  }

  state.submit_serial++;
  return true;
}

bool VulkanPresenter::RecordPresenterCommands(FrameState &state,
                                              uint32_t image_index,
                                              VkImage swapchain_image) {
  if (!api_.reset_command_buffer || !api_.begin_command_buffer ||
      !api_.end_command_buffer || !api_.cmd_pipeline_barrier) {
    if (ShouldLog(record_fail_count_, 1, 60)) {
      LOGF(LOG_ERROR, "Vulkan command buffer functions missing");
    }
    return false;
  }
  if (!state.image.valid || state.presenter_cmd == VK_NULL_HANDLE ||
      swapchain_image == VK_NULL_HANDLE ||
      state.image.image.create_info.image == VK_NULL_HANDLE) {
    return false;
  }
  if ((swapchain_usage_ & VK_IMAGE_USAGE_TRANSFER_DST_BIT) == 0) {
    if (ShouldLog(swapchain_usage_fail_count_, 3, 60)) {
      LOGF(LOG_ERROR, "Swapchain image missing TRANSFER_DST usage");
    }
    return false;
  }

  if (api_.reset_command_buffer(state.presenter_cmd, 0) != VK_SUCCESS) {
    return false;
  }

  VkCommandBufferBeginInfo begin{};
  begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  if (api_.begin_command_buffer(state.presenter_cmd, &begin) != VK_SUCCESS) {
    return false;
  }

  if (image_index >= swapchain_image_layouts_.size()) {
    return false;
  }

  const VkImageLayout core_old_layout = state.image.image.image_layout;
  const VkImageLayout core_transfer_layout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
  const VkImageLayout swapchain_old_layout = swapchain_image_layouts_[image_index];
  const VkImageLayout swapchain_transfer_layout =
      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;

  VkImageMemoryBarrier pre_barriers[2]{};

  pre_barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  pre_barriers[0].srcAccessMask =
      (core_old_layout == VK_IMAGE_LAYOUT_GENERAL) ? 0
                                                   : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  pre_barriers[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  pre_barriers[0].oldLayout = core_old_layout;
  pre_barriers[0].newLayout = core_transfer_layout;
  uint32_t src_family = state.image.src_queue_family;
  uint32_t dst_family = queue_family_index_;
  if (src_family == VK_QUEUE_FAMILY_IGNORED || src_family == dst_family) {
    src_family = VK_QUEUE_FAMILY_IGNORED;
    dst_family = VK_QUEUE_FAMILY_IGNORED;
  }
  pre_barriers[0].srcQueueFamilyIndex = src_family;
  pre_barriers[0].dstQueueFamilyIndex = dst_family;
  pre_barriers[0].image = state.image.image.create_info.image;
  pre_barriers[0].subresourceRange = state.image.image.create_info.subresourceRange;

  pre_barriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  pre_barriers[1].srcAccessMask = 0;
  pre_barriers[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  pre_barriers[1].oldLayout = swapchain_old_layout;
  pre_barriers[1].newLayout = swapchain_transfer_layout;
  pre_barriers[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  pre_barriers[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  pre_barriers[1].image = swapchain_image;
  pre_barriers[1].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  pre_barriers[1].subresourceRange.baseMipLevel = 0;
  pre_barriers[1].subresourceRange.levelCount = 1;
  pre_barriers[1].subresourceRange.baseArrayLayer = 0;
  pre_barriers[1].subresourceRange.layerCount = 1;

  api_.cmd_pipeline_barrier(
      state.presenter_cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2,
      pre_barriers);

  const uint32_t src_w =
      content_width_ > 0
          ? content_width_
          : (swapchain_extent_.width > 0 ? swapchain_extent_.width : 1);
  const uint32_t src_h =
      content_height_ > 0
          ? content_height_
          : (swapchain_extent_.height > 0 ? swapchain_extent_.height : 1);
  const uint32_t dst_w =
      swapchain_extent_.width > 0 ? swapchain_extent_.width : src_w;
  const uint32_t dst_h =
      swapchain_extent_.height > 0 ? swapchain_extent_.height : src_h;
  const uint32_t copy_w = (src_w < dst_w) ? src_w : dst_w;
  const uint32_t copy_h = (src_h < dst_h) ? src_h : dst_h;

  VkImageBlit blit{};
  blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  blit.srcSubresource.mipLevel = 0;
  blit.srcSubresource.baseArrayLayer = 0;
  blit.srcSubresource.layerCount = 1;
  blit.dstSubresource = blit.srcSubresource;
  blit.srcOffsets[0] = {0, 0, 0};
  blit.srcOffsets[1] = {static_cast<int32_t>(src_w),
                        static_cast<int32_t>(src_h), 1};
  blit.dstOffsets[0] = {0, 0, 0};
  blit.dstOffsets[1] = {static_cast<int32_t>(dst_w),
                        static_cast<int32_t>(dst_h), 1};

  const bool use_copy = (src_w == dst_w && src_h == dst_h) ||
                        !api_.cmd_blit_image;
  if (!use_copy && api_.cmd_blit_image) {
    api_.cmd_blit_image(state.presenter_cmd, state.image.image.create_info.image,
                        core_transfer_layout, swapchain_image,
                        swapchain_transfer_layout, 1, &blit,
                        VK_FILTER_NEAREST);
  } else if (api_.cmd_copy_image) {
    VkImageCopy copy{};
    copy.srcSubresource = blit.srcSubresource;
    copy.dstSubresource = blit.dstSubresource;
    copy.srcOffset = {0, 0, 0};
    copy.dstOffset = {0, 0, 0};
    copy.extent = {copy_w > 0 ? copy_w : 1, copy_h > 0 ? copy_h : 1, 1};
    api_.cmd_copy_image(state.presenter_cmd,
                        state.image.image.create_info.image,
                        core_transfer_layout, swapchain_image,
                        swapchain_transfer_layout, 1, &copy);
  } else {
    if (ShouldLog(blit_copy_fail_count_, 3, 60)) {
      LOGF(LOG_ERROR, "No blit/copy command available");
    }
    return false;
  }

  VkImageMemoryBarrier post_barriers[2]{};
  post_barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  post_barriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  post_barriers[0].dstAccessMask =
      (core_old_layout == VK_IMAGE_LAYOUT_GENERAL) ? 0
                                                   : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  post_barriers[0].oldLayout = core_transfer_layout;
  post_barriers[0].newLayout = core_old_layout;
  post_barriers[0].srcQueueFamilyIndex = dst_family;
  post_barriers[0].dstQueueFamilyIndex = src_family;
  post_barriers[0].image = state.image.image.create_info.image;
  post_barriers[0].subresourceRange =
      state.image.image.create_info.subresourceRange;

  post_barriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  post_barriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  post_barriers[1].dstAccessMask = 0;
  post_barriers[1].oldLayout = swapchain_transfer_layout;
  post_barriers[1].newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
  post_barriers[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  post_barriers[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  post_barriers[1].image = swapchain_image;
  post_barriers[1].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  post_barriers[1].subresourceRange.baseMipLevel = 0;
  post_barriers[1].subresourceRange.levelCount = 1;
  post_barriers[1].subresourceRange.baseArrayLayer = 0;
  post_barriers[1].subresourceRange.layerCount = 1;

  api_.cmd_pipeline_barrier(
      state.presenter_cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 2,
      post_barriers);

  swapchain_image_layouts_[image_index] = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

  if (api_.end_command_buffer(state.presenter_cmd) != VK_SUCCESS) {
    return false;
  }
  state.presenter_cmd_ready = true;
  return true;
}

bool VulkanPresenter::CreateCommandPool() {
  if (command_pool_ != VK_NULL_HANDLE) {
    return true;
  }
  if (!api_.create_command_pool) {
    return false;
  }
  VkCommandPoolCreateInfo info{};
  info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  info.queueFamilyIndex = queue_family_index_;
  info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  if (api_.create_command_pool(device_, &info, nullptr, &command_pool_) !=
      VK_SUCCESS) {
    command_pool_ = VK_NULL_HANDLE;
    return false;
  }
  return true;
}

void VulkanPresenter::DestroyCommandPool() {
  if (command_pool_ != VK_NULL_HANDLE && api_.destroy_command_pool) {
    api_.destroy_command_pool(device_, command_pool_, nullptr);
  }
  command_pool_ = VK_NULL_HANDLE;
}

bool VulkanPresenter::AllocateFrameResources(FrameState &state) {
  if (!device_ || command_pool_ == VK_NULL_HANDLE) {
    return false;
  }
  if (!api_.create_semaphore || !api_.create_fence ||
      !api_.allocate_command_buffers) {
    return false;
  }

  VkSemaphoreCreateInfo sem_info{};
  sem_info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  if (api_.create_semaphore(device_, &sem_info, nullptr,
                            &state.acquire_semaphore) != VK_SUCCESS) {
    return false;
  }
  if (api_.create_semaphore(device_, &sem_info, nullptr,
                            &state.present_wait_semaphore) != VK_SUCCESS) {
    DestroyFrameResources(state);
    return false;
  }

  VkFenceCreateInfo fence_info{};
  fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  fence_info.flags = VK_FENCE_CREATE_SIGNALED_BIT;
  if (api_.create_fence(device_, &fence_info, nullptr, &state.submit_fence) !=
      VK_SUCCESS) {
    DestroyFrameResources(state);
    return false;
  }

  VkCommandBufferAllocateInfo alloc{};
  alloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  alloc.commandPool = command_pool_;
  alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  alloc.commandBufferCount = 1;
  if (api_.allocate_command_buffers(device_, &alloc,
                                    &state.presenter_cmd) != VK_SUCCESS) {
    DestroyFrameResources(state);
    return false;
  }

  state.submit_serial = 0;
  state.core_cmd_submitted = false;
  state.presenter_cmd_submitted = false;
  state.presenter_cmd_ready = false;
  return true;
}

void VulkanPresenter::DestroyFrameResources(FrameState &state) {
  if (state.presenter_cmd != VK_NULL_HANDLE && api_.free_command_buffers &&
      command_pool_ != VK_NULL_HANDLE) {
    api_.free_command_buffers(device_, command_pool_, 1, &state.presenter_cmd);
  }
  state.presenter_cmd = VK_NULL_HANDLE;

  if (state.acquire_semaphore != VK_NULL_HANDLE && api_.destroy_semaphore) {
    api_.destroy_semaphore(device_, state.acquire_semaphore, nullptr);
  }
  state.acquire_semaphore = VK_NULL_HANDLE;

  if (state.present_wait_semaphore != VK_NULL_HANDLE && api_.destroy_semaphore) {
    api_.destroy_semaphore(device_, state.present_wait_semaphore, nullptr);
  }
  state.present_wait_semaphore = VK_NULL_HANDLE;

  if (state.submit_fence != VK_NULL_HANDLE && api_.destroy_fence) {
    api_.destroy_fence(device_, state.submit_fence, nullptr);
  }
  state.submit_fence = VK_NULL_HANDLE;

  state.signal_semaphore = VK_NULL_HANDLE;
  state.image = FrameImageState{};
  state.commands = FrameCommandState{};
  state.submit_serial = 0;
  state.core_cmd_submitted = false;
  state.presenter_cmd_submitted = false;
  state.presenter_cmd_ready = false;
}

} // namespace libretro
