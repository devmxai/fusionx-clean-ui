#include "FusionXVulkanBootstrap.h"

#include <dlfcn.h>
#include <sstream>
#include <vector>

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#ifndef VK_KHR_ANDROID_SURFACE_EXTENSION_NAME
#define VK_KHR_ANDROID_SURFACE_EXTENSION_NAME "VK_KHR_android_surface"
#endif

namespace {

std::string BuildStatusString(const FusionXVulkanCapabilities& capabilities) {
    std::ostringstream stream;
    stream << "loader=" << (capabilities.loader_present ? "yes" : "no")
           << ",instance=" << (capabilities.create_instance_supported ? "yes" : "no")
           << ",androidSurface=" << (capabilities.android_surface_supported ? "yes" : "no")
           << ",api=" << VK_API_VERSION_MAJOR(capabilities.api_version)
           << "." << VK_API_VERSION_MINOR(capabilities.api_version)
           << "." << VK_API_VERSION_PATCH(capabilities.api_version)
           << ",physicalDevices=" << capabilities.physical_device_count;
    return stream.str();
}

}  // namespace

FusionXVulkanCapabilities FusionXVulkanBootstrap::queryCapabilities() const {
    FusionXVulkanCapabilities capabilities;

    void* loader_handle = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (loader_handle == nullptr) {
        capabilities.status = "libvulkan.so not found";
        return capabilities;
    }
    capabilities.loader_present = true;

    const auto vk_get_instance_proc_addr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        dlsym(loader_handle, "vkGetInstanceProcAddr"));
    if (vk_get_instance_proc_addr == nullptr) {
        capabilities.status = "vkGetInstanceProcAddr unavailable";
        dlclose(loader_handle);
        return capabilities;
    }

    uint32_t instance_version = VK_API_VERSION_1_0;
#if defined(VK_VERSION_1_1)
    const auto enumerate_instance_version =
        reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
            vk_get_instance_proc_addr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
    if (enumerate_instance_version != nullptr) {
        if (enumerate_instance_version(&instance_version) == VK_SUCCESS) {
            capabilities.loader_present = true;
        }
    }
#else
    capabilities.loader_present = true;
#endif
    capabilities.api_version = instance_version;

    const auto enumerate_instance_extensions =
        reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(
            vk_get_instance_proc_addr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
    if (enumerate_instance_extensions == nullptr) {
        capabilities.status = "vkEnumerateInstanceExtensionProperties unavailable";
        dlclose(loader_handle);
        return capabilities;
    }

    uint32_t extension_count = 0;
    if (enumerate_instance_extensions(nullptr, &extension_count, nullptr) != VK_SUCCESS) {
        capabilities.status = "vkEnumerateInstanceExtensionProperties failed";
        dlclose(loader_handle);
        return capabilities;
    }

    std::vector<VkExtensionProperties> extensions(extension_count);
    if (extension_count > 0 &&
        enumerate_instance_extensions(nullptr, &extension_count, extensions.data()) !=
            VK_SUCCESS) {
        capabilities.status = "Failed to read Vulkan instance extensions";
        dlclose(loader_handle);
        return capabilities;
    }

    for (const auto& extension : extensions) {
        if (std::string(extension.extensionName) == VK_KHR_ANDROID_SURFACE_EXTENSION_NAME) {
            capabilities.android_surface_supported = true;
            break;
        }
    }

    const char* required_extensions[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
    };

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "FusionX";
    app_info.applicationVersion = VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "FusionX Vulkan Bootstrap";
    app_info.engineVersion = VK_MAKE_VERSION(0, 1, 0);
    app_info.apiVersion = instance_version;

    VkInstanceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = 2;
    create_info.ppEnabledExtensionNames = required_extensions;

    const auto create_instance =
        reinterpret_cast<PFN_vkCreateInstance>(
            vk_get_instance_proc_addr(VK_NULL_HANDLE, "vkCreateInstance"));
    if (create_instance == nullptr) {
        capabilities.status = "vkCreateInstance unavailable";
        dlclose(loader_handle);
        return capabilities;
    }

    VkInstance instance = VK_NULL_HANDLE;
    const VkResult instance_result = create_instance(&create_info, nullptr, &instance);
    if (instance_result != VK_SUCCESS) {
        capabilities.status = "vkCreateInstance failed";
        dlclose(loader_handle);
        return capabilities;
    }

    capabilities.create_instance_supported = true;

    const auto enumerate_physical_devices =
        reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(
            vk_get_instance_proc_addr(instance, "vkEnumeratePhysicalDevices"));
    if (enumerate_physical_devices != nullptr) {
        uint32_t physical_device_count = 0;
        if (enumerate_physical_devices(instance, &physical_device_count, nullptr) == VK_SUCCESS) {
            capabilities.physical_device_count = physical_device_count;
        }
    }

    const auto destroy_instance =
        reinterpret_cast<PFN_vkDestroyInstance>(
            vk_get_instance_proc_addr(instance, "vkDestroyInstance"));
    if (destroy_instance != nullptr) {
        destroy_instance(instance, nullptr);
    }

    capabilities.status = BuildStatusString(capabilities);
    dlclose(loader_handle);
    return capabilities;
}
