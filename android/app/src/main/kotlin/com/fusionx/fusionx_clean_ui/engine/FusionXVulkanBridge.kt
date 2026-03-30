package com.fusionx.fusionx_clean_ui.engine

import android.view.Surface

class FusionXVulkanBridge {
    fun queryCapabilities(): FusionXVulkanCapabilities {
        val apiVersion = nativeGetVulkanApiVersion()
        return FusionXVulkanCapabilities(
            runtimeAvailable = nativeHasVulkanRuntime(),
            physicalDeviceCount = nativeGetPhysicalDeviceCount(),
            apiVersion = apiVersion,
            status = nativeDescribeBootstrapStatus(),
        )
    }

    fun createRenderer(): Long = nativeCreateRenderer()

    fun destroyRenderer(rendererHandle: Long) {
        nativeDestroyRenderer(rendererHandle)
    }

    fun attachSurface(
        rendererHandle: Long,
        surface: Surface,
        width: Int,
        height: Int,
    ): Boolean {
        return nativeAttachSurface(rendererHandle, surface, width, height)
    }

    fun detachSurface(rendererHandle: Long) {
        nativeDetachSurface(rendererHandle)
    }

    fun renderIdleFrame(
        rendererHandle: Long,
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float,
    ): Boolean {
        return nativeRenderIdleFrame(rendererHandle, red, green, blue, alpha)
    }

    private external fun nativeHasVulkanRuntime(): Boolean
    private external fun nativeGetVulkanApiVersion(): Int
    private external fun nativeGetPhysicalDeviceCount(): Int
    private external fun nativeDescribeBootstrapStatus(): String
    private external fun nativeCreateRenderer(): Long
    private external fun nativeDestroyRenderer(rendererHandle: Long)
    private external fun nativeAttachSurface(
        rendererHandle: Long,
        surface: Surface,
        width: Int,
        height: Int,
    ): Boolean
    private external fun nativeDetachSurface(rendererHandle: Long)
    private external fun nativeRenderIdleFrame(
        rendererHandle: Long,
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float,
    ): Boolean

    companion object {
        init {
            System.loadLibrary("fusionx_vulkan")
        }
    }
}

data class FusionXVulkanCapabilities(
    val runtimeAvailable: Boolean,
    val physicalDeviceCount: Int,
    val apiVersion: Int,
    val status: String,
) {
    val apiVersionString: String
        get() {
            val major = apiVersion shr 22
            val minor = (apiVersion shr 12) and 0x3ff
            val patch = apiVersion and 0xfff
            return "$major.$minor.$patch"
        }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "runtimeAvailable" to runtimeAvailable,
            "physicalDeviceCount" to physicalDeviceCount,
            "apiVersion" to apiVersion,
            "apiVersionString" to apiVersionString,
            "status" to status,
        )
    }
}
