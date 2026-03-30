package com.fusionx.fusionx_clean_ui.engine

import io.flutter.view.TextureRegistry

class FusionXPreviewCoordinator(
    textureRegistry: TextureRegistry,
    width: Int,
    height: Int,
    private val events: FusionXEventDispatcher,
) {
    private val previewRenderTarget = FusionXRenderTarget(textureRegistry, width, height)

    fun playbackTarget(): FusionXRenderTarget = previewRenderTarget

    fun scrubTarget(): FusionXRenderTarget = previewRenderTarget

    fun activeTextureId(): Long = previewRenderTarget.textureId

    fun activatePlayback(emitEvent: Boolean = true) {
        if (emitEvent) {
            events.emit("previewTargetChanged", buildPreviewPayload())
        }
    }

    fun activateScrub(emitEvent: Boolean = true) {
        if (emitEvent) {
            events.emit("previewTargetChanged", buildPreviewPayload())
        }
    }

    fun release() {
        previewRenderTarget.release()
    }

    private fun buildPreviewPayload(): Map<String, Any?> {
        return mapOf(
            "textureId" to previewRenderTarget.textureId,
            "lane" to "single_surface",
        )
    }
}
