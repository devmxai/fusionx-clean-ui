package com.fusionx.fusionx_clean_ui.engine

class FusionXVulkanPreviewSession(
    private val renderTarget: FusionXRenderTarget,
    private val bridge: FusionXVulkanBridge,
    private val events: FusionXEventDispatcher,
) {
    private var rendererHandle: Long = 0L
    private var attached = false

    fun start(): Boolean {
        val capabilities = bridge.queryCapabilities()
        if (!capabilities.runtimeAvailable) {
            events.emit(
                "error",
                mapOf("message" to "Vulkan runtime is unavailable on this Android device."),
            )
            return false
        }

        rendererHandle = bridge.createRenderer()
        if (rendererHandle == 0L) {
            events.emit(
                "error",
                mapOf("message" to "Unable to create the Vulkan preview renderer."),
            )
            return false
        }

        attached = bridge.attachSurface(
            rendererHandle = rendererHandle,
            surface = renderTarget.surface,
            width = renderTarget.width,
            height = renderTarget.height,
        )
        if (!attached) {
            events.emit(
                "error",
                mapOf("message" to "Unable to attach the preview Surface to the Vulkan renderer."),
            )
            release()
            return false
        }

        renderIdleFrame()
        return true
    }

    fun renderIdleFrame() {
        if (!attached || rendererHandle == 0L) {
            return
        }
        if (!bridge.renderIdleFrame(
                rendererHandle = rendererHandle,
                red = 0.035f,
                green = 0.04f,
                blue = 0.05f,
                alpha = 1.0f,
            )
        ) {
            events.emit(
                "error",
                mapOf("message" to "Vulkan preview renderer failed to draw an idle frame."),
            )
        }
    }

    fun release() {
        if (rendererHandle != 0L) {
            bridge.detachSurface(rendererHandle)
            bridge.destroyRenderer(rendererHandle)
            rendererHandle = 0L
        }
        attached = false
    }
}
