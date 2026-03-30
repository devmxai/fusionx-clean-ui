#include "FusionXVulkanBootstrap.h"
#include "FusionXVulkanRenderer.h"

#include <jni.h>

#include <memory>
#include <string>

namespace {

FusionXVulkanBootstrap& GetBootstrap() {
    static FusionXVulkanBootstrap bootstrap;
    return bootstrap;
}

std::string ToUtf8Status() {
    return GetBootstrap().queryCapabilities().status;
}

FusionXVulkanRenderer* FromHandle(jlong handle) {
    return reinterpret_cast<FusionXVulkanRenderer*>(handle);
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeHasVulkanRuntime(
    JNIEnv* env,
    jobject /* thiz */) {
    (void)env;
    const auto capabilities = GetBootstrap().queryCapabilities();
    return static_cast<jboolean>(
        capabilities.loader_present &&
        capabilities.create_instance_supported &&
        capabilities.android_surface_supported &&
        capabilities.physical_device_count > 0);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeGetVulkanApiVersion(
    JNIEnv* env,
    jobject /* thiz */) {
    (void)env;
    const auto capabilities = GetBootstrap().queryCapabilities();
    return static_cast<jint>(capabilities.api_version);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeGetPhysicalDeviceCount(
    JNIEnv* env,
    jobject /* thiz */) {
    (void)env;
    const auto capabilities = GetBootstrap().queryCapabilities();
    return static_cast<jint>(capabilities.physical_device_count);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeDescribeBootstrapStatus(
    JNIEnv* env,
    jobject /* thiz */) {
    return env->NewStringUTF(ToUtf8Status().c_str());
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeCreateRenderer(
    JNIEnv* env,
    jobject /* thiz */) {
    (void)env;
    auto* renderer = new FusionXVulkanRenderer();
    return reinterpret_cast<jlong>(renderer);
}

extern "C" JNIEXPORT void JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeDestroyRenderer(
    JNIEnv* env,
    jobject /* thiz */,
    jlong renderer_handle) {
    (void)env;
    delete FromHandle(renderer_handle);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeAttachSurface(
    JNIEnv* env,
    jobject /* thiz */,
    jlong renderer_handle,
    jobject surface,
    jint width,
    jint height) {
    auto* renderer = FromHandle(renderer_handle);
    if (renderer == nullptr) {
        return JNI_FALSE;
    }
    return renderer->AttachSurface(
               env,
               surface,
               static_cast<uint32_t>(width),
               static_cast<uint32_t>(height))
        ? JNI_TRUE
        : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeDetachSurface(
    JNIEnv* env,
    jobject /* thiz */,
    jlong renderer_handle) {
    (void)env;
    auto* renderer = FromHandle(renderer_handle);
    if (renderer != nullptr) {
        renderer->DetachSurface();
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_fusionx_fusionx_1clean_1ui_engine_FusionXVulkanBridge_nativeRenderIdleFrame(
    JNIEnv* env,
    jobject /* thiz */,
    jlong renderer_handle,
    jfloat red,
    jfloat green,
    jfloat blue,
    jfloat alpha) {
    (void)env;
    auto* renderer = FromHandle(renderer_handle);
    if (renderer == nullptr) {
        return JNI_FALSE;
    }
    return renderer->RenderClear(red, green, blue, alpha) ? JNI_TRUE : JNI_FALSE;
}
