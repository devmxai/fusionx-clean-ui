#include "FusionXVulkanRenderer.h"

#include <dlfcn.h>

#include <algorithm>
#include <limits>
#include <sstream>
#include <vector>

namespace {

constexpr const char* kVulkanLoaderName = "libvulkan.so";

#ifndef VK_KHR_ANDROID_SURFACE_EXTENSION_NAME
#define VK_KHR_ANDROID_SURFACE_EXTENSION_NAME "VK_KHR_android_surface"
#endif

template <typename T>
T LoadGlobalSymbol(void* loader_handle, const char* name) {
    return reinterpret_cast<T>(dlsym(loader_handle, name));
}

template <typename T>
T LoadInstanceSymbol(PFN_vkGetInstanceProcAddr get_proc, VkInstance instance, const char* name) {
    return reinterpret_cast<T>(get_proc(instance, name));
}

template <typename T>
T LoadDeviceSymbol(PFN_vkGetDeviceProcAddr get_proc, VkDevice device, const char* name) {
    return reinterpret_cast<T>(get_proc(device, name));
}

}  // namespace

FusionXVulkanRenderer::FusionXVulkanRenderer() = default;

FusionXVulkanRenderer::~FusionXVulkanRenderer() {
    DetachSurface();
    DestroyDeviceObjects();
    DestroyInstanceObjects();
    if (loader_handle_ != nullptr) {
        dlclose(loader_handle_);
        loader_handle_ = nullptr;
    }
}

bool FusionXVulkanRenderer::AttachSurface(JNIEnv* env, jobject surface, uint32_t width, uint32_t height) {
    if (env == nullptr || surface == nullptr) {
        SetError("Surface attachment requires a valid JNI environment and Surface.");
        return false;
    }

    ANativeWindow* next_window = ANativeWindow_fromSurface(env, surface);
    if (next_window == nullptr) {
        SetError("Unable to create ANativeWindow from Surface.");
        return false;
    }

    if (!EnsureLoader() || !EnsureInstance()) {
        ANativeWindow_release(next_window);
        return false;
    }

    if (device_ != VK_NULL_HANDLE) {
        vkDeviceWaitIdle_(device_);
    }

    DetachSurface();
    native_window_ = next_window;

    if (!EnsureSurface(native_window_)) {
        DetachSurface();
        return false;
    }

    if (!EnsureDevice()) {
        DetachSurface();
        return false;
    }

    if (!CreateSwapchain(width, height)) {
        DetachSurface();
        return false;
    }

    return true;
}

void FusionXVulkanRenderer::DetachSurface() {
    if (device_ != VK_NULL_HANDLE && vkDeviceWaitIdle_ != nullptr) {
        vkDeviceWaitIdle_(device_);
    }

    DestroySwapchain();

    if (surface_ != VK_NULL_HANDLE && vkDestroySurfaceKHR_ != nullptr && instance_ != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR_(instance_, surface_, nullptr);
        surface_ = VK_NULL_HANDLE;
    }

    if (native_window_ != nullptr) {
        ANativeWindow_release(native_window_);
        native_window_ = nullptr;
    }
}

bool FusionXVulkanRenderer::RenderClear(float red, float green, float blue, float alpha) {
    if (device_ == VK_NULL_HANDLE || swapchain_ == VK_NULL_HANDLE || command_buffers_.empty()) {
        SetError("RenderClear called before Vulkan surface initialization.");
        return false;
    }

    const VkClearValue clear_value = {
        .color = {{red, green, blue, alpha}},
    };

    VkResult wait_result = vkWaitForFences_(device_, 1, &render_fence_, VK_TRUE, UINT64_MAX);
    if (wait_result != VK_SUCCESS) {
        SetError("vkWaitForFences failed: " + VkResultToString(wait_result));
        return false;
    }

    vkResetFences_(device_, 1, &render_fence_);

    uint32_t image_index = 0;
    VkResult acquire_result = vkAcquireNextImageKHR_(
        device_,
        swapchain_,
        UINT64_MAX,
        image_available_semaphore_,
        VK_NULL_HANDLE,
        &image_index);

    if (acquire_result == VK_ERROR_OUT_OF_DATE_KHR || acquire_result == VK_SUBOPTIMAL_KHR) {
        const uint32_t width = static_cast<uint32_t>(std::max(ANativeWindow_getWidth(native_window_), 1));
        const uint32_t height = static_cast<uint32_t>(std::max(ANativeWindow_getHeight(native_window_), 1));
        if (!RecreateSwapchain(width, height)) {
            return false;
        }
        acquire_result = vkAcquireNextImageKHR_(
            device_,
            swapchain_,
            UINT64_MAX,
            image_available_semaphore_,
            VK_NULL_HANDLE,
            &image_index);
    }

    if (acquire_result != VK_SUCCESS) {
        SetError("vkAcquireNextImageKHR failed: " + VkResultToString(acquire_result));
        return false;
    }

    if (!RecordCommandBuffer(image_index, clear_value)) {
        return false;
    }

    const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit_info{};
    submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = &image_available_semaphore_;
    submit_info.pWaitDstStageMask = &wait_stage;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command_buffers_[image_index];
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = &render_finished_semaphore_;

    VkResult submit_result = vkQueueSubmit_(graphics_queue_, 1, &submit_info, render_fence_);
    if (submit_result != VK_SUCCESS) {
        SetError("vkQueueSubmit failed: " + VkResultToString(submit_result));
        return false;
    }

    VkPresentInfoKHR present_info{};
    present_info.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = &render_finished_semaphore_;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &swapchain_;
    present_info.pImageIndices = &image_index;

    const VkResult present_result = vkQueuePresentKHR_(graphics_queue_, &present_info);
    if (present_result == VK_ERROR_OUT_OF_DATE_KHR || present_result == VK_SUBOPTIMAL_KHR) {
        const uint32_t width = static_cast<uint32_t>(std::max(ANativeWindow_getWidth(native_window_), 1));
        const uint32_t height = static_cast<uint32_t>(std::max(ANativeWindow_getHeight(native_window_), 1));
        return RecreateSwapchain(width, height);
    }

    if (present_result != VK_SUCCESS) {
        SetError("vkQueuePresentKHR failed: " + VkResultToString(present_result));
        return false;
    }

    return true;
}

bool FusionXVulkanRenderer::EnsureLoader() {
    if (loader_handle_ != nullptr && vkGetInstanceProcAddr_ != nullptr) {
        return true;
    }

    loader_handle_ = dlopen(kVulkanLoaderName, RTLD_NOW | RTLD_LOCAL);
    if (loader_handle_ == nullptr) {
        SetError("Unable to load libvulkan.so.");
        return false;
    }

    vkGetInstanceProcAddr_ =
        LoadGlobalSymbol<PFN_vkGetInstanceProcAddr>(loader_handle_, "vkGetInstanceProcAddr");
    if (vkGetInstanceProcAddr_ == nullptr) {
        SetError("vkGetInstanceProcAddr unavailable.");
        return false;
    }

    vkEnumerateInstanceVersion_ = LoadInstanceSymbol<PFN_vkEnumerateInstanceVersion>(
        vkGetInstanceProcAddr_, VK_NULL_HANDLE, "vkEnumerateInstanceVersion");
    vkEnumerateInstanceExtensionProperties_ =
        LoadInstanceSymbol<PFN_vkEnumerateInstanceExtensionProperties>(
            vkGetInstanceProcAddr_, VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    vkCreateInstance_ =
        LoadInstanceSymbol<PFN_vkCreateInstance>(vkGetInstanceProcAddr_, VK_NULL_HANDLE, "vkCreateInstance");

    if (vkEnumerateInstanceExtensionProperties_ == nullptr || vkCreateInstance_ == nullptr) {
        SetError("Required Vulkan global functions are unavailable.");
        return false;
    }

    return true;
}

bool FusionXVulkanRenderer::EnsureInstance() {
    if (instance_ != VK_NULL_HANDLE) {
        return true;
    }

    uint32_t api_version = VK_API_VERSION_1_0;
    if (vkEnumerateInstanceVersion_ != nullptr) {
        vkEnumerateInstanceVersion_(&api_version);
    }

    const char* required_extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
    };

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "FusionX";
    app_info.applicationVersion = VK_MAKE_VERSION(0, 2, 0);
    app_info.pEngineName = "FusionX Vulkan Preview";
    app_info.engineVersion = VK_MAKE_VERSION(0, 2, 0);
    app_info.apiVersion = api_version;

    VkInstanceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = 2;
    create_info.ppEnabledExtensionNames = required_extensions;

    const VkResult result = vkCreateInstance_(&create_info, nullptr, &instance_);
    if (result != VK_SUCCESS) {
        instance_ = VK_NULL_HANDLE;
        SetError("vkCreateInstance failed: " + VkResultToString(result));
        return false;
    }

    return LoadInstanceFunctions();
}

bool FusionXVulkanRenderer::EnsureSurface(ANativeWindow* window) {
    if (instance_ == VK_NULL_HANDLE || window == nullptr) {
        SetError("Cannot create Vulkan surface without instance and window.");
        return false;
    }

    VkAndroidSurfaceCreateInfoKHR create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR;
    create_info.window = window;

    const VkResult result = vkCreateAndroidSurfaceKHR_(instance_, &create_info, nullptr, &surface_);
    if (result != VK_SUCCESS) {
        surface_ = VK_NULL_HANDLE;
        SetError("vkCreateAndroidSurfaceKHR failed: " + VkResultToString(result));
        return false;
    }
    return true;
}

bool FusionXVulkanRenderer::EnsureDevice() {
    if (device_ != VK_NULL_HANDLE) {
        return true;
    }

    if (!PickPhysicalDevice()) {
        return false;
    }

    const float queue_priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{};
    queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueFamilyIndex = graphics_queue_family_index_;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &queue_priority;

    const char* required_extensions[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

    VkDeviceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    create_info.queueCreateInfoCount = 1;
    create_info.pQueueCreateInfos = &queue_info;
    create_info.enabledExtensionCount = 1;
    create_info.ppEnabledExtensionNames = required_extensions;

    const VkResult result = vkCreateDevice_(physical_device_, &create_info, nullptr, &device_);
    if (result != VK_SUCCESS) {
        device_ = VK_NULL_HANDLE;
        SetError("vkCreateDevice failed: " + VkResultToString(result));
        return false;
    }

    if (!LoadDeviceFunctions()) {
        return false;
    }

    vkGetDeviceQueue_(device_, graphics_queue_family_index_, 0, &graphics_queue_);
    return graphics_queue_ != VK_NULL_HANDLE;
}

bool FusionXVulkanRenderer::CreateSwapchain(uint32_t width, uint32_t height) {
    if (device_ == VK_NULL_HANDLE || surface_ == VK_NULL_HANDLE) {
        SetError("Cannot create swapchain before device and surface.");
        return false;
    }

    VkSurfaceCapabilitiesKHR surface_capabilities{};
    const VkResult caps_result =
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR_(physical_device_, surface_, &surface_capabilities);
    if (caps_result != VK_SUCCESS) {
        SetError("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: " + VkResultToString(caps_result));
        return false;
    }

    uint32_t format_count = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR_(physical_device_, surface_, &format_count, nullptr);
    if (format_count == 0) {
        SetError("No Vulkan surface formats available.");
        return false;
    }
    std::vector<VkSurfaceFormatKHR> surface_formats(format_count);
    vkGetPhysicalDeviceSurfaceFormatsKHR_(
        physical_device_, surface_, &format_count, surface_formats.data());

    VkSurfaceFormatKHR chosen_format = surface_formats.front();
    for (const auto& surface_format : surface_formats) {
        if (surface_format.format == VK_FORMAT_R8G8B8A8_UNORM ||
            surface_format.format == VK_FORMAT_B8G8R8A8_UNORM) {
            chosen_format = surface_format;
            break;
        }
    }

    uint32_t present_mode_count = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR_(physical_device_, surface_, &present_mode_count, nullptr);
    std::vector<VkPresentModeKHR> present_modes(present_mode_count);
    if (present_mode_count > 0) {
        vkGetPhysicalDeviceSurfacePresentModesKHR_(
            physical_device_, surface_, &present_mode_count, present_modes.data());
    }

    VkPresentModeKHR chosen_present_mode = VK_PRESENT_MODE_FIFO_KHR;
    for (const auto& present_mode : present_modes) {
        if (present_mode == VK_PRESENT_MODE_MAILBOX_KHR) {
            chosen_present_mode = present_mode;
            break;
        }
    }

    VkExtent2D extent{};
    if (surface_capabilities.currentExtent.width != std::numeric_limits<uint32_t>::max()) {
        extent = surface_capabilities.currentExtent;
    } else {
        extent.width = std::clamp(width,
                                  surface_capabilities.minImageExtent.width,
                                  surface_capabilities.maxImageExtent.width);
        extent.height = std::clamp(height,
                                   surface_capabilities.minImageExtent.height,
                                   surface_capabilities.maxImageExtent.height);
    }

    uint32_t image_count = surface_capabilities.minImageCount + 1;
    if (surface_capabilities.maxImageCount > 0 && image_count > surface_capabilities.maxImageCount) {
        image_count = surface_capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    create_info.surface = surface_;
    create_info.minImageCount = image_count;
    create_info.imageFormat = chosen_format.format;
    create_info.imageColorSpace = chosen_format.colorSpace;
    create_info.imageExtent = extent;
    create_info.imageArrayLayers = 1;
    create_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    create_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    create_info.preTransform = surface_capabilities.currentTransform;
    create_info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    create_info.presentMode = chosen_present_mode;
    create_info.clipped = VK_TRUE;
    create_info.oldSwapchain = VK_NULL_HANDLE;

    const VkResult swapchain_result = vkCreateSwapchainKHR_(device_, &create_info, nullptr, &swapchain_);
    if (swapchain_result != VK_SUCCESS) {
        swapchain_ = VK_NULL_HANDLE;
        SetError("vkCreateSwapchainKHR failed: " + VkResultToString(swapchain_result));
        return false;
    }

    swapchain_image_format_ = chosen_format.format;
    swapchain_extent_ = extent;

    uint32_t swapchain_image_count = 0;
    vkGetSwapchainImagesKHR_(device_, swapchain_, &swapchain_image_count, nullptr);
    swapchain_images_.resize(swapchain_image_count);
    vkGetSwapchainImagesKHR_(
        device_, swapchain_, &swapchain_image_count, swapchain_images_.data());

    swapchain_image_views_.reserve(swapchain_images_.size());
    for (const auto& image : swapchain_images_) {
        VkImageViewCreateInfo image_view_info{};
        image_view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        image_view_info.image = image;
        image_view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
        image_view_info.format = swapchain_image_format_;
        image_view_info.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        image_view_info.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        image_view_info.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        image_view_info.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
        image_view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        image_view_info.subresourceRange.baseMipLevel = 0;
        image_view_info.subresourceRange.levelCount = 1;
        image_view_info.subresourceRange.baseArrayLayer = 0;
        image_view_info.subresourceRange.layerCount = 1;

        VkImageView image_view = VK_NULL_HANDLE;
        const VkResult image_view_result =
            vkCreateImageView_(device_, &image_view_info, nullptr, &image_view);
        if (image_view_result != VK_SUCCESS) {
            SetError("vkCreateImageView failed: " + VkResultToString(image_view_result));
            return false;
        }
        swapchain_image_views_.push_back(image_view);
    }

    return CreateRenderPass() &&
        CreateFramebuffers() &&
        CreateCommandPoolAndBuffers() &&
        CreateSyncObjects();
}

void FusionXVulkanRenderer::DestroySwapchain() {
    if (device_ == VK_NULL_HANDLE) {
        return;
    }

    if (vkDeviceWaitIdle_ != nullptr) {
        vkDeviceWaitIdle_(device_);
    }

    if (render_fence_ != VK_NULL_HANDLE && vkDestroyFence_ != nullptr) {
        vkDestroyFence_(device_, render_fence_, nullptr);
        render_fence_ = VK_NULL_HANDLE;
    }
    if (image_available_semaphore_ != VK_NULL_HANDLE && vkDestroySemaphore_ != nullptr) {
        vkDestroySemaphore_(device_, image_available_semaphore_, nullptr);
        image_available_semaphore_ = VK_NULL_HANDLE;
    }
    if (render_finished_semaphore_ != VK_NULL_HANDLE && vkDestroySemaphore_ != nullptr) {
        vkDestroySemaphore_(device_, render_finished_semaphore_, nullptr);
        render_finished_semaphore_ = VK_NULL_HANDLE;
    }

    if (command_pool_ != VK_NULL_HANDLE && vkDestroyCommandPool_ != nullptr) {
        vkDestroyCommandPool_(device_, command_pool_, nullptr);
        command_pool_ = VK_NULL_HANDLE;
    }
    command_buffers_.clear();

    for (auto framebuffer : framebuffers_) {
        if (framebuffer != VK_NULL_HANDLE && vkDestroyFramebuffer_ != nullptr) {
            vkDestroyFramebuffer_(device_, framebuffer, nullptr);
        }
    }
    framebuffers_.clear();

    if (render_pass_ != VK_NULL_HANDLE && vkDestroyRenderPass_ != nullptr) {
        vkDestroyRenderPass_(device_, render_pass_, nullptr);
        render_pass_ = VK_NULL_HANDLE;
    }

    for (auto image_view : swapchain_image_views_) {
        if (image_view != VK_NULL_HANDLE && vkDestroyImageView_ != nullptr) {
            vkDestroyImageView_(device_, image_view, nullptr);
        }
    }
    swapchain_image_views_.clear();
    swapchain_images_.clear();

    if (swapchain_ != VK_NULL_HANDLE && vkDestroySwapchainKHR_ != nullptr) {
        vkDestroySwapchainKHR_(device_, swapchain_, nullptr);
        swapchain_ = VK_NULL_HANDLE;
    }
}

void FusionXVulkanRenderer::DestroyDeviceObjects() {
    DestroySwapchain();

    if (device_ != VK_NULL_HANDLE && vkDestroyDevice_ != nullptr) {
        vkDestroyDevice_(device_, nullptr);
        device_ = VK_NULL_HANDLE;
    }
    graphics_queue_ = VK_NULL_HANDLE;
    physical_device_ = VK_NULL_HANDLE;
}

void FusionXVulkanRenderer::DestroyInstanceObjects() {
    if (surface_ != VK_NULL_HANDLE && vkDestroySurfaceKHR_ != nullptr && instance_ != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR_(instance_, surface_, nullptr);
        surface_ = VK_NULL_HANDLE;
    }
    if (instance_ != VK_NULL_HANDLE && vkDestroyInstance_ != nullptr) {
        vkDestroyInstance_(instance_, nullptr);
        instance_ = VK_NULL_HANDLE;
    }
}

bool FusionXVulkanRenderer::PickPhysicalDevice() {
    uint32_t device_count = 0;
    const VkResult enumerate_result = vkEnumeratePhysicalDevices_(instance_, &device_count, nullptr);
    if (enumerate_result != VK_SUCCESS || device_count == 0) {
        SetError("No Vulkan physical devices available.");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(device_count);
    vkEnumeratePhysicalDevices_(instance_, &device_count, devices.data());

    for (const auto& device : devices) {
        uint32_t queue_family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties_(device, &queue_family_count, nullptr);
        if (queue_family_count == 0) {
            continue;
        }
        std::vector<VkQueueFamilyProperties> queue_family_properties(queue_family_count);
        vkGetPhysicalDeviceQueueFamilyProperties_(
            device, &queue_family_count, queue_family_properties.data());

        for (uint32_t queue_index = 0; queue_index < queue_family_count; ++queue_index) {
            VkBool32 supports_present = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR_(
                device, queue_index, surface_, &supports_present);
            if ((queue_family_properties[queue_index].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 &&
                supports_present == VK_TRUE) {
                physical_device_ = device;
                graphics_queue_family_index_ = queue_index;
                return true;
            }
        }
    }

    SetError("No Vulkan queue family supports both graphics and present.");
    return false;
}

bool FusionXVulkanRenderer::LoadInstanceFunctions() {
    vkDestroyInstance_ =
        LoadInstanceSymbol<PFN_vkDestroyInstance>(vkGetInstanceProcAddr_, instance_, "vkDestroyInstance");
    vkCreateAndroidSurfaceKHR_ = LoadInstanceSymbol<PFN_vkCreateAndroidSurfaceKHR>(
        vkGetInstanceProcAddr_, instance_, "vkCreateAndroidSurfaceKHR");
    vkDestroySurfaceKHR_ = LoadInstanceSymbol<PFN_vkDestroySurfaceKHR>(
        vkGetInstanceProcAddr_, instance_, "vkDestroySurfaceKHR");
    vkEnumeratePhysicalDevices_ = LoadInstanceSymbol<PFN_vkEnumeratePhysicalDevices>(
        vkGetInstanceProcAddr_, instance_, "vkEnumeratePhysicalDevices");
    vkGetPhysicalDeviceQueueFamilyProperties_ =
        LoadInstanceSymbol<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
            vkGetInstanceProcAddr_, instance_, "vkGetPhysicalDeviceQueueFamilyProperties");
    vkGetPhysicalDeviceSurfaceSupportKHR_ = LoadInstanceSymbol<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
        vkGetInstanceProcAddr_, instance_, "vkGetPhysicalDeviceSurfaceSupportKHR");
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR_ =
        LoadInstanceSymbol<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(
            vkGetInstanceProcAddr_, instance_, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    vkGetPhysicalDeviceSurfaceFormatsKHR_ = LoadInstanceSymbol<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
        vkGetInstanceProcAddr_, instance_, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    vkGetPhysicalDeviceSurfacePresentModesKHR_ =
        LoadInstanceSymbol<PFN_vkGetPhysicalDeviceSurfacePresentModesKHR>(
            vkGetInstanceProcAddr_, instance_, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    vkCreateDevice_ =
        LoadInstanceSymbol<PFN_vkCreateDevice>(vkGetInstanceProcAddr_, instance_, "vkCreateDevice");
    vkGetDeviceProcAddr_ = LoadInstanceSymbol<PFN_vkGetDeviceProcAddr>(
        vkGetInstanceProcAddr_, instance_, "vkGetDeviceProcAddr");

    const bool ready =
        vkDestroyInstance_ != nullptr &&
        vkCreateAndroidSurfaceKHR_ != nullptr &&
        vkDestroySurfaceKHR_ != nullptr &&
        vkEnumeratePhysicalDevices_ != nullptr &&
        vkGetPhysicalDeviceQueueFamilyProperties_ != nullptr &&
        vkGetPhysicalDeviceSurfaceSupportKHR_ != nullptr &&
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR_ != nullptr &&
        vkGetPhysicalDeviceSurfaceFormatsKHR_ != nullptr &&
        vkGetPhysicalDeviceSurfacePresentModesKHR_ != nullptr &&
        vkCreateDevice_ != nullptr &&
        vkGetDeviceProcAddr_ != nullptr;

    if (!ready) {
        SetError("Required Vulkan instance functions are unavailable.");
    }
    return ready;
}

bool FusionXVulkanRenderer::LoadDeviceFunctions() {
    vkDestroyDevice_ =
        LoadDeviceSymbol<PFN_vkDestroyDevice>(vkGetDeviceProcAddr_, device_, "vkDestroyDevice");
    vkGetDeviceQueue_ =
        LoadDeviceSymbol<PFN_vkGetDeviceQueue>(vkGetDeviceProcAddr_, device_, "vkGetDeviceQueue");
    vkCreateSwapchainKHR_ = LoadDeviceSymbol<PFN_vkCreateSwapchainKHR>(
        vkGetDeviceProcAddr_, device_, "vkCreateSwapchainKHR");
    vkDestroySwapchainKHR_ = LoadDeviceSymbol<PFN_vkDestroySwapchainKHR>(
        vkGetDeviceProcAddr_, device_, "vkDestroySwapchainKHR");
    vkGetSwapchainImagesKHR_ = LoadDeviceSymbol<PFN_vkGetSwapchainImagesKHR>(
        vkGetDeviceProcAddr_, device_, "vkGetSwapchainImagesKHR");
    vkCreateImageView_ = LoadDeviceSymbol<PFN_vkCreateImageView>(
        vkGetDeviceProcAddr_, device_, "vkCreateImageView");
    vkDestroyImageView_ = LoadDeviceSymbol<PFN_vkDestroyImageView>(
        vkGetDeviceProcAddr_, device_, "vkDestroyImageView");
    vkCreateRenderPass_ = LoadDeviceSymbol<PFN_vkCreateRenderPass>(
        vkGetDeviceProcAddr_, device_, "vkCreateRenderPass");
    vkDestroyRenderPass_ = LoadDeviceSymbol<PFN_vkDestroyRenderPass>(
        vkGetDeviceProcAddr_, device_, "vkDestroyRenderPass");
    vkCreateFramebuffer_ = LoadDeviceSymbol<PFN_vkCreateFramebuffer>(
        vkGetDeviceProcAddr_, device_, "vkCreateFramebuffer");
    vkDestroyFramebuffer_ = LoadDeviceSymbol<PFN_vkDestroyFramebuffer>(
        vkGetDeviceProcAddr_, device_, "vkDestroyFramebuffer");
    vkCreateCommandPool_ = LoadDeviceSymbol<PFN_vkCreateCommandPool>(
        vkGetDeviceProcAddr_, device_, "vkCreateCommandPool");
    vkDestroyCommandPool_ = LoadDeviceSymbol<PFN_vkDestroyCommandPool>(
        vkGetDeviceProcAddr_, device_, "vkDestroyCommandPool");
    vkAllocateCommandBuffers_ = LoadDeviceSymbol<PFN_vkAllocateCommandBuffers>(
        vkGetDeviceProcAddr_, device_, "vkAllocateCommandBuffers");
    vkFreeCommandBuffers_ = LoadDeviceSymbol<PFN_vkFreeCommandBuffers>(
        vkGetDeviceProcAddr_, device_, "vkFreeCommandBuffers");
    vkBeginCommandBuffer_ = LoadDeviceSymbol<PFN_vkBeginCommandBuffer>(
        vkGetDeviceProcAddr_, device_, "vkBeginCommandBuffer");
    vkEndCommandBuffer_ = LoadDeviceSymbol<PFN_vkEndCommandBuffer>(
        vkGetDeviceProcAddr_, device_, "vkEndCommandBuffer");
    vkResetCommandBuffer_ = LoadDeviceSymbol<PFN_vkResetCommandBuffer>(
        vkGetDeviceProcAddr_, device_, "vkResetCommandBuffer");
    vkQueueSubmit_ = LoadDeviceSymbol<PFN_vkQueueSubmit>(
        vkGetDeviceProcAddr_, device_, "vkQueueSubmit");
    vkQueuePresentKHR_ = LoadDeviceSymbol<PFN_vkQueuePresentKHR>(
        vkGetDeviceProcAddr_, device_, "vkQueuePresentKHR");
    vkDeviceWaitIdle_ = LoadDeviceSymbol<PFN_vkDeviceWaitIdle>(
        vkGetDeviceProcAddr_, device_, "vkDeviceWaitIdle");
    vkAcquireNextImageKHR_ = LoadDeviceSymbol<PFN_vkAcquireNextImageKHR>(
        vkGetDeviceProcAddr_, device_, "vkAcquireNextImageKHR");
    vkCreateSemaphore_ = LoadDeviceSymbol<PFN_vkCreateSemaphore>(
        vkGetDeviceProcAddr_, device_, "vkCreateSemaphore");
    vkDestroySemaphore_ = LoadDeviceSymbol<PFN_vkDestroySemaphore>(
        vkGetDeviceProcAddr_, device_, "vkDestroySemaphore");
    vkCreateFence_ = LoadDeviceSymbol<PFN_vkCreateFence>(
        vkGetDeviceProcAddr_, device_, "vkCreateFence");
    vkDestroyFence_ = LoadDeviceSymbol<PFN_vkDestroyFence>(
        vkGetDeviceProcAddr_, device_, "vkDestroyFence");
    vkWaitForFences_ = LoadDeviceSymbol<PFN_vkWaitForFences>(
        vkGetDeviceProcAddr_, device_, "vkWaitForFences");
    vkResetFences_ = LoadDeviceSymbol<PFN_vkResetFences>(
        vkGetDeviceProcAddr_, device_, "vkResetFences");
    vkCmdBeginRenderPass_ = LoadDeviceSymbol<PFN_vkCmdBeginRenderPass>(
        vkGetDeviceProcAddr_, device_, "vkCmdBeginRenderPass");
    vkCmdEndRenderPass_ = LoadDeviceSymbol<PFN_vkCmdEndRenderPass>(
        vkGetDeviceProcAddr_, device_, "vkCmdEndRenderPass");

    const bool ready =
        vkDestroyDevice_ != nullptr &&
        vkGetDeviceQueue_ != nullptr &&
        vkCreateSwapchainKHR_ != nullptr &&
        vkDestroySwapchainKHR_ != nullptr &&
        vkGetSwapchainImagesKHR_ != nullptr &&
        vkCreateImageView_ != nullptr &&
        vkDestroyImageView_ != nullptr &&
        vkCreateRenderPass_ != nullptr &&
        vkDestroyRenderPass_ != nullptr &&
        vkCreateFramebuffer_ != nullptr &&
        vkDestroyFramebuffer_ != nullptr &&
        vkCreateCommandPool_ != nullptr &&
        vkDestroyCommandPool_ != nullptr &&
        vkAllocateCommandBuffers_ != nullptr &&
        vkFreeCommandBuffers_ != nullptr &&
        vkBeginCommandBuffer_ != nullptr &&
        vkEndCommandBuffer_ != nullptr &&
        vkResetCommandBuffer_ != nullptr &&
        vkQueueSubmit_ != nullptr &&
        vkQueuePresentKHR_ != nullptr &&
        vkDeviceWaitIdle_ != nullptr &&
        vkAcquireNextImageKHR_ != nullptr &&
        vkCreateSemaphore_ != nullptr &&
        vkDestroySemaphore_ != nullptr &&
        vkCreateFence_ != nullptr &&
        vkDestroyFence_ != nullptr &&
        vkWaitForFences_ != nullptr &&
        vkResetFences_ != nullptr &&
        vkCmdBeginRenderPass_ != nullptr &&
        vkCmdEndRenderPass_ != nullptr;

    if (!ready) {
        SetError("Required Vulkan device functions are unavailable.");
    }
    return ready;
}

bool FusionXVulkanRenderer::CreateRenderPass() {
    VkAttachmentDescription color_attachment{};
    color_attachment.format = swapchain_image_format_;
    color_attachment.samples = VK_SAMPLE_COUNT_1_BIT;
    color_attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    color_attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    color_attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    color_attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    color_attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    color_attachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    VkAttachmentReference color_attachment_ref{};
    color_attachment_ref.attachment = 0;
    color_attachment_ref.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color_attachment_ref;

    VkSubpassDependency dependency{};
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo render_pass_info{};
    render_pass_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    render_pass_info.attachmentCount = 1;
    render_pass_info.pAttachments = &color_attachment;
    render_pass_info.subpassCount = 1;
    render_pass_info.pSubpasses = &subpass;
    render_pass_info.dependencyCount = 1;
    render_pass_info.pDependencies = &dependency;

    const VkResult result = vkCreateRenderPass_(device_, &render_pass_info, nullptr, &render_pass_);
    if (result != VK_SUCCESS) {
        SetError("vkCreateRenderPass failed: " + VkResultToString(result));
        return false;
    }
    return true;
}

bool FusionXVulkanRenderer::CreateFramebuffers() {
    framebuffers_.reserve(swapchain_image_views_.size());
    for (const auto& image_view : swapchain_image_views_) {
        VkFramebufferCreateInfo framebuffer_info{};
        framebuffer_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebuffer_info.renderPass = render_pass_;
        framebuffer_info.attachmentCount = 1;
        framebuffer_info.pAttachments = &image_view;
        framebuffer_info.width = swapchain_extent_.width;
        framebuffer_info.height = swapchain_extent_.height;
        framebuffer_info.layers = 1;

        VkFramebuffer framebuffer = VK_NULL_HANDLE;
        const VkResult result =
            vkCreateFramebuffer_(device_, &framebuffer_info, nullptr, &framebuffer);
        if (result != VK_SUCCESS) {
            SetError("vkCreateFramebuffer failed: " + VkResultToString(result));
            return false;
        }
        framebuffers_.push_back(framebuffer);
    }
    return true;
}

bool FusionXVulkanRenderer::CreateCommandPoolAndBuffers() {
    VkCommandPoolCreateInfo command_pool_info{};
    command_pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    command_pool_info.queueFamilyIndex = graphics_queue_family_index_;
    command_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

    const VkResult pool_result =
        vkCreateCommandPool_(device_, &command_pool_info, nullptr, &command_pool_);
    if (pool_result != VK_SUCCESS) {
        SetError("vkCreateCommandPool failed: " + VkResultToString(pool_result));
        return false;
    }

    command_buffers_.resize(framebuffers_.size(), VK_NULL_HANDLE);

    VkCommandBufferAllocateInfo alloc_info{};
    alloc_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.commandPool = command_pool_;
    alloc_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandBufferCount = static_cast<uint32_t>(command_buffers_.size());

    const VkResult alloc_result =
        vkAllocateCommandBuffers_(device_, &alloc_info, command_buffers_.data());
    if (alloc_result != VK_SUCCESS) {
        SetError("vkAllocateCommandBuffers failed: " + VkResultToString(alloc_result));
        return false;
    }
    return true;
}

bool FusionXVulkanRenderer::CreateSyncObjects() {
    VkSemaphoreCreateInfo semaphore_info{};
    semaphore_info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fence_info{};
    fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fence_info.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    if (vkCreateSemaphore_(device_, &semaphore_info, nullptr, &image_available_semaphore_) != VK_SUCCESS ||
        vkCreateSemaphore_(device_, &semaphore_info, nullptr, &render_finished_semaphore_) != VK_SUCCESS ||
        vkCreateFence_(device_, &fence_info, nullptr, &render_fence_) != VK_SUCCESS) {
        SetError("Failed to create Vulkan sync objects.");
        return false;
    }
    return true;
}

bool FusionXVulkanRenderer::RecordCommandBuffer(uint32_t image_index, const VkClearValue& clear_value) {
    const VkCommandBuffer command_buffer = command_buffers_[image_index];
    vkResetCommandBuffer_(command_buffer, 0);

    VkCommandBufferBeginInfo begin_info{};
    begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;

    const VkResult begin_result = vkBeginCommandBuffer_(command_buffer, &begin_info);
    if (begin_result != VK_SUCCESS) {
        SetError("vkBeginCommandBuffer failed: " + VkResultToString(begin_result));
        return false;
    }

    VkRenderPassBeginInfo render_pass_info{};
    render_pass_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    render_pass_info.renderPass = render_pass_;
    render_pass_info.framebuffer = framebuffers_[image_index];
    render_pass_info.renderArea.offset = {0, 0};
    render_pass_info.renderArea.extent = swapchain_extent_;
    render_pass_info.clearValueCount = 1;
    render_pass_info.pClearValues = &clear_value;

    vkCmdBeginRenderPass_(command_buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdEndRenderPass_(command_buffer);

    const VkResult end_result = vkEndCommandBuffer_(command_buffer);
    if (end_result != VK_SUCCESS) {
        SetError("vkEndCommandBuffer failed: " + VkResultToString(end_result));
        return false;
    }

    return true;
}

bool FusionXVulkanRenderer::RecreateSwapchain(uint32_t width, uint32_t height) {
    if (device_ != VK_NULL_HANDLE) {
        vkDeviceWaitIdle_(device_);
    }
    DestroySwapchain();
    return CreateSwapchain(width, height);
}

void FusionXVulkanRenderer::SetError(const std::string& message) {
    last_error_ = message;
}

std::string FusionXVulkanRenderer::VkResultToString(VkResult result) const {
    std::ostringstream stream;
    stream << static_cast<int>(result);
    return stream.str();
}
