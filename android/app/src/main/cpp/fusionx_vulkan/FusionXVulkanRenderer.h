#pragma once

#include <jni.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <cstdint>
#include <string>
#include <vector>

class FusionXVulkanRenderer {
public:
    FusionXVulkanRenderer();
    ~FusionXVulkanRenderer();

    bool AttachSurface(JNIEnv* env, jobject surface, uint32_t width, uint32_t height);
    void DetachSurface();
    bool RenderClear(float red, float green, float blue, float alpha);

    const std::string& last_error() const { return last_error_; }

private:
    bool EnsureLoader();
    bool EnsureInstance();
    bool EnsureSurface(ANativeWindow* window);
    bool EnsureDevice();
    bool CreateSwapchain(uint32_t width, uint32_t height);
    void DestroySwapchain();
    void DestroyDeviceObjects();
    void DestroyInstanceObjects();
    bool PickPhysicalDevice();
    bool LoadInstanceFunctions();
    bool LoadDeviceFunctions();
    bool CreateRenderPass();
    bool CreateFramebuffers();
    bool CreateCommandPoolAndBuffers();
    bool CreateSyncObjects();
    bool RecordCommandBuffer(uint32_t image_index, const VkClearValue& clear_value);
    bool RecreateSwapchain(uint32_t width, uint32_t height);
    void SetError(const std::string& message);
    std::string VkResultToString(VkResult result) const;

    void* loader_handle_ = nullptr;
    std::string last_error_;

    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr_ = nullptr;
    PFN_vkEnumerateInstanceVersion vkEnumerateInstanceVersion_ = nullptr;
    PFN_vkEnumerateInstanceExtensionProperties vkEnumerateInstanceExtensionProperties_ = nullptr;
    PFN_vkCreateInstance vkCreateInstance_ = nullptr;

    PFN_vkDestroyInstance vkDestroyInstance_ = nullptr;
    PFN_vkCreateAndroidSurfaceKHR vkCreateAndroidSurfaceKHR_ = nullptr;
    PFN_vkDestroySurfaceKHR vkDestroySurfaceKHR_ = nullptr;
    PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices_ = nullptr;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties vkGetPhysicalDeviceQueueFamilyProperties_ = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR vkGetPhysicalDeviceSurfaceSupportKHR_ = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR vkGetPhysicalDeviceSurfaceCapabilitiesKHR_ = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR vkGetPhysicalDeviceSurfaceFormatsKHR_ = nullptr;
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR vkGetPhysicalDeviceSurfacePresentModesKHR_ = nullptr;
    PFN_vkCreateDevice vkCreateDevice_ = nullptr;
    PFN_vkGetDeviceProcAddr vkGetDeviceProcAddr_ = nullptr;

    PFN_vkDestroyDevice vkDestroyDevice_ = nullptr;
    PFN_vkGetDeviceQueue vkGetDeviceQueue_ = nullptr;
    PFN_vkCreateSwapchainKHR vkCreateSwapchainKHR_ = nullptr;
    PFN_vkDestroySwapchainKHR vkDestroySwapchainKHR_ = nullptr;
    PFN_vkGetSwapchainImagesKHR vkGetSwapchainImagesKHR_ = nullptr;
    PFN_vkCreateImageView vkCreateImageView_ = nullptr;
    PFN_vkDestroyImageView vkDestroyImageView_ = nullptr;
    PFN_vkCreateRenderPass vkCreateRenderPass_ = nullptr;
    PFN_vkDestroyRenderPass vkDestroyRenderPass_ = nullptr;
    PFN_vkCreateFramebuffer vkCreateFramebuffer_ = nullptr;
    PFN_vkDestroyFramebuffer vkDestroyFramebuffer_ = nullptr;
    PFN_vkCreateCommandPool vkCreateCommandPool_ = nullptr;
    PFN_vkDestroyCommandPool vkDestroyCommandPool_ = nullptr;
    PFN_vkAllocateCommandBuffers vkAllocateCommandBuffers_ = nullptr;
    PFN_vkFreeCommandBuffers vkFreeCommandBuffers_ = nullptr;
    PFN_vkBeginCommandBuffer vkBeginCommandBuffer_ = nullptr;
    PFN_vkEndCommandBuffer vkEndCommandBuffer_ = nullptr;
    PFN_vkResetCommandBuffer vkResetCommandBuffer_ = nullptr;
    PFN_vkQueueSubmit vkQueueSubmit_ = nullptr;
    PFN_vkQueuePresentKHR vkQueuePresentKHR_ = nullptr;
    PFN_vkDeviceWaitIdle vkDeviceWaitIdle_ = nullptr;
    PFN_vkAcquireNextImageKHR vkAcquireNextImageKHR_ = nullptr;
    PFN_vkCreateSemaphore vkCreateSemaphore_ = nullptr;
    PFN_vkDestroySemaphore vkDestroySemaphore_ = nullptr;
    PFN_vkCreateFence vkCreateFence_ = nullptr;
    PFN_vkDestroyFence vkDestroyFence_ = nullptr;
    PFN_vkWaitForFences vkWaitForFences_ = nullptr;
    PFN_vkResetFences vkResetFences_ = nullptr;
    PFN_vkCmdBeginRenderPass vkCmdBeginRenderPass_ = nullptr;
    PFN_vkCmdEndRenderPass vkCmdEndRenderPass_ = nullptr;

    ANativeWindow* native_window_ = nullptr;
    VkInstance instance_ = VK_NULL_HANDLE;
    VkSurfaceKHR surface_ = VK_NULL_HANDLE;
    VkPhysicalDevice physical_device_ = VK_NULL_HANDLE;
    VkDevice device_ = VK_NULL_HANDLE;
    VkQueue graphics_queue_ = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkRenderPass render_pass_ = VK_NULL_HANDLE;
    VkCommandPool command_pool_ = VK_NULL_HANDLE;
    VkSemaphore image_available_semaphore_ = VK_NULL_HANDLE;
    VkSemaphore render_finished_semaphore_ = VK_NULL_HANDLE;
    VkFence render_fence_ = VK_NULL_HANDLE;

    uint32_t graphics_queue_family_index_ = 0;
    VkFormat swapchain_image_format_ = VK_FORMAT_UNDEFINED;
    VkExtent2D swapchain_extent_{};
    std::vector<VkImage> swapchain_images_;
    std::vector<VkImageView> swapchain_image_views_;
    std::vector<VkFramebuffer> framebuffers_;
    std::vector<VkCommandBuffer> command_buffers_;
};
