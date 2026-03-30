#pragma once

#include <string>

struct FusionXVulkanCapabilities {
    bool loader_present = false;
    bool create_instance_supported = false;
    bool android_surface_supported = false;
    uint32_t api_version = 0;
    uint32_t physical_device_count = 0;
    std::string status;
};

class FusionXVulkanBootstrap {
public:
    FusionXVulkanCapabilities queryCapabilities() const;
};
