cmake_minimum_required(VERSION 3.18.1)

project(fusionx_vulkan LANGUAGES CXX)

add_library(
    fusionx_vulkan
    SHARED
    fusionx_vulkan/FusionXVulkanBootstrap.cpp
    fusionx_vulkan/FusionXVulkanRenderer.cpp
    fusionx_vulkan/FusionXVulkanJni.cpp
)

target_compile_features(fusionx_vulkan PRIVATE cxx_std_20)

target_include_directories(
    fusionx_vulkan
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/fusionx_vulkan
)

target_link_libraries(
    fusionx_vulkan
    android
    log
    dl
)
